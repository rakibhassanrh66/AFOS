import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY")!
const ONESIGNAL_APP_ID = "2ae8d7b3-8999-4054-b185-2256b290993c"
const ONESIGNAL_REST_KEY = Deno.env.get("ONESIGNAL_REST_KEY")!

// Shared push + in-app notification sender.
//
// Rewritten from an earlier stub that read a `SUPABASE_SERVICE_ROLE` secret
// that doesn't exist (only SUPABASE_SERVICE_ROLE_KEY/SERVICE_ROLE_KEY do),
// so createClient() would throw on every call — this function has never
// actually worked. It also had no authorization at all: any valid JWT could
// push arbitrary notification content into any other user's in-app
// notification center (a real phishing vector), and used OneSignal's
// legacy include_external_user_ids field instead of the currently-working
// include_aliases format (verified live against this app's actual REST key).
//
// Two targeting modes:
//  - userIds: direct notification to specific users, tied to an action the
//    caller just performed (mentorship reply, lost&found claim accepted).
//    Any authenticated user may use this, capped at 20 recipients so it
//    can't become a mass-broadcast tool.
//  - roleFilter/departmentFilter: broadcast targeting (routine/exam/transport
//    updates, announcements) — restricted to admin/teacher/dept_admin/
//    super_admin, matching the same authorization used for routine uploads.
//
// Every call writes to user_notifications (in-app notification center)
// AND sends a OneSignal push via external_id targeting (the app sets
// OneSignal's external_id to the Supabase user id on login).
serve(async (req) => {
  const corsHeaders = { "Access-Control-Allow-Origin": "*", "Content-Type": "application/json" }
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })

  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE)
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "")
    if (!jwt) {
      return new Response(JSON.stringify({ error: "Missing authorization." }), { status: 401, headers: corsHeaders })
    }
    const { data: authData, error: authErr } = await supabase.auth.getUser(jwt)
    if (authErr || !authData?.user) {
      return new Response(JSON.stringify({ error: "Invalid or expired session." }), { status: 401, headers: corsHeaders })
    }
    const callerId = authData.user.id

    const body = await req.json()
    const { title, message, deepLink, category, userIds, roleFilter, departmentFilter, broadcastAll, clubId } = body
    if (!title || !message) {
      return new Response(JSON.stringify({ error: "title and message are required." }), { status: 400, headers: corsHeaders })
    }

    let targetUserIds: string[] = []

    if (clubId) {
      // A club president broadcasting to their own club's members only —
      // verified against clubs.president_id server-side so a regular
      // member can't spoof this by just passing a clubId they don't lead.
      const { data: club } = await supabase.from("clubs").select("president_id").eq("id", clubId).maybeSingle()
      if (!club || club.president_id !== callerId) {
        return new Response(JSON.stringify({ error: "Only that club's president can notify its members." }), { status: 403, headers: corsHeaders })
      }
      const { data: members, error } = await supabase.from("club_members").select("member_id").eq("club_id", clubId)
      if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: corsHeaders })
      targetUserIds = (members ?? []).map((m: { member_id: string }) => m.member_id).filter((id: string) => id !== callerId)
    } else if (Array.isArray(userIds) && userIds.length > 0) {
      if (userIds.length > 20) {
        return new Response(JSON.stringify({ error: "Too many direct recipients (max 20)." }), { status: 400, headers: corsHeaders })
      }
      targetUserIds = userIds
    } else if (roleFilter || departmentFilter || broadcastAll) {
      const { data: callerProfile } = await supabase.from("profiles").select("role").eq("id", callerId).maybeSingle()
      const broadcastRoles = ["admin", "super_admin", "dept_admin", "teacher"]
      if (!callerProfile || !broadcastRoles.includes(callerProfile.role)) {
        return new Response(JSON.stringify({ error: "Not authorized to broadcast notifications." }), { status: 403, headers: corsHeaders })
      }
      let query = supabase.from("profiles").select("id")
      if (roleFilter) query = query.eq("role", roleFilter)
      if (departmentFilter) query = query.eq("department", departmentFilter)
      const { data: rows, error } = await query
      if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: corsHeaders })
      targetUserIds = (rows ?? []).map((r: { id: string }) => r.id)
    } else {
      return new Response(JSON.stringify({ error: "Provide userIds, roleFilter/departmentFilter, broadcastAll, or clubId." }), { status: 400, headers: corsHeaders })
    }

    if (targetUserIds.length === 0) {
      return new Response(JSON.stringify({ success: true, pushTargeted: 0, inAppInserted: 0 }), { headers: corsHeaders })
    }

    const rows = targetUserIds.map((uid) => ({
      user_id: uid, title, body: message, category: category ?? "general",
      deep_link_route: deepLink ?? null,
    }))
    const { error: insertErr } = await supabase.from("user_notifications").insert(rows)

    let pushTargeted = 0
    let pushError: string | null = null
    try {
      const osRes = await fetch("https://onesignal.com/api/v1/notifications", {
        method: "POST",
        headers: { "Content-Type": "application/json", "Authorization": `Basic ${ONESIGNAL_REST_KEY}` },
        body: JSON.stringify({
          app_id: ONESIGNAL_APP_ID,
          include_aliases: { external_id: targetUserIds },
          target_channel: "push",
          headings: { en: title },
          contents: { en: message },
          data: deepLink ? { deep_link_route: deepLink } : undefined,
        }),
      })
      const osJson = await osRes.json()
      if (osRes.ok && !osJson.errors) pushTargeted = targetUserIds.length
      else pushError = JSON.stringify(osJson.errors ?? osJson)
    } catch (e) {
      pushError = String(e)
    }

    return new Response(JSON.stringify({
      success: true, inAppInserted: insertErr ? 0 : rows.length, insertError: insertErr?.message, pushTargeted, pushError,
    }), { headers: corsHeaders })
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500, headers: corsHeaders })
  }
})
