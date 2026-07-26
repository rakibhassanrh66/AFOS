-- 1. Apply Performance Indexes
CREATE INDEX IF NOT EXISTS idx_students_department ON students(department_id);
CREATE INDEX IF NOT EXISTS idx_enrollments_student ON enrollments(student_id);
CREATE INDEX IF NOT EXISTS idx_enrollments_offering ON enrollments(offering_id);
CREATE INDEX IF NOT EXISTS idx_course_offerings_teacher ON course_offerings(teacher_id);
CREATE INDEX IF NOT EXISTS idx_profiles_department ON profiles(department_id);
CREATE INDEX IF NOT EXISTS idx_marks_published ON marks(is_published);

-- 2. RLS Security Test Script (For Reference)
-- Run this in SQL Editor to verify security
DO $$
BEGIN
  -- Test 1: Student role reading other students (Should fail or return 0 rows)
  -- Perform as a student user (mocked):
  -- SET ROLE authenticated;
  -- SET request.jwt.claim.sub = 'student_user_id';
  -- SELECT count(*) FROM students; -- Should be 1
  
  -- Test 2: Teacher modifying other marks (Should fail)
  -- SET request.jwt.claim.sub = 'teacher_user_id';
  -- UPDATE marks SET final_marks = 100 WHERE id = 'marks_id_of_another_teacher'; -- Should raise error
  RAISE NOTICE 'RLS Test Script ready. Run policies in SQL editor to mock users.';
END $$;
