-- 38: ป้องกันการแก้ไขรายการสลับกะให้ปลายทางเป็นกะเดิม
-- เป้าหมาย: กันไม่ให้เกิด scheduled swap แบบ no-op ที่ทำให้ UI สับสนและไปล็อกการแก้สมาชิกโดยไม่จำเป็น
-- ตารางที่กระทบ: shift_swaps
-- เหตุผลที่ต้องทำ migration ใหม่: update_scheduled_shift_change ถูกใช้งานจริงแล้ว จึงแก้แบบ incremental เพื่อไม่ย้อนแก้ migration เดิม

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
  v_branch_id UUID;
  v_to_shift_id UUID;
  v_from_shift_id UUID;
BEGIN
  IF p_new_start_date IS NULL OR p_new_start_date < tomorrow_bangkok() THEN
    RAISE EXCEPTION 'START_DATE_MUST_BE_TOMORROW_OR_LATER'
      USING errcode = 'P0001';
  END IF;
  IF NOT (EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role,'instructor_head'::app_role))) THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can update scheduled shift change';
  END IF;

  IF p_type = 'swap' THEN
    SELECT user_id, branch_id, from_shift_id, to_shift_id
    INTO v_user_id, v_branch_id, v_from_shift_id, v_to_shift_id
    FROM shift_swaps
    WHERE id = p_id AND status = 'approved'
    LIMIT 1;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'not_found_or_not_approved');
    END IF;

    IF EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head'::app_role)
      AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role)) THEN
      IF v_branch_id IS NULL OR v_branch_id != my_branch_id() THEN
        RAISE EXCEPTION 'Instructor head can only update within their branch';
      END IF;
    END IF;

    v_to_shift_id := COALESCE(p_new_to_shift_id, v_to_shift_id);
    IF v_to_shift_id IS NOT DISTINCT FROM v_from_shift_id THEN
      RETURN jsonb_build_object('ok', false, 'error', 'ไม่สามารถแก้เป็นกะเดิมได้ หากไม่ต้องการย้ายกะแล้วให้ยกเลิกรายการแทน');
    END IF;

    UPDATE shift_swaps
      SET start_date = p_new_start_date, end_date = NULL, to_shift_id = v_to_shift_id, updated_at = now()
      WHERE id = p_id;

  ELSIF p_type = 'transfer' THEN
    SELECT user_id, to_branch_id, to_shift_id
    INTO v_user_id, v_branch_id, v_to_shift_id
    FROM cross_branch_transfers
    WHERE id = p_id AND status = 'approved'
    LIMIT 1;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'not_found_or_not_approved');
    END IF;

    IF EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head'::app_role)
      AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin'::app_role,'manager'::app_role)) THEN
      IF v_branch_id IS NULL OR v_branch_id != my_branch_id() THEN
        RAISE EXCEPTION 'Instructor head can only update within their branch';
      END IF;
    END IF;

    v_to_shift_id := COALESCE(p_new_to_shift_id, v_to_shift_id);
    UPDATE cross_branch_transfers
      SET start_date = p_new_start_date, end_date = NULL, to_shift_id = v_to_shift_id, updated_at = now()
      WHERE id = p_id;

  ELSE
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_type');
  END IF;

  RETURN jsonb_build_object('ok', true);
END;
$$;
