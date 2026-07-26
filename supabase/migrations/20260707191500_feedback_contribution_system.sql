-- Feedback existed (settings_screen.dart's "Send Feedback") but was
-- write-only: INSERT-only RLS meant nobody, not even super_admin, could
-- ever read a single submission back — every piece of feedback anyone
-- ever sent vanished into a table nobody could query. Extends it into a
-- real feedback/contribution box: a title, an optional attached file
-- (idea document, proposal, etc.), and a status a super_admin can
-- actually see and act on.
alter table feedback add column if not exists title text;
alter table feedback add column if not exists file_url text;
alter table feedback add column if not exists file_name text;
alter table feedback add column if not exists status text not null default 'new';
alter table feedback add column if not exists reviewed_by uuid references profiles(id) on delete set null;
alter table feedback add column if not exists reviewed_at timestamptz;

create policy own_read_feedback on feedback for select
  using (auth.uid() = user_id);

create policy super_admin_manage_feedback on feedback for all
  using (get_my_profile_role() = 'super_admin')
  with check (get_my_profile_role() = 'super_admin');

-- Private bucket (not public-read like avatars/lost-found) — only the
-- submitter and super_admin should ever see an attached file. Restricted
-- to common document/image formats (never executables) as the actual,
-- honest scope of "check the file is safe" — this is real gatekeeping of
-- what can even be uploaded, not a malware/antivirus scan (no such
-- service is wired up; that would need a real scanning API, a separate,
-- much bigger decision not made here).
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('feedback-attachments', 'feedback-attachments', false, 10485760,
  ARRAY['application/pdf','application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'image/jpeg','image/png','application/zip','text/plain'])
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "feedback_attachments_own_write" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'feedback-attachments' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "feedback_attachments_own_read" ON storage.objects FOR SELECT
  USING (bucket_id = 'feedback-attachments' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "feedback_attachments_super_admin_read" ON storage.objects FOR SELECT
  USING (bucket_id = 'feedback-attachments' AND get_my_profile_role() = 'super_admin');

CREATE POLICY "feedback_attachments_super_admin_delete" ON storage.objects FOR DELETE
  USING (bucket_id = 'feedback-attachments' AND get_my_profile_role() = 'super_admin');
