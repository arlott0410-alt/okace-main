-- 24: เปิด/ปิดการเข้าผ่านมือถือ (Desktop-only toggle)
-- อ่านได้ทุกคน (anon + authenticated) แก้ไขได้เฉพาะ admin

BEGIN;

CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value_bool BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- seed ค่าเริ่มต้น: ไม่อนุญาตมือถือ
INSERT INTO app_settings (key, value_bool)
VALUES ('allow_mobile_access', false)
ON CONFLICT (key) DO NOTHING;

ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;

-- ให้อ่านได้ทุกคน (anon + authenticated) เพื่อให้ middleware อ่านค่าได้
DROP POLICY IF EXISTS app_settings_select_all ON app_settings;
CREATE POLICY app_settings_select_all
ON app_settings
FOR SELECT
TO anon, authenticated
USING (true);

-- แก้ไขได้เฉพาะ admin
DROP POLICY IF EXISTS app_settings_update_admin ON app_settings;
CREATE POLICY app_settings_update_admin
ON app_settings
FOR UPDATE
TO authenticated
USING (is_admin())
WITH CHECK (is_admin());

-- กัน insert/delete (ไม่จำเป็นต้องใช้)
REVOKE INSERT ON app_settings FROM anon, authenticated;
REVOKE DELETE ON app_settings FROM anon, authenticated;

-- ใช้ฟังก์ชัน set_updated_at ที่มีอยู่แล้วในระบบ
DROP TRIGGER IF EXISTS trg_app_settings_updated_at ON app_settings;
CREATE TRIGGER trg_app_settings_updated_at
BEFORE UPDATE ON app_settings
FOR EACH ROW EXECUTE PROCEDURE set_updated_at();

COMMIT;
