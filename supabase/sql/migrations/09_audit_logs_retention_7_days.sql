-- ---------- 09_audit_logs_retention_7_days.sql ----------
-- ลบประวัติการทำรายการ (audit_logs) ที่เก่ากว่า 7 วัน เพื่อประหยัดพื้นที่
-- เรียกจาก Supabase Cron ทุกวัน หรือรันมือ: SELECT delete_audit_logs_older_than_days(7);

CREATE OR REPLACE FUNCTION delete_audit_logs_older_than_days(p_days INT DEFAULT 7)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cutoff TIMESTAMPTZ;
  v_deleted BIGINT;
BEGIN
  IF p_days IS NULL OR p_days < 1 THEN
    RAISE EXCEPTION 'p_days must be >= 1';
  END IF;
  v_cutoff := now() - (p_days || ' days')::INTERVAL;
  WITH deleted AS (
    DELETE FROM audit_logs
    WHERE created_at < v_cutoff
    RETURNING id
  )
  SELECT COUNT(*)::BIGINT INTO v_deleted FROM deleted;
  RETURN v_deleted;
END;
$$;

COMMENT ON FUNCTION delete_audit_logs_older_than_days(INT) IS
  'ลบ audit_logs ที่ created_at เก่ากว่า p_days วัน คืนจำนวนแถวที่ลบ — ใช้กับ Cron รายวัน (เช่น 7 วัน)';
