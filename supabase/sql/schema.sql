-- ============================================================
-- OKACE System - Supabase Schema
-- ลงเวลา + ตารางวันหยุด/กะ + จัดหน้าที่ + คลังรูป + คลังรหัสผ่าน + ลิงก์กลุ่ม + ประวัติ
-- ============================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- ENUMS (รันซ้ำได้ - ถ้ามีอยู่แล้วจะข้าม)
-- ============================================================
DO $$ BEGIN
  CREATE TYPE app_role AS ENUM ('admin', 'manager', 'instructor_head', 'instructor', 'staff');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE work_log_type AS ENUM ('IN', 'OUT');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE holiday_status AS ENUM ('pending', 'approved', 'rejected', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE roster_status AS ENUM ('DRAFT', 'CONFIRMED');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE swap_status AS ENUM ('pending', 'approved', 'rejected', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE transfer_status AS ENUM ('pending', 'approved', 'rejected', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE break_log_status AS ENUM ('active', 'ended');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- CORE TABLES
-- ============================================================

-- สาขา
CREATE TABLE IF NOT EXISTS branches (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  code TEXT UNIQUE,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- กะ
CREATE TABLE IF NOT EXISTS shifts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  code TEXT,
  start_time TIME,
  end_time TIME,
  sort_order INT DEFAULT 0,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- โปรไฟล์ผู้ใช้ (ผูกกับ Supabase Auth)
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  display_name TEXT,
  role app_role NOT NULL DEFAULT 'staff',
  default_branch_id UUID REFERENCES branches(id),
  default_shift_id UUID REFERENCES shifts(id),
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  telegram TEXT,
  lock_code TEXT,
  email_code TEXT,
  computer_code TEXT,
  work_access_code TEXT,
  two_fa TEXT,
  avatar_url TEXT,
  link1_url TEXT,
  link2_url TEXT,
  note_title TEXT,
  note_body TEXT
);

-- ตารางกะรายเดือน (ใครอยู่กะไหน วันที่ไหน)
CREATE TABLE IF NOT EXISTS monthly_roster (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  work_date DATE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(branch_id, shift_id, work_date, user_id)
);

CREATE INDEX IF NOT EXISTS idx_monthly_roster_branch_shift_date ON monthly_roster(branch_id, shift_id, work_date);
CREATE INDEX IF NOT EXISTS idx_monthly_roster_user_date ON monthly_roster(user_id, work_date);

-- สถานะการยืนยันตารางกะรายเดือน
CREATE TABLE IF NOT EXISTS monthly_roster_status (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  month DATE NOT NULL,
  status roster_status NOT NULL DEFAULT 'DRAFT',
  confirmed_by UUID REFERENCES profiles(id),
  confirmed_at TIMESTAMPTZ,
  unlock_reason TEXT,
  unlocked_by UUID REFERENCES profiles(id),
  unlocked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(branch_id, month)
);

-- ลงเวลา (เข้างาน/ออกงาน)
CREATE TABLE IF NOT EXISTS work_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
  logical_date DATE NOT NULL,
  log_type work_log_type NOT NULL,
  logged_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT work_logs_max_two_per_day UNIQUE (user_id, logical_date, log_type)
);

CREATE INDEX IF NOT EXISTS idx_work_logs_user_date ON work_logs(user_id, logical_date);
CREATE INDEX IF NOT EXISTS idx_work_logs_branch_shift_date ON work_logs(branch_id, shift_id, logical_date);

-- กติกาการพัก (concurrent breaks ตามจำนวนพนักงาน)
CREATE TABLE IF NOT EXISTS break_rules (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  shift_id UUID REFERENCES shifts(id) ON DELETE CASCADE,
  min_staff INT NOT NULL,
  max_staff INT NOT NULL,
  concurrent_breaks INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- บันทึกการพัก
CREATE TABLE IF NOT EXISTS break_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
  break_date DATE NOT NULL,
  started_at TIMESTAMPTZ NOT NULL,
  ended_at TIMESTAMPTZ,
  status break_log_status NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_break_logs_user_date ON break_logs(user_id, break_date);
CREATE INDEX IF NOT EXISTS idx_break_logs_branch_shift_date ON break_logs(branch_id, shift_id, break_date);

-- โควต้าวันหยุด (ต่อสาขา/กะ/วัน)
CREATE TABLE IF NOT EXISTS holiday_quotas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
  quota_date DATE NOT NULL,
  quota INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(branch_id, shift_id, quota_date)
);

-- วันหยุด (การขอลา)
CREATE TABLE IF NOT EXISTS holidays (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
  holiday_date DATE NOT NULL,
  status holiday_status NOT NULL DEFAULT 'pending',
  reason TEXT,
  approved_by UUID REFERENCES profiles(id),
  approved_at TIMESTAMPTZ,
  reject_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_holidays_branch_shift_date ON holidays(branch_id, shift_id, holiday_date);
CREATE INDEX IF NOT EXISTS idx_holidays_user_date ON holidays(user_id, holiday_date);

-- สลับกะ
CREATE TABLE IF NOT EXISTS shift_swaps (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  from_shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
  to_shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  reason TEXT,
  status swap_status NOT NULL DEFAULT 'pending',
  approved_by UUID REFERENCES profiles(id),
  approved_at TIMESTAMPTZ,
  reject_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ย้ายกะข้ามสาขา
CREATE TABLE IF NOT EXISTS cross_branch_transfers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  from_branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  to_branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  from_shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
  to_shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  reason TEXT,
  status transfer_status NOT NULL DEFAULT 'pending',
  approved_by UUID REFERENCES profiles(id),
  approved_at TIMESTAMPTZ,
  reject_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- หน้าที่/งาน (รายการหน้าที่ต่อสาขา)
CREATE TABLE IF NOT EXISTS duty_roles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- การจัดหน้าที่ (วัน/สาขา/กะ/หน้าที่ → คน) — หนึ่งหน้าที่มีหลายคนได้
CREATE TABLE IF NOT EXISTS duty_assignments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
  duty_role_id UUID NOT NULL REFERENCES duty_roles(id) ON DELETE CASCADE,
  user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  assignment_date DATE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
-- คนเดียวกันในหน้าที่เดียวกันวันเดียวกันได้แค่ 1 แถว; หลายคนต่อหน้าที่ได้
CREATE UNIQUE INDEX IF NOT EXISTS duty_assignments_one_user_per_role_per_day
  ON duty_assignments (branch_id, shift_id, duty_role_id, assignment_date, user_id)
  WHERE user_id IS NOT NULL;

-- งานที่มอบหมาย (Tasks - Instructor)
CREATE TABLE IF NOT EXISTS tasks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title TEXT NOT NULL,
  description TEXT,
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  assignee_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  status TEXT DEFAULT 'open',
  due_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- เว็บที่ดูแล (ต้องมีก่อน schedule_cards / file_vault ที่อ้างอิง websites)
CREATE TABLE IF NOT EXISTS websites (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  alias TEXT NOT NULL,
  url TEXT,
  description TEXT,
  is_active BOOLEAN DEFAULT true,
  logo_path TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS website_assignments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  website_id UUID NOT NULL REFERENCES websites(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  is_primary BOOLEAN NOT NULL DEFAULT false,
  role_on_website TEXT DEFAULT 'viewer',
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(website_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_websites_branch ON websites(branch_id);
CREATE INDEX IF NOT EXISTS idx_website_assignments_user ON website_assignments(user_id);
CREATE INDEX IF NOT EXISTS idx_website_assignments_website ON website_assignments(website_id);

-- ตารางงาน/ลิงก์งาน (Schedule Cards) — หัวหน้าสร้างได้ในสาขาตัวเอง, กำหนด role/เว็บที่เห็นได้
CREATE TABLE IF NOT EXISTS schedule_cards (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title TEXT NOT NULL,
  url TEXT,
  color_tag TEXT,
  scope TEXT DEFAULT 'all',
  card_type TEXT DEFAULT 'link',
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  visible_roles TEXT[] DEFAULT '{}',
  website_id UUID REFERENCES websites(id) ON DELETE SET NULL,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ลิงก์กลุ่ม
CREATE TABLE IF NOT EXISTS group_links (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  url TEXT,
  description TEXT,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- คลังรหัสผ่าน (ไม่ได้ใช้ในระบบ — ลบด้วย migration 05)
CREATE TABLE IF NOT EXISTS password_vault (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  site_name TEXT NOT NULL,
  url TEXT,
  username TEXT,
  encrypted_password TEXT NOT NULL,
  note TEXT,
  branch_scope TEXT,
  created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- คลังเก็บไฟล์ (metadata ของไฟล์ใน storage bucket vault)
CREATE TABLE IF NOT EXISTS file_vault (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  website_id UUID REFERENCES websites(id) ON DELETE SET NULL,
  file_path TEXT NOT NULL,
  file_name TEXT NOT NULL,
  topic TEXT,
  uploaded_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(file_path)
);
CREATE INDEX IF NOT EXISTS idx_file_vault_branch ON file_vault(branch_id);
CREATE INDEX IF NOT EXISTS idx_file_vault_website ON file_vault(website_id);
CREATE INDEX IF NOT EXISTS idx_file_vault_created ON file_vault(created_at DESC);

-- ประวัติการทำรายการ
CREATE TABLE IF NOT EXISTS audit_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  actor_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  entity TEXT NOT NULL,
  entity_id UUID,
  details_json JSONB,
  ip_address TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON audit_logs(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON audit_logs(entity, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON audit_logs(created_at);

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE monthly_roster ENABLE ROW LEVEL SECURITY;
ALTER TABLE monthly_roster_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE break_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE break_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE holiday_quotas ENABLE ROW LEVEL SECURITY;
ALTER TABLE holidays ENABLE ROW LEVEL SECURITY;
ALTER TABLE shift_swaps ENABLE ROW LEVEL SECURITY;
ALTER TABLE cross_branch_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE duty_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE duty_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedule_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE password_vault ENABLE ROW LEVEL SECURITY;
ALTER TABLE file_vault ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- Helper: ตรวจสอบว่าเป็น admin
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'::app_role
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Helper: ตรวจสอบว่าเป็น instructor ขึ้นไป
CREATE OR REPLACE FUNCTION is_instructor_or_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role IN ('admin'::app_role, 'instructor'::app_role)
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Helper: branch ที่ user มีสิทธิ์ (default_branch หรือสาขาที่โอนไป)
CREATE OR REPLACE FUNCTION user_branch_ids(uid UUID)
RETURNS SETOF UUID AS $$
  SELECT DISTINCT b.id FROM branches b
  JOIN profiles p ON p.id = uid
  WHERE p.role = 'admin'::app_role
  UNION
  SELECT p.default_branch_id FROM profiles p WHERE p.id = uid AND p.default_branch_id IS NOT NULL
  UNION
  SELECT cbt.to_branch_id FROM cross_branch_transfers cbt
  WHERE cbt.user_id = uid AND cbt.status = 'approved'
    AND current_date BETWEEN cbt.start_date AND cbt.end_date
  UNION
  SELECT cbt.from_branch_id FROM cross_branch_transfers cbt
  WHERE cbt.user_id = uid AND cbt.status = 'approved'
    AND (current_date < cbt.start_date OR current_date > cbt.end_date);
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Helper: แผนกประจำของ current user (instructor/staff)
CREATE OR REPLACE FUNCTION my_branch_id()
RETURNS UUID AS $$ SELECT p.default_branch_id FROM profiles p WHERE p.id = auth.uid() AND p.role IN ('instructor'::app_role, 'staff'::app_role) AND p.default_branch_id IS NOT NULL LIMIT 1; $$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Helper: ตรวจสอบว่าเป็นหัวหน้าพนักงานประจำ
CREATE OR REPLACE FUNCTION is_instructor_head()
RETURNS BOOLEAN AS $$ SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'instructor_head'::app_role); $$ LANGUAGE sql SECURITY DEFINER STABLE;

-- branches: ทุกคนอ่านได้
DROP POLICY IF EXISTS branches_select ON branches;
DROP POLICY IF EXISTS branches_all ON branches;
CREATE POLICY branches_select ON branches FOR SELECT TO authenticated USING (true);
CREATE POLICY branches_all ON branches FOR ALL TO authenticated USING (is_admin());

-- shifts: ทุกคนอ่านได้
DROP POLICY IF EXISTS shifts_select ON shifts;
DROP POLICY IF EXISTS shifts_all ON shifts;
CREATE POLICY shifts_select ON shifts FOR SELECT TO authenticated USING (true);
CREATE POLICY shifts_all ON shifts FOR ALL TO authenticated USING (is_admin());

-- profiles: อ่านได้ตาม role
DROP POLICY IF EXISTS profiles_select ON profiles;
DROP POLICY IF EXISTS profiles_update_self ON profiles;
DROP POLICY IF EXISTS profiles_all ON profiles;
CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated USING (
  is_admin() OR id = auth.uid() OR is_instructor_or_admin()
  OR (default_branch_id IS NOT NULL AND default_branch_id IN (SELECT user_branch_ids(auth.uid())))
);
CREATE POLICY profiles_update_self ON profiles FOR UPDATE TO authenticated USING (id = auth.uid());
CREATE POLICY profiles_all ON profiles FOR ALL TO authenticated USING (is_admin());

-- monthly_roster
DROP POLICY IF EXISTS monthly_roster_select ON monthly_roster;
DROP POLICY IF EXISTS monthly_roster_insert ON monthly_roster;
DROP POLICY IF EXISTS monthly_roster_update ON monthly_roster;
DROP POLICY IF EXISTS monthly_roster_delete ON monthly_roster;
CREATE POLICY monthly_roster_select ON monthly_roster FOR SELECT TO authenticated USING (
  is_admin() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
CREATE POLICY monthly_roster_insert ON monthly_roster FOR INSERT TO authenticated WITH CHECK (is_admin());
CREATE POLICY monthly_roster_update ON monthly_roster FOR UPDATE TO authenticated USING (is_admin());
CREATE POLICY monthly_roster_delete ON monthly_roster FOR DELETE TO authenticated USING (is_admin());

-- monthly_roster_status
DROP POLICY IF EXISTS roster_status_select ON monthly_roster_status;
DROP POLICY IF EXISTS roster_status_all ON monthly_roster_status;
CREATE POLICY roster_status_select ON monthly_roster_status FOR SELECT TO authenticated USING (
  is_admin() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
CREATE POLICY roster_status_all ON monthly_roster_status FOR ALL TO authenticated USING (is_admin());

-- work_logs
DROP POLICY IF EXISTS work_logs_select ON work_logs;
DROP POLICY IF EXISTS work_logs_insert ON work_logs;
DROP POLICY IF EXISTS work_logs_update ON work_logs;
CREATE POLICY work_logs_select ON work_logs FOR SELECT TO authenticated USING (
  is_admin() OR user_id = auth.uid() OR (is_instructor_or_admin() AND branch_id IN (SELECT user_branch_ids(auth.uid())))
);
CREATE POLICY work_logs_insert ON work_logs FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY work_logs_update ON work_logs FOR UPDATE TO authenticated USING (is_admin());

-- break_rules
DROP POLICY IF EXISTS break_rules_select ON break_rules;
DROP POLICY IF EXISTS break_rules_all ON break_rules;
CREATE POLICY break_rules_select ON break_rules FOR SELECT TO authenticated USING (true);
CREATE POLICY break_rules_all ON break_rules FOR ALL TO authenticated USING (is_admin());

-- break_logs
DROP POLICY IF EXISTS break_logs_select ON break_logs;
DROP POLICY IF EXISTS break_logs_insert ON break_logs;
DROP POLICY IF EXISTS break_logs_update ON break_logs;
CREATE POLICY break_logs_select ON break_logs FOR SELECT TO authenticated USING (
  is_admin() OR user_id = auth.uid() OR (is_instructor_or_admin() AND branch_id IN (SELECT user_branch_ids(auth.uid())))
);
CREATE POLICY break_logs_insert ON break_logs FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY break_logs_update ON break_logs FOR UPDATE TO authenticated USING (user_id = auth.uid() OR is_admin());

-- holiday_quotas
DROP POLICY IF EXISTS holiday_quotas_select ON holiday_quotas;
DROP POLICY IF EXISTS holiday_quotas_all ON holiday_quotas;
CREATE POLICY holiday_quotas_select ON holiday_quotas FOR SELECT TO authenticated USING (true);
CREATE POLICY holiday_quotas_all ON holiday_quotas FOR ALL TO authenticated USING (is_admin());

-- holidays
DROP POLICY IF EXISTS holidays_select ON holidays;
DROP POLICY IF EXISTS holidays_insert ON holidays;
DROP POLICY IF EXISTS holidays_update ON holidays;
CREATE POLICY holidays_select ON holidays FOR SELECT TO authenticated USING (
  is_admin() OR user_id = auth.uid() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
CREATE POLICY holidays_insert ON holidays FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY holidays_update ON holidays FOR UPDATE TO authenticated USING (
  is_admin() OR user_id = auth.uid()
);

-- shift_swaps
DROP POLICY IF EXISTS shift_swaps_select ON shift_swaps;
DROP POLICY IF EXISTS shift_swaps_insert ON shift_swaps;
DROP POLICY IF EXISTS shift_swaps_update ON shift_swaps;
CREATE POLICY shift_swaps_select ON shift_swaps FOR SELECT TO authenticated USING (
  is_admin() OR user_id = auth.uid() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
CREATE POLICY shift_swaps_insert ON shift_swaps FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY shift_swaps_update ON shift_swaps FOR UPDATE TO authenticated USING (is_admin() OR user_id = auth.uid());

-- cross_branch_transfers
DROP POLICY IF EXISTS transfers_select ON cross_branch_transfers;
DROP POLICY IF EXISTS transfers_insert ON cross_branch_transfers;
DROP POLICY IF EXISTS transfers_update ON cross_branch_transfers;
CREATE POLICY transfers_select ON cross_branch_transfers FOR SELECT TO authenticated USING (
  is_admin() OR user_id = auth.uid() OR from_branch_id IN (SELECT user_branch_ids(auth.uid())) OR to_branch_id IN (SELECT user_branch_ids(auth.uid()))
);
CREATE POLICY transfers_insert ON cross_branch_transfers FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY transfers_update ON cross_branch_transfers FOR UPDATE TO authenticated USING (is_admin() OR user_id = auth.uid());

-- duty_roles
DROP POLICY IF EXISTS duty_roles_select ON duty_roles;
DROP POLICY IF EXISTS duty_roles_all ON duty_roles;
CREATE POLICY duty_roles_select ON duty_roles FOR SELECT TO authenticated USING (
  is_admin() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
CREATE POLICY duty_roles_all ON duty_roles FOR ALL TO authenticated USING (is_admin());

-- duty_assignments
DROP POLICY IF EXISTS duty_assignments_select ON duty_assignments;
DROP POLICY IF EXISTS duty_assignments_all ON duty_assignments;
CREATE POLICY duty_assignments_select ON duty_assignments FOR SELECT TO authenticated USING (
  is_admin() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
CREATE POLICY duty_assignments_all ON duty_assignments FOR ALL TO authenticated USING (is_admin());

-- tasks
DROP POLICY IF EXISTS tasks_select ON tasks;
DROP POLICY IF EXISTS tasks_insert ON tasks;
DROP POLICY IF EXISTS tasks_update ON tasks;
CREATE POLICY tasks_select ON tasks FOR SELECT TO authenticated USING (
  is_admin() OR assignee_id = auth.uid() OR created_by = auth.uid() OR is_instructor_or_admin()
);
CREATE POLICY tasks_insert ON tasks FOR INSERT TO authenticated WITH CHECK (is_instructor_or_admin());
CREATE POLICY tasks_update ON tasks FOR UPDATE TO authenticated USING (
  is_instructor_or_admin() OR assignee_id = auth.uid()
);

-- schedule_cards: อ่านตาม branch + visible_roles + website; เพิ่ม/แก้/ลบ admin หรือหัวหน้าในสาขาตัวเอง
DROP POLICY IF EXISTS schedule_cards_select ON schedule_cards;
DROP POLICY IF EXISTS schedule_cards_all ON schedule_cards;
DROP POLICY IF EXISTS schedule_cards_insert ON schedule_cards;
DROP POLICY IF EXISTS schedule_cards_update ON schedule_cards;
DROP POLICY IF EXISTS schedule_cards_delete ON schedule_cards;
CREATE POLICY schedule_cards_select ON schedule_cards FOR SELECT TO authenticated USING (
  is_admin()
  OR (
    (branch_id IS NULL OR branch_id IN (SELECT user_branch_ids(auth.uid())))
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles))
    AND (website_id IS NULL OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid()))
  )
);
CREATE POLICY schedule_cards_insert ON schedule_cards FOR INSERT TO authenticated WITH CHECK (
  is_admin() OR (is_instructor_head() AND branch_id = my_branch_id())
);
CREATE POLICY schedule_cards_update ON schedule_cards FOR UPDATE TO authenticated USING (
  is_admin() OR (is_instructor_head() AND branch_id = my_branch_id())
);
CREATE POLICY schedule_cards_delete ON schedule_cards FOR DELETE TO authenticated USING (
  is_admin() OR (is_instructor_head() AND branch_id = my_branch_id())
);

-- group_links
DROP POLICY IF EXISTS group_links_select ON group_links;
DROP POLICY IF EXISTS group_links_all ON group_links;
CREATE POLICY group_links_select ON group_links FOR SELECT TO authenticated USING (true);
CREATE POLICY group_links_all ON group_links FOR ALL TO authenticated USING (is_admin());

-- password_vault: ลบด้วย migration 05 (ไม่ใช้ในระบบ)
DROP POLICY IF EXISTS password_vault_select ON password_vault;
DROP POLICY IF EXISTS password_vault_all ON password_vault;
CREATE POLICY password_vault_select ON password_vault FOR SELECT TO authenticated USING (true);
CREATE POLICY password_vault_all ON password_vault FOR ALL TO authenticated USING (is_admin());

-- audit_logs: admin อ่านได้ทั้งหมด; staff อ่านเฉพาะของตัวเอง
DROP POLICY IF EXISTS audit_logs_select ON audit_logs;
DROP POLICY IF EXISTS audit_logs_insert ON audit_logs;
CREATE POLICY audit_logs_select ON audit_logs FOR SELECT TO authenticated USING (
  is_admin() OR (actor_id = auth.uid()) OR is_instructor_or_admin()
);
CREATE POLICY audit_logs_insert ON audit_logs FOR INSERT TO authenticated WITH CHECK (true);

-- ============================================================
-- REALTIME (เปิดใน Supabase Dashboard > Database > Replication)
-- หรือรันทีละตาราง ถ้า publication มีอยู่แล้ว:
-- ALTER PUBLICATION supabase_realtime ADD TABLE holidays;
-- ALTER PUBLICATION supabase_realtime ADD TABLE shift_swaps;
-- ALTER PUBLICATION supabase_realtime ADD TABLE cross_branch_transfers;
-- ALTER PUBLICATION supabase_realtime ADD TABLE duty_assignments;
-- ALTER PUBLICATION supabase_realtime ADD TABLE monthly_roster_status;
-- ALTER PUBLICATION supabase_realtime ADD TABLE monthly_roster;
-- ============================================================

-- ============================================================
-- TRIGGERS updated_at
-- ============================================================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS branches_updated_at ON branches;
DROP TRIGGER IF EXISTS shifts_updated_at ON shifts;
DROP TRIGGER IF EXISTS profiles_updated_at ON profiles;
DROP TRIGGER IF EXISTS monthly_roster_status_updated_at ON monthly_roster_status;
DROP TRIGGER IF EXISTS break_rules_updated_at ON break_rules;
DROP TRIGGER IF EXISTS holidays_updated_at ON holidays;
DROP TRIGGER IF EXISTS shift_swaps_updated_at ON shift_swaps;
DROP TRIGGER IF EXISTS cross_branch_transfers_updated_at ON cross_branch_transfers;
DROP TRIGGER IF EXISTS duty_roles_updated_at ON duty_roles;
DROP TRIGGER IF EXISTS duty_assignments_updated_at ON duty_assignments;
DROP TRIGGER IF EXISTS tasks_updated_at ON tasks;
DROP TRIGGER IF EXISTS schedule_cards_updated_at ON schedule_cards;
DROP TRIGGER IF EXISTS group_links_updated_at ON group_links;
DROP TRIGGER IF EXISTS password_vault_updated_at ON password_vault;
CREATE TRIGGER branches_updated_at BEFORE UPDATE ON branches FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
CREATE TRIGGER shifts_updated_at BEFORE UPDATE ON shifts FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
CREATE TRIGGER monthly_roster_status_updated_at BEFORE UPDATE ON monthly_roster_status FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
CREATE TRIGGER break_rules_updated_at BEFORE UPDATE ON break_rules FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
CREATE TRIGGER holidays_updated_at BEFORE UPDATE ON holidays FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
CREATE TRIGGER shift_swaps_updated_at BEFORE UPDATE ON shift_swaps FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
CREATE TRIGGER cross_branch_transfers_updated_at BEFORE UPDATE ON cross_branch_transfers FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
CREATE TRIGGER duty_roles_updated_at BEFORE UPDATE ON duty_roles FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
CREATE TRIGGER duty_assignments_updated_at BEFORE UPDATE ON duty_assignments FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
CREATE TRIGGER tasks_updated_at BEFORE UPDATE ON tasks FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
CREATE TRIGGER schedule_cards_updated_at BEFORE UPDATE ON schedule_cards FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
CREATE TRIGGER group_links_updated_at BEFORE UPDATE ON group_links FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
CREATE TRIGGER password_vault_updated_at BEFORE UPDATE ON password_vault FOR EACH ROW EXECUTE PROCEDURE set_updated_at();

-- ============================================================
-- SEED DATA
-- ============================================================
INSERT INTO branches (id, name, code) VALUES
  (uuid_generate_v4(), 'สาขาหลัก', 'MAIN'),
  (uuid_generate_v4(), 'สาขาที่ 2', 'B2'),
  (uuid_generate_v4(), 'สาขาที่ 3', 'B3')
ON CONFLICT (code) DO NOTHING;

INSERT INTO shifts (name, code, sort_order)
SELECT v.name, v.code, v.sort_order FROM (VALUES
  ('เช้า', 'M', 1),
  ('กลาง', 'A', 2),
  ('ดึก', 'N', 3)
) AS v(name, code, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM shifts WHERE shifts.code = v.code);

-- break_rules ค่าเริ่มต้น (รันซ้ำได้ - insert เมื่อยังไม่มี)
INSERT INTO break_rules (min_staff, max_staff, concurrent_breaks)
SELECT 1, 5, 1 WHERE NOT EXISTS (SELECT 1 FROM break_rules LIMIT 1)
UNION ALL SELECT 6, 10, 2 WHERE NOT EXISTS (SELECT 1 FROM break_rules LIMIT 1)
UNION ALL SELECT 11, 15, 3 WHERE NOT EXISTS (SELECT 1 FROM break_rules LIMIT 1);

-- สร้าง profile อัตโนมัติเมื่อมี user ใหม่ (optional - ปรับ role เองหลังสร้าง)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, display_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'name', NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    'staff'::app_role
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- หมายเหตุ: ผู้ใช้คนแรกที่ต้องการเป็น Admin ให้ไปอัปเดตในตาราง profiles: UPDATE profiles SET role = 'admin' WHERE email = 'your@email.com';
