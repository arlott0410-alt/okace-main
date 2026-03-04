CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
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
CREATE TABLE IF NOT EXISTS branches (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  code TEXT UNIQUE,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
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
CREATE TABLE IF NOT EXISTS holiday_quotas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
  quota_date DATE NOT NULL,
  quota INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(branch_id, shift_id, quota_date)
);
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
CREATE TABLE IF NOT EXISTS duty_roles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
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
CREATE UNIQUE INDEX IF NOT EXISTS duty_assignments_one_user_per_role_per_day
  ON duty_assignments (branch_id, shift_id, duty_role_id, assignment_date, user_id)
  WHERE user_id IS NOT NULL;
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
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'::app_role
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;
CREATE OR REPLACE FUNCTION is_instructor_or_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role IN ('admin'::app_role, 'instructor'::app_role)
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;
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
DROP POLICY IF EXISTS branches_select ON branches;
DROP POLICY IF EXISTS branches_all ON branches;
CREATE POLICY branches_select ON branches FOR SELECT TO authenticated USING (true);
CREATE POLICY branches_all ON branches FOR ALL TO authenticated USING (is_admin());
DROP POLICY IF EXISTS shifts_select ON shifts;
DROP POLICY IF EXISTS shifts_all ON shifts;
CREATE POLICY shifts_select ON shifts FOR SELECT TO authenticated USING (true);
CREATE POLICY shifts_all ON shifts FOR ALL TO authenticated USING (is_admin());
DROP POLICY IF EXISTS profiles_select ON profiles;
DROP POLICY IF EXISTS profiles_update_self ON profiles;
DROP POLICY IF EXISTS profiles_all ON profiles;
CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated USING (
  is_admin() OR id = auth.uid() OR is_instructor_or_admin()
  OR (default_branch_id IS NOT NULL AND default_branch_id IN (SELECT user_branch_ids(auth.uid())))
);
CREATE POLICY profiles_update_self ON profiles FOR UPDATE TO authenticated USING (id = auth.uid());
CREATE POLICY profiles_all ON profiles FOR ALL TO authenticated USING (is_admin());
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
DROP POLICY IF EXISTS roster_status_select ON monthly_roster_status;
DROP POLICY IF EXISTS roster_status_all ON monthly_roster_status;
CREATE POLICY roster_status_select ON monthly_roster_status FOR SELECT TO authenticated USING (
  is_admin() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
CREATE POLICY roster_status_all ON monthly_roster_status FOR ALL TO authenticated USING (is_admin());
DROP POLICY IF EXISTS work_logs_select ON work_logs;
DROP POLICY IF EXISTS work_logs_insert ON work_logs;
DROP POLICY IF EXISTS work_logs_update ON work_logs;
CREATE POLICY work_logs_select ON work_logs FOR SELECT TO authenticated USING (
  is_admin() OR user_id = auth.uid() OR (is_instructor_or_admin() AND branch_id IN (SELECT user_branch_ids(auth.uid())))
);
CREATE POLICY work_logs_insert ON work_logs FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY work_logs_update ON work_logs FOR UPDATE TO authenticated USING (is_admin());
DROP POLICY IF EXISTS break_rules_select ON break_rules;
DROP POLICY IF EXISTS break_rules_all ON break_rules;
CREATE POLICY break_rules_select ON break_rules FOR SELECT TO authenticated USING (true);
CREATE POLICY break_rules_all ON break_rules FOR ALL TO authenticated USING (is_admin());
DROP POLICY IF EXISTS break_logs_select ON break_logs;
DROP POLICY IF EXISTS break_logs_insert ON break_logs;
DROP POLICY IF EXISTS break_logs_update ON break_logs;
CREATE POLICY break_logs_select ON break_logs FOR SELECT TO authenticated USING (
  is_admin() OR user_id = auth.uid() OR (is_instructor_or_admin() AND branch_id IN (SELECT user_branch_ids(auth.uid())))
);
CREATE POLICY break_logs_insert ON break_logs FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY break_logs_update ON break_logs FOR UPDATE TO authenticated USING (user_id = auth.uid() OR is_admin());
DROP POLICY IF EXISTS holiday_quotas_select ON holiday_quotas;
DROP POLICY IF EXISTS holiday_quotas_all ON holiday_quotas;
CREATE POLICY holiday_quotas_select ON holiday_quotas FOR SELECT TO authenticated USING (true);
CREATE POLICY holiday_quotas_all ON holiday_quotas FOR ALL TO authenticated USING (is_admin());
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
DROP POLICY IF EXISTS shift_swaps_select ON shift_swaps;
DROP POLICY IF EXISTS shift_swaps_insert ON shift_swaps;
DROP POLICY IF EXISTS shift_swaps_update ON shift_swaps;
CREATE POLICY shift_swaps_select ON shift_swaps FOR SELECT TO authenticated USING (
  is_admin() OR user_id = auth.uid() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
CREATE POLICY shift_swaps_insert ON shift_swaps FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY shift_swaps_update ON shift_swaps FOR UPDATE TO authenticated USING (is_admin() OR user_id = auth.uid());
DROP POLICY IF EXISTS transfers_select ON cross_branch_transfers;
DROP POLICY IF EXISTS transfers_insert ON cross_branch_transfers;
DROP POLICY IF EXISTS transfers_update ON cross_branch_transfers;
CREATE POLICY transfers_select ON cross_branch_transfers FOR SELECT TO authenticated USING (
  is_admin() OR user_id = auth.uid() OR from_branch_id IN (SELECT user_branch_ids(auth.uid())) OR to_branch_id IN (SELECT user_branch_ids(auth.uid()))
);
CREATE POLICY transfers_insert ON cross_branch_transfers FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY transfers_update ON cross_branch_transfers FOR UPDATE TO authenticated USING (is_admin() OR user_id = auth.uid());
DROP POLICY IF EXISTS duty_roles_select ON duty_roles;
DROP POLICY IF EXISTS duty_roles_all ON duty_roles;
CREATE POLICY duty_roles_select ON duty_roles FOR SELECT TO authenticated USING (
  is_admin() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
CREATE POLICY duty_roles_all ON duty_roles FOR ALL TO authenticated USING (is_admin());
DROP POLICY IF EXISTS duty_assignments_select ON duty_assignments;
DROP POLICY IF EXISTS duty_assignments_all ON duty_assignments;
CREATE POLICY duty_assignments_select ON duty_assignments FOR SELECT TO authenticated USING (
  is_admin() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
CREATE POLICY duty_assignments_all ON duty_assignments FOR ALL TO authenticated USING (is_admin());
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
DROP POLICY IF EXISTS schedule_cards_select ON schedule_cards;
DROP POLICY IF EXISTS schedule_cards_all ON schedule_cards;
DROP POLICY IF EXISTS schedule_cards_insert ON schedule_cards;
DROP POLICY IF EXISTS schedule_cards_update ON schedule_cards;
DROP POLICY IF EXISTS schedule_cards_delete ON schedule_cards;
CREATE POLICY schedule_cards_select ON schedule_cards FOR SELECT TO authenticated USING (
  is_admin()
  OR (
    (branch_id IS NULL OR branch_id IN (SELECT user_branch_ids(auth.uid())))
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role FROM profiles WHERE id = auth.uid()) = ANY(visible_roles))
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
DROP POLICY IF EXISTS group_links_select ON group_links;
DROP POLICY IF EXISTS group_links_all ON group_links;
CREATE POLICY group_links_select ON group_links FOR SELECT TO authenticated USING (true);
CREATE POLICY group_links_all ON group_links FOR ALL TO authenticated USING (is_admin());
DROP POLICY IF EXISTS password_vault_select ON password_vault;
DROP POLICY IF EXISTS password_vault_all ON password_vault;
CREATE POLICY password_vault_select ON password_vault FOR SELECT TO authenticated USING (true);
CREATE POLICY password_vault_all ON password_vault FOR ALL TO authenticated USING (is_admin());
DROP POLICY IF EXISTS audit_logs_select ON audit_logs;
DROP POLICY IF EXISTS audit_logs_insert ON audit_logs;
CREATE POLICY audit_logs_select ON audit_logs FOR SELECT TO authenticated USING (
  is_admin() OR (actor_id = auth.uid()) OR is_instructor_or_admin()
);
CREATE POLICY audit_logs_insert ON audit_logs FOR INSERT TO authenticated WITH CHECK (true);
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
INSERT INTO break_rules (min_staff, max_staff, concurrent_breaks)
SELECT 1, 5, 1 WHERE NOT EXISTS (SELECT 1 FROM break_rules LIMIT 1)
UNION ALL SELECT 6, 10, 2 WHERE NOT EXISTS (SELECT 1 FROM break_rules LIMIT 1)
UNION ALL SELECT 11, 15, 3 WHERE NOT EXISTS (SELECT 1 FROM break_rules LIMIT 1);
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

ALTER TABLE cross_branch_transfers ADD COLUMN IF NOT EXISTS admin_note TEXT;
INSERT INTO break_rules (min_staff, max_staff, concurrent_breaks)
SELECT 1, 5, 1 WHERE NOT EXISTS (SELECT 1 FROM break_rules LIMIT 1)
UNION ALL SELECT 6, 10, 2 WHERE NOT EXISTS (SELECT 1 FROM break_rules LIMIT 1)
UNION ALL SELECT 11, 15, 3 WHERE NOT EXISTS (SELECT 1 FROM break_rules LIMIT 1);
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE holidays; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE shift_swaps; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE cross_branch_transfers; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE duty_assignments; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE monthly_roster_status; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE monthly_roster; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE break_logs; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
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
GRANT EXECUTE ON FUNCTION public.get_email_for_login(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.get_email_for_login(TEXT) TO authenticated;
CREATE OR REPLACE FUNCTION is_staff_or_instructor()
RETURNS BOOLEAN AS $$ SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('instructor'::app_role, 'staff'::app_role)); $$ LANGUAGE sql SECURITY DEFINER STABLE;
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
CREATE TABLE IF NOT EXISTS websites (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  name TEXT NOT NULL, alias TEXT NOT NULL, url TEXT, description TEXT,
  is_active BOOLEAN DEFAULT true, created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(branch_id, alias)
);
CREATE INDEX IF NOT EXISTS idx_websites_branch ON websites(branch_id);
CREATE INDEX IF NOT EXISTS idx_websites_active ON websites(is_active);
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
GRANT EXECUTE ON FUNCTION set_primary_website(UUID, UUID) TO authenticated;
DROP TRIGGER IF EXISTS websites_updated_at ON websites;
CREATE TRIGGER websites_updated_at BEFORE UPDATE ON websites FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
CREATE OR REPLACE FUNCTION my_branch_id()
RETURNS UUID AS $$ SELECT p.default_branch_id FROM profiles p WHERE p.id = auth.uid() AND p.role IN ('instructor'::app_role, 'staff'::app_role) AND p.default_branch_id IS NOT NULL LIMIT 1; $$ LANGUAGE sql SECURITY DEFINER STABLE;
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_instructor_staff_must_have_branch;
ALTER TABLE profiles ADD CONSTRAINT profiles_instructor_staff_must_have_branch CHECK (
  (role IN ('instructor'::app_role, 'staff'::app_role) AND default_branch_id IS NOT NULL) OR (role NOT IN ('instructor'::app_role, 'staff'::app_role))
);
UPDATE profiles SET default_branch_id = (SELECT id FROM branches WHERE active = true ORDER BY name LIMIT 1)
WHERE role IN ('instructor'::app_role, 'staff'::app_role) AND default_branch_id IS NULL AND EXISTS (SELECT 1 FROM branches WHERE active = true LIMIT 1);
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
CREATE OR REPLACE FUNCTION my_user_group()
RETURNS TEXT AS $$ SELECT CASE p.role WHEN 'instructor'::app_role THEN 'INSTRUCTOR' WHEN 'staff'::app_role THEN 'STAFF' ELSE NULL END FROM profiles p WHERE p.id = auth.uid() LIMIT 1; $$ LANGUAGE sql SECURITY DEFINER STABLE;
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
UPDATE work_logs w SET user_group = CASE p.role WHEN 'instructor'::app_role THEN 'INSTRUCTOR' WHEN 'staff'::app_role THEN 'STAFF' ELSE 'STAFF' END FROM profiles p WHERE w.user_id = p.id AND w.user_group IS NULL;
UPDATE work_logs SET user_group = 'STAFF' WHERE user_group IS NULL;
UPDATE break_logs b SET user_group = CASE p.role WHEN 'instructor'::app_role THEN 'INSTRUCTOR' WHEN 'staff'::app_role THEN 'STAFF' ELSE 'STAFF' END FROM profiles p WHERE b.user_id = p.id AND b.user_group IS NULL;
UPDATE break_logs SET user_group = 'STAFF' WHERE user_group IS NULL;
UPDATE holidays h SET user_group = CASE p.role WHEN 'instructor'::app_role THEN 'INSTRUCTOR' WHEN 'staff'::app_role THEN 'STAFF' ELSE 'STAFF' END FROM profiles p WHERE h.user_id = p.id AND h.user_group IS NULL;
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
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE first_branch_id UUID;
BEGIN
  SELECT id INTO first_branch_id FROM public.branches ORDER BY (active IS NOT TRUE), name LIMIT 1;
  INSERT INTO public.profiles (id, email, display_name, role, default_branch_id)
  VALUES (NEW.id, NEW.email, COALESCE(NEW.raw_user_meta_data->>'name', NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)), 'staff'::app_role, first_branch_id)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;
ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'instructor_head';
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_instructor_staff_must_have_branch;
ALTER TABLE profiles ADD CONSTRAINT profiles_instructor_staff_must_have_branch CHECK (
  (role IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role) AND default_branch_id IS NOT NULL) OR (role NOT IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role))
);
CREATE OR REPLACE FUNCTION my_branch_id()
RETURNS UUID AS $$ SELECT p.default_branch_id FROM profiles p WHERE p.id = auth.uid() AND p.role IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role) AND p.default_branch_id IS NOT NULL LIMIT 1; $$ LANGUAGE sql SECURITY DEFINER STABLE;
CREATE OR REPLACE FUNCTION is_staff_or_instructor()
RETURNS BOOLEAN AS $$ SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role)); $$ LANGUAGE sql SECURITY DEFINER STABLE;
CREATE OR REPLACE FUNCTION is_instructor_or_admin()
RETURNS BOOLEAN AS $$ SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin'::app_role, 'instructor'::app_role, 'instructor_head'::app_role)); $$ LANGUAGE sql SECURITY DEFINER STABLE;
CREATE OR REPLACE FUNCTION is_instructor_head()
RETURNS BOOLEAN AS $$ SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'instructor_head'::app_role); $$ LANGUAGE sql SECURITY DEFINER STABLE;
DROP POLICY IF EXISTS profiles_select ON profiles;
CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated USING (
  is_admin() OR id = auth.uid() OR is_instructor_or_admin() OR (is_instructor_head() AND (id = auth.uid() OR (default_branch_id = my_branch_id() AND role IN ('instructor'::app_role, 'staff'::app_role))))
);
DROP POLICY IF EXISTS profiles_update_self ON profiles;
CREATE POLICY profiles_update_self ON profiles FOR UPDATE TO authenticated USING (id = auth.uid());
DROP POLICY IF EXISTS profiles_update_branch_head ON profiles;
CREATE POLICY profiles_update_branch_head ON profiles FOR UPDATE TO authenticated USING (is_admin() OR (is_instructor_head() AND default_branch_id = my_branch_id() AND role IN ('instructor'::app_role, 'staff'::app_role)));
CREATE OR REPLACE FUNCTION my_user_group()
RETURNS TEXT AS $$ SELECT CASE p.role WHEN 'instructor'::app_role THEN 'INSTRUCTOR' WHEN 'instructor_head'::app_role THEN 'INSTRUCTOR' WHEN 'staff'::app_role THEN 'STAFF' ELSE NULL END FROM profiles p WHERE p.id = auth.uid() LIMIT 1; $$ LANGUAGE sql SECURITY DEFINER STABLE;
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE first_branch_id UUID;
BEGIN
  SELECT id INTO first_branch_id FROM public.branches ORDER BY (active IS NOT TRUE), name LIMIT 1;
  INSERT INTO public.profiles (id, email, display_name, role, default_branch_id)
  VALUES (NEW.id, NEW.email, COALESCE(NEW.raw_user_meta_data->>'name', NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)), 'staff'::app_role, first_branch_id)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();
ALTER TABLE group_links ADD COLUMN IF NOT EXISTS website_id UUID REFERENCES websites(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_group_links_website ON group_links(website_id);
DROP POLICY IF EXISTS group_links_all ON group_links;
DROP POLICY IF EXISTS group_links_select ON group_links;
CREATE POLICY group_links_select ON group_links FOR SELECT TO authenticated USING (is_admin() OR (my_branch_id() IS NOT NULL AND (branch_id = my_branch_id() OR branch_id IS NULL)));
CREATE POLICY group_links_insert ON group_links FOR INSERT TO authenticated WITH CHECK (is_admin() OR (is_instructor_head() AND branch_id = my_branch_id()));
CREATE POLICY group_links_update ON group_links FOR UPDATE TO authenticated USING (is_admin() OR (is_instructor_head() AND branch_id = my_branch_id()));
CREATE POLICY group_links_delete ON group_links FOR DELETE TO authenticated USING (is_admin() OR (is_instructor_head() AND branch_id = my_branch_id()));
CREATE TABLE IF NOT EXISTS holiday_booking_config (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), target_year_month TEXT NOT NULL UNIQUE,
  open_from DATE NOT NULL, open_until DATE NOT NULL, max_days_per_person INT NOT NULL DEFAULT 4,
  created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT holiday_booking_config_dates_check CHECK (open_until >= open_from)
);
CREATE INDEX IF NOT EXISTS idx_holiday_booking_config_target ON holiday_booking_config(target_year_month);
ALTER TABLE holiday_booking_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS holiday_booking_config_select ON holiday_booking_config;
CREATE POLICY holiday_booking_config_select ON holiday_booking_config FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS holiday_booking_config_all ON holiday_booking_config;
CREATE POLICY holiday_booking_config_all ON holiday_booking_config FOR ALL TO authenticated USING (is_admin());
DROP POLICY IF EXISTS holidays_update ON holidays;
CREATE POLICY holidays_update ON holidays FOR UPDATE TO authenticated USING (is_admin() OR user_id = auth.uid() OR (is_instructor_head() AND branch_id = my_branch_id()));
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
CREATE TABLE IF NOT EXISTS shift_swap_rounds (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  start_date DATE NOT NULL, end_date DATE NOT NULL, pairs_per_day INT NOT NULL DEFAULT 2,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published')),
  created_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE, created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_shift_swap_rounds_branch ON shift_swap_rounds(branch_id);
CREATE INDEX IF NOT EXISTS idx_shift_swap_rounds_dates ON shift_swap_rounds(start_date, end_date);
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
ALTER TABLE shift_swap_rounds ADD COLUMN IF NOT EXISTS website_id UUID REFERENCES websites(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_shift_swap_rounds_website ON shift_swap_rounds(website_id);
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
ALTER TABLE schedule_cards ADD COLUMN IF NOT EXISTS visible_roles TEXT[] DEFAULT '{}';
ALTER TABLE schedule_cards ADD COLUMN IF NOT EXISTS website_id UUID REFERENCES websites(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_schedule_cards_website ON schedule_cards(website_id);
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
DROP POLICY IF EXISTS "vault_insert_admin_head" ON storage.objects;
CREATE POLICY "vault_insert_admin_head" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'vault' AND (public.is_admin() OR public.is_instructor_head()));
DROP POLICY IF EXISTS "vault_select_authenticated" ON storage.objects;
CREATE POLICY "vault_select_authenticated" ON storage.objects FOR SELECT TO authenticated USING (bucket_id = 'vault');
DROP POLICY IF EXISTS "vault_update_admin_head" ON storage.objects;
CREATE POLICY "vault_update_admin_head" ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'vault' AND (public.is_admin() OR public.is_instructor_head()));
DROP POLICY IF EXISTS "vault_delete_admin_head" ON storage.objects;
CREATE POLICY "vault_delete_admin_head" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'vault' AND (public.is_admin() OR public.is_instructor_head()));
ALTER TABLE file_vault ADD COLUMN IF NOT EXISTS visible_roles TEXT[] DEFAULT '{}';
DROP POLICY IF EXISTS file_vault_select ON file_vault;
CREATE POLICY file_vault_select ON file_vault FOR SELECT TO authenticated USING (
  is_admin() OR (
    (branch_id IS NULL OR branch_id IN (SELECT user_branch_ids(auth.uid())))
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles))
    AND (website_id IS NULL OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid()))
  )
);
ALTER TABLE group_links ADD COLUMN IF NOT EXISTS visible_roles TEXT[] DEFAULT '{}';
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

ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'manager';

CREATE OR REPLACE FUNCTION set_primary_website(p_user_id UUID, p_website_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_user_id IS NULL OR p_website_id IS NULL THEN RETURN; END IF;
  IF NOT is_admin() AND NOT is_instructor_head() THEN
    RAISE EXCEPTION 'ไม่มีสิทธิ์ตั้งเว็บหลัก';
  END IF;
  IF is_instructor_head() AND NOT is_admin() THEN
    IF (SELECT default_branch_id FROM profiles WHERE id = p_user_id) IS DISTINCT FROM my_branch_id() THEN
      RAISE EXCEPTION 'ไม่สามารถตั้งเว็บหลักให้ผู้ใช้ในสาขาอื่นได้';
    END IF;
  END IF;
  UPDATE website_assignments SET is_primary = false WHERE user_id = p_user_id;
  UPDATE website_assignments SET is_primary = true WHERE user_id = p_user_id AND website_id = p_website_id;
END;
$$;
DROP POLICY IF EXISTS duty_roles_all ON duty_roles;
CREATE POLICY duty_roles_insert ON duty_roles FOR INSERT TO authenticated WITH CHECK (
  is_admin() OR (is_instructor_head() AND branch_id = my_branch_id())
);
CREATE POLICY duty_roles_update ON duty_roles FOR UPDATE TO authenticated USING (
  is_admin() OR (is_instructor_head() AND branch_id = my_branch_id())
);
CREATE POLICY duty_roles_delete ON duty_roles FOR DELETE TO authenticated USING (
  is_admin() OR (is_instructor_head() AND branch_id = my_branch_id())
);
DROP POLICY IF EXISTS duty_assignments_all ON duty_assignments;
CREATE POLICY duty_assignments_insert ON duty_assignments FOR INSERT TO authenticated WITH CHECK (
  is_admin() OR (is_instructor_head() AND branch_id = my_branch_id())
);
CREATE POLICY duty_assignments_update ON duty_assignments FOR UPDATE TO authenticated USING (
  is_admin() OR (is_instructor_head() AND branch_id = my_branch_id())
);
CREATE POLICY duty_assignments_delete ON duty_assignments FOR DELETE TO authenticated USING (
  is_admin() OR (is_instructor_head() AND branch_id = my_branch_id())
);
DROP POLICY IF EXISTS group_links_select ON group_links;
CREATE POLICY group_links_select ON group_links FOR SELECT TO authenticated USING (
  is_admin()
  OR (is_instructor_head() AND (branch_id IS NULL OR branch_id = my_branch_id()))
  OR (
    (branch_id IS NULL OR branch_id = my_branch_id())
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles))
  )
);
CREATE TABLE IF NOT EXISTS holiday_quota_tiers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  dimension TEXT NOT NULL CHECK (dimension IN ('branch', 'shift', 'website')),
  user_group TEXT NOT NULL CHECK (user_group IN ('INSTRUCTOR', 'STAFF')),
  max_people INT NOT NULL CHECK (max_people > 0),
  max_leave INT NOT NULL CHECK (max_leave >= 0),
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_holiday_quota_tiers_dimension_group ON holiday_quota_tiers(dimension, user_group);
ALTER TABLE holiday_quota_tiers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS holiday_quota_tiers_select ON holiday_quota_tiers;
CREATE POLICY holiday_quota_tiers_select ON holiday_quota_tiers FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS holiday_quota_tiers_all ON holiday_quota_tiers;
CREATE POLICY holiday_quota_tiers_all ON holiday_quota_tiers FOR ALL TO authenticated USING (is_admin());
CREATE TRIGGER holiday_quota_tiers_updated_at
  BEFORE UPDATE ON holiday_quota_tiers FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
DROP POLICY IF EXISTS holidays_select ON holidays;
CREATE POLICY holidays_select ON holidays FOR SELECT TO authenticated USING (
  is_admin()
  OR is_instructor_head()
  OR (my_branch_id() IS NOT NULL AND branch_id = my_branch_id() AND user_group = my_user_group())
);
DROP POLICY IF EXISTS holidays_insert ON holidays;
CREATE POLICY holidays_insert ON holidays FOR INSERT TO authenticated WITH CHECK (
  is_admin()
  OR is_instructor_head()
  OR (
    user_id = auth.uid()
    AND is_staff_or_instructor()
    AND branch_id = my_branch_id()
    AND user_group = my_user_group()
  )
);
DROP POLICY IF EXISTS holidays_update ON holidays;
CREATE POLICY holidays_update ON holidays FOR UPDATE TO authenticated USING (
  is_admin()
  OR is_instructor_head()
  OR user_id = auth.uid()
);
DROP POLICY IF EXISTS holidays_delete ON holidays;
CREATE POLICY holidays_delete ON holidays FOR DELETE TO authenticated USING (
  is_admin()
  OR is_instructor_head()
  OR user_id = auth.uid()
);
DROP POLICY IF EXISTS profiles_select ON profiles;
CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated USING (
  is_admin()
  OR id = auth.uid()
  OR is_instructor_or_admin()
  OR (is_instructor_head() AND (id = auth.uid() OR (default_branch_id = my_branch_id() AND role IN ('instructor'::app_role, 'staff'::app_role))))
  OR (my_branch_id() IS NOT NULL AND default_branch_id = my_branch_id() AND role IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role))
);
CREATE TABLE IF NOT EXISTS group_link_branches (
  group_link_id UUID NOT NULL REFERENCES group_links(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  PRIMARY KEY (group_link_id, branch_id)
);
CREATE INDEX IF NOT EXISTS idx_group_link_branches_link ON group_link_branches(group_link_id);
CREATE INDEX IF NOT EXISTS idx_group_link_branches_branch ON group_link_branches(branch_id);
DROP POLICY IF EXISTS group_links_select ON group_links;
CREATE POLICY group_links_select ON group_links FOR SELECT TO authenticated USING (
  is_admin()
  OR (is_instructor_head() AND (branch_id IS NULL OR branch_id = my_branch_id()
      OR EXISTS (SELECT 1 FROM group_link_branches glb WHERE glb.group_link_id = group_links.id AND glb.branch_id = my_branch_id())))
  OR (
    (branch_id IS NULL OR branch_id = my_branch_id()
     OR EXISTS (SELECT 1 FROM group_link_branches glb WHERE glb.group_link_id = group_links.id AND glb.branch_id = my_branch_id()))
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles))
  )
);
DROP POLICY IF EXISTS group_links_insert ON group_links;
CREATE POLICY group_links_insert ON group_links FOR INSERT TO authenticated WITH CHECK (
  is_admin() OR (is_instructor_head() AND (branch_id = my_branch_id() OR branch_id IS NULL))
);
DROP POLICY IF EXISTS group_links_update ON group_links;
CREATE POLICY group_links_update ON group_links FOR UPDATE TO authenticated USING (
  is_admin() OR (is_instructor_head() AND (
    branch_id = my_branch_id()
    OR (branch_id IS NULL AND EXISTS (SELECT 1 FROM group_link_branches glb WHERE glb.group_link_id = group_links.id AND glb.branch_id = my_branch_id()))
  ))
);
ALTER TABLE group_link_branches ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS group_link_branches_select ON group_link_branches;
CREATE POLICY group_link_branches_select ON group_link_branches FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM group_links g WHERE g.id = group_link_id AND (
    is_admin() OR (g.branch_id IS NULL OR g.branch_id = my_branch_id())
    OR EXISTS (SELECT 1 FROM group_link_branches glb WHERE glb.group_link_id = g.id AND glb.branch_id = my_branch_id())
  ))
);
DROP POLICY IF EXISTS group_link_branches_insert ON group_link_branches;
CREATE POLICY group_link_branches_insert ON group_link_branches FOR INSERT TO authenticated WITH CHECK (
  is_admin() OR (is_instructor_head() AND branch_id = my_branch_id())
);
DROP POLICY IF EXISTS group_link_branches_delete ON group_link_branches;
CREATE POLICY group_link_branches_delete ON group_link_branches FOR DELETE TO authenticated USING (
  EXISTS (SELECT 1 FROM group_links g WHERE g.id = group_link_id AND (is_admin() OR (is_instructor_head() AND (g.branch_id = my_branch_id() OR g.branch_id IS NULL))))
);
ALTER TABLE file_vault DROP CONSTRAINT IF EXISTS file_vault_file_path_key;
CREATE OR REPLACE FUNCTION is_manager()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'manager'::app_role);
$$ LANGUAGE sql SECURITY DEFINER STABLE;
CREATE OR REPLACE FUNCTION is_admin_or_manager()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin'::app_role, 'manager'::app_role));
$$ LANGUAGE sql SECURITY DEFINER STABLE;
CREATE OR REPLACE FUNCTION is_employee_role()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('manager'::app_role, 'instructor_head'::app_role, 'instructor'::app_role, 'staff'::app_role));
$$ LANGUAGE sql SECURITY DEFINER STABLE;
CREATE OR REPLACE FUNCTION my_branch_id()
RETURNS UUID AS $$
  SELECT p.default_branch_id FROM profiles p
  WHERE p.id = auth.uid() AND p.role IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role, 'manager'::app_role) AND p.default_branch_id IS NOT NULL
  LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER STABLE;
CREATE OR REPLACE FUNCTION is_staff_or_instructor()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role, 'manager'::app_role));
$$ LANGUAGE sql SECURITY DEFINER STABLE;
CREATE OR REPLACE FUNCTION my_user_group()
RETURNS TEXT AS $$
  SELECT CASE p.role
    WHEN 'instructor'::app_role THEN 'INSTRUCTOR'
    WHEN 'instructor_head'::app_role THEN 'INSTRUCTOR'
    WHEN 'staff'::app_role THEN 'STAFF'
    WHEN 'manager'::app_role THEN 'MANAGER'
    ELSE NULL
  END FROM profiles p WHERE p.id = auth.uid() LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER STABLE;
CREATE OR REPLACE FUNCTION user_branch_ids(uid UUID)
RETURNS SETOF UUID AS $$
  SELECT DISTINCT b.id FROM branches b
  JOIN profiles p ON p.id = uid
  WHERE p.role IN ('admin'::app_role, 'manager'::app_role)
  UNION
  SELECT p.default_branch_id FROM profiles p WHERE p.id = uid AND p.default_branch_id IS NOT NULL AND p.role NOT IN ('admin'::app_role, 'manager'::app_role)
  UNION
  SELECT cbt.to_branch_id FROM cross_branch_transfers cbt
  WHERE cbt.user_id = uid AND cbt.status = 'approved'
    AND current_date BETWEEN cbt.start_date AND cbt.end_date
  UNION
  SELECT cbt.from_branch_id FROM cross_branch_transfers cbt
  WHERE cbt.user_id = uid AND cbt.status = 'approved'
    AND (current_date < cbt.start_date OR current_date > cbt.end_date);
$$ LANGUAGE sql SECURITY DEFINER STABLE;
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_instructor_staff_must_have_branch;
ALTER TABLE profiles ADD CONSTRAINT profiles_instructor_staff_must_have_branch CHECK (
  (role IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role, 'manager'::app_role) AND default_branch_id IS NOT NULL)
  OR (role NOT IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role, 'manager'::app_role))
);
ALTER TABLE holiday_quota_tiers DROP CONSTRAINT IF EXISTS holiday_quota_tiers_user_group_check;
ALTER TABLE holiday_quota_tiers ADD CONSTRAINT holiday_quota_tiers_user_group_check CHECK (user_group IN ('INSTRUCTOR', 'STAFF', 'MANAGER'));
ALTER TABLE break_rules DROP CONSTRAINT IF EXISTS break_rules_user_group_check;
ALTER TABLE break_rules ADD CONSTRAINT break_rules_user_group_check CHECK (user_group IN ('INSTRUCTOR', 'STAFF', 'MANAGER'));
ALTER TABLE work_logs DROP CONSTRAINT IF EXISTS work_logs_user_group_check;
ALTER TABLE work_logs ADD CONSTRAINT work_logs_user_group_check CHECK (user_group IN ('INSTRUCTOR', 'STAFF', 'MANAGER'));
ALTER TABLE break_logs DROP CONSTRAINT IF EXISTS break_logs_user_group_check;
ALTER TABLE break_logs ADD CONSTRAINT break_logs_user_group_check CHECK (user_group IN ('INSTRUCTOR', 'STAFF', 'MANAGER'));
ALTER TABLE holidays DROP CONSTRAINT IF EXISTS holidays_user_group_check;
ALTER TABLE holidays ADD CONSTRAINT holidays_user_group_check CHECK (user_group IN ('INSTRUCTOR', 'STAFF', 'MANAGER'));
ALTER TABLE holiday_quotas DROP CONSTRAINT IF EXISTS holiday_quotas_user_group_check;
ALTER TABLE holiday_quotas ADD CONSTRAINT holiday_quotas_user_group_check CHECK (user_group IN ('INSTRUCTOR', 'STAFF', 'MANAGER'));
DROP POLICY IF EXISTS profiles_select ON profiles;
CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated USING (
  is_admin() OR is_manager() OR id = auth.uid()
  OR is_instructor_or_admin() OR (is_instructor_head() AND (id = auth.uid() OR (default_branch_id = my_branch_id() AND role IN ('instructor'::app_role, 'staff'::app_role))))
  OR (my_branch_id() IS NOT NULL AND default_branch_id = my_branch_id() AND role IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role))
);
CREATE OR REPLACE FUNCTION profiles_guard_admin_manager_role()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.role IN ('admin'::app_role, 'manager'::app_role) AND NOT is_admin() THEN
    RAISE EXCEPTION 'ไม่มีสิทธิ์ตั้งบทบาทเป็น admin หรือ manager';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
DROP TRIGGER IF EXISTS profiles_guard_admin_manager_trigger ON profiles;
CREATE TRIGGER profiles_guard_admin_manager_trigger
  BEFORE UPDATE ON profiles FOR EACH ROW
  WHEN (OLD.role IS DISTINCT FROM NEW.role)
  EXECUTE PROCEDURE profiles_guard_admin_manager_role();
