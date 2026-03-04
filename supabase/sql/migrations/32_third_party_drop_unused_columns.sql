-- Migration 32: ลบคอลัมน์ที่ไม่ได้ใช้งานจาก third_party_providers (ตรงกับ UI ที่ลบออกแล้ว)
-- ไม่กระทบ RLS / policy อื่น (ไม่มี policy อ้างอิงคอลัมน์เหล่านี้)

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
