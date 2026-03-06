# การเพิ่มฟีเจอร์ใหม่แบบเรียงขั้นตอน

ระบบออกแบบให้เพิ่มฟีเจอร์ใหม่ได้เป็นขั้นตอน โดยไม่กระทบ flow เดิม ถ้าทำตามลำดับด้านล่าง

---

## กฎหลัก (จาก System Awareness)

- **เพิ่ม** table/column ใหม่ได้ — **ห้ามลบ/เปลี่ยนชื่อ** ของของเดิม
- ใช้ **migration แบบ backward-compatible** (มี default ไม่พังของเก่า)
- ก่อนแก้: วิเคราะห์ **ตาราง / API / หน้า / Role** ที่กระทบ

---

## ขั้นตอนเพิ่มฟีเจอร์ใหม่ (เรียงลำดับ)

### 1) ฐานข้อมูล (ถ้าฟีเจอร์ต้องเก็บข้อมูลใหม่)

- สร้างไฟล์ migration ใหม่ใน `supabase/sql/migrations/` (เลขรันต่อจากไฟล์ล่าสุด เช่น `40_ชื่อฟีเจอร์.sql`)
- ในไฟล์: สร้าง table ใหม่ หรือเพิ่ม column (พร้อม `DEFAULT` ถ้าจำเป็น)
- เปิด RLS: `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` และสร้าง policy ให้ตรงกับ role ที่จะใช้ (ดู policy ของ table คล้ายๆ ในโปรเจกต์เป็นตัวอย่าง)
- รัน migration ใน Supabase Dashboard → SQL Editor

### 2) Type / ตารางใน Frontend

- ถ้ามี table/entity ใหม่: เพิ่ม type ใน `frontend/src/lib/types.ts`
- ถ้าใช้ตารางเดิม: ใช้ type ที่มีอยู่ หรือขยายเฉพาะที่จำเป็น

### 3) หน้า UI

- สร้างหน้าใหม่ใน `frontend/src/pages/` (เช่น `FeatureName.tsx`)
- ใช้ `useAuth()`, `useBranchesShifts()` ถ้าต้องใช้ profile / branches / shifts
- เรียก `supabase.from('...')` ตาม RLS (login แล้วจะใช้ JWT อัตโนมัติ)
- ถ้ามีการกระทำสำคัญ (สร้าง/แก้/ลบ): เรียก `logAudit(...)` จาก `../lib/audit`
- ปุ่มแก้ไข/ลบในตารางใช้ `BtnEdit` / `BtnDelete` จาก `components/ui/ActionIcons.tsx` ตามกฎ UI

### 4) Route + สิทธิ์

- ใน `frontend/src/App.tsx`:
  - เพิ่ม `const FeatureName = lazy(() => import('./pages/FeatureName'));`
  - ใน `<Route path="/">...</Route>` เพิ่ม:
    - `<Route path="path-url" element={<ProtectedRoute allowedRoles={['admin', ...]}><FeatureName /></ProtectedRoute>} />`
  - กำหนด `allowedRoles` ตามว่า role ไหนเข้าได้ (ไม่ใส่ = ทุก role ที่ล็อกอินแล้ว)

### 5) เมนู (Sidebar)

- ใน `frontend/src/components/Nav.tsx`:
  - เพิ่มลิงก์ใน `NAV_SECTIONS` ใน section ที่เหมาะสม:
    - `{ to: '/path-url', label: 'ชื่อเมนู', icon: '...', roles: ['admin', ...] }`
  - `roles` ถ้าไม่ใส่ = แสดงทุก role ที่เห็น section นั้น

### 6) ฟังก์ชันที่รันที่ Edge (ถ้าจำเป็น)

- ถ้าฟีเจอร์ต้องมี API ที่รันที่ Cloudflare: สร้างไฟล์ใน `frontend/functions/api/...` (เช่น `api/feature/action.ts`)
- ตั้งค่า env ที่ต้องใช้ใน Cloudflare Pages → Settings → Environment variables

### 7) เอกสาร

- อัปเดต `docs/DOCS.md` หรือสร้างเอกสารสั้นๆ ใน `docs/` ถ้าฟีเจอร์มีกติกา/ขั้นตอนที่คนอื่นต้องรู้

---

## เช็คลิสต์สั้นๆ

- [ ] Migration สร้าง/เพิ่มแล้ว และรันใน Supabase แล้ว
- [ ] RLS เปิดและ policy ตรงกับ role ที่ใช้
- [ ] Type (ถ้ามี) เพิ่มใน `types.ts`
- [ ] หน้าใหม่มีสิทธิ์ตรงกับ ProtectedRoute (allowedRoles)
- [ ] Route ใน App.tsx และเมนูใน Nav.tsx เพิ่มแล้ว
- [ ] การกระทำสำคัญมี logAudit (ถ้าเป็นฟีเจอร์ที่ต้อง audit)
- [ ] ไม่ลบ/เปลี่ยนชื่อ table/column เดิม และไม่เปลี่ยน behavior ของ role เดิม

ถ้าทำตามลำดับนี้ ระบบจะรับฟีเจอร์ใหม่ได้เรียงๆ โดยไม่กระทบ workflow เดิม
