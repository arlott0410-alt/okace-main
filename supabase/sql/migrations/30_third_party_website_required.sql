-- Migration 30: บังคับ third_party_providers ให้ผูกเว็บ (website_id NOT NULL) + RLS ตาม website_assignments

-- 1) อัปเดตแถวที่ website_id เป็น NULL ให้ชี้ไปที่เว็บแรก (safe migration)
UPDATE third_party_providers
SET website_id = (SELECT id FROM websites ORDER BY name LIMIT 1)
WHERE website_id IS NULL
  AND EXISTS (SELECT 1 FROM websites LIMIT 1);

-- 2) ลบ FK เดิม แล้วตั้ง NOT NULL + FK ใหม่ ON DELETE CASCADE
-- (ถ้ายังมีแถวที่ website_id เป็น NULL หลังอัปเดตด้านบน — เช่นไม่มีเว็บในระบบ — จะไม่บังคับ NOT NULL)
ALTER TABLE third_party_providers DROP CONSTRAINT IF EXISTS third_party_providers_website_id_fkey;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM third_party_providers WHERE website_id IS NULL) THEN
    ALTER TABLE third_party_providers ALTER COLUMN website_id SET NOT NULL;
  END IF;
  -- TODO: ถ้ามีแถวที่ website_id ยังเป็น NULL ให้กำหนดค่าในระบบแล้วรัน ALTER ภายหลัง
END $$;
ALTER TABLE third_party_providers
  ADD CONSTRAINT third_party_providers_website_id_fkey
  FOREIGN KEY (website_id) REFERENCES websites(id) ON DELETE CASCADE;

-- 3) ปรับ RLS policies ให้บังคับตามเว็บ (มองเห็น/จัดการได้เฉพาะเว็บที่ user ถูก assign)
DROP POLICY IF EXISTS third_party_providers_select ON third_party_providers;
DROP POLICY IF EXISTS third_party_providers_insert ON third_party_providers;
DROP POLICY IF EXISTS third_party_providers_update ON third_party_providers;
DROP POLICY IF EXISTS third_party_providers_delete ON third_party_providers;

-- SELECT: หัวหน้าขึ้นไปเห็นทั้งหมด; คนอื่นเห็นเฉพาะเว็บที่ assign + ผ่าน visible_roles
CREATE POLICY third_party_providers_select ON third_party_providers
FOR SELECT TO authenticated
USING (
  (is_admin() OR is_manager() OR is_instructor_head())
  OR (
    website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid())
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR my_role() = ANY(visible_roles))
  )
);

-- INSERT: เฉพาะหัวหน้าขึ้นไป และ website_id ต้องอยู่ในเว็บที่ user จัดการได้ (admin ได้ทุกเว็บ)
CREATE POLICY third_party_providers_insert ON third_party_providers
FOR INSERT TO authenticated
WITH CHECK (
  (is_admin() OR is_manager() OR is_instructor_head())
  AND (
    is_admin()
    OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid())
  )
);

-- UPDATE: เหมือน INSERT
CREATE POLICY third_party_providers_update ON third_party_providers
FOR UPDATE TO authenticated
USING (
  (is_admin() OR is_manager() OR is_instructor_head())
  AND (
    is_admin()
    OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid())
  )
)
WITH CHECK (
  (is_admin() OR is_manager() OR is_instructor_head())
  AND (
    is_admin()
    OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid())
  )
);

-- DELETE: เหมือน INSERT
CREATE POLICY third_party_providers_delete ON third_party_providers
FOR DELETE TO authenticated
USING (
  (is_admin() OR is_manager() OR is_instructor_head())
  AND (
    is_admin()
    OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid())
  )
);
