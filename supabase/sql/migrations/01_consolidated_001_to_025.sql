-- ==============================================================================
-- 01: รวม 001–025 (รันหลัง schema.sql)
--     ต้องมี branches, profiles, work_logs, is_admin, user_branch_ids, set_updated_at
--     ถ้า error ที่ ALTER TYPE ... ADD VALUE ให้รันคำสั่งนั้นแยกครั้งเดียว แล้วรันส่วนที่เหลือ
-- ==============================================================================

-- ========== 001: admin_note ใน cross_branch_transfers ==========
ALTER TABLE cross_branch_transfers ADD COLUMN IF NOT EXISTS admin_note TEXT;
COMMENT ON COLUMN cross_branch_transfers.admin_note IS 'หมายเหตุจากผู้ดูแลระบบ (อนุมัติ/ปฏิเสธ)';

-- ========== 002: seed break_rules ==========
INSERT INTO break_rules (min_staff, max_staff, concurrent_breaks)
SELECT 1, 5, 1 WHERE NOT EXISTS (SELECT 1 FROM break_rules LIMIT 1)
UNION ALL SELECT 6, 10, 2 WHERE NOT EXISTS (SELECT 1 FROM break_rules LIMIT 1)
UNION ALL SELECT 11, 15, 3 WHERE NOT EXISTS (SELECT 1 FROM break_rules LIMIT 1);

-- ========== 003: Realtime ==========
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE holidays; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE shift_swaps; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE cross_branch_transfers; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE duty_assignments; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE monthly_roster_status; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE monthly_roster; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE break_logs; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ========== 004: ล็อกอินด้วยชื่อผู้ใช้ ==========
CREATE OR REPLACE FUNCTION public.get_email_for_login(login_name TEXT)
RETURNS TEXT LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT email FROM profiles
  WHERE active = true
    AND (
      (display_name IS NOT NULL AND LOWER(trim(display_name)) = LOWER(trim(login_name)))
      OR LOWER(trim(email)) = LOWER(trim(login_name))
    )
  LIMIT 1;
$$;
COMMENT ON FUNCTION public.get_email_for_login(TEXT) IS 'ใช้สำหรับหน้าเข้าสู่ระบบ: แปลงชื่อผู้ใช้/อีเมล เป็น email ใน profiles';
GRANT EXECUTE ON FUNCTION public.get_email_for_login(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.get_email_for_login(TEXT) TO authenticated;

-- ========== 005: Admin ไม่ใช่พนักงาน (INSERT เฉพาะ staff/instructor) ==========
CREATE OR REPLACE FUNCTION is_staff_or_instructor()
RETURNS BOOLEAN AS $$ SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('instructor', 'staff')); $$ LANGUAGE sql SECURITY DEFINER STABLE;

DROP POLICY IF EXISTS work_logs_insert ON work_logs;
CREATE POLICY work_logs_insert ON work_logs FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND is_staff_or_instructor());
DROP POLICY IF EXISTS break_logs_insert ON break_logs;
CREATE POLICY break_logs_insert ON break_logs FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND is_staff_or_instructor());
DROP POLICY IF EXISTS holidays_insert ON holidays;
CREATE POLICY holidays_insert ON holidays FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND is_staff_or_instructor());
DROP POLICY IF EXISTS shift_swaps_insert ON shift_swaps;
CREATE POLICY shift_swaps_insert ON shift_swaps FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND is_staff_or_instructor());
DROP POLICY IF EXISTS transfers_insert ON cross_branch_transfers;
CREATE POLICY transfers_insert ON cross_branch_transfers FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND is_staff_or_instructor());

-- ========== 006: โมดูลเว็บที่ดูแล (websites, website_assignments) ==========
CREATE TABLE IF NOT EXISTS websites (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  name TEXT NOT NULL, alias TEXT NOT NULL, url TEXT, description TEXT,
  is_active BOOLEAN DEFAULT true, created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(branch_id, alias)
);
CREATE INDEX IF NOT EXISTS idx_websites_branch ON websites(branch_id);
CREATE INDEX IF NOT EXISTS idx_websites_active ON websites(is_active);
COMMENT ON TABLE websites IS 'เว็บที่ดูแล — ผูกกับแผนก (branch)';

