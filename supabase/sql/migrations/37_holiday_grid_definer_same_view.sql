-- 37: ให้ตารางวันหยุดเห็นแบบเดียวกันทุกคนในแผนก + เห็นวันเปลี่ยนกะของคนอื่น
-- สาเหตุ: rpc_holiday_grid ใช้ SECURITY INVOKER → แต่ละคนได้ผลจาก RLS ไม่เท่ากัน → เห็นคนละแบบ
-- แก้: ใช้ SECURITY DEFINER + ตรวจสิทธิ์ branch ก่อนคืนข้อมูล (ไม่เปิดข้อมูลข้ามแผนก)
-- ผล: ทุกคนในแผนกเดียวกันได้ staff + holidays ชุดเดียวกันเมื่อไม่ติ๊ก "เฉพาะของฉัน"; สิทธิ์แก้ไขไม่เปลี่ยน (ฝั่ง UI/RLS ตาราง holidays ยังเหมือนเดิม)

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
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role text;
  v_caller_branch_id uuid;
  v_allowed boolean := false;
BEGIN
  SELECT p.role, p.default_branch_id INTO v_caller_role, v_caller_branch_id
  FROM profiles p WHERE p.id = auth.uid() LIMIT 1;

  -- อนุญาตเฉพาะเมื่อ: เรียกดูได้เฉพาะแผนกที่ตัวเองมีสิทธิ์ (หรือแอดมิน/ผู้จัดการ/หัวหน้าเห็นได้ทุกแผนก)
  IF v_caller_role IN ('admin', 'manager', 'instructor_head') THEN
    v_allowed := true;
  ELSIF p_branch_id IS NOT NULL AND (p_branch_id = v_caller_branch_id OR p_branch_id IN (SELECT user_branch_ids(auth.uid()))) THEN
    v_allowed := true;
  END IF;

  IF NOT v_allowed THEN
    RETURN QUERY SELECT '[]'::jsonb, '[]'::jsonb;
    RETURN;
  END IF;

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

COMMENT ON FUNCTION rpc_holiday_grid(date, date, uuid, uuid) IS 'ตารางวันหยุด: SECURITY DEFINER เพื่อให้ทุกคนในแผนกเห็น staff/holidays ชุดเดียวกัน; ตรวจสิทธิ์ branch ก่อนคืนข้อมูล';
