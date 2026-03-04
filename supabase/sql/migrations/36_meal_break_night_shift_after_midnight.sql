-- Migration 36: กะดึกหลังเที่ยงคืนให้จองพักอาหารได้
-- ปัญหา: book_meal_break ตรวจแค่ now() < (p_work_date + start_time) จึงถือว่าหลัง 00:00 ของ work_date = ยังไม่เข้ากะ
-- แก้: ถ้ากะดึก (end_time <= start_time) และ now() อยู่ในช่วง "กะที่จบในวัน work_date" (เมื่อวาน 20:00 - วันนี้ 08:00) ให้ถือว่าอยู่ในกะ
-- กระทบ: ฟังก์ชัน book_meal_break เท่านั้น ไม่เปลี่ยนตาราง/RLS

CREATE OR REPLACE FUNCTION book_meal_break(
  p_work_date DATE,
  p_round_key TEXT,
  p_slot_start_ts TIMESTAMPTZ,
  p_slot_end_ts TIMESTAMPTZ
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_branch_id UUID;
  v_shift_id UUID;
  v_website_id UUID;
  v_shift_start_ts TIMESTAMPTZ;
  v_shift_end_ts TIMESTAMPTZ;
  v_start_time TIME;
  v_end_time TIME;
  v_meal_count INT;
  v_cap JSONB;
  v_log_id UUID;
  v_ug TEXT;
BEGIN
  SELECT p.default_branch_id, p.default_shift_id INTO v_branch_id, v_shift_id FROM profiles p WHERE p.id = v_uid LIMIT 1;
  SELECT wa.website_id INTO v_website_id FROM website_assignments wa WHERE wa.user_id = v_uid AND wa.is_primary = true LIMIT 1;
  IF v_branch_id IS NULL OR v_shift_id IS NULL OR v_website_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_branch_shift_website');
  END IF;
  v_ug := (SELECT my_user_group());
  IF v_ug IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'invalid_user_group'); END IF;

  SELECT s.start_time, s.end_time INTO v_start_time, v_end_time FROM shifts s WHERE s.id = v_shift_id LIMIT 1;
  IF v_start_time IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'before_shift_start');
  END IF;

  -- ช่วงกะที่ "เริ่มในวัน work_date": work_date 20:00 -> work_date+1 08:00
  v_shift_start_ts := (p_work_date + v_start_time)::TIMESTAMPTZ;
  v_shift_end_ts := (p_work_date + v_end_time)::TIMESTAMPTZ;
  IF v_shift_end_ts <= v_shift_start_ts THEN
    v_shift_end_ts := (p_work_date + 1 + v_end_time)::TIMESTAMPTZ;
  END IF;

  -- กะดึก: ถ้า now() อยู่ในช่วงกะที่ "จบในวัน work_date" (เมื่อวาน 20:00 - วันนี้ 08:00) ใช้ช่วงนั้น
  IF v_end_time <= v_start_time THEN
    IF now() >= (p_work_date - 1 + v_start_time)::TIMESTAMPTZ AND now() < (p_work_date + v_end_time)::TIMESTAMPTZ THEN
      v_shift_start_ts := (p_work_date - 1 + v_start_time)::TIMESTAMPTZ;
      v_shift_end_ts := (p_work_date + v_end_time)::TIMESTAMPTZ;
    END IF;
  END IF;

  IF now() < v_shift_start_ts THEN
    RETURN jsonb_build_object('ok', false, 'error', 'before_shift_start');
  END IF;

  SELECT COUNT(*)::INT INTO v_meal_count FROM break_logs WHERE user_id = v_uid AND break_date = p_work_date AND break_type = 'MEAL' AND status = 'active';
  IF v_meal_count >= COALESCE((SELECT (rounds_json->>'max_per_work_date')::INT FROM meal_settings WHERE is_enabled = true ORDER BY effective_from DESC LIMIT 1), 2) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'max_meals_reached');
  END IF;

  IF EXISTS (SELECT 1 FROM break_logs WHERE user_id = v_uid AND break_date = p_work_date AND round_key = p_round_key AND break_type = 'MEAL' AND status = 'active') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_booked_this_round');
  END IF;

  -- ช่วงจองต้องอยู่ทั้งกะ: ทั้ง slot_start และ slot_end ต้องอยู่ใน [v_shift_start_ts, v_shift_end_ts]
  IF p_slot_start_ts < v_shift_start_ts OR p_slot_start_ts >= v_shift_end_ts
     OR p_slot_end_ts <= v_shift_start_ts OR p_slot_end_ts > v_shift_end_ts THEN
    RETURN jsonb_build_object('ok', false, 'error', 'slot_outside_shift');
  END IF;

  v_cap := get_meal_capacity_break_logs(v_branch_id, v_shift_id, v_website_id, p_work_date, p_round_key, p_slot_start_ts);
  IF (v_cap->>'is_full')::boolean THEN RETURN jsonb_build_object('ok', false, 'error', 'slot_full'); END IF;

  INSERT INTO break_logs (user_id, branch_id, shift_id, website_id, break_date, started_at, ended_at, status, user_group, break_type, round_key)
  VALUES (v_uid, v_branch_id, v_shift_id, v_website_id, p_work_date, p_slot_start_ts, p_slot_end_ts, 'active', v_ug, 'MEAL', p_round_key)
  RETURNING id INTO v_log_id;

  INSERT INTO audit_logs (actor_id, action, entity, entity_id, details_json, summary_text)
  VALUES (v_uid, 'meal_book', 'meal_booking', v_log_id,
    jsonb_build_object('work_date', p_work_date, 'round_key', p_round_key, 'slot_start_ts', p_slot_start_ts, 'slot_end_ts', p_slot_end_ts),
    'จองพักอาหาร ' || to_char(p_work_date, 'YYYY-MM-DD'));

  RETURN jsonb_build_object('ok', true, 'id', v_log_id);
END;
$$;
