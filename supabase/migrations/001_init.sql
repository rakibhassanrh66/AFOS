-- ══════════════════════════════════════════════════════════════════════
--  AFOS — All Facilities One System
--  Supabase SQL Migration — Run this in Supabase SQL Editor
--  Project: dtsptjallznnvattadlu  |  Region: Seoul
-- ══════════════════════════════════════════════════════════════════════

-- 1. PROFILES (depends on auth.users)
CREATE TABLE IF NOT EXISTS profiles (
  id           UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  student_id   TEXT UNIQUE,
  full_name    TEXT NOT NULL,
  email        TEXT NOT NULL,
  department   TEXT DEFAULT 'CSE',
  semester     INT  DEFAULT 1,
  role         TEXT DEFAULT 'student'
               CHECK (role IN ('student','faculty','admin','club_president','hall_manager','dept_head')),
  avatar_url   TEXT,
  is_verified  BOOL DEFAULT FALSE,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_profile_read"   ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "own_profile_update" ON profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "admin_read_all"     ON profiles FOR SELECT USING (
  EXISTS(SELECT 1 FROM profiles WHERE id=auth.uid() AND role IN ('admin','faculty')));

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION handle_new_user() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO profiles(id,email,full_name) VALUES(NEW.id,NEW.email,COALESCE(NEW.raw_user_meta_data->>'full_name','New User'))
  ON CONFLICT(id) DO NOTHING;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- 2. NOTICES
CREATE TABLE IF NOT EXISTS notices (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  title       TEXT NOT NULL,
  body        TEXT,
  category    TEXT DEFAULT 'GENERAL' CHECK (category IN ('GENERAL','EXAM','EVENT','URGENT')),
  author_name TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE notices ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_read_notices" ON notices FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "admin_write_notices" ON notices FOR INSERT TO authenticated
  WITH CHECK (EXISTS(SELECT 1 FROM profiles WHERE id=auth.uid() AND role IN ('admin','faculty')));

-- 3. SCHEDULE
CREATE TABLE IF NOT EXISTS schedule_slots (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  subject         TEXT NOT NULL,
  subject_code    TEXT,
  teacher_name    TEXT,
  teacher_avatar  TEXT,
  room_number     TEXT,
  building        TEXT,
  start_time      TIME NOT NULL,
  end_time        TIME NOT NULL,
  day_of_week     INT  NOT NULL CHECK (day_of_week BETWEEN 0 AND 5),
  credit_hours    INT  DEFAULT 3,
  department      TEXT NOT NULL,
  semester        INT  NOT NULL,
  is_cancelled    BOOL DEFAULT FALSE,
  cancelled_reason TEXT,
  cancelled_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(subject_code, day_of_week, start_time, department, semester)
);
ALTER TABLE schedule_slots ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_read_schedule" ON schedule_slots FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "admin_write_schedule" ON schedule_slots FOR ALL TO authenticated USING (
  EXISTS(SELECT 1 FROM profiles WHERE id=auth.uid() AND role IN ('admin','faculty')));

