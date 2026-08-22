import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, decryptSecret, json } from "../_shared/identity.ts";

// THE SECONDARY PATH.
//
// The emailed code is the primary gate and settles almost everyone with no
// human involved. This exists for the person it failed — the mail never
// arrived, the code expired during a lecture, they burned five attempts on a
// typo. Those signups are flagged review_state = 'needs_review' by
// register-verify and surface through admin_list_stuck_registrations.
//
// An admin holding users:approve reviews the claim and, if they are satisfied
// the person is who they say, completes it here. The account is then created
// from the SAME staged payload the code path would have used — so a manually
// approved account is identical to a self-verified one in every respect except
// how the identity was established, which is recorded on the profile.
//
// Creating an auth user needs the admin API, which SQL cannot reach, so this
// cannot be an RPC. Rejection can and is (admin_reject_stuck_registration).

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY")!;

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

    // AUTHORISATION IS THE WHOLE POINT OF THIS FUNCTION. It creates a
    // fully-approved account while deliberately SKIPPING the mailbox proof, so
    // an unauthenticated or under-privileged caller reaching it would be a
    // straight bypass of everything the code flow exists to enforce.
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "Missing authorization." }, 401);

    const { data: authData, error: authErr } = await supabase.auth.getUser(jwt);
    if (authErr || !authData?.user) return json({ error: "Invalid or expired session." }, 401);
    const callerId = authData.user.id;

    // Asked AS THE CALLER, not as service_role. can_browse_users() reads
    // auth.uid(), which is NULL under the service-role client — so asking on
    // that client would always answer false and quietly reduce this to an
    // admin-roles-only check, locking out exactly the delegates the permission
    // tier exists to empower (someone granted users:approve with no admin
    // role). Fails CLOSED.
    const userClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const { data: allowed, error: permErr } = await userClient.rpc("can_browse_users");
    if (permErr || allowed !== true) {
      if (permErr) console.error("[register-admin-approve] permission check failed:", permErr.message);
      return json({ error: "You are not authorized to approve registrations." }, 403);
    }

    const { registrationId } = await req.json().catch(() => ({}));
    if (!registrationId) return json({ error: "registrationId is required." }, 400);

    const { data: row } = await supabase
      .from("pending_registrations").select("*")
      .eq("id", registrationId).is("consumed_at", null).maybeSingle();
    if (!row) return json({ error: "That registration is no longer pending." }, 404);

    const payload = row.payload ?? {};
    const { enc_password, ...metadata } = payload;

    let plainPassword: string;
    try {
      plainPassword = await decryptSecret(enc_password);
    } catch (_) {
      await supabase.from("pending_registrations").delete().eq("id", row.id);
      return json({
        error: "This registration's stored credentials are unreadable — ask the applicant to sign up again.",
      }, 400);
    }

    const { data: created, error: createErr } = await supabase.auth.admin.createUser({
      email: row.email,
      password: plainPassword,
      // Confirmed on an ADMIN's judgement rather than a code. Recorded as such
      // on the profile below, so this is never mistaken later for a mailbox
      // that actually proved itself.
      email_confirm: true,
      user_metadata: metadata,
    });

    if (createErr || !created?.user) {
      const msg = String(createErr?.message ?? "");
      if (/already/i.test(msg)) {
        await supabase.from("pending_registrations")
          .update({ consumed_at: new Date().toISOString(), review_state: "approved" })
          .eq("id", row.id);
        return json({ error: "An account already exists for that address." }, 409);
      }
      console.error("[register-admin-approve] createUser failed:", msg);
      return json({ error: "Could not create the account. Please try again." }, 500);
    }

    const userId = created.user.id;

    // identity_source is the audit trail that matters: 'admin_override' says
    // this mailbox was never proven and a named person vouched instead. If a
    // fake account is ever found, this is the column that says how it got in.
    await supabase.from("profiles").update({
      is_verified: true,
      identity_source: "admin_override",
    }).eq("id", userId);

    await supabase.from("pending_registrations").update({
      consumed_at: new Date().toISOString(),
      review_state: "approved",
      reviewed_by: callerId,
      reviewed_at: new Date().toISOString(),
    }).eq("id", row.id);

    // The applicant has been sitting on a failed code with no idea whether
    // anyone was looking. Tell them.
    await supabase.from("user_notifications").insert({
      user_id: userId,
      title: "Account approved",
      body: "An administrator confirmed your details. You can sign in to AFOS now.",
      category: "general",
    }).then(() => {}, () => {});

    return json({ ok: true, userId, email: row.email });
  } catch (err) {
    console.error("[register-admin-approve]", err);
    return json({ error: (err as Error).message ?? "Approval failed." }, 500);
  }
});
