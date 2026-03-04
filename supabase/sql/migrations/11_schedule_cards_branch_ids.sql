-- ---------- 11_schedule_cards_branch_ids.sql ----------
-- ตารางงาน: หนึ่งการ์ดหนึ่งแถว เก็บหลายแผนกใน branch_ids (ไม่สร้างหลายแถวต่อหลายแผนก)

ALTER TABLE schedule_cards ADD COLUMN IF NOT EXISTS branch_ids UUID[] DEFAULT NULL;
COMMENT ON COLUMN schedule_cards.branch_ids IS 'แผนกที่เห็นการ์ดได้ (หลายรายการ); null หรือ {} = ใช้ branch_id เดิม';

-- backfill จาก branch_id เดิม
UPDATE schedule_cards
SET branch_ids = ARRAY[branch_id]
WHERE branch_id IS NOT NULL
  AND (branch_ids IS NULL OR branch_ids = '{}');

-- RLS: ให้เห็นการ์ดเมื่อ branch ของ user อยู่ใน branch_id หรือ branch_ids
DROP POLICY IF EXISTS schedule_cards_select ON schedule_cards;
CREATE POLICY schedule_cards_select ON schedule_cards FOR SELECT TO authenticated USING (
  is_admin_or_manager_or_head()
  OR (
    (
      (branch_id IS NULL AND (branch_ids IS NULL OR branch_ids = '{}'))
      OR branch_id IN (SELECT user_branch_ids(auth.uid()))
      OR (branch_ids IS NOT NULL AND branch_ids <> '{}' AND branch_ids && (SELECT array_agg(ub) FROM user_branch_ids(auth.uid()) AS ub))
    )
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR (SELECT role::text FROM profiles WHERE id = auth.uid()) = ANY(visible_roles))
    AND (website_id IS NULL OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid()))
  )
);

DROP POLICY IF EXISTS schedule_cards_insert ON schedule_cards;
CREATE POLICY schedule_cards_insert ON schedule_cards FOR INSERT TO authenticated WITH CHECK (
  is_admin_or_manager()
  OR (is_instructor_head() AND (
    (branch_ids IS NOT NULL AND branch_ids <> '{}' AND my_branch_id() = ANY(branch_ids))
    OR ((branch_ids IS NULL OR branch_ids = '{}') AND branch_id = my_branch_id())
  ))
);

DROP POLICY IF EXISTS schedule_cards_update ON schedule_cards;
CREATE POLICY schedule_cards_update ON schedule_cards FOR UPDATE TO authenticated USING (
  is_admin_or_manager()
  OR (is_instructor_head() AND (
    (branch_ids IS NOT NULL AND branch_ids <> '{}' AND my_branch_id() = ANY(branch_ids))
    OR ((branch_ids IS NULL OR branch_ids = '{}') AND branch_id = my_branch_id())
  ))
);

DROP POLICY IF EXISTS schedule_cards_delete ON schedule_cards;
CREATE POLICY schedule_cards_delete ON schedule_cards FOR DELETE TO authenticated USING (
  is_admin_or_manager()
  OR (is_instructor_head() AND (
    (branch_ids IS NOT NULL AND branch_ids <> '{}' AND my_branch_id() = ANY(branch_ids))
    OR ((branch_ids IS NULL OR branch_ids = '{}') AND branch_id = my_branch_id())
  ))
);
