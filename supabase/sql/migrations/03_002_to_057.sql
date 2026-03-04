-- ==============================================================================
-- 03: รวม 002-010, 011-057 (รันหลัง 01 และ 02)
-- ลำดับ: 002 ตั้งเว็บหลัก → ... → 010 manager → 011 หัวหน้าเห็นทุกคน → ... → 057 หัวหน้า=ผู้จัดการ
-- ==============================================================================

-- ---------- 002_set_primary_website_instructor_head.sql ----------
-- ตั้งเว็บหลัก: อนุญาตแอดมิน และหัวหน้าสาขา (เฉพาะผู้ใช้ในสาขาของตัวเอง)

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

-- ---------- 003_duty_roles_instructor_head.sql ----------
-- duty_roles: ให้หัวหน้าสาขาเพิ่ม/แก้/ลบ หน้าที่ได้เฉพาะสาขาของตัวเอง
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

-- duty_assignments: ให้หัวหน้าสาขาจัดหน้าที่ (สุ่ม/ลาก/ล้าง) ได้เฉพาะสาขาของตัวเอง
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


-- ---------- 004_group_links_instructor_head_always_see_branch.sql ----------
-- ========== 004: group_links — หัวหน้าผู้สอนเห็นทุกลิงก์ในสาขาของตัวเอง ==========
-- เป้าหมาย: แก้ RLS ให้หัวหน้าผู้สอนเห็นและแก้ไขลิงก์กลุ่มในสาขาของตัวเองได้เสมอ
--          แม้จะตั้ง "แสดงให้ตำแหน่ง" เป็นแค่ staff/instructor (ไม่เลือกหัวหน้าผู้สอน)
-- กระทบ: ตาราง group_links (SELECT policy เท่านั้น), role instructor_head
-- เหตุผล: หัวหน้าต้องเห็นทุกกลุ่มที่ตัวเองสร้าง และต้องแก้ไขได้

DROP POLICY IF EXISTS group_links_select ON group_links;
CREATE POLICY group_links_select ON group_links FOR SELECT TO authenticated USING (
  is_admin()
  OR (is_instructor_head() AND (branch_id IS NULL OR branch_id = my_branch_id()))
  OR (
    (branch_id IS NULL OR branch_id = my_branch_id())
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles))
  )
);


-- ---------- 005_holiday_quota_tiers_and_head_see_all.sql ----------
-- ========== 005: กติกาโควต้าวันหยุดแบบชั้น (tiers) + หัวหน้าเห็นทุกสาขา ==========
-- เป้าหมาย:
--   1) ตารางกติกาโควตาแบบชั้น: ถ้าจำนวนคน <= max_people จะหยุดได้สูงสุด max_leave คน (แยกตาม dimension + user_group)
--   2) หัวหน้าผู้สอนเห็นตารางวันหยุดทุกสาขา (แก้ไขได้เฉพาะสาขาตัวเอง)
-- กระทบ: ตารางใหม่ holiday_quota_tiers, policies ของ holidays
-- หมายเหตุ: โควต้าแยกตามกลุ่ม (INSTRUCTOR vs STAFF) ไม่นับรวมกัน

-- ตารางกติกาโควต้าวันหยุด (ชั้น): dimension = branch | shift | website, user_group = INSTRUCTOR | STAFF
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

-- หัวหน้าผู้สอนเห็นวันหยุดทุกสาขา (แก้ไขได้เฉพาะสาขาตัวเอง — ใช้ policy update เดิม)
DROP POLICY IF EXISTS holidays_select ON holidays;
CREATE POLICY holidays_select ON holidays FOR SELECT TO authenticated USING (
  is_admin()
  OR is_instructor_head()
  OR (my_branch_id() IS NOT NULL AND branch_id = my_branch_id() AND user_group = my_user_group())
);


-- ---------- 006_holidays_admin_head_insert_update_delete.sql ----------
-- ========== 006: แอดมินและหัวหน้าสามารถเพิ่ม/แก้ไข/ลบวันหยุดให้พนักงานได้ ==========
-- เป้าหมาย:
--   - แอดมิน (admin): เลือก/เพิ่ม/แก้ไข/ลบ วันหยุดให้ทุกคนได้
--   - หัวหน้าผู้สอน (instructor_head): เลือก/เพิ่ม/แก้ไข/ลบ วันหยุดให้พนักงานทุกสาขาได้
--   - พนักงาน/ผู้สอน: เฉพาะของตัวเอง (insert ตัวเอง, update/delete แค่ของตัวเอง)
-- กระทบ: policies ของ holidays (INSERT, UPDATE, DELETE)

-- INSERT: แอดมินหรือหัวหน้าสามารถ insert แถวใดก็ได้ (เพิ่มวันหยุดให้ใครก็ได้); คนอื่น insert ได้เฉพาะ user_id = ตัวเอง
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

-- UPDATE: แอดมินหรือหัวหน้าสามารถแก้ไขแถวใดก็ได้; คนอื่นแก้ได้เฉพาะแถวที่ user_id = ตัวเอง
DROP POLICY IF EXISTS holidays_update ON holidays;
CREATE POLICY holidays_update ON holidays FOR UPDATE TO authenticated USING (
  is_admin()
  OR is_instructor_head()
  OR user_id = auth.uid()
);

-- DELETE: แอดมินหรือหัวหน้าสามารถลบแถวใดก็ได้; คนอื่นลบได้เฉพาะแถวที่ user_id = ตัวเอง
DROP POLICY IF EXISTS holidays_delete ON holidays;
CREATE POLICY holidays_delete ON holidays FOR DELETE TO authenticated USING (
  is_admin()
  OR is_instructor_head()
  OR user_id = auth.uid()
);


-- ---------- 007_profiles_select_same_branch_colleagues.sql ----------
-- ========== 007: ให้ผู้สอนและพนักงานออนไลน์เห็นรายชื่อเพื่อนในสาขาเดียวกัน ==========
-- เป้าหมาย: ตารางวันหยุด (และหน้าอื่นที่โหลด profiles ตามสาขา) จะแสดงเพื่อนในสาขาได้
-- สาเหตุเดิม: RLS profiles_select ให้ staff เห็นเฉพาะ id = auth.uid() จึงเห็นแค่ตัวเอง
-- กระทบ: policy profiles_select

DROP POLICY IF EXISTS profiles_select ON profiles;
CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated USING (
  is_admin()
  OR id = auth.uid()
  OR is_instructor_or_admin()
  OR (is_instructor_head() AND (id = auth.uid() OR (default_branch_id = my_branch_id() AND role IN ('instructor', 'staff'))))
  OR (my_branch_id() IS NOT NULL AND default_branch_id = my_branch_id() AND role IN ('instructor', 'staff', 'instructor_head'))
);


-- ---------- 008_group_link_branches.sql ----------
-- ========== 008: group_links หลายสาขา (group_link_branches) ==========
-- เป้าหมาย: ให้ลิงก์กลุ่มเลือกได้หลายสาขา (เมื่อเลือกหลายสาขา ใช้ group_link_branches; สาขาเดียวหรือทั้งหมดยังใช้ branch_id)
-- กระทบ: group_links (RLS SELECT), ตารางใหม่ group_link_branches

CREATE TABLE IF NOT EXISTS group_link_branches (
  group_link_id UUID NOT NULL REFERENCES group_links(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  PRIMARY KEY (group_link_id, branch_id)
);
CREATE INDEX IF NOT EXISTS idx_group_link_branches_link ON group_link_branches(group_link_id);
CREATE INDEX IF NOT EXISTS idx_group_link_branches_branch ON group_link_branches(branch_id);
-- RLS: เห็นลิงก์ถ้า branch_id ตรง หรือ branch_id IS NULL (ทั้งหมด) หรือ สาขาของฉันอยู่ใน group_link_branches
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

-- หัวหน้าสามารถสร้าง/อัปเดตลิงก์ที่ branch_id = null (แล้วใส่สาขาใน group_link_branches)
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


-- ---------- 009_file_vault_allow_duplicate_path.sql ----------
-- ========== 009: file_vault อนุญาต path ซ้ำ (หนึ่งไฟล์เห็นได้หลายสาขา/หลายเว็บ) ==========
-- เป้าหมาย: ให้อัปโหลดหนึ่งไฟล์แล้วเลือกหลายสาขา/หลายเว็บได้ (insert หลายแถว path เดียวกัน)
-- กระทบ: ตาราง file_vault (ลบ UNIQUE บน file_path)

ALTER TABLE file_vault DROP CONSTRAINT IF EXISTS file_vault_file_path_key;


-- ---------- 010_add_manager_role.sql ----------
-- ========== 010: บทบาท manager (ผู้จัดการ) + กลุ่ม MANAGER ==========
-- ⚠️ รันไฟล์ 010a_add_manager_enum_only.sql ก่อน แล้วค่อยรันไฟล์นี้
-- (PostgreSQL ต้อง commit ค่า enum ใหม่ก่อนถึงจะใช้ในฟังก์ชัน/RLS ได้)
--
-- เป้าหมาย:
--   - Role hierarchy: admin > manager > instructor_head > instructor > staff
--   - Manager ทำได้เหมือน admin ทุกสาขา/กะ/เว็บ ยกเว้น: สร้าง/แก้/ลบ admin, สร้าง/แก้/ลบ manager อื่น, เปลี่ยน role เป็น admin/manager
--   - Manager เป็นพนักงานด้วย: ลงเวลา, พัก, วันหยุด, สลับกะ, ย้ายกะ
--   - โควต้าวันหยุด/พัก: กลุ่ม MANAGER แยกจาก INSTRUCTOR/STAFF
-- กระทบ: app_role, user_group checks, profiles RLS, ตารางที่ admin ควบคุม, ตารางพนักงาน

-- 1) Helper functions
CREATE OR REPLACE FUNCTION is_manager()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'manager'::app_role);
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION is_admin_or_manager()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin'::app_role, 'manager'::app_role));
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- พนักงาน = ลงเวลา/พัก/วันหยุดได้ (manager, instructor_head, instructor, staff)
CREATE OR REPLACE FUNCTION is_employee_role()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('manager'::app_role, 'instructor_head'::app_role, 'instructor'::app_role, 'staff'::app_role));
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- 3) my_branch_id: manager มี default_branch_id สำหรับใช้เป็นพนักงาน
CREATE OR REPLACE FUNCTION my_branch_id()
RETURNS UUID AS $$
  SELECT p.default_branch_id FROM profiles p
  WHERE p.id = auth.uid() AND p.role IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role, 'manager'::app_role) AND p.default_branch_id IS NOT NULL
  LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- 4) is_staff_or_instructor: รวม manager สำหรับ INSERT ลง work_logs/break_logs/holidays ฯลฯ
