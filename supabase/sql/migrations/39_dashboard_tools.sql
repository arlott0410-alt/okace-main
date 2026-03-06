-- 39: กล่องเครื่องมือบนแดชบอร์ด (เครื่องมือช่วย) — โครงสร้างเดียวกับเมนูลัด
-- อ่านได้ทุกคน (authenticated) แก้ไขได้เฉพาะ admin, manager, instructor_head
-- เป้าหมาย: แสดงบล็อก "กล่องเครื่องมือ" บน Dashboard ให้ทุกคนเห็น; หัวหน้า/ผู้จัดการ/แอดมินแก้ไขได้

BEGIN;

CREATE TABLE IF NOT EXISTS dashboard_tools (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  url TEXT NOT NULL,
  title TEXT NOT NULL,
  icon_url TEXT,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE dashboard_tools ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dashboard_tools_select ON dashboard_tools;
CREATE POLICY dashboard_tools_select
ON dashboard_tools FOR SELECT TO authenticated
USING (true);

DROP POLICY IF EXISTS dashboard_tools_insert ON dashboard_tools;
CREATE POLICY dashboard_tools_insert
ON dashboard_tools FOR INSERT TO authenticated
WITH CHECK (is_admin_or_manager_or_head());

DROP POLICY IF EXISTS dashboard_tools_update ON dashboard_tools;
CREATE POLICY dashboard_tools_update
ON dashboard_tools FOR UPDATE TO authenticated
USING (is_admin_or_manager_or_head())
WITH CHECK (is_admin_or_manager_or_head());

DROP POLICY IF EXISTS dashboard_tools_delete ON dashboard_tools;
CREATE POLICY dashboard_tools_delete
ON dashboard_tools FOR DELETE TO authenticated
USING (is_admin_or_manager_or_head());

DROP TRIGGER IF EXISTS dashboard_tools_updated_at ON dashboard_tools;
CREATE TRIGGER dashboard_tools_updated_at
BEFORE UPDATE ON dashboard_tools
FOR EACH ROW EXECUTE PROCEDURE set_updated_at();

COMMIT;
