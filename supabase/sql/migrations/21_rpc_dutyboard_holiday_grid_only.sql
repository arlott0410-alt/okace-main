-- ==============================================================================
-- 21: RPC consolidation — ONLY 3 RPCs used by frontend: Dashboard Today, DutyBoard, HolidayGrid
-- Adds rpc_dutyboard and rpc_holiday_grid. Timezone Asia/Bangkok where relevant.
-- ==============================================================================

-- ---------- rpc_dutyboard: one call for DutyBoard daily view ----------
CREATE OR REPLACE FUNCTION rpc_dutyboard(
  p_date date,
  p_branch_id uuid,
  p_shift_id uuid
)
RETURNS TABLE(
  duty_roles jsonb,
  assignments jsonb,
  staff jsonb,
  leave_user_ids jsonb,
  roster_status jsonb,
  websites jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
AS $$
DECLARE
  v_month date;
BEGIN
  v_month := date_trunc('month', p_date)::date;

  RETURN QUERY
  WITH
  dr AS (
    SELECT COALESCE(jsonb_agg(to_jsonb(dr.*) ORDER BY dr.sort_order), '[]'::jsonb) AS j
    FROM duty_roles dr
    WHERE dr.branch_id = p_branch_id
  ),
  asn AS (
    SELECT COALESCE(jsonb_agg(to_jsonb(a.*)), '[]'::jsonb) AS j
    FROM duty_assignments a
    WHERE a.branch_id = p_branch_id AND a.shift_id = p_shift_id AND a.assignment_date = p_date
  ),
  leave_ids AS (
    SELECT COALESCE(jsonb_agg(uid), '[]'::jsonb) AS j
    FROM (SELECT DISTINCT h.user_id AS uid FROM holidays h WHERE h.holiday_date = p_date AND h.status IN ('approved', 'pending')) t
  ),
  roster AS (
    SELECT to_jsonb(mrs.*) AS j
    FROM monthly_roster_status mrs
    WHERE mrs.branch_id = p_branch_id AND mrs.month = v_month
    LIMIT 1
  ),
  ws AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id', w.id, 'name', w.name) ORDER BY w.name), '[]'::jsonb) AS j
    FROM websites w
    WHERE w.is_active = true AND (w.branch_id = p_branch_id OR w.branch_id IS NULL)
  ),
  staff_with_eff AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'display_name', p.display_name,
        'email', p.email,
        'role', p.role,
        'default_branch_id', p.default_branch_id,
        'default_shift_id', p.default_shift_id,
        'active', p.active,
        'effective_branch_id', eff.branch_id,
        'effective_shift_id', eff.shift_id
      )
      ORDER BY p.display_name NULLS LAST
    ) AS j
    FROM profiles p
    CROSS JOIN LATERAL get_effective_branch_shift_for_date(p.id, p_date, p.default_branch_id, p.default_shift_id) AS eff(branch_id, shift_id)
    WHERE p.active = true AND p.role IN ('instructor', 'staff')
  )
  SELECT
    (SELECT j FROM dr),
    (SELECT j FROM asn),
    (SELECT j FROM staff_with_eff),
    (SELECT j FROM leave_ids),
    (SELECT j FROM roster),
    (SELECT j FROM ws);
END;
$$;

-- ---------- rpc_holiday_grid: one call for HolidayGrid monthly view ----------
CREATE OR REPLACE FUNCTION rpc_holiday_grid(
  p_month_start date,
  p_month_end date,
  p_branch_id uuid DEFAULT NULL,
  p_only_my_user_id uuid DEFAULT NULL
)
RETURNS TABLE(
  staff jsonb,
  holidays jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
AS $$
BEGIN
  RETURN QUERY
  WITH
  staff_list AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'email', p.email,
        'display_name', COALESCE(p.display_name, p.email, ''),
        'role', p.role,
        'default_branch_id', p.default_branch_id,
        'default_shift_id', p.default_shift_id,
        'primary_website_id', wa.website_id
      )
      ORDER BY p.display_name NULLS LAST
    ) AS j
    FROM profiles p
    LEFT JOIN LATERAL (
      SELECT website_id FROM website_assignments WHERE user_id = p.id AND is_primary = true LIMIT 1
    ) wa ON true
    WHERE p.active = true AND p.role <> 'admin'
      AND (p_branch_id IS NULL OR p.default_branch_id = p_branch_id)
      AND (p_only_my_user_id IS NULL OR p.id = p_only_my_user_id)
  ),
  hol AS (
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', h.id, 'user_id', h.user_id, 'holiday_date', h.holiday_date,
          'status', h.status, 'leave_type', h.leave_type, 'reason', h.reason,
          'user_group', h.user_group, 'branch_id', h.branch_id, 'shift_id', h.shift_id,
          'approved_by', h.approved_by, 'approved_at', h.approved_at, 'reject_reason', h.reject_reason,
          'created_at', h.created_at, 'updated_at', h.updated_at, 'is_quota_exempt', h.is_quota_exempt
        )
      ),
      '[]'::jsonb
    ) AS j
    FROM (
      SELECT DISTINCT ON (h.user_id, h.holiday_date)
        h.id, h.user_id, h.holiday_date, h.status, h.leave_type, h.reason, h.user_group, h.branch_id, h.shift_id,
        h.approved_by, h.approved_at, h.reject_reason, h.created_at, h.updated_at, h.is_quota_exempt
      FROM holidays h
      WHERE h.holiday_date >= p_month_start AND h.holiday_date <= p_month_end
        AND (p_branch_id IS NULL OR h.branch_id = p_branch_id)
        AND (p_only_my_user_id IS NULL OR h.user_id = p_only_my_user_id)
      ORDER BY h.user_id, h.holiday_date, h.created_at DESC
    ) h
  )
  SELECT (SELECT j FROM staff_list), (SELECT j FROM hol);
END;
$$;

-- ---------- Indexes (STEP 5): ensure fast lookups for RPCs and direct queries ----------
-- holidays: reverse lookup by user (HolidayGrid "only my data", leave_ids in rpc_dutyboard)
CREATE INDEX IF NOT EXISTS idx_holidays_user_id_holiday_date ON holidays(user_id, holiday_date);
