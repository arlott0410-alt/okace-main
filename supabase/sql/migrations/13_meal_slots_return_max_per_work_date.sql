-- ========== 013: คืน max_per_work_date ใน get_meal_slots_unified ==========
-- ให้หน้า Meal ใช้กติกา "จำนวนจองสูงสุดต่อวัน" จากตั้งค่า (rounds_json.max_per_work_date) แทนค่าคงที่

CREATE OR REPLACE FUNCTION get_meal_slots_unified(p_work_date DATE)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_branch_id UUID;
  v_shift_id UUID;
  v_website_id UUID;
  v_shift_start_ts TIMESTAMPTZ;
  v_shift_end_ts TIMESTAMPTZ;
  v_shift_start_time TIME;
  v_settings JSONB;
  v_rounds JSONB;
  v_round JSONB;
  v_slot JSONB;
  v_round_key TEXT;
  v_slot_start_ts TIMESTAMPTZ;
  v_slot_end_ts TIMESTAMPTZ;
  v_cap JSONB;
  v_my_bookings JSONB := '[]'::JSONB;
  v_meal_count INT;
  v_out_rounds JSONB := '[]'::JSONB;
  v_slots_in_round JSONB;
  v_booked_count INT;
  v_max_concurrent INT;
  v_is_booked_by_me BOOLEAN;
  v_available BOOLEAN;
  v_on_duty_user_ids JSONB;
  i INT; j INT;
BEGIN
  SELECT p.default_branch_id, p.default_shift_id INTO v_branch_id, v_shift_id FROM profiles p WHERE p.id = v_uid LIMIT 1;
  SELECT wa.website_id INTO v_website_id FROM website_assignments wa WHERE wa.user_id = v_uid AND wa.is_primary = true LIMIT 1;

  IF v_branch_id IS NULL OR v_shift_id IS NULL OR v_website_id IS NULL THEN
    RETURN jsonb_build_object('error', 'missing_branch_shift_website', 'rounds', '[]'::JSONB, 'my_bookings', '[]'::JSONB, 'meal_count', 0, 'on_duty_user_ids', '[]'::JSONB, 'max_per_work_date', 2);
  END IF;

  v_on_duty_user_ids := get_meal_on_duty_user_ids(p_work_date);

  SELECT s.start_time, (p_work_date + s.start_time)::TIMESTAMPTZ, (p_work_date + s.end_time)::TIMESTAMPTZ
  INTO v_shift_start_time, v_shift_start_ts, v_shift_end_ts
  FROM shifts s WHERE s.id = v_shift_id LIMIT 1;
  IF v_shift_start_ts IS NULL THEN
    RETURN jsonb_build_object('error', 'shift_not_found', 'rounds', '[]'::JSONB, 'my_bookings', '[]'::JSONB, 'meal_count', 0, 'on_duty_user_ids', v_on_duty_user_ids, 'max_per_work_date', 2);
  END IF;
  IF v_shift_end_ts <= v_shift_start_ts THEN
    v_shift_end_ts := (p_work_date + 1 + (SELECT end_time FROM shifts WHERE id = v_shift_id))::TIMESTAMPTZ;
  END IF;

  SELECT rounds_json INTO v_settings FROM meal_settings WHERE is_enabled = true ORDER BY effective_from DESC LIMIT 1;
  IF v_settings IS NULL OR (v_settings->'rounds') IS NULL THEN
    RETURN jsonb_build_object('work_date', p_work_date, 'shift_start_ts', v_shift_start_ts, 'shift_end_ts', v_shift_end_ts, 'rounds', '[]'::JSONB, 'my_bookings', '[]'::JSONB, 'meal_count', 0, 'on_duty_user_ids', v_on_duty_user_ids, 'max_per_work_date', 2);
  END IF;
  v_rounds := v_settings->'rounds';

  SELECT COUNT(*)::INT INTO v_meal_count
  FROM break_logs WHERE user_id = v_uid AND break_date = p_work_date AND break_type = 'MEAL' AND status = 'active';

  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'round_key', round_key, 'slot_start_ts', started_at, 'slot_end_ts', ended_at)), '[]'::JSONB) INTO v_my_bookings
  FROM break_logs
  WHERE user_id = v_uid AND break_date = p_work_date AND break_type = 'MEAL' AND status = 'active';

  FOR i IN 0 .. jsonb_array_length(v_rounds) - 1 LOOP
    v_round := v_rounds->i;
    v_round_key := v_round->>'key';
    IF v_round_key IS NULL OR v_round_key = '' THEN v_round_key := 'round_' || i; END IF;
    v_slots_in_round := '[]'::JSONB;
    FOR j IN 0 .. jsonb_array_length(COALESCE(v_round->'slots', '[]'::JSONB)) - 1 LOOP
      v_slot := (v_round->'slots')->j;
      v_slot_start_ts := (p_work_date + ((v_slot->>'start')::TIME))::TIMESTAMPTZ;
      v_slot_end_ts := (p_work_date + ((v_slot->>'end')::TIME))::TIMESTAMPTZ;
      IF v_shift_end_ts <= v_shift_start_ts AND ((v_slot->>'start')::TIME) < v_shift_start_time THEN
        v_slot_start_ts := (p_work_date + 1 + ((v_slot->>'start')::TIME))::TIMESTAMPTZ;
        v_slot_end_ts := (p_work_date + 1 + ((v_slot->>'end')::TIME))::TIMESTAMPTZ;
      ELSIF v_slot_end_ts <= v_slot_start_ts THEN
        v_slot_end_ts := (p_work_date + 1 + ((v_slot->>'end')::TIME))::TIMESTAMPTZ;
      END IF;
      v_cap := get_meal_capacity_break_logs(v_branch_id, v_shift_id, v_website_id, p_work_date, v_round_key, v_slot_start_ts);
      v_booked_count := COALESCE((v_cap->>'current_booked')::INT, 0);
      v_max_concurrent := COALESCE((v_cap->>'max_concurrent')::INT, 1);
      SELECT EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_my_bookings) AS el
        WHERE (el->>'slot_start_ts')::timestamptz = v_slot_start_ts
      ) INTO v_is_booked_by_me;
      v_available := (v_booked_count < v_max_concurrent) AND NOT v_is_booked_by_me;

      v_slots_in_round := v_slots_in_round || jsonb_build_array(jsonb_build_object(
        'slot_start', v_slot->>'start', 'slot_end', v_slot->>'end',
        'slot_start_ts', v_slot_start_ts, 'slot_end_ts', v_slot_end_ts,
        'booked_count', v_booked_count, 'max_concurrent', v_max_concurrent,
        'is_booked_by_me', v_is_booked_by_me, 'available', v_available,
        'capacity', v_cap
      ));
    END LOOP;
    v_out_rounds := v_out_rounds || jsonb_build_array(jsonb_build_object(
      'round_key', v_round_key, 'round_name', v_round->>'name', 'slots', v_slots_in_round
    ));
  END LOOP;

  RETURN jsonb_build_object(
    'work_date', p_work_date,
    'shift_start_ts', v_shift_start_ts,
    'shift_end_ts', v_shift_end_ts,
    'rounds', v_out_rounds,
    'my_bookings', v_my_bookings,
    'meal_count', v_meal_count,
    'on_duty_user_ids', v_on_duty_user_ids,
    'max_per_work_date', COALESCE((v_settings->>'max_per_work_date')::INT, 2)
  );
END;
$$;
