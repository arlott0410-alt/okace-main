-- ==============================================================================
-- 06: อัปเดตโปรไฟล์ (กะ/แผนก) เมื่อถึงวันที่ตั้งเวลาย้ายกะ
-- ใช้เรียกทุกวัน (Supabase Cron หรือกดรันมือ) เพื่อให้ default_shift_id / default_branch_id สอดคล้องกับย้ายกะที่ effective
-- ==============================================================================

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
             ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY start_date DESC) AS rn
      FROM (
        SELECT user_id, branch_id AS to_branch_id, to_shift_id, start_date
        FROM shift_swaps
        WHERE status = 'approved' AND start_date <= p_date AND end_date >= p_date
        UNION ALL
        SELECT user_id, to_branch_id, to_shift_id, start_date
        FROM cross_branch_transfers
        WHERE status = 'approved' AND start_date <= p_date AND end_date >= p_date
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

GRANT EXECUTE ON FUNCTION apply_scheduled_shift_changes_for_date(DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION apply_scheduled_shift_changes_for_date(DATE) TO service_role;
