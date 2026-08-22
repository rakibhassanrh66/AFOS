-- The console's campus panels, aggregated in Postgres.
--
-- WHY A FUNCTION AND NOT SIX QUERIES. schedule_slots holds 1854 rows and the
-- heatmap needs a 6x9 grid of counts from it. Shipping 1854 rows to a browser
-- to count them there is the same mistake nine dashboard queries already made
-- once in this project (downloading ID lists just to take .length). This
-- returns roughly 60 numbers instead, in one round trip.
--
-- SECURITY INVOKER on purpose. Every table it touches is already readable by
-- the caller under RLS; this adds no reach, it only does the arithmetic
-- server-side. A DEFINER here would silently widen what a student can total up.
create or replace function public.campus_activity_facets()
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select jsonb_build_object(
    -- day_of_week x hour-of-day density. The grid the heatmap draws.
    'density', coalesce((
      select jsonb_agg(jsonb_build_object('d', d, 'h', h, 'n', n))
      from (
        select day_of_week as d,
               extract(hour from start_time)::int as h,
               count(*) as n
        from schedule_slots
        where coalesce(is_cancelled, false) = false
          and start_time is not null
          and day_of_week is not null
        group by 1, 2
      ) g
    ), '[]'::jsonb),

    'liveSlots', (select count(*) from schedule_slots
                  where coalesce(is_cancelled, false) = false),
    'labSlots',  (select count(*) from schedule_slots
                  where is_lab and coalesce(is_cancelled, false) = false),
    'cancelled', (select count(*) from schedule_slots where is_cancelled),
    'rooms',     (select count(distinct room_number) from schedule_slots
                  where coalesce(room_number, '') <> ''),
    'teachers',  (select count(distinct teacher_initial) from schedule_slots
                  where coalesce(teacher_initial, '') <> ''),

    -- Teaching load per batch, biggest first. The client folds the tail.
    'byBatch', coalesce((
      select jsonb_agg(jsonb_build_object('k', k, 'n', n) order by n desc)
      from (
        select batch as k, count(*) as n
        from schedule_slots
        where coalesce(batch, '') <> ''
          and coalesce(is_cancelled, false) = false
        group by 1
      ) b
    ), '[]'::jsonb),

    -- The rooms carrying the most classes.
    'topRooms', coalesce((
      select jsonb_agg(jsonb_build_object('k', k, 'n', n) order by n desc)
      from (
        select room_number as k, count(*) as n
        from schedule_slots
        where coalesce(room_number, '') <> ''
          and coalesce(is_cancelled, false) = false
        group by 1
        order by 2 desc
        limit 6
      ) r
    ), '[]'::jsonb),

    'clubs',        (select count(*) from clubs),
    'clubMembers',  (select count(*) from club_members),
    'routes',       (select count(*) from transport_routes),
    'stops',        (select count(*) from transport_stops),
    'books',        (select count(*) from books),
    'departments',  (select count(*) from departments),
    'programs',     (select count(*) from programs)
  );
$$;

comment on function public.campus_activity_facets() is
  'Aggregates for the web console campus panels. INVOKER: RLS on the underlying tables remains the boundary.';

grant execute on function public.campus_activity_facets() to authenticated;
