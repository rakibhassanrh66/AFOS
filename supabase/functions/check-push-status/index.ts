import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY")!
const ONESIGNAL_APP_ID = "2ae8d7b3-8999-4054-b185-2256b290993c"
const ONESIGNAL_REST_KEY = Deno.env.get("ONESIGNAL_REST_KEY")!

// Diagnostic-only: reports whether a given user (defaults to the caller)
// actually has a live, subscribed OneSignal push subscription — this is
// the one thing send-notification's pushError field can't tell us, since
// OneSignal returns "success" for a send that targets zero *actually
// subscribed* devices. super_admin only, since this reveals another
// user's device/subscription state.
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

    const { data: callerProfile } = await supabase.from("profiles").select("role").eq("id", callerId).maybeSingle()
    if (!callerProfile || callerProfile.role !== "super_admin") {
      return new Response(JSON.stringify({ error: "super_admin only." }), { status: 403, headers: corsHeaders })
    }

    const body = await req.json().catch(() => ({}))
    const targetId = body.userId || callerId

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
