import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const SUPABASE_URL    = Deno.env.get("SUPABASE_URL")!
const SERVICE_ROLE    = Deno.env.get("SUPABASE_SERVICE_ROLE")!
const OS_REST_KEY     = Deno.env.get("ONESIGNAL_REST_KEY")!
const ONESIGNAL_APP   = "2ae8d7b3-8999-4054-b185-2256b290993c"

serve(async (req) => {
  const cors = { "Access-Control-Allow-Origin": "*", "Content-Type": "application/json" }
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors })

  const { userId, title, body, category, data } = await req.json()
  if (!userId || !title) return new Response(JSON.stringify({ error: "userId and title required" }), { status: 400, headers: cors })

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE)

  // Log in-app notification
  await supabase.from("user_notifications").insert({
    user_id: userId, title, body: body ?? "", category: category ?? "general",
    is_read: false, deep_link_route: data?.route ?? "/notifications",
  })

  // Send OneSignal push
  const osRes = await fetch("https://onesignal.com/api/v1/notifications", {
    method: "POST",
    headers: { "Authorization": `Basic ${OS_REST_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      app_id: ONESIGNAL_APP,
      include_external_user_ids: [userId],
      headings: { en: title },
      contents: { en: body ?? "" },
      data: data ?? {},
    }),
  })
  const osData = await osRes.json()
  return new Response(JSON.stringify({ success: true, oneSignal: osData }), { headers: cors })
})