CREATE TABLE IF NOT EXISTS website_assignments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  website_id UUID NOT NULL REFERENCES websites(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  is_primary BOOLEAN NOT NULL DEFAULT false, role_on_website TEXT DEFAULT 'viewer',
  created_at TIMESTAMPTZ DEFAULT now(), UNIQUE(website_id, user_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_website_assignments_one_primary_per_user ON website_assignments(user_id) WHERE (is_primary = true);
CREATE INDEX IF NOT EXISTS idx_website_assignments_user ON website_assignments(user_id);
CREATE INDEX IF NOT EXISTS idx_website_assignments_website ON website_assignments(website_id);
COMMENT ON TABLE website_assignments IS 'การมอบหมายว่า user ไหนดูแล website ไหน — ต่อ user มีเว็บหลักได้ 1 เว็บ';

ALTER TABLE websites ENABLE ROW LEVEL SECURITY;
ALTER TABLE website_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS websites_select ON websites;
DROP POLICY IF EXISTS websites_all ON websites;
CREATE POLICY websites_select ON websites FOR SELECT TO authenticated USING (is_admin() OR id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid()));
CREATE POLICY websites_insert ON websites FOR INSERT TO authenticated WITH CHECK (is_admin());
CREATE POLICY websites_update ON websites FOR UPDATE TO authenticated USING (is_admin());
CREATE POLICY websites_delete ON websites FOR DELETE TO authenticated USING (is_admin());

DROP POLICY IF EXISTS website_assignments_select ON website_assignments;
DROP POLICY IF EXISTS website_assignments_insert ON website_assignments;
DROP POLICY IF EXISTS website_assignments_update ON website_assignments;
DROP POLICY IF EXISTS website_assignments_delete ON website_assignments;
CREATE POLICY website_assignments_select ON website_assignments FOR SELECT TO authenticated USING (is_admin() OR user_id = auth.uid());
CREATE POLICY website_assignments_insert ON website_assignments FOR INSERT TO authenticated WITH CHECK (is_admin());
CREATE POLICY website_assignments_update ON website_assignments FOR UPDATE TO authenticated USING (is_admin());
CREATE POLICY website_assignments_delete ON website_assignments FOR DELETE TO authenticated USING (is_admin());

CREATE OR REPLACE FUNCTION set_primary_website(p_user_id UUID, p_website_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_user_id IS NULL OR p_website_id IS NULL THEN RETURN; END IF;
  UPDATE website_assignments SET is_primary = false WHERE user_id = p_user_id;
  UPDATE website_assignments SET is_primary = true WHERE user_id = p_user_id AND website_id = p_website_id;
END;
$$;
COMMENT ON FUNCTION set_primary_website(UUID, UUID) IS 'ตั้งเว็บหลักของ user (เฉพาะ admin เรียกผ่าน service)';
GRANT EXECUTE ON FUNCTION set_primary_website(UUID, UUID) TO authenticated;

DROP TRIGGER IF EXISTS websites_updated_at ON websites;
CREATE TRIGGER websites_updated_at BEFORE UPDATE ON websites FOR EACH ROW EXECUTE PROCEDURE set_updated_at();

-- ========== 007: แผนกประจำ my_branch_id + RLS ==========
CREATE OR REPLACE FUNCTION my_branch_id()
RETURNS UUID AS $$ SELECT p.default_branch_id FROM profiles p WHERE p.id = auth.uid() AND p.role IN ('instructor', 'staff') AND p.default_branch_id IS NOT NULL LIMIT 1; $$ LANGUAGE sql SECURITY DEFINER STABLE;
COMMENT ON FUNCTION my_branch_id() IS 'แผนกประจำของ current user (instructor/staff); admin ได้ null';

ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_instructor_staff_must_have_branch;
ALTER TABLE profiles ADD CONSTRAINT profiles_instructor_staff_must_have_branch CHECK (
  (role IN ('instructor', 'staff') AND default_branch_id IS NOT NULL) OR (role NOT IN ('instructor', 'staff'))
);

UPDATE profiles SET default_branch_id = (SELECT id FROM branches WHERE active = true ORDER BY name LIMIT 1)
WHERE role IN ('instructor', 'staff') AND default_branch_id IS NULL AND EXISTS (SELECT 1 FROM branches WHERE active = true LIMIT 1);

DROP POLICY IF EXISTS monthly_roster_select ON monthly_roster;
CREATE POLICY monthly_roster_select ON monthly_roster FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND branch_id = my_branch_id()));
DROP POLICY IF EXISTS roster_status_select ON monthly_roster_status;
CREATE POLICY roster_status_select ON monthly_roster_status FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND branch_id = my_branch_id()));

DROP POLICY IF EXISTS work_logs_select ON work_logs;
CREATE POLICY work_logs_select ON work_logs FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND branch_id = my_branch_id()));
DROP POLICY IF EXISTS work_logs_insert ON work_logs;
CREATE POLICY work_logs_insert ON work_logs FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND is_staff_or_instructor() AND (is_admin() OR branch_id = my_branch_id()));

DROP POLICY IF EXISTS break_rules_select ON break_rules;
CREATE POLICY break_rules_select ON break_rules FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND (branch_id = my_branch_id() OR branch_id IS NULL)));
DROP POLICY IF EXISTS break_logs_select ON break_logs;
CREATE POLICY break_logs_select ON break_logs FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND branch_id = my_branch_id()));
DROP POLICY IF EXISTS break_logs_insert ON break_logs;
CREATE POLICY break_logs_insert ON break_logs FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND is_staff_or_instructor() AND (is_admin() OR branch_id = my_branch_id()));

DROP POLICY IF EXISTS holiday_quotas_select ON holiday_quotas;
CREATE POLICY holiday_quotas_select ON holiday_quotas FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND branch_id = my_branch_id()));
DROP POLICY IF EXISTS holidays_select ON holidays;
CREATE POLICY holidays_select ON holidays FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND branch_id = my_branch_id()));
DROP POLICY IF EXISTS holidays_insert ON holidays;
CREATE POLICY holidays_insert ON holidays FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND is_staff_or_instructor() AND (is_admin() OR branch_id = my_branch_id()));

DROP POLICY IF EXISTS shift_swaps_select ON shift_swaps;
CREATE POLICY shift_swaps_select ON shift_swaps FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND branch_id = my_branch_id()));
DROP POLICY IF EXISTS shift_swaps_insert ON shift_swaps;
CREATE POLICY shift_swaps_insert ON shift_swaps FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND is_staff_or_instructor() AND (is_admin() OR branch_id = my_branch_id()));

DROP POLICY IF EXISTS transfers_select ON cross_branch_transfers;
CREATE POLICY transfers_select ON cross_branch_transfers FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND (from_branch_id = my_branch_id() OR to_branch_id = my_branch_id())));
DROP POLICY IF EXISTS transfers_insert ON cross_branch_transfers;
CREATE POLICY transfers_insert ON cross_branch_transfers FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND is_staff_or_instructor());

DROP POLICY IF EXISTS duty_roles_select ON duty_roles;
CREATE POLICY duty_roles_select ON duty_roles FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND branch_id = my_branch_id()));
DROP POLICY IF EXISTS duty_assignments_select ON duty_assignments;
CREATE POLICY duty_assignments_select ON duty_assignments FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND branch_id = my_branch_id()));

