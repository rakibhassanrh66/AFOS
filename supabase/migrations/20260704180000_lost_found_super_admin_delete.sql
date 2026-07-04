-- Scoped to super_admin only, per explicit product decision — not all
-- admin roles. lost_found_claims.post_id already has ON DELETE CASCADE
-- (002_lost_found_claims.sql / 20260704050000), so no separate claims
-- policy is needed — deleting a post auto-removes its claims.
CREATE POLICY "super_admin_delete_lf" ON lost_found_posts FOR DELETE
  USING (get_my_profile_role() = 'super_admin');
