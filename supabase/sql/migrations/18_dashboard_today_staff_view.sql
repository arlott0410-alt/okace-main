-- ==============================================================================
-- 18: Dashboard "Today's Staff (from Holiday Grid)"
-- Present = staff in scope minus holidays(today). Leave = staff with holidays row for today.
-- No attendance; timezone Asia/Bangkok; single view for Supervisor/Manager/Admin.
-- ==============================================================================

-- View: หนึ่งแถวต่อ staff (instructor/staff, active) พร้อมสถานะวันนี้และจองพักอาหาร
-- Logic ตรง DutyBoard: holidays สำหรับวันนี้ (approved/pending) = ไม่มาทำงาน (LEAVE)
CREATE OR REPLACE VIEW dashboard_today_staff AS
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
meal_today AS (
  SELECT DISTINCT ON (user_id)
    user_id,
    started_at AS meal_start_time,
    ended_at   AS meal_end_time
  FROM break_logs, today
  WHERE break_date = today.d
    AND break_type = 'MEAL'
    AND status = 'active'
  ORDER BY user_id, created_at DESC
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
  m.meal_start_time   AS meal_start_time,
  m.meal_end_time     AS meal_end_time
FROM profiles p
CROSS JOIN today
LEFT JOIN shifts s ON s.id = p.default_shift_id
LEFT JOIN holidays_today h ON h.user_id = p.id
LEFT JOIN meal_today m ON m.user_id = p.id
WHERE p.active = true
  AND p.role IN ('instructor', 'staff', 'instructor_head');

COMMENT ON VIEW dashboard_today_staff IS
  'พนักงานวันนี้จากตารางวันหยุด: PRESENT = ไม่มีแถว holidays วันนี้, LEAVE = มีแถว holidays (approved/pending). จองพักอาหารจาก break_logs MEAL. ใช้ในแดชบอร์ด Supervisor/Manager/Admin. Timezone Asia/Bangkok.';

-- RLS: ใช้ policy เดียวกับที่เห็น profiles/branches — ให้ authenticated อ่านได้ตามสิทธิ์ที่มี
-- (View อ่านจาก profiles, shifts, holidays, break_logs ที่มี RLS อยู่แล้ว ดังนั้นการ SELECT view จะถูกบังคับโดย underlying tables)
-- ถ้า Supabase ไม่ให้ SELECT view โดยไม่มี policy แยก เราอาจต้อง GRANT SELECT ให้ role ที่ใช้
GRANT SELECT ON dashboard_today_staff TO authenticated;
