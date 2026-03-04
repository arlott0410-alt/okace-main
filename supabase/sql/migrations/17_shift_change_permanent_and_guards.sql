-- ==============================================================================
-- 17: ย้ายกะ/สลับกะแบบถาวร + กันบั๊ก
-- - end_date = NULL หมายถึงถาวร
-- - start_date ต้อง >= วันพรุ่งนี้ (Asia/Bangkok) ทั้ง insert และ update
-- - apply_scheduled_shift_changes_for_date: เลือกรายการล่าสุดที่มีผลต่อวัน, idempotent
-- - apply_bulk_assignment / apply_paired_swap: บันทึกแบบถาวร (end_date NULL), validate start_date
-- - update_scheduled_shift_change: validate วันที่ใหม่ >= พรุ่งนี้, ตั้ง end_date = NULL
-- ==============================================================================

-- -----------------------------------------------------------------------------
-- A) Allow end_date NULL (permanent)
-- -----------------------------------------------------------------------------
ALTER TABLE shift_swaps
  ALTER COLUMN end_date DROP NOT NULL;

ALTER TABLE cross_branch_transfers
  ALTER COLUMN end_date DROP NOT NULL;

-- -----------------------------------------------------------------------------
-- Helper: วันพรุ่งนี้ใน timezone Asia/Bangkok
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tomorrow_bangkok()
RETURNS DATE
LANGUAGE sql
STABLE
AS $$
  SELECT ((now() AT TIME ZONE 'Asia/Bangkok')::date + 1);
$$;

-- -----------------------------------------------------------------------------
-- Trigger: start_date must be >= tomorrow (Bangkok) on insert and update
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_shift_change_start_date()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.start_date IS NULL THEN
    RAISE EXCEPTION 'START_DATE_MUST_BE_TOMORROW_OR_LATER' USING errcode = 'P0001';
  END IF;
  IF NEW.start_date < tomorrow_bangkok() THEN
    RAISE EXCEPTION 'START_DATE_MUST_BE_TOMORROW_OR_LATER: วันที่มีผลต้องเป็นวันพรุ่งนี้ขึ้นไป (Asia/Bangkok)'
      USING errcode = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS shift_swaps_start_date_tomorrow ON shift_swaps;
CREATE TRIGGER shift_swaps_start_date_tomorrow
  BEFORE INSERT OR UPDATE OF start_date ON shift_swaps
  FOR EACH ROW EXECUTE PROCEDURE check_shift_change_start_date();

DROP TRIGGER IF EXISTS cross_branch_transfers_start_date_tomorrow ON cross_branch_transfers;
CREATE TRIGGER cross_branch_transfers_start_date_tomorrow
  BEFORE INSERT OR UPDATE OF start_date ON cross_branch_transfers
  FOR EACH ROW EXECUTE PROCEDURE check_shift_change_start_date();

-- -----------------------------------------------------------------------------
-- B) apply_scheduled_shift_changes_for_date: ล่าสุดที่มีผลต่อวัน, รองรับ end_date NULL, idempotent
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION apply_scheduled_shift_changes_for_date(p_date DATE)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  uid UUID;
  to_br UUID;
  to_sh UUID;
  updated_count INT := 0;
