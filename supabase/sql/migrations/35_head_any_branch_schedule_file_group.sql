-- ---------- 35_head_any_branch_schedule_file_group.sql ----------
-- ให้หัวหน้าขึ้นไป (instructor_head) สร้าง/แก้ไข/ลบ ได้ทุกแผนก ในตารางงาน คลังเก็บไฟล์ ศูนย์รวมกลุ่มงาน
-- กระทบ: schedule_cards, file_vault (RLS เท่านั้น); group_links/group_link_branches ตรวจแล้วหัวหน้าทำได้แล้วจาก 04/07

-- 1) schedule_cards: หัวหน้าสร้าง/แก้/ลบ ได้ทุกแผนก (เทียบเท่า admin/manager)
DROP POLICY IF EXISTS schedule_cards_insert ON schedule_cards;
CREATE POLICY schedule_cards_insert ON schedule_cards FOR INSERT TO authenticated WITH CHECK (
  is_admin_or_manager() OR is_instructor_head()
);

DROP POLICY IF EXISTS schedule_cards_update ON schedule_cards;
CREATE POLICY schedule_cards_update ON schedule_cards FOR UPDATE TO authenticated USING (
  is_admin_or_manager() OR is_instructor_head()
);

DROP POLICY IF EXISTS schedule_cards_delete ON schedule_cards;
CREATE POLICY schedule_cards_delete ON schedule_cards FOR DELETE TO authenticated USING (
  is_admin_or_manager() OR is_instructor_head()
);

-- 2) file_vault: หัวหน้าสร้าง/แก้/ลบ ได้ทุกแผนก (branch_id ใดก็ได้)
DROP POLICY IF EXISTS file_vault_insert ON file_vault;
CREATE POLICY file_vault_insert ON file_vault FOR INSERT TO authenticated WITH CHECK (
  is_admin_or_manager_or_head()
);

DROP POLICY IF EXISTS file_vault_update ON file_vault;
CREATE POLICY file_vault_update ON file_vault FOR UPDATE TO authenticated USING (
  is_admin_or_manager_or_head()
);

DROP POLICY IF EXISTS file_vault_delete ON file_vault;
CREATE POLICY file_vault_delete ON file_vault FOR DELETE TO authenticated USING (
  is_admin_or_manager_or_head()
);
