-- Migration 33: ห้ามจองพักอาหารนอกเวลากะ — ตรวจทั้ง slot_start และ slot_end ต้องอยู่ภายในช่วงกะ
-- ก่อนหน้ารองแค่ slot_start อยู่ในกะ ทำให้ slot ที่เลยเวลาออกกะ (เช่น 21:00-23:00 เมื่อกะ 08:00-20:00) จองได้

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

  IF now() < (p_work_date + (SELECT start_time FROM shifts WHERE id = v_shift_id))::TIMESTAMPTZ THEN
    RETURN jsonb_build_object('ok', false, 'error', 'before_shift_start');
  END IF;

  SELECT COUNT(*)::INT INTO v_meal_count FROM break_logs WHERE user_id = v_uid AND break_date = p_work_date AND break_type = 'MEAL' AND status = 'active';
  IF v_meal_count >= COALESCE((SELECT (rounds_json->>'max_per_work_date')::INT FROM meal_settings WHERE is_enabled = true ORDER BY effective_from DESC LIMIT 1), 2) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'max_meals_reached');
  END IF;

  IF EXISTS (SELECT 1 FROM break_logs WHERE user_id = v_uid AND break_date = p_work_date AND round_key = p_round_key AND break_type = 'MEAL' AND status = 'active') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_booked_this_round');
  END IF;

  SELECT (p_work_date + s.start_time)::TIMESTAMPTZ, (p_work_date + s.end_time)::TIMESTAMPTZ INTO v_shift_start_ts, v_shift_end_ts FROM shifts s WHERE s.id = v_shift_id LIMIT 1;
  IF v_shift_end_ts <= v_shift_start_ts THEN v_shift_end_ts := (p_work_date + 1 + (SELECT end_time FROM shifts WHERE id = v_shift_id))::TIMESTAMPTZ; END IF;

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

COMMENT ON FUNCTION book_meal_break(DATE,TEXT,TIMESTAMPTZ,TIMESTAMPTZ) IS 'จองพักอาหาร MEAL — ตรวจ slot ต้องอยู่ทั้งกะ (ทั้งเริ่มและจบภายในเวลากะ)';
