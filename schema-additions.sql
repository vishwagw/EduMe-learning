-- ============================================================
--  EDUME LEARNING — Schema Additions (Production)
--  Run this AFTER the base supabase-schema.sql
--  In: Supabase Dashboard → SQL Editor
-- ============================================================

-- ============================================================
--  LESSON PROGRESS  (tracks per-lesson watch progress)
-- ============================================================
CREATE TABLE IF NOT EXISTS lesson_progress (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id          UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  course_id        UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  lesson_id        UUID NOT NULL REFERENCES course_lessons(id) ON DELETE CASCADE,
  completed        BOOLEAN DEFAULT FALSE,
  watch_percent    INTEGER DEFAULT 0 CHECK (watch_percent BETWEEN 0 AND 100),
  last_position_sec INTEGER DEFAULT 0,
  completed_at     TIMESTAMPTZ,
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, lesson_id)
);

ALTER TABLE lesson_progress ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own lesson progress"
  ON lesson_progress FOR ALL USING (user_id = auth.uid());

CREATE TRIGGER lesson_progress_updated_at
  BEFORE UPDATE ON lesson_progress
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
--  ADDITIONAL COURSE COLUMNS  (for production features)
-- ============================================================
ALTER TABLE courses ADD COLUMN IF NOT EXISTS full_description TEXT;
ALTER TABLE courses ADD COLUMN IF NOT EXISTS learning_outcomes TEXT[] DEFAULT '{}';
ALTER TABLE courses ADD COLUMN IF NOT EXISTS requirements TEXT[] DEFAULT '{}';
ALTER TABLE courses ADD COLUMN IF NOT EXISTS original_price NUMERIC(10,2);
ALTER TABLE courses ADD COLUMN IF NOT EXISTS avg_rating NUMERIC(3,2) DEFAULT 0;
ALTER TABLE courses ADD COLUMN IF NOT EXISTS review_count INTEGER DEFAULT 0;
ALTER TABLE courses ADD COLUMN IF NOT EXISTS enrollment_count INTEGER DEFAULT 0;
ALTER TABLE courses ADD COLUMN IF NOT EXISTS lesson_count INTEGER DEFAULT 0;
ALTER TABLE courses ADD COLUMN IF NOT EXISTS has_resources BOOLEAN DEFAULT FALSE;
ALTER TABLE courses ADD COLUMN IF NOT EXISTS is_new BOOLEAN DEFAULT TRUE;

-- ============================================================
--  ADDITIONAL LESSON COLUMNS
-- ============================================================
ALTER TABLE course_lessons ADD COLUMN IF NOT EXISTS pdf_url TEXT;
ALTER TABLE course_lessons ADD COLUMN IF NOT EXISTS text_content TEXT;

-- ============================================================
--  ADDITIONAL PROFILE COLUMNS
-- ============================================================
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS instructor_title TEXT;

-- ============================================================
--  TRIGGERS: auto-update course stats
-- ============================================================

-- Update enrollment_count when enrollment is added
CREATE OR REPLACE FUNCTION update_course_enrollment_count()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE courses
  SET enrollment_count = (SELECT COUNT(*) FROM enrollments WHERE course_id = NEW.course_id AND status = 'active')
  WHERE id = NEW.course_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_enrollment_added
  AFTER INSERT OR UPDATE ON enrollments
  FOR EACH ROW EXECUTE FUNCTION update_course_enrollment_count();

-- Update avg_rating when review is added
CREATE OR REPLACE FUNCTION update_course_rating()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE courses
  SET
    avg_rating   = (SELECT ROUND(AVG(rating)::NUMERIC, 2) FROM reviews WHERE course_id = NEW.course_id),
    review_count = (SELECT COUNT(*) FROM reviews WHERE course_id = NEW.course_id)
  WHERE id = NEW.course_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_review_added
  AFTER INSERT OR UPDATE OR DELETE ON reviews
  FOR EACH ROW EXECUTE FUNCTION update_course_rating();

-- ============================================================
--  STORAGE: signed URL access for enrolled students
-- ============================================================
-- Allow enrolled students to generate signed URLs for private course videos
CREATE POLICY "Enrolled students can read course videos"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'course-videos'
    AND auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM enrollments e
      WHERE e.user_id = auth.uid()
      AND e.status = 'active'
    )
  );

-- Allow enrolled students to read course resources (PDFs)
CREATE POLICY "Enrolled students can read course resources"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'course-resources'
    AND auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM enrollments e
      WHERE e.user_id = auth.uid()
      AND e.status = 'active'
    )
  );

-- Allow instructors to upload to course-videos
CREATE POLICY "Instructors upload course videos"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'course-videos'
    AND auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'instructor'
    )
  );

-- Allow instructors to upload course resources
CREATE POLICY "Instructors upload course resources"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'course-resources'
    AND auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'instructor'
    )
  );

-- Allow instructors to delete their own uploads
CREATE POLICY "Instructors delete own videos"
  ON storage.objects FOR DELETE
  USING (
    (bucket_id = 'course-videos' OR bucket_id = 'course-resources')
    AND auth.uid() IS NOT NULL
    AND owner = auth.uid()
  );