DROP POLICY IF EXISTS tasks_select ON tasks;
CREATE POLICY tasks_select ON tasks FOR SELECT TO authenticated USING (
  is_admin() OR assignee_id = auth.uid() OR created_by = auth.uid() OR (my_branch_id() IS NOT NULL AND (branch_id = my_branch_id() OR branch_id IS NULL) AND is_instructor_or_admin())
);
DROP POLICY IF EXISTS schedule_cards_select ON schedule_cards;
CREATE POLICY schedule_cards_select ON schedule_cards FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND (branch_id = my_branch_id() OR branch_id IS NULL)));
DROP POLICY IF EXISTS group_links_select ON group_links;
CREATE POLICY group_links_select ON group_links FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND (branch_id = my_branch_id() OR branch_id IS NULL)));
DROP POLICY IF EXISTS password_vault_select ON password_vault;
CREATE POLICY password_vault_select ON password_vault FOR SELECT TO authenticated USING (
  is_admin() OR branch_scope IS NULL OR branch_scope = 'all' OR (my_branch_id() IS NOT NULL AND branch_scope = my_branch_id()::text)
);

-- ========== 008: user_group (INSTRUCTOR/STAFF) ==========
CREATE OR REPLACE FUNCTION my_user_group()
RETURNS TEXT AS $$ SELECT CASE p.role WHEN 'instructor' THEN 'INSTRUCTOR' WHEN 'staff' THEN 'STAFF' ELSE NULL END FROM profiles p WHERE p.id = auth.uid() LIMIT 1; $$ LANGUAGE sql SECURITY DEFINER STABLE;
COMMENT ON FUNCTION my_user_group() IS 'กลุ่มผู้ใช้ปัจจุบัน: INSTRUCTOR หรือ STAFF; admin ได้ NULL';

ALTER TABLE work_logs ADD COLUMN IF NOT EXISTS user_group TEXT;
ALTER TABLE work_logs DROP CONSTRAINT IF EXISTS work_logs_user_group_check;
ALTER TABLE work_logs ADD CONSTRAINT work_logs_user_group_check CHECK (user_group IS NULL OR user_group IN ('INSTRUCTOR', 'STAFF'));
ALTER TABLE break_logs ADD COLUMN IF NOT EXISTS user_group TEXT;
ALTER TABLE break_logs DROP CONSTRAINT IF EXISTS break_logs_user_group_check;
ALTER TABLE break_logs ADD CONSTRAINT break_logs_user_group_check CHECK (user_group IS NULL OR user_group IN ('INSTRUCTOR', 'STAFF'));
ALTER TABLE holidays ADD COLUMN IF NOT EXISTS user_group TEXT;
ALTER TABLE holidays DROP CONSTRAINT IF EXISTS holidays_user_group_check;
ALTER TABLE holidays ADD CONSTRAINT holidays_user_group_check CHECK (user_group IS NULL OR user_group IN ('INSTRUCTOR', 'STAFF'));
ALTER TABLE holiday_quotas ADD COLUMN IF NOT EXISTS user_group TEXT;
ALTER TABLE holiday_quotas DROP CONSTRAINT IF EXISTS holiday_quotas_user_group_check;
ALTER TABLE holiday_quotas ADD CONSTRAINT holiday_quotas_user_group_check CHECK (user_group IS NULL OR user_group IN ('INSTRUCTOR', 'STAFF'));
ALTER TABLE break_rules ADD COLUMN IF NOT EXISTS user_group TEXT;
ALTER TABLE break_rules DROP CONSTRAINT IF EXISTS break_rules_user_group_check;
ALTER TABLE break_rules ADD CONSTRAINT break_rules_user_group_check CHECK (user_group IS NULL OR user_group IN ('INSTRUCTOR', 'STAFF'));

UPDATE work_logs w SET user_group = CASE p.role WHEN 'instructor' THEN 'INSTRUCTOR' WHEN 'staff' THEN 'STAFF' ELSE 'STAFF' END FROM profiles p WHERE w.user_id = p.id AND w.user_group IS NULL;
UPDATE work_logs SET user_group = 'STAFF' WHERE user_group IS NULL;
UPDATE break_logs b SET user_group = CASE p.role WHEN 'instructor' THEN 'INSTRUCTOR' WHEN 'staff' THEN 'STAFF' ELSE 'STAFF' END FROM profiles p WHERE b.user_id = p.id AND b.user_group IS NULL;
UPDATE break_logs SET user_group = 'STAFF' WHERE user_group IS NULL;
UPDATE holidays h SET user_group = CASE p.role WHEN 'instructor' THEN 'INSTRUCTOR' WHEN 'staff' THEN 'STAFF' ELSE 'STAFF' END FROM profiles p WHERE h.user_id = p.id AND h.user_group IS NULL;
UPDATE holidays SET user_group = 'STAFF' WHERE user_group IS NULL;
UPDATE holiday_quotas SET user_group = 'STAFF' WHERE user_group IS NULL;
UPDATE break_rules SET user_group = 'STAFF' WHERE user_group IS NULL;

ALTER TABLE holiday_quotas DROP CONSTRAINT IF EXISTS holiday_quotas_branch_id_shift_id_quota_date_key;
ALTER TABLE holiday_quotas ALTER COLUMN user_group SET NOT NULL;
ALTER TABLE holiday_quotas DROP CONSTRAINT IF EXISTS holiday_quotas_user_group_check;
ALTER TABLE holiday_quotas ADD CONSTRAINT holiday_quotas_user_group_check CHECK (user_group IN ('INSTRUCTOR', 'STAFF'));
ALTER TABLE holiday_quotas ADD CONSTRAINT holiday_quotas_branch_shift_date_group_key UNIQUE (branch_id, shift_id, quota_date, user_group);
ALTER TABLE break_rules DROP CONSTRAINT IF EXISTS break_rules_user_group_check;
ALTER TABLE break_rules ADD CONSTRAINT break_rules_user_group_check CHECK (user_group IN ('INSTRUCTOR', 'STAFF'));
ALTER TABLE break_rules ALTER COLUMN user_group SET NOT NULL;
ALTER TABLE work_logs ALTER COLUMN user_group SET NOT NULL;
ALTER TABLE break_logs ALTER COLUMN user_group SET NOT NULL;
ALTER TABLE holidays ALTER COLUMN user_group SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_work_logs_branch_shift_date_group ON work_logs(branch_id, shift_id, logical_date, user_group);
CREATE INDEX IF NOT EXISTS idx_work_logs_user_date_group ON work_logs(user_id, logical_date, user_group);
CREATE INDEX IF NOT EXISTS idx_break_logs_branch_shift_date_group ON break_logs(branch_id, shift_id, break_date, user_group);
CREATE INDEX IF NOT EXISTS idx_break_logs_user_date_group ON break_logs(user_id, break_date, user_group);
CREATE INDEX IF NOT EXISTS idx_holidays_branch_shift_date_group ON holidays(branch_id, shift_id, holiday_date, user_group);
CREATE INDEX IF NOT EXISTS idx_holidays_user_date_group ON holidays(user_id, holiday_date, user_group);
CREATE INDEX IF NOT EXISTS idx_holiday_quotas_branch_shift_date_group ON holiday_quotas(branch_id, shift_id, quota_date, user_group);
CREATE INDEX IF NOT EXISTS idx_break_rules_branch_shift_group ON break_rules(branch_id, shift_id, user_group);

