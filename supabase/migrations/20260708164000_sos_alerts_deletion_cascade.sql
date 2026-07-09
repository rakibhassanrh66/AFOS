-- sos_alerts.user_id was created without ON DELETE CASCADE -- the same
-- FK gap already fixed for every other content table in
-- 20260706000100_user_deletion_cascade.sql (any account with real activity
-- would block auth.admin.deleteUser() with a foreign-key violation).
-- user_id (the sender, personal content) cascades; resolved_by (a
-- positional reference to whichever admin resolved it) sets null instead,
-- matching that same migration's split between personal-content vs
-- positional/institutional references.
alter table sos_alerts drop constraint sos_alerts_user_id_fkey;
alter table sos_alerts add constraint sos_alerts_user_id_fkey
  foreign key (user_id) references profiles(id) on delete cascade;

alter table sos_alerts drop constraint sos_alerts_resolved_by_fkey;
alter table sos_alerts add constraint sos_alerts_resolved_by_fkey
  foreign key (resolved_by) references profiles(id) on delete set null;
