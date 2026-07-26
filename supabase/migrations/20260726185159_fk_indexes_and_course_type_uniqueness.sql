-- Two corrections to the schema added earlier this session.
--
-- 1. A teacher may hold BOTH the theory and the lab for one section.
--
-- The allocation uniqueness rule was (department, course_code, batch, section,
-- semester) and omitted course_type, so allocating CSE221 theory and CSE221
-- lab to batch 68 section D was rejected as a duplicate. Lab courses usually
-- carry their own code at DIU, which is why this did not show up immediately,
-- but where they share one it silently blocks half a teacher's load -- and a
-- teacher holding four theory sections plus four labs is the normal case, not
-- an edge case.
--
-- The rule stays "one teacher per class per semester"; a theory class and a
-- lab class are simply not the same class.

ALTER TABLE teaching_assignments
  DROP CONSTRAINT IF EXISTS teaching_assignments_department_course_code_batch_section_s_key;

CREATE UNIQUE INDEX IF NOT EXISTS teaching_assignments_unique_class
  ON teaching_assignments (department, course_code, course_type, batch, section, semester);

COMMENT ON INDEX teaching_assignments_unique_class IS
  'One teacher per class per semester. course_type is part of the key because '
  'the theory and the lab of the same course are different classes.';

-- 2. Foreign keys with no covering index.
--
-- Every one of these forces a sequential scan of the child table whenever the
-- referenced row is deleted or its key updated -- removing a teacher profile
-- scans every attendance record ever written. Cheap to add, and the tables
-- only grow. Same class of finding as assignment_submissions.graded_by, which
-- the advisors named and which was fixed in isolation; these are its siblings.

CREATE INDEX IF NOT EXISTS attendance_records_marked_by_idx
  ON attendance_records (marked_by);
CREATE INDEX IF NOT EXISTS attendance_sessions_taken_by_idx
  ON attendance_sessions (taken_by);
CREATE INDEX IF NOT EXISTS module_leaders_appointed_by_idx
  ON module_leaders (appointed_by);
CREATE INDEX IF NOT EXISTS offering_result_submissions_reviewed_by_idx
  ON offering_result_submissions (reviewed_by);
CREATE INDEX IF NOT EXISTS offering_result_submissions_submitted_by_idx
  ON offering_result_submissions (submitted_by);
CREATE INDEX IF NOT EXISTS student_marks_component_idx
  ON student_marks (component_id);
CREATE INDEX IF NOT EXISTS student_marks_updated_by_idx
  ON student_marks (updated_by);
CREATE INDEX IF NOT EXISTS teaching_assignments_assigned_by_idx
  ON teaching_assignments (assigned_by);
CREATE INDEX IF NOT EXISTS teaching_assignments_offering_idx
  ON teaching_assignments (offering_id);