DROP POLICY IF EXISTS work_logs_select ON work_logs;
CREATE POLICY work_logs_select ON work_logs FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND branch_id = my_branch_id() AND user_group = my_user_group()));
DROP POLICY IF EXISTS work_logs_insert ON work_logs;
CREATE POLICY work_logs_insert ON work_logs FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND is_staff_or_instructor() AND (is_admin() OR branch_id = my_branch_id()) AND user_group = my_user_group());
DROP POLICY IF EXISTS break_rules_select ON break_rules;
CREATE POLICY break_rules_select ON break_rules FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND (branch_id = my_branch_id() OR branch_id IS NULL) AND user_group = my_user_group()));
DROP POLICY IF EXISTS break_rules_all ON break_rules;
CREATE POLICY break_rules_all ON break_rules FOR ALL TO authenticated USING (is_admin());
DROP POLICY IF EXISTS break_logs_select ON break_logs;
CREATE POLICY break_logs_select ON break_logs FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND branch_id = my_branch_id() AND user_group = my_user_group()));
DROP POLICY IF EXISTS break_logs_insert ON break_logs;
CREATE POLICY break_logs_insert ON break_logs FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND is_staff_or_instructor() AND (is_admin() OR branch_id = my_branch_id()) AND user_group = my_user_group());
DROP POLICY IF EXISTS holiday_quotas_select ON holiday_quotas;
CREATE POLICY holiday_quotas_select ON holiday_quotas FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND branch_id = my_branch_id() AND user_group = my_user_group()));
DROP POLICY IF EXISTS holiday_quotas_all ON holiday_quotas;
CREATE POLICY holiday_quotas_all ON holiday_quotas FOR ALL TO authenticated USING (is_admin());
DROP POLICY IF EXISTS holidays_select ON holidays;
CREATE POLICY holidays_select ON holidays FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND branch_id = my_branch_id() AND user_group = my_user_group()));
DROP POLICY IF EXISTS holidays_insert ON holidays;
CREATE POLICY holidays_insert ON holidays FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND is_staff_or_instructor() AND (is_admin() OR branch_id = my_branch_id()) AND user_group = my_user_group());
DROP POLICY IF EXISTS holidays_update ON holidays;
CREATE POLICY holidays_update ON holidays FOR UPDATE TO authenticated USING (is_admin() OR user_id = auth.uid());

-- ========== 009: handle_new_user (รุ่นแรก — จะถูก 012 แทนที่) ==========
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE first_branch_id UUID;
BEGIN
  SELECT id INTO first_branch_id FROM public.branches ORDER BY (active IS NOT TRUE), name LIMIT 1;
  INSERT INTO public.profiles (id, email, display_name, role, default_branch_id)
  VALUES (NEW.id, NEW.email, COALESCE(NEW.raw_user_meta_data->>'name', NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)), 'staff', first_branch_id)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- ========== 010: enum instructor_head ==========
-- ถ้า error: "ALTER TYPE ... ADD VALUE cannot run inside a transaction block"
-- ให้รันคำสั่งด้านล่างแยกครั้งเดียว (Execute) แล้ว commit แล้วค่อยรันส่วนที่เหลือของไฟล์
ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'instructor_head';

-- ========== 011: บทบาท instructor_head ==========
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_instructor_staff_must_have_branch;
ALTER TABLE profiles ADD CONSTRAINT profiles_instructor_staff_must_have_branch CHECK (
  (role IN ('instructor', 'staff', 'instructor_head') AND default_branch_id IS NOT NULL) OR (role NOT IN ('instructor', 'staff', 'instructor_head'))
);

CREATE OR REPLACE FUNCTION my_branch_id()
RETURNS UUID AS $$ SELECT p.default_branch_id FROM profiles p WHERE p.id = auth.uid() AND p.role IN ('instructor', 'staff', 'instructor_head') AND p.default_branch_id IS NOT NULL LIMIT 1; $$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION is_staff_or_instructor()
RETURNS BOOLEAN AS $$ SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('instructor', 'staff', 'instructor_head')); $$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION is_instructor_or_admin()
RETURNS BOOLEAN AS $$ SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'instructor', 'instructor_head')); $$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION is_instructor_head()
RETURNS BOOLEAN AS $$ SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'instructor_head'); $$ LANGUAGE sql SECURITY DEFINER STABLE;

DROP POLICY IF EXISTS profiles_select ON profiles;
CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated USING (
  is_admin() OR id = auth.uid() OR is_instructor_or_admin() OR (is_instructor_head() AND (id = auth.uid() OR (default_branch_id = my_branch_id() AND role IN ('instructor', 'staff'))))
);
DROP POLICY IF EXISTS profiles_update_self ON profiles;
CREATE POLICY profiles_update_self ON profiles FOR UPDATE TO authenticated USING (id = auth.uid());
DROP POLICY IF EXISTS profiles_update_branch_head ON profiles;
CREATE POLICY profiles_update_branch_head ON profiles FOR UPDATE TO authenticated USING (is_admin() OR (is_instructor_head() AND default_branch_id = my_branch_id() AND role IN ('instructor', 'staff')));

