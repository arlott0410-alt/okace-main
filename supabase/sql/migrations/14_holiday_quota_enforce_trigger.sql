-- ========== 014: บังคับกติกาวันหยุดที่ DB (โควต้าต่อเดือน + โควต้าขั้นต่อวัน) ==========
-- 1) กติกากลาง: แต่ละคนจองวันหยุดได้ไม่เกิน max_holiday_days_per_person_per_month วัน/เดือน
-- 2) กติกาแบบขั้น (combined): วันนั้นในขอบเขตแผนก+กะ+กลุ่ม(+เว็บถ้าเปิด) หยุดได้ไม่เกิน max_leave คน
-- นับเฉพาะ leave_type = 'HOLIDAY' (วันหยุด) — วันลาอื่นๆ (ลากิจ, ลาพักร้อน, ขาดงาน ฯลฯ) ไม่นับรวมโควต้า

CREATE OR REPLACE FUNCTION holidays_check_quota()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_days INT;
  v_cnt INT;
  v_total_after INT;
  v_new_counts BOOLEAN;
  v_scope_by_website BOOLEAN := true;
  v_total_people INT;
  v_current_booked INT;
  v_max_leave INT;
  v_primary_website_id UUID;
BEGIN
  IF NEW.status NOT IN ('approved', 'pending') THEN
    RETURN NEW;
  END IF;

  v_new_counts := (NEW.leave_type IS NULL OR NEW.leave_type = 'HOLIDAY') AND (NEW.is_quota_exempt IS NULL OR NEW.is_quota_exempt = false);

  -- ----- 1) กติกากลาง: วัน/คน/เดือน (นับเฉพาะวันหยุด HOLIDAY) -----
  IF v_new_counts THEN
    SELECT COALESCE(ms.max_holiday_days_per_person_per_month, 4) INTO v_max_days
    FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;
    IF v_max_days IS NULL THEN v_max_days := 4; END IF;

    SELECT COUNT(*)::INT INTO v_cnt
    FROM holidays h
    WHERE h.user_id = NEW.user_id
      AND h.holiday_date >= date_trunc('month', NEW.holiday_date)::date
      AND h.holiday_date < date_trunc('month', NEW.holiday_date)::date + interval '1 month'
      AND h.status IN ('approved', 'pending')
      AND (h.leave_type IS NULL OR h.leave_type = 'HOLIDAY')
      AND (h.is_quota_exempt IS NULL OR h.is_quota_exempt = false)
      AND (TG_OP <> 'UPDATE' OR h.id <> NEW.id);

    v_total_after := v_cnt + 1;
    IF v_total_after > v_max_days THEN
      RAISE EXCEPTION 'เกินกติกากลาง: แต่ละคนจองวันหยุดได้สูงสุด % วัน/เดือน (คนนี้จะมี % วันในเดือนนี้)', v_max_days, v_total_after
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  -- ----- 2) กติกาแบบขั้น (combined): คน/วัน (นับเฉพาะวันหยุด HOLIDAY ที่ไม่ exempt) -----
  IF NEW.is_quota_exempt = true OR (NEW.leave_type IS NOT NULL AND NEW.leave_type <> 'HOLIDAY') THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(ms.scope_holiday_quota_by_website, true) INTO v_scope_by_website
  FROM meal_settings ms WHERE ms.is_enabled = true ORDER BY ms.effective_from DESC LIMIT 1;

  SELECT wa.website_id INTO v_primary_website_id
  FROM website_assignments wa WHERE wa.user_id = NEW.user_id AND wa.is_primary = true LIMIT 1;

  -- จำนวนคนในขอบเขตเดียวกัน (แผนก+กะ+กลุ่ม; ถ้าเปิดแยกเว็บ = เว็บเดียวกัน)
  IF v_scope_by_website AND v_primary_website_id IS NOT NULL THEN
    SELECT COUNT(*)::INT INTO v_total_people
    FROM profiles p
    INNER JOIN website_assignments wa ON wa.user_id = p.id AND wa.is_primary = true AND wa.website_id = v_primary_website_id
    WHERE p.default_branch_id = NEW.branch_id AND p.default_shift_id = NEW.shift_id
      AND (p.active IS NULL OR p.active = true)
      AND (
        (NEW.user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
        OR (NEW.user_group = 'STAFF' AND p.role = 'staff')
        OR (NEW.user_group = 'MANAGER' AND p.role = 'manager')
      );
  ELSE
    SELECT COUNT(*)::INT INTO v_total_people
    FROM profiles p
    WHERE p.default_branch_id = NEW.branch_id AND p.default_shift_id = NEW.shift_id
      AND (p.active IS NULL OR p.active = true)
      AND (
        (NEW.user_group = 'INSTRUCTOR' AND p.role IN ('instructor', 'instructor_head'))
        OR (NEW.user_group = 'STAFF' AND p.role = 'staff')
        OR (NEW.user_group = 'MANAGER' AND p.role = 'manager')
      );
  END IF;

  -- โควต้าขั้น: เลือก tier ที่ total_people <= max_people แล้วใช้ min(max_leave) (เข้มงวดที่สุด)
  SELECT MIN(hqt.max_leave) INTO v_max_leave
  FROM holiday_quota_tiers hqt
  WHERE hqt.dimension = 'combined'
    AND (hqt.user_group = NEW.user_group OR hqt.user_group IS NULL)
    AND v_total_people <= hqt.max_people;

  IF v_max_leave IS NULL THEN
    RETURN NEW;
  END IF;

  -- จำนวนคนที่จองวันนี้ในขอบเขตเดียวกัน (นับเฉพาะวันหยุด HOLIDAY ที่ไม่ exempt)
  IF v_scope_by_website AND v_primary_website_id IS NOT NULL THEN
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM holidays h
    INNER JOIN website_assignments wa ON wa.user_id = h.user_id AND wa.is_primary = true AND wa.website_id = v_primary_website_id
    WHERE h.holiday_date = NEW.holiday_date
      AND h.branch_id = NEW.branch_id AND h.shift_id = NEW.shift_id AND h.user_group = NEW.user_group
      AND h.status IN ('approved', 'pending') AND (h.leave_type IS NULL OR h.leave_type = 'HOLIDAY') AND (h.is_quota_exempt IS NULL OR h.is_quota_exempt = false)
      AND (TG_OP <> 'UPDATE' OR h.id <> NEW.id);
  ELSE
    SELECT COUNT(*)::INT INTO v_current_booked
    FROM holidays h
    WHERE h.holiday_date = NEW.holiday_date
      AND h.branch_id = NEW.branch_id AND h.shift_id = NEW.shift_id AND h.user_group = NEW.user_group
      AND h.status IN ('approved', 'pending') AND (h.leave_type IS NULL OR h.leave_type = 'HOLIDAY') AND (h.is_quota_exempt IS NULL OR h.is_quota_exempt = false)
      AND (TG_OP <> 'UPDATE' OR h.id <> NEW.id);
  END IF;

  v_current_booked := v_current_booked + 1;
  IF v_current_booked > v_max_leave THEN
    RAISE EXCEPTION 'โควต้าวันนี้เต็มแล้ว: ในกลุ่มแผนกกะเดียวกันหยุดได้สูงสุด % คน/วัน (วันนี้มี % คนแล้ว)', v_max_leave, v_current_booked - 1
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS holidays_check_quota_trigger ON holidays;
CREATE TRIGGER holidays_check_quota_trigger
  BEFORE INSERT OR UPDATE OF user_id, branch_id, shift_id, holiday_date, status, user_group, is_quota_exempt, leave_type
  ON holidays
  FOR EACH ROW
  EXECUTE PROCEDURE holidays_check_quota();

COMMENT ON FUNCTION holidays_check_quota() IS 'บังคับกติกาวันหยุด: นับเฉพาะ leave_type=HOLIDAY (1) สูงสุด X วัน/คน/เดือน (2) โควต้าขั้น combined ต่อวัน — วันลาอื่นๆ ไม่นับโควต้า';
