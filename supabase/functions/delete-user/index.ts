import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY")!

// Full account deletion for the super-admin "delete user entirely" feature.
// Requires service_role (auth.admin.deleteUser is not available to regular
// clients) so this has to be an edge function, gated to super_admin only —
// this is the most destructive action in the app, unlike everything else
// which is scoped to admin+super_admin.
//
// Order matters: storage objects are removed first (nothing in Postgres
// references storage paths, so nothing else depends on this happening
// first, but it's pointless to leave orphaned files if the DB call below
// fails), then auth.admin.deleteUser cascades through every FK that now
// points at profiles.id with ON DELETE CASCADE (see the
// 20260706000100_user_deletion_cascade migration) — positional references
// like club president/department head are SET NULL instead of deleted.
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
      return new Response(JSON.stringify({ error: "Only super_admin can delete accounts." }), { status: 403, headers: corsHeaders })
    }

    const { targetUserId } = await req.json()
    if (!targetUserId) {
      return new Response(JSON.stringify({ error: "targetUserId is required." }), { status: 400, headers: corsHeaders })
    }
    if (targetUserId === callerId) {
      return new Response(JSON.stringify({ error: "Cannot delete your own account." }), { status: 400, headers: corsHeaders })
    }

    for (const bucket of ["avatars", "lost-found"]) {
      const { data: files } = await supabase.storage.from(bucket).list(targetUserId)
      if (files && files.length > 0) {
        await supabase.storage.from(bucket).remove(files.map((f) => `${targetUserId}/${f.name}`))
      }
    }

    const { error: deleteErr } = await supabase.auth.admin.deleteUser(targetUserId)
    if (deleteErr) {
      return new Response(JSON.stringify({ error: deleteErr.message }), { status: 500, headers: corsHeaders })
    }

    return new Response(JSON.stringify({ success: true }), { headers: corsHeaders })
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500, headers: corsHeaders })
  }
})