BEGIN
  IF p_date IS NULL THEN RETURN 0; END IF;

  FOR r IN (
    SELECT user_id, to_branch_id, to_shift_id
    FROM (
      SELECT user_id, to_branch_id, to_shift_id,
             ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC NULLS LAST, start_date DESC) AS rn
      FROM (
        SELECT user_id, branch_id AS to_branch_id, to_shift_id, start_date, created_at
        FROM shift_swaps
        WHERE status = 'approved'
          AND start_date <= p_date
          AND (end_date IS NULL OR p_date <= end_date)
        UNION ALL
        SELECT user_id, to_branch_id, to_shift_id, start_date, created_at
        FROM cross_branch_transfers
        WHERE status = 'approved'
          AND start_date <= p_date
          AND (end_date IS NULL OR p_date <= end_date)
      ) combined
    ) sub
    WHERE rn = 1
  ) LOOP
    uid := r.user_id;
    to_br := r.to_branch_id;
    to_sh := r.to_shift_id;
    IF uid IS NOT NULL AND to_sh IS NOT NULL THEN
      UPDATE profiles
      SET default_shift_id = to_sh,
          default_branch_id = COALESCE(to_br, default_branch_id),
          updated_at = now()
      WHERE id = uid
        AND (default_shift_id IS DISTINCT FROM to_sh OR default_branch_id IS DISTINCT FROM COALESCE(to_br, default_branch_id));
      IF FOUND THEN
        updated_count := updated_count + 1;
      END IF;
    END IF;
  END LOOP;

  RETURN updated_count;
END;
$$;