CREATE OR REPLACE FUNCTION is_staff_or_instructor()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role, 'manager'::app_role));
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- 5) my_user_group: manager => 'MANAGER'
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

-- 6) user_branch_ids: manager เห็นทุกสาขา (เหมือน admin)
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

-- 7) profiles: constraint ให้ manager/instructor_head/instructor/staff มี default_branch_id
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_instructor_staff_must_have_branch;
ALTER TABLE profiles ADD CONSTRAINT profiles_instructor_staff_must_have_branch CHECK (
  (role IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role, 'manager'::app_role) AND default_branch_id IS NOT NULL)
  OR (role NOT IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role, 'manager'::app_role))
);

-- 8) user_group: เพิ่ม MANAGER ในตารางที่ใช้ user_group
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

-- 9) PROFILES RLS
-- SELECT: manager เห็นทุก profile (สำหรับ UI จัดการ)
DROP POLICY IF EXISTS profiles_select ON profiles;
CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated USING (
  is_admin() OR is_manager() OR id = auth.uid()
  OR is_instructor_or_admin() OR (is_instructor_head() AND (id = auth.uid() OR (default_branch_id = my_branch_id() AND role IN ('instructor'::app_role, 'staff'::app_role))))
  OR (my_branch_id() IS NOT NULL AND default_branch_id = my_branch_id() AND role IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role))
);

-- UPDATE: ห้าม set role เป็น admin หรือ manager เว้นแต่ caller เป็น admin (ใช้ trigger)
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

-- Manager อัปเดตได้: ตัวเอง (id = auth.uid()) หรือ profile ที่ role IN (instructor_head, instructor, staff) เท่านั้น
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

-- Admin ยังคง ALL (insert/delete ผ่าน service role หรือ admin-only policy ถ้ามี)
DROP POLICY IF EXISTS profiles_all ON profiles;
CREATE POLICY profiles_all ON profiles FOR ALL TO authenticated USING (is_admin());

-- 10) ตารางที่ admin ควบคุมทั้งหมด: อนุญาต manager เช่นกัน (branches, shifts, break_rules, ฯลฯ)
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

-- group_links: manager เห็นทุกลิงก์ (เหมือน admin)
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

-- holiday_booking_config
DROP POLICY IF EXISTS holiday_booking_config_all ON holiday_booking_config;
CREATE POLICY holiday_booking_config_all ON holiday_booking_config FOR ALL TO authenticated USING (is_admin_or_manager());

-- schedule_cards SELECT (manager เห็นทุกการ์ดเหมือน admin)
DROP POLICY IF EXISTS schedule_cards_select ON schedule_cards;
CREATE POLICY schedule_cards_select ON schedule_cards FOR SELECT TO authenticated USING (
  is_admin_or_manager()
  OR (
    (branch_id IS NULL OR branch_id IN (SELECT user_branch_ids(auth.uid())))
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles))
    AND (website_id IS NULL OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid()))
  )
);

-- websites, website_assignments: manager เหมือน admin
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

-- audit_logs: manager อ่านได้
DROP POLICY IF EXISTS audit_logs_select ON audit_logs;
CREATE POLICY audit_logs_select ON audit_logs FOR SELECT TO authenticated USING (
  is_admin_or_manager() OR (actor_id = auth.uid()) OR is_instructor_or_admin()
);

-- 11) Employee tables: manager INSERT ตัวเอง, SELECT ทั้งหมด, UPDATE/DELETE อนุมัติได้
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

-- holidays: 006 policies - เพิ่ม manager
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

-- duty_roles / duty_assignments SELECT
DROP POLICY IF EXISTS duty_roles_select ON duty_roles;
CREATE POLICY duty_roles_select ON duty_roles FOR SELECT TO authenticated USING (
  is_admin_or_manager() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
DROP POLICY IF EXISTS duty_assignments_select ON duty_assignments;
CREATE POLICY duty_assignments_select ON duty_assignments FOR SELECT TO authenticated USING (
  is_admin_or_manager() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);

-- monthly_roster SELECT
DROP POLICY IF EXISTS monthly_roster_select ON monthly_roster;
CREATE POLICY monthly_roster_select ON monthly_roster FOR SELECT TO authenticated USING (
  is_admin_or_manager() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);
DROP POLICY IF EXISTS roster_status_select ON monthly_roster_status;
CREATE POLICY roster_status_select ON monthly_roster_status FOR SELECT TO authenticated USING (
  is_admin_or_manager() OR branch_id IN (SELECT user_branch_ids(auth.uid()))
);

-- break_rules SELECT: manager ใช้กติกาตาม user_group
DROP POLICY IF EXISTS break_rules_select ON break_rules;
CREATE POLICY break_rules_select ON break_rules FOR SELECT TO authenticated USING (
  true
);

-- holiday_quotas SELECT
DROP POLICY IF EXISTS holiday_quotas_select ON holiday_quotas;
CREATE POLICY holiday_quotas_select ON holiday_quotas FOR SELECT TO authenticated USING (true);

-- 12) Indexes for performance (breaks/holidays list)
CREATE INDEX IF NOT EXISTS idx_break_logs_branch_shift_date_status ON break_logs(branch_id, shift_id, break_date, status);
CREATE INDEX IF NOT EXISTS idx_holidays_branch_shift_date_status ON holidays(branch_id, shift_id, holiday_date, status);


-- ---------- 011_head_instructor_global_visibility.sql ----------
-- ========== 011: instructor_head + instructor เห็นทุกคน (ทุกสาขา/กะ) แต่เขียนเฉพาะของตัวเอง ==========
-- เป้าหมาย:
--   - หัวหน้าผู้สอนและผู้สอน: SELECT ได้ทุก profile, holidays, break_logs, work_logs (ทุกสาขา)
--   - เขียน (INSERT/UPDATE/DELETE): เฉพาะของตัวเองเท่านั้น ไม่ให้สร้าง/แก้วันหยุดหรือพักให้คนอื่น
--   - Staff ยังคงเห็นเฉพาะสาขาของตัวเอง (ไม่เปลี่ยน)
--   - ผู้จัดการ (manager) เห็นได้ทุกคนอยู่แล้ว

-- 1) Helper: is_instructor() (role = instructor เท่านั้น)
CREATE OR REPLACE FUNCTION is_instructor()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'instructor'::app_role);
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- 2) can_global_read_employees(): admin, manager, instructor_head, instructor เห็นทุกพนักงาน/ทุกสาขา
CREATE OR REPLACE FUNCTION can_global_read_employees()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role IN ('admin'::app_role, 'manager'::app_role, 'instructor_head'::app_role, 'instructor'::app_role)
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- 3) is_employee_self(uid): ใช้ตรวจว่าแถวเป็นของตัวเอง
CREATE OR REPLACE FUNCTION is_employee_self(uid UUID)
RETURNS BOOLEAN AS $$
  SELECT auth.uid() = uid;
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- 4) PROFILES: SELECT ให้ head + instructor เห็นทุก profile
DROP POLICY IF EXISTS profiles_select ON profiles;
CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated USING (
  can_global_read_employees()
  OR id = auth.uid()
  OR (my_branch_id() IS NOT NULL AND default_branch_id = my_branch_id() AND role IN ('instructor'::app_role, 'staff'::app_role, 'instructor_head'::app_role))
);

-- 5) PROFILES: UPDATE — instructor_head แก้ได้เฉพาะตัวเอง (ไม่ให้แก้ profile คนอื่น)
DROP POLICY IF EXISTS profiles_update_branch_head ON profiles;
CREATE POLICY profiles_update_branch_head ON profiles FOR UPDATE TO authenticated USING (
  is_admin() OR (is_instructor_head() AND id = auth.uid())
);

-- 6) HOLIDAYS: SELECT — head + instructor เห็นทุกแถว
DROP POLICY IF EXISTS holidays_select ON holidays;
CREATE POLICY holidays_select ON holidays FOR SELECT TO authenticated USING (
  can_global_read_employees()
  OR (my_branch_id() IS NOT NULL AND branch_id = my_branch_id() AND user_group = my_user_group())
);

-- 7) HOLIDAYS: INSERT — head/instructor ได้เฉพาะ user_id = ตัวเอง (admin/manager ยังทำได้ทุกคน)
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

-- 8) HOLIDAYS: UPDATE/DELETE — head/instructor ได้เฉพาะแถวของตัวเอง
DROP POLICY IF EXISTS holidays_update ON holidays;
CREATE POLICY holidays_update ON holidays FOR UPDATE TO authenticated USING (
  is_admin() OR is_manager() OR user_id = auth.uid()
);

DROP POLICY IF EXISTS holidays_delete ON holidays;
CREATE POLICY holidays_delete ON holidays FOR DELETE TO authenticated USING (
  is_admin() OR is_manager() OR user_id = auth.uid()
);

-- 9) BREAK_LOGS: SELECT — head + instructor เห็นทุกแถว
DROP POLICY IF EXISTS break_logs_select ON break_logs;
CREATE POLICY break_logs_select ON break_logs FOR SELECT TO authenticated USING (
  can_global_read_employees()
  OR user_id = auth.uid()
  OR (my_branch_id() IS NOT NULL AND branch_id IN (SELECT user_branch_ids(auth.uid())))
);

