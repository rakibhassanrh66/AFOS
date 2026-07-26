-- hall_availability was a bare view, which (absent an explicit
-- security_invoker=true, unset here) runs with the view CREATOR's
-- permissions rather than the querying user's -- flagged Critical by
-- Supabase's security advisor. It genuinely needs to bypass RLS: the
-- available-seats count is computed by aggregating hall_applications,
-- whose RLS restricts each student to their own row (auth.uid() =
-- student_id), so a plain security_invoker view would show every student
-- only their own application's contribution to the count instead of the
-- true hall-wide total.
--
-- The columns returned (hall id/name/gender/capacity/computed available
-- count/amenities) contain zero per-student data, so the actual exposure
-- here was always low -- but a bare view can silently grow more columns
-- later without anyone re-checking the security implication. A SECURITY
-- DEFINER FUNCTION with an explicit, fixed return signature and a pinned
-- search_path (blocking the classic search-path-hijack attack a SECURITY
-- DEFINER function is otherwise vulnerable to) is the standard hardened
-- replacement for exactly this "need a real aggregate across an
-- RLS-protected table" pattern.
drop view if exists public.hall_availability;

create or replace function public.get_hall_availability()
returns table (
  id uuid,
  name text,
  gender text,
  capacity integer,
  available integer,
  amenities text[]
)
language sql
security definer
set search_path = public
stable
as $$
  select
    h.id, h.name, h.gender, h.capacity,
    h.capacity - coalesce(occupied.cnt, 0) as available,
    h.amenities
  from halls h
  left join (
    select preferred_hall, count(*) as cnt
    from hall_applications
    where status in ('approved', 'cancel_requested')
    group by preferred_hall
  ) occupied on occupied.preferred_hall = h.name
  where h.is_active;
$$;

grant execute on function public.get_hall_availability() to authenticated;
