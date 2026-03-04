-- ==============================================================================
-- 19: แสดงทุกช่วงจองพักอาหารต่อคน (ไม่จำกัดแค่ 1 ช่วง)
-- View dashboard_today_staff เพิ่มคอลัมน์ meal_slots (jsonb array ของ {start, end})
-- ต้อง DROP ก่อนแล้ว CREATE ใหม่ เพราะ Postgres ไม่อนุญาตให้เปลี่ยนชื่อ/ลำดับคอลัมน์ด้วย CREATE OR REPLACE
-- ==============================================================================

DROP VIEW IF EXISTS dashboard_today_staff CASCADE;

CREATE VIEW dashboard_today_staff AS
WITH today AS (
  SELECT ((now() AT TIME ZONE 'Asia/Bangkok')::date) AS d
),
holidays_today AS (
  SELECT DISTINCT ON (user_id)
    user_id,
    leave_type,
    reason,
    created_at
  FROM holidays, today
  WHERE holiday_date = today.d
    AND status IN ('approved', 'pending')
  ORDER BY user_id, created_at DESC
),
meal_all_today AS (
  SELECT
    user_id,
    jsonb_agg(
      jsonb_build_object('start', started_at, 'end', ended_at)
      ORDER BY started_at
    ) AS meal_slots
  FROM break_logs, today
  WHERE break_date = today.d
    AND break_type = 'MEAL'
    AND status = 'active'
  GROUP BY user_id
)
SELECT
  p.id                AS staff_id,
  p.display_name      AS name,
  p.email             AS staff_code,
  p.role              AS role,
  p.default_branch_id AS default_branch_id,
  p.default_shift_id  AS default_shift_id,
  s.name              AS shift_name,
  CASE WHEN h.user_id IS NOT NULL THEN 'LEAVE' ELSE 'PRESENT' END AS status,
  h.leave_type        AS leave_type,
  h.reason            AS leave_reason,
  m.meal_slots        AS meal_slots,
  (m.meal_slots->0->>'start')::timestamptz AS meal_start_time,
  (m.meal_slots->0->>'end')::timestamptz   AS meal_end_time
FROM profiles p
CROSS JOIN today
LEFT JOIN shifts s ON s.id = p.default_shift_id
LEFT JOIN holidays_today h ON h.user_id = p.id
LEFT JOIN meal_all_today m ON m.user_id = p.id
WHERE p.active = true
  AND p.role IN ('instructor', 'staff', 'instructor_head');

GRANT SELECT ON dashboard_today_staff TO authenticated;