CREATE OR REPLACE FUNCTION my_user_group()
RETURNS TEXT AS $$ SELECT CASE p.role WHEN 'instructor' THEN 'INSTRUCTOR' WHEN 'instructor_head' THEN 'INSTRUCTOR' WHEN 'staff' THEN 'STAFF' ELSE NULL END FROM profiles p WHERE p.id = auth.uid() LIMIT 1; $$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ========== 012: handle_new_user (รุ่นสุดท้าย) + trigger ==========
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE first_branch_id UUID;
BEGIN
  SELECT id INTO first_branch_id FROM public.branches ORDER BY (active IS NOT TRUE), name LIMIT 1;
  INSERT INTO public.profiles (id, email, display_name, role, default_branch_id)
  VALUES (NEW.id, NEW.email, COALESCE(NEW.raw_user_meta_data->>'name', NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)), 'staff', first_branch_id)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- ========== 013: group_links website_id + RLS หัวหน้า ==========
ALTER TABLE group_links ADD COLUMN IF NOT EXISTS website_id UUID REFERENCES websites(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_group_links_website ON group_links(website_id);
COMMENT ON COLUMN group_links.website_id IS 'เว็บที่กลุ่มงานนี้สังกัด (อยู่ในสาขา branch_id)';

DROP POLICY IF EXISTS group_links_all ON group_links;
DROP POLICY IF EXISTS group_links_select ON group_links;
CREATE POLICY group_links_select ON group_links FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND (branch_id = my_branch_id() OR branch_id IS NULL)));
CREATE POLICY group_links_insert ON group_links FOR INSERT TO authenticated WITH CHECK (is_admin() OR (is_instructor_head() AND branch_id = my_branch_id()));
CREATE POLICY group_links_update ON group_links FOR UPDATE TO authenticated USING (is_admin() OR (is_instructor_head() AND branch_id = my_branch_id()));
CREATE POLICY group_links_delete ON group_links FOR DELETE TO authenticated USING (is_admin() OR (is_instructor_head() AND branch_id = my_branch_id()));

-- ========== 014: holiday_booking_config ==========
CREATE TABLE IF NOT EXISTS holiday_booking_config (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), target_year_month TEXT NOT NULL UNIQUE,
  open_from DATE NOT NULL, open_until DATE NOT NULL, max_days_per_person INT NOT NULL DEFAULT 4,
  created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT holiday_booking_config_dates_check CHECK (open_until >= open_from)
);
COMMENT ON TABLE holiday_booking_config IS 'เปิดจองวันหยุดต่อเดือน: target_year_month = yyyy-MM, open_from/open_until = ช่วงที่พนักงานจองได้';
CREATE INDEX IF NOT EXISTS idx_holiday_booking_config_target ON holiday_booking_config(target_year_month);
ALTER TABLE holiday_booking_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS holiday_booking_config_select ON holiday_booking_config;
CREATE POLICY holiday_booking_config_select ON holiday_booking_config FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS holiday_booking_config_all ON holiday_booking_config;
CREATE POLICY holiday_booking_config_all ON holiday_booking_config FOR ALL TO authenticated USING (is_admin());

-- ========== 015: หัวหน้าอนุมัติวันหยุด ==========
DROP POLICY IF EXISTS holidays_update ON holidays;
CREATE POLICY holidays_update ON holidays FOR UPDATE TO authenticated USING (is_admin() OR user_id = auth.uid() OR (is_instructor_head() AND branch_id = my_branch_id()));

-- ========== 016: เว็บที่ดูแล — หัวหน้าผู้สอน ==========
DROP POLICY IF EXISTS websites_select ON websites;
CREATE POLICY websites_select ON websites FOR SELECT TO authenticated USING (
  is_admin() OR id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid()) OR (is_instructor_head() AND branch_id = my_branch_id())
);
DROP POLICY IF EXISTS websites_insert ON websites;
CREATE POLICY websites_insert ON websites FOR INSERT TO authenticated WITH CHECK (is_admin() OR (is_instructor_head() AND branch_id = my_branch_id()));
DROP POLICY IF EXISTS websites_update ON websites;
CREATE POLICY websites_update ON websites FOR UPDATE TO authenticated USING (is_admin() OR (is_instructor_head() AND branch_id = my_branch_id()));
DROP POLICY IF EXISTS websites_delete ON websites;
CREATE POLICY websites_delete ON websites FOR DELETE TO authenticated USING (is_admin() OR (is_instructor_head() AND branch_id = my_branch_id()));

DROP POLICY IF EXISTS website_assignments_select ON website_assignments;
CREATE POLICY website_assignments_select ON website_assignments FOR SELECT TO authenticated USING (
  is_admin() OR user_id = auth.uid() OR (is_instructor_head() AND website_id IN (SELECT id FROM websites WHERE branch_id = my_branch_id()))
);
DROP POLICY IF EXISTS website_assignments_insert ON website_assignments;
CREATE POLICY website_assignments_insert ON website_assignments FOR INSERT TO authenticated WITH CHECK (is_admin() OR (is_instructor_head() AND website_id IN (SELECT id FROM websites WHERE branch_id = my_branch_id())));
DROP POLICY IF EXISTS website_assignments_update ON website_assignments;
CREATE POLICY website_assignments_update ON website_assignments FOR UPDATE TO authenticated USING (is_admin() OR (is_instructor_head() AND website_id IN (SELECT id FROM websites WHERE branch_id = my_branch_id())));
DROP POLICY IF EXISTS website_assignments_delete ON website_assignments;
CREATE POLICY website_assignments_delete ON website_assignments FOR DELETE TO authenticated USING (is_admin() OR (is_instructor_head() AND website_id IN (SELECT id FROM websites WHERE branch_id = my_branch_id())));