DROP POLICY IF EXISTS profiles_update_self ON profiles;
CREATE POLICY profiles_update_self ON profiles FOR UPDATE TO authenticated USING (id = auth.uid());
DROP POLICY IF EXISTS profiles_update_branch_head ON profiles;
CREATE POLICY profiles_update_branch_head ON profiles FOR UPDATE TO authenticated USING (
  is_admin() OR (is_instructor_head() AND default_branch_id = my_branch_id() AND role IN ('instructor'::app_role, 'staff'::app_role))
);
DROP POLICY IF EXISTS profiles_update_manager ON profiles;
CREATE POLICY profiles_update_manager ON profiles FOR UPDATE TO authenticated USING (
  is_manager() AND id != auth.uid() AND role IN ('instructor_head'::app_role, 'instructor'::app_role, 'staff'::app_role)
);
DROP POLICY IF EXISTS profiles_all ON profiles;
CREATE POLICY profiles_all ON profiles FOR ALL TO authenticated USING (is_admin());
DROP POLICY IF EXISTS branches_all ON branches;
CREATE POLICY branches_all ON branches FOR ALL TO authenticated USING (is_admin_or_manager());
DROP POLICY IF EXISTS shifts_all ON shifts;
CREATE POLICY shifts_all ON shifts FOR ALL TO authenticated USING (is_admin_or_manager());
DROP POLICY IF EXISTS break_rules_all ON break_rules;
CREATE POLICY break_rules_all ON break_rules FOR ALL TO authenticated USING (is_admin_or_manager());
DROP POLICY IF EXISTS holiday_quotas_all ON holiday_quotas;
CREATE POLICY holiday_quotas_all ON holiday_quotas FOR ALL TO authenticated USING (is_admin_or_manager());
DROP POLICY IF EXISTS holiday_quota_tiers_all ON holiday_quota_tiers;
CREATE POLICY holiday_quota_tiers_all ON holiday_quota_tiers FOR ALL TO authenticated USING (is_admin_or_manager());
DROP POLICY IF EXISTS roster_status_all ON monthly_roster_status;
CREATE POLICY roster_status_all ON monthly_roster_status FOR ALL TO authenticated USING (is_admin_or_manager());
DROP POLICY IF EXISTS monthly_roster_insert ON monthly_roster;
CREATE POLICY monthly_roster_insert ON monthly_roster FOR INSERT TO authenticated WITH CHECK (is_admin_or_manager());
DROP POLICY IF EXISTS monthly_roster_update ON monthly_roster;
CREATE POLICY monthly_roster_update ON monthly_roster FOR UPDATE TO authenticated USING (is_admin_or_manager());
DROP POLICY IF EXISTS monthly_roster_delete ON monthly_roster;
CREATE POLICY monthly_roster_delete ON monthly_roster FOR DELETE TO authenticated USING (is_admin_or_manager());
DROP POLICY IF EXISTS duty_roles_all ON duty_roles;
CREATE POLICY duty_roles_all ON duty_roles FOR ALL TO authenticated USING (is_admin_or_manager());
DROP POLICY IF EXISTS duty_assignments_all ON duty_assignments;
CREATE POLICY duty_assignments_all ON duty_assignments FOR ALL TO authenticated USING (is_admin_or_manager());
DROP POLICY IF EXISTS schedule_cards_insert ON schedule_cards;
CREATE POLICY schedule_cards_insert ON schedule_cards FOR INSERT TO authenticated WITH CHECK (
  is_admin_or_manager() OR (is_instructor_head() AND branch_id = my_branch_id())
);
DROP POLICY IF EXISTS schedule_cards_update ON schedule_cards;
CREATE POLICY schedule_cards_update ON schedule_cards FOR UPDATE TO authenticated USING (
  is_admin_or_manager() OR (is_instructor_head() AND branch_id = my_branch_id())
);
DROP POLICY IF EXISTS schedule_cards_delete ON schedule_cards;
CREATE POLICY schedule_cards_delete ON schedule_cards FOR DELETE TO authenticated USING (
  is_admin_or_manager() OR (is_instructor_head() AND branch_id = my_branch_id())
);
DROP POLICY IF EXISTS group_links_select ON group_links;
CREATE POLICY group_links_select ON group_links FOR SELECT TO authenticated USING (
  is_admin() OR is_manager()
  OR (is_instructor_head() AND (branch_id IS NULL OR branch_id = my_branch_id()
      OR EXISTS (SELECT 1 FROM group_link_branches glb WHERE glb.group_link_id = group_links.id AND glb.branch_id = my_branch_id())))
  OR (
    (branch_id IS NULL OR branch_id = my_branch_id()
     OR EXISTS (SELECT 1 FROM group_link_branches glb WHERE glb.group_link_id = group_links.id AND glb.branch_id = my_branch_id()))
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles))
  )
);
DROP POLICY IF EXISTS group_links_all ON group_links;
CREATE POLICY group_links_all ON group_links FOR ALL TO authenticated USING (is_admin_or_manager());
DROP POLICY IF EXISTS password_vault_all ON password_vault;
CREATE POLICY password_vault_all ON password_vault FOR ALL TO authenticated USING (is_admin_or_manager());
DROP POLICY IF EXISTS file_vault_select ON file_vault;
CREATE POLICY file_vault_select ON file_vault FOR SELECT TO authenticated USING (
  is_admin_or_manager() OR (branch_id IS NULL AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles)))
  OR (branch_id IN (SELECT user_branch_ids(auth.uid())) AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles)))
);
DROP POLICY IF EXISTS file_vault_insert ON file_vault;
CREATE POLICY file_vault_insert ON file_vault FOR INSERT TO authenticated WITH CHECK (
  is_admin_or_manager() OR (is_instructor_head() AND (branch_id = my_branch_id() OR branch_id IS NULL))
);
DROP POLICY IF EXISTS file_vault_update ON file_vault;
CREATE POLICY file_vault_update ON file_vault FOR UPDATE TO authenticated USING (
  is_admin_or_manager() OR (is_instructor_head() AND (branch_id = my_branch_id() OR branch_id IS NULL))
);
DROP POLICY IF EXISTS file_vault_delete ON file_vault;
CREATE POLICY file_vault_delete ON file_vault FOR DELETE TO authenticated USING (
  is_admin_or_manager() OR (is_instructor_head() AND (branch_id = my_branch_id() OR branch_id IS NULL))
);
DROP POLICY IF EXISTS holiday_booking_config_all ON holiday_booking_config;
CREATE POLICY holiday_booking_config_all ON holiday_booking_config FOR ALL TO authenticated USING (is_admin_or_manager());
DROP POLICY IF EXISTS schedule_cards_select ON schedule_cards;
CREATE POLICY schedule_cards_select ON schedule_cards FOR SELECT TO authenticated USING (
  is_admin_or_manager()
  OR (
    (branch_id IS NULL OR branch_id IN (SELECT user_branch_ids(auth.uid())))
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles))
    AND (website_id IS NULL OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid()))
  )
);
DROP POLICY IF EXISTS websites_select ON websites;
CREATE POLICY websites_select ON websites FOR SELECT TO authenticated USING (
  is_admin_or_manager() OR id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid()) OR (is_instructor_head() AND branch_id = my_branch_id())
);
DROP POLICY IF EXISTS websites_insert ON websites;
CREATE POLICY websites_insert ON websites FOR INSERT TO authenticated WITH CHECK (is_admin_or_manager());
DROP POLICY IF EXISTS websites_update ON websites;
CREATE POLICY websites_update ON websites FOR UPDATE TO authenticated USING (is_admin_or_manager());
DROP POLICY IF EXISTS websites_delete ON websites;
CREATE POLICY websites_delete ON websites FOR DELETE TO authenticated USING (is_admin_or_manager());
DROP POLICY IF EXISTS website_assignments_select ON website_assignments;
CREATE POLICY website_assignments_select ON website_assignments FOR SELECT TO authenticated USING (is_admin_or_manager() OR user_id = auth.uid());
DROP POLICY IF EXISTS website_assignments_insert ON website_assignments;
CREATE POLICY website_assignments_insert ON website_assignments FOR INSERT TO authenticated WITH CHECK (is_admin_or_manager());
DROP POLICY IF EXISTS website_assignments_update ON website_assignments;
CREATE POLICY website_assignments_update ON website_assignments FOR UPDATE TO authenticated USING (is_admin_or_manager());
DROP POLICY IF EXISTS website_assignments_delete ON website_assignments;
CREATE POLICY website_assignments_delete ON website_assignments FOR DELETE TO authenticated USING (is_admin_or_manager());
DROP POLICY IF EXISTS audit_logs_select ON audit_logs;
CREATE POLICY audit_logs_select ON audit_logs FOR SELECT TO authenticated USING (
  is_admin_or_manager() OR (actor_id = auth.uid()) OR is_instructor_or_admin()
);
DROP POLICY IF EXISTS work_logs_select ON work_logs;
CREATE POLICY work_logs_select ON work_logs FOR SELECT TO authenticated USING (
  is_admin_or_manager() OR user_id = auth.uid() OR (is_instructor_or_admin() AND branch_id IN (SELECT user_branch_ids(auth.uid())))
);
DROP POLICY IF EXISTS work_logs_insert ON work_logs;
CREATE POLICY work_logs_insert ON work_logs FOR INSERT TO authenticated WITH CHECK (
  user_id = auth.uid() AND is_staff_or_instructor() AND (is_admin_or_manager() OR branch_id = my_branch_id()) AND user_group = my_user_group()
);
DROP POLICY IF EXISTS work_logs_update ON work_logs;
CREATE POLICY work_logs_update ON work_logs FOR UPDATE TO authenticated USING (is_admin_or_manager() OR user_id = auth.uid());
DROP POLICY IF EXISTS break_logs_select ON break_logs;
CREATE POLICY break_logs_select ON break_logs FOR SELECT TO authenticated USING (
  is_admin_or_manager() OR user_id = auth.uid() OR (is_instructor_or_admin() AND branch_id IN (SELECT user_branch_ids(auth.uid())))
);
DROP POLICY IF EXISTS break_logs_insert ON break_logs;
CREATE POLICY break_logs_insert ON break_logs FOR INSERT TO authenticated WITH CHECK (
  user_id = auth.uid() AND is_staff_or_instructor() AND (is_admin_or_manager() OR branch_id = my_branch_id()) AND user_group = my_user_group()
);
DROP POLICY IF EXISTS break_logs_update ON break_logs;
CREATE POLICY break_logs_update ON break_logs FOR UPDATE TO authenticated USING (user_id = auth.uid() OR is_admin_or_manager());
DROP POLICY IF EXISTS holidays_select ON holidays;
CREATE POLICY holidays_select ON holidays FOR SELECT TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head()
  OR (my_branch_id() IS NOT NULL AND branch_id = my_branch_id() AND user_group = my_user_group())
);
DROP POLICY IF EXISTS holidays_insert ON holidays;
CREATE POLICY holidays_insert ON holidays FOR INSERT TO authenticated WITH CHECK (
  is_admin() OR is_manager() OR is_instructor_head()
  OR (
    user_id = auth.uid()
    AND is_staff_or_instructor()
    AND branch_id = my_branch_id()
    AND user_group = my_user_group()
  )
);
DROP POLICY IF EXISTS holidays_update ON holidays;
CREATE POLICY holidays_update ON holidays FOR UPDATE TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head() OR user_id = auth.uid()
);
DROP POLICY IF EXISTS holidays_delete ON holidays;
CREATE POLICY holidays_delete ON holidays FOR DELETE TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head() OR user_id = auth.uid()
);
DROP POLICY IF EXISTS shift_swaps_select ON shift_swaps;
CREATE POLICY shift_swaps_select ON shift_swaps FOR SELECT TO authenticated USING (
  is_admin_or_manager() OR user_id = auth.uid() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
DROP POLICY IF EXISTS shift_swaps_insert ON shift_swaps;
CREATE POLICY shift_swaps_insert ON shift_swaps FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND is_staff_or_instructor());
DROP POLICY IF EXISTS shift_swaps_update ON shift_swaps;
CREATE POLICY shift_swaps_update ON shift_swaps FOR UPDATE TO authenticated USING (is_admin_or_manager() OR user_id = auth.uid());
DROP POLICY IF EXISTS transfers_select ON cross_branch_transfers;
CREATE POLICY transfers_select ON cross_branch_transfers FOR SELECT TO authenticated USING (
  is_admin_or_manager() OR user_id = auth.uid() OR from_branch_id IN (SELECT user_branch_ids(auth.uid())) OR to_branch_id IN (SELECT user_branch_ids(auth.uid()))
);
DROP POLICY IF EXISTS transfers_insert ON cross_branch_transfers;
CREATE POLICY transfers_insert ON cross_branch_transfers FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND is_staff_or_instructor());
DROP POLICY IF EXISTS transfers_update ON cross_branch_transfers;
CREATE POLICY transfers_update ON cross_branch_transfers FOR UPDATE TO authenticated USING (is_admin_or_manager() OR user_id = auth.uid());
DROP POLICY IF EXISTS duty_roles_select ON duty_roles;
CREATE POLICY duty_roles_select ON duty_roles FOR SELECT TO authenticated USING (
  is_admin_or_manager() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
DROP POLICY IF EXISTS duty_assignments_select ON duty_assignments;
CREATE POLICY duty_assignments_select ON duty_assignments FOR SELECT TO authenticated USING (
  is_admin_or_manager() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
DROP POLICY IF EXISTS monthly_roster_select ON monthly_roster;
CREATE POLICY monthly_roster_select ON monthly_roster FOR SELECT TO authenticated USING (
  is_admin_or_manager() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
DROP POLICY IF EXISTS roster_status_select ON monthly_roster_status;
CREATE POLICY roster_status_select ON monthly_roster_status FOR SELECT TO authenticated USING (
  is_admin_or_manager() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
DROP POLICY IF EXISTS break_rules_select ON break_rules;
CREATE POLICY break_rules_select ON break_rules FOR SELECT TO authenticated USING (
  true
);
DROP POLICY IF EXISTS holiday_quotas_select ON holiday_quotas;
CREATE POLICY holiday_quotas_select ON holiday_quotas FOR SELECT TO authenticated USING (true);
CREATE INDEX IF NOT EXISTS idx_break_logs_branch_shift_date_status ON break_logs(branch_id, shift_id, break_date, status);
CREATE INDEX IF NOT EXISTS idx_holidays_branch_shift_date_status ON holidays(branch_id, shift_id, holiday_date, status);
CREATE OR REPLACE FUNCTION is_instructor()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'instructor'::app_role);
$$ LANGUAGE sql SECURITY DEFINER STABLE;
CREATE OR REPLACE FUNCTION can_global_read_employees()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role IN ('admin'::app_role, 'manager'::app_role, 'instructor_head'::app_role, 'instructor'::app_role)
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;
CREATE OR REPLACE FUNCTION is_employee_self(uid UUID)
RETURNS BOOLEAN AS $$
  SELECT auth.uid() = uid;
$$ LANGUAGE sql SECURITY DEFINER STABLE;
DROP POLICY IF EXISTS profiles_select ON profiles;
CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated USING (
  can_global_read_employees()
  OR id = auth.uid()
  OR (my_branch_id() IS NOT NULL AND default_branch_id = my_branch_id() AND role IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role))
);
DROP POLICY IF EXISTS profiles_update_branch_head ON profiles;
CREATE POLICY profiles_update_branch_head ON profiles FOR UPDATE TO authenticated USING (
  is_admin() OR (is_instructor_head() AND id = auth.uid())
);
DROP POLICY IF EXISTS holidays_select ON holidays;
CREATE POLICY holidays_select ON holidays FOR SELECT TO authenticated USING (
  can_global_read_employees()
  OR (my_branch_id() IS NOT NULL AND branch_id = my_branch_id() AND user_group = my_user_group())
);
DROP POLICY IF EXISTS holidays_insert ON holidays;
CREATE POLICY holidays_insert ON holidays FOR INSERT TO authenticated WITH CHECK (
  (is_admin() OR is_manager())
  OR (
    user_id = auth.uid()
    AND is_staff_or_instructor()
    AND branch_id = my_branch_id()
    AND user_group = my_user_group()
  )
);
DROP POLICY IF EXISTS holidays_update ON holidays;
CREATE POLICY holidays_update ON holidays FOR UPDATE TO authenticated USING (
  is_admin() OR is_manager() OR user_id = auth.uid()
);
DROP POLICY IF EXISTS holidays_delete ON holidays;
CREATE POLICY holidays_delete ON holidays FOR DELETE TO authenticated USING (
  is_admin() OR is_manager() OR user_id = auth.uid()
);
DROP POLICY IF EXISTS break_logs_select ON break_logs;
CREATE POLICY break_logs_select ON break_logs FOR SELECT TO authenticated USING (
  can_global_read_employees()
  OR user_id = auth.uid()
  OR (my_branch_id() IS NOT NULL AND branch_id IN (SELECT user_branch_ids(auth.uid())))
);
DROP POLICY IF EXISTS work_logs_select ON work_logs;
CREATE POLICY work_logs_select ON work_logs FOR SELECT TO authenticated USING (
  can_global_read_employees()
  OR user_id = auth.uid()
  OR (my_branch_id() IS NOT NULL AND branch_id IN (SELECT user_branch_ids(auth.uid())))
);
CREATE INDEX IF NOT EXISTS idx_break_logs_break_date_status ON break_logs(break_date, status);
CREATE INDEX IF NOT EXISTS idx_holidays_holiday_date_status ON holidays(holiday_date, status);
CREATE OR REPLACE FUNCTION public.get_email_for_login(login_name TEXT)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT u.email
  FROM auth.users AS u
  JOIN profiles AS p ON p.id = u.id
  WHERE p.active = true
    AND (
      (p.display_name IS NOT NULL AND LOWER(trim(p.display_name)) = LOWER(trim(login_name)))
      OR LOWER(trim(p.email)) = LOWER(trim(login_name))
      OR LOWER(trim(u.email)) = LOWER(trim(login_name))
    )
  ORDER BY u.created_at DESC
  LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.get_email_for_login(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.get_email_for_login(TEXT) TO authenticated;
CREATE OR REPLACE FUNCTION profiles_guard_admin_manager_role()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.role IN ('admin'::app_role, 'manager'::app_role)
     AND auth.uid() IS NOT NULL
     AND NOT is_admin() THEN
    RAISE EXCEPTION 'ไม่มีสิทธิ์ตั้งบทบาทเป็น admin หรือ manager';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
DROP POLICY IF EXISTS holidays_insert ON holidays;
CREATE POLICY holidays_insert ON holidays FOR INSERT TO authenticated WITH CHECK (
  is_admin() OR is_manager() OR is_instructor_head()
  OR (
    user_id = auth.uid()
    AND is_staff_or_instructor()
    AND branch_id = my_branch_id()
    AND user_group = my_user_group()
  )
);
DROP POLICY IF EXISTS holidays_update ON holidays;
CREATE POLICY holidays_update ON holidays FOR UPDATE TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head() OR user_id = auth.uid()
);
DROP POLICY IF EXISTS holidays_delete ON holidays;
CREATE POLICY holidays_delete ON holidays FOR DELETE TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head() OR user_id = auth.uid()
);
CREATE TABLE IF NOT EXISTS meal_round_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_meal_round_templates_branch ON meal_round_templates(branch_id);
CREATE INDEX IF NOT EXISTS idx_meal_round_templates_active ON meal_round_templates(active) WHERE active = true;
CREATE TABLE IF NOT EXISTS meal_slot_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  round_id UUID NOT NULL REFERENCES meal_round_templates(id) ON DELETE CASCADE,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_meal_slot_templates_round ON meal_slot_templates(round_id);
CREATE TABLE IF NOT EXISTS meal_concurrency_rules (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
  website_id UUID NOT NULL REFERENCES websites(id) ON DELETE CASCADE,
  max_staff_threshold INT NOT NULL,
  max_concurrent INT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT meal_concurrency_rules_positive CHECK (max_staff_threshold >= 0 AND max_concurrent >= 0)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_meal_concurrency_rules_group_threshold
  ON meal_concurrency_rules(branch_id, shift_id, website_id, max_staff_threshold);
CREATE INDEX IF NOT EXISTS idx_meal_concurrency_rules_lookup
  ON meal_concurrency_rules(branch_id, shift_id, website_id);
CREATE TABLE IF NOT EXISTS meal_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
  website_id UUID NOT NULL REFERENCES websites(id) ON DELETE CASCADE,
  work_date DATE NOT NULL,
  round_id UUID NOT NULL REFERENCES meal_round_templates(id) ON DELETE CASCADE,
  slot_id UUID NOT NULL REFERENCES meal_slot_templates(id) ON DELETE CASCADE,
  slot_start_ts TIMESTAMPTZ NOT NULL,
  slot_end_ts TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL DEFAULT 'booked',
  created_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT meal_logs_user_workdate_round_unique UNIQUE (user_id, work_date, round_id)
);
CREATE INDEX IF NOT EXISTS idx_meal_logs_user_work_date ON meal_logs(user_id, work_date);
CREATE INDEX IF NOT EXISTS idx_meal_logs_slot_capacity ON meal_logs(branch_id, shift_id, website_id, work_date, slot_id);
CREATE OR REPLACE FUNCTION meal_logs_check_max_two_per_workday()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  cnt INT;
BEGIN
  SELECT COUNT(*) INTO cnt
  FROM meal_logs
  WHERE user_id = NEW.user_id AND work_date = NEW.work_date AND status = 'booked'
    AND (id IS NULL OR id != NEW.id);
  IF cnt >= 2 THEN
    RAISE EXCEPTION 'meal_logs: max 2 bookings per workday (used %/2)', cnt;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS meal_logs_max_two_trigger ON meal_logs;
CREATE TRIGGER meal_logs_max_two_trigger
  BEFORE INSERT OR UPDATE ON meal_logs
  FOR EACH ROW WHEN (NEW.status = 'booked')
  EXECUTE PROCEDURE meal_logs_check_max_two_per_workday();
CREATE OR REPLACE FUNCTION get_meal_capacity(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_work_date DATE,
  p_slot_id UUID,
  p_slot_start_ts TIMESTAMPTZ
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE AS $$
DECLARE
  v_holiday_date DATE;
  v_on_duty_count INT;
  v_max_concurrent INT;
  v_current_booked INT;
BEGIN
  v_holiday_date := DATE(p_slot_start_ts);
  WITH eligible AS (
    SELECT p.id
    FROM profiles p
    INNER JOIN website_assignments wa ON wa.user_id = p.id AND wa.website_id = p_website_id AND wa.is_primary = true
    WHERE p.default_branch_id = p_branch_id
      AND p.default_shift_id = p_shift_id
      AND (p.active IS NULL OR p.active = true)
      AND NOT EXISTS (
        SELECT 1 FROM holidays h
        WHERE h.user_id = p.id
          AND h.holiday_date = v_holiday_date
          AND h.status = 'approved'
      )
  ),
  last_log AS (
    SELECT DISTINCT ON (wl.user_id) wl.user_id, wl.log_type
    FROM work_logs wl
    WHERE wl.logical_date = p_work_date
      AND wl.branch_id = p_branch_id
      AND wl.shift_id = p_shift_id
      AND wl.user_id IN (SELECT id FROM eligible)
    ORDER BY wl.user_id, wl.logged_at DESC
  )
  SELECT COUNT(*)::INT INTO v_on_duty_count
  FROM last_log
  WHERE log_type = 'IN';
  SELECT mcr.max_concurrent INTO v_max_concurrent
  FROM meal_concurrency_rules mcr
  WHERE mcr.branch_id = p_branch_id
    AND mcr.shift_id = p_shift_id
    AND mcr.website_id = p_website_id
    AND mcr.max_staff_threshold >= v_on_duty_count
  ORDER BY mcr.max_staff_threshold ASC
  LIMIT 1;
  v_max_concurrent := COALESCE(v_max_concurrent, 0);
  SELECT COUNT(*)::INT INTO v_current_booked
  FROM meal_logs
  WHERE branch_id = p_branch_id
    AND shift_id = p_shift_id
    AND website_id = p_website_id
    AND work_date = p_work_date
    AND slot_id = p_slot_id
    AND status = 'booked';
  RETURN jsonb_build_object(
    'on_duty_count', v_on_duty_count,
    'max_concurrent', v_max_concurrent,
    'current_booked', v_current_booked,
    'is_full', (v_current_booked >= v_max_concurrent)
  );
END;
$$;
ALTER TABLE meal_round_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE meal_slot_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE meal_concurrency_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE meal_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS meal_round_templates_select ON meal_round_templates;
CREATE POLICY meal_round_templates_select ON meal_round_templates FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS meal_slot_templates_select ON meal_slot_templates;
CREATE POLICY meal_slot_templates_select ON meal_slot_templates FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS meal_concurrency_rules_select ON meal_concurrency_rules;
CREATE POLICY meal_concurrency_rules_select ON meal_concurrency_rules FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS meal_logs_select ON meal_logs;
CREATE POLICY meal_logs_select ON meal_logs FOR SELECT TO authenticated USING (
  is_admin() OR is_manager() OR user_id = auth.uid()
);
DROP POLICY IF EXISTS meal_logs_insert ON meal_logs;
CREATE POLICY meal_logs_insert ON meal_logs FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS meal_logs_update ON meal_logs;
CREATE POLICY meal_logs_update ON meal_logs FOR UPDATE TO authenticated USING (
  user_id = auth.uid() AND now() < slot_start_ts
);
DROP POLICY IF EXISTS meal_logs_delete ON meal_logs;
CREATE POLICY meal_logs_delete ON meal_logs FOR DELETE TO authenticated USING (
  user_id = auth.uid() AND now() < slot_start_ts
);
GRANT EXECUTE ON FUNCTION get_meal_capacity(UUID,UUID,UUID,DATE,UUID,TIMESTAMPTZ) TO authenticated;
CREATE OR REPLACE FUNCTION get_available_slots(p_work_date DATE)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_branch_id UUID;
  v_shift_id UUID;
  v_website_id UUID;
  v_shift_start_ts TIMESTAMPTZ;
  v_shift_end_ts TIMESTAMPTZ;
  v_shift_start_time TIME;
  v_round RECORD;
  v_slot RECORD;
  v_slot_start_ts TIMESTAMPTZ;
  v_slot_end_ts TIMESTAMPTZ;
  v_cap JSONB;
  v_my_bookings JSONB := '[]'::JSONB;
  v_rounds JSONB := '[]'::JSONB;
  v_slots_in_round JSONB;
  v_meal_count INT;
BEGIN
  SELECT p.default_branch_id, p.default_shift_id INTO v_branch_id, v_shift_id
  FROM profiles p WHERE p.id = v_uid LIMIT 1;
  SELECT wa.website_id INTO v_website_id
  FROM website_assignments wa WHERE wa.user_id = v_uid AND wa.is_primary = true LIMIT 1;
  IF v_branch_id IS NULL OR v_shift_id IS NULL OR v_website_id IS NULL THEN
    RETURN jsonb_build_object('error', 'missing_branch_shift_website', 'rounds', '[]'::JSONB, 'my_bookings', '[]'::JSONB, 'meal_count', 0);
  END IF;
  SELECT s.start_time, (p_work_date + s.start_time)::TIMESTAMPTZ, (p_work_date + s.end_time)::TIMESTAMPTZ
  INTO v_shift_start_time, v_shift_start_ts, v_shift_end_ts
  FROM shifts s WHERE s.id = v_shift_id LIMIT 1;
  IF v_shift_start_ts IS NULL THEN
    RETURN jsonb_build_object('error', 'shift_not_found', 'rounds', '[]'::JSONB, 'my_bookings', '[]'::JSONB, 'meal_count', 0);
  END IF;
  IF v_shift_end_ts <= v_shift_start_ts THEN
    v_shift_end_ts := (p_work_date + 1 + (SELECT end_time FROM shifts WHERE id = v_shift_id))::TIMESTAMPTZ;
  END IF;
  SELECT COUNT(*)::INT INTO v_meal_count
  FROM meal_logs WHERE user_id = v_uid AND work_date = p_work_date AND status = 'booked';
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id, 'round_id', round_id, 'slot_id', slot_id, 'slot_start_ts', slot_start_ts, 'slot_end_ts', slot_end_ts
  )), '[]'::JSONB) INTO v_my_bookings
  FROM meal_logs
  WHERE user_id = v_uid AND work_date = p_work_date AND status = 'booked';
  FOR v_round IN
    SELECT r.id, r.name, r.start_time, r.end_time, r.sort_order
    FROM meal_round_templates r
    WHERE (r.branch_id IS NULL OR r.branch_id = v_branch_id) AND r.active = true
    ORDER BY r.sort_order, r.start_time
  LOOP
    v_slots_in_round := '[]'::JSONB;
    FOR v_slot IN
      SELECT s.id, s.start_time, s.end_time, s.sort_order
      FROM meal_slot_templates s
      WHERE s.round_id = v_round.id AND s.active = true
      ORDER BY s.sort_order, s.start_time
    LOOP
      v_slot_start_ts := (p_work_date + v_slot.start_time)::TIMESTAMPTZ;
      v_slot_end_ts := (p_work_date + v_slot.end_time)::TIMESTAMPTZ;
      IF v_shift_end_ts <= v_shift_start_ts AND v_slot.start_time < v_shift_start_time THEN
        v_slot_start_ts := (p_work_date + 1 + v_slot.start_time)::TIMESTAMPTZ;
        v_slot_end_ts := (p_work_date + 1 + v_slot.end_time)::TIMESTAMPTZ;
      ELSIF v_slot_end_ts <= v_slot_start_ts THEN
        v_slot_end_ts := (p_work_date + 1 + v_slot.end_time)::TIMESTAMPTZ;
      END IF;
      v_cap := get_meal_capacity(v_branch_id, v_shift_id, v_website_id, p_work_date, v_slot.id, v_slot_start_ts);
      v_slots_in_round := v_slots_in_round || jsonb_build_array(jsonb_build_object(
        'slot_id', v_slot.id, 'start_time', v_slot.start_time, 'end_time', v_slot.end_time,
        'slot_start_ts', v_slot_start_ts, 'slot_end_ts', v_slot_end_ts,
        'capacity', v_cap
      ));
    END LOOP;
    v_rounds := v_rounds || jsonb_build_array(jsonb_build_object(
      'round_id', v_round.id, 'name', v_round.name, 'slots', v_slots_in_round
    ));
  END LOOP;
  RETURN jsonb_build_object(
    'work_date', p_work_date,
    'shift_start_ts', v_shift_start_ts,
    'shift_end_ts', v_shift_end_ts,
    'rounds', v_rounds,
    'my_bookings', v_my_bookings,
    'meal_count', v_meal_count
  );
END;
$$;
GRANT EXECUTE ON FUNCTION get_available_slots(DATE) TO authenticated;
CREATE OR REPLACE FUNCTION book_meal(
  p_slot_id UUID,
  p_work_date DATE,
  p_slot_start_ts TIMESTAMPTZ,
  p_slot_end_ts TIMESTAMPTZ,
  p_round_id UUID
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_branch_id UUID;
  v_shift_id UUID;
  v_website_id UUID;
  v_shift_start_ts TIMESTAMPTZ;
  v_shift_end_ts TIMESTAMPTZ;
  v_meal_count INT;
  v_cap JSONB;
  v_log_id UUID;
BEGIN
  SELECT p.default_branch_id, p.default_shift_id INTO v_branch_id, v_shift_id FROM profiles p WHERE p.id = v_uid LIMIT 1;
  SELECT wa.website_id INTO v_website_id FROM website_assignments wa WHERE wa.user_id = v_uid AND wa.is_primary = true LIMIT 1;
  IF v_branch_id IS NULL OR v_shift_id IS NULL OR v_website_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_branch_shift_website');
  END IF;
  IF now() < (p_work_date + (SELECT start_time FROM shifts WHERE id = v_shift_id))::TIMESTAMPTZ THEN
    RETURN jsonb_build_object('ok', false, 'error', 'before_shift_start');
  END IF;
  SELECT COUNT(*)::INT INTO v_meal_count FROM meal_logs WHERE user_id = v_uid AND work_date = p_work_date AND status = 'booked';
  IF v_meal_count >= 2 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'max_meals_reached');
  END IF;
  IF EXISTS (SELECT 1 FROM meal_logs WHERE user_id = v_uid AND work_date = p_work_date AND round_id = p_round_id AND status = 'booked') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_booked_this_round');
  END IF;
  SELECT (p_work_date + s.start_time)::TIMESTAMPTZ, (p_work_date + s.end_time)::TIMESTAMPTZ INTO v_shift_start_ts, v_shift_end_ts FROM shifts s WHERE s.id = v_shift_id LIMIT 1;
  IF v_shift_end_ts <= v_shift_start_ts THEN
    v_shift_end_ts := (p_work_date + 1 + (SELECT end_time FROM shifts WHERE id = v_shift_id))::TIMESTAMPTZ;
  END IF;
  IF p_slot_start_ts < v_shift_start_ts OR p_slot_start_ts >= v_shift_end_ts THEN
    RETURN jsonb_build_object('ok', false, 'error', 'slot_outside_shift');
  END IF;
  v_cap := get_meal_capacity(v_branch_id, v_shift_id, v_website_id, p_work_date, p_slot_id, p_slot_start_ts);
  IF (v_cap->>'is_full')::boolean THEN
    RETURN jsonb_build_object('ok', false, 'error', 'slot_full');
  END IF;
  INSERT INTO meal_logs (user_id, branch_id, shift_id, website_id, work_date, round_id, slot_id, slot_start_ts, slot_end_ts, status)
  VALUES (v_uid, v_branch_id, v_shift_id, v_website_id, p_work_date, p_round_id, p_slot_id, p_slot_start_ts, p_slot_end_ts, 'booked')
  RETURNING id INTO v_log_id;
  RETURN jsonb_build_object('ok', true, 'id', v_log_id);
