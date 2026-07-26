-- 1. Create Grade Change Requests Table
CREATE TABLE IF NOT EXISTS grade_change_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  marks_id uuid REFERENCES marks(id) ON DELETE CASCADE,
  requested_by uuid REFERENCES teachers(profile_id),
  reason text NOT NULL,
  old_values jsonb,
  new_values jsonb,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by uuid REFERENCES profiles(id),
  reviewed_at timestamp with time zone
);

-- 2. Enable RLS
ALTER TABLE grade_change_requests ENABLE ROW LEVEL SECURITY;

-- 3. RLS Policies
-- Teachers can create requests, DeptAdmin can approve
CREATE POLICY teacher_create_request ON grade_change_requests FOR INSERT TO authenticated WITH CHECK (requested_by = auth.uid());
CREATE POLICY dept_admin_read_requests ON grade_change_requests FOR SELECT TO authenticated USING (has_permission('grade_change', 'select', 'department'));
CREATE POLICY dept_admin_approve_requests ON grade_change_requests FOR UPDATE TO authenticated USING (has_permission('grade_change', 'update', 'department'));

-- 4. Transactional Approval Function
CREATE OR REPLACE FUNCTION approve_grade_change(request_id uuid)
RETURNS void AS $$
DECLARE
  req record;
BEGIN
  -- 1. Get request
  SELECT * INTO req FROM grade_change_requests WHERE id = request_id;
  
  -- 2. Update marks (requires disabling the trigger temporarily or using a flag if needed)
  -- For now, we update the mark directly, the trigger handles the grading logic
  UPDATE marks 
  SET attendance_marks = (req.new_values->>'attendance_marks')::numeric,
      quiz_marks = (req.new_values->>'quiz_marks')::numeric,
      assignment_marks = (req.new_values->>'assignment_marks')::numeric,
      midterm_marks = (req.new_values->>'midterm_marks')::numeric,
      final_marks = (req.new_values->>'final_marks')::numeric
  WHERE id = req.marks_id;
  
  -- 3. Update request status
  UPDATE grade_change_requests 
  SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = now() 
  WHERE id = request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