CREATE OR REPLACE FUNCTION set_primary_website(p_user_id UUID, p_website_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_user_id IS NULL OR p_website_id IS NULL THEN RETURN; END IF;
  IF NOT is_admin() AND is_instructor_head() THEN
    IF (SELECT default_branch_id FROM profiles WHERE id = p_user_id) IS DISTINCT FROM my_branch_id() THEN RAISE EXCEPTION 'ไม่สามารถตั้งเว็บหลักให้ผู้ใช้ในสาขาอื่นได้'; END IF;
    IF (SELECT branch_id FROM websites WHERE id = p_website_id) IS DISTINCT FROM my_branch_id() THEN RAISE EXCEPTION 'เว็บไม่อยู่ในสาขาของคุณ'; END IF;
  ELSIF NOT is_admin() AND NOT is_instructor_head() THEN RAISE EXCEPTION 'ไม่มีสิทธิ์ตั้งเว็บหลัก'; END IF;
  UPDATE website_assignments SET is_primary = false WHERE user_id = p_user_id;
  UPDATE website_assignments SET is_primary = true WHERE user_id = p_user_id AND website_id = p_website_id;
END;
$$;

-- ========== 017: รอบสลับกะ + การมอบหมาย ==========
CREATE TABLE IF NOT EXISTS shift_swap_rounds (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  start_date DATE NOT NULL, end_date DATE NOT NULL, pairs_per_day INT NOT NULL DEFAULT 2,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published')),
  created_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE, created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_shift_swap_rounds_branch ON shift_swap_rounds(branch_id);
CREATE INDEX IF NOT EXISTS idx_shift_swap_rounds_dates ON shift_swap_rounds(start_date, end_date);
COMMENT ON TABLE shift_swap_rounds IS 'รอบสลับกะรายเดือน — หัวหน้า/แอดมินสร้างและเผยแพร่';

CREATE TABLE IF NOT EXISTS shift_swap_assignments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), round_id UUID NOT NULL REFERENCES shift_swap_rounds(id) ON DELETE CASCADE,
  swap_date DATE NOT NULL, user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  from_shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE, to_shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
  partner_id UUID REFERENCES profiles(id) ON DELETE SET NULL, created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(round_id, swap_date, user_id)
);
CREATE INDEX IF NOT EXISTS idx_shift_swap_assignments_round ON shift_swap_assignments(round_id);
CREATE INDEX IF NOT EXISTS idx_shift_swap_assignments_user ON shift_swap_assignments(user_id);
CREATE INDEX IF NOT EXISTS idx_shift_swap_assignments_date ON shift_swap_assignments(swap_date);
COMMENT ON TABLE shift_swap_assignments IS 'รายการสลับกะต่อคนต่อวัน — สุ่มหรือหัวหน้าแมนนวล';

ALTER TABLE shift_swap_rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE shift_swap_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS shift_swap_rounds_select ON shift_swap_rounds;
CREATE POLICY shift_swap_rounds_select ON shift_swap_rounds FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS shift_swap_rounds_insert ON shift_swap_rounds;
CREATE POLICY shift_swap_rounds_insert ON shift_swap_rounds FOR INSERT TO authenticated WITH CHECK (is_admin() OR (is_instructor_head() AND branch_id = my_branch_id()));
DROP POLICY IF EXISTS shift_swap_rounds_update ON shift_swap_rounds;
CREATE POLICY shift_swap_rounds_update ON shift_swap_rounds FOR UPDATE TO authenticated USING (is_admin() OR (is_instructor_head() AND branch_id = my_branch_id()));
DROP POLICY IF EXISTS shift_swap_rounds_delete ON shift_swap_rounds;
CREATE POLICY shift_swap_rounds_delete ON shift_swap_rounds FOR DELETE TO authenticated USING (is_admin() OR (is_instructor_head() AND branch_id = my_branch_id()));

DROP POLICY IF EXISTS shift_swap_assignments_select ON shift_swap_assignments;
CREATE POLICY shift_swap_assignments_select ON shift_swap_assignments FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS shift_swap_assignments_insert ON shift_swap_assignments;
CREATE POLICY shift_swap_assignments_insert ON shift_swap_assignments FOR INSERT TO authenticated WITH CHECK (is_admin() OR (is_instructor_head() AND EXISTS (SELECT 1 FROM shift_swap_rounds r WHERE r.id = round_id AND r.branch_id = my_branch_id())));
DROP POLICY IF EXISTS shift_swap_assignments_update ON shift_swap_assignments;
CREATE POLICY shift_swap_assignments_update ON shift_swap_assignments FOR UPDATE TO authenticated USING (is_admin() OR (is_instructor_head() AND EXISTS (SELECT 1 FROM shift_swap_rounds r WHERE r.id = round_id AND r.branch_id = my_branch_id())));
DROP POLICY IF EXISTS shift_swap_assignments_delete ON shift_swap_assignments;
CREATE POLICY shift_swap_assignments_delete ON shift_swap_assignments FOR DELETE TO authenticated USING (is_admin() OR (is_instructor_head() AND EXISTS (SELECT 1 FROM shift_swap_rounds r WHERE r.id = round_id AND r.branch_id = my_branch_id())));

DROP TRIGGER IF EXISTS shift_swap_rounds_updated_at ON shift_swap_rounds;
CREATE TRIGGER shift_swap_rounds_updated_at BEFORE UPDATE ON shift_swap_rounds FOR EACH ROW EXECUTE PROCEDURE set_updated_at();

