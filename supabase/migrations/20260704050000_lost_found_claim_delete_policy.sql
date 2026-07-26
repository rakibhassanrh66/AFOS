-- =====================================================================
--  AFOS — Lost & Found: let either side delete a claim record
--
--  No DELETE policy existed on lost_found_claims at all — the only way a
--  claim record ever disappeared was cascading from a full post deletion.
--  Requirement: after handover, "either side can close, archive, or
--  permanently delete the record" — claimant needs to withdraw a pending
--  claim, and either side needs to clear an accepted/rejected claim once
--  resolved, without requiring the poster to delete the whole post.
-- =====================================================================

CREATE POLICY "claimant_or_poster_delete_claim" ON lost_found_claims FOR DELETE USING (
  auth.uid() = claimant_id
  OR auth.uid() = (SELECT poster_id FROM lost_found_posts WHERE id = post_id)
);