END;
$$;
GRANT EXECUTE ON FUNCTION book_meal(UUID,DATE,TIMESTAMPTZ,TIMESTAMPTZ,UUID) TO authenticated;
CREATE OR REPLACE FUNCTION cancel_meal(p_meal_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_row meal_logs%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM meal_logs WHERE id = p_meal_id AND user_id = v_uid LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found_or_not_owner');
  END IF;
  IF now() >= v_row.slot_start_ts THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cannot_cancel_after_slot_start');
  END IF;
  UPDATE meal_logs SET status = 'cancelled' WHERE id = p_meal_id AND user_id = v_uid;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION cancel_meal(UUID) TO authenticated;
DO $$ BEGIN
  CREATE TYPE break_type_enum AS ENUM ('NORMAL', 'MEAL');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
ALTER TABLE break_logs ADD COLUMN IF NOT EXISTS break_type TEXT NOT NULL DEFAULT 'NORMAL'
  CHECK (break_type IN ('NORMAL', 'MEAL'));
ALTER TABLE break_logs ADD COLUMN IF NOT EXISTS round_key TEXT;
ALTER TABLE break_logs ADD COLUMN IF NOT EXISTS website_id UUID REFERENCES websites(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_break_logs_meal_user_date_round
  ON break_logs (user_id, break_date, round_key)
  WHERE break_type = 'MEAL' AND round_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_break_logs_meal_capacity
  ON break_logs (branch_id, shift_id, website_id, break_date, round_key)
  WHERE break_type = 'MEAL' AND status = 'active';
CREATE OR REPLACE FUNCTION break_logs_check_meal_max_per_workday()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_max INT := 2;
BEGIN
  IF NEW.break_type <> 'MEAL' OR NEW.status <> 'active' THEN RETURN NEW; END IF;
  SELECT COALESCE((SELECT (rounds_json->>'max_per_work_date')::INT FROM meal_settings WHERE is_enabled = true ORDER BY effective_from DESC LIMIT 1), 2) INTO v_max;
  IF (SELECT COUNT(*) FROM break_logs WHERE user_id = NEW.user_id AND break_date = NEW.break_date AND break_type = 'MEAL' AND status = 'active' AND (id IS NULL OR id <> NEW.id)) >= v_max THEN
    RAISE EXCEPTION 'break_logs: max % meal bookings per workday', v_max;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS break_logs_meal_max_trigger ON break_logs;
CREATE TRIGGER break_logs_meal_max_trigger
  BEFORE INSERT OR UPDATE ON break_logs
  FOR EACH ROW WHEN (NEW.break_type = 'MEAL' AND NEW.status = 'active')
  EXECUTE PROCEDURE break_logs_check_meal_max_per_workday();
CREATE TABLE IF NOT EXISTS meal_settings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
  is_enabled BOOLEAN NOT NULL DEFAULT true,
  rounds_json JSONB NOT NULL DEFAULT '{"max_per_work_date":2,"rounds":[]}'::JSONB,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_meal_settings_effective ON meal_settings(effective_from DESC);
ALTER TABLE meal_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS meal_settings_select ON meal_settings;
CREATE POLICY meal_settings_select ON meal_settings FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS meal_settings_all ON meal_settings;
CREATE POLICY meal_settings_all ON meal_settings FOR ALL TO authenticated USING (is_admin() OR is_manager());
CREATE TABLE IF NOT EXISTS meal_quota_rules (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
  website_id UUID NOT NULL REFERENCES websites(id) ON DELETE CASCADE,
  on_duty_threshold INT NOT NULL,
  max_concurrent INT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT meal_quota_rules_positive CHECK (on_duty_threshold >= 0 AND max_concurrent >= 0)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_meal_quota_rules_lookup
  ON meal_quota_rules(branch_id, shift_id, website_id, on_duty_threshold);
CREATE INDEX IF NOT EXISTS idx_meal_quota_rules_group ON meal_quota_rules(branch_id, shift_id, website_id);
ALTER TABLE meal_quota_rules ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS meal_quota_rules_select ON meal_quota_rules;
CREATE POLICY meal_quota_rules_select ON meal_quota_rules FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS meal_quota_rules_all ON meal_quota_rules;
CREATE POLICY meal_quota_rules_all ON meal_quota_rules FOR ALL TO authenticated USING (is_admin() OR is_manager());
INSERT INTO meal_settings (effective_from, is_enabled, rounds_json)
SELECT CURRENT_DATE, true, '{"max_per_work_date":2,"rounds":[{"key":"round_0","name":"มื้อเช้า","slots":[{"start":"08:00","end":"08:30"},{"start":"08:30","end":"09:00"}]},{"key":"round_1","name":"มื้อกลางวัน","slots":[{"start":"12:00","end":"12:30"},{"start":"12:30","end":"13:00"}]}]}'::JSONB
WHERE NOT EXISTS (SELECT 1 FROM meal_settings LIMIT 1);
DROP POLICY IF EXISTS break_logs_insert ON break_logs;
CREATE POLICY break_logs_insert ON break_logs FOR INSERT TO authenticated WITH CHECK (
  user_id = auth.uid()
  AND (is_admin_or_manager() OR (is_staff_or_instructor() AND (branch_id = my_branch_id() OR branch_id IN (SELECT user_branch_ids(auth.uid())))))
  AND (break_type = 'NORMAL' OR (break_type = 'MEAL' AND round_key IS NOT NULL))
);
DROP POLICY IF EXISTS break_logs_update ON break_logs;
CREATE POLICY break_logs_update ON break_logs FOR UPDATE TO authenticated USING (
  (break_type = 'NORMAL' AND (user_id = auth.uid() OR is_admin_or_manager()))
  OR (break_type = 'MEAL' AND user_id = auth.uid() AND now() < started_at)
  OR (break_type = 'MEAL' AND is_admin_or_manager())
);
DROP POLICY IF EXISTS break_logs_select ON break_logs;
CREATE POLICY break_logs_select ON break_logs FOR SELECT TO authenticated USING (
  can_global_read_employees()
  OR user_id = auth.uid()
  OR (my_branch_id() IS NOT NULL AND branch_id IN (SELECT user_branch_ids(auth.uid())))
);
CREATE OR REPLACE FUNCTION get_meal_slots_unified(p_work_date DATE)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_branch_id UUID;
  v_shift_id UUID;
  v_website_id UUID;
  v_shift_start_ts TIMESTAMPTZ;
  v_shift_end_ts TIMESTAMPTZ;
  v_shift_start_time TIME;
  v_settings JSONB;
  v_rounds JSONB;
  v_round JSONB;
  v_slot JSONB;
  v_round_key TEXT;
  v_slot_start_ts TIMESTAMPTZ;
  v_slot_end_ts TIMESTAMPTZ;
  v_cap JSONB;
  v_my_bookings JSONB := '[]'::JSONB;
  v_meal_count INT;
  v_out_rounds JSONB := '[]'::JSONB;
  v_slots_in_round JSONB;
  i INT; j INT;
BEGIN
  SELECT p.default_branch_id, p.default_shift_id INTO v_branch_id, v_shift_id FROM profiles p WHERE p.id = v_uid LIMIT 1;
  SELECT wa.website_id INTO v_website_id FROM website_assignments wa WHERE wa.user_id = v_uid AND wa.is_primary = true LIMIT 1;
  IF v_branch_id IS NULL OR v_shift_id IS NULL OR v_website_id IS NULL THEN
    RETURN jsonb_build_object('error', 'missing_branch_shift_website', 'rounds', '[]'::JSONB, 'my_bookings', '[]'::JSONB, 'meal_count', 0);
  END IF;
  SELECT s.start_time, (p_work_date + s.start_time)::TIMESTAMPTZ, (p_work_date + s.end_time)::TIMESTAMPTZ
  INTO v_shift_start_time, v_shift_start_ts, v_shift_end_ts
  FROM shifts s WHERE s.id = v_shift_id LIMIT 1;
  IF v_shift_start_ts IS NULL THEN
    RETURN jsonb_build_object('error', 'shift_not_found', 'rounds', '[]'::JSONB, 'my_bookings', '[]'::JSONB, 'meal_count', 0);
  END IF;
  IF v_shift_end_ts <= v_shift_start_ts THEN
    v_shift_end_ts := (p_work_date + 1 + (SELECT end_time FROM shifts WHERE id = v_shift_id))::TIMESTAMPTZ;
  END IF;
  SELECT rounds_json INTO v_settings FROM meal_settings WHERE is_enabled = true ORDER BY effective_from DESC LIMIT 1;
  IF v_settings IS NULL OR (v_settings->'rounds') IS NULL THEN
    RETURN jsonb_build_object('work_date', p_work_date, 'shift_start_ts', v_shift_start_ts, 'shift_end_ts', v_shift_end_ts, 'rounds', '[]'::JSONB, 'my_bookings', '[]'::JSONB, 'meal_count', 0);
  END IF;
  v_rounds := v_settings->'rounds';
  SELECT COUNT(*)::INT INTO v_meal_count
  FROM break_logs WHERE user_id = v_uid AND break_date = p_work_date AND break_type = 'MEAL' AND status = 'active';
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'round_key', round_key, 'slot_start_ts', started_at, 'slot_end_ts', ended_at)), '[]'::JSONB) INTO v_my_bookings
  FROM break_logs
  WHERE user_id = v_uid AND break_date = p_work_date AND break_type = 'MEAL' AND status = 'active';
  FOR i IN 0 .. jsonb_array_length(v_rounds) - 1 LOOP
    v_round := v_rounds->i;
    v_round_key := v_round->>'key';
    IF v_round_key IS NULL OR v_round_key = '' THEN v_round_key := 'round_' || i; END IF;
    v_slots_in_round := '[]'::JSONB;
    FOR j IN 0 .. jsonb_array_length(COALESCE(v_round->'slots', '[]'::JSONB)) - 1 LOOP
      v_slot := (v_round->'slots')->j;
      v_slot_start_ts := (p_work_date + ((v_slot->>'start')::TIME))::TIMESTAMPTZ;
      v_slot_end_ts := (p_work_date + ((v_slot->>'end')::TIME))::TIMESTAMPTZ;
      IF v_shift_end_ts <= v_shift_start_ts AND ((v_slot->>'start')::TIME) < v_shift_start_time THEN
        v_slot_start_ts := (p_work_date + 1 + ((v_slot->>'start')::TIME))::TIMESTAMPTZ;
        v_slot_end_ts := (p_work_date + 1 + ((v_slot->>'end')::TIME))::TIMESTAMPTZ;
      ELSIF v_slot_end_ts <= v_slot_start_ts THEN
        v_slot_end_ts := (p_work_date + 1 + ((v_slot->>'end')::TIME))::TIMESTAMPTZ;
      END IF;
      v_cap := get_meal_capacity_break_logs(v_branch_id, v_shift_id, v_website_id, p_work_date, v_round_key, v_slot_start_ts);
      v_slots_in_round := v_slots_in_round || jsonb_build_array(jsonb_build_object(
        'slot_start', v_slot->>'start', 'slot_end', v_slot->>'end',
        'slot_start_ts', v_slot_start_ts, 'slot_end_ts', v_slot_end_ts, 'capacity', v_cap
      ));
    END LOOP;
    v_out_rounds := v_out_rounds || jsonb_build_array(jsonb_build_object(
      'round_key', v_round_key, 'round_name', v_round->>'name', 'slots', v_slots_in_round
    ));
  END LOOP;
  RETURN jsonb_build_object(
    'work_date', p_work_date,
    'shift_start_ts', v_shift_start_ts,
    'shift_end_ts', v_shift_end_ts,
    'rounds', v_out_rounds,
    'my_bookings', v_my_bookings,
    'meal_count', v_meal_count
  );
