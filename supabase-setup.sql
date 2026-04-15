-- ==========================================
-- Supabase Setup: Tables + RLS Policies
-- Run this in your Supabase SQL Editor
-- ==========================================

-- 1. PROFILES TABLE
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  full_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('teacher', 'student')) DEFAULT 'student',
  class_name TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Students can read their own profile
CREATE POLICY "students_read_own_profile" ON profiles
  FOR SELECT USING (auth.uid() = id);

-- Teachers can read all profiles
CREATE POLICY "teachers_read_all_profiles" ON profiles
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'teacher')
  );

-- Users can insert their own profile (on signup)
CREATE POLICY "users_insert_own_profile" ON profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

-- Teachers can insert profiles (for creating students)
CREATE POLICY "teachers_insert_profiles" ON profiles
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'teacher')
  );

-- Teachers can update any profile
CREATE POLICY "teachers_update_profiles" ON profiles
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'teacher')
  );

-- Teachers can delete student profiles
CREATE POLICY "teachers_delete_profiles" ON profiles
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'teacher')
  );

-- 2. STUDENT PROGRESS TABLE
CREATE TABLE student_progress (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  unit_id INTEGER NOT NULL CHECK (unit_id BETWEEN 1 AND 6),
  content_page INTEGER DEFAULT 0,
  quiz_score INTEGER DEFAULT 0,
  quiz_total INTEGER DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, unit_id)
);

ALTER TABLE student_progress ENABLE ROW LEVEL SECURITY;

CREATE POLICY "students_manage_own_progress" ON student_progress
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "teachers_read_all_progress" ON student_progress
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'teacher')
  );

-- 3. QUIZ ATTEMPTS TABLE
CREATE TABLE quiz_attempts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  unit_id INTEGER NOT NULL,
  mode TEXT NOT NULL CHECK (mode IN ('practice', 'exam')),
  correct_count INTEGER NOT NULL,
  total_count INTEGER NOT NULL,
  score_percent INTEGER NOT NULL,
  completed_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE quiz_attempts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "students_manage_own_attempts" ON quiz_attempts
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "teachers_read_all_attempts" ON quiz_attempts
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'teacher')
  );

-- 4. GAME SCORES TABLE
CREATE TABLE game_scores (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  game_type TEXT NOT NULL,
  score INTEGER NOT NULL,
  max_score INTEGER NOT NULL,
  score_percent INTEGER NOT NULL,
  completed_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE game_scores ENABLE ROW LEVEL SECURITY;

CREATE POLICY "students_manage_own_scores" ON game_scores
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "teachers_read_all_scores" ON game_scores
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'teacher')
  );

-- 5. ACTIVITY LOG TABLE
CREATE TABLE activity_log (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE activity_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "students_insert_own_activity" ON activity_log
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "students_read_own_activity" ON activity_log
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "teachers_read_all_activity" ON activity_log
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'teacher')
  );

-- 6. INDEXES FOR PERFORMANCE
CREATE INDEX idx_student_progress_user ON student_progress(user_id);
CREATE INDEX idx_quiz_attempts_user ON quiz_attempts(user_id);
CREATE INDEX idx_game_scores_user ON game_scores(user_id);
CREATE INDEX idx_activity_log_user ON activity_log(user_id);
CREATE INDEX idx_activity_log_created ON activity_log(created_at DESC);

-- 7. TRIGGER: Auto-update updated_at on student_progress
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER student_progress_updated
  BEFORE UPDATE ON student_progress
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ==========================================
-- SEED: Create the teacher account
-- After running this, go to Supabase Auth dashboard
-- and create a user with the teacher's email/password.
-- Then run this INSERT with the user's UUID:
-- ==========================================
-- INSERT INTO profiles (id, email, full_name, role)
-- VALUES ('YOUR-TEACHER-UUID-HERE', 'teacher@example.com', 'הרב ברק', 'teacher');

-- ==========================================
-- STORAGE: Podcasts bucket (public)
-- ==========================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('podcasts', 'podcasts', true)
ON CONFLICT (id) DO NOTHING;

-- Allow public read access to podcast files
CREATE POLICY "public_podcast_read" ON storage.objects
  FOR SELECT USING (bucket_id = 'podcasts');

-- Allow authenticated users (teachers) to upload
CREATE POLICY "teachers_upload_podcasts" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'podcasts'
    AND EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'teacher')
  );

-- Allow teachers to delete podcast files
CREATE POLICY "teachers_delete_podcasts" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'podcasts'
    AND EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'teacher')
  );

-- ==========================================
-- FEEDBACK TABLE (bug reports / suggestions from students)
-- ==========================================
CREATE TABLE IF NOT EXISTS feedback (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  user_name TEXT,
  user_email TEXT,
  category TEXT NOT NULL CHECK (category IN ('bug','suggestion','content','other')),
  message TEXT NOT NULL CHECK (char_length(message) BETWEEN 3 AND 2000),
  page_url TEXT,
  user_agent TEXT,
  status TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new','read','resolved','archived')),
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE feedback ENABLE ROW LEVEL SECURITY;

-- Anyone (anon + authenticated) can insert feedback
CREATE POLICY "anyone_can_submit_feedback" ON feedback
  FOR INSERT WITH CHECK (true);

-- Only teachers can read feedback
CREATE POLICY "teachers_read_feedback" ON feedback
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'teacher')
  );

-- Only teachers can update (mark as read/resolved)
CREATE POLICY "teachers_update_feedback" ON feedback
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'teacher')
  );

-- Only teachers can delete feedback
CREATE POLICY "teachers_delete_feedback" ON feedback
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'teacher')
  );

CREATE INDEX IF NOT EXISTS idx_feedback_created ON feedback(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_feedback_status ON feedback(status);
