-- Approving a Class Representative would have failed on a constraint.
--
-- APPLIED 2026-08-16. Found while verifying the columns behind the web
-- console's work-queue counts -- i.e. by reading the schema rather than by
-- anyone hitting it, which is the only reason it was found before a user did.
--
-- 20260816011500 shipped approve_cr_request, which closes the other pending
-- requests in the section rather than leaving them pending forever:
--
--     update cr_requests set status = 'superseded' ... where status = 'pending'
--
-- But the table's CHECK allowed only three values:
--
--     CHECK (status = ANY (ARRAY['pending','approved','rejected']))
--
-- So the whole approval transaction aborted with 23514 the moment TWO students
-- in one section had both applied. That is not an edge case -- it is precisely
-- the situation the one-CR-per-section rule exists to resolve. Approving the
-- first CR in a contested section was the one path guaranteed to fail.
--
-- Confirmed before fixing, by inserting a 'superseded' row directly:
--   ERROR: 23514 new row for relation "cr_requests" violates check constraint
--          "cr_requests_status_check"
--
-- Dropped and recreated rather than added NOT VALID. This WIDENS the allowed
-- set, so every existing row already satisfies it and the validating scan is
-- free -- and a NOT VALID check would have been the wrong tool anyway: it only
-- skips the one-time scan, it still blocks UPDATEs, which is how violating
-- rows become permanently un-editable.
alter table public.cr_requests drop constraint cr_requests_status_check;

alter table public.cr_requests add constraint cr_requests_status_check
  check (status = any (array['pending', 'approved', 'rejected', 'superseded']));

-- VERIFIED after applying, end to end rather than by inspection: two pending
-- requests were created for one section, approve_cr_request() was called as a
-- real super_admin via request.jwt.claims, and the transaction completed --
-- the accepted request became 'approved' and the other became 'superseded'.
-- Both test rows and the CR promotion were then removed; `select count(*) from
-- students where is_cr` returned to its original value of 2.
