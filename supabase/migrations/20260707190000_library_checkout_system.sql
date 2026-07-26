-- borrowed_books had zero INSERT policy anywhere and books had zero write
-- policy at all — students could search the catalogue and see their own
-- existing borrows/renew them, but nobody (not even staff) could ever
-- actually issue a book to a student. A real library requires physical
-- handover/sign-out, so this is a staff/admin-tier action, not
-- student self-service.
create policy admin_manage_borrowed_books on borrowed_books for all
  using (get_my_profile_role() = ANY (ARRAY['admin','staff','dept_admin','super_admin']))
  with check (get_my_profile_role() = ANY (ARRAY['admin','staff','dept_admin','super_admin']));

create policy admin_manage_books on books for all
  using (get_my_profile_role() = ANY (ARRAY['admin','staff','dept_admin','super_admin']))
  with check (get_my_profile_role() = ANY (ARRAY['admin','staff','dept_admin','super_admin']));
