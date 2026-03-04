-- ==============================================================================
-- 20: Performance indexes + RPC for Manager Dashboard Today (single-call)
-- Purpose: Reduce query count and payload; support 100-200 staff.
-- No business logic change. Timezone: Asia/Bangkok.
-- ==============================================================================

-- ---------- Indexes (match actual WHERE/ORDER in codebase) ----------

-- holidays: date-first lookup (DutyBoard leaveIdsForDate; holiday grid by month)
CREATE INDEX IF NOT EXISTS idx_holidays_holiday_date_user_id ON holidays(holiday_date, user_id);

-- break_logs (meal bookings): date + user for "bookings today" and capacity
CREATE INDEX IF NOT EXISTS idx_break_logs_break_date_user_id ON break_logs(break_date, user_id);

-- profiles: branch and role filtering (MemberManagement, DutyBoard, scoping)
CREATE INDEX IF NOT EXISTS idx_profiles_default_branch_id ON profiles(default_branch_id);
CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role);

-- cross_branch_transfers: TransferHistory filters and list by created_at
CREATE INDEX IF NOT EXISTS idx_cross_branch_transfers_created_at ON cross_branch_transfers(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cross_branch_transfers_from_branch_created ON cross_branch_transfers(from_branch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cross_branch_transfers_to_branch_created ON cross_branch_transfers(to_branch_id, created_at DESC);

-- shift_swaps: list by created_at and by branch
CREATE INDEX IF NOT EXISTS idx_shift_swaps_created_at ON shift_swaps(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_shift_swaps_branch_created ON shift_swaps(branch_id, created_at DESC) WHERE branch_id IS NOT NULL;


-- ---------- Helper: effective branch/shift for a user on a date (for dashboard scope) ----------
CREATE OR REPLACE FUNCTION get_effective_branch_shift_for_date(
  p_user_id uuid,
  p_date date,
  p_fallback_branch uuid,
  p_fallback_shift uuid
)
RETURNS TABLE(branch_id uuid, shift_id uuid)
LANGUAGE sql
STABLE
AS $$
  WITH swaps AS (
    SELECT ss.branch_id, ss.to_shift_id AS shift_id, ss.start_date
    FROM shift_swaps ss
    WHERE ss.user_id = p_user_id AND ss.status = 'approved'
      AND ss.start_date <= p_date AND (ss.end_date IS NULL OR ss.end_date >= p_date)
    ORDER BY ss.start_date DESC
    LIMIT 1
  ),
  transfers AS (
    SELECT cbt.to_branch_id AS branch_id, cbt.to_shift_id AS shift_id, cbt.start_date
    FROM cross_branch_transfers cbt
    WHERE cbt.user_id = p_user_id AND cbt.status = 'approved'
      AND cbt.start_date <= p_date AND (cbt.end_date IS NULL OR cbt.end_date >= p_date)
    ORDER BY cbt.start_date DESC
    LIMIT 1
  ),
  combined AS (
    SELECT branch_id, shift_id, start_date FROM swaps
    UNION ALL
    SELECT branch_id, shift_id, start_date FROM transfers
  ),
  best AS (
    SELECT branch_id, shift_id
    FROM combined
    WHERE branch_id IS NOT NULL AND shift_id IS NOT NULL
    ORDER BY start_date DESC NULLS LAST
    LIMIT 1
  )
  SELECT COALESCE(b.branch_id, p_fallback_branch), COALESCE(b.shift_id, p_fallback_shift)
  FROM best b
  UNION ALL
  SELECT p_fallback_branch, p_fallback_shift
  WHERE NOT EXISTS (SELECT 1 FROM best);
$$;

COMMENT ON FUNCTION get_effective_branch_shift_for_date(uuid, date, uuid, uuid) IS
  'Effective branch_id and shift_id for a user on a date from approved shift_swaps/cross_branch_transfers; fallback from profile.';


-- ---------- RPC: Manager Dashboard Today — one call returns Name | Shift | Status | Leave type/reason | Meal time (optional scope) ----------
CREATE OR REPLACE FUNCTION rpc_manager_dashboard_today(
  p_today date DEFAULT ((now() AT TIME ZONE 'Asia/Bangkok')::date),
  p_scope_branch_id uuid DEFAULT NULL,
  p_scope_shift_id uuid DEFAULT NULL
)
RETURNS TABLE(
  staff_id uuid,
  name text,
  staff_code text,
  role text,
  shift_name text,
  status text,
  leave_type text,
  leave_reason text,
  meal_slots jsonb,
  meal_start_time timestamptz,
  meal_end_time timestamptz
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH today AS (SELECT p_today AS d),
  holidays_today AS (
    SELECT DISTINCT ON (user_id) user_id, leave_type, reason, created_at
    FROM holidays, today
    WHERE holiday_date = today.d AND status IN ('approved', 'pending')
    ORDER BY user_id, created_at DESC
  ),
  meal_all_today AS (
    SELECT user_id,
      jsonb_agg(jsonb_build_object('start', started_at, 'end', ended_at) ORDER BY started_at) AS meal_slots
    FROM break_logs, today
    WHERE break_date = today.d AND break_type = 'MEAL' AND status = 'active'
    GROUP BY user_id
  ),
  base AS (
    SELECT
      p.id AS staff_id,
      p.display_name AS name,
      p.email AS staff_code,
      p.role AS role,
      s_eff.name AS shift_name,
      CASE WHEN h.user_id IS NOT NULL THEN 'LEAVE' ELSE 'PRESENT' END AS status,
      h.leave_type AS leave_type,
      h.reason AS leave_reason,
      m.meal_slots AS meal_slots,
      (m.meal_slots->0->>'start')::timestamptz AS meal_start_time,
      (m.meal_slots->0->>'end')::timestamptz AS meal_end_time,
      eff.branch_id AS eff_branch_id,
      eff.shift_id AS eff_shift_id
    FROM profiles p
    CROSS JOIN today
    LEFT JOIN holidays_today h ON h.user_id = p.id
    LEFT JOIN meal_all_today m ON m.user_id = p.id
    CROSS JOIN LATERAL get_effective_branch_shift_for_date(p.id, p_today, p.default_branch_id, p.default_shift_id) AS eff(branch_id, shift_id)
    LEFT JOIN shifts s_eff ON s_eff.id = eff.shift_id
    WHERE p.active = true
      AND p.role IN ('instructor', 'staff', 'instructor_head')
  )
  SELECT b.staff_id, b.name, b.staff_code, b.role, b.shift_name, b.status, b.leave_type, b.leave_reason,
         b.meal_slots, b.meal_start_time, b.meal_end_time
  FROM base b
  WHERE (p_scope_branch_id IS NULL OR b.eff_branch_id = p_scope_branch_id)
    AND (p_scope_shift_id IS NULL OR b.eff_shift_id = p_scope_shift_id)
  ORDER BY b.status, b.name NULLS LAST;
$$;

COMMENT ON FUNCTION rpc_manager_dashboard_today(date, uuid, uuid) IS
  'Today overview for Supervisor/Manager/Admin: Name, Shift, Status (PRESENT/LEAVE), leave type/reason, meal slots. Optional scope by branch and/or shift. Asia/Bangkok.';
