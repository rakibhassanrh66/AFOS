-- auth_rls_initplan: 114 RLS policies call auth.uid() unwrapped, so Postgres
-- re-evaluates it once PER ROW instead of once per statement. Wrapping in a
-- scalar subquery is Postgres/Supabase's own documented fix -- it does not
-- change which rows are visible/writable, only how often the function call
-- is planned. Mechanical, in-place (ALTER POLICY preserves everything else
-- about the policy), applied across every schema/table at once.
DO $$
DECLARE
  r RECORD;
  new_qual text;
  new_check text;
  alter_sql text;
  n int := 0;
BEGIN
  FOR r IN
    SELECT schemaname, tablename, policyname, qual, with_check
    FROM pg_policies
    WHERE (qual IS NOT NULL AND qual ~ 'auth\.uid\(\)' AND qual !~ '\(select auth\.uid\(\)\)' AND qual !~ '\( SELECT auth\.uid\(\)')
       OR (with_check IS NOT NULL AND with_check ~ 'auth\.uid\(\)' AND with_check !~ '\(select auth\.uid\(\)\)' AND with_check !~ '\( SELECT auth\.uid\(\)')
  LOOP
    new_qual := NULL;
    new_check := NULL;
    IF r.qual IS NOT NULL THEN
      new_qual := regexp_replace(r.qual, 'auth\.uid\(\)', '(select auth.uid())', 'g');
    END IF;
    IF r.with_check IS NOT NULL THEN
      new_check := regexp_replace(r.with_check, 'auth\.uid\(\)', '(select auth.uid())', 'g');
    END IF;

    alter_sql := format('ALTER POLICY %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
    IF new_qual IS NOT NULL THEN
      alter_sql := alter_sql || format(' USING (%s)', new_qual);
    END IF;
    IF new_check IS NOT NULL THEN
      alter_sql := alter_sql || format(' WITH CHECK (%s)', new_check);
    END IF;
    EXECUTE alter_sql;
    n := n + 1;
  END LOOP;
  RAISE NOTICE 'Rewrote % policies', n;
END $$;
