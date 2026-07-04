-- =====================================================================
--  AFOS — Notices: ownership tracking + manage (update/delete) policies
--
--  notices had INSERT + SELECT policies only — no UPDATE/DELETE at all,
--  and no author_id column, so there was no way to scope "can this
--  teacher edit their own notice" via RLS. Adding author_id (set
--  automatically via trigger, not client-supplied, so it can't be
--  spoofed) plus manage policies: admin/dept_admin/super_admin can
--  manage any notice; a teacher can only manage their own.
-- =====================================================================

ALTER TABLE notices ADD COLUMN IF NOT EXISTS author_id uuid REFERENCES profiles(id);

CREATE OR REPLACE FUNCTION set_notice_author()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.author_id := auth.uid();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_notice_author_trigger ON notices;
CREATE TRIGGER set_notice_author_trigger
  BEFORE INSERT ON notices
  FOR EACH ROW EXECUTE FUNCTION set_notice_author();

CREATE POLICY "manage_own_or_admin_notices" ON notices FOR UPDATE USING (
  author_id = auth.uid()
  OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = ANY (ARRAY['admin','dept_admin','super_admin']))
);

CREATE POLICY "delete_own_or_admin_notices" ON notices FOR DELETE USING (
  author_id = auth.uid()
  OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = ANY (ARRAY['admin','dept_admin','super_admin']))
);