-- break_logs INSERT/UPDATE อยู่แล้ว: ใส่เฉพาะของตัวเอง หรือ admin/manager (ไม่เปลี่ยน)

-- 10) WORK_LOGS: SELECT — head + instructor เห็นทุกแถว (สำหรับหน้ารายการลงเวลา)
DROP POLICY IF EXISTS work_logs_select ON work_logs;
CREATE POLICY work_logs_select ON work_logs FOR SELECT TO authenticated USING (
  can_global_read_employees()
  OR user_id = auth.uid()
  OR (my_branch_id() IS NOT NULL AND branch_id IN (SELECT user_branch_ids(auth.uid())))
);

-- 11) Indexes for list queries (ถ้ามีอยู่แล้วจะไม่สร้างซ้ำ)
CREATE INDEX IF NOT EXISTS idx_break_logs_break_date_status ON break_logs(break_date, status);
CREATE INDEX IF NOT EXISTS idx_holidays_holiday_date_status ON holidays(holiday_date, status);


-- ---------- 012_update_get_email_for_login_use_auth_users.sql ----------
-- 012: ปรับ get_email_for_login ให้ใช้อีเมลจาก auth.users เป็นหลัก
-- ปัญหาที่แก้:
--   - ก่อนหน้านี้ฟังก์ชันใช้ email จากตาราง profiles เท่านั้น
--   - ถ้าเปลี่ยนอีเมลในหน้า Authentication (auth.users) แต่ไม่ได้อัปเดต profiles.email จะล็อกอินไม่ผ่าน (400 / invalid credentials)
-- แนวทางใหม่:
--   - JOIN auth.users กับ profiles ตาม id
--   - คืนค่า auth.users.email เสมอ (เป็นค่า canonical สำหรับ signInWithPassword)
--   - ค้นหาจาก:
--       * display_name (profiles)
--       * profiles.email
--       * auth.users.email

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



-- ---------- 013_profiles_guard_allow_service_role.sql ----------
-- ========== 013: ให้ backend (service role) ตั้ง role admin/manager ได้ ==========
-- ปัญหา: เวลาแอดมินสร้างผู้ใช้ admin/manager ผ่าน API, updateProfile ใช้ Service Role Key
--        ทำให้ auth.uid() = null → is_admin() = false → trigger ยกเลิกการอัปเดต → role ค้างเป็นค่า default (staff)
-- แก้: ตรวจสอบเฉพาะเมื่อมี "ผู้ใช้ล็อกอิน" (auth.uid() IS NOT NULL) — ถ้าเป็น service role (uid เป็น null) ให้ผ่าน

CREATE OR REPLACE FUNCTION profiles_guard_admin_manager_role()
RETURNS TRIGGER AS $$
BEGIN
  -- บล็อกเฉพาะเมื่อมีผู้ใช้ล็อกอินอยู่และไม่ใช่ admin (ถ้า auth.uid() เป็น null = เรียกจาก service role ให้ผ่าน)
  IF NEW.role IN ('admin'::app_role, 'manager'::app_role)
     AND auth.uid() IS NOT NULL
     AND NOT is_admin() THEN
    RAISE EXCEPTION 'ไม่มีสิทธิ์ตั้งบทบาทเป็น admin หรือ manager';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ---------- 014_holidays_head_manager_full_edit.sql ----------
-- ========== 014: หัวหน้าและผู้จัดการแก้ไขวันหยุดของทุกคนได้ (เหมือนแอดมิน) ==========
-- ปัญหา: migration 011 จำกัดให้หัวหน้าเขียนได้เฉพาะของตัวเอง ทำให้หัวหน้าแก้ไขวันหยุดตัวเองหรือคนอื่นไม่ได้
-- แก้: ให้ is_instructor_head() และ is_manager() มีสิทธิ์ INSERT/UPDATE/DELETE ทุกแถว (เหมือน admin)

-- INSERT: หัวหน้าสร้างวันหยุดให้ใครก็ได้ (คืนค่าเหมือน 010)
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

-- UPDATE / DELETE: หัวหน้าและผู้จัดการแก้ไข/ลบวันหยุดของใครก็ได้
DROP POLICY IF EXISTS holidays_update ON holidays;
CREATE POLICY holidays_update ON holidays FOR UPDATE TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head() OR user_id = auth.uid()
);

DROP POLICY IF EXISTS holidays_delete ON holidays;
CREATE POLICY holidays_delete ON holidays FOR DELETE TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head() OR user_id = auth.uid()
);


-- ---------- 015_meal_system.sql ----------
-- ========== 015: MEAL TIME BOOKING SYSTEM ==========
-- Workday = date of shift start; night shift slots after midnight belong to same workday.
-- Max 2 meals per workday; capacity by on-duty staff (holiday-aware); self-book only; cancel before slot start.

-- 1) meal_round_templates (rounds within a shift day, e.g. breakfast / lunch)
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
-- 2) meal_slot_templates (slots within a round)
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
-- 3) meal_concurrency_rules (capacity: when on_duty_count <= X, allow Y concurrent)
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
-- 4) meal_logs (bookings)
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
-- Trigger: max 2 bookings per (user_id, work_date)
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

-- ========== 5) get_meal_capacity ==========
-- Returns on_duty_count, max_concurrent, current_booked, is_full for a slot.
-- holiday_date = calendar date of slot (for night shift, slot after midnight uses next calendar day for holiday check).
-- On-duty = eligible staff (branch+shift+website, active, not on approved holiday that day) with last work_log = IN for work_date.
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

  -- Eligible staff: branch + shift + primary website, active, not on approved holiday on holiday_date
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
  -- Last log per user for work_date (logical_date)
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

  -- Rule: smallest max_staff_threshold >= on_duty_count
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
-- ========== 6) RLS ==========
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

-- meal_logs: SELECT admin/manager all; others own. INSERT user_id = auth.uid(). UPDATE/DELETE own and only when now() < slot_start_ts
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

-- ========== 7) RPC wrappers ==========
-- get_available_slots(work_date): returns rounds + slots with capacity and user's bookings for that workday
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

  -- Night shift: if end_time < start_time, shift ends next day
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
      -- Night shift: slot after midnight (slot time < shift start time) = next calendar day, same workday
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

-- book_meal: insert meal_log; checks shift_start_ts, meal_count < 2, capacity, slot in shift window
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

-- cancel_meal: set status cancelled or delete; only when now() < slot_start_ts (enforced in RLS; server re-checks)
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


-- ---------- 016_unify_meal_breaks.sql ----------
-- ========== 016: Unify meal booking with break_logs ==========
-- One data model: break_logs with break_type 'NORMAL' | 'MEAL'.
-- Meal config: meal_settings (rounds_json, max_per_work_date), meal_quota_rules (on_duty_threshold, max_concurrent).

-- 1) Extend break_logs for meal bookings
DO $$ BEGIN
  CREATE TYPE break_type_enum AS ENUM ('NORMAL', 'MEAL');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE break_logs ADD COLUMN IF NOT EXISTS break_type TEXT NOT NULL DEFAULT 'NORMAL'
  CHECK (break_type IN ('NORMAL', 'MEAL'));
ALTER TABLE break_logs ADD COLUMN IF NOT EXISTS round_key TEXT;
ALTER TABLE break_logs ADD COLUMN IF NOT EXISTS website_id UUID REFERENCES websites(id) ON DELETE SET NULL;
-- Unique: one meal booking per user per work_date per round
CREATE UNIQUE INDEX IF NOT EXISTS idx_break_logs_meal_user_date_round
  ON break_logs (user_id, break_date, round_key)
  WHERE break_type = 'MEAL' AND round_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_break_logs_meal_capacity
  ON break_logs (branch_id, shift_id, website_id, break_date, round_key)
  WHERE break_type = 'MEAL' AND status = 'active';

-- Trigger: max meal bookings per user per work_date (from meal_settings.max_per_work_date, default 2)
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

-- 2) meal_settings (single effective config; rounds_json = { max_per_work_date?: number, rounds: [{ key, name, slots: [{ start, end }] }] })
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

-- 3) meal_quota_rules (on_duty_threshold X → max_concurrent Y; same pattern as meal_concurrency_rules)
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

-- Seed default meal_settings if none
INSERT INTO meal_settings (effective_from, is_enabled, rounds_json)
SELECT CURRENT_DATE, true, '{"max_per_work_date":2,"rounds":[{"key":"round_0","name":"มื้อเช้า","slots":[{"start":"08:00","end":"08:30"},{"start":"08:30","end":"09:00"}]},{"key":"round_1","name":"มื้อกลางวัน","slots":[{"start":"12:00","end":"12:30"},{"start":"12:30","end":"13:00"}]}]}'::JSONB
WHERE NOT EXISTS (SELECT 1 FROM meal_settings LIMIT 1);

-- 4) RLS: break_logs MEAL - INSERT own, UPDATE/DELETE own only when now() < started_at
DROP POLICY IF EXISTS break_logs_insert ON break_logs;
CREATE POLICY break_logs_insert ON break_logs FOR INSERT TO authenticated WITH CHECK (
  user_id = auth.uid()
  AND (is_admin_or_manager() OR (is_staff_or_instructor() AND (branch_id = my_branch_id() OR branch_id IN (SELECT user_branch_ids(auth.uid())))))
  AND (break_type = 'NORMAL' OR (break_type = 'MEAL' AND round_key IS NOT NULL))
);

-- Allow update/delete own MEAL only when now() < started_at (slot not started)
DROP POLICY IF EXISTS break_logs_update ON break_logs;
CREATE POLICY break_logs_update ON break_logs FOR UPDATE TO authenticated USING (
  (break_type = 'NORMAL' AND (user_id = auth.uid() OR is_admin_or_manager()))
  OR (break_type = 'MEAL' AND user_id = auth.uid() AND now() < started_at)
  OR (break_type = 'MEAL' AND is_admin_or_manager())
);