CREATE TABLE IF NOT EXISTS exams (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  subject      TEXT,
  subject_code TEXT,
  department   TEXT,
  semester     INT,
  exam_date    DATE,
  start_time   TIME,
  end_time     TIME,
  room         TEXT,
  building     TEXT,
  is_retake    BOOL DEFAULT FALSE,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE exams ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_read_exams" ON exams FOR SELECT TO authenticated USING (TRUE);

-- 4. HALL
CREATE TABLE IF NOT EXISTS hall_applications (
  id                UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  student_id        UUID REFERENCES profiles(id) ON DELETE CASCADE,
  preferred_hall    TEXT,
  preference        TEXT,
  reason            TEXT,
  emergency_contact TEXT,
  status            TEXT DEFAULT 'pending' CHECK (status IN ('pending','reviewing','approved','rejected')),
  assigned_room     TEXT,
  assigned_floor    INT,
  assigned_building TEXT,
  roommate_id       UUID REFERENCES profiles(id),
  rejection_reason  TEXT,
  reviewed_by       UUID,
  reviewed_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE hall_applications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_hall_app"    ON hall_applications FOR SELECT USING (auth.uid() = student_id);
CREATE POLICY "own_hall_insert" ON hall_applications FOR INSERT WITH CHECK (auth.uid() = student_id);
CREATE POLICY "admin_hall_all"  ON hall_applications FOR ALL USING (
  EXISTS(SELECT 1 FROM profiles WHERE id=auth.uid() AND role IN ('admin','hall_manager')));

CREATE TABLE IF NOT EXISTS hall_complaints (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  student_id UUID REFERENCES profiles(id),
  category   TEXT,
  description TEXT,
  photo_url  TEXT,
  status     TEXT DEFAULT 'open',
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE hall_complaints ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_complaints" ON hall_complaints FOR SELECT USING (auth.uid() = student_id);
CREATE POLICY "insert_complaint" ON hall_complaints FOR INSERT WITH CHECK (auth.uid() = student_id);

-- 5. TRANSPORT
CREATE TABLE IF NOT EXISTS transport_routes (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  route_number    TEXT,
  route_name      TEXT,
  departure_times JSONB,
  is_active       BOOL DEFAULT TRUE
);
ALTER TABLE transport_routes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_read_routes" ON transport_routes FOR SELECT TO authenticated USING (TRUE);

CREATE TABLE IF NOT EXISTS transport_stops (
  id                          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  route_id                    UUID REFERENCES transport_routes(id),
  stop_name                   TEXT,
  stop_order                  INT,
  latitude                    FLOAT,
  longitude                   FLOAT,
  estimated_minutes_from_diu  INT
);
ALTER TABLE transport_stops ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_read_stops" ON transport_stops FOR SELECT TO authenticated USING (TRUE);

CREATE TABLE IF NOT EXISTS transport_live_status (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  route_id      UUID REFERENCES transport_routes(id),
  status        TEXT DEFAULT 'on_time' CHECK (status IN ('on_time','delayed','departed','cancelled')),
  delay_minutes INT DEFAULT 0,
  note          TEXT,
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE transport_live_status ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_read_status" ON transport_live_status FOR SELECT TO authenticated USING (TRUE);

-- 6. PAYMENT
CREATE TABLE IF NOT EXISTS payment_records (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  student_id     UUID REFERENCES profiles(id),
  category       TEXT,
  amount         FLOAT,
  currency       TEXT DEFAULT 'BDT',
  status         TEXT DEFAULT 'pending' CHECK (status IN ('pending','paid','failed')),
  transaction_id TEXT,
  payment_date   TIMESTAMPTZ,
  receipt_url    TEXT,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE payment_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_payments" ON payment_records FOR SELECT USING (auth.uid() = student_id);
CREATE POLICY "insert_payment" ON payment_records FOR INSERT WITH CHECK (auth.uid() = student_id);

-- 7. LIBRARY
CREATE TABLE IF NOT EXISTS books (
  id               UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  title            TEXT,
  author           TEXT,
  isbn             TEXT UNIQUE,
  publisher        TEXT,
  year             INT,
  category         TEXT,
  cover_url        TEXT,
  total_copies     INT DEFAULT 1,
  available_copies INT DEFAULT 1,
  shelf_location   TEXT,
  description      TEXT
);
ALTER TABLE books ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_read_books" ON books FOR SELECT TO authenticated USING (TRUE);

CREATE TABLE IF NOT EXISTS borrowed_books (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  student_id     UUID REFERENCES profiles(id),
  book_id        UUID REFERENCES books(id),
  borrowed_date  DATE,
  due_date       DATE,
  return_date    DATE,
  renewals_count INT  DEFAULT 0,
  fine_amount    FLOAT DEFAULT 0,
  status         TEXT DEFAULT 'borrowed' CHECK (status IN ('borrowed','returned','overdue'))
);
ALTER TABLE borrowed_books ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_borrowed" ON borrowed_books FOR SELECT USING (auth.uid() = student_id);
CREATE POLICY "update_borrowed" ON borrowed_books FOR UPDATE USING (auth.uid() = student_id);

-- 8. LOST & FOUND
CREATE TABLE IF NOT EXISTS lost_found_posts (
  id                 UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  poster_id          UUID REFERENCES profiles(id),
  type               TEXT CHECK (type IN ('lost','found')),
  title              TEXT,
  description        TEXT,
  category           TEXT,
  location_text      TEXT,
  photo_url          TEXT,
  contact_preference TEXT,
  contact_value      TEXT,
  status             TEXT DEFAULT 'active' CHECK (status IN ('active','claimed','returned')),
  created_at         TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE lost_found_posts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_read_lf"    ON lost_found_posts FOR SELECT TO authenticated USING (status != 'deleted');
CREATE POLICY "own_lf_manage"   ON lost_found_posts FOR ALL USING (auth.uid() = poster_id);
CREATE POLICY "auth_insert_lf"  ON lost_found_posts FOR INSERT TO authenticated WITH CHECK (auth.uid() = poster_id);

-- 9. CLUBS
CREATE TABLE IF NOT EXISTS clubs (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name         TEXT,
  category     TEXT,
  tagline      TEXT,
  description  TEXT,
  banner_url   TEXT,
  logo_url     TEXT,
  president_id UUID REFERENCES profiles(id),
  contact_email TEXT,
  founded_year INT,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE clubs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_read_clubs" ON clubs FOR SELECT TO authenticated USING (TRUE);

CREATE TABLE IF NOT EXISTS club_members (
  id        UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  club_id   UUID REFERENCES clubs(id) ON DELETE CASCADE,
  member_id UUID REFERENCES profiles(id),
  role      TEXT DEFAULT 'member',
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(club_id, member_id)
);
ALTER TABLE club_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_read_members" ON club_members FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "own_membership"    ON club_members FOR ALL USING (auth.uid() = member_id);

CREATE TABLE IF NOT EXISTS club_events (
  id               UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  club_id          UUID REFERENCES clubs(id),
  title            TEXT,
  description      TEXT,
  event_date       TIMESTAMPTZ,
  venue            TEXT,
  max_seats        INT,
  registered_count INT DEFAULT 0,
  photo_url        TEXT,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE club_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_read_events" ON club_events FOR SELECT TO authenticated USING (TRUE);

CREATE TABLE IF NOT EXISTS event_registrations (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  event_id     UUID REFERENCES club_events(id),
  student_id   UUID REFERENCES profiles(id),
  registered_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(event_id, student_id)
);
ALTER TABLE event_registrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_reg" ON event_registrations FOR ALL USING (auth.uid() = student_id);

-- 10. MENTORSHIP
CREATE TABLE IF NOT EXISTS mentors (
  id                   UUID REFERENCES profiles(id) PRIMARY KEY,
  title                TEXT,
  bio                  TEXT,
  specializations      TEXT[],
  research_interests   TEXT,
  publications_count   INT DEFAULT 0,
  average_rating       FLOAT DEFAULT 0,
  is_accepting_bookings BOOL DEFAULT TRUE
);
ALTER TABLE mentors ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_read_mentors" ON mentors FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "own_mentor_profile" ON mentors FOR ALL USING (auth.uid() = id);

CREATE TABLE IF NOT EXISTS mentor_availability (
  id        UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  mentor_id UUID REFERENCES mentors(id),
  day_of_week INT,
  start_time TIME,
  end_time   TIME,
  is_booked  BOOL DEFAULT FALSE
);
ALTER TABLE mentor_availability ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_read_avail" ON mentor_availability FOR SELECT TO authenticated USING (TRUE);

CREATE TABLE IF NOT EXISTS mentorship_bookings (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  student_id      UUID REFERENCES profiles(id),
  mentor_id       UUID REFERENCES mentors(id),
  topic           TEXT,
  session_type    TEXT,
  scheduled_at    TIMESTAMPTZ,
  location_or_link TEXT,
  status          TEXT DEFAULT 'pending' CHECK (status IN ('pending','confirmed','completed','rejected')),
  student_notes   TEXT,
  faculty_notes   TEXT,
  rating          INT CHECK (rating BETWEEN 1 AND 5),
  created_at      TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE mentorship_bookings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_booking"    ON mentorship_bookings FOR SELECT USING (auth.uid() = student_id OR auth.uid() = mentor_id);
CREATE POLICY "insert_booking" ON mentorship_bookings FOR INSERT WITH CHECK (auth.uid() = student_id);
CREATE POLICY "update_booking" ON mentorship_bookings FOR UPDATE USING (auth.uid() = mentor_id OR auth.uid() = student_id);

-- 11. EXAM SEATS
CREATE TABLE IF NOT EXISTS exam_seat_assignments (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  exam_id      UUID REFERENCES exams(id),
  student_id   UUID REFERENCES profiles(id),
  room_number  TEXT,
  building     TEXT,
  floor_number INT,
  seat_number  TEXT,
  row_label    TEXT,
  is_retake    BOOL DEFAULT FALSE,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(exam_id, student_id)
);
ALTER TABLE exam_seat_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_seat"    ON exam_seat_assignments FOR SELECT USING (auth.uid() = student_id);
CREATE POLICY "admin_seats" ON exam_seat_assignments FOR ALL USING (
  EXISTS(SELECT 1 FROM profiles WHERE id=auth.uid() AND role='admin'));

-- 12. DEPT CHAT
CREATE TABLE IF NOT EXISTS dept_channels (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  department   TEXT,
  channel_name TEXT,
  description  TEXT,
  is_admin_only BOOL DEFAULT FALSE,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(department, channel_name)
);
ALTER TABLE dept_channels ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_read_channels" ON dept_channels FOR SELECT TO authenticated USING (TRUE);

-- Seed default channels per department
INSERT INTO dept_channels(department,channel_name,description) VALUES
  ('CSE','general','General discussion'),('CSE','notices','Official notices'),
  ('CSE','academic','Academic help'),('CSE','events','Events & activities'),
  ('EEE','general','General discussion'),('EEE','notices','Official notices'),
  ('BBA','general','General discussion'),('BBA','notices','Official notices')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS dept_messages (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  channel_id   UUID REFERENCES dept_channels(id) ON DELETE CASCADE,
  sender_id    UUID REFERENCES profiles(id),
  content      TEXT,
  message_type TEXT DEFAULT 'text' CHECK (message_type IN ('text','image','file')),
  file_url     TEXT,
  file_name    TEXT,
  is_pinned    BOOL DEFAULT FALSE,
  pinned_by    UUID,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE dept_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "dept_members_read" ON dept_messages FOR SELECT TO authenticated USING (
  EXISTS(SELECT 1 FROM profiles p JOIN dept_channels c ON p.department=c.department
    WHERE p.id=auth.uid() AND c.id=channel_id));
CREATE POLICY "members_send" ON dept_messages FOR INSERT WITH CHECK (auth.uid() = sender_id);
CREATE POLICY "admin_pin"    ON dept_messages FOR UPDATE USING (
  EXISTS(SELECT 1 FROM profiles WHERE id=auth.uid() AND role IN ('admin','faculty')));

-- 13. VR-ID ACCESS LOG
CREATE TABLE IF NOT EXISTS vr_access_log (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  scanned_user_id UUID REFERENCES profiles(id),
  scanned_by_id   UUID REFERENCES profiles(id),
  location_note   TEXT,
  scanned_at      TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE vr_access_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_log"        ON vr_access_log FOR SELECT USING (auth.uid() = scanned_user_id);
CREATE POLICY "auth_can_scan"  ON vr_access_log FOR INSERT WITH CHECK (auth.uid() = scanned_by_id);

-- 14. NOTIFICATIONS
CREATE TABLE IF NOT EXISTS user_notifications (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id         UUID REFERENCES profiles(id),
  title           TEXT,
  body            TEXT,
  category        TEXT,
  is_read         BOOL DEFAULT FALSE,
  deep_link_route TEXT,
  received_at     TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE user_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_notifs"     ON user_notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "system_insert"  ON user_notifications FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "own_update"     ON user_notifications FOR UPDATE USING (auth.uid() = user_id);

-- 15. FEEDBACK
CREATE TABLE IF NOT EXISTS feedback (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id     UUID REFERENCES profiles(id),
  category    TEXT,
  message     TEXT,
  app_version TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE feedback ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_feedback" ON feedback FOR INSERT WITH CHECK (auth.uid() = user_id);
