-- 23: ให้พนักงาน (staff) เห็นโปรไฟล์ของคนในแผนกเดียวกัน เพื่อให้ตารางวันหยุดแสดงวันลา/เปลี่ยนกะของคนอื่นในแผนกได้
-- ไม่เปลี่ยนสิทธิ์อื่น: แก้เฉพาะ profiles_select

DROP POLICY IF EXISTS profiles_select ON profiles;
CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated USING (
  is_admin()
  OR id = auth.uid()
  OR is_instructor_or_admin()
  OR (default_branch_id IS NOT NULL AND default_branch_id IN (SELECT user_branch_ids(auth.uid())))
);

COMMENT ON POLICY profiles_select ON profiles IS 'admin/instructor/self เหมือนเดิม; พนักงานเห็นโปรไฟล์คนในแผนกเดียวกัน (สำหรับตารางวันหยุด)';
