-- Let a user delete a file they uploaded to `assignment-submissions`.
--
-- WHY. The bucket was created (20260726120221) with INSERT, UPDATE and two
-- SELECT policies and NO DELETE policy at all, so nothing that lands there
-- could ever be removed by the person who put it there. That was survivable
-- while the only writer was a student submitting coursework they wanted kept.
--
-- It stops being survivable now that teachers attach a brief: deleting an
-- assignment drops the row, the row is what `assignment_brief_read` keys on,
-- and the file is left behind — unreferenced, unreadable by the students it
-- was for, and counted against storage forever. Every deleted assignment
-- would leak one file.
--
-- Scoped to the first path segment, exactly like the INSERT and UPDATE
-- policies beside it: you may delete only out of your own {uid}/ folder. That
-- is the narrowest rule that fixes the leak — a teacher cannot reach a
-- student's submission with it, and a student cannot reach a brief.
DROP POLICY IF EXISTS assignment_submission_own_delete ON storage.objects;
CREATE POLICY assignment_submission_own_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'assignment-submissions'
         AND (storage.foldername(name))[1] = auth.uid()::text);