END;
$$;
CREATE OR REPLACE FUNCTION get_meal_capacity_break_logs(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_work_date DATE,
  p_round_key TEXT,
  p_slot_start_ts TIMESTAMPTZ
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE AS $$
DECLARE
  v_holiday_date DATE;
  v_on_duty_count INT;
  v_max_concurrent INT;
  v_current_booked INT;
BEGIN
  v_holiday_date := DATE(p_slot_start_ts);
  WITH eligible AS (
    SELECT p.id FROM profiles p
    INNER JOIN website_assignments wa ON wa.user_id = p.id AND wa.website_id = p_website_id AND wa.is_primary = true
    WHERE p.default_branch_id = p_branch_id AND p.default_shift_id = p_shift_id AND (p.active IS NULL OR p.active = true)
      AND NOT EXISTS (SELECT 1 FROM holidays h WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status = 'approved')
  ),
  last_log AS (
    SELECT DISTINCT ON (wl.user_id) wl.user_id, wl.log_type
    FROM work_logs wl
    WHERE wl.logical_date = p_work_date AND wl.branch_id = p_branch_id AND wl.shift_id = p_shift_id AND wl.user_id IN (SELECT id FROM eligible)
    ORDER BY wl.user_id, wl.logged_at DESC
  )
  SELECT COUNT(*)::INT INTO v_on_duty_count FROM last_log WHERE log_type = 'IN';
  SELECT mqr.max_concurrent INTO v_max_concurrent
  FROM meal_quota_rules mqr
  WHERE mqr.branch_id = p_branch_id AND mqr.shift_id = p_shift_id AND mqr.website_id = p_website_id AND mqr.on_duty_threshold >= v_on_duty_count
  ORDER BY mqr.on_duty_threshold ASC LIMIT 1;
  v_max_concurrent := COALESCE(v_max_concurrent, 1);
  SELECT COUNT(*)::INT INTO v_current_booked
  FROM break_logs
  WHERE branch_id = p_branch_id AND shift_id = p_shift_id AND website_id = p_website_id AND break_date = p_work_date AND round_key = p_round_key AND break_type = 'MEAL' AND status = 'active';
  RETURN jsonb_build_object('on_duty_count', v_on_duty_count, 'max_concurrent', v_max_concurrent, 'current_booked', v_current_booked, 'is_full', (v_current_booked >= v_max_concurrent));
END;
$$;
GRANT EXECUTE ON FUNCTION get_meal_capacity_break_logs(UUID,UUID,UUID,DATE,TEXT,TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION get_meal_slots_unified(DATE) TO authenticated;
CREATE OR REPLACE FUNCTION book_meal_break(
  p_work_date DATE,
  p_round_key TEXT,
  p_slot_start_ts TIMESTAMPTZ,
  p_slot_end_ts TIMESTAMPTZ
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_branch_id UUID;
  v_shift_id UUID;
  v_website_id UUID;
  v_shift_start_ts TIMESTAMPTZ;
  v_shift_end_ts TIMESTAMPTZ;
  v_meal_count INT;
  v_cap JSONB;
  v_log_id UUID;
  v_ug TEXT;
BEGIN
  SELECT p.default_branch_id, p.default_shift_id INTO v_branch_id, v_shift_id FROM profiles p WHERE p.id = v_uid LIMIT 1;
  SELECT wa.website_id INTO v_website_id FROM website_assignments wa WHERE wa.user_id = v_uid AND wa.is_primary = true LIMIT 1;
  IF v_branch_id IS NULL OR v_shift_id IS NULL OR v_website_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_branch_shift_website');
  END IF;
  v_ug := (SELECT my_user_group());
  IF v_ug IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'invalid_user_group'); END IF;
  IF now() < (p_work_date + (SELECT start_time FROM shifts WHERE id = v_shift_id))::TIMESTAMPTZ THEN
    RETURN jsonb_build_object('ok', false, 'error', 'before_shift_start');
  END IF;
  SELECT COUNT(*)::INT INTO v_meal_count FROM break_logs WHERE user_id = v_uid AND break_date = p_work_date AND break_type = 'MEAL' AND status = 'active';
  IF v_meal_count >= COALESCE((SELECT (rounds_json->>'max_per_work_date')::INT FROM meal_settings WHERE is_enabled = true ORDER BY effective_from DESC LIMIT 1), 2) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'max_meals_reached');
  END IF;
  IF EXISTS (SELECT 1 FROM break_logs WHERE user_id = v_uid AND break_date = p_work_date AND round_key = p_round_key AND break_type = 'MEAL' AND status = 'active') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_booked_this_round');
  END IF;
  SELECT (p_work_date + s.start_time)::TIMESTAMPTZ, (p_work_date + s.end_time)::TIMESTAMPTZ INTO v_shift_start_ts, v_shift_end_ts FROM shifts s WHERE s.id = v_shift_id LIMIT 1;
  IF v_shift_end_ts <= v_shift_start_ts THEN v_shift_end_ts := (p_work_date + 1 + (SELECT end_time FROM shifts WHERE id = v_shift_id))::TIMESTAMPTZ; END IF;
  IF p_slot_start_ts < v_shift_start_ts OR p_slot_start_ts >= v_shift_end_ts THEN
    RETURN jsonb_build_object('ok', false, 'error', 'slot_outside_shift');
  END IF;
  v_cap := get_meal_capacity_break_logs(v_branch_id, v_shift_id, v_website_id, p_work_date, p_round_key, p_slot_start_ts);
  IF (v_cap->>'is_full')::boolean THEN RETURN jsonb_build_object('ok', false, 'error', 'slot_full'); END IF;
  INSERT INTO break_logs (user_id, branch_id, shift_id, website_id, break_date, started_at, ended_at, status, user_group, break_type, round_key)
  VALUES (v_uid, v_branch_id, v_shift_id, v_website_id, p_work_date, p_slot_start_ts, p_slot_end_ts, 'active', v_ug, 'MEAL', p_round_key)
  RETURNING id INTO v_log_id;
  RETURN jsonb_build_object('ok', true, 'id', v_log_id);
END;
$$;
GRANT EXECUTE ON FUNCTION book_meal_break(DATE,TEXT,TIMESTAMPTZ,TIMESTAMPTZ) TO authenticated;
CREATE OR REPLACE FUNCTION cancel_meal_break(p_break_log_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_row break_logs%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM break_logs WHERE id = p_break_log_id AND user_id = v_uid AND break_type = 'MEAL' LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'not_found_or_not_owner'); END IF;
  IF now() >= v_row.started_at THEN RETURN jsonb_build_object('ok', false, 'error', 'cannot_cancel_after_slot_start'); END IF;
  UPDATE break_logs SET status = 'ended' WHERE id = p_break_log_id AND user_id = v_uid;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION cancel_meal_break(UUID) TO authenticated;
DROP POLICY IF EXISTS shift_swaps_insert ON shift_swaps;
CREATE POLICY shift_swaps_insert ON shift_swaps
  FOR INSERT TO authenticated
  WITH CHECK (
    is_admin_or_manager() OR is_instructor_head()
  );
DROP POLICY IF EXISTS transfers_insert ON cross_branch_transfers;
CREATE POLICY transfers_insert ON cross_branch_transfers
  FOR INSERT TO authenticated
  WITH CHECK (
    is_admin_or_manager() OR is_instructor_head()
  );
ALTER TABLE shift_swaps
  ADD COLUMN IF NOT EXISTS skipped_dates JSONB DEFAULT NULL;
ALTER TABLE cross_branch_transfers
  ADD COLUMN IF NOT EXISTS skipped_dates JSONB DEFAULT NULL;
DROP POLICY IF EXISTS monthly_roster_insert ON monthly_roster;
CREATE POLICY monthly_roster_insert ON monthly_roster
  FOR INSERT TO authenticated
  WITH CHECK (is_admin_or_manager() OR (is_instructor_head() AND branch_id = my_branch_id()));
DROP POLICY IF EXISTS monthly_roster_update ON monthly_roster;
CREATE POLICY monthly_roster_update ON monthly_roster
  FOR UPDATE TO authenticated
  USING (is_admin_or_manager() OR (is_instructor_head() AND branch_id = my_branch_id()));
DROP POLICY IF EXISTS monthly_roster_delete ON monthly_roster;
CREATE POLICY monthly_roster_delete ON monthly_roster
  FOR DELETE TO authenticated
  USING (is_admin_or_manager() OR (is_instructor_head() AND branch_id = my_branch_id()));
CREATE OR REPLACE FUNCTION apply_bulk_assignment(
  p_employee_ids UUID[],
  p_start_date DATE,
  p_end_date DATE,
  p_to_branch_id UUID,
  p_to_shift_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  may_run BOOLEAN;
  is_head BOOLEAN;
  conflict_dates RECORD;
  emp_id UUID;
  from_branch_id UUID;
  from_shift_id UUID;
  work_d DATE;
  skipped_arr DATE[];
  skip_set DATE[];
  applied_count INT := 0;
  out_skipped JSONB := '{}'::JSONB;
  out_applied INT := 0;
BEGIN
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head'::app_role);
  IF NOT may_run AND NOT is_head THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can run bulk assignment';
  END IF;
  IF is_head AND NOT may_run THEN
    IF p_to_branch_id IS NULL OR p_to_branch_id != my_branch_id() THEN
      RAISE EXCEPTION 'Instructor head can only assign to their own branch';
    END IF;
  END IF;
  FOR emp_id IN SELECT unnest(p_employee_ids)
  LOOP
    skipped_arr := ARRAY[]::DATE[];
    SELECT ARRAY_AGG(h.holiday_date ORDER BY h.holiday_date)
      INTO skip_set
      FROM holidays h
      WHERE h.user_id = emp_id
        AND h.holiday_date BETWEEN p_start_date AND p_end_date
        AND h.status IN ('approved','pending');
    IF skip_set IS NULL THEN skip_set := ARRAY[]::DATE[]; END IF;
    SELECT r.branch_id, r.shift_id INTO from_branch_id, from_shift_id
      FROM monthly_roster r
      WHERE r.user_id = emp_id AND r.work_date BETWEEN p_start_date AND p_end_date
      ORDER BY r.work_date
      LIMIT 1;
    IF from_branch_id IS NULL THEN
      from_branch_id := p_to_branch_id;
      from_shift_id := p_to_shift_id;
    END IF;
    work_d := p_start_date;
    WHILE work_d <= p_end_date LOOP
      IF work_d = ANY(skip_set) THEN
        skipped_arr := array_append(skipped_arr, work_d);
      ELSE
        DELETE FROM monthly_roster
          WHERE user_id = emp_id AND work_date = work_d;
        INSERT INTO monthly_roster (branch_id, shift_id, user_id, work_date)
          VALUES (p_to_branch_id, p_to_shift_id, emp_id, work_d);
        applied_count := applied_count + 1;
      END IF;
      work_d := work_d + 1;
    END LOOP;
    IF from_branch_id = p_to_branch_id THEN
      INSERT INTO shift_swaps (
        user_id, branch_id, from_shift_id, to_shift_id,
        start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
      ) VALUES (
        emp_id, from_branch_id, from_shift_id, p_to_shift_id,
        p_start_date, p_end_date, p_reason, 'approved', uid, now(),
        CASE WHEN array_length(skipped_arr, 1) > 0
          THEN to_jsonb(ARRAY(SELECT to_char(d, 'YYYY-MM-DD') FROM unnest(skipped_arr) AS d))
          ELSE NULL END
      );
    ELSE
      INSERT INTO cross_branch_transfers (
        user_id, from_branch_id, to_branch_id, from_shift_id, to_shift_id,
        start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
      ) VALUES (
        emp_id, from_branch_id, p_to_branch_id, from_shift_id, p_to_shift_id,
        p_start_date, p_end_date, p_reason, 'approved', uid, now(),
        CASE WHEN array_length(skipped_arr, 1) > 0
          THEN to_jsonb(ARRAY(SELECT to_char(d, 'YYYY-MM-DD') FROM unnest(skipped_arr) AS d))
          ELSE NULL END
      );
    END IF;
    IF array_length(skipped_arr, 1) > 0 THEN
      out_skipped := out_skipped || jsonb_build_object(emp_id::text,
        (SELECT jsonb_agg(to_char(d, 'YYYY-MM-DD')) FROM unnest(skipped_arr) AS d));
    END IF;
  END LOOP;
  out_applied := applied_count;
  RETURN jsonb_build_object(
    'applied', out_applied,
    'skipped_per_user', out_skipped
  );
END;
$$;
ALTER TABLE holidays ADD COLUMN IF NOT EXISTS leave_type VARCHAR DEFAULT 'HOLIDAY';
ALTER TABLE holidays ADD COLUMN IF NOT EXISTS is_quota_exempt BOOLEAN DEFAULT FALSE;
CREATE TABLE IF NOT EXISTS leave_types (
  code VARCHAR PRIMARY KEY,
  name TEXT NOT NULL,
  color TEXT,
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE leave_types ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS leave_types_select ON leave_types;
CREATE POLICY leave_types_select ON leave_types FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS leave_types_all ON leave_types;
CREATE POLICY leave_types_all ON leave_types FOR ALL TO authenticated USING (is_admin_or_manager());
CREATE TRIGGER leave_types_updated_at
  BEFORE UPDATE ON leave_types FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
INSERT INTO leave_types (code, name, color, description) VALUES
  ('HOLIDAY', 'วันหยุด', '#9CA3AF', 'วันหยุดทั่วไป (จองเอง)'),
  ('CL', 'ลากิจ', '#56CCF2', 'ลากิจ'),
  ('VL', 'ลาพักร้อน', '#F2C94C', 'ลาพักร้อน'),
  ('SL', 'ลาป่วย', '#2D9CDB', 'ลาป่วย')
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, color = EXCLUDED.color, description = EXCLUDED.description, updated_at = now();
CREATE OR REPLACE FUNCTION holidays_leave_type_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_role TEXT;
BEGIN
  SELECT role::TEXT INTO user_role FROM profiles WHERE id = auth.uid() LIMIT 1;
  IF user_role IN ('instructor'::text, 'staff'::text) THEN
    NEW.leave_type := 'HOLIDAY';
    NEW.is_quota_exempt := FALSE;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS holidays_leave_type_guard ON holidays;
CREATE TRIGGER holidays_leave_type_guard
  BEFORE INSERT OR UPDATE ON holidays
  FOR EACH ROW EXECUTE PROCEDURE holidays_leave_type_guard();
ALTER TABLE meal_quota_rules
  ADD COLUMN IF NOT EXISTS user_group TEXT NOT NULL DEFAULT 'INSTRUCTOR';
ALTER TABLE break_logs ALTER COLUMN break_type SET DEFAULT 'MEAL';
ALTER TABLE meal_quota_rules
  ALTER COLUMN branch_id DROP NOT NULL,
  ALTER COLUMN shift_id DROP NOT NULL,
  ALTER COLUMN website_id DROP NOT NULL,
  ALTER COLUMN user_group DROP NOT NULL;
CREATE OR REPLACE FUNCTION get_meal_quota_for_group(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_user_group TEXT,
  p_on_duty_count INT
)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((
    SELECT mqr.max_concurrent
    FROM meal_quota_rules mqr
    WHERE
      (mqr.branch_id = p_branch_id OR mqr.branch_id IS NULL)
      AND (mqr.shift_id = p_shift_id OR mqr.shift_id IS NULL)
      AND (mqr.website_id = p_website_id OR mqr.website_id IS NULL)
      AND (mqr.user_group = p_user_group OR mqr.user_group IS NULL)
      AND mqr.on_duty_threshold >= p_on_duty_count
    ORDER BY
      (
        (CASE WHEN mqr.branch_id IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN mqr.shift_id IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN mqr.website_id IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN mqr.user_group IS NOT NULL THEN 1 ELSE 0 END)
      ) DESC,
      mqr.on_duty_threshold ASC,
      mqr.created_at DESC
    LIMIT 1
  ), 1);
$$;
CREATE OR REPLACE FUNCTION get_meal_capacity_break_logs(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_work_date DATE,
  p_round_key TEXT,
  p_slot_start_ts TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_holiday_date DATE;
  v_on_duty_count INT;
  v_max_concurrent INT;
  v_current_booked INT;
  v_user_group TEXT;
BEGIN
  v_holiday_date := DATE(p_slot_start_ts);
  v_user_group := my_user_group();
  WITH eligible AS (
    SELECT p.id
    FROM profiles p
    INNER JOIN website_assignments wa
      ON wa.user_id = p.id
     AND wa.website_id = p_website_id
     AND wa.is_primary = true
    WHERE p.default_branch_id = p_branch_id
      AND p.default_shift_id = p_shift_id
      AND (p.active IS NULL OR p.active = true)
      AND NOT EXISTS (
        SELECT 1 FROM holidays h
        WHERE h.user_id = p.id
          AND h.holiday_date = v_holiday_date
          AND h.status = 'approved'
      )
      AND (
        v_user_group IS NULL
        OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
        OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
        OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
      )
  ),
  last_log AS (
    SELECT DISTINCT ON (wl.user_id) wl.user_id, wl.log_type
    FROM work_logs wl
    WHERE wl.logical_date = p_work_date
      AND wl.branch_id = p_branch_id
      AND wl.shift_id = p_shift_id
      AND wl.user_id IN (SELECT id FROM eligible)
    ORDER BY wl.user_id, wl.logged_at DESC
  )
  SELECT COUNT(*)::INT INTO v_on_duty_count FROM last_log WHERE log_type = 'IN';
  v_max_concurrent := get_meal_quota_for_group(p_branch_id, p_shift_id, p_website_id, v_user_group, v_on_duty_count);
  SELECT COUNT(*)::INT INTO v_current_booked
  FROM break_logs
  WHERE branch_id = p_branch_id
    AND shift_id = p_shift_id
    AND website_id = p_website_id
    AND break_date = p_work_date
    AND round_key = p_round_key
    AND break_type = 'MEAL'
    AND status = 'active'
    AND (user_group = v_user_group OR v_user_group IS NULL);
  RETURN jsonb_build_object(
    'on_duty_count', v_on_duty_count,
    'max_concurrent', v_max_concurrent,
    'current_booked', v_current_booked,
    'is_full', (v_current_booked >= v_max_concurrent)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION get_meal_capacity_break_logs(UUID,UUID,UUID,DATE,TEXT,TIMESTAMPTZ) TO authenticated;
DROP INDEX IF EXISTS idx_meal_quota_rules_lookup;
CREATE UNIQUE INDEX idx_meal_quota_rules_lookup
  ON meal_quota_rules(branch_id, shift_id, website_id, user_group, on_duty_threshold);
CREATE TABLE IF NOT EXISTS holiday_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  action TEXT NOT NULL,
  actor_id UUID NOT NULL,
  actor_role TEXT NOT NULL,
  target_user_id UUID NOT NULL,
  holiday_id UUID,
  holiday_date DATE,
  branch_id UUID,
  leave_type TEXT,
  reason TEXT,
  is_quota_exempt BOOLEAN,
  before_payload JSONB,
  after_payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_holiday_audit_logs_created_at ON holiday_audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_holiday_audit_logs_target_user ON holiday_audit_logs(target_user_id);
CREATE INDEX IF NOT EXISTS idx_holiday_audit_logs_actor ON holiday_audit_logs(actor_id);
CREATE INDEX IF NOT EXISTS idx_holiday_audit_logs_holiday_date ON holiday_audit_logs(holiday_date);
ALTER TABLE holiday_audit_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS holiday_audit_logs_select ON holiday_audit_logs;
CREATE POLICY holiday_audit_logs_select ON holiday_audit_logs FOR SELECT TO authenticated
  USING (is_admin() OR is_manager() OR is_instructor_head());
DROP POLICY IF EXISTS holiday_audit_logs_insert_system ON holiday_audit_logs;
CREATE POLICY holiday_audit_logs_insert_system ON holiday_audit_logs FOR INSERT TO authenticated
  WITH CHECK (actor_id = auth.uid());
CREATE OR REPLACE FUNCTION holiday_audit_log_trigger_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_id UUID;
  v_actor_role TEXT;
  v_target_user_id UUID;
  v_holiday_id UUID;
  v_holiday_date DATE;
  v_branch_id UUID;
  v_leave_type TEXT;
  v_reason TEXT;
  v_is_quota_exempt BOOLEAN;
  v_action TEXT;
  v_before JSONB;
  v_after JSONB;
BEGIN
  v_actor_id := auth.uid();
  IF v_actor_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  SELECT role::TEXT INTO v_actor_role FROM profiles WHERE id = v_actor_id LIMIT 1;
  IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin', 'manager', 'instructor_head') THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  IF TG_OP = 'INSERT' THEN
    v_action := 'INSERT';
    v_target_user_id := NEW.user_id;
    v_holiday_id := NEW.id;
    v_holiday_date := NEW.holiday_date;
    v_branch_id := NEW.branch_id;
    v_leave_type := NEW.leave_type;
    v_reason := NEW.reason;
    v_is_quota_exempt := NEW.is_quota_exempt;
    v_before := NULL;
    v_after := to_jsonb(NEW);
  ELSIF TG_OP = 'UPDATE' THEN
    v_action := 'UPDATE';
    v_target_user_id := NEW.user_id;
    v_holiday_id := NEW.id;
    v_holiday_date := NEW.holiday_date;
    v_branch_id := NEW.branch_id;
    v_leave_type := NEW.leave_type;
    v_reason := NEW.reason;
    v_is_quota_exempt := NEW.is_quota_exempt;
    v_before := to_jsonb(OLD);
    v_after := to_jsonb(NEW);
  ELSIF TG_OP = 'DELETE' THEN
    v_action := 'DELETE';
    v_target_user_id := OLD.user_id;
    v_holiday_id := OLD.id;
    v_holiday_date := OLD.holiday_date;
    v_branch_id := OLD.branch_id;
    v_leave_type := OLD.leave_type;
    v_reason := OLD.reason;
    v_is_quota_exempt := OLD.is_quota_exempt;
    v_before := to_jsonb(OLD);
    v_after := NULL;
  ELSE
    RETURN COALESCE(NEW, OLD);
  END IF;
  INSERT INTO holiday_audit_logs (
    action, actor_id, actor_role, target_user_id, holiday_id, holiday_date, branch_id, leave_type, reason, is_quota_exempt, before_payload, after_payload
  ) VALUES (
    v_action, v_actor_id, v_actor_role, v_target_user_id, v_holiday_id, v_holiday_date, v_branch_id, v_leave_type, v_reason, v_is_quota_exempt, v_before, v_after
  );
  RETURN COALESCE(NEW, OLD);
END;
$$;
DROP TRIGGER IF EXISTS holiday_audit_log_trigger ON holidays;
CREATE TRIGGER holiday_audit_log_trigger
  AFTER INSERT OR UPDATE OR DELETE ON holidays
  FOR EACH ROW EXECUTE PROCEDURE holiday_audit_log_trigger_fn();
ALTER TABLE audit_logs
ADD COLUMN IF NOT EXISTS summary_text TEXT;
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at_desc ON audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON audit_logs(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity_id ON audit_logs(entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON audit_logs(entity);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);
ALTER TABLE password_vault
  ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES profiles(id) ON DELETE CASCADE;
UPDATE password_vault SET owner_id = created_by WHERE owner_id IS NULL AND created_by IS NOT NULL;
DROP POLICY IF EXISTS password_vault_select ON password_vault;
CREATE POLICY password_vault_select ON password_vault FOR SELECT TO authenticated USING (
  is_admin() OR is_manager() OR owner_id = auth.uid() OR (owner_id IS NULL AND created_by = auth.uid())
);
DROP POLICY IF EXISTS password_vault_all ON password_vault;
DROP POLICY IF EXISTS password_vault_insert ON password_vault;
DROP POLICY IF EXISTS password_vault_update ON password_vault;
DROP POLICY IF EXISTS password_vault_delete ON password_vault;
CREATE POLICY password_vault_insert ON password_vault FOR INSERT TO authenticated WITH CHECK (
  (owner_id = auth.uid() OR owner_id IS NULL) AND (created_by = auth.uid() OR created_by IS NULL)
);
CREATE POLICY password_vault_update ON password_vault FOR UPDATE TO authenticated USING (
  is_admin() OR is_manager() OR owner_id = auth.uid() OR (owner_id IS NULL AND created_by = auth.uid())
);
CREATE POLICY password_vault_delete ON password_vault FOR DELETE TO authenticated USING (
  is_admin() OR is_manager() OR owner_id = auth.uid() OR (owner_id IS NULL AND created_by = auth.uid())
);
CREATE OR REPLACE FUNCTION cancel_meal_break(p_break_log_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_row break_logs%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM break_logs WHERE id = p_break_log_id AND break_type = 'MEAL' LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'not_found'); END IF;
  IF v_row.user_id <> v_uid AND NOT is_admin_or_manager() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found_or_not_owner');
  END IF;
  IF v_row.user_id = v_uid AND now() >= v_row.started_at AND NOT is_admin_or_manager() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cannot_cancel_after_slot_start');
  END IF;
  UPDATE break_logs SET status = 'ended' WHERE id = p_break_log_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
CREATE OR REPLACE FUNCTION get_meal_slots_unified(p_work_date DATE)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_branch_id UUID;
  v_shift_id UUID;
  v_website_id UUID;
  v_shift_start_ts TIMESTAMPTZ;
  v_shift_end_ts TIMESTAMPTZ;
  v_shift_start_time TIME;
  v_settings JSONB;
  v_rounds JSONB;
  v_round JSONB;
  v_slot JSONB;
  v_round_key TEXT;
  v_slot_start_ts TIMESTAMPTZ;
  v_slot_end_ts TIMESTAMPTZ;
  v_cap JSONB;
  v_my_bookings JSONB := '[]'::JSONB;
  v_meal_count INT;
  v_out_rounds JSONB := '[]'::JSONB;
  v_slots_in_round JSONB;
  v_booked_count INT;
  v_max_concurrent INT;
  v_is_booked_by_me BOOLEAN;
  v_available BOOLEAN;
  i INT; j INT;
BEGIN
  SELECT p.default_branch_id, p.default_shift_id INTO v_branch_id, v_shift_id FROM profiles p WHERE p.id = v_uid LIMIT 1;
  SELECT wa.website_id INTO v_website_id FROM website_assignments wa WHERE wa.user_id = v_uid AND wa.is_primary = true LIMIT 1;
  IF v_branch_id IS NULL OR v_shift_id IS NULL OR v_website_id IS NULL THEN
    RETURN jsonb_build_object('error', 'missing_branch_shift_website', 'rounds', '[]'::JSONB, 'my_bookings', '[]'::JSONB, 'meal_count', 0);
  END IF;
  SELECT s.start_time, (p_work_date + s.start_time)::TIMESTAMPTZ, (p_work_date + s.end_time)::TIMESTAMPTZ
  INTO v_shift_start_time, v_shift_start_ts, v_shift_end_ts
  FROM shifts s WHERE s.id = v_shift_id LIMIT 1;
  IF v_shift_start_ts IS NULL THEN
    RETURN jsonb_build_object('error', 'shift_not_found', 'rounds', '[]'::JSONB, 'my_bookings', '[]'::JSONB, 'meal_count', 0);
  END IF;
  IF v_shift_end_ts <= v_shift_start_ts THEN
    v_shift_end_ts := (p_work_date + 1 + (SELECT end_time FROM shifts WHERE id = v_shift_id))::TIMESTAMPTZ;
  END IF;
  SELECT rounds_json INTO v_settings FROM meal_settings WHERE is_enabled = true ORDER BY effective_from DESC LIMIT 1;
  IF v_settings IS NULL OR (v_settings->'rounds') IS NULL THEN
    RETURN jsonb_build_object('work_date', p_work_date, 'shift_start_ts', v_shift_start_ts, 'shift_end_ts', v_shift_end_ts, 'rounds', '[]'::JSONB, 'my_bookings', '[]'::JSONB, 'meal_count', 0);
  END IF;
  v_rounds := v_settings->'rounds';
  SELECT COUNT(*)::INT INTO v_meal_count
  FROM break_logs WHERE user_id = v_uid AND break_date = p_work_date AND break_type = 'MEAL' AND status = 'active';
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'round_key', round_key, 'slot_start_ts', started_at, 'slot_end_ts', ended_at)), '[]'::JSONB) INTO v_my_bookings
  FROM break_logs
  WHERE user_id = v_uid AND break_date = p_work_date AND break_type = 'MEAL' AND status = 'active';
  FOR i IN 0 .. jsonb_array_length(v_rounds) - 1 LOOP
    v_round := v_rounds->i;
    v_round_key := v_round->>'key';
    IF v_round_key IS NULL OR v_round_key = '' THEN v_round_key := 'round_' || i; END IF;
    v_slots_in_round := '[]'::JSONB;
    FOR j IN 0 .. jsonb_array_length(COALESCE(v_round->'slots', '[]'::JSONB)) - 1 LOOP
      v_slot := (v_round->'slots')->j;
      v_slot_start_ts := (p_work_date + ((v_slot->>'start')::TIME))::TIMESTAMPTZ;
      v_slot_end_ts := (p_work_date + ((v_slot->>'end')::TIME))::TIMESTAMPTZ;
      IF v_shift_end_ts <= v_shift_start_ts AND ((v_slot->>'start')::TIME) < v_shift_start_time THEN
        v_slot_start_ts := (p_work_date + 1 + ((v_slot->>'start')::TIME))::TIMESTAMPTZ;
        v_slot_end_ts := (p_work_date + 1 + ((v_slot->>'end')::TIME))::TIMESTAMPTZ;
      ELSIF v_slot_end_ts <= v_slot_start_ts THEN
        v_slot_end_ts := (p_work_date + 1 + ((v_slot->>'end')::TIME))::TIMESTAMPTZ;
      END IF;
      v_cap := get_meal_capacity_break_logs(v_branch_id, v_shift_id, v_website_id, p_work_date, v_round_key, v_slot_start_ts);
      v_booked_count := COALESCE((v_cap->>'current_booked')::INT, 0);
      v_max_concurrent := COALESCE((v_cap->>'max_concurrent')::INT, 1);
      SELECT EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_my_bookings) AS el
        WHERE (el->>'slot_start_ts')::timestamptz = v_slot_start_ts
      ) INTO v_is_booked_by_me;
      v_available := (v_booked_count < v_max_concurrent) AND NOT v_is_booked_by_me;
      v_slots_in_round := v_slots_in_round || jsonb_build_array(jsonb_build_object(
        'slot_start', v_slot->>'start', 'slot_end', v_slot->>'end',
        'slot_start_ts', v_slot_start_ts, 'slot_end_ts', v_slot_end_ts,
        'booked_count', v_booked_count, 'max_concurrent', v_max_concurrent,
        'is_booked_by_me', v_is_booked_by_me, 'available', v_available,
        'capacity', v_cap
      ));
    END LOOP;
    v_out_rounds := v_out_rounds || jsonb_build_array(jsonb_build_object(
      'round_key', v_round_key, 'round_name', v_round->>'name', 'slots', v_slots_in_round
    ));
  END LOOP;
  RETURN jsonb_build_object(
    'work_date', p_work_date,
    'shift_start_ts', v_shift_start_ts,
    'shift_end_ts', v_shift_end_ts,
    'rounds', v_out_rounds,
    'my_bookings', v_my_bookings,
    'meal_count', v_meal_count
  );
END;
$$;
GRANT EXECUTE ON FUNCTION get_meal_slots_unified(DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION cancel_meal_break(UUID) TO authenticated;
CREATE OR REPLACE FUNCTION book_meal_break(
  p_work_date DATE,
  p_round_key TEXT,
  p_slot_start_ts TIMESTAMPTZ,
  p_slot_end_ts TIMESTAMPTZ
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_branch_id UUID;
  v_shift_id UUID;
  v_website_id UUID;
  v_shift_start_ts TIMESTAMPTZ;
  v_shift_end_ts TIMESTAMPTZ;
  v_meal_count INT;
  v_cap JSONB;
  v_log_id UUID;
  v_ug TEXT;
BEGIN
  SELECT p.default_branch_id, p.default_shift_id INTO v_branch_id, v_shift_id FROM profiles p WHERE p.id = v_uid LIMIT 1;
  SELECT wa.website_id INTO v_website_id FROM website_assignments wa WHERE wa.user_id = v_uid AND wa.is_primary = true LIMIT 1;
  IF v_branch_id IS NULL OR v_shift_id IS NULL OR v_website_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_branch_shift_website');
  END IF;
  v_ug := (SELECT my_user_group());
  IF v_ug IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'invalid_user_group'); END IF;
  IF now() < (p_work_date + (SELECT start_time FROM shifts WHERE id = v_shift_id))::TIMESTAMPTZ THEN
    RETURN jsonb_build_object('ok', false, 'error', 'before_shift_start');
  END IF;
  SELECT COUNT(*)::INT INTO v_meal_count FROM break_logs WHERE user_id = v_uid AND break_date = p_work_date AND break_type = 'MEAL' AND status = 'active';
  IF v_meal_count >= COALESCE((SELECT (rounds_json->>'max_per_work_date')::INT FROM meal_settings WHERE is_enabled = true ORDER BY effective_from DESC LIMIT 1), 2) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'max_meals_reached');
  END IF;
  IF EXISTS (SELECT 1 FROM break_logs WHERE user_id = v_uid AND break_date = p_work_date AND round_key = p_round_key AND break_type = 'MEAL' AND status = 'active') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_booked_this_round');
  END IF;
  SELECT (p_work_date + s.start_time)::TIMESTAMPTZ, (p_work_date + s.end_time)::TIMESTAMPTZ INTO v_shift_start_ts, v_shift_end_ts FROM shifts s WHERE s.id = v_shift_id LIMIT 1;
  IF v_shift_end_ts <= v_shift_start_ts THEN v_shift_end_ts := (p_work_date + 1 + (SELECT end_time FROM shifts WHERE id = v_shift_id))::TIMESTAMPTZ; END IF;
  IF p_slot_start_ts < v_shift_start_ts OR p_slot_start_ts >= v_shift_end_ts THEN
    RETURN jsonb_build_object('ok', false, 'error', 'slot_outside_shift');
  END IF;
  v_cap := get_meal_capacity_break_logs(v_branch_id, v_shift_id, v_website_id, p_work_date, p_round_key, p_slot_start_ts);
  IF (v_cap->>'is_full')::boolean THEN RETURN jsonb_build_object('ok', false, 'error', 'slot_full'); END IF;
  INSERT INTO break_logs (user_id, branch_id, shift_id, website_id, break_date, started_at, ended_at, status, user_group, break_type, round_key)
  VALUES (v_uid, v_branch_id, v_shift_id, v_website_id, p_work_date, p_slot_start_ts, p_slot_end_ts, 'active', v_ug, 'MEAL', p_round_key)
  RETURNING id INTO v_log_id;
  INSERT INTO audit_logs (actor_id, action, entity, entity_id, details_json, summary_text)
  VALUES (v_uid, 'meal_book', 'meal_booking', v_log_id,
    jsonb_build_object('work_date', p_work_date, 'round_key', p_round_key, 'slot_start_ts', p_slot_start_ts, 'slot_end_ts', p_slot_end_ts),
    'จองพักอาหาร ' || to_char(p_work_date, 'YYYY-MM-DD'));
  RETURN jsonb_build_object('ok', true, 'id', v_log_id);
END;
$$;
CREATE OR REPLACE FUNCTION cancel_meal_break(p_break_log_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_row break_logs%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM break_logs WHERE id = p_break_log_id AND break_type = 'MEAL' LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'not_found'); END IF;
  IF v_row.user_id <> v_uid AND NOT is_admin_or_manager() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found_or_not_owner');
  END IF;
  IF v_row.user_id = v_uid AND now() >= v_row.started_at AND NOT is_admin_or_manager() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cannot_cancel_after_slot_start');
  END IF;
  UPDATE break_logs SET status = 'ended' WHERE id = p_break_log_id;
  INSERT INTO audit_logs (actor_id, action, entity, entity_id, details_json, summary_text)
  VALUES (v_uid, 'meal_cancel', 'meal_booking', p_break_log_id,
    jsonb_build_object('break_log_id', p_break_log_id, 'break_date', v_row.break_date, 'round_key', v_row.round_key),
    'ยกเลิกจองพักอาหาร ' || to_char(v_row.break_date, 'YYYY-MM-DD'));
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION book_meal_break(DATE,TEXT,TIMESTAMPTZ,TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION cancel_meal_break(UUID) TO authenticated;
DROP POLICY IF EXISTS password_vault_select ON password_vault;
CREATE POLICY password_vault_select ON password_vault FOR SELECT TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head()
  OR owner_id = auth.uid() OR (owner_id IS NULL AND created_by = auth.uid())
);
CREATE OR REPLACE FUNCTION public.get_my_role_level()
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    CASE role
      WHEN 'admin'::app_role THEN 4
      WHEN 'manager'::app_role THEN 3
      WHEN 'instructor_head'::app_role THEN 2
      WHEN 'instructor'::app_role THEN 1
      WHEN 'staff'::app_role THEN 0
      ELSE 0
    END
  FROM profiles
  WHERE id = auth.uid()
  LIMIT 1;
$$;
CREATE OR REPLACE FUNCTION public.get_role_level(p_role app_role)
RETURNS INT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    CASE p_role
      WHEN 'admin'::app_role THEN 4
      WHEN 'manager'::app_role THEN 3
      WHEN 'instructor_head'::app_role THEN 2
      WHEN 'instructor'::app_role THEN 1
      WHEN 'staff'::app_role THEN 0
      ELSE 0
    END;
$$;
CREATE POLICY head_insert_lower_role ON profiles
FOR INSERT TO authenticated
WITH CHECK (
  public.get_my_role_level() > public.get_role_level(role)
  AND (
    default_branch_id = (SELECT default_branch_id FROM profiles WHERE id = auth.uid() LIMIT 1)
    OR ((SELECT default_branch_id FROM profiles WHERE id = auth.uid() LIMIT 1) IS NULL AND default_branch_id IS NULL)
  )
);
CREATE POLICY head_update_lower_role ON profiles
FOR UPDATE TO authenticated
USING (public.get_my_role_level() > public.get_role_level(role))
WITH CHECK (public.get_my_role_level() > public.get_role_level(role));
CREATE INDEX IF NOT EXISTS idx_duty_assignments_branch_shift_date
  ON duty_assignments(branch_id, shift_id, assignment_date);
CREATE INDEX IF NOT EXISTS idx_duty_roles_branch_sort
  ON duty_roles(branch_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_website_assignments_user_website
  ON website_assignments(user_id, website_id);
UPDATE meal_quota_rules
SET max_concurrent = on_duty_threshold
WHERE max_concurrent > on_duty_threshold;
ALTER TABLE meal_quota_rules
  ADD CONSTRAINT meal_quota_rules_step CHECK (max_concurrent <= on_duty_threshold);
ALTER TABLE meal_settings
  ADD COLUMN IF NOT EXISTS scope_meal_quota_by_website BOOLEAN DEFAULT true;
CREATE OR REPLACE FUNCTION get_meal_capacity_break_logs(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_work_date DATE,
  p_round_key TEXT,
  p_slot_start_ts TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_holiday_date DATE;
  v_on_duty_count INT;
  v_max_concurrent INT;
  v_current_booked INT;
  v_user_group TEXT;
  v_scope_by_website BOOLEAN := true;
BEGIN
  v_holiday_date := DATE(p_slot_start_ts);
  v_user_group := my_user_group();
  SELECT COALESCE(ms.scope_meal_quota_by_website, true) INTO v_scope_by_website
  FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;
  IF v_scope_by_website THEN
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      INNER JOIN website_assignments wa
        ON wa.user_id = p.id
       AND wa.website_id = p_website_id
       AND wa.is_primary = true
      WHERE p.default_branch_id = p_branch_id
        AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status = 'approved'
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    ),
    last_log AS (
      SELECT DISTINCT ON (wl.user_id) wl.user_id, wl.log_type
      FROM work_logs wl
      WHERE wl.logical_date = p_work_date
        AND wl.branch_id = p_branch_id
        AND wl.shift_id = p_shift_id
        AND wl.user_id IN (SELECT id FROM eligible)
      ORDER BY wl.user_id, wl.logged_at DESC
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM last_log WHERE log_type = 'IN';
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id
      AND shift_id = p_shift_id
      AND website_id = p_website_id
      AND break_date = p_work_date
      AND round_key = p_round_key
      AND break_type = 'MEAL'
      AND status = 'active'
      AND (user_group = v_user_group OR v_user_group IS NULL);
  ELSE
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      WHERE p.default_branch_id = p_branch_id
        AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status = 'approved'
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    ),
    last_log AS (
      SELECT DISTINCT ON (wl.user_id) wl.user_id, wl.log_type
      FROM work_logs wl
      WHERE wl.logical_date = p_work_date
        AND wl.branch_id = p_branch_id
        AND wl.shift_id = p_shift_id
        AND wl.user_id IN (SELECT id FROM eligible)
      ORDER BY wl.user_id, wl.logged_at DESC
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM last_log WHERE log_type = 'IN';
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id
      AND shift_id = p_shift_id
      AND break_date = p_work_date
      AND round_key = p_round_key
      AND break_type = 'MEAL'
      AND status = 'active'
      AND (user_group = v_user_group OR v_user_group IS NULL);
  END IF;
  v_max_concurrent := get_meal_quota_for_group(p_branch_id, p_shift_id, p_website_id, v_user_group, v_on_duty_count);
  RETURN jsonb_build_object(
    'on_duty_count', v_on_duty_count,
    'max_concurrent', v_max_concurrent,
    'current_booked', v_current_booked,
    'is_full', (v_current_booked >= v_max_concurrent)
  );
END;
$$;
ALTER TABLE meal_settings
  ADD COLUMN IF NOT EXISTS scope_holiday_quota_by_website BOOLEAN DEFAULT true;
ALTER TABLE holiday_quota_tiers DROP CONSTRAINT IF EXISTS holiday_quota_tiers_dimension_check;
ALTER TABLE holiday_quota_tiers ADD CONSTRAINT holiday_quota_tiers_dimension_check
  CHECK (dimension IN ('branch', 'shift', 'website', 'combined'));
CREATE OR REPLACE FUNCTION apply_paired_swap(
  p_branch_id UUID,
  p_start_date DATE,
  p_end_date DATE,
  p_assignments JSONB,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  may_run BOOLEAN;
  is_head BOOLEAN;
  rec JSONB;
  emp_id UUID;
  to_shift_id UUID;
  from_shift_id UUID;
  work_d DATE;
  skip_set DATE[];
  skipped_arr DATE[];
  applied_count INT := 0;
  out_skipped JSONB := '{}'::JSONB;
  i INT;
BEGIN
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head'::app_role);
  IF NOT may_run AND NOT is_head THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can run paired swap';
  END IF;
  IF is_head AND NOT may_run THEN
    IF p_branch_id IS NULL OR p_branch_id != my_branch_id() THEN
      RAISE EXCEPTION 'Instructor head can only assign to their own branch';
    END IF;
  END IF;
  WITH elem AS (
    SELECT (e->>'user_id')::UUID AS uid, (e->>'to_shift_id')::UUID AS sid, ord
    FROM jsonb_array_elements(p_assignments) WITH ORDINALITY AS t(e, ord)
    WHERE (e->>'user_id')::UUID IS NOT NULL AND (e->>'to_shift_id')::UUID IS NOT NULL
  ),
  deduped AS (
    SELECT uid, sid, ROW_NUMBER() OVER (PARTITION BY uid ORDER BY ord DESC) AS rn FROM elem
  )
  SELECT jsonb_agg(jsonb_build_object('user_id', uid, 'to_shift_id', sid))
  INTO p_assignments
  FROM (SELECT uid, sid FROM deduped WHERE rn = 1) sub;
  IF p_assignments IS NULL THEN p_assignments := '[]'::JSONB; END IF;
  FOR i IN 0 .. jsonb_array_length(p_assignments) - 1 LOOP
    rec := p_assignments->i;
    emp_id := (rec->>'user_id')::UUID;
    to_shift_id := (rec->>'to_shift_id')::UUID;
    IF emp_id IS NULL OR to_shift_id IS NULL THEN CONTINUE; END IF;
    SELECT ARRAY_AGG(h.holiday_date ORDER BY h.holiday_date)
      INTO skip_set
      FROM holidays h
      WHERE h.user_id = emp_id
        AND h.holiday_date BETWEEN p_start_date AND p_end_date
        AND h.status IN ('approved','pending');
    IF skip_set IS NULL THEN skip_set := ARRAY[]::DATE[]; END IF;
    SELECT r.shift_id INTO from_shift_id
      FROM monthly_roster r
      WHERE r.user_id = emp_id AND r.branch_id = p_branch_id AND r.work_date BETWEEN p_start_date AND p_end_date
      ORDER BY r.work_date LIMIT 1;
    IF from_shift_id IS NULL THEN
      from_shift_id := to_shift_id;
    END IF;
    skipped_arr := ARRAY[]::DATE[];
    work_d := p_start_date;
    WHILE work_d <= p_end_date LOOP
      IF work_d = ANY(skip_set) THEN
        skipped_arr := array_append(skipped_arr, work_d);
      ELSE
        DELETE FROM monthly_roster
          WHERE user_id = emp_id AND work_date = work_d;
        INSERT INTO monthly_roster (branch_id, shift_id, user_id, work_date)
          VALUES (p_branch_id, to_shift_id, emp_id, work_d);
        applied_count := applied_count + 1;
      END IF;
      work_d := work_d + 1;
    END LOOP;
    INSERT INTO shift_swaps (
      user_id, branch_id, from_shift_id, to_shift_id,
      start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
    ) VALUES (
      emp_id, p_branch_id, from_shift_id, to_shift_id,
      p_start_date, p_end_date, p_reason, 'approved', uid, now(),
      CASE WHEN array_length(skipped_arr, 1) > 0
        THEN to_jsonb(ARRAY(SELECT to_char(d, 'YYYY-MM-DD') FROM unnest(skipped_arr) AS d))
        ELSE NULL END
    );
    IF array_length(skipped_arr, 1) > 0 THEN
      out_skipped := out_skipped || jsonb_build_object(emp_id::text,
        (SELECT jsonb_agg(to_char(d, 'YYYY-MM-DD')) FROM unnest(skipped_arr) AS d));
    END IF;
  END LOOP;
  RETURN jsonb_build_object(
    'applied', applied_count,
    'skipped_per_user', out_skipped
  );
END;
$$;
GRANT EXECUTE ON FUNCTION apply_paired_swap(UUID, DATE, DATE, JSONB, TEXT) TO authenticated;
ALTER TABLE holiday_quota_tiers DROP CONSTRAINT IF EXISTS holiday_quota_tiers_user_group_check;
ALTER TABLE holiday_quota_tiers ALTER COLUMN user_group DROP NOT NULL;
ALTER TABLE holiday_quota_tiers ADD CONSTRAINT holiday_quota_tiers_user_group_check
  CHECK (user_group IS NULL OR user_group IN ('INSTRUCTOR', 'STAFF', 'MANAGER'));
CREATE OR REPLACE FUNCTION get_meal_capacity_break_logs(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_work_date DATE,
  p_round_key TEXT,
  p_slot_start_ts TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_holiday_date DATE;
  v_on_duty_count INT;
  v_max_concurrent INT;
  v_current_booked INT;
  v_user_group TEXT;
  v_scope_by_website BOOLEAN := true;
BEGIN
  v_holiday_date := DATE(p_slot_start_ts);
  v_user_group := my_user_group();
  SELECT COALESCE(ms.scope_meal_quota_by_website, true) INTO v_scope_by_website
  FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;
  IF v_scope_by_website THEN
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      INNER JOIN website_assignments wa
        ON wa.user_id = p.id
       AND wa.website_id = p_website_id
       AND wa.is_primary = true
      WHERE p.default_branch_id = p_branch_id
        AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status = 'approved'
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id
      AND shift_id = p_shift_id
      AND website_id = p_website_id
      AND break_date = p_work_date
      AND round_key = p_round_key
      AND break_type = 'MEAL'
      AND status = 'active'
      AND (user_group = v_user_group OR v_user_group IS NULL);
  ELSE
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      WHERE p.default_branch_id = p_branch_id
        AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status = 'approved'
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id
      AND shift_id = p_shift_id
      AND break_date = p_work_date
      AND round_key = p_round_key
      AND break_type = 'MEAL'
      AND status = 'active'
      AND (user_group = v_user_group OR v_user_group IS NULL);
  END IF;
  v_max_concurrent := get_meal_quota_for_group(p_branch_id, p_shift_id, p_website_id, v_user_group, v_on_duty_count);
  RETURN jsonb_build_object(
    'on_duty_count', v_on_duty_count,
    'max_concurrent', v_max_concurrent,
    'current_booked', v_current_booked,
    'is_full', (v_current_booked >= v_max_concurrent)
  );
END;
$$;
DROP INDEX IF EXISTS idx_break_logs_meal_user_date_round;
CREATE UNIQUE INDEX idx_break_logs_meal_user_date_round
  ON break_logs (user_id, break_date, round_key)
  WHERE break_type = 'MEAL' AND round_key IS NOT NULL AND status = 'active';
CREATE OR REPLACE FUNCTION apply_bulk_assignment(
  p_employee_ids UUID[],
  p_start_date DATE,
  p_end_date DATE,
  p_to_branch_id UUID,
  p_to_shift_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  may_run BOOLEAN;
  is_head BOOLEAN;
  emp_id UUID;
  from_branch_id UUID;
  from_shift_id UUID;
  work_d DATE;
  skipped_arr DATE[];
  skip_set DATE[];
  applied_count INT := 0;
  out_skipped JSONB := '{}'::JSONB;
  out_applied INT := 0;
BEGIN
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head'::app_role);
  IF NOT may_run AND NOT is_head THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can run bulk assignment';
  END IF;
  IF is_head AND NOT may_run THEN
    IF p_to_branch_id IS NULL OR p_to_branch_id != my_branch_id() THEN
      RAISE EXCEPTION 'Instructor head can only assign to their own branch';
    END IF;
  END IF;
  FOR emp_id IN SELECT unnest(p_employee_ids)
  LOOP
    skipped_arr := ARRAY[]::DATE[];
    SELECT ARRAY_AGG(h.holiday_date ORDER BY h.holiday_date)
      INTO skip_set
      FROM holidays h
      WHERE h.user_id = emp_id
        AND h.holiday_date BETWEEN p_start_date AND p_end_date
        AND h.status IN ('approved','pending');
    IF skip_set IS NULL THEN skip_set := ARRAY[]::DATE[]; END IF;
    SELECT r.branch_id, r.shift_id INTO from_branch_id, from_shift_id
      FROM monthly_roster r
      WHERE r.user_id = emp_id AND r.work_date BETWEEN p_start_date AND p_end_date
      ORDER BY r.work_date
      LIMIT 1;
    IF from_branch_id IS NULL OR from_shift_id IS NULL THEN
      SELECT p.default_branch_id, p.default_shift_id INTO from_branch_id, from_shift_id
        FROM profiles p WHERE p.id = emp_id LIMIT 1;
    END IF;
    IF from_branch_id IS NULL THEN from_branch_id := p_to_branch_id; END IF;
    IF from_shift_id IS NULL THEN from_shift_id := p_to_shift_id; END IF;
    work_d := p_start_date;
    WHILE work_d <= p_end_date LOOP
      IF work_d = ANY(skip_set) THEN
        skipped_arr := array_append(skipped_arr, work_d);
      ELSE
        DELETE FROM monthly_roster
          WHERE user_id = emp_id AND work_date = work_d;
        INSERT INTO monthly_roster (branch_id, shift_id, user_id, work_date)
          VALUES (p_to_branch_id, p_to_shift_id, emp_id, work_d);
        applied_count := applied_count + 1;
      END IF;
      work_d := work_d + 1;
    END LOOP;
    IF from_branch_id = p_to_branch_id THEN
      INSERT INTO shift_swaps (
        user_id, branch_id, from_shift_id, to_shift_id,
        start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
      ) VALUES (
        emp_id, from_branch_id, from_shift_id, p_to_shift_id,
        p_start_date, p_end_date, p_reason, 'approved', uid, now(),
        CASE WHEN array_length(skipped_arr, 1) > 0
          THEN to_jsonb(ARRAY(SELECT to_char(d, 'YYYY-MM-DD') FROM unnest(skipped_arr) AS d))
          ELSE NULL END
      );
    ELSE
      INSERT INTO cross_branch_transfers (
        user_id, from_branch_id, to_branch_id, from_shift_id, to_shift_id,
        start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
      ) VALUES (
        emp_id, from_branch_id, p_to_branch_id, from_shift_id, p_to_shift_id,
        p_start_date, p_end_date, p_reason, 'approved', uid, now(),
        CASE WHEN array_length(skipped_arr, 1) > 0
          THEN to_jsonb(ARRAY(SELECT to_char(d, 'YYYY-MM-DD') FROM unnest(skipped_arr) AS d))
          ELSE NULL END
      );
    END IF;
    IF array_length(skipped_arr, 1) > 0 THEN
      out_skipped := out_skipped || jsonb_build_object(emp_id::text,
        (SELECT jsonb_agg(to_char(d, 'YYYY-MM-DD')) FROM unnest(skipped_arr) AS d));
    END IF;
  END LOOP;
  out_applied := applied_count;
  RETURN jsonb_build_object(
    'applied', out_applied,
    'skipped_per_user', out_skipped
  );
END;
$$;
CREATE OR REPLACE FUNCTION apply_bulk_assignment(
  p_employee_ids UUID[],
  p_start_date DATE,
  p_end_date DATE,
  p_to_branch_id UUID,
  p_to_shift_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  may_run BOOLEAN;
  is_head BOOLEAN;
  emp_id UUID;
  from_branch_id UUID;
  from_shift_id UUID;
  skip_set DATE[];
  skipped_arr DATE[];
  applied_count INT := 0;
  out_skipped JSONB := '{}'::JSONB;
  out_applied INT := 0;
BEGIN
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head'::app_role);
  IF NOT may_run AND NOT is_head THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can run bulk assignment';
  END IF;
  IF is_head AND NOT may_run THEN
    IF p_to_branch_id IS NULL OR p_to_branch_id != my_branch_id() THEN
      RAISE EXCEPTION 'Instructor head can only assign to their own branch';
    END IF;
  END IF;
  FOR emp_id IN SELECT unnest(p_employee_ids)
  LOOP
    skipped_arr := ARRAY[]::DATE[];
    SELECT ARRAY_AGG(h.holiday_date)
      INTO skip_set
      FROM holidays h
      WHERE h.user_id = emp_id
        AND h.holiday_date = p_start_date
        AND h.status IN ('approved','pending');
    IF skip_set IS NULL THEN skip_set := ARRAY[]::DATE[]; END IF;
    IF p_start_date = ANY(skip_set) THEN
      skipped_arr := array_append(skipped_arr, p_start_date);
    ELSE
      SELECT r.branch_id, r.shift_id INTO from_branch_id, from_shift_id
        FROM monthly_roster r
        WHERE r.user_id = emp_id AND r.work_date = p_start_date
        LIMIT 1;
      IF from_branch_id IS NULL OR from_shift_id IS NULL THEN
        SELECT p.default_branch_id, p.default_shift_id INTO from_branch_id, from_shift_id
          FROM profiles p WHERE p.id = emp_id LIMIT 1;
      END IF;
      IF from_branch_id IS NULL THEN from_branch_id := p_to_branch_id; END IF;
      IF from_shift_id IS NULL THEN from_shift_id := p_to_shift_id; END IF;
      DELETE FROM monthly_roster
        WHERE user_id = emp_id AND work_date = p_start_date;
      INSERT INTO monthly_roster (branch_id, shift_id, user_id, work_date)
        VALUES (p_to_branch_id, p_to_shift_id, emp_id, p_start_date);
      applied_count := applied_count + 1;
      IF from_branch_id = p_to_branch_id THEN
        INSERT INTO shift_swaps (
          user_id, branch_id, from_shift_id, to_shift_id,
          start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
        ) VALUES (
          emp_id, from_branch_id, from_shift_id, p_to_shift_id,
          p_start_date, p_start_date, p_reason, 'approved', uid, now(), NULL
        );
      ELSE
        INSERT INTO cross_branch_transfers (
          user_id, from_branch_id, to_branch_id, from_shift_id, to_shift_id,
          start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
        ) VALUES (
          emp_id, from_branch_id, p_to_branch_id, from_shift_id, p_to_shift_id,
          p_start_date, p_start_date, p_reason, 'approved', uid, now(), NULL
        );
      END IF;
    END IF;
    IF array_length(skipped_arr, 1) > 0 THEN
      out_skipped := out_skipped || jsonb_build_object(emp_id::text,
        (SELECT jsonb_agg(to_char(d, 'YYYY-MM-DD')) FROM unnest(skipped_arr) AS d));
    END IF;
  END LOOP;
  out_applied := applied_count;
  RETURN jsonb_build_object(
    'applied', out_applied,
    'skipped_per_user', out_skipped
  );
END;
$$;
CREATE OR REPLACE FUNCTION apply_paired_swap(
  p_branch_id UUID,
  p_start_date DATE,
  p_end_date DATE,
  p_assignments JSONB,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  may_run BOOLEAN;
  is_head BOOLEAN;
  rec JSONB;
  emp_id UUID;
  to_shift_id UUID;
  from_shift_id UUID;
  skip_set DATE[];
  skipped_arr DATE[];
  applied_count INT := 0;
  out_skipped JSONB := '{}'::JSONB;
  i INT;
BEGIN
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head'::app_role);
  IF NOT may_run AND NOT is_head THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can run paired swap';
  END IF;
  IF is_head AND NOT may_run THEN
    IF p_branch_id IS NULL OR p_branch_id != my_branch_id() THEN
      RAISE EXCEPTION 'Instructor head can only assign to their own branch';
    END IF;
  END IF;
  WITH elem AS (
    SELECT (e->>'user_id')::UUID AS uid, (e->>'to_shift_id')::UUID AS sid, ord
    FROM jsonb_array_elements(p_assignments) WITH ORDINALITY AS t(e, ord)
    WHERE (e->>'user_id')::UUID IS NOT NULL AND (e->>'to_shift_id')::UUID IS NOT NULL
  ),
  deduped AS (
    SELECT uid, sid, ROW_NUMBER() OVER (PARTITION BY uid ORDER BY ord DESC) AS rn FROM elem
  )
  SELECT jsonb_agg(jsonb_build_object('user_id', uid, 'to_shift_id', sid))
  INTO p_assignments
  FROM (SELECT uid, sid FROM deduped WHERE rn = 1) sub;
  IF p_assignments IS NULL THEN p_assignments := '[]'::JSONB; END IF;
  FOR i IN 0 .. jsonb_array_length(p_assignments) - 1 LOOP
    rec := p_assignments->i;
    emp_id := (rec->>'user_id')::UUID;
    to_shift_id := (rec->>'to_shift_id')::UUID;
    IF emp_id IS NULL OR to_shift_id IS NULL THEN CONTINUE; END IF;
    skipped_arr := ARRAY[]::DATE[];
    SELECT ARRAY_AGG(h.holiday_date)
      INTO skip_set
      FROM holidays h
      WHERE h.user_id = emp_id
        AND h.holiday_date = p_start_date
        AND h.status IN ('approved','pending');
    IF skip_set IS NULL THEN skip_set := ARRAY[]::DATE[]; END IF;
    IF p_start_date = ANY(skip_set) THEN
      skipped_arr := array_append(skipped_arr, p_start_date);
    ELSE
      SELECT r.shift_id INTO from_shift_id
        FROM monthly_roster r
        WHERE r.user_id = emp_id AND r.branch_id = p_branch_id AND r.work_date = p_start_date
        LIMIT 1;
      IF from_shift_id IS NULL THEN
        from_shift_id := to_shift_id;
      END IF;
      DELETE FROM monthly_roster
        WHERE user_id = emp_id AND work_date = p_start_date;
      INSERT INTO monthly_roster (branch_id, shift_id, user_id, work_date)
        VALUES (p_branch_id, to_shift_id, emp_id, p_start_date);
      applied_count := applied_count + 1;
      INSERT INTO shift_swaps (
        user_id, branch_id, from_shift_id, to_shift_id,
        start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
      ) VALUES (
        emp_id, p_branch_id, from_shift_id, to_shift_id,
        p_start_date, p_start_date, p_reason, 'approved', uid, now(),
        NULL
      );
    END IF;
    IF array_length(skipped_arr, 1) > 0 THEN
      out_skipped := out_skipped || jsonb_build_object(emp_id::text,
        (SELECT jsonb_agg(to_char(d, 'YYYY-MM-DD')) FROM unnest(skipped_arr) AS d));
    END IF;
  END LOOP;
  RETURN jsonb_build_object(
    'applied', applied_count,
    'skipped_per_user', out_skipped
  );
END;
$$;
CREATE OR REPLACE FUNCTION cancel_scheduled_shift_change(p_type TEXT, p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  v_user_id UUID;
  v_start_date DATE;
  v_branch_id UUID;
  v_row RECORD;
BEGIN
  IF NOT (EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role,'instructor_head'::app_role))) THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can cancel scheduled shift change';
  END IF;
  IF p_type = 'swap' THEN
    SELECT user_id, start_date, branch_id INTO v_user_id, v_start_date, v_branch_id
      FROM shift_swaps WHERE id = p_id AND status = 'approved' LIMIT 1;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'not_found_or_not_approved');
    END IF;
    IF EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head'::app_role) AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role)) THEN
      IF v_branch_id IS NULL OR v_branch_id != my_branch_id() THEN
        RAISE EXCEPTION 'Instructor head can only cancel within their branch';
      END IF;
    END IF;
    DELETE FROM monthly_roster
      WHERE user_id = v_user_id AND work_date = v_start_date AND branch_id = v_branch_id;
    UPDATE shift_swaps SET status = 'cancelled' WHERE id = p_id;
  ELSIF p_type = 'transfer' THEN
    SELECT user_id, start_date, to_branch_id INTO v_user_id, v_start_date, v_branch_id
      FROM cross_branch_transfers WHERE id = p_id AND status = 'approved' LIMIT 1;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'not_found_or_not_approved');
    END IF;
    IF EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head'::app_role) AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role)) THEN
      IF v_branch_id IS NULL OR v_branch_id != my_branch_id() THEN
        RAISE EXCEPTION 'Instructor head can only cancel within their branch';
      END IF;
    END IF;
    DELETE FROM monthly_roster
      WHERE user_id = v_user_id AND work_date = v_start_date AND branch_id = v_branch_id;
    UPDATE cross_branch_transfers SET status = 'cancelled' WHERE id = p_id;
  ELSE
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_type');
  END IF;
  RETURN jsonb_build_object('ok', true);
END;
$$;
CREATE OR REPLACE FUNCTION update_scheduled_shift_change(
  p_type TEXT,
  p_id UUID,
  p_new_start_date DATE,
  p_new_to_shift_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  v_user_id UUID;
  v_old_start DATE;
  v_branch_id UUID;
  v_to_shift_id UUID;
  v_skip_set DATE[];
BEGIN
  IF NOT (EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role,'instructor_head'::app_role))) THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can update scheduled shift change';
  END IF;
  IF p_type = 'swap' THEN
    SELECT user_id, start_date, branch_id, to_shift_id
      INTO v_user_id, v_old_start, v_branch_id, v_to_shift_id
      FROM shift_swaps WHERE id = p_id AND status = 'approved' LIMIT 1;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'not_found_or_not_approved');
    END IF;
    IF EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head'::app_role) AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role)) THEN
      IF v_branch_id != my_branch_id() THEN
        RAISE EXCEPTION 'Instructor head can only update within their branch';
      END IF;
    END IF;
    v_to_shift_id := COALESCE(p_new_to_shift_id, v_to_shift_id);
    DELETE FROM monthly_roster
      WHERE user_id = v_user_id AND work_date = v_old_start AND branch_id = v_branch_id;
    SELECT ARRAY_AGG(h.holiday_date) INTO v_skip_set
      FROM holidays h
      WHERE h.user_id = v_user_id AND h.holiday_date = p_new_start_date
        AND h.status IN ('approved','pending');
    IF v_skip_set IS NULL OR NOT (p_new_start_date = ANY(v_skip_set)) THEN
      INSERT INTO monthly_roster (branch_id, shift_id, user_id, work_date)
        VALUES (v_branch_id, v_to_shift_id, v_user_id, p_new_start_date);
    END IF;
    UPDATE shift_swaps
      SET start_date = p_new_start_date, end_date = p_new_start_date, to_shift_id = v_to_shift_id, updated_at = now()
      WHERE id = p_id;
  ELSIF p_type = 'transfer' THEN
    SELECT user_id, start_date, to_branch_id, to_shift_id
      INTO v_user_id, v_old_start, v_branch_id, v_to_shift_id
      FROM cross_branch_transfers WHERE id = p_id AND status = 'approved' LIMIT 1;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'not_found_or_not_approved');
    END IF;
    IF EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head'::app_role) AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role)) THEN
      IF v_branch_id != my_branch_id() THEN
        RAISE EXCEPTION 'Instructor head can only update within their branch';
      END IF;
    END IF;
    v_to_shift_id := COALESCE(p_new_to_shift_id, v_to_shift_id);
    DELETE FROM monthly_roster
      WHERE user_id = v_user_id AND work_date = v_old_start AND branch_id = v_branch_id;
    SELECT ARRAY_AGG(h.holiday_date) INTO v_skip_set
      FROM holidays h
      WHERE h.user_id = v_user_id AND h.holiday_date = p_new_start_date
        AND h.status IN ('approved','pending');
    IF v_skip_set IS NULL OR NOT (p_new_start_date = ANY(v_skip_set)) THEN
      INSERT INTO monthly_roster (branch_id, shift_id, user_id, work_date)
        VALUES (v_branch_id, v_to_shift_id, v_user_id, p_new_start_date);
    END IF;
    UPDATE cross_branch_transfers
      SET start_date = p_new_start_date, end_date = p_new_start_date, to_shift_id = v_to_shift_id, updated_at = now()
      WHERE id = p_id;
  ELSE
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_type');
  END IF;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION cancel_scheduled_shift_change(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION update_scheduled_shift_change(TEXT, UUID, DATE, UUID) TO authenticated;
UPDATE shift_swaps s
SET from_shift_id = p.default_shift_id
FROM profiles p
WHERE s.user_id = p.id
  AND s.from_shift_id = s.to_shift_id
  AND s.status = 'approved'
  AND p.default_shift_id IS NOT NULL
  AND p.default_shift_id IS DISTINCT FROM s.to_shift_id;
UPDATE cross_branch_transfers t
SET from_shift_id = p.default_shift_id
FROM profiles p
WHERE t.user_id = p.id
  AND t.from_shift_id = t.to_shift_id
  AND t.status = 'approved'
  AND p.default_shift_id IS NOT NULL
  AND p.default_shift_id IS DISTINCT FROM t.to_shift_id;
CREATE OR REPLACE FUNCTION apply_bulk_assignment(
  p_employee_ids UUID[],
  p_start_date DATE,
  p_end_date DATE,
  p_to_branch_id UUID,
  p_to_shift_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  may_run BOOLEAN;
  is_head BOOLEAN;
  emp_id UUID;
  from_branch_id UUID;
  from_shift_id UUID;
  skip_set DATE[];
  skipped_arr DATE[];
  applied_count INT := 0;
  out_skipped JSONB := '{}'::JSONB;
  out_applied INT := 0;
BEGIN
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head'::app_role);
  IF NOT may_run AND NOT is_head THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can run bulk assignment';
  END IF;
  IF is_head AND NOT may_run THEN
    IF p_to_branch_id IS NULL OR p_to_branch_id != my_branch_id() THEN
      RAISE EXCEPTION 'Instructor head can only assign to their own branch';
    END IF;
  END IF;
  FOR emp_id IN SELECT unnest(p_employee_ids)
  LOOP
    skipped_arr := ARRAY[]::DATE[];
    SELECT ARRAY_AGG(h.holiday_date)
      INTO skip_set
      FROM holidays h
      WHERE h.user_id = emp_id
        AND h.holiday_date = p_start_date
        AND h.status IN ('approved','pending');
    IF skip_set IS NULL THEN skip_set := ARRAY[]::DATE[]; END IF;
    IF p_start_date = ANY(skip_set) THEN
      skipped_arr := array_append(skipped_arr, p_start_date);
    ELSE
      SELECT r.branch_id, r.shift_id INTO from_branch_id, from_shift_id
        FROM monthly_roster r
        WHERE r.user_id = emp_id AND r.work_date = p_start_date
        LIMIT 1;
      IF from_branch_id IS NULL OR from_shift_id IS NULL THEN
        SELECT p.default_branch_id, p.default_shift_id INTO from_branch_id, from_shift_id
          FROM profiles p WHERE p.id = emp_id LIMIT 1;
      END IF;
      IF from_branch_id IS NULL THEN from_branch_id := p_to_branch_id; END IF;
      IF from_shift_id IS NULL THEN from_shift_id := p_to_shift_id; END IF;
      DELETE FROM monthly_roster
        WHERE user_id = emp_id AND work_date = p_start_date;
      INSERT INTO monthly_roster (branch_id, shift_id, user_id, work_date)
        VALUES (p_to_branch_id, p_to_shift_id, emp_id, p_start_date);
      applied_count := applied_count + 1;
      IF from_branch_id = p_to_branch_id THEN
        IF from_shift_id IS DISTINCT FROM p_to_shift_id THEN
          INSERT INTO shift_swaps (
            user_id, branch_id, from_shift_id, to_shift_id,
            start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
          ) VALUES (
            emp_id, from_branch_id, from_shift_id, p_to_shift_id,
            p_start_date, p_start_date, p_reason, 'approved', uid, now(), NULL
          );
        END IF;
      ELSE
        INSERT INTO cross_branch_transfers (
          user_id, from_branch_id, to_branch_id, from_shift_id, to_shift_id,
          start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
        ) VALUES (
          emp_id, from_branch_id, p_to_branch_id, from_shift_id, p_to_shift_id,
          p_start_date, p_start_date, p_reason, 'approved', uid, now(), NULL
        );
      END IF;
    END IF;
    IF array_length(skipped_arr, 1) > 0 THEN
      out_skipped := out_skipped || jsonb_build_object(emp_id::text,
        (SELECT jsonb_agg(to_char(d, 'YYYY-MM-DD')) FROM unnest(skipped_arr) AS d));
    END IF;
  END LOOP;
  out_applied := applied_count;
  RETURN jsonb_build_object(
    'applied', out_applied,
    'skipped_per_user', out_skipped
  );
END;
$$;
CREATE OR REPLACE FUNCTION apply_paired_swap(
  p_branch_id UUID,
  p_start_date DATE,
  p_end_date DATE,
  p_assignments JSONB,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  may_run BOOLEAN;
  is_head BOOLEAN;
  rec JSONB;
  emp_id UUID;
  to_shift_id UUID;
  from_shift_id UUID;
  skip_set DATE[];
  skipped_arr DATE[];
  applied_count INT := 0;
  out_skipped JSONB := '{}'::JSONB;
  i INT;
BEGIN
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head'::app_role);
  IF NOT may_run AND NOT is_head THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can run paired swap';
  END IF;
  IF is_head AND NOT may_run THEN
    IF p_branch_id IS NULL OR p_branch_id != my_branch_id() THEN
      RAISE EXCEPTION 'Instructor head can only assign to their own branch';
    END IF;
  END IF;
  WITH elem AS (
    SELECT (e->>'user_id')::UUID AS uid, (e->>'to_shift_id')::UUID AS sid, ord
    FROM jsonb_array_elements(p_assignments) WITH ORDINALITY AS t(e, ord)
    WHERE (e->>'user_id')::UUID IS NOT NULL AND (e->>'to_shift_id')::UUID IS NOT NULL
  ),
  deduped AS (
    SELECT uid, sid, ROW_NUMBER() OVER (PARTITION BY uid ORDER BY ord DESC) AS rn FROM elem
  )
  SELECT jsonb_agg(jsonb_build_object('user_id', uid, 'to_shift_id', sid))
  INTO p_assignments
  FROM (SELECT uid, sid FROM deduped WHERE rn = 1) sub;
  IF p_assignments IS NULL THEN p_assignments := '[]'::JSONB; END IF;
  FOR i IN 0 .. jsonb_array_length(p_assignments) - 1 LOOP
    rec := p_assignments->i;
    emp_id := (rec->>'user_id')::UUID;
    to_shift_id := (rec->>'to_shift_id')::UUID;
    IF emp_id IS NULL OR to_shift_id IS NULL THEN CONTINUE; END IF;
    skipped_arr := ARRAY[]::DATE[];
    SELECT ARRAY_AGG(h.holiday_date)
      INTO skip_set
      FROM holidays h
      WHERE h.user_id = emp_id
        AND h.holiday_date = p_start_date
        AND h.status IN ('approved','pending');
    IF skip_set IS NULL THEN skip_set := ARRAY[]::DATE[]; END IF;
    IF p_start_date = ANY(skip_set) THEN
      skipped_arr := array_append(skipped_arr, p_start_date);
    ELSE
      SELECT r.shift_id INTO from_shift_id
        FROM monthly_roster r
        WHERE r.user_id = emp_id AND r.branch_id = p_branch_id AND r.work_date = p_start_date
        LIMIT 1;
      IF from_shift_id IS NULL THEN
        SELECT p.default_shift_id INTO from_shift_id
          FROM profiles p WHERE p.id = emp_id LIMIT 1;
      END IF;
      IF from_shift_id IS NULL THEN
        from_shift_id := to_shift_id;
      END IF;
      DELETE FROM monthly_roster
        WHERE user_id = emp_id AND work_date = p_start_date;
      INSERT INTO monthly_roster (branch_id, shift_id, user_id, work_date)
        VALUES (p_branch_id, to_shift_id, emp_id, p_start_date);
      applied_count := applied_count + 1;
      IF from_shift_id IS DISTINCT FROM to_shift_id THEN
        INSERT INTO shift_swaps (
          user_id, branch_id, from_shift_id, to_shift_id,
          start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
        ) VALUES (
          emp_id, p_branch_id, from_shift_id, to_shift_id,
          p_start_date, p_start_date, p_reason, 'approved', uid, now(),
          NULL
        );
      END IF;
    END IF;
    IF array_length(skipped_arr, 1) > 0 THEN
      out_skipped := out_skipped || jsonb_build_object(emp_id::text,
        (SELECT jsonb_agg(to_char(d, 'YYYY-MM-DD')) FROM unnest(skipped_arr) AS d));
    END IF;
  END LOOP;
  RETURN jsonb_build_object(
    'applied', applied_count,
    'skipped_per_user', out_skipped
  );
END;
$$;
ALTER TABLE schedule_cards ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE group_links ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES profiles(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_schedule_cards_created_by ON schedule_cards(created_by);
CREATE INDEX IF NOT EXISTS idx_group_links_created_by ON group_links(created_by);
CREATE OR REPLACE FUNCTION get_meal_capacity_break_logs(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_work_date DATE,
  p_round_key TEXT,
  p_slot_start_ts TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_holiday_date DATE;
  v_on_duty_count INT;
  v_max_concurrent INT;
  v_current_booked INT;
  v_user_group TEXT;
  v_scope_by_website BOOLEAN := true;
BEGIN
  v_holiday_date := DATE(p_slot_start_ts);
  v_user_group := my_user_group();
  SELECT COALESCE(ms.scope_meal_quota_by_website, true) INTO v_scope_by_website
  FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;
  IF v_scope_by_website THEN
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      INNER JOIN website_assignments wa
        ON wa.user_id = p.id
       AND wa.website_id = p_website_id
       AND wa.is_primary = true
      WHERE p.default_branch_id = p_branch_id
        AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status = 'approved'
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    ),
    last_log AS (
      SELECT DISTINCT ON (wl.user_id) wl.user_id, wl.log_type
      FROM work_logs wl
      WHERE wl.logical_date = p_work_date
        AND wl.branch_id = p_branch_id
        AND wl.shift_id = p_shift_id
        AND wl.user_id IN (SELECT id FROM eligible)
      ORDER BY wl.user_id, wl.logged_at DESC
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM last_log WHERE log_type = 'IN';
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id
      AND shift_id = p_shift_id
      AND website_id = p_website_id
      AND break_date = p_work_date
      AND round_key = p_round_key
      AND started_at = p_slot_start_ts
      AND break_type = 'MEAL'
      AND status = 'active'
      AND (user_group = v_user_group OR v_user_group IS NULL);
  ELSE
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      WHERE p.default_branch_id = p_branch_id
        AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status = 'approved'
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    ),
    last_log AS (
      SELECT DISTINCT ON (wl.user_id) wl.user_id, wl.log_type
      FROM work_logs wl
      WHERE wl.logical_date = p_work_date
        AND wl.branch_id = p_branch_id
        AND wl.shift_id = p_shift_id
        AND wl.user_id IN (SELECT id FROM eligible)
      ORDER BY wl.user_id, wl.logged_at DESC
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM last_log WHERE log_type = 'IN';
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id
      AND shift_id = p_shift_id
      AND break_date = p_work_date
      AND round_key = p_round_key
      AND started_at = p_slot_start_ts
      AND break_type = 'MEAL'
      AND status = 'active'
      AND (user_group = v_user_group OR v_user_group IS NULL);
  END IF;
  v_max_concurrent := get_meal_quota_for_group(p_branch_id, p_shift_id, p_website_id, v_user_group, v_on_duty_count);
  RETURN jsonb_build_object(
    'on_duty_count', v_on_duty_count,
    'max_concurrent', v_max_concurrent,
    'current_booked', v_current_booked,
    'is_full', (v_current_booked >= v_max_concurrent)
  );
END;
$$;
CREATE OR REPLACE FUNCTION get_meal_capacity_break_logs(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_work_date DATE,
  p_round_key TEXT,
  p_slot_start_ts TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_holiday_date DATE;
  v_on_duty_count INT;
  v_max_concurrent INT;
  v_current_booked INT;
  v_user_group TEXT;
  v_scope_by_website BOOLEAN := true;
BEGIN
  v_holiday_date := DATE(p_slot_start_ts);
  v_user_group := my_user_group();
  SELECT COALESCE(ms.scope_meal_quota_by_website, true) INTO v_scope_by_website
  FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;
  IF v_scope_by_website THEN
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      INNER JOIN website_assignments wa
        ON wa.user_id = p.id
       AND wa.website_id = p_website_id
       AND wa.is_primary = true
      WHERE p.default_branch_id = p_branch_id
        AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status = 'approved'
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id
      AND shift_id = p_shift_id
      AND website_id = p_website_id
      AND break_date = p_work_date
      AND round_key = p_round_key
      AND started_at = p_slot_start_ts
      AND break_type = 'MEAL'
      AND status = 'active'
      AND (user_group = v_user_group OR v_user_group IS NULL);
  ELSE
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      WHERE p.default_branch_id = p_branch_id
        AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status = 'approved'
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id
      AND shift_id = p_shift_id
      AND break_date = p_work_date
      AND round_key = p_round_key
      AND started_at = p_slot_start_ts
      AND break_type = 'MEAL'
      AND status = 'active'
      AND (user_group = v_user_group OR v_user_group IS NULL);
  END IF;
  v_max_concurrent := get_meal_quota_for_group(p_branch_id, p_shift_id, p_website_id, v_user_group, v_on_duty_count);
  RETURN jsonb_build_object(
    'on_duty_count', v_on_duty_count,
    'max_concurrent', v_max_concurrent,
    'current_booked', v_current_booked,
    'is_full', (v_current_booked >= v_max_concurrent)
  );
END;
$$;
CREATE OR REPLACE FUNCTION get_meal_quota_for_group(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_user_group TEXT,
  p_on_duty_count INT
)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((
    SELECT mqr.max_concurrent
    FROM meal_quota_rules mqr
    WHERE
      (mqr.branch_id = p_branch_id OR mqr.branch_id IS NULL)
      AND (mqr.shift_id = p_shift_id OR mqr.shift_id IS NULL)
      AND (mqr.website_id = p_website_id OR mqr.website_id IS NULL)
      AND (mqr.user_group = p_user_group OR mqr.user_group IS NULL)
      AND mqr.on_duty_threshold >= p_on_duty_count
    ORDER BY
      (
        (CASE WHEN mqr.branch_id IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN mqr.shift_id IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN mqr.website_id IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN mqr.user_group IS NOT NULL THEN 1 ELSE 0 END)
      ) DESC,
      mqr.max_concurrent ASC,
      mqr.on_duty_threshold ASC,
      mqr.created_at DESC
    LIMIT 1
  ), 1);
$$;
CREATE OR REPLACE FUNCTION get_meal_capacity_break_logs(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_work_date DATE,
  p_round_key TEXT,
  p_slot_start_ts TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_holiday_date DATE;
  v_on_duty_count INT;
  v_max_concurrent INT;
  v_current_booked INT;
  v_user_group TEXT;
  v_scope_by_website BOOLEAN := true;
  v_booked_user_ids JSONB;
BEGIN
  v_holiday_date := DATE(p_slot_start_ts);
  v_user_group := my_user_group();
  SELECT COALESCE(ms.scope_meal_quota_by_website, true) INTO v_scope_by_website
  FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;
  IF v_scope_by_website THEN
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      INNER JOIN website_assignments wa
        ON wa.user_id = p.id
       AND wa.website_id = p_website_id
       AND wa.is_primary = true
      WHERE p.default_branch_id = p_branch_id
        AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status = 'approved'
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id
      AND shift_id = p_shift_id
      AND website_id = p_website_id
      AND break_date = p_work_date
      AND round_key = p_round_key
      AND started_at = p_slot_start_ts
      AND break_type = 'MEAL'
      AND status = 'active'
      AND (user_group = v_user_group OR v_user_group IS NULL);
    SELECT COALESCE(jsonb_agg(bl.user_id ORDER BY bl.user_id), '[]'::JSONB) INTO v_booked_user_ids
    FROM break_logs bl
    WHERE bl.branch_id = p_branch_id
      AND bl.shift_id = p_shift_id
      AND bl.website_id = p_website_id
      AND bl.break_date = p_work_date
      AND bl.round_key = p_round_key
      AND bl.started_at = p_slot_start_ts
      AND bl.break_type = 'MEAL'
      AND bl.status = 'active'
      AND (bl.user_group = v_user_group OR v_user_group IS NULL);
  ELSE
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      WHERE p.default_branch_id = p_branch_id
        AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status = 'approved'
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id
      AND shift_id = p_shift_id
      AND break_date = p_work_date
      AND round_key = p_round_key
      AND started_at = p_slot_start_ts
      AND break_type = 'MEAL'
      AND status = 'active'
      AND (user_group = v_user_group OR v_user_group IS NULL);
    SELECT COALESCE(jsonb_agg(bl.user_id ORDER BY bl.user_id), '[]'::JSONB) INTO v_booked_user_ids
    FROM break_logs bl
    WHERE bl.branch_id = p_branch_id
      AND bl.shift_id = p_shift_id
      AND bl.break_date = p_work_date
      AND bl.round_key = p_round_key
      AND bl.started_at = p_slot_start_ts
      AND bl.break_type = 'MEAL'
      AND bl.status = 'active'
      AND (bl.user_group = v_user_group OR v_user_group IS NULL);
  END IF;
  v_max_concurrent := get_meal_quota_for_group(p_branch_id, p_shift_id, p_website_id, v_user_group, v_on_duty_count);
  RETURN jsonb_build_object(
    'on_duty_count', v_on_duty_count,
    'max_concurrent', v_max_concurrent,
    'current_booked', v_current_booked,
    'is_full', (v_current_booked >= v_max_concurrent),
    'booked_user_ids', COALESCE(v_booked_user_ids, '[]'::JSONB)
  );
END;
$$;
CREATE OR REPLACE FUNCTION get_meal_on_duty_user_ids(p_work_date DATE)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_branch_id UUID;
  v_shift_id UUID;
  v_website_id UUID;
  v_holiday_date DATE := p_work_date;
  v_user_group TEXT;
  v_scope_by_website BOOLEAN := true;
  v_result JSONB;
BEGIN
  SELECT p.default_branch_id, p.default_shift_id INTO v_branch_id, v_shift_id FROM profiles p WHERE p.id = v_uid LIMIT 1;
  SELECT wa.website_id INTO v_website_id FROM website_assignments wa WHERE wa.user_id = v_uid AND wa.is_primary = true LIMIT 1;
  IF v_branch_id IS NULL OR v_shift_id IS NULL OR v_website_id IS NULL THEN
    RETURN '[]'::JSONB;
  END IF;
  v_user_group := my_user_group();
  SELECT COALESCE(ms.scope_meal_quota_by_website, true) INTO v_scope_by_website
  FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;
  IF v_scope_by_website THEN
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      INNER JOIN website_assignments wa
        ON wa.user_id = p.id
       AND wa.website_id = v_website_id
       AND wa.is_primary = true
      WHERE p.default_branch_id = v_branch_id
        AND p.default_shift_id = v_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status = 'approved'
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    )
    SELECT COALESCE(jsonb_agg(id ORDER BY id), '[]'::JSONB) INTO v_result FROM eligible;
  ELSE
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      WHERE p.default_branch_id = v_branch_id
        AND p.default_shift_id = v_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status = 'approved'
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    )
    SELECT COALESCE(jsonb_agg(id ORDER BY id), '[]'::JSONB) INTO v_result FROM eligible;
  END IF;
  RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;
CREATE OR REPLACE FUNCTION get_meal_slots_unified(p_work_date DATE)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_branch_id UUID;
  v_shift_id UUID;
  v_website_id UUID;
  v_shift_start_ts TIMESTAMPTZ;
  v_shift_end_ts TIMESTAMPTZ;
  v_shift_start_time TIME;
  v_settings JSONB;
  v_rounds JSONB;
  v_round JSONB;
  v_slot JSONB;
  v_round_key TEXT;
  v_slot_start_ts TIMESTAMPTZ;
  v_slot_end_ts TIMESTAMPTZ;
  v_cap JSONB;
  v_my_bookings JSONB := '[]'::JSONB;
  v_meal_count INT;
  v_out_rounds JSONB := '[]'::JSONB;
  v_slots_in_round JSONB;
  v_booked_count INT;
  v_max_concurrent INT;
  v_is_booked_by_me BOOLEAN;
  v_available BOOLEAN;
  v_on_duty_user_ids JSONB;
  i INT; j INT;
BEGIN
  SELECT p.default_branch_id, p.default_shift_id INTO v_branch_id, v_shift_id FROM profiles p WHERE p.id = v_uid LIMIT 1;
  SELECT wa.website_id INTO v_website_id FROM website_assignments wa WHERE wa.user_id = v_uid AND wa.is_primary = true LIMIT 1;
  IF v_branch_id IS NULL OR v_shift_id IS NULL OR v_website_id IS NULL THEN
    RETURN jsonb_build_object('error', 'missing_branch_shift_website', 'rounds', '[]'::JSONB, 'my_bookings', '[]'::JSONB, 'meal_count', 0, 'on_duty_user_ids', '[]'::JSONB);
  END IF;
  v_on_duty_user_ids := get_meal_on_duty_user_ids(p_work_date);
  SELECT s.start_time, (p_work_date + s.start_time)::TIMESTAMPTZ, (p_work_date + s.end_time)::TIMESTAMPTZ
  INTO v_shift_start_time, v_shift_start_ts, v_shift_end_ts
  FROM shifts s WHERE s.id = v_shift_id LIMIT 1;
  IF v_shift_start_ts IS NULL THEN
    RETURN jsonb_build_object('error', 'shift_not_found', 'rounds', '[]'::JSONB, 'my_bookings', '[]'::JSONB, 'meal_count', 0, 'on_duty_user_ids', v_on_duty_user_ids);
  END IF;
  IF v_shift_end_ts <= v_shift_start_ts THEN
    v_shift_end_ts := (p_work_date + 1 + (SELECT end_time FROM shifts WHERE id = v_shift_id))::TIMESTAMPTZ;
  END IF;
  SELECT rounds_json INTO v_settings FROM meal_settings WHERE is_enabled = true ORDER BY effective_from DESC LIMIT 1;
  IF v_settings IS NULL OR (v_settings->'rounds') IS NULL THEN
    RETURN jsonb_build_object('work_date', p_work_date, 'shift_start_ts', v_shift_start_ts, 'shift_end_ts', v_shift_end_ts, 'rounds', '[]'::JSONB, 'my_bookings', '[]'::JSONB, 'meal_count', 0, 'on_duty_user_ids', v_on_duty_user_ids);
  END IF;
  v_rounds := v_settings->'rounds';
  SELECT COUNT(*)::INT INTO v_meal_count
  FROM break_logs WHERE user_id = v_uid AND break_date = p_work_date AND break_type = 'MEAL' AND status = 'active';
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'round_key', round_key, 'slot_start_ts', started_at, 'slot_end_ts', ended_at)), '[]'::JSONB) INTO v_my_bookings
  FROM break_logs
  WHERE user_id = v_uid AND break_date = p_work_date AND break_type = 'MEAL' AND status = 'active';
  FOR i IN 0 .. jsonb_array_length(v_rounds) - 1 LOOP
    v_round := v_rounds->i;
    v_round_key := v_round->>'key';
    IF v_round_key IS NULL OR v_round_key = '' THEN v_round_key := 'round_' || i; END IF;
    v_slots_in_round := '[]'::JSONB;
    FOR j IN 0 .. jsonb_array_length(COALESCE(v_round->'slots', '[]'::JSONB)) - 1 LOOP
      v_slot := (v_round->'slots')->j;
      v_slot_start_ts := (p_work_date + ((v_slot->>'start')::TIME))::TIMESTAMPTZ;
      v_slot_end_ts := (p_work_date + ((v_slot->>'end')::TIME))::TIMESTAMPTZ;
      IF v_shift_end_ts <= v_shift_start_ts AND ((v_slot->>'start')::TIME) < v_shift_start_time THEN
        v_slot_start_ts := (p_work_date + 1 + ((v_slot->>'start')::TIME))::TIMESTAMPTZ;
        v_slot_end_ts := (p_work_date + 1 + ((v_slot->>'end')::TIME))::TIMESTAMPTZ;
      ELSIF v_slot_end_ts <= v_slot_start_ts THEN
        v_slot_end_ts := (p_work_date + 1 + ((v_slot->>'end')::TIME))::TIMESTAMPTZ;
      END IF;
      v_cap := get_meal_capacity_break_logs(v_branch_id, v_shift_id, v_website_id, p_work_date, v_round_key, v_slot_start_ts);
      v_booked_count := COALESCE((v_cap->>'current_booked')::INT, 0);
      v_max_concurrent := COALESCE((v_cap->>'max_concurrent')::INT, 1);
      SELECT EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_my_bookings) AS el
        WHERE (el->>'slot_start_ts')::timestamptz = v_slot_start_ts
      ) INTO v_is_booked_by_me;
      v_available := (v_booked_count < v_max_concurrent) AND NOT v_is_booked_by_me;
      v_slots_in_round := v_slots_in_round || jsonb_build_array(jsonb_build_object(
        'slot_start', v_slot->>'start', 'slot_end', v_slot->>'end',
        'slot_start_ts', v_slot_start_ts, 'slot_end_ts', v_slot_end_ts,
        'booked_count', v_booked_count, 'max_concurrent', v_max_concurrent,
        'is_booked_by_me', v_is_booked_by_me, 'available', v_available,
        'capacity', v_cap
      ));
    END LOOP;
    v_out_rounds := v_out_rounds || jsonb_build_array(jsonb_build_object(
      'round_key', v_round_key, 'round_name', v_round->>'name', 'slots', v_slots_in_round
    ));
  END LOOP;
  RETURN jsonb_build_object(
    'work_date', p_work_date,
    'shift_start_ts', v_shift_start_ts,
    'shift_end_ts', v_shift_end_ts,
    'rounds', v_out_rounds,
    'my_bookings', v_my_bookings,
    'meal_count', v_meal_count,
    'on_duty_user_ids', v_on_duty_user_ids
  );
END;
$$;
CREATE OR REPLACE FUNCTION get_meal_capacity_break_logs(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_work_date DATE,
  p_round_key TEXT,
  p_slot_start_ts TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_holiday_date DATE;
  v_on_duty_count INT;
  v_max_concurrent INT;
  v_current_booked INT;
  v_user_group TEXT;
  v_scope_by_website BOOLEAN := true;
  v_booked_user_ids JSONB;
BEGIN
  v_holiday_date := DATE(p_slot_start_ts);
  v_user_group := my_user_group();
  SELECT COALESCE(ms.scope_meal_quota_by_website, true) INTO v_scope_by_website
  FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;
  IF v_scope_by_website THEN
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      INNER JOIN website_assignments wa
        ON wa.user_id = p.id
       AND wa.website_id = p_website_id
       AND wa.is_primary = true
      WHERE p.default_branch_id = p_branch_id
        AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status = 'approved'
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id
      AND shift_id = p_shift_id
      AND website_id = p_website_id
      AND break_date = p_work_date
      AND round_key = p_round_key
      AND started_at = p_slot_start_ts
      AND break_type = 'MEAL'
      AND status = 'active'
      AND (user_group = v_user_group OR v_user_group IS NULL);
    SELECT COALESCE(jsonb_agg(bl.user_id ORDER BY bl.user_id), '[]'::JSONB) INTO v_booked_user_ids
    FROM break_logs bl
    WHERE bl.branch_id = p_branch_id
      AND bl.shift_id = p_shift_id
      AND bl.website_id = p_website_id
      AND bl.break_date = p_work_date
      AND bl.round_key = p_round_key
      AND bl.started_at = p_slot_start_ts
      AND bl.break_type = 'MEAL'
      AND bl.status = 'active'
      AND (bl.user_group = v_user_group OR v_user_group IS NULL);
  ELSE
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      WHERE p.default_branch_id = p_branch_id
        AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status = 'approved'
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id
      AND shift_id = p_shift_id
      AND break_date = p_work_date
      AND round_key = p_round_key
      AND started_at = p_slot_start_ts
      AND break_type = 'MEAL'
      AND status = 'active'
      AND (user_group = v_user_group OR v_user_group IS NULL);
    SELECT COALESCE(jsonb_agg(bl.user_id ORDER BY bl.user_id), '[]'::JSONB) INTO v_booked_user_ids
    FROM break_logs bl
    WHERE bl.branch_id = p_branch_id
      AND bl.shift_id = p_shift_id
      AND bl.break_date = p_work_date
      AND bl.round_key = p_round_key
      AND bl.started_at = p_slot_start_ts
      AND bl.break_type = 'MEAL'
      AND bl.status = 'active'
      AND (bl.user_group = v_user_group OR v_user_group IS NULL);
  END IF;
  v_max_concurrent := get_meal_quota_for_group(p_branch_id, p_shift_id, p_website_id, v_user_group, v_on_duty_count);
  IF v_on_duty_count <= 4 AND v_max_concurrent > 1 THEN
    v_max_concurrent := 1;
  END IF;
  RETURN jsonb_build_object(
    'on_duty_count', v_on_duty_count,
    'max_concurrent', v_max_concurrent,
    'current_booked', v_current_booked,
    'is_full', (v_current_booked >= v_max_concurrent),
    'booked_user_ids', COALESCE(v_booked_user_ids, '[]'::JSONB)
  );
END;
$$;
CREATE OR REPLACE FUNCTION get_meal_capacity_break_logs(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_work_date DATE,
  p_round_key TEXT,
  p_slot_start_ts TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_holiday_date DATE;
  v_on_duty_count INT;
  v_max_concurrent INT;
  v_current_booked INT;
  v_user_group TEXT;
  v_scope_by_website BOOLEAN := true;
  v_booked_user_ids JSONB;
BEGIN
  v_holiday_date := DATE(p_slot_start_ts);
  v_user_group := my_user_group();
  SELECT COALESCE(ms.scope_meal_quota_by_website, true) INTO v_scope_by_website
  FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;
  IF v_scope_by_website THEN
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      INNER JOIN website_assignments wa
        ON wa.user_id = p.id
       AND wa.website_id = p_website_id
       AND wa.is_primary = true
      WHERE p.default_branch_id = p_branch_id
        AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status = 'approved'
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id
      AND shift_id = p_shift_id
      AND website_id = p_website_id
      AND break_date = p_work_date
      AND round_key = p_round_key
      AND started_at = p_slot_start_ts
      AND break_type = 'MEAL'
      AND status = 'active'
      AND (user_group = v_user_group OR v_user_group IS NULL);
    SELECT COALESCE(jsonb_agg(bl.user_id ORDER BY bl.user_id), '[]'::JSONB) INTO v_booked_user_ids
    FROM break_logs bl
    WHERE bl.branch_id = p_branch_id
      AND bl.shift_id = p_shift_id
      AND bl.website_id = p_website_id
      AND bl.break_date = p_work_date
      AND bl.round_key = p_round_key
      AND bl.started_at = p_slot_start_ts
      AND bl.break_type = 'MEAL'
      AND bl.status = 'active'
      AND (bl.user_group = v_user_group OR v_user_group IS NULL);
  ELSE
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      WHERE p.default_branch_id = p_branch_id
        AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status = 'approved'
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id
      AND shift_id = p_shift_id
      AND break_date = p_work_date
      AND round_key = p_round_key
      AND started_at = p_slot_start_ts
      AND break_type = 'MEAL'
      AND status = 'active'
      AND (user_group = v_user_group OR v_user_group IS NULL);
    SELECT COALESCE(jsonb_agg(bl.user_id ORDER BY bl.user_id), '[]'::JSONB) INTO v_booked_user_ids
    FROM break_logs bl
    WHERE bl.branch_id = p_branch_id
      AND bl.shift_id = p_shift_id
      AND bl.break_date = p_work_date
      AND bl.round_key = p_round_key
      AND bl.started_at = p_slot_start_ts
      AND bl.break_type = 'MEAL'
      AND bl.status = 'active'
      AND (bl.user_group = v_user_group OR v_user_group IS NULL);
  END IF;
  v_max_concurrent := get_meal_quota_for_group(p_branch_id, p_shift_id, p_website_id, v_user_group, v_on_duty_count);
  RETURN jsonb_build_object(
    'on_duty_count', v_on_duty_count,
    'max_concurrent', v_max_concurrent,
    'current_booked', v_current_booked,
    'is_full', (v_current_booked >= v_max_concurrent),
    'booked_user_ids', COALESCE(v_booked_user_ids, '[]'::JSONB)
  );
END;
$$;
CREATE OR REPLACE FUNCTION get_meal_quota_for_group(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_user_group TEXT,
  p_on_duty_count INT
)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
  WITH matching AS (
    SELECT
      mqr.max_concurrent,
      (CASE WHEN mqr.branch_id IS NOT NULL THEN 1 ELSE 0 END) +
      (CASE WHEN mqr.shift_id IS NOT NULL THEN 1 ELSE 0 END) +
      (CASE WHEN mqr.website_id IS NOT NULL THEN 1 ELSE 0 END) +
      (CASE WHEN mqr.user_group IS NOT NULL THEN 1 ELSE 0 END) AS spec
    FROM meal_quota_rules mqr
    WHERE
      (mqr.branch_id = p_branch_id OR mqr.branch_id IS NULL)
      AND (mqr.shift_id = p_shift_id OR mqr.shift_id IS NULL)
      AND (mqr.website_id = p_website_id OR mqr.website_id IS NULL)
      AND (mqr.user_group = p_user_group OR mqr.user_group IS NULL)
      AND mqr.on_duty_threshold >= p_on_duty_count
  ),
  best_spec AS (
    SELECT MAX(spec) AS ms FROM matching
  )
  SELECT COALESCE(
    (
      SELECT MIN(m.max_concurrent)
      FROM matching m
      INNER JOIN best_spec b ON m.spec = b.ms
    ),
    1
  );
$$;
CREATE OR REPLACE FUNCTION apply_paired_swap(
  p_branch_id UUID,
  p_start_date DATE,
  p_end_date DATE,
  p_assignments JSONB,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_uid UUID := auth.uid();
  may_run BOOLEAN;
  is_head BOOLEAN;
  rec JSONB;
  emp_id UUID;
  to_shift_id UUID;
  from_shift_id UUID;
  skip_set DATE[];
  skipped_arr DATE[];
  applied_count INT := 0;
  out_skipped JSONB := '{}'::JSONB;
  i INT;
BEGIN
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = caller_uid AND role IN ('admin'::app_role,'manager'::app_role));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = caller_uid AND role = 'instructor_head'::app_role);
  IF NOT may_run AND NOT is_head THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can run paired swap';
  END IF;
  IF is_head AND NOT may_run THEN
    IF p_branch_id IS NULL OR p_branch_id != my_branch_id() THEN
      RAISE EXCEPTION 'Instructor head can only assign to their own branch';
    END IF;
  END IF;
  WITH elem AS (
    SELECT (e->>'user_id')::UUID AS elem_uid, (e->>'to_shift_id')::UUID AS elem_sid, ord
    FROM jsonb_array_elements(p_assignments) WITH ORDINALITY AS t(e, ord)
    WHERE (e->>'user_id')::UUID IS NOT NULL AND (e->>'to_shift_id')::UUID IS NOT NULL
  ),
  deduped AS (
    SELECT elem_uid, elem_sid, ROW_NUMBER() OVER (PARTITION BY elem_uid ORDER BY ord DESC) AS rn FROM elem
  )
  SELECT jsonb_agg(jsonb_build_object('user_id', d.elem_uid, 'to_shift_id', d.elem_sid))
  INTO p_assignments
  FROM (SELECT elem_uid, elem_sid FROM deduped WHERE rn = 1) d;
  IF p_assignments IS NULL THEN p_assignments := '[]'::JSONB; END IF;
  FOR i IN 0 .. jsonb_array_length(p_assignments) - 1 LOOP
    rec := p_assignments->i;
    emp_id := (rec->>'user_id')::UUID;
    to_shift_id := (rec->>'to_shift_id')::UUID;
    IF emp_id IS NULL OR to_shift_id IS NULL THEN CONTINUE; END IF;
    skipped_arr := ARRAY[]::DATE[];
    SELECT ARRAY_AGG(h.holiday_date)
      INTO skip_set
      FROM holidays h
      WHERE h.user_id = emp_id
        AND h.holiday_date = p_start_date
        AND h.status IN ('approved','pending');
    IF skip_set IS NULL THEN skip_set := ARRAY[]::DATE[]; END IF;
    IF p_start_date = ANY(skip_set) THEN
      skipped_arr := array_append(skipped_arr, p_start_date);
    ELSE
      SELECT r.shift_id INTO from_shift_id
        FROM monthly_roster r
        WHERE r.user_id = emp_id AND r.branch_id = p_branch_id AND r.work_date = p_start_date
        LIMIT 1;
      IF from_shift_id IS NULL THEN
        SELECT p.default_shift_id INTO from_shift_id
          FROM profiles p WHERE p.id = emp_id LIMIT 1;
      END IF;
      IF from_shift_id IS NULL THEN
        from_shift_id := to_shift_id;
      END IF;
      DELETE FROM monthly_roster
        WHERE user_id = emp_id AND work_date = p_start_date;
      INSERT INTO monthly_roster (branch_id, shift_id, user_id, work_date)
        VALUES (p_branch_id, to_shift_id, emp_id, p_start_date);
      applied_count := applied_count + 1;
      IF from_shift_id IS DISTINCT FROM to_shift_id THEN
        INSERT INTO shift_swaps (
          user_id, branch_id, from_shift_id, to_shift_id,
          start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
        ) VALUES (
          emp_id, p_branch_id, from_shift_id, to_shift_id,
          p_start_date, p_start_date, p_reason, 'approved', caller_uid, now(),
          NULL
        );
      END IF;
    END IF;
    IF array_length(skipped_arr, 1) > 0 THEN
      out_skipped := out_skipped || jsonb_build_object(emp_id::text,
        (SELECT jsonb_agg(to_char(d, 'YYYY-MM-DD')) FROM unnest(skipped_arr) AS d));
    END IF;
  END LOOP;
  RETURN jsonb_build_object(
    'applied', applied_count,
    'skipped_per_user', out_skipped
  );
END;
$$;
CREATE OR REPLACE FUNCTION apply_bulk_assignment(
  p_employee_ids UUID[],
  p_start_date DATE,
  p_end_date DATE,
  p_to_branch_id UUID,
  p_to_shift_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  may_run BOOLEAN;
  is_head BOOLEAN;
  emp_id UUID;
  from_branch_id UUID;
  from_shift_id UUID;
  skip_set DATE[];
  skipped_arr DATE[];
  applied_count INT := 0;
  out_skipped JSONB := '{}'::JSONB;
  out_applied INT := 0;
  has_scheduled BOOLEAN;
BEGIN
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head'::app_role);
  IF NOT may_run AND NOT is_head THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can run bulk assignment';
  END IF;
  IF is_head AND NOT may_run THEN
    IF p_to_branch_id IS NULL OR p_to_branch_id != my_branch_id() THEN
      RAISE EXCEPTION 'Instructor head can only assign to their own branch';
    END IF;
  END IF;
  FOR emp_id IN SELECT unnest(p_employee_ids)
  LOOP
    skipped_arr := ARRAY[]::DATE[];
    SELECT EXISTS (
      SELECT 1 FROM shift_swaps s
      WHERE s.user_id = emp_id AND s.status = 'approved' AND s.start_date >= current_date
      UNION ALL
      SELECT 1 FROM cross_branch_transfers t
      WHERE t.user_id = emp_id AND t.status = 'approved' AND t.start_date >= current_date
    ) INTO has_scheduled;
    IF has_scheduled THEN
      skipped_arr := array_append(skipped_arr, p_start_date);
    ELSE
      SELECT ARRAY_AGG(h.holiday_date)
        INTO skip_set
        FROM holidays h
        WHERE h.user_id = emp_id
          AND h.holiday_date = p_start_date
          AND h.status IN ('approved','pending');
      IF skip_set IS NULL THEN skip_set := ARRAY[]::DATE[]; END IF;
      IF p_start_date = ANY(skip_set) THEN
        skipped_arr := array_append(skipped_arr, p_start_date);
      ELSE
        SELECT r.branch_id, r.shift_id INTO from_branch_id, from_shift_id
          FROM monthly_roster r
          WHERE r.user_id = emp_id AND r.work_date = p_start_date
          LIMIT 1;
        IF from_branch_id IS NULL OR from_shift_id IS NULL THEN
          SELECT p.default_branch_id, p.default_shift_id INTO from_branch_id, from_shift_id
            FROM profiles p WHERE p.id = emp_id LIMIT 1;
        END IF;
        IF from_branch_id IS NULL THEN from_branch_id := p_to_branch_id; END IF;
        IF from_shift_id IS NULL THEN from_shift_id := p_to_shift_id; END IF;
        DELETE FROM monthly_roster
          WHERE user_id = emp_id AND work_date = p_start_date;
        INSERT INTO monthly_roster (branch_id, shift_id, user_id, work_date)
          VALUES (p_to_branch_id, p_to_shift_id, emp_id, p_start_date);
        applied_count := applied_count + 1;
        IF from_branch_id = p_to_branch_id THEN
          IF from_shift_id IS DISTINCT FROM p_to_shift_id THEN
            INSERT INTO shift_swaps (
              user_id, branch_id, from_shift_id, to_shift_id,
              start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
            ) VALUES (
              emp_id, from_branch_id, from_shift_id, p_to_shift_id,
              p_start_date, p_start_date, p_reason, 'approved', uid, now(), NULL
            );
          END IF;
        ELSE
          INSERT INTO cross_branch_transfers (
            user_id, from_branch_id, to_branch_id, from_shift_id, to_shift_id,
            start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
          ) VALUES (
            emp_id, from_branch_id, p_to_branch_id, from_shift_id, p_to_shift_id,
            p_start_date, p_start_date, p_reason, 'approved', uid, now(), NULL
          );
        END IF;
      END IF;
    END IF;
    IF array_length(skipped_arr, 1) > 0 THEN
      out_skipped := out_skipped || jsonb_build_object(emp_id::text,
        (SELECT jsonb_agg(to_char(d, 'YYYY-MM-DD')) FROM unnest(skipped_arr) AS d));
    END IF;
  END LOOP;
  out_applied := applied_count;
  RETURN jsonb_build_object(
    'applied', out_applied,
    'skipped_per_user', out_skipped
  );
END;
$$;
CREATE OR REPLACE FUNCTION apply_paired_swap(
  p_branch_id UUID,
  p_start_date DATE,
  p_end_date DATE,
  p_assignments JSONB,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_uid UUID := auth.uid();
  may_run BOOLEAN;
  is_head BOOLEAN;
  rec JSONB;
  emp_id UUID;
  to_shift_id UUID;
  from_shift_id UUID;
  skip_set DATE[];
  skipped_arr DATE[];
  applied_count INT := 0;
  out_skipped JSONB := '{}'::JSONB;
  i INT;
  has_scheduled BOOLEAN;
BEGIN
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = caller_uid AND role IN ('admin'::app_role,'manager'::app_role));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = caller_uid AND role = 'instructor_head'::app_role);
  IF NOT may_run AND NOT is_head THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can run paired swap';
  END IF;
  IF is_head AND NOT may_run THEN
    IF p_branch_id IS NULL OR p_branch_id != my_branch_id() THEN
      RAISE EXCEPTION 'Instructor head can only assign to their own branch';
    END IF;
  END IF;
  WITH elem AS (
    SELECT (e->>'user_id')::UUID AS elem_uid, (e->>'to_shift_id')::UUID AS elem_sid, ord
    FROM jsonb_array_elements(p_assignments) WITH ORDINALITY AS t(e, ord)
    WHERE (e->>'user_id')::UUID IS NOT NULL AND (e->>'to_shift_id')::UUID IS NOT NULL
  ),
  deduped AS (
    SELECT elem_uid, elem_sid, ROW_NUMBER() OVER (PARTITION BY elem_uid ORDER BY ord DESC) AS rn FROM elem
  )
  SELECT jsonb_agg(jsonb_build_object('user_id', d.elem_uid, 'to_shift_id', d.elem_sid))
  INTO p_assignments
  FROM (SELECT elem_uid, elem_sid FROM deduped WHERE rn = 1) d;
  IF p_assignments IS NULL THEN p_assignments := '[]'::JSONB; END IF;
  FOR i IN 0 .. jsonb_array_length(p_assignments) - 1 LOOP
    rec := p_assignments->i;
    emp_id := (rec->>'user_id')::UUID;
    to_shift_id := (rec->>'to_shift_id')::UUID;
    IF emp_id IS NULL OR to_shift_id IS NULL THEN CONTINUE; END IF;
    skipped_arr := ARRAY[]::DATE[];
    SELECT EXISTS (
      SELECT 1 FROM shift_swaps s
      WHERE s.user_id = emp_id AND s.status = 'approved' AND s.start_date >= current_date
      UNION ALL
      SELECT 1 FROM cross_branch_transfers t
      WHERE t.user_id = emp_id AND t.status = 'approved' AND t.start_date >= current_date
    ) INTO has_scheduled;
    IF has_scheduled THEN
      skipped_arr := array_append(skipped_arr, p_start_date);
    ELSE
      SELECT ARRAY_AGG(h.holiday_date)
        INTO skip_set
        FROM holidays h
        WHERE h.user_id = emp_id
          AND h.holiday_date = p_start_date
          AND h.status IN ('approved','pending');
      IF skip_set IS NULL THEN skip_set := ARRAY[]::DATE[]; END IF;
      IF p_start_date = ANY(skip_set) THEN
        skipped_arr := array_append(skipped_arr, p_start_date);
      ELSE
        SELECT r.shift_id INTO from_shift_id
          FROM monthly_roster r
          WHERE r.user_id = emp_id AND r.branch_id = p_branch_id AND r.work_date = p_start_date
          LIMIT 1;
        IF from_shift_id IS NULL THEN
          SELECT p.default_shift_id INTO from_shift_id
            FROM profiles p WHERE p.id = emp_id LIMIT 1;
        END IF;
        IF from_shift_id IS NULL THEN
          from_shift_id := to_shift_id;
        END IF;
        DELETE FROM monthly_roster
          WHERE user_id = emp_id AND work_date = p_start_date;
        INSERT INTO monthly_roster (branch_id, shift_id, user_id, work_date)
          VALUES (p_branch_id, to_shift_id, emp_id, p_start_date);
        applied_count := applied_count + 1;
        IF from_shift_id IS DISTINCT FROM to_shift_id THEN
          INSERT INTO shift_swaps (
            user_id, branch_id, from_shift_id, to_shift_id,
            start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
          ) VALUES (
            emp_id, p_branch_id, from_shift_id, to_shift_id,
            p_start_date, p_start_date, p_reason, 'approved', caller_uid, now(),
            NULL
          );
        END IF;
      END IF;
    END IF;
    IF array_length(skipped_arr, 1) > 0 THEN
      out_skipped := out_skipped || jsonb_build_object(emp_id::text,
        (SELECT jsonb_agg(to_char(d, 'YYYY-MM-DD')) FROM unnest(skipped_arr) AS d));
    END IF;
  END LOOP;
  RETURN jsonb_build_object(
    'applied', applied_count,
    'skipped_per_user', out_skipped
  );
END;
$$;
DROP POLICY IF EXISTS group_links_select ON group_links;
CREATE POLICY group_links_select ON group_links FOR SELECT TO authenticated USING (
  created_by = auth.uid()
  OR is_admin()
  OR is_manager()
  OR (is_instructor_head() AND (branch_id IS NULL OR branch_id = my_branch_id()
      OR EXISTS (SELECT 1 FROM group_link_branches glb WHERE glb.group_link_id = group_links.id AND glb.branch_id = my_branch_id())))
  OR (
    (branch_id IS NULL OR branch_id = my_branch_id()
     OR EXISTS (SELECT 1 FROM group_link_branches glb WHERE glb.group_link_id = group_links.id AND glb.branch_id = my_branch_id()))
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles))
  )
);
DROP POLICY IF EXISTS group_links_select ON group_links;
CREATE POLICY group_links_select ON group_links FOR SELECT TO authenticated USING (
  created_by = auth.uid()
  OR is_admin()
  OR is_manager()
  OR is_instructor_head()
  OR (
    (branch_id IS NULL OR branch_id = my_branch_id()
     OR EXISTS (SELECT 1 FROM group_link_branches glb WHERE glb.group_link_id = group_links.id AND glb.branch_id = my_branch_id()))
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles))
  )
);
DROP POLICY IF EXISTS group_links_update ON group_links;
CREATE POLICY group_links_update ON group_links FOR UPDATE TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head()
);
DROP POLICY IF EXISTS group_links_delete ON group_links;
CREATE POLICY group_links_delete ON group_links FOR DELETE TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head()
);
DROP POLICY IF EXISTS group_link_branches_select ON group_link_branches;
CREATE POLICY group_link_branches_select ON group_link_branches FOR SELECT TO authenticated USING (
  is_admin() OR is_instructor_head()
  OR EXISTS (SELECT 1 FROM group_links g WHERE g.id = group_link_id AND (
    g.branch_id IS NULL OR g.branch_id = my_branch_id()
    OR EXISTS (SELECT 1 FROM group_link_branches glb WHERE glb.group_link_id = g.id AND glb.branch_id = my_branch_id())
  ))
);
DROP POLICY IF EXISTS group_link_branches_insert ON group_link_branches;
CREATE POLICY group_link_branches_insert ON group_link_branches FOR INSERT TO authenticated WITH CHECK (
  is_admin() OR (is_instructor_head() AND branch_id IS NOT NULL)
);
DROP POLICY IF EXISTS group_link_branches_delete ON group_link_branches;
CREATE POLICY group_link_branches_delete ON group_link_branches FOR DELETE TO authenticated USING (
  is_admin() OR is_instructor_head()
);
DROP POLICY IF EXISTS group_link_websites_select ON group_link_websites;
CREATE POLICY group_link_websites_select ON group_link_websites FOR SELECT TO authenticated USING (
  is_admin() OR is_instructor_head()
  OR EXISTS (SELECT 1 FROM group_links g WHERE g.id = group_link_id AND (g.branch_id IS NULL OR g.branch_id = my_branch_id()))
);
DROP POLICY IF EXISTS group_link_websites_insert ON group_link_websites;
CREATE POLICY group_link_websites_insert ON group_link_websites FOR INSERT TO authenticated WITH CHECK (
  is_admin() OR is_instructor_head()
);
DROP POLICY IF EXISTS group_link_websites_delete ON group_link_websites;
CREATE POLICY group_link_websites_delete ON group_link_websites FOR DELETE TO authenticated USING (
  is_admin() OR is_instructor_head()
);
DROP POLICY IF EXISTS shift_swaps_select ON shift_swaps;
CREATE POLICY shift_swaps_select ON shift_swaps FOR SELECT TO authenticated USING (
  is_admin_or_manager()
  OR (is_instructor_head() AND branch_id = my_branch_id())
  OR user_id = auth.uid()
  OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
DROP POLICY IF EXISTS transfers_select ON cross_branch_transfers;
CREATE POLICY transfers_select ON cross_branch_transfers FOR SELECT TO authenticated USING (
  is_admin_or_manager()
  OR (is_instructor_head() AND (from_branch_id = my_branch_id() OR to_branch_id = my_branch_id()))
  OR user_id = auth.uid()
  OR from_branch_id IN (SELECT user_branch_ids(auth.uid()))
  OR to_branch_id IN (SELECT user_branch_ids(auth.uid()))
);
CREATE OR REPLACE FUNCTION check_no_scheduled_shift_change_on_profile_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.default_shift_id IS DISTINCT FROM OLD.default_shift_id THEN
    IF EXISTS (
      SELECT 1 FROM shift_swaps s
      WHERE s.user_id = NEW.id AND s.status = 'approved' AND s.start_date >= current_date
      LIMIT 1
    ) THEN
      RAISE EXCEPTION 'ไม่สามารถเปลี่ยนกะได้ เนื่องจากมีรายการตั้งเวลาย้ายกะที่ยังมีผล — กรุณายกเลิกหรือรอให้ครบก่อน'
        USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (
      SELECT 1 FROM cross_branch_transfers c
      WHERE c.user_id = NEW.id AND c.status = 'approved' AND c.start_date >= current_date
      LIMIT 1
    ) THEN
      RAISE EXCEPTION 'ไม่สามารถเปลี่ยนกะได้ เนื่องจากมีรายการตั้งเวลาย้ายกะข้ามแผนกที่ยังมีผล — กรุณายกเลิกหรือรอให้ครบก่อน'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS block_change_shift_when_scheduled ON profiles;
CREATE TRIGGER block_change_shift_when_scheduled
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE PROCEDURE check_no_scheduled_shift_change_on_profile_update();
DROP POLICY IF EXISTS shift_swaps_select ON shift_swaps;
CREATE POLICY shift_swaps_select ON shift_swaps FOR SELECT TO authenticated USING (
  is_admin_or_manager()
  OR (is_instructor_head() AND (
    branch_id = my_branch_id()
    OR (branch_id IS NULL AND EXISTS (SELECT 1 FROM profiles p WHERE p.id = shift_swaps.user_id AND p.default_branch_id = my_branch_id()))
  ))
  OR user_id = auth.uid()
  OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
CREATE OR REPLACE FUNCTION user_branch_ids(uid UUID)
RETURNS SETOF UUID AS $$
  SELECT DISTINCT b.id FROM branches b
  JOIN profiles p ON p.id = uid
  WHERE p.role IN ('admin'::app_role, 'manager'::app_role, 'instructor_head'::app_role)
  UNION
  SELECT p.default_branch_id FROM profiles p WHERE p.id = uid AND p.default_branch_id IS NOT NULL AND p.role NOT IN ('admin'::app_role, 'manager'::app_role, 'instructor_head'::app_role)
  UNION
  SELECT cbt.to_branch_id FROM cross_branch_transfers cbt
  WHERE cbt.user_id = uid AND cbt.status = 'approved'
    AND current_date BETWEEN cbt.start_date AND cbt.end_date
  UNION
  SELECT cbt.from_branch_id FROM cross_branch_transfers cbt
  WHERE cbt.user_id = uid AND cbt.status = 'approved'
    AND (current_date < cbt.start_date OR current_date > cbt.end_date);
$$ LANGUAGE sql SECURITY DEFINER STABLE;
CREATE OR REPLACE FUNCTION is_admin_or_manager_or_head()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin'::app_role, 'manager'::app_role, 'instructor_head'::app_role));
$$ LANGUAGE sql SECURITY DEFINER STABLE;
DROP POLICY IF EXISTS profiles_update_branch_head ON profiles;
CREATE POLICY profiles_update_branch_head ON profiles FOR UPDATE TO authenticated USING (
  is_admin() OR (is_instructor_head() AND default_branch_id = my_branch_id() AND role IN ('instructor'::app_role, 'staff'::app_role))
);
DROP POLICY IF EXISTS branches_all ON branches;
CREATE POLICY branches_all ON branches FOR ALL TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS shifts_all ON shifts;
CREATE POLICY shifts_all ON shifts FOR ALL TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS break_rules_all ON break_rules;
CREATE POLICY break_rules_all ON break_rules FOR ALL TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS holiday_quotas_all ON holiday_quotas;
CREATE POLICY holiday_quotas_all ON holiday_quotas FOR ALL TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS holiday_quota_tiers_all ON holiday_quota_tiers;
CREATE POLICY holiday_quota_tiers_all ON holiday_quota_tiers FOR ALL TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS roster_status_all ON monthly_roster_status;
CREATE POLICY roster_status_all ON monthly_roster_status FOR ALL TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS monthly_roster_insert ON monthly_roster;
CREATE POLICY monthly_roster_insert ON monthly_roster FOR INSERT TO authenticated WITH CHECK (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS monthly_roster_update ON monthly_roster;
CREATE POLICY monthly_roster_update ON monthly_roster FOR UPDATE TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS monthly_roster_delete ON monthly_roster;
CREATE POLICY monthly_roster_delete ON monthly_roster FOR DELETE TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS duty_roles_all ON duty_roles;
CREATE POLICY duty_roles_all ON duty_roles FOR ALL TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS duty_assignments_all ON duty_assignments;
CREATE POLICY duty_assignments_all ON duty_assignments FOR ALL TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS password_vault_all ON password_vault;
CREATE POLICY password_vault_all ON password_vault FOR ALL TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS holiday_booking_config_all ON holiday_booking_config;
CREATE POLICY holiday_booking_config_all ON holiday_booking_config FOR ALL TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS leave_types_all ON leave_types;
CREATE POLICY leave_types_all ON leave_types FOR ALL TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS websites_select ON websites;
CREATE POLICY websites_select ON websites FOR SELECT TO authenticated USING (
  is_admin_or_manager_or_head() OR id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid())
);
DROP POLICY IF EXISTS websites_insert ON websites;
CREATE POLICY websites_insert ON websites FOR INSERT TO authenticated WITH CHECK (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS websites_update ON websites;
CREATE POLICY websites_update ON websites FOR UPDATE TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS websites_delete ON websites;
CREATE POLICY websites_delete ON websites FOR DELETE TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS website_assignments_select ON website_assignments;
CREATE POLICY website_assignments_select ON website_assignments FOR SELECT TO authenticated USING (is_admin_or_manager_or_head() OR user_id = auth.uid());
DROP POLICY IF EXISTS website_assignments_insert ON website_assignments;
CREATE POLICY website_assignments_insert ON website_assignments FOR INSERT TO authenticated WITH CHECK (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS website_assignments_update ON website_assignments;
CREATE POLICY website_assignments_update ON website_assignments FOR UPDATE TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS website_assignments_delete ON website_assignments;
CREATE POLICY website_assignments_delete ON website_assignments FOR DELETE TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS work_logs_update ON work_logs;
CREATE POLICY work_logs_update ON work_logs FOR UPDATE TO authenticated USING (is_admin_or_manager_or_head() OR user_id = auth.uid());
DROP POLICY IF EXISTS break_logs_update ON break_logs;
CREATE POLICY break_logs_update ON break_logs FOR UPDATE TO authenticated USING (user_id = auth.uid() OR is_admin_or_manager_or_head());
DROP POLICY IF EXISTS shift_swaps_update ON shift_swaps;
CREATE POLICY shift_swaps_update ON shift_swaps FOR UPDATE TO authenticated USING (is_admin_or_manager_or_head() OR user_id = auth.uid());
DROP POLICY IF EXISTS transfers_update ON cross_branch_transfers;
CREATE POLICY transfers_update ON cross_branch_transfers FOR UPDATE TO authenticated USING (is_admin_or_manager_or_head() OR user_id = auth.uid());
DROP POLICY IF EXISTS shift_swaps_select ON shift_swaps;
CREATE POLICY shift_swaps_select ON shift_swaps FOR SELECT TO authenticated USING (
  is_admin_or_manager_or_head()
  OR user_id = auth.uid()
  OR branch_id IN (SELECT user_branch_ids(auth.uid()))
  OR (branch_id IS NULL AND is_instructor_head() AND EXISTS (SELECT 1 FROM profiles p WHERE p.id = shift_swaps.user_id AND p.default_branch_id = my_branch_id()))
);
DROP POLICY IF EXISTS transfers_select ON cross_branch_transfers;
CREATE POLICY transfers_select ON cross_branch_transfers FOR SELECT TO authenticated USING (
  is_admin_or_manager_or_head()
  OR user_id = auth.uid()
  OR from_branch_id IN (SELECT user_branch_ids(auth.uid()))
  OR to_branch_id IN (SELECT user_branch_ids(auth.uid()))
);
DROP POLICY IF EXISTS schedule_cards_select ON schedule_cards;
CREATE POLICY schedule_cards_select ON schedule_cards FOR SELECT TO authenticated USING (
  is_admin_or_manager_or_head()
  OR (
    (branch_id IS NULL OR branch_id IN (SELECT user_branch_ids(auth.uid())))
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles))
    AND (website_id IS NULL OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid()))
  )
);
DROP POLICY IF EXISTS file_vault_select ON file_vault;
CREATE POLICY file_vault_select ON file_vault FOR SELECT TO authenticated USING (
  is_admin_or_manager_or_head()
  OR (branch_id IS NULL AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles)))
  OR (branch_id IN (SELECT user_branch_ids(auth.uid())) AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles)))
);
DROP POLICY IF EXISTS file_vault_insert ON file_vault;
CREATE POLICY file_vault_insert ON file_vault FOR INSERT TO authenticated WITH CHECK (
  is_admin_or_manager_or_head() OR (is_instructor_head() AND (branch_id = my_branch_id() OR branch_id IS NULL))
);
DROP POLICY IF EXISTS file_vault_update ON file_vault;
CREATE POLICY file_vault_update ON file_vault FOR UPDATE TO authenticated USING (
  is_admin_or_manager_or_head() OR (is_instructor_head() AND (branch_id = my_branch_id() OR branch_id IS NULL))
);
DROP POLICY IF EXISTS file_vault_delete ON file_vault;
CREATE POLICY file_vault_delete ON file_vault FOR DELETE TO authenticated USING (
  is_admin_or_manager_or_head() OR (is_instructor_head() AND (branch_id = my_branch_id() OR branch_id IS NULL))
);
DROP POLICY IF EXISTS audit_logs_select ON audit_logs;
CREATE POLICY audit_logs_select ON audit_logs FOR SELECT TO authenticated USING (
  is_admin_or_manager_or_head() OR (actor_id = auth.uid()) OR is_instructor_or_admin()
);

