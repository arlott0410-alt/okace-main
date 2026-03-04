-- ==============================================================================
-- Verification: rpc_manager_dashboard_today
-- Run in Supabase SQL Editor. Assumes migration 20 applied.
-- ==============================================================================

-- 1) Function exists and returns table type
SELECT p.proname, pg_get_function_result(p.oid) AS result_type
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'rpc_manager_dashboard_today';

-- 2) Today (Asia/Bangkok) matches expectation
SELECT (now() AT TIME ZONE 'Asia/Bangkok')::date AS today_bangkok;

-- 3) Call RPC with no scope (all staff) — should return rows
SELECT staff_id, name, shift_name, status, leave_type, meal_slots
FROM rpc_manager_dashboard_today(
  (now() AT TIME ZONE 'Asia/Bangkok')::date,
  NULL,
  NULL
)
LIMIT 5;

-- 4) Call with scope (use a real branch_id/shift_id from your DB if needed)
-- SELECT * FROM rpc_manager_dashboard_today(NULL, 'your-branch-uuid', 'your-shift-uuid') LIMIT 5;
