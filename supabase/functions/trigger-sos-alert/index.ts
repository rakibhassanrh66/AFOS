import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY")!
const ONESIGNAL_APP_ID = "2ae8d7b3-8999-4054-b185-2256b290993c"
const ONESIGNAL_REST_KEY = Deno.env.get("ONESIGNAL_REST_KEY")!

// Campus centroid -- Daffodil Smart City, Birulia, Savar. Matches the same
// constant already used in transport_screen.dart (_diuLat/_diuLng) so the
// whole app agrees on one DIU location rather than two different
// approximations; confirm/refine both together with a real pin drop before
// relying on this for production alerts.
const CAMPUS_LAT = 23.7953
const CAMPUS_LNG = 90.4044
const CAMPUS_RADIUS_KM = 3
const NEARBY_RADIUS_KM = 5
const NEARBY_STALE_MINUTES = 60
const STAFF_TIER_ROLES = ["staff", "admin", "dept_admin", "super_admin", "exam_controller", "teacher"]
const ONESIGNAL_CHUNK_SIZE = 2000

// Consumes one token from a named bucket, returning whether the call is
// allowed. Capacity and refill rate live in the rate_limit_policies table
// (see sec_token_bucket_rate_limiting), so a threshold can be retuned with
// an UPDATE instead of a redeploy.
//
// The key MUST be passed explicitly: consume_rate_limit() defaults it to
// auth.uid(), which is NULL under the service-role client this function
// uses -- and a NULL key is DENIED, not allowed, so relying on the default
// here would reject every SOS.
//
// Fails OPEN if the limiter itself errors. An outage in rate limiting must
// never be the reason an emergency alert doesn't go out; a genuine `false`
// (bucket actually empty) is still enforced.
async function consumeRateLimit(
  // deno-lint-ignore no-explicit-any
  supabase: any, bucket: string, key: string,
): Promise<boolean> {
  const { data, error } = await supabase.rpc("consume_rate_limit", {
    p_bucket: bucket, p_key: key, p_cost: 1,
  })
  if (error) {
    console.error(`[rate_limit] ${bucket} check failed, allowing:`, error.message)
    return true
  }
  return data !== false
}

function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371
  const dLat = (lat2 - lat1) * Math.PI / 180
  const dLon = (lon2 - lon1) * Math.PI / 180
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLon / 2) ** 2
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

