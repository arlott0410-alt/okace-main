-- ==============================================================================
-- 05: ลบตาราง password_vault (ไม่ได้ใช้ในระบบ)
--     ตรวจสอบแล้ว: ไม่มี frontend (.from('password_vault')), ไม่มี RPC, ไม่มี API
--     รันหลัง 04 (หรือหลัง 03 ถ้าไม่ได้รัน 04)
-- ==============================================================================

DROP POLICY IF EXISTS password_vault_select ON password_vault;
DROP POLICY IF EXISTS password_vault_all ON password_vault;
DROP POLICY IF EXISTS password_vault_insert ON password_vault;
DROP POLICY IF EXISTS password_vault_update ON password_vault;
DROP POLICY IF EXISTS password_vault_delete ON password_vault;
DROP TRIGGER IF EXISTS password_vault_updated_at ON password_vault;
DROP TABLE IF EXISTS password_vault CASCADE;
