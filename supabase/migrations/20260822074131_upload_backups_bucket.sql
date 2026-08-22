-- Private bucket for the backup PDF taken before an upload is removed.
-- Kept rather than discarded after download: a backup you cannot fetch twice
-- is not much of a backup, and these are a few KB against the thousands of
-- rows they stand in for.
insert into storage.buckets (id, name, public)
values ('upload-backups', 'upload-backups', false)
on conflict (id) do nothing;

drop policy if exists uploaders_read_upload_backups on storage.objects;
create policy uploaders_read_upload_backups on storage.objects
  for select to authenticated
  using (bucket_id = 'upload-backups' and can_manage_uploads());

drop policy if exists uploaders_write_upload_backups on storage.objects;
create policy uploaders_write_upload_backups on storage.objects
  for insert to authenticated
  with check (bucket_id = 'upload-backups' and can_manage_uploads());
