-- Postgres grants EXECUTE to PUBLIC on every new function, so the explicit
-- "grant execute to authenticated" in the two previous migrations added
-- nothing -- anon already had it. Nothing leaked: calling
-- campus_activity_facets() as anon fails anyway, because an RLS policy on one
-- of the tables it reads calls caller_can(), which anon may not execute.
--
-- But that is a boundary held by accident. It is one unrelated grant away from
-- becoming a real anon-readable endpoint, and it answers an unauthenticated
-- caller with a 42501 from three layers down instead of a clean refusal.
-- Neither function has any business being reachable before sign-in.
revoke all on function public.campus_activity_facets() from public, anon;
revoke all on function public.my_campus_facets()       from public, anon;

grant execute on function public.campus_activity_facets() to authenticated;
grant execute on function public.my_campus_facets()       to authenticated;