-- SELECT: NORMAL as before; MEAL own or admin/manager
DROP POLICY IF EXISTS break_logs_select ON break_logs;
CREATE POLICY break_logs_select ON break_logs FOR SELECT TO authenticated USING (
  can_global_read_employees()
  OR user_id = auth.uid()
  OR (my_branch_id() IS NOT NULL AND branch_id IN (SELECT user_branch_ids(auth.uid())))
);

-- 5) RPC: get_meal_slots_unified(p_work_date) — uses meal_settings.rounds_json, break_logs (MEAL), meal_quota_rules, same on-duty logic
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

-- get_meal_capacity_break_logs: same logic as get_meal_capacity but count from break_logs (break_type=MEAL, round_key)
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

-- 6) RPC: book_meal_break — insert break_logs MEAL
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

-- 7) RPC: cancel_meal_break — set status = 'ended' when now() < started_at
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


-- ---------- 017_mass_shift_assignment.sql ----------
-- ========== 017: Mass shift assignment - restrict employee-initiated requests ==========
-- Goal:
--   - Disable staff/instructor ability to create shift_swaps / cross_branch_transfers themselves.
--   - Allow only admin / manager / instructor_head to insert these records (used by bulk assignment tools).

-- shift_swaps: allow inserts only for admin/manager/instructor_head
DROP POLICY IF EXISTS shift_swaps_insert ON shift_swaps;
CREATE POLICY shift_swaps_insert ON shift_swaps
  FOR INSERT TO authenticated
  WITH CHECK (
    is_admin_or_manager() OR is_instructor_head()
  );

-- cross_branch_transfers: allow inserts only for admin/manager/instructor_head
DROP POLICY IF EXISTS transfers_insert ON cross_branch_transfers;
CREATE POLICY transfers_insert ON cross_branch_transfers
  FOR INSERT TO authenticated
  WITH CHECK (
    is_admin_or_manager() OR is_instructor_head()
  );



-- ---------- 018_bulk_assignment_holiday_guard.sql ----------
-- ========== 018: Bulk shift assignment – holiday conflict guard + skipped_dates ==========
-- 1) Add skipped_dates to shift_swaps and cross_branch_transfers (for SKIP_DAYS mode)
-- 2) Allow instructor_head to insert/update/delete monthly_roster for their branch only
-- 3) RPC apply_bulk_assignment: recheck holidays server-side, skip conflict dates, write roster + swap/transfer rows

-- 1) skipped_dates: array of date strings (e.g. ["2025-02-10","2025-02-15"]) for days skipped due to holiday
ALTER TABLE shift_swaps
  ADD COLUMN IF NOT EXISTS skipped_dates JSONB DEFAULT NULL;

ALTER TABLE cross_branch_transfers
  ADD COLUMN IF NOT EXISTS skipped_dates JSONB DEFAULT NULL;

-- 2) monthly_roster: instructor_head can insert/update/delete for their branch only
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

-- 3) RPC: apply_bulk_assignment – rechecks holidays, skips conflict dates, updates roster and creates swap/transfer rows
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
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin','manager'));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head');
  IF NOT may_run AND NOT is_head THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can run bulk assignment';
  END IF;
  IF is_head AND NOT may_run THEN
    IF p_to_branch_id IS NULL OR p_to_branch_id != my_branch_id() THEN
      RAISE EXCEPTION 'Instructor head can only assign to their own branch';
    END IF;
  END IF;

  -- Build conflict map: for each user, set of holiday dates (approved/pending)
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

    -- Current roster for this user in range (to get from_branch/from_shift and to update)
    SELECT r.branch_id, r.shift_id INTO from_branch_id, from_shift_id
      FROM monthly_roster r
      WHERE r.user_id = emp_id AND r.work_date BETWEEN p_start_date AND p_end_date
      ORDER BY r.work_date
      LIMIT 1;
    IF from_branch_id IS NULL THEN
      from_branch_id := p_to_branch_id;
      from_shift_id := p_to_shift_id;
    END IF;

    -- For each date in range: skip if in holiday set, else delete existing and insert new
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

    -- One swap or transfer per user with skipped_dates
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


-- ---------- 019_leave_types_and_quota_exempt.sql ----------
-- ========== 019: Leave types + quota exemption for manager-entered leaves ==========
-- 1) holidays: leave_type (default HOLIDAY), is_quota_exempt (default FALSE)
-- 2) leave_types table + seed
-- 3) Trigger: staff/instructor can only have leave_type='HOLIDAY' and is_quota_exempt=FALSE
-- 4) RLS for leave_types (all read; admin/manager manage)

-- 1) Columns on holidays
ALTER TABLE holidays ADD COLUMN IF NOT EXISTS leave_type VARCHAR DEFAULT 'HOLIDAY';
ALTER TABLE holidays ADD COLUMN IF NOT EXISTS is_quota_exempt BOOLEAN DEFAULT FALSE;
-- 2) leave_types
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

-- Seed default leave types (idempotent: use ON CONFLICT)
INSERT INTO leave_types (code, name, color, description) VALUES
  ('HOLIDAY', 'วันหยุด', '#9CA3AF', 'วันหยุดทั่วไป (จองเอง)'),
  ('CL', 'ลากิจ', '#56CCF2', 'ลากิจ'),
  ('VL', 'ลาพักร้อน', '#F2C94C', 'ลาพักร้อน'),
  ('SL', 'ลาป่วย', '#2D9CDB', 'ลาป่วย')
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, color = EXCLUDED.color, description = EXCLUDED.description, updated_at = now();

-- 3) Trigger: enforce employees (instructor, staff) get only leave_type=HOLIDAY and is_quota_exempt=FALSE
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
  IF user_role IN ('instructor', 'staff') THEN
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

-- Optional: FK to leave_types (soft: allow any code for flexibility)
-- ALTER TABLE holidays ADD CONSTRAINT fk_holidays_leave_type FOREIGN KEY (leave_type) REFERENCES leave_types(code);
-- We skip FK so custom codes can be added later without touching holidays.


-- ---------- 020_meal_quota_user_group_and_break_cleanup.sql ----------
-- ========== 020: Meal quota user_group + break cleanup ==========
-- 1) meal_quota_rules: add user_group dimension (INSTRUCTOR/STAFF)
-- 2) break_logs: default MEAL for new records used by meal booking (non-breaking)

ALTER TABLE meal_quota_rules
  ADD COLUMN IF NOT EXISTS user_group TEXT NOT NULL DEFAULT 'INSTRUCTOR';

-- Keep existing RLS: admin/manager manage, all roles can SELECT (from migration 016)

-- Optional soft guard: new breaks default to MEAL when created via future generic inserts
ALTER TABLE break_logs ALTER COLUMN break_type SET DEFAULT 'MEAL';



-- ---------- 021_tiered_meal_quota_rules.sql ----------
-- ========== 021: Tiered meal quota rules (branch/shift/website/user_group) ==========
-- Goal:
--  - Allow wildcard dimensions (NULL = all) for meal_quota_rules.
--  - Select the most specific rule, then appropriate on_duty_threshold tier.
--  - Keep existing behavior backward-compatible (default max_concurrent = 1 when no rule).

-- 1) Relax NOT NULL constraints to allow wildcard (NULL = all).
ALTER TABLE meal_quota_rules
  ALTER COLUMN branch_id DROP NOT NULL,
  ALTER COLUMN shift_id DROP NOT NULL,
  ALTER COLUMN website_id DROP NOT NULL,
  ALTER COLUMN user_group DROP NOT NULL;

-- 2) Helper: find max_concurrent for given dimensions and on_duty_count
--    Precedence: more specific dimensions win (branch/shift/website/user_group).
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

-- 3) Update get_meal_capacity_break_logs to:
--    - filter on-duty staff by user_group (role mapping)
--    - call get_meal_quota_for_group to get max_concurrent
--    - count existing MEAL bookings only for that user_group
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
        OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
        OR (v_user_group = 'STAFF' AND p.role = 'staff')
        OR (v_user_group = 'MANAGER' AND p.role = 'manager')
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

-- 4) Unique index: allow same (branch, shift, website, on_duty_threshold) for different user_group
--    and allow multiple tier rows (different on_duty_threshold) per dimension set.
DROP INDEX IF EXISTS idx_meal_quota_rules_lookup;
CREATE UNIQUE INDEX idx_meal_quota_rules_lookup
  ON meal_quota_rules(branch_id, shift_id, website_id, user_group, on_duty_threshold);



-- ---------- 022_holiday_audit_logs.sql ----------
-- ========== 022: Holiday audit logs (privileged create/update/delete) ==========
-- Log every create/update/delete of holiday records by admin/manager/instructor_head.
-- Actor and role come from auth.uid() and profiles; only privileged actions are logged.

-- 1) Table: holiday_audit_logs
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

-- No INSERT/UPDATE/DELETE from app; only trigger writes
DROP POLICY IF EXISTS holiday_audit_logs_insert_system ON holiday_audit_logs;
-- Trigger runs as definer so we allow service role or use SECURITY DEFINER that bypasses RLS for insert
-- In Supabase, trigger runs with table owner rights; RLS still applies. So we need to allow insert from the trigger.
-- Option: use a policy that allows insert when actor_id = auth.uid() and actor_role in privileged (so only our trigger inserts)
-- But trigger runs in same transaction as the holiday mutation, so auth.uid() is the same. So: allow INSERT when auth.uid() = actor_id (trigger will set actor_id = auth.uid()).
CREATE POLICY holiday_audit_logs_insert_system ON holiday_audit_logs FOR INSERT TO authenticated
  WITH CHECK (actor_id = auth.uid());

-- 2) Trigger function: log only when actor is admin/manager/instructor_head
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


