-- ==============================================================================
-- 22: Ensure duty_assignments allows multiple users per duty per day (idempotent)
-- ถ้ารัน migration 16 ไปแล้วหรือ constraint ชื่อต่างกัน รันไฟล์นี้ใน Supabase SQL Editor
-- ==============================================================================

-- ลบ unique เก่าที่จำกัดแค่ 1 คนต่อ 1 หน้าที่ต่อวัน (ชื่อมาตรฐาน)
ALTER TABLE public.duty_assignments
  DROP CONSTRAINT IF EXISTS duty_assignments_branch_id_shift_id_duty_role_id_assignment_date_key;

-- ลบ unique อื่นที่อยู่บน (branch_id, shift_id, duty_role_id, assignment_date) เฉพาะ 4 คอลัมน์
-- กรณี constraint ชื่ออื่นหรือสร้างจาก schema อื่น
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

-- กำหนด unique ใหม่: คนเดียวกันในหน้าที่เดียวกันวันเดียวกันได้แค่ 1 แถว; หลายคนต่อหน้าที่ได้
CREATE UNIQUE INDEX IF NOT EXISTS duty_assignments_one_user_per_role_per_day
  ON public.duty_assignments (branch_id, shift_id, duty_role_id, assignment_date, user_id)
  WHERE user_id IS NOT NULL;
