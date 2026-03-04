-- ==============================================================================
-- 07: group_links — ให้หัวหน้า (instructor_head) ทำได้เท่าผู้จัดการ (manager)
--     ปัญหา: หัวหน้าเพิ่มลิงก์ใหม่ไม่ได้ — RLS INSERT บังคับ branch_id = my_branch_id() หรือ null
--     ต้องการ: หัวหน้าและผู้จัดการทำได้เหมือนกัน (ยกเว้นจัดการ user สูงกว่าตัวเองในที่อื่น)
--     กระทบ: group_links (INSERT policy เท่านั้น)
-- ==============================================================================

DROP POLICY IF EXISTS group_links_insert ON group_links;
CREATE POLICY group_links_insert ON group_links FOR INSERT TO authenticated WITH CHECK (
  is_admin() OR is_manager() OR is_instructor_head()
);
