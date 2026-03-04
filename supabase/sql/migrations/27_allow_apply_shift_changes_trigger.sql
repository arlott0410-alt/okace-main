-- ==============================================================================
-- 27: อนุญาตให้ apply_scheduled_shift_changes_for_date อัปเดต profiles ได้
-- ปัญหา: Trigger check_no_scheduled_shift_change_on_profile_update บล็อกทุกการเปลี่ยน default_shift_id
-- เมื่อมีรายการย้ายกะที่ start_date >= วันนี้ จึงบล็อกการรัน apply_scheduled_shift_changes_for_date ด้วย
-- แก้: ถ้า NEW.default_shift_id ตรงกับ to_shift_id ของรายการย้ายกะที่มีผลในวันนี้ (start_date <= วันนี้, end_date null หรือ วันนี้ <= end_date) ให้อนุญาต (เป็นการ apply)
-- ==============================================================================

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

  -- ถ้า NEW.default_shift_id ตรงกับกะปลายทางของรายการย้ายกะที่มีผลในวันนี้ = กำลัง apply ตามกำหนด → อนุญาต
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

  -- ไม่ใช่การ apply → ห้ามถ้ามีรายการตั้งเวลาที่ยังมีผล (start_date >= วันนี้)
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

COMMENT ON FUNCTION check_no_scheduled_shift_change_on_profile_update() IS
  'ห้ามอัปเดต default_shift_id เมื่อ user มีรายการตั้งเวลาย้ายกะ (approved, start_date>=วันนี้) — ยกเว้นเมื่อค่าใหม่ตรงกับ to_shift_id ที่มีผลวันนี้ (ให้ apply_scheduled_shift_changes_for_date อัปเดตได้)';