-- ---------- 023_audit_logs_performance.sql ----------
-- ========== 023: Audit logs — performance indexes + summary_text ==========
-- Purpose: Fast activity log page (cursor pagination, minimal columns, no heavy queries).
-- Table: audit_logs (ประวัติการทำรายการ). No breaking changes; additive only.

-- 1) Optional summary column (display in list without parsing details_json)
ALTER TABLE audit_logs
ADD COLUMN IF NOT EXISTS summary_text TEXT;

-- 2) Indexes for filtered list + cursor pagination (created_at DESC, filters)
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at_desc ON audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON audit_logs(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity_id ON audit_logs(entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON audit_logs(entity);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);

-- Note: idx_audit_logs_actor and idx_audit_logs_entity may already exist in schema;
-- IF NOT EXISTS keeps migration idempotent.


-- ---------- 024_password_vault_owner_rls.sql ----------
-- ========== 024: Password Vault — personal (owner_id) + RLS ==========
-- Each entry belongs to a user (owner_id). Employees see/edit only own; Admin/Manager see all.

-- 1) Add owner_id (nullable for backfill; new rows set by app)
ALTER TABLE password_vault
  ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES profiles(id) ON DELETE CASCADE;

-- Backfill: use created_by as owner where available
UPDATE password_vault SET owner_id = created_by WHERE owner_id IS NULL AND created_by IS NOT NULL;

-- 2) RLS: employees list/create/update/delete only own; admin/manager see and manage all
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


-- ---------- 025_meal_booking_slot_fields_and_cancel_privileged.sql ----------
-- ========== 025: Meal booking — slot fields (booked_count, max_concurrent, is_booked_by_me, available) + cancel for admin/manager ==========

-- 1) cancel_meal_break: allow privileged (admin/manager) to cancel any; user can cancel own when now() < slot_start_ts
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

-- 2) get_meal_slots_unified: per-slot return slot_start_ts, slot_end_ts, booked_count, max_concurrent, is_booked_by_me, available
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


-- ---------- 026_meal_booking_audit_log.sql ----------
-- ========== 026: Audit log for meal book/cancel ==========
-- Insert into audit_logs on book_meal_break and cancel_meal_break (actor, timestamp, details).

-- book_meal_break: after successful INSERT, log to audit_logs
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

-- cancel_meal_break: after successful UPDATE, log to audit_logs
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


-- ---------- 027_password_vault_instructor_head_see_all.sql ----------
-- ========== 027: Password Vault — instructor_head เห็นของทุกคนได้ (แก้ไขได้เฉพาะของตัวเอง) ==========

DROP POLICY IF EXISTS password_vault_select ON password_vault;
CREATE POLICY password_vault_select ON password_vault FOR SELECT TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head()
  OR owner_id = auth.uid() OR (owner_id IS NULL AND created_by = auth.uid())
);


-- ---------- 028_role_hierarchy.sql ----------
-- ========== 028: Role hierarchy — Head can create/edit only lower roles, same branch ==========
-- Do NOT remove existing admin policies. This adds policies for manager/instructor_head.

-- Helper: get my role level (4=admin, 3=manager, 2=instructor_head, 1=instructor, 0=staff)
CREATE OR REPLACE FUNCTION public.get_my_role_level()
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    CASE role
      WHEN 'admin' THEN 4
      WHEN 'manager' THEN 3
      WHEN 'instructor_head' THEN 2
      WHEN 'instructor' THEN 1
      WHEN 'staff' THEN 0
      ELSE 0
    END
  FROM profiles
  WHERE id = auth.uid()
  LIMIT 1;
$$;

-- Helper: role level from app_role (matches profiles.role column type)
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

-- Allow INSERT only if new user's role is lower than my role AND same branch (for non-admin; admin already has profiles_all)
CREATE POLICY head_insert_lower_role ON profiles
FOR INSERT TO authenticated
WITH CHECK (
  public.get_my_role_level() > public.get_role_level(role)
  AND (
    default_branch_id = (SELECT default_branch_id FROM profiles WHERE id = auth.uid() LIMIT 1)
    OR ((SELECT default_branch_id FROM profiles WHERE id = auth.uid() LIMIT 1) IS NULL AND default_branch_id IS NULL)
  )
);

-- Allow UPDATE only if target's role (before and after) is lower than my role (admin already has profiles_all)
CREATE POLICY head_update_lower_role ON profiles
FOR UPDATE TO authenticated
USING (public.get_my_role_level() > public.get_role_level(role))
WITH CHECK (public.get_my_role_level() > public.get_role_level(role));


-- ---------- 029_duty_indexes.sql ----------
-- ========== 029: Indexes for duty_assignments and duty_roles ==========
-- Purpose: Speed up DutyBoard and any queries filtering by branch_id, shift_id, assignment_date.
-- Run in Supabase SQL Editor (Dashboard → SQL Editor → New query → paste → Run).

-- duty_assignments: main list query is by branch_id, shift_id, assignment_date
CREATE INDEX IF NOT EXISTS idx_duty_assignments_branch_shift_date
  ON duty_assignments(branch_id, shift_id, assignment_date);

-- duty_roles: list by branch_id, sort_order
CREATE INDEX IF NOT EXISTS idx_duty_roles_branch_sort
  ON duty_roles(branch_id, sort_order);

-- website_assignments: lookup by user + website (e.g. is_primary)
CREATE INDEX IF NOT EXISTS idx_website_assignments_user_website
  ON website_assignments(user_id, website_id);


-- ---------- 030_meal_quota_step_logic.sql ----------
-- ========== 030: โควต้าพักอาหารเป็นขั้น — จองพร้อมกันได้ต้องไม่เกินคนอยู่ปฏิบัติ ==========
-- Logic: max_concurrent ต้อง <= on_duty_threshold (ไม่ให้ตั้งแบบ 10 คนอยู่ปฏิบัติ แต่จองพร้อมกัน 50 คน)

-- 1) แก้ข้อมูลเดิมที่ผิด logic ให้ตรงกับขั้น
UPDATE meal_quota_rules
SET max_concurrent = on_duty_threshold
WHERE max_concurrent > on_duty_threshold;

-- 2) บังคับ constraint ตั้งค่าต่อไปต้องเป็นขั้น
ALTER TABLE meal_quota_rules
  ADD CONSTRAINT meal_quota_rules_step CHECK (max_concurrent <= on_duty_threshold);


-- ---------- 031_meal_quota_scope_by_website_setting.sql ----------
-- ========== 031: ตั้งค่าโควต้าพักอาหาร — ใช้เว็บหลักเดียวกันในการนับหรือไม่ ==========
-- เมื่อเปิด (true) = นับเฉพาะคนที่เว็บหลักเดียวกัน (พฤติกรรมเดิม)
-- เมื่อปิด (false) = ไม่แยกเว็บ นับเฉพาะแผนก+กะ+กลุ่ม

ALTER TABLE meal_settings
  ADD COLUMN IF NOT EXISTS scope_meal_quota_by_website BOOLEAN DEFAULT true;


-- ---------- 032_meal_capacity_scope_by_website_logic.sql ----------
-- ========== 032: get_meal_capacity_break_logs อ่าน scope_meal_quota_by_website ==========
-- เมื่อ scope_meal_quota_by_website = true: นับและจองแยกตามเว็บหลัก (พฤติกรรมเดิม)
-- เมื่อ false: ไม่แยกเว็บ — eligible = แผนก+กะ+กลุ่มเท่านั้น, current_booked ไม่กรอง website_id

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
    -- แยกตามเว็บหลัก: eligible = แผนก+กะ+เว็บหลัก+กลุ่ม
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
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
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
    -- ไม่แยกเว็บ: eligible = แผนก+กะ+กลุ่ม (ไม่ดูเว็บ), จองนับทุกเว็บในแผนก+กะ
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
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
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


-- ---------- 033_holiday_quota_combined_scope.sql ----------
-- ========== 033: โควต้าวันหยุดแบบรวม (แผนก+กะ+กลุ่ม+เว็บเลือกได้) ==========
-- 1) ตั้งค่าใช้เว็บในการนับโควต้าวันหยุดหรือไม่ (เหมือนพักอาหาร)
ALTER TABLE meal_settings
  ADD COLUMN IF NOT EXISTS scope_holiday_quota_by_website BOOLEAN DEFAULT true;

-- 2) อนุญาตมิติ 'combined' ในกติกาโควต้าวันหยุด (นับคนในแผนก+กะ+กลุ่ม+เว็บถ้าเปิด)
ALTER TABLE holiday_quota_tiers DROP CONSTRAINT IF EXISTS holiday_quota_tiers_dimension_check;
ALTER TABLE holiday_quota_tiers ADD CONSTRAINT holiday_quota_tiers_dimension_check
  CHECK (dimension IN ('branch', 'shift', 'website', 'combined'));


-- ---------- 034_apply_paired_swap.sql ----------
-- ========== 034: RPC สลับกะจับคู่ (แต่ละคนไปกะปลายทางต่างกัน ในแผนกเดียวกัน) ==========
-- p_assignments: JSONB array [{ "user_id": "uuid", "to_shift_id": "uuid" }, ...]
-- ข้ามวันที่ที่มีวันหยุด (approved/pending) ของคนนั้น

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
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin','manager'));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head');
  IF NOT may_run AND NOT is_head THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can run paired swap';
  END IF;
  IF is_head AND NOT may_run THEN
    IF p_branch_id IS NULL OR p_branch_id != my_branch_id() THEN
      RAISE EXCEPTION 'Instructor head can only assign to their own branch';
    END IF;
  END IF;

  -- Dedupe by user_id (last wins) to avoid double-processing if frontend sends duplicate
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


-- ---------- 035_holiday_quota_tiers_user_group_null.sql ----------
-- ========== 035: โควต้าวันหยุดแบบขั้น — user_group เป็น NULL ได้ (ใช้กับทุกกลุ่ม เหมือนพักอาหาร) ==========
-- เมื่อ user_group = NULL กติกานั้นใช้กับทุกกลุ่ม (INSTRUCTOR/STAFF/MANAGER)