ALTER TABLE group_links ADD COLUMN IF NOT EXISTS website_id UUID REFERENCES websites(id) ON DELETE SET NULL;
ALTER TABLE group_links ADD COLUMN IF NOT EXISTS visible_roles TEXT[] DEFAULT '{}';
ALTER TABLE group_links ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES profiles(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_group_links_website ON group_links(website_id);
CREATE INDEX IF NOT EXISTS idx_group_links_created_by ON group_links(created_by);
CREATE TABLE IF NOT EXISTS group_link_websites (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  group_link_id UUID NOT NULL REFERENCES group_links(id) ON DELETE CASCADE,
  website_id UUID NOT NULL REFERENCES websites(id) ON DELETE CASCADE,
  UNIQUE(group_link_id, website_id)
);
CREATE INDEX IF NOT EXISTS idx_group_link_websites_link ON group_link_websites(group_link_id);
CREATE INDEX IF NOT EXISTS idx_group_link_websites_website ON group_link_websites(website_id);
ALTER TABLE group_link_websites ENABLE ROW LEVEL SECURITY;
CREATE TABLE IF NOT EXISTS group_link_branches (
  group_link_id UUID NOT NULL REFERENCES group_links(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  PRIMARY KEY (group_link_id, branch_id)
);
CREATE INDEX IF NOT EXISTS idx_group_link_branches_link ON group_link_branches(group_link_id);
CREATE INDEX IF NOT EXISTS idx_group_link_branches_branch ON group_link_branches(branch_id);
ALTER TABLE group_link_branches ENABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION is_instructor_head()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'instructor_head'::app_role);
$$ LANGUAGE sql SECURITY DEFINER STABLE;
CREATE OR REPLACE FUNCTION is_admin_or_manager_or_head()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin'::app_role, 'manager'::app_role, 'instructor_head'::app_role));
$$ LANGUAGE sql SECURITY DEFINER STABLE;
CREATE OR REPLACE FUNCTION can_see_group_link(p_group_link_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM group_links g WHERE g.id = p_group_link_id
    AND (
      g.created_by = auth.uid()
      OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin'::app_role, 'manager'::app_role, 'instructor_head'::app_role))
      OR (
        (g.branch_id IS NULL OR g.branch_id = my_branch_id()
         OR EXISTS (SELECT 1 FROM group_link_branches glb WHERE glb.group_link_id = g.id AND glb.branch_id = my_branch_id()))
        AND (g.visible_roles IS NULL OR array_length(g.visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(g.visible_roles))
      )
  )
  );
$$;
DROP POLICY IF EXISTS group_links_select ON group_links;
CREATE POLICY group_links_select ON group_links FOR SELECT TO authenticated USING (
  created_by = auth.uid()
  OR is_admin()
  OR is_manager()
  OR is_instructor_head()
  OR can_see_group_link(id)
);
DROP POLICY IF EXISTS group_links_insert ON group_links;
CREATE POLICY group_links_insert ON group_links FOR INSERT TO authenticated WITH CHECK (
  is_admin() OR is_manager() OR (is_instructor_head() AND (branch_id = my_branch_id() OR branch_id IS NULL))
);
DROP POLICY IF EXISTS group_links_update ON group_links;
CREATE POLICY group_links_update ON group_links FOR UPDATE TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head()
);
DROP POLICY IF EXISTS group_links_delete ON group_links;
CREATE POLICY group_links_delete ON group_links FOR DELETE TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head()
);
DROP POLICY IF EXISTS group_link_branches_select ON group_link_branches;
CREATE POLICY group_link_branches_select ON group_link_branches FOR SELECT TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head()
  OR can_see_group_link(group_link_id)
);
DROP POLICY IF EXISTS group_link_branches_insert ON group_link_branches;
CREATE POLICY group_link_branches_insert ON group_link_branches FOR INSERT TO authenticated WITH CHECK (
  is_admin() OR is_manager() OR (is_instructor_head() AND branch_id IS NOT NULL)
);
DROP POLICY IF EXISTS group_link_branches_delete ON group_link_branches;
CREATE POLICY group_link_branches_delete ON group_link_branches FOR DELETE TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head()
);
DROP POLICY IF EXISTS group_link_websites_select ON group_link_websites;
CREATE POLICY group_link_websites_select ON group_link_websites FOR SELECT TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head()
  OR can_see_group_link(group_link_id)
);
DROP POLICY IF EXISTS group_link_websites_insert ON group_link_websites;
CREATE POLICY group_link_websites_insert ON group_link_websites FOR INSERT TO authenticated WITH CHECK (
  is_admin() OR is_manager() OR is_instructor_head()
);
DROP POLICY IF EXISTS group_link_websites_delete ON group_link_websites;
CREATE POLICY group_link_websites_delete ON group_link_websites FOR DELETE TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head()
);

