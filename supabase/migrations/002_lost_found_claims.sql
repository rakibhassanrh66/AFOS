-- ══════════════════════════════════════════════════════════════════════
--  AFOS — Lost & Found claim workflow
--  Run after 001_init.sql
-- ══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS lost_found_claims (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  post_id      UUID REFERENCES lost_found_posts(id) ON DELETE CASCADE,
  claimant_id  UUID REFERENCES profiles(id),
  message      TEXT,
  status       TEXT DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected')),
  created_at   TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE lost_found_claims ENABLE ROW LEVEL SECURITY;

-- Claimant can see their own claims; poster can see claims on their posts
CREATE POLICY "read_own_or_poster_claims" ON lost_found_claims FOR SELECT USING (
  auth.uid() = claimant_id
  OR auth.uid() = (SELECT poster_id FROM lost_found_posts WHERE id = post_id)
);

-- Any authenticated user (except the poster) can file a claim on an active post
CREATE POLICY "insert_claim" ON lost_found_claims FOR INSERT TO authenticated WITH CHECK (
  auth.uid() = claimant_id
  AND auth.uid() <> (SELECT poster_id FROM lost_found_posts WHERE id = post_id)
);

-- Only the post owner can accept/reject a claim on their post
CREATE POLICY "poster_updates_claim" ON lost_found_claims FOR UPDATE USING (
  auth.uid() = (SELECT poster_id FROM lost_found_posts WHERE id = post_id)
);

-- When a claim is accepted, mark the post as returned and reject any other
-- pending claims on the same post so it drops out of the feed everywhere.
CREATE OR REPLACE FUNCTION handle_claim_accepted() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.status = 'accepted' AND OLD.status IS DISTINCT FROM 'accepted' THEN
    UPDATE lost_found_posts SET status = 'returned' WHERE id = NEW.post_id;
    UPDATE lost_found_claims SET status = 'rejected'
      WHERE post_id = NEW.post_id AND id <> NEW.id AND status = 'pending';
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS on_claim_accepted ON lost_found_claims;
CREATE TRIGGER on_claim_accepted AFTER UPDATE ON lost_found_claims
  FOR EACH ROW EXECUTE FUNCTION handle_claim_accepted();