ALTER TABLE holiday_quota_tiers DROP CONSTRAINT IF EXISTS holiday_quota_tiers_user_group_check;
ALTER TABLE holiday_quota_tiers ALTER COLUMN user_group DROP NOT NULL;
ALTER TABLE holiday_quota_tiers ADD CONSTRAINT holiday_quota_tiers_user_group_check
  CHECK (user_group IS NULL OR user_group IN ('INSTRUCTOR', 'STAFF', 'MANAGER'));


-- ---------- 036_meal_on_duty_count_without_work_logs.sql ----------
-- ========== 036: อยู่ปฏิบัติไม่ใช้ IN/OUT — นับจากพนักงานที่ถือกะนั้น (active, ไม่หยุด) ==========
-- กระทบ: get_meal_capacity_break_logs เท่านั้น (ใช้โดย get_meal_slots_unified, book_meal_break)
-- Logic ใหม่: on_duty_count = จำนวนคนในกลุ่ม eligible (แผนก+กะ+เว็บถ้าเปิด+กลุ่ม) ที่ active และไม่อยู่วันหยุดอนุมัติ
-- ไม่อ้างอิง work_logs อีกต่อไป (เมนูลงเวลา IN/OUT ถูกลบแล้ว)

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
    -- แยกตามเว็บหลัก: นับคนที่ แผนก+กะ+เว็บหลัก+กลุ่ม, active, ไม่หยุดอนุมัติ (ไม่ดู work_logs)
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
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
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
    -- ไม่แยกเว็บ: นับคนที่ แผนก+กะ+กลุ่ม, active, ไม่หยุดอนุมัติ (ไม่ดู work_logs)
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
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
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


-- ---------- 037_break_logs_meal_unique_active_only.sql ----------
-- ========== 037: ให้จองพักอาหารซ้ำหลังยกเลิกได้ (unique เฉพาะ status = 'active') ==========
-- ปัญหา: idx_break_logs_meal_user_date_round ไม่กรอง status จึงรวมแถวที่ยกเลิก (status = 'ended')
--       ทำให้หลังยกเลิกแล้วกดจองใหม่จะ INSERT ไม่ได้ → duplicate key
-- แก้: ทำให้ unique จำกัดเฉพาะแถวที่ status = 'active' เท่านั้น (หนึ่งคนหนึ่งวันหนึ่งรอบได้แค่หนึ่งการจองที่ active)
-- กระทบ: break_logs — index เท่านั้น; book_meal_break / cancel_meal_break / capacity ไม่เปลี่ยน logic

DROP INDEX IF EXISTS idx_break_logs_meal_user_date_round;

CREATE UNIQUE INDEX idx_break_logs_meal_user_date_round
  ON break_logs (user_id, break_date, round_key)
  WHERE break_type = 'MEAL' AND round_key IS NOT NULL AND status = 'active';


-- ---------- 038_bulk_assignment_from_profile_when_no_roster.sql ----------
-- ========== 038: apply_bulk_assignment — ใช้โปรไฟล์เป็น from เมื่อไม่มี roster ในช่วง ==========
-- เมื่อพนักงานไม่มีแถว monthly_roster ในช่วงวันที่ เดิมใช้ p_to_* เป็น from ทำให้ประวัติแสดง "จากกะX เป็นกะX"
-- แก้: ดึง from_branch_id / from_shift_id จาก profiles.default_branch_id, default_shift_id
-- กระทบ: apply_bulk_assignment เท่านั้น

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
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin','manager'));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head');
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

    -- from_branch/from_shift: จาก roster แรกในช่วง; ถ้าไม่มี ใช้โปรไฟล์ (default_branch, default_shift); สุดท้ายใช้ to
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


-- ---------- 039_bulk_and_paired_swap_single_day.sql ----------
-- ========== 039: ย้ายกะ/สลับกะมีผลแค่วันเดียว (วันที่เริ่ม = วันที่มีผล) ==========
-- ความต้องการ: ย้ายแค่วันเดียว เช่น วันที่ 4 เป็นวันเริ่มกะดึก; ช่วงวันที่ใช้กับสลับจับคู่ = ระบบใช้วันที่เริ่มเป็นวันสลับวันเดียว
-- กระทบ: apply_bulk_assignment, apply_paired_swap

-- 1) apply_bulk_assignment: อัปเดตแค่วันที่เริ่ม (p_start_date) เท่านั้น
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
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin','manager'));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head');
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

    -- วันหยุด: ตรวจเฉพาะวันที่มีผล (p_start_date)
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
      -- from_branch/from_shift: จาก roster วันที่เริ่ม; ถ้าไม่มี ใช้โปรไฟล์; สุดท้ายใช้ to
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

-- 2) apply_paired_swap: สลับแค่วันเดียว — ใช้วันที่เริ่ม (p_start_date) เป็นวันสลับ
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
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin','manager'));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head');
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


-- ---------- 040_cancel_and_update_scheduled_shift_change.sql ----------
-- ========== 040: หัวหน้ายกเลิกหรือแก้ไขการตั้งเวลาย้ายกะ ==========
-- กระทบ: shift_swaps, cross_branch_transfers, monthly_roster
-- เมื่อยกเลิก: ลบแถว roster ของวันนั้น + ตั้ง status = 'cancelled'
-- เมื่อแก้ไข: อัปเดตวันที่หรือกะปลายทาง + ปรับ roster ให้ตรง

-- 1) ยกเลิกการตั้งเวลาย้ายกะ (ลบออกจาก roster วันนั้น + ตั้ง status = cancelled)
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
  IF NOT (EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin','manager','instructor_head'))) THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can cancel scheduled shift change';
  END IF;

  IF p_type = 'swap' THEN
    SELECT user_id, start_date, branch_id INTO v_user_id, v_start_date, v_branch_id
      FROM shift_swaps WHERE id = p_id AND status = 'approved' LIMIT 1;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'not_found_or_not_approved');
    END IF;
    IF EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head') AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin','manager')) THEN
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
    IF EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head') AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin','manager')) THEN
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

-- 2) แก้ไขการตั้งเวลาย้ายกะ (เปลี่ยนวันที่หรือกะปลายทาง)
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
  IF NOT (EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin','manager','instructor_head'))) THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can update scheduled shift change';
  END IF;

  IF p_type = 'swap' THEN
    SELECT user_id, start_date, branch_id, to_shift_id
      INTO v_user_id, v_old_start, v_branch_id, v_to_shift_id
      FROM shift_swaps WHERE id = p_id AND status = 'approved' LIMIT 1;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'not_found_or_not_approved');
    END IF;
    IF EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head') AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin','manager')) THEN
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
    IF EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head') AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin','manager')) THEN
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


-- ---------- 041_from_shift_from_roster_or_profile.sql ----------
-- ========== 041: กะต้นทาง (from_shift_id) ต้องมาจาก roster หรือ profile ไม่ใช้ to_shift ==========
-- ปัญหา: เมื่อไม่มี roster วันนั้น apply_paired_swap ใช้ to_shift_id เป็น from_shift_id → แสดง "จากกะกลาง เป็นกะกลาง"
-- แก้: ใช้ profiles.default_shift_id เป็น fallback ก่อน to_shift_id; ไม่บันทึก shift_swaps เมื่อ from = to
-- แก้ข้อมูลเก่า: อัปเดต shift_swaps ที่ from_shift_id = to_shift_id ให้ใช้ default_shift_id จาก profile (ถ้ามีและต่างจาก to)

-- 1) แก้ข้อมูลเก่า: จากกะX เป็นกะX → ใช้กะจากโปรไฟล์เป็น from (ถ้าโปรไฟล์มีกะและไม่เท่ากับ to)
UPDATE shift_swaps s
SET from_shift_id = p.default_shift_id
FROM profiles p
WHERE s.user_id = p.id
  AND s.from_shift_id = s.to_shift_id
  AND s.status = 'approved'
  AND p.default_shift_id IS NOT NULL
  AND p.default_shift_id IS DISTINCT FROM s.to_shift_id;

-- เหมือนกันสำหรับ cross_branch_transfers
UPDATE cross_branch_transfers t
SET from_shift_id = p.default_shift_id
FROM profiles p
WHERE t.user_id = p.id
  AND t.from_shift_id = t.to_shift_id
  AND t.status = 'approved'
  AND p.default_shift_id IS NOT NULL
  AND p.default_shift_id IS DISTINCT FROM t.to_shift_id;

-- 2) apply_bulk_assignment: บันทึก shift_swaps เฉพาะเมื่อ from_shift_id != to_shift_id
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
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin','manager'));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head');
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
        -- บันทึกประวัติสลับกะเฉพาะเมื่อกะต้นทางต่างจากกะปลายทาง
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

-- 3) apply_paired_swap: ใช้ profile.default_shift_id เป็น from เมื่อไม่มี roster; บันทึก shift_swaps เฉพาะเมื่อ from != to
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
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin','manager'));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head');
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
      -- กะต้นทาง: จาก roster วันนั้นก่อน; ถ้าไม่มี ใช้โปรไฟล์ (default_shift_id); สุดท้ายใช้ to_shift_id
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

      -- บันทึกประวัติสลับกะเฉพาะเมื่อกะต้นทางต่างจากกะปลายทาง
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


-- ---------- 042_schedule_cards_group_links_created_by.sql ----------
-- ========== 042: เพิ่มคอลัมน์ผู้สร้าง (created_by) สำหรับตารางงานและกลุ่มงาน ==========
-- file_vault มี uploaded_by อยู่แล้ว แสดงใน UI ได้เลย

