-- 25: เมนูลัดบนแดชบอร์ด (ลิงก์ + หัวข้อ + ไอคอน optional)
-- อ่านได้ทุกคน แก้ไขได้เฉพาะ admin, manager, instructor_head

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

-- อ่านได้ทุกคน (authenticated) เพื่อแสดงบนแดชบอร์ด
DROP POLICY IF EXISTS dashboard_shortcuts_select ON dashboard_shortcuts;
CREATE POLICY dashboard_shortcuts_select
ON dashboard_shortcuts FOR SELECT TO authenticated
USING (true);

-- เพิ่ม/แก้/ลบ ได้เฉพาะ admin, manager, instructor_head
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