// Any authenticated user may call this for themselves -- unlike
// send-notification's admin-gated broadcast paths, there is no role check
// here at all. Recipient resolution:
//  - campus zone (within CAMPUS_RADIUS_KM of the DIU campus point): every
//    user_locations row within NEARBY_RADIUS_KM with sharing_enabled and a
//    fresh-enough ping, UNION every approved hall_applications resident,
//    UNION every staff-tier role (always, regardless of proximity).
//  - zila zone (elsewhere in Bangladesh): admin/super_admin always, plus
//    every profile whose registered permanent_district matches the
//    sender's own registered permanent_district (falls back to
//    permanent_division if nobody else shares the exact district) -- based
//    on registered address, not a live reverse-geocode of the coordinate.
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
    const { latitude, longitude, message, voicePath } = body
    if (typeof latitude !== "number" || typeof longitude !== "number") {
      return new Response(JSON.stringify({ error: "latitude and longitude are required." }), { status: 400, headers: corsHeaders })
    }

    // Rate limit -- prevents spam/duplicate taps from re-alerting the same
    // people every few seconds.
    //
    // Was a hardcoded 5-minute window over recent ACTIVE alerts. Now a token
    // bucket whose capacity/refill live in rate_limit_policies, so the
    // threshold is tunable without a redeploy. The 'sos_alert' policy is
    // deliberately set to burst 2 / refill 0.2 per minute: the same sustained
    // one-per-5-minutes as before, plus one spare token so a second genuine
    // emergency right after a resolved one is not swallowed (the old check
    // ignored resolved alerts; a plain 1-token bucket would not have).
    if (!await consumeRateLimit(supabase, "sos_alert", callerId)) {
      return new Response(JSON.stringify({ error: "You already sent an alert in the last few minutes." }), { status: 429, headers: corsHeaders })
    }

    const { data: sender } = await supabase.from("profiles")
      .select("full_name, permanent_district, permanent_division").eq("id", callerId).maybeSingle()

    const distanceFromCampus = haversineKm(latitude, longitude, CAMPUS_LAT, CAMPUS_LNG)
    const zoneType: "campus" | "zila" = distanceFromCampus <= CAMPUS_RADIUS_KM ? "campus" : "zila"

    const recipientIds = new Set<string>()

    if (zoneType === "campus") {
      const { data: nearby } = await supabase.from("user_locations")
        .select("user_id, latitude, longitude")
        .eq("sharing_enabled", true)
        .not("latitude", "is", null).not("longitude", "is", null)
        .gte("updated_at", new Date(Date.now() - NEARBY_STALE_MINUTES * 60_000).toISOString())
      for (const row of nearby ?? []) {
        if (haversineKm(latitude, longitude, row.latitude, row.longitude) <= NEARBY_RADIUS_KM) {
          recipientIds.add(row.user_id)
        }
      }

      const { data: residents } = await supabase.from("hall_applications")
        .select("student_id").eq("status", "approved")
      for (const row of residents ?? []) recipientIds.add(row.student_id)

      const { data: staffTier } = await supabase.from("profiles")
        .select("id").in("role", STAFF_TIER_ROLES)
      for (const row of staffTier ?? []) recipientIds.add(row.id)
    } else {
      const { data: admins } = await supabase.from("profiles")
        .select("id").in("role", ["admin", "super_admin"])
      for (const row of admins ?? []) recipientIds.add(row.id)

      if (sender?.permanent_district) {
        const { data: sameDistrict } = await supabase.from("profiles")
          .select("id").eq("permanent_district", sender.permanent_district)
        for (const row of sameDistrict ?? []) recipientIds.add(row.id)
      }
      if (recipientIds.size === 0 && sender?.permanent_division) {
        const { data: sameDivision } = await supabase.from("profiles")
          .select("id").eq("permanent_division", sender.permanent_division)
        for (const row of sameDivision ?? []) recipientIds.add(row.id)
      }
    }

    recipientIds.delete(callerId)
    const targetUserIds = Array.from(recipientIds)

    const { data: alert, error: insertAlertErr } = await supabase.from("sos_alerts").insert({
      user_id: callerId, latitude, longitude, zone_type: zoneType,
      message: message ?? null, voice_path: voicePath ?? null,
      recipient_count: targetUserIds.length,
    }).select("id").single()
    if (insertAlertErr || !alert) {
      return new Response(JSON.stringify({ error: insertAlertErr?.message ?? "Could not create alert." }), { status: 500, headers: corsHeaders })
    }

    const title = `🆘 SOS: ${sender?.full_name ?? "Someone"} needs help`
    const pushBody = message?.trim() ? message.trim() : "Tap to see their location and respond."
    const deepLinkRoute = `/sos/${alert.id}`

    let inAppInserted = 0
    let insertError: string | null = null
    if (targetUserIds.length > 0) {
      const rows = targetUserIds.map((uid) => ({
        user_id: uid, title, body: pushBody, category: "sos", deep_link_route: deepLinkRoute,
      }))
      const { error } = await supabase.from("user_notifications").insert(rows)
      if (error) insertError = error.message
      else inAppInserted = rows.length
    }

    let pushTargeted = 0
    let pushError: string | null = null
    if (targetUserIds.length > 0) {
      try {
        for (let i = 0; i < targetUserIds.length; i += ONESIGNAL_CHUNK_SIZE) {
          const chunk = targetUserIds.slice(i, i + ONESIGNAL_CHUNK_SIZE)
          const osRes = await fetch("https://onesignal.com/api/v1/notifications", {
            method: "POST",
            headers: { "Content-Type": "application/json", "Authorization": `Basic ${ONESIGNAL_REST_KEY}` },
            body: JSON.stringify({
              app_id: ONESIGNAL_APP_ID,
              include_aliases: { external_id: chunk },
              target_channel: "push",
              priority: 10,
              headings: { en: title },
              contents: { en: pushBody },
              data: { deep_link_route: deepLinkRoute },
            }),
          })
          const osJson = await osRes.json()
          if (osRes.ok && !osJson.errors) pushTargeted += chunk.length
          else pushError = JSON.stringify(osJson.errors ?? osJson)
        }
      } catch (e) {
        pushError = String(e)
      }
    }

    return new Response(JSON.stringify({
      success: true, alertId: alert.id, zoneType, recipientCount: targetUserIds.length,
      inAppInserted, insertError, pushTargeted, pushError,
    }), { headers: corsHeaders })
  } catch (err) {
    // `err` is `unknown`: a non-Error throw (a string, a rejected fetch value)
    // used to render as "undefined" here, which tells the caller nothing and
    // tells us nothing in the log either.
    const message = err instanceof Error ? err.message : String(err)
    return new Response(JSON.stringify({ error: message }), { status: 500, headers: corsHeaders })
  }
})
