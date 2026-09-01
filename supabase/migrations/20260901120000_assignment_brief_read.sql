-- Let a student open the brief their teacher attached to an assignment.
--
-- WHY THIS IS NEEDED. `assignments.attachment_url` has existed since the table
-- was created and nothing has ever written it: the teacher's create form had
-- no attach control, so a teacher could not send the question paper, only
-- type instructions into a text box. Adding that control is the point of this
-- change — but the file has to be READABLE by the students it is set for, and
-- it was not.
--
-- The `assignment-submissions` bucket had exactly two SELECT policies:
--   * assignment_submission_own_read      — your own {uid}/ folder
--   * assignment_submission_teacher_read  — a teacher reading submissions made
--                                           to their own assignment
-- A teacher's brief lives under the TEACHER's uid folder, so a student matched
-- neither and got nothing back. Uploading a brief without this policy would
-- have produced a file nobody but its author could open.
--
-- WHY IT INHERITS RATHER THAN RESTATES THE SCOPING. The condition is simply
-- "some assignment row that I can see points at this object". RLS applies to
-- the subquery for ordinary roles, so `assignments`' own three policies decide
-- who that is — the owning teacher, a student in the matching
-- department+batch+section, and a super_admin observer. Restating those rules
-- here would be a second copy free to drift from the first; this cannot,
-- because it asks the table itself.
--
-- Matched on equality, not LIKE. The column stores the storage PATH (the
-- bucket is private and paths are signed on demand), so `= objects.name` is
-- exact. The neighbouring teacher-read policy uses `LIKE '%' || name`, which
-- would also match a path merely ENDING in another's name.
create policy assignment_brief_read
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'assignment-submissions'
    and exists (
      select 1
        from assignments a
       where a.attachment_url = objects.name
    )
  );