-- ========== 018: shift_swap_rounds website_id ==========
ALTER TABLE shift_swap_rounds ADD COLUMN IF NOT EXISTS website_id UUID REFERENCES websites(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_shift_swap_rounds_website ON shift_swap_rounds(website_id);
COMMENT ON COLUMN shift_swap_rounds.website_id IS 'null = ทั้งสาขา; มีค่า = เฉพาะเว็บที่เลือก';

-- ========== 019: file_vault ==========
CREATE TABLE IF NOT EXISTS file_vault (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  website_id UUID REFERENCES websites(id) ON DELETE SET NULL, file_path TEXT NOT NULL, file_name TEXT NOT NULL, topic TEXT,
  uploaded_by UUID REFERENCES profiles(id) ON DELETE SET NULL, created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(file_path)
);
CREATE INDEX IF NOT EXISTS idx_file_vault_branch ON file_vault(branch_id);
CREATE INDEX IF NOT EXISTS idx_file_vault_website ON file_vault(website_id);
CREATE INDEX IF NOT EXISTS idx_file_vault_created ON file_vault(created_at DESC);
ALTER TABLE file_vault ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS file_vault_select ON file_vault;
CREATE POLICY file_vault_select ON file_vault FOR SELECT TO authenticated USING (is_admin() OR (branch_id IN (SELECT user_branch_ids(auth.uid()))));
DROP POLICY IF EXISTS file_vault_insert ON file_vault;
CREATE POLICY file_vault_insert ON file_vault FOR INSERT TO authenticated WITH CHECK (is_admin() OR (is_instructor_head() AND branch_id = my_branch_id()));
DROP POLICY IF EXISTS file_vault_update ON file_vault;
CREATE POLICY file_vault_update ON file_vault FOR UPDATE TO authenticated USING (is_admin() OR (is_instructor_head() AND branch_id = my_branch_id()));
DROP POLICY IF EXISTS file_vault_delete ON file_vault;
CREATE POLICY file_vault_delete ON file_vault FOR DELETE TO authenticated USING (is_admin() OR (is_instructor_head() AND branch_id = my_branch_id()));
CREATE TRIGGER file_vault_updated_at BEFORE UPDATE ON file_vault FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
COMMENT ON TABLE file_vault IS 'คลังเก็บไฟล์ — metadata ของไฟล์ใน storage bucket vault';

-- ========== 020: เว็บไม่ผูกสาขา + โลโก้ + แก้ recursion RLS ==========
CREATE OR REPLACE FUNCTION my_assigned_website_ids()
RETURNS SETOF UUID LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$ SELECT website_id FROM website_assignments WHERE user_id = auth.uid(); $$;

ALTER TABLE websites ALTER COLUMN branch_id DROP NOT NULL;
ALTER TABLE websites DROP CONSTRAINT IF EXISTS websites_branch_id_alias_key;
CREATE UNIQUE INDEX IF NOT EXISTS idx_websites_name_unique ON websites(LOWER(TRIM(name)));
CREATE UNIQUE INDEX IF NOT EXISTS idx_websites_alias_unique ON websites(LOWER(TRIM(alias)));
ALTER TABLE websites ADD COLUMN IF NOT EXISTS logo_path TEXT;

DROP POLICY IF EXISTS websites_select ON websites;
DROP POLICY IF EXISTS websites_insert ON websites;
DROP POLICY IF EXISTS websites_update ON websites;
DROP POLICY IF EXISTS websites_delete ON websites;
CREATE POLICY websites_select ON websites FOR SELECT TO authenticated USING (is_admin() OR id IN (SELECT my_assigned_website_ids()));
CREATE POLICY websites_insert ON websites FOR INSERT TO authenticated WITH CHECK (is_admin());
CREATE POLICY websites_update ON websites FOR UPDATE TO authenticated USING (is_admin());
CREATE POLICY websites_delete ON websites FOR DELETE TO authenticated USING (is_admin());

DROP POLICY IF EXISTS website_assignments_select ON website_assignments;
DROP POLICY IF EXISTS website_assignments_insert ON website_assignments;
DROP POLICY IF EXISTS website_assignments_update ON website_assignments;
DROP POLICY IF EXISTS website_assignments_delete ON website_assignments;
CREATE POLICY website_assignments_select ON website_assignments FOR SELECT TO authenticated USING (is_admin() OR user_id = auth.uid());
CREATE POLICY website_assignments_insert ON website_assignments FOR INSERT TO authenticated WITH CHECK (is_admin());
CREATE POLICY website_assignments_update ON website_assignments FOR UPDATE TO authenticated USING (is_admin());
CREATE POLICY website_assignments_delete ON website_assignments FOR DELETE TO authenticated USING (is_admin());

CREATE OR REPLACE FUNCTION set_primary_website(p_user_id UUID, p_website_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_user_id IS NULL OR p_website_id IS NULL THEN RETURN; END IF;
  IF NOT is_admin() THEN RAISE EXCEPTION 'ไม่มีสิทธิ์ตั้งเว็บหลัก'; END IF;
  UPDATE website_assignments SET is_primary = false WHERE user_id = p_user_id;
  UPDATE website_assignments SET is_primary = true WHERE user_id = p_user_id AND website_id = p_website_id;
END;
$$;
COMMENT ON TABLE websites IS 'เว็บที่ดูแล — ผูกกับผู้ใช้ผ่าน website_assignments (ไม่บังคับผูกสาขา)';
COMMENT ON COLUMN websites.logo_path IS 'โลโก้เว็บ (option) — path ใน storage หรือ URL';

-- ========== 021: file_vault branch_id nullable ==========
ALTER TABLE file_vault ALTER COLUMN branch_id DROP NOT NULL;
DROP POLICY IF EXISTS file_vault_select ON file_vault;
CREATE POLICY file_vault_select ON file_vault FOR SELECT TO authenticated USING (
  is_admin() OR (branch_id IS NOT NULL AND branch_id IN (SELECT user_branch_ids(auth.uid()))) OR (branch_id IS NULL)
);
DROP POLICY IF EXISTS file_vault_insert ON file_vault;
CREATE POLICY file_vault_insert ON file_vault FOR INSERT TO authenticated WITH CHECK (is_admin() OR (is_instructor_head() AND (branch_id = my_branch_id() OR branch_id IS NULL)));
DROP POLICY IF EXISTS file_vault_update ON file_vault;
CREATE POLICY file_vault_update ON file_vault FOR UPDATE TO authenticated USING (is_admin() OR (is_instructor_head() AND (branch_id = my_branch_id() OR branch_id IS NULL)));
DROP POLICY IF EXISTS file_vault_delete ON file_vault;
CREATE POLICY file_vault_delete ON file_vault FOR DELETE TO authenticated USING (is_admin() OR (is_instructor_head() AND (branch_id = my_branch_id() OR branch_id IS NULL)));

-- ========== 022: schedule_cards visible_roles + website_id ==========
ALTER TABLE schedule_cards ADD COLUMN IF NOT EXISTS visible_roles TEXT[] DEFAULT '{}';
ALTER TABLE schedule_cards ADD COLUMN IF NOT EXISTS website_id UUID REFERENCES websites(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_schedule_cards_website ON schedule_cards(website_id);
COMMENT ON COLUMN schedule_cards.visible_roles IS 'roles ที่เห็นการ์ดได้ (staff, instructor, instructor_head, admin); ว่าง = ทุก role ในสาขา';
COMMENT ON COLUMN schedule_cards.website_id IS 'null = ทุกเว็บ; มีค่า = เฉพาะผู้ที่ถูก assign เว็บนี้';

CREATE OR REPLACE FUNCTION my_role()
RETURNS TEXT LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$ SELECT role FROM profiles WHERE id = auth.uid() LIMIT 1; $$;

DROP POLICY IF EXISTS schedule_cards_select ON schedule_cards;
DROP POLICY IF EXISTS schedule_cards_all ON schedule_cards;
DROP POLICY IF EXISTS schedule_cards_insert ON schedule_cards;
DROP POLICY IF EXISTS schedule_cards_update ON schedule_cards;
DROP POLICY IF EXISTS schedule_cards_delete ON schedule_cards;
CREATE POLICY schedule_cards_select ON schedule_cards FOR SELECT TO authenticated USING (
  (is_admin() OR (
    (branch_id IS NULL OR branch_id IN (SELECT user_branch_ids(auth.uid())))
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR my_role() = ANY(visible_roles))
    AND (website_id IS NULL OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid()))
  ))
);
CREATE POLICY schedule_cards_insert ON schedule_cards FOR INSERT TO authenticated WITH CHECK (is_admin() OR (is_instructor_head() AND branch_id = my_branch_id()));
CREATE POLICY schedule_cards_update ON schedule_cards FOR UPDATE TO authenticated USING (is_admin() OR (is_instructor_head() AND branch_id = my_branch_id()));
CREATE POLICY schedule_cards_delete ON schedule_cards FOR DELETE TO authenticated USING (is_admin() OR (is_instructor_head() AND branch_id = my_branch_id()));

-- ========== 023: Storage bucket vault ==========
DROP POLICY IF EXISTS "vault_insert_admin_head" ON storage.objects;
CREATE POLICY "vault_insert_admin_head" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'vault' AND (public.is_admin() OR public.is_instructor_head()));
DROP POLICY IF EXISTS "vault_select_authenticated" ON storage.objects;
CREATE POLICY "vault_select_authenticated" ON storage.objects FOR SELECT TO authenticated USING (bucket_id = 'vault');
DROP POLICY IF EXISTS "vault_update_admin_head" ON storage.objects;
CREATE POLICY "vault_update_admin_head" ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'vault' AND (public.is_admin() OR public.is_instructor_head()));
DROP POLICY IF EXISTS "vault_delete_admin_head" ON storage.objects;
CREATE POLICY "vault_delete_admin_head" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'vault' AND (public.is_admin() OR public.is_instructor_head()));