-- -----------------------------------------------------------------------------
-- C) apply_bulk_assignment: validate start_date >= tomorrow, insert ถาวร (end_date NULL), ไม่แก้ roster
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION apply_bulk_assignment(
  p_employee_ids UUID[],
  p_start_date DATE,
  p_end_date DATE,
  p_to_branch_id UUID,
  p_to_shift_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  may_run BOOLEAN;
  is_head BOOLEAN;
  emp_id UUID;
  from_branch_id UUID;
  from_shift_id UUID;
  applied_count INT := 0;
  out_skipped JSONB := '{}'::JSONB;
  has_scheduled BOOLEAN;
BEGIN
  IF p_start_date IS NULL OR p_start_date < tomorrow_bangkok() THEN
    RAISE EXCEPTION 'START_DATE_MUST_BE_TOMORROW_OR_LATER'
      USING errcode = 'P0001';
  END IF;

  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin','manager'));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head');
  IF NOT may_run AND NOT is_head THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can run bulk assignment';
  END IF;
  IF is_head AND NOT may_run THEN
    IF p_to_branch_id IS NULL OR p_to_branch_id != my_branch_id() THEN
      RAISE EXCEPTION 'Instructor head can only assign to their own branch';
    END IF;
  END IF;

  FOR emp_id IN SELECT unnest(p_employee_ids)
  LOOP
    SELECT EXISTS (
      SELECT 1 FROM shift_swaps s
      WHERE s.user_id = emp_id AND s.status = 'approved' AND s.start_date >= current_date
        AND (s.end_date IS NULL OR s.end_date >= current_date)
      UNION ALL
      SELECT 1 FROM cross_branch_transfers t
      WHERE t.user_id = emp_id AND t.status = 'approved' AND t.start_date >= current_date
        AND (t.end_date IS NULL OR t.end_date >= current_date)
    ) INTO has_scheduled;

    IF has_scheduled THEN
      out_skipped := out_skipped || jsonb_build_object(emp_id::text, to_jsonb(ARRAY[p_start_date]::text[]));
    ELSE
      SELECT p.default_branch_id, p.default_shift_id INTO from_branch_id, from_shift_id
        FROM profiles p WHERE p.id = emp_id LIMIT 1;
      IF from_branch_id IS NULL THEN from_branch_id := p_to_branch_id; END IF;
      IF from_shift_id IS NULL THEN from_shift_id := p_to_shift_id; END IF;

      IF from_branch_id = p_to_branch_id THEN
        IF from_shift_id IS DISTINCT FROM p_to_shift_id THEN
          INSERT INTO shift_swaps (
            user_id, branch_id, from_shift_id, to_shift_id,
            start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
          ) VALUES (
            emp_id, from_branch_id, from_shift_id, p_to_shift_id,
            p_start_date, NULL, p_reason, 'approved', uid, now(), NULL
          );
          applied_count := applied_count + 1;
        END IF;
      ELSE
        INSERT INTO cross_branch_transfers (
          user_id, from_branch_id, to_branch_id, from_shift_id, to_shift_id,
          start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
        ) VALUES (
          emp_id, from_branch_id, p_to_branch_id, from_shift_id, p_to_shift_id,
          p_start_date, NULL, p_reason, 'approved', uid, now(), NULL
        );
        applied_count := applied_count + 1;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'applied', applied_count,
    'skipped_per_user', out_skipped
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- D) apply_paired_swap: validate start_date >= tomorrow, insert ถาวร, กัน overlap
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION apply_paired_swap(
  p_branch_id UUID,
  p_start_date DATE,
  p_end_date DATE,
  p_assignments JSONB,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_uid UUID := auth.uid();
  may_run BOOLEAN;
  is_head BOOLEAN;
  rec JSONB;
  emp_id UUID;
  to_shift_id UUID;
  from_shift_id UUID;
  applied_count INT := 0;
  out_skipped JSONB := '{}'::JSONB;
  i INT;
  has_scheduled BOOLEAN;
  overlap_user UUID;
BEGIN
  IF p_start_date IS NULL OR p_start_date < tomorrow_bangkok() THEN
    RAISE EXCEPTION 'START_DATE_MUST_BE_TOMORROW_OR_LATER'
      USING errcode = 'P0001';
  END IF;

  may_run := EXISTS (SELECT 1 FROM profiles WHERE id = caller_uid AND role IN ('admin','manager'));
  is_head := EXISTS (SELECT 1 FROM profiles WHERE id = caller_uid AND role = 'instructor_head');
  IF NOT may_run AND NOT is_head THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can run paired swap';
  END IF;
  IF is_head AND NOT may_run THEN
    IF p_branch_id IS NULL OR p_branch_id != my_branch_id() THEN
      RAISE EXCEPTION 'Instructor head can only assign to their own branch';
    END IF;
  END IF;

  -- Overlap check: any user in assignments already has an active (approved, effective at p_start_date) shift change?
  FOR i IN 0 .. jsonb_array_length(p_assignments) - 1 LOOP
    rec := p_assignments->i;
    emp_id := (rec->>'user_id')::UUID;
    IF emp_id IS NULL THEN CONTINUE; END IF;
    SELECT EXISTS (
      SELECT 1 FROM shift_swaps s
      WHERE s.user_id = emp_id AND s.status = 'approved' AND s.start_date <= p_start_date
        AND (s.end_date IS NULL OR p_start_date <= s.end_date)
      UNION ALL
      SELECT 1 FROM cross_branch_transfers t
      WHERE t.user_id = emp_id AND t.status = 'approved' AND t.start_date <= p_start_date
        AND (t.end_date IS NULL OR p_start_date <= t.end_date)
    ) INTO has_scheduled;
    IF has_scheduled THEN
      RAISE EXCEPTION 'SHIFT_CHANGE_OVERLAP_CONFLICT: ผู้ใช้มีรายการย้ายกะ/สลับกะที่ยังมีผลอยู่'
        USING errcode = 'P0001';
    END IF;
  END LOOP;

  WITH elem AS (
    SELECT (e->>'user_id')::UUID AS elem_uid, (e->>'to_shift_id')::UUID AS elem_sid, ord
    FROM jsonb_array_elements(p_assignments) WITH ORDINALITY AS t(e, ord)
    WHERE (e->>'user_id')::UUID IS NOT NULL AND (e->>'to_shift_id')::UUID IS NOT NULL
  ),
  deduped AS (
    SELECT elem_uid, elem_sid, ROW_NUMBER() OVER (PARTITION BY elem_uid ORDER BY ord DESC) AS rn FROM elem
  )
  SELECT jsonb_agg(jsonb_build_object('user_id', d.elem_uid, 'to_shift_id', d.elem_sid))
  INTO p_assignments
  FROM (SELECT elem_uid, elem_sid FROM deduped WHERE rn = 1) d;

  IF p_assignments IS NULL THEN p_assignments := '[]'::JSONB; END IF;

  FOR i IN 0 .. jsonb_array_length(p_assignments) - 1 LOOP
    rec := p_assignments->i;
    emp_id := (rec->>'user_id')::UUID;
    to_shift_id := (rec->>'to_shift_id')::UUID;
    IF emp_id IS NULL OR to_shift_id IS NULL THEN CONTINUE; END IF;

    SELECT p.default_shift_id INTO from_shift_id
      FROM profiles p WHERE p.id = emp_id LIMIT 1;
    IF from_shift_id IS NULL THEN from_shift_id := to_shift_id; END IF;

    IF from_shift_id IS DISTINCT FROM to_shift_id THEN
      INSERT INTO shift_swaps (
        user_id, branch_id, from_shift_id, to_shift_id,
        start_date, end_date, reason, status, approved_by, approved_at, skipped_dates
      ) VALUES (
        emp_id, p_branch_id, from_shift_id, to_shift_id,
        p_start_date, NULL, p_reason, 'approved', caller_uid, now(), NULL
      );
      applied_count := applied_count + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'applied', applied_count,
    'skipped_per_user', out_skipped
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- E) update_scheduled_shift_change: validate p_new_start_date >= tomorrow, set end_date = NULL
-- -----------------------------------------------------------------------------
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
BEGIN
  IF p_new_start_date IS NULL OR p_new_start_date < tomorrow_bangkok() THEN
    RAISE EXCEPTION 'START_DATE_MUST_BE_TOMORROW_OR_LATER'
      USING errcode = 'P0001';
  END IF;

  IF NOT (EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin','manager','instructor_head'))) THEN
    RAISE EXCEPTION 'Only admin, manager, or instructor_head can update scheduled shift change';
  END IF;

  IF p_type = 'swap' THEN
    SELECT user_id, branch_id, to_shift_id INTO v_user_id, v_branch_id, v_to_shift_id
      FROM shift_swaps WHERE id = p_id AND status = 'approved' LIMIT 1;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'not_found_or_not_approved');
    END IF;
    IF EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head') AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin','manager')) THEN
      IF v_branch_id IS NULL OR v_branch_id != my_branch_id() THEN
        RAISE EXCEPTION 'Instructor head can only update within their branch';
      END IF;
    END IF;
    v_to_shift_id := COALESCE(p_new_to_shift_id, v_to_shift_id);
    UPDATE shift_swaps
      SET start_date = p_new_start_date, end_date = NULL, to_shift_id = v_to_shift_id, updated_at = now()
      WHERE id = p_id;
  ELSIF p_type = 'transfer' THEN
    SELECT user_id, to_branch_id, to_shift_id INTO v_user_id, v_branch_id, v_to_shift_id
      FROM cross_branch_transfers WHERE id = p_id AND status = 'approved' LIMIT 1;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'not_found_or_not_approved');
    END IF;
    IF EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role = 'instructor_head') AND NOT EXISTS (SELECT 1 FROM profiles WHERE id = uid AND role IN ('admin','manager')) THEN
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

-- -----------------------------------------------------------------------------
-- F) cron_runs table for logging (optional debug)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cron_runs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_name TEXT NOT NULL,
  ran_at TIMESTAMPTZ DEFAULT now(),
  p_date DATE,
  success BOOLEAN NOT NULL,
  result_count INT,
  error_message TEXT
);

-- Wrapper สำหรับ Cron: รัน apply แล้ว log
CREATE OR REPLACE FUNCTION run_apply_shift_changes_and_log()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  p_date DATE := ((now() AT TIME ZONE 'Asia/Bangkok')::date);
  cnt INT;
BEGIN
  cnt := apply_scheduled_shift_changes_for_date(p_date);
  INSERT INTO cron_runs (job_name, p_date, success, result_count)
  VALUES ('apply_scheduled_shift_changes_for_date', p_date, true, cnt);
  RETURN cnt;
EXCEPTION WHEN OTHERS THEN
  INSERT INTO cron_runs (job_name, p_date, success, error_message)
  VALUES ('apply_scheduled_shift_changes_for_date', p_date, false, SQLERRM);
  RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION run_apply_shift_changes_and_log() TO service_role;
