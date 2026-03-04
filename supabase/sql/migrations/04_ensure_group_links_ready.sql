-- ==============================================================================
-- 04: แก้ 500 บน group_links (ศูนย์รวมกลุ่มงาน)
--     สาเหตุ: ตาราง/คอลัมน์ที่ frontend ใช้ไม่มี หรือ RLS อ้างอิงคอลัมน์ที่ยังไม่ถูกสร้าง
--     รันไฟล์นี้หลัง 01, 02, 03 (หรือรันเมื่อหน้ากลุ่มงานขึ้น 500)
-- ==============================================================================

-- 1) คอลัมน์ที่ group_links ต้องมี (frontend + RLS 053 ใช้)
ALTER TABLE group_links ADD COLUMN IF NOT EXISTS website_id UUID REFERENCES websites(id) ON DELETE SET NULL;
ALTER TABLE group_links ADD COLUMN IF NOT EXISTS visible_roles TEXT[] DEFAULT '{}';
ALTER TABLE group_links ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES profiles(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_group_links_website ON group_links(website_id);
CREATE INDEX IF NOT EXISTS idx_group_links_created_by ON group_links(created_by);

-- 2) ตาราง group_link_websites (frontend select ใช้ embed)
CREATE TABLE IF NOT EXISTS group_link_websites (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  group_link_id UUID NOT NULL REFERENCES group_links(id) ON DELETE CASCADE,
  website_id UUID NOT NULL REFERENCES websites(id) ON DELETE CASCADE,
  UNIQUE(group_link_id, website_id)
);
CREATE INDEX IF NOT EXISTS idx_group_link_websites_link ON group_link_websites(group_link_id);
CREATE INDEX IF NOT EXISTS idx_group_link_websites_website ON group_link_websites(website_id);
ALTER TABLE group_link_websites ENABLE ROW LEVEL SECURITY;

-- 3) ตาราง group_link_branches (frontend select ใช้ embed)
CREATE TABLE IF NOT EXISTS group_link_branches (
  group_link_id UUID NOT NULL REFERENCES group_links(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  PRIMARY KEY (group_link_id, branch_id)
);
CREATE INDEX IF NOT EXISTS idx_group_link_branches_link ON group_link_branches(group_link_id);
CREATE INDEX IF NOT EXISTS idx_group_link_branches_branch ON group_link_branches(branch_id);
ALTER TABLE group_link_branches ENABLE ROW LEVEL SECURITY;

-- 4) ฟังก์ชันที่ RLS ใช้ (ถ้ายังไม่มีจะ error ตอนประเมิน policy)
CREATE OR REPLACE FUNCTION is_instructor_head()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'instructor_head'::app_role);
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION is_admin_or_manager_or_head()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin'::app_role, 'manager'::app_role, 'instructor_head'::app_role));
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- 4b) ตัด infinite recursion ระหว่าง group_links ↔ group_link_branches (อ่านตารางในฟังก์ชันโดยไม่ผ่าน RLS)
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

-- 5) RLS group_links — ใช้ can_see_group_link(id) แทน subquery ไป group_link_branches เพื่อไม่ให้ recursion
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

-- 6) RLS group_link_branches — ใช้ can_see_group_link(group_link_id) แทน subquery ไป group_links เพื่อไม่ให้ recursion
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

-- 7) RLS group_link_websites — ใช้ can_see_group_link เพื่อไม่ให้ trigger group_links RLS แล้ว recursion
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
