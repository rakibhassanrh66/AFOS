// Who gets told when an account needs a human, and how they are told.
//
// EXTRACTED, not copied. register-verify already resolved this recipient set;
// register-review-request needs the identical one. A second copy would drift
// the first time one of them learned about a role the other did not, and the
// thing that drifts here is "who finds out an applicant is stuck" — a silent
// failure, because nobody is notified that nobody was notified.
//
// THE DIRECT-GRANT BRANCH IS THE LOAD-BEARING HALF. AFOS's delegation tier
// lives in user_permissions, not role_permissions, so resolving recipients by
// admin role alone omits precisely the people appointed to do this job and
// holding no admin role at all. That exact omission has now been the bug four
// times in this project (most recently can_browse_users, 20260816210000).

const ONESIGNAL_APP_ID = "2ae8d7b3-8999-4054-b185-2256b290993c";
const ONESIGNAL_REST_KEY = Deno.env.get("ONESIGNAL_REST_KEY");

/// Every account that may act on a pending registration: the admin roles, plus
/// anyone explicitly granted users:approve.
// deno-lint-ignore no-explicit-any
export async function resolveApprovers(
  supabase: any,
  excludeUserId?: string,
): Promise<string[]> {
  const recipients = new Set<string>();

  const { data: admins } = await supabase
    .from("profiles").select("id").in("role", ["super_admin", "admin", "dept_admin"]);
  for (const a of admins ?? []) recipients.add(a.id);

  const { data: perm } = await supabase
    .from("permissions").select("id").eq("resource", "users").eq("action", "approve").maybeSingle();
  if (perm) {
    const { data: grants } = await supabase
      .from("user_permissions").select("user_id").eq("permission_id", perm.id);
    for (const g of grants ?? []) recipients.add(g.user_id);
  }

  if (excludeUserId) recipients.delete(excludeUserId);
  return [...recipients];
}

/// Tells the approvers that a specific applicant is stuck.
///
/// WHY THIS EXISTS, AND THE REAL PERSON IT WAS WRITTEN FOR.
///
/// Flagging `review_state = 'needs_review'` and NOTIFYING somebody were two
/// separate steps, and only one of them was ever wired up. register-request
/// staged applicants on quota exhaustion and on provider rejection;
/// register-verify staged them on an expired code and on spent attempts. Not
/// one of those four paths told a human. The row simply appeared in a tab
/// nobody had a reason to open.
///
/// The failure that exposed it: a real applicant signed up on 2026-09-01 while
/// the sending domain was unverified. register-request staged her and notified
/// nobody. The app then showed her "Ask an administrator to approve me" — she
/// pressed it — and register-review-request's update was guarded on
/// `review_state = 'none'`, which she no longer was, so it matched zero rows,
/// returned ok, and notified nobody a SECOND time. The screen told her
/// administrators had been asked. They had not. She waited a day in a queue
/// no one knew had anything in it.
///
/// Two individually reasonable mechanisms composing into total silence is
/// exactly the failure mode this file's header warns about: "nobody is
/// notified that nobody was notified." So staging now goes through here.
///
/// NEVER THROWS — notifyApprovers swallows its own failures, and the
/// resolveApprovers lookup is wrapped for the same reason: this always runs
/// after the applicant's real work is done, and a notification problem must
/// not become an error they see.
// deno-lint-ignore no-explicit-any
export async function alertStuckApplicant(
  supabase: any,
  o: { email: string; name?: string | null; role?: string | null; reason: string },
): Promise<void> {
  try {
    const ids = await resolveApprovers(supabase);
    const who = o.name ? `${o.name} (${o.role ?? "student"})` : o.email;
    await notifyApprovers(supabase, ids, {
      // Deliberately does NOT say the person is verified. Nobody has proved
      // anything here; the approver is being asked to make a judgement, and
      // the review screen repeats that before they can act.
      title: "An applicant needs manual approval",
      body: `${who} signed up as ${o.email} but could not finish. ${o.reason}`,
      route: "/admin/users",
    });
  } catch (e) {
    console.error("[approvers] stuck-applicant alert failed (non-fatal):", e);
  }
}

/// Writes the in-app notification and fires the push.
///
/// NEVER THROWS. Every caller runs this after the user's real work has already
/// succeeded, so a failure here must not turn a completed registration — or a
/// successfully-raised hand — into an error the applicant sees.
// deno-lint-ignore no-explicit-any
export async function notifyApprovers(
  supabase: any,
  ids: string[],
  msg: { title: string; body: string; route?: string },
): Promise<void> {
  try {
    if (ids.length === 0) return;
    const route = msg.route ?? "/admin/users";

    await supabase.from("user_notifications").insert(
      ids.map((uid) => ({
        user_id: uid,
        title: msg.title,
        body: msg.body,
        category: "general",
        deep_link_route: route,
      })),
    );

    if (ONESIGNAL_REST_KEY) {
      await fetch("https://onesignal.com/api/v1/notifications", {
        method: "POST",
        headers: { "Content-Type": "application/json", "Authorization": `Basic ${ONESIGNAL_REST_KEY}` },
        body: JSON.stringify({
          app_id: ONESIGNAL_APP_ID,
          include_aliases: { external_id: ids },
          target_channel: "push",
          headings: { en: msg.title },
          contents: { en: msg.body },
          data: { deep_link_route: route },
        }),
      });
    }
  } catch (e) {
    console.error("[approvers] notification failed (non-fatal):", e);
  }
}
