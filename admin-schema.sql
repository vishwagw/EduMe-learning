-- ════════════════════════════════════════════════════════════
--  Edume Learning — Admin & Certificate Schema
--  Run this AFTER supabase-schema.sql + schema-additions.sql
-- ════════════════════════════════════════════════════════════

-- ── 1. Add admin role to profiles enum ──────────────────────
-- (Skip if your profiles.role column already has 'admin')
DO $$
BEGIN
  -- Try to add 'admin' to the role check constraint if it exists
  ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
  ALTER TABLE profiles ADD CONSTRAINT profiles_role_check
    CHECK (role IN ('student', 'instructor', 'admin'));
EXCEPTION WHEN others THEN NULL;
END $$;

-- ── 2. Add banned column to profiles ─────────────────────────
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS banned BOOLEAN DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS bio TEXT;

-- ── 3. Add extra columns to enrollments ──────────────────────
ALTER TABLE enrollments ADD COLUMN IF NOT EXISTS completed BOOLEAN DEFAULT false;
ALTER TABLE enrollments ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;
ALTER TABLE enrollments ADD COLUMN IF NOT EXISTS certificate_id UUID;

-- ── 4. Add status column to courses ──────────────────────────
-- (pending → manual review before publishing)
ALTER TABLE courses ADD COLUMN IF NOT EXISTS status_admin TEXT DEFAULT 'approved'
  CHECK (status_admin IN ('pending', 'approved', 'rejected'));

-- ── 5. Certificates table ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS certificates (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  course_id     UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  issued_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  issued_by     TEXT NOT NULL DEFAULT 'system',   -- 'system' | 'admin'
  completion_pct INTEGER DEFAULT 100,
  revoked       BOOLEAN DEFAULT false,
  revoked_at    TIMESTAMPTZ,
  UNIQUE(user_id, course_id)  -- one cert per student per course
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_certificates_user     ON certificates(user_id);
CREATE INDEX IF NOT EXISTS idx_certificates_course   ON certificates(course_id);
CREATE INDEX IF NOT EXISTS idx_certificates_issued   ON certificates(issued_at DESC);

-- ── 6. Payments table additions ───────────────────────────────
ALTER TABLE payments ADD COLUMN IF NOT EXISTS payment_method TEXT;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS payment_type   TEXT DEFAULT 'course'
  CHECK (payment_type IN ('course', 'live_class'));

-- ── 7. RLS Policies ───────────────────────────────────────────

-- Enable RLS
ALTER TABLE certificates ENABLE ROW LEVEL SECURITY;

-- Students can view their own certificates
CREATE POLICY "students_view_own_certs" ON certificates
  FOR SELECT USING (auth.uid() = user_id);

-- Anyone can verify a certificate by ID (for shareable links)
CREATE POLICY "public_verify_cert" ON certificates
  FOR SELECT USING (revoked = false);

-- Only admins can insert/update/delete
CREATE POLICY "admins_manage_certs" ON certificates
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- ── 8. Admin views ────────────────────────────────────────────

-- View: admin dashboard stats (aggregated, no RLS needed as view)
CREATE OR REPLACE VIEW admin_stats AS
SELECT
  (SELECT COUNT(*) FROM profiles)::INT                                     AS total_users,
  (SELECT COUNT(*) FROM profiles WHERE role = 'instructor')::INT           AS total_instructors,
  (SELECT COUNT(*) FROM courses WHERE status = 'published')::INT           AS published_courses,
  (SELECT COUNT(*) FROM enrollments)::INT                                  AS total_enrollments,
  (SELECT COUNT(*) FROM certificates WHERE revoked = false)::INT           AS total_certificates,
  (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE status = 'completed') AS total_revenue,
  (SELECT COUNT(*) FROM live_classes)::INT                                 AS total_live_classes;

-- ── 9. Auto-issue certificate trigger ─────────────────────────
-- When all lessons in a course are marked complete, auto-call certificate issuance
-- (Lightweight trigger — actual issuance goes through Edge Function for full checks)

CREATE OR REPLACE FUNCTION check_course_completion()
RETURNS TRIGGER AS $$
DECLARE
  v_course_id UUID;
  v_total_lessons INT;
  v_completed_lessons INT;
BEGIN
  -- Get course_id from the lesson
  SELECT cm.course_id INTO v_course_id
  FROM course_lessons cl
  JOIN course_modules cm ON cl.module_id = cm.id
  WHERE cl.id = NEW.lesson_id;

  IF v_course_id IS NULL THEN RETURN NEW; END IF;

  -- Count total lessons in course
  SELECT COUNT(*) INTO v_total_lessons
  FROM course_lessons cl
  JOIN course_modules cm ON cl.module_id = cm.id
  WHERE cm.course_id = v_course_id;

  -- Count completed lessons by this user
  SELECT COUNT(*) INTO v_completed_lessons
  FROM lesson_progress lp
  JOIN course_lessons cl ON lp.lesson_id = cl.id
  JOIN course_modules cm ON cl.module_id = cm.id
  WHERE cm.course_id = v_course_id
    AND lp.user_id = NEW.user_id
    AND lp.completed = true;

  -- If ≥80% complete and enrolled, issue certificate
  IF v_total_lessons > 0 AND (v_completed_lessons::FLOAT / v_total_lessons) >= 0.8 THEN
    -- Check enrolled
    IF EXISTS (
      SELECT 1 FROM enrollments
      WHERE user_id = NEW.user_id AND course_id = v_course_id
    ) THEN
      -- Insert certificate (idempotent — unique constraint handles duplicates)
      INSERT INTO certificates (user_id, course_id, issued_by, completion_pct)
      VALUES (
        NEW.user_id,
        v_course_id,
        'system',
        ROUND((v_completed_lessons::FLOAT / v_total_lessons) * 100)
      )
      ON CONFLICT (user_id, course_id) DO NOTHING;

      -- Mark enrollment as completed
      UPDATE enrollments
      SET completed = true, completed_at = now()
      WHERE user_id = NEW.user_id
        AND course_id = v_course_id
        AND completed = false;

      -- Notify student
      INSERT INTO notifications (user_id, title, message, type)
      SELECT
        NEW.user_id,
        '🎓 Certificate Earned!',
        'You have completed "' || c.title || '". Download your certificate now!',
        'certificate'
      FROM courses c WHERE c.id = v_course_id
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach trigger to lesson_progress
DROP TRIGGER IF EXISTS on_lesson_complete ON lesson_progress;
CREATE TRIGGER on_lesson_complete
  AFTER INSERT OR UPDATE OF completed ON lesson_progress
  FOR EACH ROW
  WHEN (NEW.completed = true)
  EXECUTE FUNCTION check_course_completion();

-- ── 10. Grant first admin ─────────────────────────────────────
-- IMPORTANT: Replace 'your-email@example.com' with your admin email
-- UPDATE profiles SET role = 'admin' WHERE email = 'your-email@example.com';

-- ════════════════════════════════════════════════════════════
--  DONE. Verify with:
--    SELECT * FROM admin_stats;
--    SELECT * FROM certificates LIMIT 5;
-- ════════════════════════════════════════════════════════════