DROP POLICY IF EXISTS password_vault_select ON password_vault;
DROP POLICY IF EXISTS password_vault_all ON password_vault;
DROP POLICY IF EXISTS password_vault_insert ON password_vault;
DROP POLICY IF EXISTS password_vault_update ON password_vault;
DROP POLICY IF EXISTS password_vault_delete ON password_vault;
DROP TRIGGER IF EXISTS password_vault_updated_at ON password_vault;
DROP TABLE IF EXISTS password_vault CASCADE;

CREATE OR REPLACE FUNCTION apply_scheduled_shift_changes_for_date(p_date DATE)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  uid UUID;
  to_br UUID;
  to_sh UUID;
  updated_count INT := 0;
BEGIN
  IF p_date IS NULL THEN RETURN 0; END IF;
  FOR r IN (
    SELECT user_id, to_branch_id, to_shift_id
    FROM (
      SELECT user_id, to_branch_id, to_shift_id,
             ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY start_date DESC) AS rn
      FROM (
        SELECT user_id, branch_id AS to_branch_id, to_shift_id, start_date
        FROM shift_swaps
        WHERE status = 'approved' AND start_date <= p_date AND end_date >= p_date
        UNION ALL
        SELECT user_id, to_branch_id, to_shift_id, start_date
        FROM cross_branch_transfers
        WHERE status = 'approved' AND start_date <= p_date AND end_date >= p_date
      ) combined
    ) sub
    WHERE rn = 1
  ) LOOP
    uid := r.user_id;
    to_br := r.to_branch_id;
    to_sh := r.to_shift_id;
    IF uid IS NOT NULL AND to_sh IS NOT NULL THEN
      UPDATE profiles
      SET default_shift_id = to_sh,
          default_branch_id = COALESCE(to_br, default_branch_id),
          updated_at = now()
      WHERE id = uid
        AND (default_shift_id IS DISTINCT FROM to_sh OR default_branch_id IS DISTINCT FROM COALESCE(to_br, default_branch_id));
      IF FOUND THEN
        updated_count := updated_count + 1;
      END IF;
    END IF;
  END LOOP;
  RETURN updated_count;
END;
$$;
GRANT EXECUTE ON FUNCTION apply_scheduled_shift_changes_for_date(DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION apply_scheduled_shift_changes_for_date(DATE) TO service_role;

DROP POLICY IF EXISTS group_links_insert ON group_links;
CREATE POLICY group_links_insert ON group_links FOR INSERT TO authenticated WITH CHECK (
  is_admin() OR is_manager() OR is_instructor_head()
);

CREATE OR REPLACE FUNCTION get_meal_on_duty_user_ids(p_work_date DATE)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_branch_id UUID;
  v_shift_id UUID;
  v_website_id UUID;
  v_holiday_date DATE := p_work_date;
  v_user_group TEXT;
  v_scope_by_website BOOLEAN := true;
  v_result JSONB;
BEGIN
  SELECT p.default_branch_id, p.default_shift_id INTO v_branch_id, v_shift_id FROM profiles p WHERE p.id = v_uid LIMIT 1;
  SELECT wa.website_id INTO v_website_id FROM website_assignments wa WHERE wa.user_id = v_uid AND wa.is_primary = true LIMIT 1;
  IF v_branch_id IS NULL OR v_shift_id IS NULL OR v_website_id IS NULL THEN
    RETURN '[]'::JSONB;
  END IF;
  v_user_group := my_user_group();
  SELECT COALESCE(ms.scope_meal_quota_by_website, true) INTO v_scope_by_website
  FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;
  IF v_scope_by_website THEN
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      INNER JOIN website_assignments wa
        ON wa.user_id = p.id
       AND wa.website_id = v_website_id
       AND wa.is_primary = true
      WHERE p.default_branch_id = v_branch_id
        AND p.default_shift_id = v_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status IN ('approved', 'pending')
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    )
    SELECT COALESCE(jsonb_agg(id ORDER BY id), '[]'::JSONB) INTO v_result FROM eligible;
  ELSE
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      WHERE p.default_branch_id = v_branch_id
        AND p.default_shift_id = v_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status IN ('approved', 'pending')
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    )
    SELECT COALESCE(jsonb_agg(id ORDER BY id), '[]'::JSONB) INTO v_result FROM eligible;
  END IF;
  RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;
CREATE OR REPLACE FUNCTION get_meal_capacity_break_logs(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_work_date DATE,
  p_round_key TEXT,
  p_slot_start_ts TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_holiday_date DATE;
  v_on_duty_count INT;
  v_max_concurrent INT;
  v_current_booked INT;
  v_user_group TEXT;
  v_scope_by_website BOOLEAN := true;
  v_booked_user_ids JSONB;
BEGIN
  v_holiday_date := DATE(p_slot_start_ts);
  v_user_group := my_user_group();
  SELECT COALESCE(ms.scope_meal_quota_by_website, true) INTO v_scope_by_website
  FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;
  IF v_scope_by_website THEN
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      INNER JOIN website_assignments wa
        ON wa.user_id = p.id
       AND wa.website_id = p_website_id
       AND wa.is_primary = true
      WHERE p.default_branch_id = p_branch_id
        AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status IN ('approved', 'pending')
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id
      AND shift_id = p_shift_id
      AND website_id = p_website_id
      AND break_date = p_work_date
      AND round_key = p_round_key
      AND started_at = p_slot_start_ts
      AND break_type = 'MEAL'
      AND status = 'active'
      AND (user_group = v_user_group OR v_user_group IS NULL);
    SELECT COALESCE(jsonb_agg(bl.user_id ORDER BY bl.user_id), '[]'::JSONB) INTO v_booked_user_ids
    FROM break_logs bl
    WHERE bl.branch_id = p_branch_id
      AND bl.shift_id = p_shift_id
      AND bl.website_id = p_website_id
      AND bl.break_date = p_work_date
      AND bl.round_key = p_round_key
      AND bl.started_at = p_slot_start_ts
      AND bl.break_type = 'MEAL'
      AND bl.status = 'active'
      AND (bl.user_group = v_user_group OR v_user_group IS NULL);
  ELSE
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      WHERE p.default_branch_id = p_branch_id
        AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status IN ('approved', 'pending')
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
          OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role)
          OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role)
        )
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id
      AND shift_id = p_shift_id
      AND break_date = p_work_date
      AND round_key = p_round_key
      AND started_at = p_slot_start_ts
      AND break_type = 'MEAL'
      AND status = 'active'
      AND (user_group = v_user_group OR v_user_group IS NULL);
    SELECT COALESCE(jsonb_agg(bl.user_id ORDER BY bl.user_id), '[]'::JSONB) INTO v_booked_user_ids
    FROM break_logs bl
    WHERE bl.branch_id = p_branch_id
      AND bl.shift_id = p_shift_id
      AND bl.break_date = p_work_date
      AND bl.round_key = p_round_key
      AND bl.started_at = p_slot_start_ts
      AND bl.break_type = 'MEAL'
      AND bl.status = 'active'
      AND (bl.user_group = v_user_group OR v_user_group IS NULL);
  END IF;
  v_max_concurrent := get_meal_quota_for_group(p_branch_id, p_shift_id, p_website_id, v_user_group, v_on_duty_count);
  RETURN jsonb_build_object(
    'on_duty_count', v_on_duty_count,
    'max_concurrent', v_max_concurrent,
    'current_booked', v_current_booked,
    'is_full', (v_current_booked >= v_max_concurrent),
    'booked_user_ids', COALESCE(v_booked_user_ids, '[]'::JSONB)
  );
END;
$$;

CREATE OR REPLACE FUNCTION delete_audit_logs_older_than_days(p_days INT DEFAULT 7)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cutoff TIMESTAMPTZ;
  v_deleted BIGINT;
BEGIN
  IF p_days IS NULL OR p_days < 1 THEN
    RAISE EXCEPTION 'p_days must be >= 1';
  END IF;
  v_cutoff := now() - (p_days || ' days')::INTERVAL;
  WITH deleted AS (
    DELETE FROM audit_logs
    WHERE created_at < v_cutoff
    RETURNING id
  )
  SELECT COUNT(*)::BIGINT INTO v_deleted FROM deleted;
  RETURN v_deleted;
END;
$$;

CREATE OR REPLACE FUNCTION get_meal_quota_for_group(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_user_group TEXT,
  p_on_duty_count INT
)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    (
      SELECT MIN(mqr.max_concurrent)
      FROM meal_quota_rules mqr
      WHERE
        (mqr.branch_id = p_branch_id OR mqr.branch_id IS NULL)
        AND (mqr.shift_id = p_shift_id OR mqr.shift_id IS NULL)
        AND (mqr.website_id = p_website_id OR mqr.website_id IS NULL)
        AND (mqr.user_group = p_user_group OR mqr.user_group IS NULL)
        AND mqr.on_duty_threshold >= p_on_duty_count
    ),
    1
  );
