-- Migration 29: Third Party Providers (บุคคลที่สาม)
-- Table + RLS + indexes + updated_at trigger

CREATE TABLE IF NOT EXISTS third_party_providers (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  provider_name text NOT NULL,
  provider_code text,
  logo_url text,
  merchant_id text,
  login_acc text,
  login_pass text,
  fund_pass text,
  pay_pass text,
  link_url text,
  fee_b numeric DEFAULT 0,
  fee_t numeric DEFAULT 0,
  fee_p numeric DEFAULT 0,
  fee_i numeric DEFAULT 0,
  withdraw_enabled boolean DEFAULT true,
  branch_id uuid REFERENCES branches(id) ON DELETE CASCADE,
  website_id uuid REFERENCES websites(id) ON DELETE SET NULL,
  visible_roles text[],
  sort_order int DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_third_party_created ON third_party_providers (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_third_party_sort ON third_party_providers (sort_order);
CREATE INDEX IF NOT EXISTS idx_third_party_branch ON third_party_providers (branch_id);
CREATE INDEX IF NOT EXISTS idx_third_party_website ON third_party_providers (website_id);

CREATE TRIGGER third_party_providers_updated_at
  BEFORE UPDATE ON third_party_providers
  FOR EACH ROW EXECUTE PROCEDURE set_updated_at();

ALTER TABLE third_party_providers ENABLE ROW LEVEL SECURITY;

-- SELECT: admin/manager/head เห็นทั้งหมด; คนอื่นเห็นเมื่อ branch/website/visible_roles ผ่าน
CREATE POLICY third_party_providers_select ON third_party_providers
FOR SELECT TO authenticated
USING (
  (is_admin() OR is_manager() OR is_instructor_head())
  OR (
    (branch_id IS NULL OR branch_id IN (SELECT user_branch_ids(auth.uid())))
    AND (website_id IS NULL OR website_id IN (SELECT website_id FROM website_assignments WHERE user_id = auth.uid()))
    AND (visible_roles IS NULL OR array_length(visible_roles, 1) IS NULL OR my_role() = ANY(visible_roles))
  )
);

-- INSERT: เฉพาะหัวหน้าขึ้นไป; ถ้ามี branch_id ต้องเป็น my_branch_id() สำหรับ manager/head
CREATE POLICY third_party_providers_insert ON third_party_providers
FOR INSERT TO authenticated
WITH CHECK (
  is_admin()
  OR ((is_manager() OR is_instructor_head()) AND (branch_id IS NULL OR branch_id = my_branch_id()))
);

-- UPDATE: เหมือน INSERT
CREATE POLICY third_party_providers_update ON third_party_providers
FOR UPDATE TO authenticated
USING (
  is_admin()
  OR ((is_manager() OR is_instructor_head()) AND (branch_id IS NULL OR branch_id = my_branch_id()))
)
WITH CHECK (
  is_admin()
  OR ((is_manager() OR is_instructor_head()) AND (branch_id IS NULL OR branch_id = my_branch_id()))
);

-- DELETE: เหมือน INSERT
CREATE POLICY third_party_providers_delete ON third_party_providers
FOR DELETE TO authenticated
USING (
  is_admin()
  OR ((is_manager() OR is_instructor_head()) AND (branch_id IS NULL OR branch_id = my_branch_id()))
);
