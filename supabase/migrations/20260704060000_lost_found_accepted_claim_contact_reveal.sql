-- =====================================================================
--  AFOS — Lost & Found: reveal contact info only between matched parties
--
--  Requirement: once a claim is accepted, poster and claimant need to be
--  able to reach each other to arrange handover ("allow secure
--  communication"). Checked current profiles RLS: nothing lets a student
--  view another arbitrary student's profile (phone/email) — a claimant
--  had no way to see the poster's contact info at all, and vice versa.
--  Scope this narrowly: a profile becomes visible to the other party
--  ONLY while there's an accepted claim connecting them, not generally.
-- =====================================================================

CREATE POLICY "accepted_claim_parties_read_profiles" ON profiles FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM lost_found_claims c
    JOIN lost_found_posts p ON p.id = c.post_id
    WHERE c.status = 'accepted'
      AND (
        (c.claimant_id = auth.uid() AND p.poster_id = profiles.id)
        OR (p.poster_id = auth.uid() AND c.claimant_id = profiles.id)
      )
  )
);