$$;
CREATE OR REPLACE FUNCTION get_meal_capacity_break_logs(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_work_date DATE,
  p_round_key TEXT,
  p_slot_start_ts TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_holiday_date DATE;
  v_on_duty_count INT;
  v_max_concurrent INT;
  v_current_booked INT;
  v_user_group TEXT;
  v_scope_by_website BOOLEAN := true;
  v_booked_user_ids JSONB;
BEGIN
  v_holiday_date := DATE(p_slot_start_ts);
  v_user_group := my_user_group();
  SELECT COALESCE(ms.scope_meal_quota_by_website, true) INTO v_scope_by_website
  FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;
  IF v_scope_by_website THEN
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      INNER JOIN website_assignments wa ON wa.user_id = p.id AND wa.website_id = p_website_id AND wa.is_primary = true
      WHERE p.default_branch_id = p_branch_id AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (SELECT 1 FROM holidays h WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status IN ('approved', 'pending'))
        AND (v_user_group IS NULL OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role)) OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role) OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role))
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id AND shift_id = p_shift_id AND website_id = p_website_id
      AND break_date = p_work_date AND round_key = p_round_key AND started_at = p_slot_start_ts
      AND break_type = 'MEAL' AND status = 'active' AND (user_group = v_user_group OR v_user_group IS NULL);
    SELECT COALESCE(jsonb_agg(bl.user_id ORDER BY bl.user_id), '[]'::JSONB) INTO v_booked_user_ids
    FROM break_logs bl
    WHERE bl.branch_id = p_branch_id AND bl.shift_id = p_shift_id AND bl.website_id = p_website_id
      AND bl.break_date = p_work_date AND bl.round_key = p_round_key AND bl.started_at = p_slot_start_ts
      AND bl.break_type = 'MEAL' AND bl.status = 'active' AND (bl.user_group = v_user_group OR v_user_group IS NULL);
  ELSE
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      WHERE p.default_branch_id = p_branch_id AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (SELECT 1 FROM holidays h WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status IN ('approved', 'pending'))
        AND (v_user_group IS NULL OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role)) OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role) OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role))
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id AND shift_id = p_shift_id AND break_date = p_work_date
      AND round_key = p_round_key AND started_at = p_slot_start_ts
      AND break_type = 'MEAL' AND status = 'active' AND (user_group = v_user_group OR v_user_group IS NULL);
    SELECT COALESCE(jsonb_agg(bl.user_id ORDER BY bl.user_id), '[]'::JSONB) INTO v_booked_user_ids
    FROM break_logs bl
    WHERE bl.branch_id = p_branch_id AND bl.shift_id = p_shift_id AND bl.break_date = p_work_date
      AND bl.round_key = p_round_key AND bl.started_at = p_slot_start_ts
      AND bl.break_type = 'MEAL' AND bl.status = 'active' AND (bl.user_group = v_user_group OR v_user_group IS NULL);
  END IF;
  SELECT COALESCE(MIN(mqr.max_concurrent), 1) INTO v_max_concurrent
  FROM meal_quota_rules mqr
  WHERE (mqr.branch_id = p_branch_id OR mqr.branch_id IS NULL)
    AND (mqr.shift_id = p_shift_id OR mqr.shift_id IS NULL)
    AND (mqr.website_id = p_website_id OR mqr.website_id IS NULL)
    AND (mqr.user_group = v_user_group OR mqr.user_group IS NULL)
    AND mqr.on_duty_threshold >= v_on_duty_count;
  RETURN jsonb_build_object(
    'on_duty_count', v_on_duty_count,
    'max_concurrent', v_max_concurrent,
    'current_booked', v_current_booked,
    'is_full', (v_current_booked >= v_max_concurrent),
    'booked_user_ids', COALESCE(v_booked_user_ids, '[]'::JSONB)
  );
END;
$$;

ALTER TABLE schedule_cards ADD COLUMN IF NOT EXISTS branch_ids UUID[] DEFAULT NULL;
UPDATE schedule_cards
SET branch_ids = ARRAY[branch_id]
WHERE branch_id IS NOT NULL
  AND (branch_ids IS NULL OR branch_ids = '{}');
DROP POLICY IF EXISTS schedule_cards_select ON schedule_cards;
CREATE POLICY schedule_cards_select ON schedule_cards FOR SELECT TO authenticated USING (
  is_admin_or_manager_or_head()
  OR (
    (
      (branch_id IS NULL AND (branch_ids IS NULL OR branch_ids = '{}'))
      OR branch_id IN (SELECT user_branch_ids(auth.uid()))
      OR (branch_ids IS NOT NULL AND branch_ids <> '{}' AND branch_ids && (SELECT array_agg(ub) FROM user_branch_ids(auth.uid()) AS ub))
    )
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles))
    AND (website_id IS NULL OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid()))
  )
);
DROP POLICY IF EXISTS schedule_cards_insert ON schedule_cards;
CREATE POLICY schedule_cards_insert ON schedule_cards FOR INSERT TO authenticated WITH CHECK (
  is_admin_or_manager()
  OR (is_instructor_head() AND (
    (branch_ids IS NOT NULL AND branch_ids <> '{}' AND my_branch_id() = ANY(branch_ids))
    OR ((branch_ids IS NULL OR branch_ids = '{}') AND branch_id = my_branch_id())
  ))
);
DROP POLICY IF EXISTS schedule_cards_update ON schedule_cards;
CREATE POLICY schedule_cards_update ON schedule_cards FOR UPDATE TO authenticated USING (
  is_admin_or_manager()
  OR (is_instructor_head() AND (
    (branch_ids IS NOT NULL AND branch_ids <> '{}' AND my_branch_id() = ANY(branch_ids))
    OR ((branch_ids IS NULL OR branch_ids = '{}') AND branch_id = my_branch_id())
  ))
);
DROP POLICY IF EXISTS schedule_cards_delete ON schedule_cards;
CREATE POLICY schedule_cards_delete ON schedule_cards FOR DELETE TO authenticated USING (
  is_admin_or_manager()
  OR (is_instructor_head() AND (
    (branch_ids IS NOT NULL AND branch_ids <> '{}' AND my_branch_id() = ANY(branch_ids))
    OR ((branch_ids IS NULL OR branch_ids = '{}') AND branch_id = my_branch_id())
  ))
);

ALTER TABLE meal_settings ADD COLUMN IF NOT EXISTS max_holiday_days_per_person_per_month INT DEFAULT 4;

CREATE OR REPLACE FUNCTION get_meal_slots_unified(p_work_date DATE)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_branch_id UUID;
  v_shift_id UUID;
  v_website_id UUID;
  v_shift_start_ts TIMESTAMPTZ;
  v_shift_end_ts TIMESTAMPTZ;
  v_shift_start_time TIME;
  v_settings JSONB;
  v_rounds JSONB;
  v_round JSONB;
  v_slot JSONB;
  v_round_key TEXT;
  v_slot_start_ts TIMESTAMPTZ;
  v_slot_end_ts TIMESTAMPTZ;
  v_cap JSONB;
  v_my_bookings JSONB := '[]'::JSONB;
  v_meal_count INT;
  v_out_rounds JSONB := '[]'::JSONB;
  v_slots_in_round JSONB;
  v_booked_count INT;
  v_max_concurrent INT;
  v_is_booked_by_me BOOLEAN;
  v_available BOOLEAN;
  v_on_duty_user_ids JSONB;
  i INT; j INT;
BEGIN
  SELECT p.default_branch_id, p.default_shift_id INTO v_branch_id, v_shift_id FROM profiles p WHERE p.id = v_uid LIMIT 1;
  SELECT wa.website_id INTO v_website_id FROM website_assignments wa WHERE wa.user_id = v_uid AND wa.is_primary = true LIMIT 1;
  IF v_branch_id IS NULL OR v_shift_id IS NULL OR v_website_id IS NULL THEN
    RETURN jsonb_build_object('error', 'missing_branch_shift_website', 'rounds', '[]'::JSONB, 'my_bookings', '[]'::JSONB, 'meal_count', 0, 'on_duty_user_ids', '[]'::JSONB, 'max_per_work_date', 2);
  END IF;
  v_on_duty_user_ids := get_meal_on_duty_user_ids(p_work_date);
  SELECT s.start_time, (p_work_date + s.start_time)::TIMESTAMPTZ, (p_work_date + s.end_time)::TIMESTAMPTZ
  INTO v_shift_start_time, v_shift_start_ts, v_shift_end_ts
  FROM shifts s WHERE s.id = v_shift_id LIMIT 1;
  IF v_shift_start_ts IS NULL THEN
    RETURN jsonb_build_object('error', 'shift_not_found', 'rounds', '[]'::JSONB, 'my_bookings', '[]'::JSONB, 'meal_count', 0, 'on_duty_user_ids', v_on_duty_user_ids, 'max_per_work_date', 2);
  END IF;
  IF v_shift_end_ts <= v_shift_start_ts THEN
    v_shift_end_ts := (p_work_date + 1 + (SELECT end_time FROM shifts WHERE id = v_shift_id))::TIMESTAMPTZ;
  END IF;
  SELECT rounds_json INTO v_settings FROM meal_settings WHERE is_enabled = true ORDER BY effective_from DESC LIMIT 1;
  IF v_settings IS NULL OR (v_settings->'rounds') IS NULL THEN
    RETURN jsonb_build_object('work_date', p_work_date, 'shift_start_ts', v_shift_start_ts, 'shift_end_ts', v_shift_end_ts, 'rounds', '[]'::JSONB, 'my_bookings', '[]'::JSONB, 'meal_count', 0, 'on_duty_user_ids', v_on_duty_user_ids, 'max_per_work_date', 2);
  END IF;
  v_rounds := v_settings->'rounds';
  SELECT COUNT(*)::INT INTO v_meal_count
  FROM break_logs WHERE user_id = v_uid AND break_date = p_work_date AND break_type = 'MEAL' AND status = 'active';
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'round_key', round_key, 'slot_start_ts', started_at, 'slot_end_ts', ended_at)), '[]'::JSONB) INTO v_my_bookings
  FROM break_logs
  WHERE user_id = v_uid AND break_date = p_work_date AND break_type = 'MEAL' AND status = 'active';
  FOR i IN 0 .. jsonb_array_length(v_rounds) - 1 LOOP
    v_round := v_rounds->i;
    v_round_key := v_round->>'key';
    IF v_round_key IS NULL OR v_round_key = '' THEN v_round_key := 'round_' || i; END IF;
    v_slots_in_round := '[]'::JSONB;
    FOR j IN 0 .. jsonb_array_length(COALESCE(v_round->'slots', '[]'::JSONB)) - 1 LOOP
      v_slot := (v_round->'slots')->j;
      v_slot_start_ts := (p_work_date + ((v_slot->>'start')::TIME))::TIMESTAMPTZ;
      v_slot_end_ts := (p_work_date + ((v_slot->>'end')::TIME))::TIMESTAMPTZ;
      IF v_shift_end_ts <= v_shift_start_ts AND ((v_slot->>'start')::TIME) < v_shift_start_time THEN
        v_slot_start_ts := (p_work_date + 1 + ((v_slot->>'start')::TIME))::TIMESTAMPTZ;
        v_slot_end_ts := (p_work_date + 1 + ((v_slot->>'end')::TIME))::TIMESTAMPTZ;
      ELSIF v_slot_end_ts <= v_slot_start_ts THEN
        v_slot_end_ts := (p_work_date + 1 + ((v_slot->>'end')::TIME))::TIMESTAMPTZ;
      END IF;
      v_cap := get_meal_capacity_break_logs(v_branch_id, v_shift_id, v_website_id, p_work_date, v_round_key, v_slot_start_ts);
      v_booked_count := COALESCE((v_cap->>'current_booked')::INT, 0);
      v_max_concurrent := COALESCE((v_cap->>'max_concurrent')::INT, 1);
      SELECT EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_my_bookings) AS el
        WHERE (el->>'slot_start_ts')::timestamptz = v_slot_start_ts
      ) INTO v_is_booked_by_me;
      v_available := (v_booked_count < v_max_concurrent) AND NOT v_is_booked_by_me;
      v_slots_in_round := v_slots_in_round || jsonb_build_array(jsonb_build_object(
        'slot_start', v_slot->>'start', 'slot_end', v_slot->>'end',
        'slot_start_ts', v_slot_start_ts, 'slot_end_ts', v_slot_end_ts,
        'booked_count', v_booked_count, 'max_concurrent', v_max_concurrent,
        'is_booked_by_me', v_is_booked_by_me, 'available', v_available,
        'capacity', v_cap
      ));
    END LOOP;
    v_out_rounds := v_out_rounds || jsonb_build_array(jsonb_build_object(
      'round_key', v_round_key, 'round_name', v_round->>'name', 'slots', v_slots_in_round
    ));
  END LOOP;
  RETURN jsonb_build_object(
    'work_date', p_work_date,
    'shift_start_ts', v_shift_start_ts,
    'shift_end_ts', v_shift_end_ts,
    'rounds', v_out_rounds,
    'my_bookings', v_my_bookings,
    'meal_count', v_meal_count,
    'on_duty_user_ids', v_on_duty_user_ids,
    'max_per_work_date', COALESCE((v_settings->>'max_per_work_date')::INT, 2)
  );
END;
$$;

CREATE OR REPLACE FUNCTION holidays_check_quota()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_days INT;
  v_cnt INT;
  v_total_after INT;
  v_new_counts BOOLEAN;
  v_scope_by_website BOOLEAN := true;
  v_total_people INT;
  v_current_booked INT;
  v_max_leave INT;
  v_primary_website_id UUID;
BEGIN
  IF NEW.status NOT IN ('approved', 'pending') THEN
    RETURN NEW;
  END IF;
  v_new_counts := (NEW.leave_type IS NULL OR NEW.leave_type = 'HOLIDAY') AND (NEW.is_quota_exempt IS NULL OR NEW.is_quota_exempt = false);
  IF v_new_counts THEN
    SELECT COALESCE(ms.max_holiday_days_per_person_per_month, 4) INTO v_max_days
    FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;
    IF v_max_days IS NULL THEN v_max_days := 4; END IF;
    SELECT COUNT(*)::INT INTO v_cnt
    FROM holidays h
    WHERE h.user_id = NEW.user_id
      AND h.holiday_date >= date_trunc('month', NEW.holiday_date)::date
      AND h.holiday_date < date_trunc('month', NEW.holiday_date)::date + interval '1 month'
      AND h.status IN ('approved', 'pending')
      AND (h.leave_type IS NULL OR h.leave_type = 'HOLIDAY')
      AND (h.is_quota_exempt IS NULL OR h.is_quota_exempt = false)
      AND (TG_OP <> 'UPDATE' OR h.id <> NEW.id);
    v_total_after := v_cnt + 1;
    IF v_total_after > v_max_days THEN
      RAISE EXCEPTION 'เกินกติกากลาง: แต่ละคนจองวันหยุดได้สูงสุด % วัน/เดือน (คนนี้จะมี % วันในเดือนนี้)', v_max_days, v_total_after
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF NEW.is_quota_exempt = true OR (NEW.leave_type IS NOT NULL AND NEW.leave_type <> 'HOLIDAY') THEN
    RETURN NEW;
  END IF;
  SELECT COALESCE(ms.scope_holiday_quota_by_website, true) INTO v_scope_by_website
  FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;
  SELECT wa.website_id INTO v_primary_website_id
  FROM website_assignments wa WHERE wa.user_id = NEW.user_id AND wa.is_primary = true LIMIT 1;
  IF v_scope_by_website AND v_primary_website_id IS NOT NULL THEN
    SELECT COUNT(*)::INT INTO v_total_people
    FROM profiles p
    INNER JOIN website_assignments wa ON wa.user_id = p.id AND wa.is_primary = true AND wa.website_id = v_primary_website_id
    WHERE p.default_branch_id = NEW.branch_id AND p.default_shift_id = NEW.shift_id
      AND (p.active IS NULL OR p.active = true)
      AND (
        (NEW.user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
        OR (NEW.user_group = 'STAFF' AND p.role = 'staff'::app_role)
        OR (NEW.user_group = 'MANAGER' AND p.role = 'manager'::app_role)
      );
  ELSE
    SELECT COUNT(*)::INT INTO v_total_people
    FROM profiles p
    WHERE p.default_branch_id = NEW.branch_id AND p.default_shift_id = NEW.shift_id
      AND (p.active IS NULL OR p.active = true)
      AND (
        (NEW.user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
        OR (NEW.user_group = 'STAFF' AND p.role = 'staff'::app_role)
        OR (NEW.user_group = 'MANAGER' AND p.role = 'manager'::app_role)
      );
  END IF;
  SELECT MIN(hqt.max_leave) INTO v_max_leave
  FROM holiday_quota_tiers hqt
  WHERE hqt.dimension = 'combined'
    AND (hqt.user_group = NEW.user_group OR hqt.user_group IS NULL)
    AND v_total_people <= hqt.max_people;
  IF v_max_leave IS NULL THEN
    RETURN NEW;
  END IF;
  IF v_scope_by_website AND v_primary_website_id IS NOT NULL THEN
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM holidays h
    INNER JOIN website_assignments wa ON wa.user_id = h.user_id AND wa.is_primary = true AND wa.website_id = v_primary_website_id
    WHERE h.holiday_date = NEW.holiday_date
      AND h.branch_id = NEW.branch_id AND h.shift_id = NEW.shift_id AND h.user_group = NEW.user_group
      AND h.status IN ('approved', 'pending') AND (h.leave_type IS NULL OR h.leave_type = 'HOLIDAY') AND (h.is_quota_exempt IS NULL OR h.is_quota_exempt = false)
      AND (TG_OP <> 'UPDATE' OR h.id <> NEW.id);
  ELSE
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM holidays h
    WHERE h.holiday_date = NEW.holiday_date
      AND h.branch_id = NEW.branch_id AND h.shift_id = NEW.shift_id AND h.user_group = NEW.user_group
      AND h.status IN ('approved', 'pending') AND (h.leave_type IS NULL OR h.leave_type = 'HOLIDAY') AND (h.is_quota_exempt IS NULL OR h.is_quota_exempt = false)
      AND (TG_OP <> 'UPDATE' OR h.id <> NEW.id);
  END IF;
  v_current_booked := v_current_booked + 1;
  IF v_current_booked > v_max_leave THEN
    RAISE EXCEPTION 'โควต้าวันนี้เต็มแล้ว: ในกลุ่มแผนกกะเดียวกันหยุดได้สูงสุด % คน/วัน (วันนี้มี % คนแล้ว)', v_max_leave, v_current_booked - 1
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS holidays_check_quota_trigger ON holidays;
CREATE TRIGGER holidays_check_quota_trigger
  BEFORE INSERT OR UPDATE OF user_id, branch_id, shift_id, holiday_date, status, user_group, is_quota_exempt, leave_type
  ON holidays
  FOR EACH ROW
  EXECUTE PROCEDURE holidays_check_quota();

CREATE OR REPLACE FUNCTION get_meal_quota_for_group(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_user_group TEXT,
  p_on_duty_count INT
)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    (
      SELECT mqr.max_concurrent
      FROM meal_quota_rules mqr
      WHERE
        (mqr.branch_id = p_branch_id OR mqr.branch_id IS NULL)
        AND (mqr.shift_id = p_shift_id OR mqr.shift_id IS NULL)
        AND (mqr.website_id = p_website_id OR mqr.website_id IS NULL)
        AND (mqr.user_group = p_user_group OR mqr.user_group IS NULL)
        AND mqr.on_duty_threshold >= p_on_duty_count
      ORDER BY mqr.on_duty_threshold ASC
      LIMIT 1
    ),
    1
  );
$$;
CREATE OR REPLACE FUNCTION get_meal_capacity_break_logs(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_work_date DATE,
  p_round_key TEXT,
  p_slot_start_ts TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_holiday_date DATE;
  v_on_duty_count INT;
  v_max_concurrent INT;
  v_current_booked INT;
  v_user_group TEXT;
  v_scope_by_website BOOLEAN := true;
  v_booked_user_ids JSONB;
BEGIN
  v_holiday_date := DATE(p_slot_start_ts);
  v_user_group := my_user_group();
  SELECT COALESCE(ms.scope_meal_quota_by_website, true) INTO v_scope_by_website
  FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;
  IF v_scope_by_website THEN
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      INNER JOIN website_assignments wa ON wa.user_id = p.id AND wa.website_id = p_website_id AND wa.is_primary = true
      WHERE p.default_branch_id = p_branch_id AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (SELECT 1 FROM holidays h WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status IN ('approved', 'pending'))
        AND (v_user_group IS NULL OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role)) OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role) OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role))
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id AND shift_id = p_shift_id AND website_id = p_website_id
      AND break_date = p_work_date AND round_key = p_round_key AND started_at = p_slot_start_ts
      AND break_type = 'MEAL' AND status = 'active' AND (user_group = v_user_group OR v_user_group IS NULL);
    SELECT COALESCE(jsonb_agg(bl.user_id ORDER BY bl.user_id), '[]'::JSONB) INTO v_booked_user_ids
    FROM break_logs bl
    WHERE bl.branch_id = p_branch_id AND bl.shift_id = p_shift_id AND bl.website_id = p_website_id
      AND bl.break_date = p_work_date AND bl.round_key = p_round_key AND bl.started_at = p_slot_start_ts
      AND bl.break_type = 'MEAL' AND bl.status = 'active' AND (bl.user_group = v_user_group OR v_user_group IS NULL);
  ELSE
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      WHERE p.default_branch_id = p_branch_id AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (SELECT 1 FROM holidays h WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status IN ('approved', 'pending'))
        AND (v_user_group IS NULL OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role)) OR (v_user_group = 'STAFF' AND p.role = 'staff'::app_role) OR (v_user_group = 'MANAGER' AND p.role = 'manager'::app_role))
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id AND shift_id = p_shift_id AND break_date = p_work_date
      AND round_key = p_round_key AND started_at = p_slot_start_ts
      AND break_type = 'MEAL' AND status = 'active' AND (user_group = v_user_group OR v_user_group IS NULL);
    SELECT COALESCE(jsonb_agg(bl.user_id ORDER BY bl.user_id), '[]'::JSONB) INTO v_booked_user_ids
    FROM break_logs bl
    WHERE bl.branch_id = p_branch_id AND bl.shift_id = p_shift_id AND bl.break_date = p_work_date
      AND bl.round_key = p_round_key AND bl.started_at = p_slot_start_ts
      AND bl.break_type = 'MEAL' AND bl.status = 'active' AND (bl.user_group = v_user_group OR v_user_group IS NULL);
  END IF;
  SELECT COALESCE(
    (
      SELECT mqr.max_concurrent
      FROM meal_quota_rules mqr
      WHERE (mqr.branch_id = p_branch_id OR mqr.branch_id IS NULL)
        AND (mqr.shift_id = p_shift_id OR mqr.shift_id IS NULL)
        AND (mqr.website_id = p_website_id OR mqr.website_id IS NULL)
        AND (mqr.user_group = v_user_group OR mqr.user_group IS NULL)
        AND mqr.on_duty_threshold >= v_on_duty_count
      ORDER BY mqr.on_duty_threshold ASC
      LIMIT 1
    ),
    1
  ) INTO v_max_concurrent;
  IF v_on_duty_count <= 4 AND v_max_concurrent > 1 THEN
    v_max_concurrent := 1;
  END IF;
  RETURN jsonb_build_object(
    'on_duty_count', v_on_duty_count,
    'max_concurrent', v_max_concurrent,
    'current_booked', v_current_booked,
    'is_full', (v_current_booked >= v_max_concurrent),
    'booked_user_ids', COALESCE(v_booked_user_ids, '[]'::JSONB)
  );
END;
$$;

ALTER TABLE public.duty_assignments
  DROP CONSTRAINT IF EXISTS duty_assignments_branch_id_shift_id_duty_role_id_assignment_date_key;
CREATE UNIQUE INDEX IF NOT EXISTS duty_assignments_one_user_per_role_per_day
  ON public.duty_assignments (branch_id, shift_id, duty_role_id, assignment_date, user_id)
  WHERE user_id IS NOT NULL;

ALTER TABLE shift_swaps
  ALTER COLUMN end_date DROP NOT NULL;
ALTER TABLE cross_branch_transfers
  ALTER COLUMN end_date DROP NOT NULL;
CREATE OR REPLACE FUNCTION tomorrow_bangkok()
RETURNS DATE
LANGUAGE sql
STABLE
AS $$
  SELECT ((now() AT TIME ZONE 'Asia/Bangkok')::date + 1);
$$;
CREATE OR REPLACE FUNCTION check_shift_change_start_date()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.start_date IS NULL THEN
    RAISE EXCEPTION 'START_DATE_MUST_BE_TOMORROW_OR_LATER' USING errcode = 'P0001';
  END IF;
  IF NEW.start_date < tomorrow_bangkok() THEN
    RAISE EXCEPTION 'START_DATE_MUST_BE_TOMORROW_OR_LATER: วันที่มีผลต้องเป็นวันพรุ่งนี้ขึ้นไป (Asia/Bangkok)'
      USING errcode = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS shift_swaps_start_date_tomorrow ON shift_swaps;
CREATE TRIGGER shift_swaps_start_date_tomorrow
  BEFORE INSERT OR UPDATE OF start_date ON shift_swaps
  FOR EACH ROW EXECUTE PROCEDURE check_shift_change_start_date();
DROP TRIGGER IF EXISTS cross_branch_transfers_start_date_tomorrow ON cross_branch_transfers;
CREATE TRIGGER cross_branch_transfers_start_date_tomorrow
  BEFORE INSERT OR UPDATE OF start_date ON cross_branch_transfers
  FOR EACH ROW EXECUTE PROCEDURE check_shift_change_start_date();
CREATE OR REPLACE FUNCTION apply_scheduled_shift_changes_for_date(p_date DATE)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  uid UUID;
  to_br UUID;
  to_sh UUID;
  updated_count INT := 0;
BEGIN
  IF p_date IS NULL THEN RETURN 0; END IF;
  FOR r IN (
    SELECT user_id, to_branch_id, to_shift_id
    FROM (
      SELECT user_id, to_branch_id, to_shift_id,
             ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC NULLS LAST, start_date DESC) AS rn
      FROM (
        SELECT user_id, branch_id AS to_branch_id, to_shift_id, start_date, created_at
        FROM shift_swaps
        WHERE status = 'approved'
          AND start_date <= p_date
          AND (end_date IS NULL OR p_date <= end_date)
        UNION ALL
        SELECT user_id, to_branch_id, to_shift_id, start_date, created_at
        FROM cross_branch_transfers
        WHERE status = 'approved'
          AND start_date <= p_date
          AND (end_date IS NULL OR p_date <= end_date)
      ) combined
    ) sub
    WHERE rn = 1
  ) LOOP
    uid := r.user_id;
    to_br := r.to_branch_id;
    to_sh := r.to_shift_id;
    IF uid IS NOT NULL AND to_sh IS NOT NULL THEN
      UPDATE profiles
      SET default_shift_id = to_sh,
          default_branch_id = COALESCE(to_br, default_branch_id),
          updated_at = now()
      WHERE id = uid
        AND (default_shift_id IS DISTINCT FROM to_sh OR default_branch_id IS DISTINCT FROM COALESCE(to_br, default_branch_id));
      IF FOUND THEN
        updated_count := updated_count + 1;
      END IF;
    END IF;
  END LOOP;
  RETURN updated_count;
END;
$$;
CREATE OR REPLACE FUNCTION apply_bulk_assignment(
  p_employee_ids UUID[],
  p_start_date DATE,
  p_end_date DATE,
  p_to_branch_id UUID,
  p_to_shift_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  may_run BOOLEAN;
  is_head BOOLEAN;
  emp_id UUID;
  from_branch_id UUID;
  from_shift_id UUID;
  applied_count INT := 0;
  out_skipped JSONB := '{}'::JSONB;
  has_scheduled BOOLEAN;
BEGIN
  IF p_start_date IS NULL OR p_start_date < tomorrow_bangkok() THEN
    RAISE EXCEPTION 'START_DATE_MUST_BE_TOMORROW_OR_LATER'
      USING errcode = 'P0001';
  END IF;
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head'::app_role);
  IF NOT may_run AND NOT is_head THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can run bulk assignment';
  END IF;
  IF is_head AND NOT may_run THEN
    IF p_to_branch_id IS NULL OR p_to_branch_id != my_branch_id() THEN
      RAISE EXCEPTION 'Instructor head can only assign to their own branch';
    END IF;
  END IF;
  FOR emp_id IN SELECT unnest(p_employee_ids)
  LOOP
    SELECT EXISTS (
      SELECT 1 FROM shift_swaps s
      WHERE s.user_id = emp_id AND s.status = 'approved' AND s.start_date >= current_date
        AND (s.end_date IS NULL OR s.end_date >= current_date)
      UNION ALL
      SELECT 1 FROM cross_branch_transfers t
      WHERE t.user_id = emp_id AND t.status = 'approved' AND t.start_date >= current_date
        AND (t.end_date IS NULL OR t.end_date >= current_date)
    ) INTO has_scheduled;
    IF has_scheduled THEN
      out_skipped := out_skipped || jsonb_build_object(emp_id::text, to_jsonb(ARRAY[p_start_date]::text[]));
    ELSE
      SELECT p.default_branch_id, p.default_shift_id INTO from_branch_id, from_shift_id
        FROM profiles p WHERE p.id = emp_id LIMIT 1;
      IF from_branch_id IS NULL THEN from_branch_id := p_to_branch_id; END IF;
      IF from_shift_id IS NULL THEN from_shift_id := p_to_shift_id; END IF;
      IF from_branch_id = p_to_branch_id THEN
        IF from_shift_id IS DISTINCT FROM p_to_shift_id THEN
          INSERT INTO shift_swaps (
            user_id, branch_id, from_shift_id, to_shift_id,
            start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
          ) VALUES (
            emp_id, from_branch_id, from_shift_id, p_to_shift_id,
            p_start_date, NULL, p_reason, 'approved', uid, now(), NULL
          );
          applied_count := applied_count + 1;
        END IF;
      ELSE
        INSERT INTO cross_branch_transfers (
          user_id, from_branch_id, to_branch_id, from_shift_id, to_shift_id,
          start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
        ) VALUES (
          emp_id, from_branch_id, p_to_branch_id, from_shift_id, p_to_shift_id,
          p_start_date, NULL, p_reason, 'approved', uid, now(), NULL
        );
        applied_count := applied_count + 1;
      END IF;
    END IF;
  END LOOP;
  RETURN jsonb_build_object(
    'applied', applied_count,
    'skipped_per_user', out_skipped
  );
END;
$$;
CREATE OR REPLACE FUNCTION apply_paired_swap(
  p_branch_id UUID,
  p_start_date DATE,
  p_end_date DATE,
  p_assignments JSONB,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_uid UUID := auth.uid();
  may_run BOOLEAN;
  is_head BOOLEAN;
  rec JSONB;
  emp_id UUID;
  to_shift_id UUID;
  from_shift_id UUID;
  applied_count INT := 0;
  out_skipped JSONB := '{}'::JSONB;
  i INT;
  has_scheduled BOOLEAN;
  overlap_user UUID;
BEGIN
  IF p_start_date IS NULL OR p_start_date < tomorrow_bangkok() THEN
    RAISE EXCEPTION 'START_DATE_MUST_BE_TOMORROW_OR_LATER'
      USING errcode = 'P0001';
  END IF;
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = caller_uid AND role IN ('admin'::app_role,'manager'::app_role));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = caller_uid AND role = 'instructor_head'::app_role);
  IF NOT may_run AND NOT is_head THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can run paired swap';
  END IF;
  IF is_head AND NOT may_run THEN
    IF p_branch_id IS NULL OR p_branch_id != my_branch_id() THEN
      RAISE EXCEPTION 'Instructor head can only assign to their own branch';
    END IF;
  END IF;
  FOR i IN 0 .. jsonb_array_length(p_assignments) - 1 LOOP
    rec := p_assignments->i;
    emp_id := (rec->>'user_id')::UUID;
    IF emp_id IS NULL THEN CONTINUE; END IF;
    SELECT EXISTS (
      SELECT 1 FROM shift_swaps s
      WHERE s.user_id = emp_id AND s.status = 'approved' AND s.start_date <= p_start_date
        AND (s.end_date IS NULL OR p_start_date <= s.end_date)
      UNION ALL
      SELECT 1 FROM cross_branch_transfers t
      WHERE t.user_id = emp_id AND t.status = 'approved' AND t.start_date <= p_start_date
        AND (t.end_date IS NULL OR p_start_date <= t.end_date)
    ) INTO has_scheduled;
    IF has_scheduled THEN
      RAISE EXCEPTION 'SHIFT_CHANGE_OVERLAP_CONFLICT: ผู้ใช้มีรายการย้ายกะ/สลับกะที่ยังมีผลอยู่'
        USING errcode = 'P0001';
    END IF;
  END LOOP;
  WITH elem AS (
    SELECT (e->>'user_id')::UUID AS elem_uid, (e->>'to_shift_id')::UUID AS elem_sid, ord
    FROM jsonb_array_elements(p_assignments) WITH ORDINALITY AS t(e, ord)
    WHERE (e->>'user_id')::UUID IS NOT NULL AND (e->>'to_shift_id')::UUID IS NOT NULL
  ),
  deduped AS (
    SELECT elem_uid, elem_sid, ROW_NUMBER() OVER (PARTITION BY elem_uid ORDER BY ord DESC) AS rn FROM elem
  )
  SELECT jsonb_agg(jsonb_build_object('user_id', d.elem_uid, 'to_shift_id', d.elem_sid))
  INTO p_assignments
  FROM (SELECT elem_uid, elem_sid FROM deduped WHERE rn = 1) d;
  IF p_assignments IS NULL THEN p_assignments := '[]'::JSONB; END IF;
  FOR i IN 0 .. jsonb_array_length(p_assignments) - 1 LOOP
    rec := p_assignments->i;
    emp_id := (rec->>'user_id')::UUID;
    to_shift_id := (rec->>'to_shift_id')::UUID;
    IF emp_id IS NULL OR to_shift_id IS NULL THEN CONTINUE; END IF;
    SELECT p.default_shift_id INTO from_shift_id
      FROM profiles p WHERE p.id = emp_id LIMIT 1;
    IF from_shift_id IS NULL THEN from_shift_id := to_shift_id; END IF;
    IF from_shift_id IS DISTINCT FROM to_shift_id THEN
      INSERT INTO shift_swaps (
        user_id, branch_id, from_shift_id, to_shift_id,
        start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
      ) VALUES (
        emp_id, p_branch_id, from_shift_id, to_shift_id,
        p_start_date, NULL, p_reason, 'approved', caller_uid, now(), NULL
      );
      applied_count := applied_count + 1;
    END IF;
  END LOOP;
  RETURN jsonb_build_object(
    'applied', applied_count,
    'skipped_per_user', out_skipped
  );
END;
$$;
CREATE OR REPLACE FUNCTION update_scheduled_shift_change(
  p_type TEXT,
  p_id UUID,
  p_new_start_date DATE,
  p_new_to_shift_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  v_user_id UUID;
  v_branch_id UUID;
  v_to_shift_id UUID;
BEGIN
  IF p_new_start_date IS NULL OR p_new_start_date < tomorrow_bangkok() THEN
    RAISE EXCEPTION 'START_DATE_MUST_BE_TOMORROW_OR_LATER'
      USING errcode = 'P0001';
  END IF;
  IF NOT (EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role,'instructor_head'::app_role))) THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can update scheduled shift change';
  END IF;
  IF p_type = 'swap' THEN
    SELECT user_id, branch_id, to_shift_id INTO v_user_id, v_branch_id, v_to_shift_id
      FROM shift_swaps WHERE id = p_id AND status = 'approved' LIMIT 1;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'not_found_or_not_approved');
    END IF;
    IF EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head'::app_role) AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role)) THEN
      IF v_branch_id IS NULL OR v_branch_id != my_branch_id() THEN
        RAISE EXCEPTION 'Instructor head can only update within their branch';
      END IF;
    END IF;
    v_to_shift_id := COALESCE(p_new_to_shift_id, v_to_shift_id);
    UPDATE shift_swaps
      SET start_date = p_new_start_date, end_date = NULL, to_shift_id = v_to_shift_id, updated_at = now()
      WHERE id = p_id;
  ELSIF p_type = 'transfer' THEN
    SELECT user_id, to_branch_id, to_shift_id INTO v_user_id, v_branch_id, v_to_shift_id
      FROM cross_branch_transfers WHERE id = p_id AND status = 'approved' LIMIT 1;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'not_found_or_not_approved');
    END IF;
    IF EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head'::app_role) AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role)) THEN
      IF v_branch_id IS NULL OR v_branch_id != my_branch_id() THEN
        RAISE EXCEPTION 'Instructor head can only update within their branch';
      END IF;
    END IF;
    v_to_shift_id := COALESCE(p_new_to_shift_id, v_to_shift_id);
    UPDATE cross_branch_transfers
      SET start_date = p_new_start_date, end_date = NULL, to_shift_id = v_to_shift_id, updated_at = now()
      WHERE id = p_id;
  ELSE
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_type');
  END IF;
  RETURN jsonb_build_object('ok', true);
END;
$$;
CREATE TABLE IF NOT EXISTS cron_runs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_name TEXT NOT NULL,
  ran_at TIMESTAMPTZ DEFAULT now(),
  p_date DATE,
  success BOOLEAN NOT NULL,
  result_count INT,
  error_message TEXT
);
CREATE OR REPLACE FUNCTION run_apply_shift_changes_and_log()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  p_date DATE := ((now() AT TIME ZONE 'Asia/Bangkok')::date);
  cnt INT;
BEGIN
  cnt := apply_scheduled_shift_changes_for_date(p_date);
  INSERT INTO cron_runs (job_name, p_date, success, result_count)
  VALUES ('apply_scheduled_shift_changes_for_date', p_date, true, cnt);
  RETURN cnt;