ALTER TABLE schedule_cards ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE group_links ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES profiles(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_schedule_cards_created_by ON schedule_cards(created_by);
CREATE INDEX IF NOT EXISTS idx_group_links_created_by ON group_links(created_by);


-- ---------- 043_meal_quota_on_duty_by_work_logs_and_per_slot.sql ----------
-- ========== 043: โควต้าพักอาหาร — นับคนอยู่ปฏิบัติจาก work_logs (สถานะจริง) + นับจองต่อช่วง (ไม่รวมทั้งรอบ) ==========
-- 1) คนอยู่ปฏิบัติ = เฉพาะคนที่ลงเวลาเข้า (work_logs log_type='IN') ในวันนั้น แผนก+กะ(+เว็บถ้าเปิด)+กลุ่ม
-- 2) current_booked = จำนวนคนที่จองช่วงเวลานี้ (started_at = slot_start_ts) ไม่นับทั้งรอบ — ช่วงเดียวกันในรอบเดียวกันจองได้ไม่เกิน max_concurrent คน
-- 3) คนละช่วงในรอบเดียวกันจองได้ (แต่ละ slot นับแยก)

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
    -- แยกตามเว็บหลัก: นับเฉพาะคนที่ลงเวลาเข้าแล้ว (work_logs IN) ในแผนก+กะ+เว็บหลัก+กลุ่ม
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
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
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

    -- นับเฉพาะคนที่จองช่วงนี้ (slot) ไม่นับทั้งรอบ
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
    -- ไม่แยกเว็บ: นับเฉพาะคนที่ลงเวลาเข้าแล้ว (work_logs IN) ในแผนก+กะ+กลุ่ม
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
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
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

    -- นับเฉพาะคนที่จองช่วงนี้ (slot)
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


-- ---------- 044_meal_quota_no_work_logs_eligible_only.sql ----------
-- ========== 044: โควต้าพักอาหาร — ไม่ใช้ IN/OUT (work_logs) ==========
-- ระบบเอาการลงเวลา IN/OUT ออกแล้ว โควต้านับแค่คนที่อยู่:
--   กลุ่มเดียวกัน + แผนกเดียวกัน + กะเดียวกัน + เว็บเดียวกัน (ถ้าเปิดตัวเลือก scope_meal_quota_by_website)
-- ไม่อ้างอิง work_logs; current_booked ยังนับต่อช่วง (per slot) ตาม 043

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
    -- แยกตามเว็บ: นับคนที่ กลุ่ม+แผนก+กะ+เว็บหลักเดียวกัน, active, ไม่หยุดอนุมัติ (ไม่ใช้ work_logs)
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
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
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
    -- ไม่แยกเว็บ: นับคนที่ กลุ่ม+แผนก+กะเดียวกัน, active, ไม่หยุดอนุมัติ (ไม่ใช้ work_logs)
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
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
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


-- ---------- 045_meal_quota_most_restrictive_tier_and_booked_users.sql ----------
-- ========== 045: โควต้าพักอาหาร — เลือก tier ที่จำกัดที่สุด + คืนรายชื่อผู้จองแต่ละช่วง ==========
-- 1) get_meal_quota_for_group: เมื่อหลาย tier ตรง (on_duty_threshold >= count) ให้เลือก max_concurrent น้อยที่สุดก่อน
--    เช่น 2 คน มี (2,2) กับ (4,1) จะได้ (4,1) → จองได้ 1 คน (4 ลงมา = 1 คน)
-- 2) get_meal_capacity_break_logs: คืน booked_user_ids (array) เพื่อให้ UI แสดงว่าใครจองช่วงนั้นแล้ว

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

-- get_meal_capacity_break_logs: เพิ่ม booked_user_ids ใน return
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
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
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
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
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


-- ---------- 046_meal_on_duty_user_ids_in_slots_response.sql ----------
-- ========== 046: คืนรายชื่อคนที่ระบบนับเป็น "อยู่ปฏิบัติ" ใน get_meal_slots_unified ==========
-- ให้ UI แสดงทางขวาว่ามีใครบ้างที่ระบบใช้คำนวณโควต้า (กลุ่ม+แผนก+กะ+เว็บถ้าเปิด)

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
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
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
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
        )
    )
    SELECT COALESCE(jsonb_agg(id ORDER BY id), '[]'::JSONB) INTO v_result FROM eligible;
  END IF;

  RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;

-- เพิ่ม on_duty_user_ids ใน return ของ get_meal_slots_unified
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


-- ---------- 047_meal_quota_cap_max_one_when_four_or_less.sql ----------
-- ========== 047: บังคับโควต้าพักอาหาร — เมื่อคนอยู่ปฏิบัติ ≤ 4 ให้จองได้สูงสุด 1 คน ==========
-- แก้กรณีตั้งค่าไว้ 1 คนแต่ยังจองได้ 2: บังคับ cap max_concurrent = 1 เมื่อ on_duty_count <= 4

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
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
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
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
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

  -- บังคับ: คนอยู่ปฏิบัติ ≤ 4 ให้จองได้สูงสุด 1 คน (ตามกติกา "4 ลงมา = 1 คน")
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


-- ---------- 048_meal_quota_use_tier_only_no_hardcap.sql ----------
-- ========== 048: ใช้เงื่อนไขจากตารางโควต้าเท่านั้น (ไม่บังคับแค่ 1) ==========
-- ยกเลิกการ cap แบบตายตัวใน 047 — ให้ max_concurrent มาจาก get_meal_quota_for_group ตาม tier ที่ตั้งค่า (4→1, 7→2, 10→3, 14→4, 20→5)

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
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
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
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
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


-- ---------- 049_meal_quota_min_concurrent_among_matching_tiers.sql ----------
-- ========== 049: โควต้าพักอาหาร — ใช้ MIN(max_concurrent) ใน tier ที่ตรงเสมอ ==========
-- แก้ปัญหา "ยังจองได้สองอยู่ ควรจองได้คนเดียว": เมื่อหลายแถวในตาราง tier ตรงกับจำนวนคนอยู่ปฏิบัติ
-- (เช่น 2 คน ตรงทั้ง ≤4 และ ≤7) ให้ใช้ค่าที่จำกัดที่สุดเสมอ = MIN(max_concurrent)
-- และยังเคารพ rule เฉพาะ (branch/shift/website/user_group) ก่อน แล้วค่อย MIN ในชุดนั้น

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


-- ---------- 050_apply_paired_swap_fix_ambiguous_uid.sql ----------
-- ========== 050: แก้ apply_paired_swap — column reference "uid" is ambiguous ==========
-- ใน CTE ใช้ชื่อคอลัมน์ uid/sid แล้ว SELECT INTO อ้าง uid — พอมีตัวแปร DECLARE uid ใน PL ทำให้ ambiguous
-- แก้โดยอ้าง sub.uid, sub.sid ใน SELECT list ให้ชัดว่าเป็นคอลัมน์จาก subquery
-- Logic วันหยุด/ลาอยู่แล้ว: ถ้าวันนั้นมี holidays (approved/pending) จะไม่ย้ายกะวันนั้น (skip)

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
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = caller_uid AND role IN ('admin','manager'));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = caller_uid AND role = 'instructor_head');
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

    -- วันที่มีวันหยุดหรือลา (approved/pending) จะไม่ย้ายกะ — ข้ามวันนั้น
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
      -- กะต้นทาง: จาก roster วันนั้นก่อน; ถ้าไม่มี ใช้โปรไฟล์ (default_shift_id); สุดท้ายใช้ to_shift_id
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

      -- บันทึกประวัติสลับกะเฉพาะเมื่อกะต้นทางต่างจากกะปลายทาง
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


-- ---------- 051_block_scheduled_users_bulk_paired.sql ----------
-- ========== 051: ป้องกันย้ายกะคนที่กำลังถูกตั้งเวลาย้ายกะอยู่ ==========
-- แอดมิน/หัวหน้าจะไม่สามารถย้ายกะให้คนที่มีรายการตั้งเวลา (approved) ที่ start_date >= วันนี้
-- จนกว่าจะสิ้นสุดการตั้งเวลาหรือยกเลิกก่อน
-- กระทบ: apply_bulk_assignment, apply_paired_swap

-- 1) apply_bulk_assignment: ข้ามพนักงานที่มียอดตั้งเวลาย้ายกะ (approved, start_date >= current_date)
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
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin','manager'));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head');
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

    -- ผู้ที่กำลังถูกตั้งเวลาย้ายกะอยู่ (approved, start_date >= วันนี้) ห้ามย้ายกะเพิ่ม
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

-- 2) apply_paired_swap: ข้ามพนักงานที่กำลังถูกตั้งเวลาย้ายกะอยู่ (approved, start_date >= current_date)
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
  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = caller_uid AND role IN ('admin','manager'));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = caller_uid AND role = 'instructor_head');
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

    -- ผู้ที่กำลังถูกตั้งเวลาย้ายกะอยู่ ห้ามย้ายกะเพิ่ม
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


-- ---------- 052_group_links_creator_see_and_department_filter_all.sql ----------
-- ========== 052: ลิงก์กลุ่ม — ผู้สร้างเห็นเสมอ + ตัวกรองแผนกเลือกทั้งหมดได้ ==========
-- 1) หัวหน้าสร้างลิงก์แล้วต้องแสดง: เพิ่มเงื่อนไข created_by = auth.uid() ใน SELECT
-- 2) ไม่เปลี่ยน INSERT/UPDATE (หัวหน้าสร้างได้อยู่แล้วจาก migration 008)

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


-- ---------- 053_group_links_head_see_all_like_schedule_cards.sql ----------
-- ========== 053: กลุ่มงาน — หัวหน้าเห็นทุกลิงก์ + แก้/ลบได้ + กำหนดหลายแผนกได้ (ทำสิทธิ์เหมือนตารางงาน) ==========
-- กระทบ: group_links, group_link_branches, group_link_websites (RLS เท่านั้น)
-- ไม่เปลี่ยนโครงตาราง / ไม่กระทบลงเวลา-ตารางรายเดือน-โควต้า

-- 1) SELECT: หัวหน้าเห็นทุกลิงก์ (เหมือน admin/manager) + ผู้สร้างเห็นของตัวเองเสมอ
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

