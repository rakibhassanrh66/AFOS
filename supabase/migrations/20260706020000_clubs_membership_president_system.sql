-- Clubs system: real DIU club roster, membership request/approval,
-- officer-post (secretary/vice_president/president) request/approval, all
-- gated through super_admin — a student could previously write their own
-- club_members row directly with ANY role value (the old `own_membership`
-- ALL policy had no column restriction), which would have been a real
-- privilege-escalation path now that `role='president'` actually grants
-- club-wide broadcast power. Fixed by removing that policy and only
-- allowing writes via the request+approval flow below.

-- `clubs`/`club_events` had SELECT-only policies before this — nobody,
-- not even super_admin, had any write path to them via the API.
CREATE POLICY super_admin_manage_clubs ON clubs
  FOR ALL
  USING (get_my_profile_role() = 'super_admin')
  WITH CHECK (get_my_profile_role() = 'super_admin');

DROP POLICY IF EXISTS own_membership ON club_members;

CREATE POLICY super_admin_manage_club_members ON club_members
  FOR ALL
  USING (get_my_profile_role() = 'super_admin')
  WITH CHECK (get_my_profile_role() = 'super_admin');

-- Leaving a club is still fully self-service — no approval needed to quit.
CREATE POLICY own_membership_leave ON club_members
  FOR DELETE
  USING (auth.uid() = member_id);

CREATE TABLE club_membership_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id uuid NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  rejection_reason text,
  reviewed_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (club_id, student_id)
);

ALTER TABLE club_membership_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY own_club_membership_request_insert ON club_membership_requests
  FOR INSERT WITH CHECK (auth.uid() = student_id);

CREATE POLICY own_club_membership_request_read ON club_membership_requests
  FOR SELECT USING (auth.uid() = student_id);

CREATE POLICY super_admin_manage_club_membership_requests ON club_membership_requests
  FOR ALL
  USING (get_my_profile_role() = 'super_admin')
  WITH CHECK (get_my_profile_role() = 'super_admin');

-- Officer-post requests — only an existing (approved) member can request
-- to become secretary/vice_president/president of their own club.
CREATE TABLE club_post_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id uuid NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  member_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  requested_role text NOT NULL CHECK (requested_role IN ('secretary', 'vice_president', 'president')),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  rejection_reason text,
  reviewed_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE club_post_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY own_club_post_request_insert ON club_post_requests
  FOR INSERT
  WITH CHECK (
    auth.uid() = member_id
    AND EXISTS (SELECT 1 FROM club_members cm WHERE cm.club_id = club_post_requests.club_id AND cm.member_id = auth.uid())
  );

CREATE POLICY own_club_post_request_read ON club_post_requests
  FOR SELECT USING (auth.uid() = member_id);

CREATE POLICY super_admin_manage_club_post_requests ON club_post_requests
  FOR ALL
  USING (get_my_profile_role() = 'super_admin')
  WITH CHECK (get_my_profile_role() = 'super_admin');

