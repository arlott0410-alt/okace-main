-- ========== 015: โควต้าพักอาหาร — ยึดขั้นที่น้อยที่สุดก่อน (คนอยู่ปฏิบัติ ≤ X ใช้ tier แรกที่เข้าเงื่อนไข) ==========
-- ตัวอย่าง: นับได้ 2 คน → เข้าเงื่อนไขขั้นแรก "คนอยู่ปฏิบัติ (≤) 4" → จองได้แค่ 1 คน
-- เลือก tier โดย ORDER BY on_duty_threshold ASC LIMIT 1 แล้วใช้ max_concurrent ของแถวนั้น (ไม่ใช้ MIN ทุกแถว)

CREATE OR REPLACE FUNCTION get_meal_quota_for_group(
  p_branch_id UUID,
  p_shift_id UUID,
  p_website_id UUID,
  p_user_group TEXT,
  p_on_duty_count INT
)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    (
      SELECT mqr.max_concurrent
      FROM meal_quota_rules mqr
      WHERE
        (mqr.branch_id = p_branch_id OR mqr.branch_id IS NULL)
        AND (mqr.shift_id = p_shift_id OR mqr.shift_id IS NULL)
        AND (mqr.website_id = p_website_id OR mqr.website_id IS NULL)
        AND (mqr.user_group = p_user_group OR mqr.user_group IS NULL)
        AND mqr.on_duty_threshold >= p_on_duty_count
      ORDER BY mqr.on_duty_threshold ASC
      LIMIT 1
    ),
    1
  );
$$;

COMMENT ON FUNCTION get_meal_quota_for_group(UUID,UUID,UUID,TEXT,INT) IS
  'โควต้าพักอาหาร: ใช้ขั้นที่น้อยที่สุดก่อน — เลือก tier ที่ on_duty_threshold น้อยที่สุดที่ >= count แล้วใช้ max_concurrent ของขั้นนั้น (เช่น 2 คน → tier ≤4 → จองได้ 1 คน)';

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
      INNER JOIN website_assignments wa ON wa.user_id = p.id AND wa.website_id = p_website_id AND wa.is_primary = true
      WHERE p.default_branch_id = p_branch_id AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (SELECT 1 FROM holidays h WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status IN ('approved', 'pending'))
        AND (v_user_group IS NULL OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head')) OR (v_user_group = 'STAFF' AND p.role = 'staff') OR (v_user_group = 'MANAGER' AND p.role = 'manager'))
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;

    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id AND shift_id = p_shift_id AND website_id = p_website_id
      AND break_date = p_work_date AND round_key = p_round_key AND started_at = p_slot_start_ts
      AND break_type = 'MEAL' AND status = 'active' AND (user_group = v_user_group OR v_user_group IS NULL);

    SELECT COALESCE(jsonb_agg(bl.user_id ORDER BY bl.user_id), '[]'::JSONB) INTO v_booked_user_ids
    FROM break_logs bl
    WHERE bl.branch_id = p_branch_id AND bl.shift_id = p_shift_id AND bl.website_id = p_website_id
      AND bl.break_date = p_work_date AND bl.round_key = p_round_key AND bl.started_at = p_slot_start_ts
      AND bl.break_type = 'MEAL' AND bl.status = 'active' AND (bl.user_group = v_user_group OR v_user_group IS NULL);
  ELSE
    WITH eligible AS (
      SELECT p.id
      FROM profiles p
      WHERE p.default_branch_id = p_branch_id AND p.default_shift_id = p_shift_id
        AND (p.active IS NULL OR p.active = true)
        AND NOT EXISTS (SELECT 1 FROM holidays h WHERE h.user_id = p.id AND h.holiday_date = v_holiday_date AND h.status IN ('approved', 'pending'))
        AND (v_user_group IS NULL OR (v_user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head')) OR (v_user_group = 'STAFF' AND p.role = 'staff') OR (v_user_group = 'MANAGER' AND p.role = 'manager'))
    )
    SELECT COUNT(*)::INT INTO v_on_duty_count FROM eligible;

    SELECT COUNT(*)::INT INTO v_current_booked
    FROM break_logs
    WHERE branch_id = p_branch_id AND shift_id = p_shift_id AND break_date = p_work_date
      AND round_key = p_round_key AND started_at = p_slot_start_ts
      AND break_type = 'MEAL' AND status = 'active' AND (user_group = v_user_group OR v_user_group IS NULL);

    SELECT COALESCE(jsonb_agg(bl.user_id ORDER BY bl.user_id), '[]'::JSONB) INTO v_booked_user_ids
    FROM break_logs bl
    WHERE bl.branch_id = p_branch_id AND bl.shift_id = p_shift_id AND bl.break_date = p_work_date
      AND bl.round_key = p_round_key AND bl.started_at = p_slot_start_ts
      AND bl.break_type = 'MEAL' AND bl.status = 'active' AND (bl.user_group = v_user_group OR v_user_group IS NULL);
  END IF;

  -- ขั้นที่น้อยที่สุดก่อน: เลือก tier ที่ on_duty_threshold น้อยที่สุดที่ >= v_on_duty_count
  SELECT COALESCE(
    (
      SELECT mqr.max_concurrent
      FROM meal_quota_rules mqr
      WHERE (mqr.branch_id = p_branch_id OR mqr.branch_id IS NULL)
        AND (mqr.shift_id = p_shift_id OR mqr.shift_id IS NULL)
        AND (mqr.website_id = p_website_id OR mqr.website_id IS NULL)
        AND (mqr.user_group = v_user_group OR mqr.user_group IS NULL)
        AND mqr.on_duty_threshold >= v_on_duty_count
      ORDER BY mqr.on_duty_threshold ASC
      LIMIT 1
    ),
    1
  ) INTO v_max_concurrent;

  -- บังคับกติกา: คนอยู่ปฏิบัติ ≤ 4 → จองได้สูงสุด 1 คน (ขั้นแรกที่ตั้งค่า) แม้ตาราง tier จะไม่มีแถว (4,1) หรือ dimension ไม่ตรง
  IF v_on_duty_count <= 4 AND v_max_concurrent > 1 THEN
    v_max_concurrent := 1;
  END IF;

  RETURN jsonb_build_object(
    'on_duty_count', v_on_duty_count,
    'max_concurrent', v_max_concurrent,
    'current_booked', v_current_booked,
    'is_full', (v_current_booked >= v_max_concurrent),
    'booked_user_ids', COALESCE(v_booked_user_ids, '[]'::JSONB)
  );
END;
$$;

COMMENT ON FUNCTION get_meal_capacity_break_logs(UUID,UUID,UUID,DATE,TEXT,TIMESTAMPTZ) IS
  'โควต้าพักอาหาร: นับแค่คนอยู่หน้างาน (แผนก+กะ+กลุ่ม+เว็บถ้าเปิด, active, ไม่หยุด) — ยึดขั้นที่น้อยที่สุดก่อน (tier แรกที่เข้าเงื่อนไข)';
