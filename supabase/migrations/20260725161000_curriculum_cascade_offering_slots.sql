-- =====================================================================
--  AFOS — Deleting an offering must take its generated routine rows with it.
--
--  Found by the end-to-end probe of the curriculum flow: deleting a
--  course_offerings row left its generated schedule_slots behind, because
--  schedule_slots.course_offering_id was ON DELETE SET NULL. The slots
--  simply lost their provenance link and stayed on the routine forever,
--  taking every enrolled student's user_pinned_slots rows with them --
--  a class that no longer exists, un-unpinnable and indistinguishable
--  from a real routine-uploaded row.
--
--  Reachable in practice: teacher_delete_own_pending_offering is scoped to
--  status='pending' (no slots generated yet, so harmless), but
--  admin_manage_offerings is FOR ALL, so an admin deleting an APPROVED
--  offering hits exactly this. archive_course_offering does the right thing
--  by deleting the slots explicitly; a raw DELETE did not.
--
--  CASCADE is the correct semantic: a slot carrying a course_offering_id
--  exists *because of* that offering and has no meaning without it. Rows
--  imported from a routine PDF always have course_offering_id NULL, so
--  they are untouched by this.
--
--  Note this pairs with the parse-routine change in the same session, which
--  excludes course_offering_id IS NOT NULL rows from deleteObsolete so a
--  routine re-upload can't delete them either. Between the two, generated
--  slots now have exactly one lifecycle owner: the offering.
-- =====================================================================

ALTER TABLE schedule_slots
  DROP CONSTRAINT IF EXISTS schedule_slots_course_offering_id_fkey;

ALTER TABLE schedule_slots
  ADD CONSTRAINT schedule_slots_course_offering_id_fkey
  FOREIGN KEY (course_offering_id) REFERENCES course_offerings(id) ON DELETE CASCADE;