EXCEPTION WHEN OTHERS THEN
  INSERT INTO cron_runs (job_name, p_date, success, error_message)
  VALUES ('apply_scheduled_shift_changes_for_date', p_date, false, SQLERRM);
  RAISE;
END;
$$;
GRANT EXECUTE ON FUNCTION run_apply_shift_changes_and_log() TO service_role;

CREATE OR REPLACE VIEW dashboard_today_staff AS
WITH today AS (
  SELECT ((now() AT TIME ZONE 'Asia/Bangkok')::date) AS d
),
holidays_today AS (
  SELECT DISTINCT ON (user_id)
    user_id,
    leave_type,
    reason,
    created_at
  FROM holidays, today
  WHERE holiday_date = today.d
    AND status IN ('approved', 'pending')
  ORDER BY user_id, created_at DESC
),
meal_today AS (
  SELECT DISTINCT ON (user_id)
    user_id,
    started_at AS meal_start_time,
    ended_at   AS meal_end_time
  FROM break_logs, today
  WHERE break_date = today.d
    AND break_type = 'MEAL'
    AND status = 'active'
  ORDER BY user_id, created_at DESC
)
SELECT
  p.id                AS staff_id,
  p.display_name      AS name,
  p.email             AS staff_code,
  p.role              AS role,
  p.default_branch_id AS default_branch_id,
  p.default_shift_id  AS default_shift_id,
  s.name              AS shift_name,
  CASE WHEN h.user_id IS NOT NULL THEN 'LEAVE' ELSE 'PRESENT' END AS status,
  h.leave_type        AS leave_type,
  h.reason            AS leave_reason,
  m.meal_start_time   AS meal_start_time,
  m.meal_end_time     AS meal_end_time
FROM profiles p
CROSS JOIN today
LEFT JOIN shifts s ON s.id = p.default_shift_id
LEFT JOIN holidays_today h ON h.user_id = p.id
LEFT JOIN meal_today m ON m.user_id = p.id
WHERE p.active = true
  AND p.role IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role);
GRANT SELECT ON dashboard_today_staff TO authenticated;

DROP VIEW IF EXISTS dashboard_today_staff CASCADE;
CREATE VIEW dashboard_today_staff AS
WITH today AS (
  SELECT ((now() AT TIME ZONE 'Asia/Bangkok')::date) AS d
),
holidays_today AS (
  SELECT DISTINCT ON (user_id)
    user_id,
    leave_type,
    reason,
    created_at
  FROM holidays, today
  WHERE holiday_date = today.d
    AND status IN ('approved', 'pending')
  ORDER BY user_id, created_at DESC
),
meal_all_today AS (
  SELECT
    user_id,
    jsonb_agg(
      jsonb_build_object('start', started_at, 'end', ended_at)
      ORDER BY started_at
    ) AS meal_slots
  FROM break_logs, today
  WHERE break_date = today.d
    AND break_type = 'MEAL'
    AND status = 'active'
  GROUP BY user_id
)
SELECT
  p.id                AS staff_id,
  p.display_name      AS name,
  p.email             AS staff_code,
  p.role              AS role,
  p.default_branch_id AS default_branch_id,
  p.default_shift_id  AS default_shift_id,
  s.name              AS shift_name,
  CASE WHEN h.user_id IS NOT NULL THEN 'LEAVE' ELSE 'PRESENT' END AS status,
  h.leave_type        AS leave_type,
  h.reason            AS leave_reason,
  m.meal_slots        AS meal_slots,
  (m.meal_slots->0->>'start')::timestamptz AS meal_start_time,
  (m.meal_slots->0->>'end')::timestamptz   AS meal_end_time
FROM profiles p
CROSS JOIN today
LEFT JOIN shifts s ON s.id = p.default_shift_id
LEFT JOIN holidays_today h ON h.user_id = p.id
LEFT JOIN meal_all_today m ON m.user_id = p.id
WHERE p.active = true
  AND p.role IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role);
GRANT SELECT ON dashboard_today_staff TO authenticated;

CREATE INDEX IF NOT EXISTS idx_holidays_holiday_date_user_id ON holidays(holiday_date, user_id);
CREATE INDEX IF NOT EXISTS idx_break_logs_break_date_user_id ON break_logs(break_date, user_id);
CREATE INDEX IF NOT EXISTS idx_profiles_default_branch_id ON profiles(default_branch_id);
CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role);
CREATE INDEX IF NOT EXISTS idx_cross_branch_transfers_created_at ON cross_branch_transfers(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cross_branch_transfers_from_branch_created ON cross_branch_transfers(from_branch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cross_branch_transfers_to_branch_created ON cross_branch_transfers(to_branch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_shift_swaps_created_at ON shift_swaps(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_shift_swaps_branch_created ON shift_swaps(branch_id, created_at DESC) WHERE branch_id IS NOT NULL;
CREATE OR REPLACE FUNCTION get_effective_branch_shift_for_date(
  p_user_id uuid,
  p_date date,
  p_fallback_branch uuid,
  p_fallback_shift uuid
)
RETURNS TABLE(branch_id uuid, shift_id uuid)
LANGUAGE sql
STABLE
AS $$
  WITH swaps AS (
    SELECT ss.branch_id, ss.to_shift_id AS shift_id, ss.start_date
    FROM shift_swaps ss
    WHERE ss.user_id = p_user_id AND ss.status = 'approved'
      AND ss.start_date <= p_date AND (ss.end_date IS NULL OR ss.end_date >= p_date)
    ORDER BY ss.start_date DESC
    LIMIT 1
  ),
  transfers AS (
    SELECT cbt.to_branch_id AS branch_id, cbt.to_shift_id AS shift_id, cbt.start_date
    FROM cross_branch_transfers cbt
    WHERE cbt.user_id = p_user_id AND cbt.status = 'approved'
      AND cbt.start_date <= p_date AND (cbt.end_date IS NULL OR cbt.end_date >= p_date)
    ORDER BY cbt.start_date DESC
    LIMIT 1
  ),
  combined AS (
    SELECT branch_id, shift_id, start_date FROM swaps
    UNION ALL
    SELECT branch_id, shift_id, start_date FROM transfers
  ),
  best AS (
    SELECT branch_id, shift_id
    FROM combined
    WHERE branch_id IS NOT NULL AND shift_id IS NOT NULL
    ORDER BY start_date DESC NULLS LAST
    LIMIT 1
  )
  SELECT COALESCE(b.branch_id, p_fallback_branch), COALESCE(b.shift_id, p_fallback_shift)
  FROM best b
  UNION ALL
  SELECT p_fallback_branch, p_fallback_shift
  WHERE NOT EXISTS (SELECT 1 FROM best);
$$;
CREATE OR REPLACE FUNCTION rpc_manager_dashboard_today(
  p_today date DEFAULT ((now() AT TIME ZONE 'Asia/Bangkok')::date),
  p_scope_branch_id uuid DEFAULT NULL,
  p_scope_shift_id uuid DEFAULT NULL
)
RETURNS TABLE(
  staff_id uuid,
  name text,
  staff_code text,
  role text,
  shift_name text,
  status text,
  leave_type text,
  leave_reason text,
  meal_slots jsonb,
  meal_start_time timestamptz,
  meal_end_time timestamptz
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH today AS (SELECT p_today AS d),
  holidays_today AS (
    SELECT DISTINCT ON (user_id) user_id, leave_type, reason, created_at
    FROM holidays, today
    WHERE holiday_date = today.d AND status IN ('approved', 'pending')
    ORDER BY user_id, created_at DESC
  ),
  meal_all_today AS (
    SELECT user_id,
      jsonb_agg(jsonb_build_object('start', started_at, 'end', ended_at) ORDER BY started_at) AS meal_slots
    FROM break_logs, today
    WHERE break_date = today.d AND break_type = 'MEAL' AND status = 'active'
    GROUP BY user_id
  ),
  base AS (
    SELECT
      p.id AS staff_id,
      p.display_name AS name,
      p.email AS staff_code,
      p.role AS role,
      s_eff.name AS shift_name,
      CASE WHEN h.user_id IS NOT NULL THEN 'LEAVE' ELSE 'PRESENT' END AS status,
      h.leave_type AS leave_type,
      h.reason AS leave_reason,
      m.meal_slots AS meal_slots,
      (m.meal_slots->0->>'start')::timestamptz AS meal_start_time,
      (m.meal_slots->0->>'end')::timestamptz AS meal_end_time,
      eff.branch_id AS eff_branch_id,
      eff.shift_id AS eff_shift_id
    FROM profiles p
    CROSS JOIN today
    LEFT JOIN holidays_today h ON h.user_id = p.id
    LEFT JOIN meal_all_today m ON m.user_id = p.id
    CROSS JOIN LATERAL get_effective_branch_shift_for_date(p.id, p_today, p.default_branch_id, p.default_shift_id) AS eff(branch_id, shift_id)
    LEFT JOIN shifts s_eff ON s_eff.id = eff.shift_id
    WHERE p.active = true
      AND p.role IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role)
  )
  SELECT b.staff_id, b.name, b.staff_code, b.role, b.shift_name, b.status, b.leave_type, b.leave_reason,
         b.meal_slots, b.meal_start_time, b.meal_end_time
  FROM base b
  WHERE (p_scope_branch_id IS NULL OR b.eff_branch_id = p_scope_branch_id)
    AND (p_scope_shift_id IS NULL OR b.eff_shift_id = p_scope_shift_id)
  ORDER BY b.status, b.name NULLS LAST;
$$;

CREATE OR REPLACE FUNCTION rpc_dutyboard(
  p_date date,
  p_branch_id uuid,
  p_shift_id uuid
)
RETURNS TABLE(
  duty_roles jsonb,
  assignments jsonb,
  staff jsonb,
  leave_user_ids jsonb,
  roster_status jsonb,
  websites jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
AS $$
DECLARE
  v_month date;
BEGIN
  v_month := date_trunc('month', p_date)::date;
  RETURN QUERY
  WITH
  dr AS (
    SELECT COALESCE(jsonb_agg(to_jsonb(dr.*) ORDER BY dr.sort_order), '[]'::jsonb) AS j
    FROM duty_roles dr
    WHERE dr.branch_id = p_branch_id
  ),
  asn AS (
    SELECT COALESCE(jsonb_agg(to_jsonb(a.*)), '[]'::jsonb) AS j
    FROM duty_assignments a
    WHERE a.branch_id = p_branch_id AND a.shift_id = p_shift_id AND a.assignment_date = p_date
  ),
  leave_ids AS (
    SELECT COALESCE(jsonb_agg(uid), '[]'::jsonb) AS j
    FROM (SELECT DISTINCT h.user_id AS uid FROM holidays h WHERE h.holiday_date = p_date AND h.status IN ('approved', 'pending')) t
  ),
  roster AS (
    SELECT to_jsonb(mrs.*) AS j
    FROM monthly_roster_status mrs
    WHERE mrs.branch_id = p_branch_id AND mrs.month = v_month
    LIMIT 1
  ),
  ws AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id', w.id, 'name', w.name) ORDER BY w.name), '[]'::jsonb) AS j
    FROM websites w
    WHERE w.is_active = true AND (w.branch_id = p_branch_id OR w.branch_id IS NULL)
  ),
  staff_with_eff AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'display_name', p.display_name,
        'email', p.email,
        'role', p.role,
        'default_branch_id', p.default_branch_id,
        'default_shift_id', p.default_shift_id,
        'active', p.active,
        'effective_branch_id', eff.branch_id,
        'effective_shift_id', eff.shift_id
      )
      ORDER BY p.display_name NULLS LAST
    ) AS j
    FROM profiles p
    CROSS JOIN LATERAL get_effective_branch_shift_for_date(p.id, p_date, p.default_branch_id, p.default_shift_id) AS eff(branch_id, shift_id)
    WHERE p.active = true AND p.role IN ('instructor'::app_role, 'staff'::app_role)
  )
  SELECT
    (SELECT j FROM dr),
    (SELECT j FROM asn),
    (SELECT j FROM staff_with_eff),
    (SELECT j FROM leave_ids),
    (SELECT j FROM roster),
    (SELECT j FROM ws);
END;
$$;
CREATE OR REPLACE FUNCTION rpc_holiday_grid(
  p_month_start date,
  p_month_end date,
  p_branch_id uuid DEFAULT NULL,
  p_only_my_user_id uuid DEFAULT NULL
)
RETURNS TABLE(
  staff jsonb,
  holidays jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
AS $$
BEGIN
  RETURN QUERY
  WITH
  staff_list AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'email', p.email,
        'display_name', COALESCE(p.display_name, p.email, ''),
        'role', p.role,
        'default_branch_id', p.default_branch_id,
        'default_shift_id', p.default_shift_id,
        'primary_website_id', wa.website_id
      )
      ORDER BY p.display_name NULLS LAST
    ) AS j
    FROM profiles p
    LEFT JOIN LATERAL (
      SELECT website_id FROM website_assignments WHERE user_id = p.id AND is_primary = true LIMIT 1
    ) wa ON true
    WHERE p.active = true AND p.role <> 'admin'
      AND (p_branch_id IS NULL OR p.default_branch_id = p_branch_id)
      AND (p_only_my_user_id IS NULL OR p.id = p_only_my_user_id)
  ),
  hol AS (
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', h.id, 'user_id', h.user_id, 'holiday_date', h.holiday_date,
          'status', h.status, 'leave_type', h.leave_type, 'reason', h.reason,
          'user_group', h.user_group, 'branch_id', h.branch_id, 'shift_id', h.shift_id,
          'approved_by', h.approved_by, 'approved_at', h.approved_at, 'reject_reason', h.reject_reason,
          'created_at', h.created_at, 'updated_at', h.updated_at, 'is_quota_exempt', h.is_quota_exempt
        )
      ),
      '[]'::jsonb
    ) AS j
    FROM (
      SELECT DISTINCT ON (h.user_id, h.holiday_date)
        h.id, h.user_id, h.holiday_date, h.status, h.leave_type, h.reason, h.user_group, h.branch_id, h.shift_id,
        h.approved_by, h.approved_at, h.reject_reason, h.created_at, h.updated_at, h.is_quota_exempt
      FROM holidays h
      WHERE h.holiday_date >= p_month_start AND h.holiday_date <= p_month_end
        AND (p_branch_id IS NULL OR h.branch_id = p_branch_id)
        AND (p_only_my_user_id IS NULL OR h.user_id = p_only_my_user_id)
      ORDER BY h.user_id, h.holiday_date, h.created_at DESC
    ) h
  )
  SELECT (SELECT j FROM staff_list), (SELECT j FROM hol);
END;
$$;
CREATE INDEX IF NOT EXISTS idx_holidays_user_id_holiday_date ON holidays(user_id, holiday_date);

ALTER TABLE public.duty_assignments
  DROP CONSTRAINT IF EXISTS duty_assignments_branch_id_shift_id_duty_role_id_assignment_date_key;
DO $$
DECLARE
  cn name;
BEGIN
  FOR cn IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    WHERE rel.relname = 'duty_assignments' AND con.contype = 'u'
      AND (
        SELECT array_agg(att.attname ORDER BY array_position(con.conkey, att.attnum))
        FROM pg_attribute att
        WHERE att.attrelid = con.conrelid AND att.attnum = ANY(con.conkey) AND NOT att.attisdropped
      ) IS NOT NULL
      AND (
        SELECT array_agg(att.attname ORDER BY array_position(con.conkey, att.attnum))
        FROM pg_attribute att
        WHERE att.attrelid = con.conrelid AND att.attnum = ANY(con.conkey) AND NOT att.attisdropped
      ) = ARRAY['branch_id', 'shift_id', 'duty_role_id', 'assignment_date']::name[]
  LOOP
    EXECUTE format('ALTER TABLE duty_assignments DROP CONSTRAINT IF EXISTS %I', cn);
  END LOOP;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS duty_assignments_one_user_per_role_per_day
  ON public.duty_assignments (branch_id, shift_id, duty_role_id, assignment_date, user_id)
  WHERE user_id IS NOT NULL;

DROP POLICY IF EXISTS profiles_select ON profiles;
CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated USING (
  is_admin()
  OR id = auth.uid()
  OR is_instructor_or_admin()
  OR (default_branch_id IS NOT NULL AND default_branch_id IN (SELECT user_branch_ids(auth.uid())))
);

BEGIN;
CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value_bool BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO app_settings (key, value_bool)
VALUES ('allow_mobile_access', false)
ON CONFLICT (key) DO NOTHING;
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS app_settings_select_all ON app_settings;
CREATE POLICY app_settings_select_all
ON app_settings
FOR SELECT
TO anon, authenticated
USING (true);
DROP POLICY IF EXISTS app_settings_update_admin ON app_settings;
CREATE POLICY app_settings_update_admin
ON app_settings
FOR UPDATE
TO authenticated
USING (is_admin())
WITH CHECK (is_admin());
REVOKE INSERT ON app_settings FROM anon, authenticated;
REVOKE DELETE ON app_settings FROM anon, authenticated;
DROP TRIGGER IF EXISTS trg_app_settings_updated_at ON app_settings;
CREATE TRIGGER trg_app_settings_updated_at
BEFORE UPDATE ON app_settings
FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
COMMIT;

BEGIN;
CREATE TABLE IF NOT EXISTS dashboard_shortcuts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  url TEXT NOT NULL,
  title TEXT NOT NULL,
  icon_url TEXT,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE dashboard_shortcuts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS dashboard_shortcuts_select ON dashboard_shortcuts;
CREATE POLICY dashboard_shortcuts_select
ON dashboard_shortcuts FOR SELECT TO authenticated
USING (true);
DROP POLICY IF EXISTS dashboard_shortcuts_insert ON dashboard_shortcuts;
CREATE POLICY dashboard_shortcuts_insert
ON dashboard_shortcuts FOR INSERT TO authenticated
WITH CHECK (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS dashboard_shortcuts_update ON dashboard_shortcuts;
CREATE POLICY dashboard_shortcuts_update
ON dashboard_shortcuts FOR UPDATE TO authenticated
USING (is_admin_or_manager_or_head())
WITH CHECK (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS dashboard_shortcuts_delete ON dashboard_shortcuts;
CREATE POLICY dashboard_shortcuts_delete
ON dashboard_shortcuts FOR DELETE TO authenticated
USING (is_admin_or_manager_or_head());
DROP TRIGGER IF EXISTS dashboard_shortcuts_updated_at ON dashboard_shortcuts;
CREATE TRIGGER dashboard_shortcuts_updated_at
BEFORE UPDATE ON dashboard_shortcuts
FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
COMMIT;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS telegram TEXT,
  ADD COLUMN IF NOT EXISTS lock_code TEXT,
  ADD COLUMN IF NOT EXISTS email_code TEXT,
  ADD COLUMN IF NOT EXISTS computer_code TEXT,
  ADD COLUMN IF NOT EXISTS work_access_code TEXT,
  ADD COLUMN IF NOT EXISTS two_fa TEXT,
  ADD COLUMN IF NOT EXISTS avatar_url TEXT,
  ADD COLUMN IF NOT EXISTS link1_url TEXT,
  ADD COLUMN IF NOT EXISTS link2_url TEXT,
  ADD COLUMN IF NOT EXISTS note_title TEXT,
  ADD COLUMN IF NOT EXISTS note_body TEXT;

CREATE OR REPLACE FUNCTION check_no_scheduled_shift_change_on_profile_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  effective_to_shift_id UUID;
BEGIN
  IF NEW.default_shift_id IS NOT DISTINCT FROM OLD.default_shift_id THEN
    RETURN NEW;
  END IF;
  SELECT to_shift_id INTO effective_to_shift_id
  FROM (
    SELECT ss.to_shift_id AS to_shift_id, ss.start_date
    FROM shift_swaps ss
    WHERE ss.user_id = NEW.id AND ss.status = 'approved'
      AND ss.start_date <= current_date
      AND (ss.end_date IS NULL OR current_date <= ss.end_date)
    UNION ALL
    SELECT cbt.to_shift_id, cbt.start_date
    FROM cross_branch_transfers cbt
    WHERE cbt.user_id = NEW.id AND cbt.status = 'approved'
      AND cbt.start_date <= current_date
      AND (cbt.end_date IS NULL OR current_date <= cbt.end_date)
  ) combined
  ORDER BY start_date DESC NULLS LAST
  LIMIT 1;
  IF effective_to_shift_id IS NOT NULL AND effective_to_shift_id = NEW.default_shift_id THEN
    RETURN NEW;
  END IF;
  IF EXISTS (
    SELECT 1 FROM shift_swaps s
    WHERE s.user_id = NEW.id AND s.status = 'approved' AND s.start_date >= current_date
    LIMIT 1
  ) THEN
    RAISE EXCEPTION 'ไม่สามารถเปลี่ยนกะได้ เนื่องจากมีรายการตั้งเวลาย้ายกะที่ยังมีผล — กรุณายกเลิกหรือรอให้ครบก่อน'
      USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (
    SELECT 1 FROM cross_branch_transfers c
    WHERE c.user_id = NEW.id AND c.status = 'approved' AND c.start_date >= current_date
    LIMIT 1
  ) THEN
    RAISE EXCEPTION 'ไม่สามารถเปลี่ยนกะได้ เนื่องจากมีรายการตั้งเวลาย้ายกะข้ามแผนกที่ยังมีผล — กรุณายกเลิกหรือรอให้ครบก่อน'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

UPDATE holidays SET leave_type = 'X' WHERE leave_type = 'HOLIDAY' OR leave_type IS NULL;
ALTER TABLE holidays ALTER COLUMN leave_type SET DEFAULT 'X';
UPDATE leave_types SET code = 'X' WHERE code = 'HOLIDAY';
CREATE OR REPLACE FUNCTION holidays_leave_type_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_role TEXT;
BEGIN
  SELECT role::TEXT INTO user_role FROM profiles WHERE id = auth.uid() LIMIT 1;
  IF user_role IN ('instructor'::text, 'staff'::text) THEN
    NEW.leave_type := 'X';
    NEW.is_quota_exempt := FALSE;
  END IF;
  RETURN NEW;
END;
$$;
CREATE OR REPLACE FUNCTION holidays_check_quota()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_days INT;
  v_cnt INT;
  v_total_after INT;
  v_new_counts BOOLEAN;
  v_scope_by_website BOOLEAN := true;
  v_total_people INT;
  v_current_booked INT;
  v_max_leave INT;
  v_primary_website_id UUID;
BEGIN
  IF NEW.status NOT IN ('approved', 'pending') THEN
    RETURN NEW;
  END IF;
  v_new_counts := (NEW.leave_type IS NULL OR NEW.leave_type = 'X') AND (NEW.is_quota_exempt IS NULL OR NEW.is_quota_exempt = false);
  IF v_new_counts THEN
    SELECT COALESCE(ms.max_holiday_days_per_person_per_month, 4) INTO v_max_days
    FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;
    IF v_max_days IS NULL THEN v_max_days := 4; END IF;
    SELECT COUNT(*)::INT INTO v_cnt
    FROM holidays h
    WHERE h.user_id = NEW.user_id
      AND h.holiday_date >= date_trunc('month', NEW.holiday_date)::date
      AND h.holiday_date < date_trunc('month', NEW.holiday_date)::date + interval '1 month'
      AND h.status IN ('approved', 'pending')
      AND (h.leave_type IS NULL OR h.leave_type = 'X')
      AND (h.is_quota_exempt IS NULL OR h.is_quota_exempt = false)
      AND (TG_OP <> 'UPDATE' OR h.id <> NEW.id);
    v_total_after := v_cnt + 1;
    IF v_total_after > v_max_days THEN
      RAISE EXCEPTION 'เกินกติกากลาง: แต่ละคนจองวันหยุดได้สูงสุด % วัน/เดือน (คนนี้จะมี % วันในเดือนนี้)', v_max_days, v_total_after
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF NEW.is_quota_exempt = true OR (NEW.leave_type IS NOT NULL AND NEW.leave_type <> 'X') THEN
    RETURN NEW;
  END IF;
  SELECT COALESCE(ms.scope_holiday_quota_by_website, true) INTO v_scope_by_website
  FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;
  SELECT wa.website_id INTO v_primary_website_id
  FROM website_assignments wa WHERE wa.user_id = NEW.user_id AND wa.is_primary = true LIMIT 1;
  IF v_scope_by_website AND v_primary_website_id IS NOT NULL THEN
    SELECT COUNT(*)::INT INTO v_total_people
    FROM profiles p
    INNER JOIN website_assignments wa ON wa.user_id = p.id AND wa.is_primary = true AND wa.website_id = v_primary_website_id
    WHERE p.default_branch_id = NEW.branch_id AND p.default_shift_id = NEW.shift_id
      AND (p.active IS NULL OR p.active = true)
      AND (
        (NEW.user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
        OR (NEW.user_group = 'STAFF' AND p.role = 'staff'::app_role)
        OR (NEW.user_group = 'MANAGER' AND p.role = 'manager'::app_role)
      );
  ELSE
    SELECT COUNT(*)::INT INTO v_total_people
    FROM profiles p
    WHERE p.default_branch_id = NEW.branch_id AND p.default_shift_id = NEW.shift_id
      AND (p.active IS NULL OR p.active = true)
      AND (
        (NEW.user_group = 'INSTRUCTOR' AND p.role IN ('instructor'::app_role, 'instructor_head'::app_role))
        OR (NEW.user_group = 'STAFF' AND p.role = 'staff'::app_role)
        OR (NEW.user_group = 'MANAGER' AND p.role = 'manager'::app_role)
      );
  END IF;
  SELECT MIN(hqt.max_leave) INTO v_max_leave
  FROM holiday_quota_tiers hqt
  WHERE hqt.dimension = 'combined'
    AND (hqt.user_group = NEW.user_group OR hqt.user_group IS NULL)
    AND v_total_people <= hqt.max_people;
  IF v_max_leave IS NULL THEN
    RETURN NEW;
  END IF;
  IF v_scope_by_website AND v_primary_website_id IS NOT NULL THEN
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM holidays h
    INNER JOIN website_assignments wa ON wa.user_id = h.user_id AND wa.is_primary = true AND wa.website_id = v_primary_website_id
    WHERE h.holiday_date = NEW.holiday_date
      AND h.branch_id = NEW.branch_id AND h.shift_id = NEW.shift_id AND h.user_group = NEW.user_group
      AND h.status IN ('approved', 'pending') AND (h.leave_type IS NULL OR h.leave_type = 'X') AND (h.is_quota_exempt IS NULL OR h.is_quota_exempt = false)
      AND (TG_OP <> 'UPDATE' OR h.id <> NEW.id);
  ELSE
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM holidays h
    WHERE h.holiday_date = NEW.holiday_date
      AND h.branch_id = NEW.branch_id AND h.shift_id = NEW.shift_id AND h.user_group = NEW.user_group
      AND h.status IN ('approved', 'pending') AND (h.leave_type IS NULL OR h.leave_type = 'X') AND (h.is_quota_exempt IS NULL OR h.is_quota_exempt = false)
      AND (TG_OP <> 'UPDATE' OR h.id <> NEW.id);
  END IF;
  v_current_booked := v_current_booked + 1;
  IF v_current_booked > v_max_leave THEN
    RAISE EXCEPTION 'โควต้าวันนี้เต็มแล้ว: ในกลุ่มแผนกกะเดียวกันหยุดได้สูงสุด % คน/วัน (วันนี้มี % คนแล้ว)', v_max_leave, v_current_booked - 1
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TABLE IF NOT EXISTS third_party_providers (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  provider_name text NOT NULL,
  provider_code text,
  logo_url text,
  merchant_id text,
  login_acc text,
  login_pass text,
  fund_pass text,
  pay_pass text,
  link_url text,
  fee_b numeric DEFAULT 0,
  fee_t numeric DEFAULT 0,
  fee_p numeric DEFAULT 0,
  fee_i numeric DEFAULT 0,
  withdraw_enabled boolean DEFAULT true,
  branch_id uuid REFERENCES branches(id) ON DELETE CASCADE,
  website_id uuid REFERENCES websites(id) ON DELETE SET NULL,
  visible_roles text[],
  sort_order int DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_third_party_created ON third_party_providers (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_third_party_sort ON third_party_providers (sort_order);
CREATE INDEX IF NOT EXISTS idx_third_party_branch ON third_party_providers (branch_id);
CREATE INDEX IF NOT EXISTS idx_third_party_website ON third_party_providers (website_id);
CREATE TRIGGER third_party_providers_updated_at
  BEFORE UPDATE ON third_party_providers
  FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
ALTER TABLE third_party_providers ENABLE ROW LEVEL SECURITY;
CREATE POLICY third_party_providers_select ON third_party_providers
FOR SELECT TO authenticated
USING (
  (is_admin() OR is_manager() OR is_instructor_head())
  OR (
    (branch_id IS NULL OR branch_id IN (SELECT user_branch_ids(auth.uid())))
    AND (website_id IS NULL OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid()))
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR my_role() = ANY(visible_roles))
  )
);
CREATE POLICY third_party_providers_insert ON third_party_providers
FOR INSERT TO authenticated
WITH CHECK (
  is_admin()
  OR ((is_manager() OR is_instructor_head()) AND (branch_id IS NULL OR branch_id = my_branch_id()))
);
CREATE POLICY third_party_providers_update ON third_party_providers
FOR UPDATE TO authenticated
USING (
  is_admin()
  OR ((is_manager() OR is_instructor_head()) AND (branch_id IS NULL OR branch_id = my_branch_id()))
)
WITH CHECK (
  is_admin()
  OR ((is_manager() OR is_instructor_head()) AND (branch_id IS NULL OR branch_id = my_branch_id()))
);
CREATE POLICY third_party_providers_delete ON third_party_providers
FOR DELETE TO authenticated
USING (
  is_admin()
  OR ((is_manager() OR is_instructor_head()) AND (branch_id IS NULL OR branch_id = my_branch_id()))
);

UPDATE third_party_providers
SET website_id = (SELECT id FROM websites ORDER BY name LIMIT 1)
WHERE website_id IS NULL
  AND EXISTS (SELECT 1 FROM websites LIMIT 1);
ALTER TABLE third_party_providers DROP CONSTRAINT IF EXISTS third_party_providers_website_id_fkey;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM third_party_providers WHERE website_id IS NULL) THEN
    ALTER TABLE third_party_providers ALTER COLUMN website_id SET NOT NULL;
  END IF;
END $$;
ALTER TABLE third_party_providers
  ADD CONSTRAINT third_party_providers_website_id_fkey
  FOREIGN KEY (website_id) REFERENCES websites(id) ON DELETE CASCADE;
DROP POLICY IF EXISTS third_party_providers_select ON third_party_providers;
DROP POLICY IF EXISTS third_party_providers_insert ON third_party_providers;
DROP POLICY IF EXISTS third_party_providers_update ON third_party_providers;
DROP POLICY IF EXISTS third_party_providers_delete ON third_party_providers;
CREATE POLICY third_party_providers_select ON third_party_providers
FOR SELECT TO authenticated
USING (
  (is_admin() OR is_manager() OR is_instructor_head())
  OR (
    website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid())
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR my_role() = ANY(visible_roles))
  )
);
CREATE POLICY third_party_providers_insert ON third_party_providers
FOR INSERT TO authenticated
WITH CHECK (
  (is_admin() OR is_manager() OR is_instructor_head())
  AND (
    is_admin()
    OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid())
  )
);
CREATE POLICY third_party_providers_update ON third_party_providers
FOR UPDATE TO authenticated
USING (
  (is_admin() OR is_manager() OR is_instructor_head())
  AND (
    is_admin()
    OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid())
  )
)
WITH CHECK (
  (is_admin() OR is_manager() OR is_instructor_head())
  AND (
    is_admin()
    OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid())
  )
);
CREATE POLICY third_party_providers_delete ON third_party_providers
FOR DELETE TO authenticated
USING (
  (is_admin() OR is_manager() OR is_instructor_head())
  AND (
    is_admin()
    OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid())
  )
);

ALTER TABLE schedule_cards ADD COLUMN IF NOT EXISTS icon_url TEXT;

ALTER TABLE third_party_providers
  DROP COLUMN IF EXISTS login_acc,
  DROP COLUMN IF EXISTS login_pass,
  DROP COLUMN IF EXISTS fund_pass,
  DROP COLUMN IF EXISTS pay_pass,
  DROP COLUMN IF EXISTS fee_b,
  DROP COLUMN IF EXISTS fee_t,
  DROP COLUMN IF EXISTS fee_p,
  DROP COLUMN IF EXISTS fee_i,
  DROP COLUMN IF EXISTS withdraw_enabled;

CREATE OR REPLACE FUNCTION book_meal_break(
  p_work_date DATE,
  p_round_key TEXT,
  p_slot_start_ts TIMESTAMPTZ,
  p_slot_end_ts TIMESTAMPTZ
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_branch_id UUID;
  v_shift_id UUID;
  v_website_id UUID;
  v_shift_start_ts TIMESTAMPTZ;
  v_shift_end_ts TIMESTAMPTZ;
  v_meal_count INT;
  v_cap JSONB;
  v_log_id UUID;
  v_ug TEXT;
BEGIN
  SELECT p.default_branch_id, p.default_shift_id INTO v_branch_id, v_shift_id FROM profiles p WHERE p.id = v_uid LIMIT 1;
  SELECT wa.website_id INTO v_website_id FROM website_assignments wa WHERE wa.user_id = v_uid AND wa.is_primary = true LIMIT 1;
  IF v_branch_id IS NULL OR v_shift_id IS NULL OR v_website_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_branch_shift_website');
  END IF;
  v_ug := (SELECT my_user_group());
  IF v_ug IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'invalid_user_group'); END IF;
  IF now() < (p_work_date + (SELECT start_time FROM shifts WHERE id = v_shift_id))::TIMESTAMPTZ THEN
    RETURN jsonb_build_object('ok', false, 'error', 'before_shift_start');
  END IF;
  SELECT COUNT(*)::INT INTO v_meal_count FROM break_logs WHERE user_id = v_uid AND break_date = p_work_date AND break_type = 'MEAL' AND status = 'active';
  IF v_meal_count >= COALESCE((SELECT (rounds_json->>'max_per_work_date')::INT FROM meal_settings WHERE is_enabled = true ORDER BY effective_from DESC LIMIT 1), 2) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'max_meals_reached');
  END IF;
  IF EXISTS (SELECT 1 FROM break_logs WHERE user_id = v_uid AND break_date = p_work_date AND round_key = p_round_key AND break_type = 'MEAL' AND status = 'active') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_booked_this_round');
  END IF;
  SELECT (p_work_date + s.start_time)::TIMESTAMPTZ, (p_work_date + s.end_time)::TIMESTAMPTZ INTO v_shift_start_ts, v_shift_end_ts FROM shifts s WHERE s.id = v_shift_id LIMIT 1;
  IF v_shift_end_ts <= v_shift_start_ts THEN v_shift_end_ts := (p_work_date + 1 + (SELECT end_time FROM shifts WHERE id = v_shift_id))::TIMESTAMPTZ; END IF;
  IF p_slot_start_ts < v_shift_start_ts OR p_slot_start_ts >= v_shift_end_ts
     OR p_slot_end_ts <= v_shift_start_ts OR p_slot_end_ts > v_shift_end_ts THEN
    RETURN jsonb_build_object('ok', false, 'error', 'slot_outside_shift');
  END IF;
  v_cap := get_meal_capacity_break_logs(v_branch_id, v_shift_id, v_website_id, p_work_date, p_round_key, p_slot_start_ts);
  IF (v_cap->>'is_full')::boolean THEN RETURN jsonb_build_object('ok', false, 'error', 'slot_full'); END IF;
  INSERT INTO break_logs (user_id, branch_id, shift_id, website_id, break_date, started_at, ended_at, status, user_group, break_type, round_key)
  VALUES (v_uid, v_branch_id, v_shift_id, v_website_id, p_work_date, p_slot_start_ts, p_slot_end_ts, 'active', v_ug, 'MEAL', p_round_key)
  RETURNING id INTO v_log_id;
  INSERT INTO audit_logs (actor_id, action, entity, entity_id, details_json, summary_text)
  VALUES (v_uid, 'meal_book', 'meal_booking', v_log_id,
    jsonb_build_object('work_date', p_work_date, 'round_key', p_round_key, 'slot_start_ts', p_slot_start_ts, 'slot_end_ts', p_slot_end_ts),
    'จองพักอาหาร ' || to_char(p_work_date, 'YYYY-MM-DD'));
  RETURN jsonb_build_object('ok', true, 'id', v_log_id);
END;
$$;

CREATE OR REPLACE VIEW shift_change_history_view
WITH (security_invoker = true)
AS
SELECT
  'swap'::text AS type,
  id, user_id, start_date, end_date,
  status::text AS status,
  created_at,
  branch_id AS from_branch_id,
  branch_id AS to_branch_id,
  from_shift_id, to_shift_id
FROM shift_swaps
UNION ALL
SELECT
  'transfer'::text,
  id, user_id, start_date, end_date,
  status::text AS status,
  created_at,
  from_branch_id, to_branch_id,
  from_shift_id, to_shift_id
FROM cross_branch_transfers;
GRANT SELECT ON shift_change_history_view TO authenticated;

