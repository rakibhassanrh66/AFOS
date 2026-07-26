-- Mandatory live-GPS capture (see complete_profile_screen.dart's new
-- "Confirm my location" step) is a hard gate now, same tier as the
-- permanent-address fields added earlier today -- not just an opt-in
-- Settings toggle. Same retroactive-reset pattern as
-- 20260708162000_permanent_address_and_gate.sql: force every EXISTING
-- account that hasn't captured a real coordinate back through
-- /complete-profile on next open, not just new signups.
update profiles p set profile_completed = false
where not exists (
  select 1 from user_locations ul where ul.user_id = p.id and ul.latitude is not null
);