-- 2) UPDATE/DELETE: หัวหน้าแก้/ลบลิงก์ใดก็ได้ (ให้สอดคล้องกับการเห็นทั้งหมด)
DROP POLICY IF EXISTS group_links_update ON group_links;
CREATE POLICY group_links_update ON group_links FOR UPDATE TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head()
);

DROP POLICY IF EXISTS group_links_delete ON group_links;
CREATE POLICY group_links_delete ON group_links FOR DELETE TO authenticated USING (
  is_admin() OR is_manager() OR is_instructor_head()
);

-- 3) group_link_branches: หัวหน้าเห็นทุกแถว + ใส่/ลบ branch ใดก็ได้ (กำหนดสิทธิ์ตอนสร้างได้หลายแผนก)
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

-- 4) group_link_websites: หัวหน้าเห็น/ใส่/ลบ ได้ทุกแถว (ให้แก้ลิงก์ใดก็ได้)
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


-- ---------- 054_shift_swaps_head_see_branch.sql ----------
-- ========== 054: หัวหน้าเห็นวันย้ายกะของพนักงานในแผนกตัวเอง (ตารางวันหยุด) ==========
-- ปัญหา: หัวหน้าผู้สอนไม่เห็นปุ่ม "ย้ายกะ" ของพนักงานอื่นในตารางวันหยุด (เห็นเฉพาะแอดมิน)
-- สาเหตุ: RLS shift_swaps / cross_branch_transfers ใช้ user_branch_ids(auth.uid()) ซึ่งอาจไม่ครอบคลุมหัวหน้าในบางสภาพ
-- แก้: เพิ่มเงื่อนไข is_instructor_head() AND branch_id = my_branch_id() ให้ชัดเจน
-- กระทบ: shift_swaps, cross_branch_transfers (SELECT เท่านั้น) — ไม่กระทบลงเวลา/โควต้า/ตารางรายเดือน

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


-- ---------- 055_block_change_shift_when_scheduled.sql ----------
-- ========== 055: ห้ามเปลี่ยนกะในจัดการสมาชิกเมื่อพนักงานถูกตั้งเวลาย้ายกะอยู่ ==========
-- ปัญหา: แอดมิน/หัวหน้าไปแก้ "กะเริ่มต้น" ในจัดการสมาชิกได้ แม้พนักงานนั้นจะมีรายการตั้งเวลาย้ายกะ (approved, start_date >= วันนี้)
-- แก้: Trigger บน profiles — เมื่อมีการเปลี่ยน default_shift_id ให้ตรวจว่ามี shift_swaps หรือ cross_branch_transfers ที่ approved และ start_date >= current_date หรือไม่ ถ้ามี ให้ยกเลิกการอัปเดต
-- กระทบ: profiles (BEFORE UPDATE trigger เท่านั้น) — ไม่กระทบลงเวลา/โควต้า/ตารางรายเดือน

CREATE OR REPLACE FUNCTION check_no_scheduled_shift_change_on_profile_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- เปลี่ยนกะ (default_shift_id) เท่านั้นที่ต้องเช็ค
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


-- ---------- 056_shift_swaps_head_see_null_branch_by_user.sql ----------
-- ========== 056: หัวหน้าเห็นวันย้ายกะแม้ branch_id เป็น NULL (ยึดจาก user ในแผนก) ==========
-- ปัญหา: บางรายการ shift_swaps อาจมี branch_id = NULL ทำให้หัวหน้าไม่เห็น (policy 054 ใช้ branch_id = my_branch_id())
-- แก้: ให้หัวหน้าเห็นแถวที่ branch_id IS NULL แต่ user_id อยู่ในแผนกตัวเอง (profiles.default_branch_id = my_branch_id())
-- กระทบ: shift_swaps (SELECT เท่านั้น)

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


-- ---------- 057_head_same_visibility_as_manager.sql ----------
-- 057: หัวหน้าเห็นทุกแผนกเหมือนผู้จัดการ; user_branch_ids รวมหัวหน้า; is_admin_or_manager_or_head(); profiles หัวหน้าแก้ได้เฉพาะ instructor/staff ในแผนกตัวเอง

-- 1) user_branch_ids: หัวหน้าเห็นทุกสาขา (เหมือน admin/manager)
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

-- 2) หัวหน้า = สิทธิ์มองเห็น/จัดการเท่ากับผู้จัดการ (ใช้ใน policy ต่างๆ ไม่ใช้ใน profiles UPDATE)
CREATE OR REPLACE FUNCTION is_admin_or_manager_or_head()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin'::app_role, 'manager'::app_role, 'instructor_head'::app_role));
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- 3) profiles UPDATE: หัวหน้าแก้ไขได้เฉพาะ instructor/staff ในแผนกตัวเอง (ห้ามแก้ manager/admin)
DROP POLICY IF EXISTS profiles_update_branch_head ON profiles;
CREATE POLICY profiles_update_branch_head ON profiles FOR UPDATE TO authenticated USING (
  is_admin() OR (is_instructor_head() AND default_branch_id = my_branch_id() AND role IN ('instructor'::app_role, 'staff'::app_role))
);

-- 4) นโยบายที่ให้หัวหน้า = ผู้จัดการ (SELECT/INSERT/UPDATE/DELETE ตามตาราง)
-- branches, shifts, break_rules, holiday_quotas, holiday_quota_tiers, monthly_roster_status
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

-- monthly_roster
DROP POLICY IF EXISTS monthly_roster_insert ON monthly_roster;
CREATE POLICY monthly_roster_insert ON monthly_roster FOR INSERT TO authenticated WITH CHECK (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS monthly_roster_update ON monthly_roster;
CREATE POLICY monthly_roster_update ON monthly_roster FOR UPDATE TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS monthly_roster_delete ON monthly_roster;
CREATE POLICY monthly_roster_delete ON monthly_roster FOR DELETE TO authenticated USING (is_admin_or_manager_or_head());

-- duty_roles, duty_assignments
DROP POLICY IF EXISTS duty_roles_all ON duty_roles;
CREATE POLICY duty_roles_all ON duty_roles FOR ALL TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS duty_assignments_all ON duty_assignments;
CREATE POLICY duty_assignments_all ON duty_assignments FOR ALL TO authenticated USING (is_admin_or_manager_or_head());

-- password_vault, holiday_booking_config
DROP POLICY IF EXISTS password_vault_all ON password_vault;
CREATE POLICY password_vault_all ON password_vault FOR ALL TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS holiday_booking_config_all ON holiday_booking_config;
CREATE POLICY holiday_booking_config_all ON holiday_booking_config FOR ALL TO authenticated USING (is_admin_or_manager_or_head());

-- leave_types
DROP POLICY IF EXISTS leave_types_all ON leave_types;
CREATE POLICY leave_types_all ON leave_types FOR ALL TO authenticated USING (is_admin_or_manager_or_head());

-- websites
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

-- website_assignments
DROP POLICY IF EXISTS website_assignments_select ON website_assignments;
CREATE POLICY website_assignments_select ON website_assignments FOR SELECT TO authenticated USING (is_admin_or_manager_or_head() OR user_id = auth.uid());
DROP POLICY IF EXISTS website_assignments_insert ON website_assignments;
CREATE POLICY website_assignments_insert ON website_assignments FOR INSERT TO authenticated WITH CHECK (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS website_assignments_update ON website_assignments;
CREATE POLICY website_assignments_update ON website_assignments FOR UPDATE TO authenticated USING (is_admin_or_manager_or_head());
DROP POLICY IF EXISTS website_assignments_delete ON website_assignments;
CREATE POLICY website_assignments_delete ON website_assignments FOR DELETE TO authenticated USING (is_admin_or_manager_or_head());

-- work_logs, break_logs
DROP POLICY IF EXISTS work_logs_update ON work_logs;
CREATE POLICY work_logs_update ON work_logs FOR UPDATE TO authenticated USING (is_admin_or_manager_or_head() OR user_id = auth.uid());
DROP POLICY IF EXISTS break_logs_update ON break_logs;
CREATE POLICY break_logs_update ON break_logs FOR UPDATE TO authenticated USING (user_id = auth.uid() OR is_admin_or_manager_or_head());

-- shift_swaps, cross_branch_transfers
DROP POLICY IF EXISTS shift_swaps_update ON shift_swaps;
CREATE POLICY shift_swaps_update ON shift_swaps FOR UPDATE TO authenticated USING (is_admin_or_manager_or_head() OR user_id = auth.uid());
DROP POLICY IF EXISTS transfers_update ON cross_branch_transfers;
CREATE POLICY transfers_update ON cross_branch_transfers FOR UPDATE TO authenticated USING (is_admin_or_manager_or_head() OR user_id = auth.uid());

-- shift_swaps_select / transfers_select: ให้หัวหน้าเห็นทุกรายการ (ใช้ user_branch_ids แล้วได้ทุกสาขา; เผื่อ branch_id NULL)
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

-- schedule_cards: SELECT ให้หัวหน้าเห็นทุกการ์ดเหมือนผู้จัดการ
DROP POLICY IF EXISTS schedule_cards_select ON schedule_cards;
CREATE POLICY schedule_cards_select ON schedule_cards FOR SELECT TO authenticated USING (
  is_admin_or_manager_or_head()
  OR (
    (branch_id IS NULL OR branch_id IN (SELECT user_branch_ids(auth.uid())))
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles))
    AND (website_id IS NULL OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid()))
  )
);

-- file_vault: SELECT/INSERT/UPDATE/DELETE ให้หัวหน้าเหมือนผู้จัดการ
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

-- audit_logs SELECT (ให้หัวหน้าเห็นเหมือนผู้จัดการ)
DROP POLICY IF EXISTS audit_logs_select ON audit_logs;
CREATE POLICY audit_logs_select ON audit_logs FOR SELECT TO authenticated USING (
  is_admin_or_manager_or_head() OR (actor_id = auth.uid()) OR is_instructor_or_admin()
);

