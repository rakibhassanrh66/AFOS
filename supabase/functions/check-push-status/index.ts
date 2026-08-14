import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY")!
const ONESIGNAL_APP_ID = "2ae8d7b3-8999-4054-b185-2256b290993c"
const ONESIGNAL_REST_KEY = Deno.env.get("ONESIGNAL_REST_KEY")!

// Diagnostic mode (default): reports whether a given user actually has a
// live, subscribed OneSignal push subscription — this is the one thing
// send-notification's pushError field can't tell us, since OneSignal
// returns "success" for a send that targets zero *actually subscribed*
// devices. Targeting another user's id is super_admin-only (reveals
// another user's device state); targeting your own id is open to anyone.
//
// Reset mode (body.resetIdentity: true): deletes the OneSignal User
// record for the target external_id server-side. This exists because a
// device's local OneSignal identity can end up permanently orphaned —
// confirmed live: repeated rebinding across this app's testing history
// left several external_ids stuck with OneSignal's server rejecting any
// further login() with a 409 "Aliases claimed by another User", which no
// amount of client-side logout()/login() (even a full uninstall+reinstall)
// can fix, since the conflict is a server-side record, not local device
// state. Deleting the stale User frees the alias so the next login()
// succeeds and creates a fresh one. Self-service (same ownership rule as
// the read above) since any user's device can hit this, not just admins.
serve(async (req) => {
  const corsHeaders = { "Access-Control-Allow-Origin": "*", "Content-Type": "application/json" }
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })

  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE)
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "")
    if (!jwt) return new Response(JSON.stringify({ error: "Missing authorization." }), { status: 401, headers: corsHeaders })

    const { data: authData, error: authErr } = await supabase.auth.getUser(jwt)
    if (authErr || !authData?.user) {
      return new Response(JSON.stringify({ error: "Invalid or expired session." }), { status: 401, headers: corsHeaders })
    }
    const callerId = authData.user.id

    const body = await req.json().catch(() => ({}))
    const targetId = body.userId || callerId

    if (targetId !== callerId) {
      const { data: callerProfile } = await supabase.from("profiles").select("role").eq("id", callerId).maybeSingle()
      if (!callerProfile || callerProfile.role !== "super_admin") {
        return new Response(JSON.stringify({ error: "Can only target your own account (super_admin only for others)." }), { status: 403, headers: corsHeaders })
      }
    }

    if (body.resetIdentity === true) {
      const delRes = await fetch(
        `https://onesignal.com/api/v1/apps/${ONESIGNAL_APP_ID}/users/by/external_id/${targetId}`,
        { method: "DELETE", headers: { "Authorization": `Basic ${ONESIGNAL_REST_KEY}` } },
      )
      const delJson = await delRes.json().catch(() => ({}))
      return new Response(JSON.stringify({
        targetId, reset: true, oneSignalHttpStatus: delRes.status, oneSignalResponse: delJson,
      }), { headers: corsHeaders })
    }

    const osRes = await fetch(
      `https://onesignal.com/api/v1/apps/${ONESIGNAL_APP_ID}/users/by/external_id/${targetId}`,
      { headers: { "Authorization": `Basic ${ONESIGNAL_REST_KEY}` } },
    )
    const osJson = await osRes.json()

    return new Response(JSON.stringify({
      targetId,
      oneSignalHttpStatus: osRes.status,
      oneSignalResponse: osJson,
    }), { headers: corsHeaders })
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500, headers: corsHeaders })
  }
})