-- Real DIU club roster (central + departmental), sourced from
-- clubs.daffodilvarsity.edu.bd and studentshub.daffodilvarsity.edu.bd —
-- excludes the two obvious placeholder/test entries found on that page
-- ("System Test", "Test Club DIU"). No president assigned yet; super_admin
-- assigns one via an approved club_post_requests 'president' request.
INSERT INTO clubs (name, category, tagline) VALUES
  ('DIU Computer and Programming Club', 'Tech', 'The oldest and largest club at DIU'),
  ('DIU Robotics Club', 'Tech', 'The biggest and most extensive tech club at DIU'),
  ('DIU Software Engineering Club', 'Tech', 'DIUSEC — for aspiring software engineers'),
  ('Data Science Club', 'Tech', 'Exploring data science and analytics'),
  ('DIU Cyber Security Club', 'Tech', 'Security research and awareness'),
  ('DIU Girls'' Computer Programming Club', 'Tech', 'Programming community for women at DIU'),
  ('DIU CIS Club', 'Tech', 'Computing & Information Systems'),
  ('Daffodil AI Club', 'Tech', 'Artificial intelligence enthusiasts'),
  ('DIU AIRIS', 'Tech', 'AI Research And Innovation Society'),
  ('DIU ITM Club', 'Tech', 'Information Technology & Management'),
  ('DIU Information & Communication Engineering Club', 'Tech', 'Electronics & Telecommunication'),
  ('Chess Club of DIU', 'Sports', 'Winner of many inter-university tournaments'),
  ('DIU Karate-Do Club', 'Sports', 'Martial arts training and competition'),
  ('Daffodil Running Community', 'Sports', 'Running events and fitness'),
  ('DIU Air Rover Scout', 'Sports', 'Scouting and adventure activities'),
  ('DIU BNCC', 'Sports', 'Bangladesh National Cadet Corps unit'),
  ('DIU Cultural Club', 'Cultural', 'Promoting arts and culture at DIU'),
  ('DIU Band Society', 'Cultural', 'A vibrant music community'),
  ('DIU Film Society', 'Cultural', 'Filmmaking and cinema appreciation'),
  ('DIU Readers'' Club', 'Cultural', 'For book lovers and discussion'),
  ('DIU English Literary Club', 'Cultural', 'Literature and language'),
  ('All Stars Daffodil', 'Cultural', 'Drama and performing arts'),
  ('DIU Creative Park', 'Cultural', 'Multimedia & creative technology'),
  ('DIU Photographic Society', 'Cultural', 'Photography community at DIU'),
  ('DIU Voluntary Service Club', 'Volunteer', 'Community service initiatives'),
  ('DIU Blood Donors Club', 'Volunteer', 'Organizing blood donation drives'),
  ('Rotaract Club of DIU', 'Volunteer', 'International community service'),
  ('DIU Change Together Club', 'Volunteer', 'Social activism and change'),
  ('Daffodil Prothom Alo Bondhushava', 'Volunteer', 'Social and voluntary service'),
  ('DIU Youth Engagement and Support (YES) Club', 'Volunteer', 'Youth support programs'),
  ('DIU Business and Education Club', 'Business', 'Business and education initiatives'),
  ('DIU Marketing Club', 'Business', 'Marketing skills and networking'),
  ('DIU HR Club', 'Business', 'Human resource development'),
  ('DIU Finance Club', 'Business', 'Finance and investment education'),
  ('DIU Investment Club', 'Business', 'Investment strategy and learning'),
  ('DIU e-Business Club', 'Business', 'E-commerce and digital business'),
  ('Daffodil Entrepreneurs'' Club', 'Business', 'For aspiring entrepreneurs'),
  ('Society for Young Business Leaders', 'Business', 'SYBL — leadership development'),
  ('Social Business Students'' Forum', 'Business', 'Social entrepreneurship'),
  ('Real Estate Club - DIU', 'Business', 'Real estate industry insights'),
  ('SkillUp Club (HRDI)', 'Business', 'Human Resource Development Institute'),
  ('DIU Debating Club', 'Academic', 'DIUDC — competitive debate'),
  ('DIU Model United Nations Association', 'Academic', 'MUN conferences and diplomacy'),
  ('Daffodil International University Research Society', 'Academic', 'DIURS — research culture'),
  ('Mathematical Society', 'Academic', 'DIUMS — mathematics enthusiasts'),
  ('DIU Agricultural Science Club', 'Academic', 'Agricultural science community'),
  ('DIU Study Abroad Forum', 'Academic', 'Guidance for studying abroad'),
  ('Daffodil Moot Court Society', 'Academic', 'DMCS — for law students'),
  ('DIU Public Health Club', 'Academic', 'Public health awareness'),
  ('DIU Textile Club', 'Academic', 'Textile Engineering department'),
  ('DIU Civil Engineering Club', 'Academic', 'Civil Engineering department'),
  ('DIU NFE Club', 'Academic', 'Nutrition and Food Engineering'),
  ('DIU EEE Club', 'Academic', 'Electrical & Electronic Engineering'),
  ('Pharmacia Club - DIU', 'Academic', 'Pharmacy department'),
  ('DIU Communication Club', 'Academic', 'Journalism, Media & Communication');
