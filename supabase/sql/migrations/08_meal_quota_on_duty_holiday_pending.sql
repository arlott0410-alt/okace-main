-- ---------- 08_meal_quota_on_duty_holiday_pending.sql ----------
-- โควต้าพักอาหาร: นับ "คนอยู่ปฏิบัติ" แบบ realtime ตามตารางวันหยุด (holidays)
-- รวมทั้ง approved และ pending — ให้ตรงกับจัดหน้าที่ (DutyBoard) และกติกา tier (คนน้อยลงใช้ tier ที่ตั้งไว้)

CREATE OR REPLACE FUNCTION get_meal_on_duty_user_ids(p_work_date DATE)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_branch_id UUID;
  v_shift_id UUID;
  v_website_id UUID;
  v_holiday_date DATE := p_work_date;
  v_user_group TEXT;
  v_scope_by_website BOOLEAN := true;
  v_result JSONB;
BEGIN
  SELECT p.default_branch_id, p.default_shift_id INTO v_branch_id, v_shift_id FROM profiles p WHERE p.id = v_uid LIMIT 1;
  SELECT wa.website_id INTO v_website_id FROM website_assignments wa WHERE wa.user_id = v_uid AND wa.is_primary = true LIMIT 1;

  IF v_branch_id IS NULL OR v_shift_id IS NULL OR v_website_id IS NULL THEN
    RETURN '[]'::JSONB;
  END IF;

  v_user_group := my_user_group();
  SELECT COALESCE(ms.scope_meal_quota_by_website, true) INTO v_scope_by_website
  FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;

  IF v_scope_by_website THEN
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      INNER JOIN website_assignments wa
        ON wa.user_id = p.id
       AND wa.website_id = v_website_id
       AND wa.is_primary = true
      WHERE p.default_branch_id = v_branch_id
        AND p.default_shift_id = v_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status IN ('approved', 'pending')
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
        )
    )
    SELECT COALESCE(jsonb_agg(id ORDER BY id), '[]'::JSONB) INTO v_result FROM eligible;
  ELSE
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      WHERE p.default_branch_id = v_branch_id
        AND p.default_shift_id = v_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status IN ('approved', 'pending')
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
        )
    )
    SELECT COALESCE(jsonb_agg(id ORDER BY id), '[]'::JSONB) INTO v_result FROM eligible;
  END IF;

  RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;

CREATE OR REPLACE FUNCTION get_meal_capacity_break_logs(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_work_date DATE,
  p_round_key TEXT,
  p_slot_start_ts TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_holiday_date DATE;
  v_on_duty_count INT;
  v_max_concurrent INT;
  v_current_booked INT;
  v_user_group TEXT;
  v_scope_by_website BOOLEAN := true;
  v_booked_user_ids JSONB;
BEGIN
  v_holiday_date := DATE(p_slot_start_ts);
  v_user_group := my_user_group();

  SELECT COALESCE(ms.scope_meal_quota_by_website, true) INTO v_scope_by_website
  FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;

  IF v_scope_by_website THEN
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      INNER JOIN website_assignments wa
        ON wa.user_id = p.id
       AND wa.website_id = p_website_id
       AND wa.is_primary = true
      WHERE p.default_branch_id = p_branch_id
        AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status IN ('approved', 'pending')
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
        )
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;

    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id
      AND shift_id = p_shift_id
      AND website_id = p_website_id
      AND break_date = p_work_date
      AND round_key = p_round_key
      AND started_at = p_slot_start_ts
      AND break_type = 'MEAL'
      AND status = 'active'
      AND (user_group = v_user_group OR v_user_group IS NULL);

    SELECT COALESCE(jsonb_agg(bl.user_id ORDER BY bl.user_id), '[]'::JSONB) INTO v_booked_user_ids
    FROM break_logs bl
    WHERE bl.branch_id = p_branch_id
      AND bl.shift_id = p_shift_id
      AND bl.website_id = p_website_id
      AND bl.break_date = p_work_date
      AND bl.round_key = p_round_key
      AND bl.started_at = p_slot_start_ts
      AND bl.break_type = 'MEAL'
      AND bl.status = 'active'
      AND (bl.user_group = v_user_group OR v_user_group IS NULL);
  ELSE
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      WHERE p.default_branch_id = p_branch_id
        AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (
          SELECT 1 FROM holidays h
          WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status IN ('approved', 'pending')
        )
        AND (
          v_user_group IS NULL
          OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
          OR (v_user_group = 'STAFF' AND p.role = 'staff')
          OR (v_user_group = 'MANAGER' AND p.role = 'manager')
        )
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;

    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id
      AND shift_id = p_shift_id
      AND break_date = p_work_date
      AND round_key = p_round_key
      AND started_at = p_slot_start_ts
      AND break_type = 'MEAL'
      AND status = 'active'
      AND (user_group = v_user_group OR v_user_group IS NULL);

    SELECT COALESCE(jsonb_agg(bl.user_id ORDER BY bl.user_id), '[]'::JSONB) INTO v_booked_user_ids
    FROM break_logs bl
    WHERE bl.branch_id = p_branch_id
      AND bl.shift_id = p_shift_id
      AND bl.break_date = p_work_date
      AND bl.round_key = p_round_key
      AND bl.started_at = p_slot_start_ts
      AND bl.break_type = 'MEAL'
      AND bl.status = 'active'
      AND (bl.user_group = v_user_group OR v_user_group IS NULL);
  END IF;

  v_max_concurrent := get_meal_quota_for_group(p_branch_id, p_shift_id, p_website_id, v_user_group, v_on_duty_count);

  RETURN jsonb_build_object(
    'on_duty_count', v_on_duty_count,
    'max_concurrent', v_max_concurrent,
    'current_booked', v_current_booked,
    'is_full', (v_current_booked >= v_max_concurrent),
    'booked_user_ids', COALESCE(v_booked_user_ids, '[]'::JSONB)
  );
END;
$$;
