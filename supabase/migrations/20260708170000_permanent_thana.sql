-- Dhaka city proper isn't subdivided into upazilas at all -- it's policed/
-- administered as 50 thanas under Dhaka Metropolitan Police (DNCC + DSCC).
-- The existing permanent_upazila column can't represent that, so residents
-- selecting the synthetic "Dhaka Mahanagar" upazila entry (see
-- lib/core/data/bd_geography.dart) get a 4th address field instead.
-- Nullable and optional: only Dhaka Mahanagar residents ever set it, so no
-- retroactive profile_completed reset is needed here (unlike the upazila
-- migration) -- nobody was ever required to have this field.
alter table profiles add column if not exists permanent_thana text;
