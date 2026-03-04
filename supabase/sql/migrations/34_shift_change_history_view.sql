-- Migration 34: View สำหรับประวัติย้ายกะรวม (shift_swaps + cross_branch_transfers) — ใช้ pagination ใน TransferHistory
-- security_invoker = on เพื่อให้ RLS ของตารางต้นทางใช้กับผู้ query

CREATE OR REPLACE VIEW shift_change_history_view
WITH (security_invoker = true)
AS
SELECT
  'swap'::text AS type,
  id, user_id, start_date, end_date,
  status::text AS status,
  created_at,
  branch_id AS from_branch_id,
  branch_id AS to_branch_id,
  from_shift_id, to_shift_id
FROM shift_swaps
UNION ALL
SELECT
  'transfer'::text,
  id, user_id, start_date, end_date,
  status::text AS status,
  created_at,
  from_branch_id, to_branch_id,
  from_shift_id, to_shift_id
FROM cross_branch_transfers;

COMMENT ON VIEW shift_change_history_view IS 'ประวัติย้ายกะรวม (สลับกะ + ย้ายข้ามแผนก) สำหรับ pagination';

GRANT SELECT ON shift_change_history_view TO authenticated;
