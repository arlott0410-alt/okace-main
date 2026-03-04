-- ==============================================================================
-- Verification: ย้ายกะ/สลับกะแบบถาวร + guards
-- รันใน Supabase SQL Editor (ใช้ test data ตาม env จริง)
-- ==============================================================================

-- -----------------------------------------------------------------------------
-- 1) start_date = วันนี้ ต้อง fail (trigger)
-- -----------------------------------------------------------------------------
-- คาด: ERROR ... START_DATE_MUST_BE_TOMORROW_OR_LATER
/*
INSERT INTO shift_swaps (
  user_id, branch_id, from_shift_id, to_shift_id,
  start_date, end_date, reason, status, approved_by, approved_at
) VALUES (
  (SELECT id FROM profiles LIMIT 1),
  (SELECT id FROM branches LIMIT 1),
  (SELECT id FROM shifts LIMIT 1),
  (SELECT id FROM shifts OFFSET 1 LIMIT 1),
  (now() AT TIME ZONE 'Asia/Bangkok')::date,  -- วันนี้
  NULL,
  'test',
  'approved',
  (SELECT id FROM profiles WHERE role = 'admin' LIMIT 1),
  now()
);
-- ลบถ้า insert ผ่าน (ไม่ควรเกิด): DELETE FROM shift_swaps WHERE reason = 'test';
*/

-- -----------------------------------------------------------------------------
-- 2) ย้ายกะถาวร: start_date = พรุ่งนี้ → วันนี้ยังไม่เปลี่ยน / พรุ่งนี้หลัง apply เปลี่ยน
-- -----------------------------------------------------------------------------
-- 2.1 สร้างรายการ (ใช้ RPC apply_bulk_assignment หรือ insert ตรง)
-- 2.2 ตรวจว่า profile.default_shift_id ยังเป็นของเดิมก่อนรัน apply
-- 2.3 SELECT apply_scheduled_shift_changes_for_date(tomorrow_bangkok());
-- 2.4 ตรวจว่า profile.default_shift_id = to_shift_id

-- ตัวอย่างเช็คฟังก์ชัน tomorrow_bangkok:
SELECT tomorrow_bangkok() AS tomorrow_bangkok;

-- ตัวอย่างรัน apply สำหรับวันนี้ (ไม่เปลี่ยนอะไรถ้าไม่มีรายการมีผลวันนี้):
SELECT apply_scheduled_shift_changes_for_date((now() AT TIME ZONE 'Asia/Bangkok')::date) AS applied_today;

-- -----------------------------------------------------------------------------
-- 3) สลับคู่ถาวร: ทั้งสองคนมี shift_swaps end_date NULL
-- -----------------------------------------------------------------------------
-- หลังเรียก apply_paired_swap แล้ว ตรวจ:
-- SELECT id, user_id, start_date, end_date, to_shift_id FROM shift_swaps WHERE status = 'approved' ORDER BY created_at DESC LIMIT 10;

-- -----------------------------------------------------------------------------
-- 4) Overlap: มีรายการ active อยู่ แล้วสลับคู่ซ้ำ → ต้องได้ SHIFT_CHANGE_OVERLAP_CONFLICT
-- -----------------------------------------------------------------------------
-- ต้องเรียก apply_paired_swap สำหรับ user ที่มีย้ายกะ approved และ start_date <= วันที่จะสลับ และ (end_date IS NULL OR end_date >= วันนั้น)
-- คาด: RPC return error message มี 'SHIFT_CHANGE_OVERLAP_CONFLICT'

-- -----------------------------------------------------------------------------
-- 5) สรุปตรวจสอบ
-- -----------------------------------------------------------------------------
-- [ ] Insert shift_swaps ด้วย start_date = today → fail
-- [ ] apply_bulk_assignment ด้วย start_date = today → fail
-- [ ] apply_bulk_assignment ด้วย start_date = tomorrow → success, end_date NULL
-- [ ] apply_scheduled_shift_changes_for_date(วันที่มีผล) → อัปเดต profiles
-- [ ] apply_paired_swap สร้างรายการ end_date NULL
-- [ ] apply_paired_swap เมื่อ user มี active change → SHIFT_CHANGE_OVERLAP_CONFLICT
