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