-- ========== 024: file_vault visible_roles ==========
ALTER TABLE file_vault ADD COLUMN IF NOT EXISTS visible_roles TEXT[] DEFAULT '{}';
COMMENT ON COLUMN file_vault.visible_roles IS 'roles ที่เห็นไฟล์ได้ (staff, instructor, instructor_head, admin); ว่าง/null = ทุก role';
DROP POLICY IF EXISTS file_vault_select ON file_vault;
CREATE POLICY file_vault_select ON file_vault FOR SELECT TO authenticated USING (
  is_admin() OR (
    (branch_id IS NULL OR branch_id IN (SELECT user_branch_ids(auth.uid())))
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles))
    AND (website_id IS NULL OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid()))
  )
);

-- ========== 025: group_links visible_roles + หลายเว็บ (group_link_websites) ==========
ALTER TABLE group_links ADD COLUMN IF NOT EXISTS visible_roles TEXT[] DEFAULT '{}';
COMMENT ON COLUMN group_links.visible_roles IS 'roles ที่เห็นลิงก์ได้ (staff, instructor, instructor_head, admin); ว่าง/null = ทุก role';

CREATE TABLE IF NOT EXISTS group_link_websites (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  group_link_id UUID NOT NULL REFERENCES group_links(id) ON DELETE CASCADE,
  website_id UUID NOT NULL REFERENCES websites(id) ON DELETE CASCADE,
  UNIQUE(group_link_id, website_id)
);
CREATE INDEX IF NOT EXISTS idx_group_link_websites_link ON group_link_websites(group_link_id);
CREATE INDEX IF NOT EXISTS idx_group_link_websites_website ON group_link_websites(website_id);

INSERT INTO group_link_websites (group_link_id, website_id)
  SELECT id, website_id FROM group_links WHERE website_id IS NOT NULL
  ON CONFLICT (group_link_id, website_id) DO NOTHING;

DROP POLICY IF EXISTS group_links_select ON group_links;
CREATE POLICY group_links_select ON group_links FOR SELECT TO authenticated USING (
  is_admin() OR (
    (branch_id IS NULL OR branch_id = my_branch_id())
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles))
  )
);

ALTER TABLE group_link_websites ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS group_link_websites_select ON group_link_websites;
CREATE POLICY group_link_websites_select ON group_link_websites FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM group_links g WHERE g.id = group_link_id AND (is_admin() OR (g.branch_id IS NULL OR g.branch_id = my_branch_id())))
);
DROP POLICY IF EXISTS group_link_websites_insert ON group_link_websites;
CREATE POLICY group_link_websites_insert ON group_link_websites FOR INSERT TO authenticated WITH CHECK (
  EXISTS (SELECT 1 FROM group_links g WHERE g.id = group_link_id AND (is_admin() OR (is_instructor_head() AND g.branch_id = my_branch_id())))
);
DROP POLICY IF EXISTS group_link_websites_delete ON group_link_websites;
CREATE POLICY group_link_websites_delete ON group_link_websites FOR DELETE TO authenticated USING (
  EXISTS (SELECT 1 FROM group_links g WHERE g.id = group_link_id AND (is_admin() OR (is_instructor_head() AND g.branch_id = my_branch_id())))
);
