import { serve } from "https://deno.land/std@0.177.0/http/server.ts"

// DISABLED 2026-07-25: this was a one-off dev/QA utility gated only by a
// pre-shared secret header (not a real caller-role check), able to reset
// the password of 5 hardcoded accounts -- including the real admin/
// super_admin accounts -- to any value the caller supplied. Its exact
// behavior and target email addresses were fully visible in this repo's
// public source, and it was never wired into any CI/automated flow (the
// integration test suite that motivated it reads passwords via
// --dart-define and never called this function directly), so removing it
// costs nothing. Left deployed-but-inert (instead of deleted outright,
// which this tooling can't do) so any stale caller gets a clear, safe
// response instead of a mysterious failure.
serve(async (_req) => {
  return new Response(
    JSON.stringify({ error: "This endpoint has been permanently disabled." }),
    { status: 410, headers: { "Content-Type": "application/json" } },
  )
})
