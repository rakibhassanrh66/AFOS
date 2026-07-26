-- unindexed_foreign_keys: 84 FK columns in `public` with no covering index,
-- meaning every FK-driven join/delete-cascade check does a full table scan
-- instead of an index lookup. Mechanical, generated from pg_constraint
-- itself rather than hand-typed (matches the same safe pattern as the
-- auth.uid() RLS pass) -- only `public` schema tables; auth.*/storage.*
-- are Supabase-managed internals and deliberately left untouched.
DO $$
DECLARE
  r RECORD;
  cols text;
  idx_name text;
  n int := 0;
BEGIN
  FOR r IN
    SELECT c.conrelid::regclass::text AS table_name, c.conname,
           (SELECT array_agg(a.attname ORDER BY k.ord)
              FROM unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
              JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum) AS col_arr
    FROM pg_constraint c
    WHERE c.contype = 'f'
      AND c.connamespace = 'public'::regnamespace
      AND NOT EXISTS (
        SELECT 1 FROM pg_index i
        WHERE i.indrelid = c.conrelid
          AND (i.indkey::int2[])[0:cardinality(c.conkey)-1] = c.conkey::int2[]
      )
  LOOP
    cols := array_to_string(r.col_arr, ', ');
    idx_name := 'idx_' || replace(r.table_name, '.', '_') || '_' || array_to_string(r.col_arr, '_');
    -- Postgres identifier limit is 63 bytes; fall back to a constraint-based
    -- name for the rare long one rather than silently truncating/colliding.
    IF length(idx_name) > 63 THEN
      idx_name := 'idx_' || r.conname;
    END IF;
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %s (%s)', idx_name, r.table_name, cols);
    n := n + 1;
  END LOOP;
  RAISE NOTICE 'Created % indexes', n;
END $$;
