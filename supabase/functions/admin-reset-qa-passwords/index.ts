import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY")!
const ADMIN_SECRET = Deno.env.get("QA_RESET_SECRET")!

// One-off dev utility, not part of the app's real surface: resets the 5
// persistent QA integration-test accounts (see integration_test/
// overflow_smoke_test.dart) to a known password so the suite can actually
// run without needing anyone's real credentials. Gated by a pre-shared
// secret header rather than a caller JWT/role check, since this is invoked
// from tooling, not the app itself -- meant to be deleted once no longer
// needed, not left as permanent standing surface.
serve(async (req) => {
  const corsHeaders = { "Access-Control-Allow-Origin": "*", "Content-Type": "application/json" }
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })

  const provided = req.headers.get("x-admin-secret")
  if (!provided || provided !== ADMIN_SECRET) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: corsHeaders })
  }

  const { newPassword } = await req.json()
  if (!newPassword || String(newPassword).length < 8) {
    return new Response(JSON.stringify({ error: "newPassword (8+ chars) required" }), { status: 400, headers: corsHeaders })
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE)
  const emails = [
    "qa_student@afos.test",
    "qa_teacher@afos.test",
    "qa_staff@afos.test",
    "rakibhassan.rh68+qaadmin@gmail.com",
    "rakibhassan.rh68+qasuperadmin@gmail.com",
  ]

  const { data: userList, error: listErr } = await supabase.auth.admin.listUsers({ perPage: 1000 })
  if (listErr) {
    return new Response(JSON.stringify({ error: listErr.message }), { status: 500, headers: corsHeaders })
  }

  const results: Record<string, string> = {}
  for (const email of emails) {
    const user = userList.users.find((u) => u.email === email)
    if (!user) { results[email] = "not found"; continue }
    const { error } = await supabase.auth.admin.updateUserById(user.id, { password: newPassword })
    results[email] = error ? `error: ${error.message}` : "reset"
  }

  return new Response(JSON.stringify({ results }), { headers: corsHeaders })
})
