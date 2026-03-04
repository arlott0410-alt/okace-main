# OKACE — เอกสารรวม (Consolidated Docs)

เอกสารรวบรวมจาก README + docs ทั้งหมดในโปรเจกต์

---

## สารบัญ

1. [README — ภาพรวมระบบ](#1-readme--ภาพรวมระบบ)
2. [SETUP — คู่มือตั้งค่า](#2-setup--คู่มือตั้งค่า)
3. [BUILD — การ Build บน Cloudflare](#3-build--การ-build-บน-cloudflare)
4. [BRANCH_SCOPE — การแบ่งการมองเห็นตามแผนก](#4-branch_scope--การแบ่งการมองเห็นตามแผนก)
5. [MANAGED_WEBSITES — เว็บที่ดูแล](#5-managed_websites--เว็บที่ดูแล)
6. [ROLE_ADMIN_NOT_STAFF — Admin ไม่ใช่พนักงาน](#6-role_admin_not_staff--admin-ไม่ใช่พนักงาน)

---

## 1. README — ภาพรวมระบบ

# OKACE — ระบบลงเวลาและจัดการกะ

ระบบลงเวลา + ตารางวันหยุด/กะ + จัดหน้าที่ + คลังรูป + คลังรหัสผ่าน + ลิงก์กลุ่ม + ประวัติการทำรายการ  
ธีม Premium ดำ-ทอง (#0B0F1A / #D4AF37) ภาษาไทยทั้งระบบ

### ข้อกำหนดสำคัญ

- **ไม่ใช้ Node.js / Wrangler ในเครื่อง** — Deploy ผ่าน GitHub → Cloudflare Pages เท่านั้น
- **ฐานข้อมูล**: Supabase (Postgres + Auth + Realtime + Storage)
- **Environment Variables** ตั้งค่าทั้งหมดผ่าน Dashboard (Supabase + Cloudflare Pages)

### โครงสร้างโปรเจกต์

```
okace/
├── frontend/          # React + Vite + TypeScript + Tailwind
│   ├── src/
│   │   ├── lib/       # supabase, auth, types, breaks, roster, transfers, audit
│   │   └── pages/
│   ├── functions/     # Cloudflare Pages Functions (encrypt/decrypt vault)
│   └── ...
├── supabase/
│   └── sql/
│       ├── schema.sql   # ตาราง, RLS, seed หลัก
│       └── migrations/  # SQL 01 → … → 34 หรือ full_install.sql (ดู migrations/README.md)
└── docs/
    └── ...
```

### การ Deploy (ทำใน Dashboard)

1. **Supabase**  
   - สร้าง Project → รัน SQL จาก `supabase/sql/schema.sql` ใน SQL Editor  
   - สร้าง Storage bucket ชื่อ `vault` และตั้งค่า Policy  
   - เปิด Realtime สำหรับตารางที่ต้องการ (holidays, shift_swaps, cross_branch_transfers, duty_assignments, monthly_roster_status, monthly_roster, **break_logs**)  
   - ตั้ง Auth → URL Redirect: ใส่ URL ของแอป (เช่น `https://xxx.pages.dev`)

2. **Cloudflare Pages**  
   - สร้าง Pages Project จาก GitHub repo นี้  
   - Root directory: `frontend`  
   - Build command: `npm install && npm run build` (หรือ `npm ci && npm run build` ถ้ามี package-lock ใน repo)  
   - Build output directory: `dist`  
   - ตั้ง Environment Variables ตามส่วน SETUP ด้านล่างในเอกสารนี้

3. **หลัง Deploy**  
   - สร้างผู้ใช้ใน Supabase Auth (สมัครหรือ Invite)  
   - เพิ่มแถวในตาราง `profiles` (id = auth.users.id, role = 'admin' / 'manager' / 'instructor_head' / 'instructor' / 'staff')

### Build (สำหรับ CI ของ Cloudflare)

- ในเครื่องไม่จำเป็นต้องรัน `npm install` / `npm run build`  
- Cloudflare Pages จะรันอัตโนมัติ:  
  - **Build command:** `npm ci && npm run build`  
  - **Output directory:** `dist`

### สิทธิ์ (Roles)

| Role | สิทธิ์หลัก |
|------|------------|
| ผู้ดูแลระบบ (admin) | จัดการสาขา/กะ/พนักงาน/ตั้งค่า/อนุมัติ/คลังรูป/คลังรหัสผ่าน/กลุ่มงาน/ประวัติ |
| ผู้จัดการ (manager) | เห็นทุกแผนก; จัดการอนุมัติ/ตาราง/กลุ่มงาน/คลังรหัสผ่าน (แก้ไข user ได้) |
| หัวหน้าพนักงานประจำ (instructor_head) | เห็นทุกแผนกเหมือนผู้จัดการ; แก้ไข user ได้เฉพาะ instructor/staff ในแผนกตัวเอง |
| พนักงานประจำ (instructor) | ดูตารางกะ-วันหยุด, สร้าง-มอบหมายงาน, ลงเวลา, พัก |
| พนักงานออนไลน์ (staff) | ลงเวลา, พัก, ขอวันหยุด/สลับกะ/ย้ายกะ, ดูจัดหน้าที่/งานที่ได้รับมอบหมาย |

### ฟีเจอร์เพิ่ม (Backward Compatible)

- **กติกาพัก (Break Concurrency)** — ตั้งค่าต่อสาขา/กะ ใน ตั้งค่า > กติกาพัก; หน้า พัก มีปุ่มเริ่มพัก/เลิกพัก + Admin เห็นคนกำลังพักและประวัติ
- **ยืนยันตารางกะรายเดือน** — หน้า ตารางกะรายเดือน: Admin ยืนยัน/ปลดล็อก; หลังยืนยัน จัดหน้าที่ เป็น read-only
- **ย้ายกะข้ามสาขา + ประวัติ** — หน้า ย้ายกะข้ามสาขา (filter เดือน/สาขา/สถานะ, admin_note); หน้า ประวัติย้ายกะ แยกสำหรับดูประวัติ

### กลุ่มงาน — การมองเห็นและสิทธิ์

- **Admin / ผู้จัดการ:** เห็นและจัดการทุกลิงก์
- **หัวหน้าพนักงานประจำ (instructor_head):** เห็นทุกลิงก์ทุกแผนกเหมือนผู้จัดการ และแก้ไข/ลบได้ (รวมลิงก์ที่ตัวเองสร้าง)
- **พนักงานประจำ/พนักงานออนไลน์:** เห็นเฉพาะลิงก์ที่สาขาตรงกัน และ role ตัวเองอยู่ใน "แสดงให้ตำแหน่ง" (หรือไม่เลือก = ทุกตำแหน่ง)
- ฟอร์มสร้าง/แก้กลุ่มงาน: เลือก **เว็บ** + **แผนก** (แสดงเป็นการ์ด, กรองตามเว็บ/แผนกได้)

### Migration (รันหลัง schema หลัก)

รันใน Supabase SQL Editor **ตามลำดับ**: **schema.sql** แล้ว **01 → 02 → … → 34** หรือรันไฟล์เดียว **migrations/full_install.sql**  
รายการและคำอธิบาย: **[supabase/sql/migrations/README.md](../supabase/sql/migrations/README.md)**

### ตารางวันหยุด — กติกาโควต้าและสิทธิ์

- **เปิดจอง:** แอดมินตั้งค่าใน ตั้งค่า → ตั้งค่าการจองวันหยุด (เดือนเป้าหมาย + ช่วงวันที่เปิดจอง) — ต้องมี config และอยู่ในช่วงถึงจะจองได้ (แอดมิน/หัวหน้าแก้ไขได้แม้ยังไม่เปิด)
- **โควต้าแบบชั้น:** แอดมินตั้งค่าใน ตั้งค่า → กติกาโควต้าวันหยุด: เลือกมิติ (สาขา/กะ/เว็บ) และกลุ่ม (หัวหน้า·ผู้สอน / พนักงานออนไลน์) แล้วเพิ่มเงื่อนไข เช่น 「จำนวนคน ≤ 4 → หยุดได้สูงสุด 1 คน」 — ต้องไม่เกินทั้ง 3 มิติถึงจะจองได้ ใครลงก่อนได้ก่อน วันไหนเต็มแสดง "เต็ม"
- **เว็บ:** ยึดเว็บหลักของแต่ละคน (primary website)
- **หัวหน้า:** เห็นตารางวันหยุดทุกสาขา แก้ไขได้เฉพาะสาขาตัวเอง
- **ประวัติ:** ทุกการจอง/เพิ่ม/ลบวันหยุดมี log ใน audit_logs (ดูได้จาก ประวัติ)

---

## 2. SETUP — คู่มือตั้งค่า

# คู่มือ Setup — OKACE (ทำใน Dashboard ทีละขั้นตอน)

คู่มือนี้ไม่บังคับให้รันคำสั่งในเครื่อง (ยกเว้น git clone / commit / push)  
ทำทั้งหมดผ่าน **Supabase Dashboard** และ **Cloudflare Pages Dashboard**

### ส่วนที่ 1: Supabase

#### 1.1 สร้าง Supabase Project

1. ไปที่ [supabase.com](https://supabase.com) → เข้าสู่ระบบ
2. กด **New Project**
3. ตั้งชื่อโปรเจกต์ เลือก Region ใส่รหัสผ่าน Database
4. รอสร้างเสร็จ แล้วเปิด **Project Settings** → **API** จดค่า:
   - **Project URL** (เช่น `https://xxxx.supabase.co`)
   - **anon public** (ใช้ฝั่ง Frontend)
   - **service_role** (ใช้เฉพาะใน Cloudflare Functions และไม่เปิดเผยฝั่ง Client)

#### 1.2 รัน SQL Schema

1. ใน Supabase Dashboard ไปที่ **SQL Editor**
2. กด **New query**
3. คัดลอกเนื้อหาทั้งหมดจากไฟล์ **`supabase/sql/schema.sql`** ใน repo นี้
4. วางใน Editor แล้วกด **Run**
5. ตรวจสอบว่าไม่มี error (ถ้ามี error เรื่อง Realtime publication ให้ข้ามหรือลบบรรทัด `ALTER PUBLICATION supabase_realtime ADD TABLE ...` ชั่วคราว แล้วไปเปิด Realtime จาก Table Editor ภายหลัง)

5.1 (ตัวเลือก) รัน Migration เพิ่มเติม ใน SQL Editor **ตามลำดับ 01 → 02 → … → 34** หรือรัน **migrations/full_install.sql** ครั้งเดียว (ดู `supabase/sql/migrations/README.md`)

#### 1.3 สร้าง Storage Bucket สำหรับคลังรูป

1. ไปที่ **Storage**
2. กด **New bucket**
3. ชื่อ bucket: **`vault`**
4. เปิด **Public bucket** ตามความต้องการ (ถ้าให้ดูรูปได้ผ่าน URL)
5. สร้าง Policy:
   - สำหรับ **อัปโหลด**: ให้ authenticated อัปโหลดได้ใน path `branch-<branch_id>/`
   - สำหรับ **อ่าน**: ให้ authenticated อ่านได้ (หรือ public ตามที่ตั้ง)

ตัวอย่าง Policy (ปรับตาม RLS ที่ต้องการ):

- **Allow upload**:  
  - Policy name: `Upload for authenticated`  
  - Allowed operation: INSERT  
  - Target roles: authenticated  
  - USING expression: `true`  
  - WITH CHECK expression: `bucket_id = 'vault'`

- **Allow read**:  
  - Policy name: `Read for authenticated`  
  - Allowed operation: SELECT  
  - Target roles: authenticated  
  - USING: `bucket_id = 'vault'`

#### 1.4 เปิด Realtime

**หมายเหตุ:** หน้า **Replication** (Platform → Replication) ใช้สำหรับ read replicas / data pipelines **ไม่ใช่** ที่เปิด Realtime สำหรับตาราง

การเปิด Realtime ให้แอป subscribe เปลี่ยนข้อมูลตารางแบบ realtime ทำได้ดังนี้:

**วิธีที่ 1: ใช้ SQL Editor (แนะนำ)**

1. ไปที่ **SQL Editor** ใน Supabase
2. สร้าง query ใหม่ แล้วรันสคริปต์นี้ (เพิ่มตารางเข้า publication `supabase_realtime`):

```sql
-- เปิด Realtime สำหรับตารางที่ใช้ในแอป
ALTER PUBLICATION supabase_realtime ADD TABLE holidays;
ALTER PUBLICATION supabase_realtime ADD TABLE shift_swaps;
ALTER PUBLICATION supabase_realtime ADD TABLE cross_branch_transfers;
ALTER PUBLICATION supabase_realtime ADD TABLE duty_assignments;
ALTER PUBLICATION supabase_realtime ADD TABLE monthly_roster_status;
ALTER PUBLICATION supabase_realtime ADD TABLE monthly_roster;
ALTER PUBLICATION supabase_realtime ADD TABLE break_logs;
```

ถ้าตารางใดถูกเพิ่มไปแล้วจะ error "already member" — ข้ามบรรทัดนั้นหรือรันทีละบรรทัดได้  
หรือใช้ไฟล์ `supabase/sql/migrations/003_enable_realtime_tables.sql` (รันใน SQL Editor) จะข้ามตารางที่เพิ่มแล้วอัตโนมัติ

**วิธีที่ 2: ใช้ Dashboard**

1. ไปที่ **Database** → **Publications**
2. เลือก publication ชื่อ **supabase_realtime**
3. กดจัดการ/แก้ไข แล้วเพิ่มตารางต่อไปนี้:
   - `holidays`
   - `shift_swaps`
   - `cross_branch_transfers`
   - `duty_assignments`
   - `monthly_roster_status`
   - `monthly_roster`
   - `break_logs` (สำหรับ Admin ดูคนกำลังพักแบบ Realtime)

#### 1.5 ตั้งค่า Auth Redirect URLs

1. ไปที่ **Authentication** → **URL Configuration**
2. ใน **Redirect URLs** เพิ่ม:
   - `https://<your-pages-domain>.pages.dev/**`
   - `https://<your-custom-domain>/**` (ถ้ามี)
   - สำหรับ local: `http://localhost:5173/**` (ถ้าจะรัน local ชั่วคราว)

#### 1.6 สร้างผู้ใช้และ Profile แรก (Admin)

1. ไปที่ **Authentication** → **Users**
2. กด **Add user** → **Create new user** ใส่ Email และ Password
3. จด **User UID** (UUID)
4. ไปที่ **SQL Editor** รันคำสั่ง (แทนที่ `USER_UID`, `EMAIL`, `BRANCH_ID`, `SHIFT_ID` ด้วยค่าจริง):

```sql
-- หา branch_id และ shift_id ก่อน (จากตาราง branches และ shifts)
INSERT INTO profiles (id, email, display_name, role, default_branch_id, default_shift_id)
VALUES (
  'USER_UID',
  'EMAIL',
  'ชื่อผู้ดูแล',
  'admin',
  (SELECT id FROM branches LIMIT 1),
  (SELECT id FROM shifts LIMIT 1)
);
```

จากนั้นใช้บัญชีนี้ล็อกอินเข้าแอปได้  
**หมายเหตุ:** ถ้ารัน migration `004_login_by_username.sql` แล้ว ผู้ใช้สามารถล็อกอินด้วย **ชื่อผู้ใช้** (ค่า `display_name` ใน profiles) หรืออีเมล พร้อมรหัสผ่านได้

### ส่วนที่ 2: Cloudflare Pages

#### 2.1 สร้าง Pages Project จาก GitHub

1. ไปที่ [dash.cloudflare.com](https://dash.cloudflare.com) → **Workers & Pages** → **Create** → **Pages** → **Connect to Git**
2. เลือก GitHub แล้วเลือก repo ของโปรเจกต์นี้
3. ตั้งค่า Build:
   - **Project name**: ตั้งชื่อ (เช่น `okace`)
   - **Production branch**: `main` (หรือ branch หลัก)
   - **Root directory (advanced)**: ตั้งเป็น **`frontend`**
   - **Build command**: `npm ci && npm run build`
   - **Build output directory**: **`dist`**
4. กด **Save and Deploy**

#### 2.2 ตั้งค่า Environment Variables

ไปที่ **Settings** → **Environment variables** ของโปรเจกต์ Pages แล้วเพิ่ม:

**สำหรับ Frontend (ใช้ตอน Build):**

| Name | Value | หมายเหตุ |
|------|--------|----------|
| `VITE_SUPABASE_URL` | ค่า Project URL จาก Supabase (เช่น `https://xxxx.supabase.co`) | บังคับ |
| `VITE_SUPABASE_ANON_KEY` | ค่า anon public key จาก Supabase | บังคับ |
| `VITE_API_BASE` | เว้นว่างได้ (ถ้าแอปกับ API อยู่โดเมนเดียวกัน) หรือใส่ URL เต็ม (เช่น `https://okace.pages.dev`) | ใช้เรียก /api/vault/* |

**สำหรับ Cloudflare Pages Functions (ใช้ตอนรัน Function):**  
ใช้กับ `/api/vault/*`, **สร้างผู้ใช้** (`/api/admin/create-user`), **จองพักอาหาร** (`/api/meal/proxy`) และ **shifts proxy** (`/api/shifts/proxy`) — ต้องตั้งครบและเลือก **Production** (และ **Preview** ถ้าทดสอบ branch อื่น)

ไปที่ **Settings** → **Environment variables** เลือก **Encrypt** สำหรับค่าลับ

| Name | Value | หมายเหตุ |
|------|--------|----------|
| `ENCRYPTION_KEY` | Base64 ของ key 32 bytes (AES-256) | สร้างด้วย: `openssl rand -base64 32` (รันในเครื่องหรือเครื่องอื่นแล้ววางค่า) |
| `SUPABASE_URL` | ค่า Project URL จาก Supabase | **ต้องเหมือน VITE_SUPABASE_URL ทุกตัวอักษร** (โปรเจกต์เดียวกัน) เพื่อให้ API สร้างผู้ใช้ตรวจโทเค็นได้ |
| `SUPABASE_ANON_KEY` | ค่า anon public จาก Supabase | สำหรับ encrypt ตรวจ role |
| `SUPABASE_SERVICE_ROLE_KEY` | ค่า service_role จาก Supabase | สำหรับ decrypt + เขียน audit_logs (ห้ามเปิดเผยฝั่ง Client) |

หมายเหตุ:  
- `VITE_*` จะถูก embed ใน build ดังนั้นไม่ใส่ secret ที่เป็นความลับสูงใน VITE_  
- ค่าเช่น `ENCRYPTION_KEY`, `SUPABASE_SERVICE_ROLE_KEY` ใส่เป็น Encrypted / Secret ใน Cloudflare

#### 2.3 Deploy และทดสอบ

1. หลังเพิ่ม Environment Variables ให้กด **Retry deployment** หรือ push commit ใหม่
2. เปิด URL ของแอป (เช่น `https://okace.pages.dev`)
3. ล็อกอินด้วยบัญชี Admin ที่สร้างใน Supabase (ใส่ชื่อผู้ใช้ หรืออีเมล + รหัสผ่าน — ถ้ารัน 004_login_by_username แล้ว)
4. ทดสอบ: ลงเวลา, ตารางวันหยุด, คลังรหัสผ่าน (สร้างรายการ + กดแสดงรหัสผ่าน เพื่อทดสอบ decrypt และ audit)

### (ตัวเลือก) รัน Frontend ในเครื่อง

ถ้าต้องการทดสอบแอปในเครื่องก่อน deploy:

1. เปิดโฟลเดอร์โปรเจกต์ แล้วเข้าโฟลเดอร์ `frontend`
2. สร้างไฟล์ `.env` หรือ `.env.local` ใส่:
   - `VITE_SUPABASE_URL` = Project URL จาก Supabase
   - `VITE_SUPABASE_ANON_KEY` = anon key จาก Supabase
   - `VITE_API_BASE` = เว้นว่าง หรือ `http://localhost:5173` (สำหรับเรียก Functions ถ้ารัน local)
3. รันคำสั่ง: `npm ci` แล้ว `npm run dev`
4. เปิดเบราว์เซอร์ที่ `http://localhost:5173`
5. ใน Supabase ตั้ง Redirect URLs ให้มี `http://localhost:5173/**` (ตาม 1.5)

การ deploy จริงยังทำผ่าน Cloudflare Pages ตามส่วนที่ 2 ข้างต้น ไม่กระทบงานอื่น

### สรุป Checklist Setup

- [ ] Supabase: สร้าง Project
- [ ] Supabase: รัน `schema.sql`
- [ ] Supabase: รัน schema.sql แล้ว migrations 01→34 หรือ full_install.sql (ดู migrations/README.md)
- [ ] Supabase: สร้าง Storage bucket `vault` + Policy
- [ ] Supabase: เปิด Realtime ตามตารางที่ใช้ (หรือรัน migration 003)
- [ ] Supabase: ตั้ง Redirect URLs
- [ ] Supabase: สร้าง User + แถว `profiles` role admin
- [ ] Cloudflare Pages: เชื่อม GitHub, Root = `frontend`, Build = `npm ci && npm run build`, Output = `dist`
- [ ] Cloudflare Pages: ตั้ง VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY, VITE_API_BASE
- [ ] Cloudflare Pages: ตั้ง ENCRYPTION_KEY, SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
- [ ] Deploy และล็อกอินทดสอบ

ถ้าทำครบตามนี้ ระบบจะพร้อมใช้งาน Production (และไม่ต้องรัน npm ในเครื่องของคุณ).

---

## 3. BUILD — การ Build บน Cloudflare

# Build (Cloudflare Pages)

โปรเจกต์นี้ **ไม่รัน build ในเครื่อง** — Deploy ผ่าน Push ไป GitHub แล้ว Cloudflare Pages จะ build ให้อัตโนมัติ

### ถ้า Build ล้มเหลวบน Cloudflare

#### สาเหตุที่พบบ่อย: ใช้ `npm ci` แต่ไม่มี lock file

โฟลเดอร์ `frontend` อาจยังไม่มี `package-lock.json`  
คำสั่ง **`npm ci`** ต้องมีไฟล์นี้อยู่แล้ว

#### แก้ไข (ตั้งผ่าน Dashboard เท่านั้น)

ใน **Cloudflare Pages → โปรเจกต์ okace → Settings → Build**  
เปลี่ยน **Build command** เป็น:

```text
npm install && npm run build
```

แล้ว Save และ Deploy ใหม่ (หรือ Push commit ใหม่ให้ trigger deploy)

Environment Variables ตั้งใน **Cloudflare Pages → Settings → Variables and Secrets**  
ไม่มีการรัน build หรือคำสั่ง Node/npm ในเครื่อง local

---

## 4. BRANCH_SCOPE — การแบ่งการมองเห็นตามแผนก

# การแบ่งการมองเห็นข้อมูลตามแผนก (Branch Scope)

แผนก = **branches** (ใช้ `public.branches.id`) ไม่สร้างตาราง departments ใหม่

### สรุปการทำงาน

| บทบาท | แผนกประจำ | การมองเห็นข้อมูล | UI |
|--------|------------|------------------|-----|
| **Admin / Manager / หัวหน้าพนักงานประจำ** | ไม่บังคับ (null ได้) | เห็นทุกแผนก | Dropdown เลือกแผนก + ค้นหาชื่อ (ทุกหน้ารายการ) |
| **พนักงานประจำ (instructor) / พนักงานออนไลน์ (staff)** | บังคับมี `default_branch_id` | เห็นเฉพาะแผนกตัวเอง | ไม่มี dropdown แผนก (ใช้แผนกจากโปรไฟล์) + Toggle 「เฉพาะของฉัน」 |

### RLS (บังคับที่ Supabase)

- **Helper:** `my_branch_id()` = แผนกประจำของ current user (instructor/staff); admin ได้ `null`
- **SELECT:** Admin เห็นทุกแถว; Instructor/Staff เห็นเฉพาะ `branch_id = my_branch_id()`
- **INSERT:** Staff/Instructor สร้างได้เฉพาะเมื่อ `branch_id = my_branch_id()` และ `user_id = auth.uid()` (ตามตาราง)
- **UPDATE อนุมัติ (approved_by/status):** เฉพาะ admin

Migrations: ดู `supabase/sql/migrations/README.md` (รวม 007, 011, 057 ฯลฯ)

### ข้อกำหนด profiles

- Instructor และ Staff **ต้องมี** `default_branch_id` (CHECK constraint)
- Backfill: ถ้าไม่มีจะตั้งเป็นสาขาแรกที่ active

### Checklist ทดสอบ Branch Scope

- [ ] **Staff/Instructor เห็นเฉพาะข้อมูลแผนกตัวเอง:** ล็อกอินเป็น staff/instructor เปิดตารางวันหยุด, ลงเวลา, พัก, จัดหน้าที่ ฯลฯ — ต้องเห็นเฉพาะข้อมูลที่ `branch_id` = แผนกประจำ (และเลือกแผนกอื่นใน dropdown ไม่ได้)
- [ ] **เปิด 「เฉพาะของฉัน」:** ในตารางวันหยุด ติ๊ก "เฉพาะของฉัน" — เห็นเฉพาะแถว/รายการของตัวเอง
- [ ] **RLS กันการดูข้ามแผนก:** พยายามเรียก API/query ด้วย `branch_id` ของแผนกอื่น (ถ้ามีทางทดสอบ) — ต้องได้ข้อมูลว่างหรือถูกปฏิเสธ
- [ ] **Admin เห็นทุกแผนก:** ล็อกอินเป็น admin — มี dropdown แผนกในทุกหน้ารายการ และเลือกแผนกใดก็ได้
- [ ] **Settings จัดการแผนก:** หน้า Settings มีตารางแผนก (เพิ่ม/แก้ไข/ปิดใช้งาน) และ dropdown อื่นใช้เฉพาะแผนกที่ active

---

## 5. MANAGED_WEBSITES — เว็บที่ดูแล

# โมดูล เว็บที่ดูแล (Managed Websites)

### Permission Matrix

| การกระทำ | Admin | Instructor / Staff |
|----------|--------|---------------------|
| ดูรายการเว็บทั้งหมด | ✅ ได้ | ❌ ไม่ได้ (เห็นเฉพาะเว็บที่ถูก assign ให้ตัวเอง) |
| ดูเว็บที่ตัวเองดูแล | ✅ ได้ | ✅ ได้ |
| เพิ่มเว็บ | ✅ ได้ | ❌ ไม่ได้ |
| แก้ไขเว็บ | ✅ ได้ | ❌ ไม่ได้ |
| ลบเว็บ | ✅ ได้ | ❌ ไม่ได้ |
| มอบหมาย/เอาออก/ตั้งเว็บหลัก | ✅ ได้ | ❌ ไม่ได้ |

- **Admin**: เต็มสิทธิ์บนตาราง `websites` และ `website_assignments` (RLS อนุญาตทุกอย่าง)
- **Instructor/Staff**: 
  - `websites`: SELECT ได้เฉพาะแถวที่ id อยู่ใน assignment ของตัวเอง (ผ่าน RLS)
  - `website_assignments`: SELECT ได้เฉพาะที่ `user_id = auth.uid()`; INSERT/UPDATE/DELETE ถูกห้ามโดย RLS

### Checklist ทดสอบ Managed Websites

- [ ] **User ดูแลหลายเว็บได้**: มอบหมายหลายเว็บให้ user คนเดียว แล้วตรวจว่าใน "เว็บที่ฉันดูแล" แสดงครบ
- [ ] **ตั้งเว็บหลักได้แค่ 1**: ตั้งเว็บ A เป็นหลัก แล้วตั้งเว็บ B เป็นหลัก — ต้องเหลือเฉพาะ B เป็นหลัก (index partial unique บังคับ)
- [ ] **Staff เห็นเฉพาะเว็บตัวเอง**: ล็อกอินเป็น instructor/staff เปิด "เว็บที่ฉันดูแล" — ต้องเห็นเฉพาะเว็บที่ถูก assign ให้ตัวเอง และไม่มีปุ่มเพิ่ม/แก้ไข/ลบ
- [ ] **Admin เห็นทุกแผนกและจัดการได้**: ล็อกอินเป็น admin เปิด "เว็บที่ดูแล" — Tab รายการเว็บเห็นทั้งหมด, Tab จัดการผู้ดูแลสามารถเลือกผู้ใช้ เพิ่ม/เอาออก/ตั้งเว็บหลักได้ และมี confirm modal ก่อนลบ/เอาออก
- [ ] **Audit log**: หลัง Admin เพิ่ม/แก้/ลบเว็บ หรือ assign/unassign/set primary ตรวจในตาราง audit_log ว่ามี action ตาม (WEBSITE_CREATE, WEBSITE_UPDATE, WEBSITE_DELETE, WEBSITE_ASSIGN, WEBSITE_UNASSIGN, WEBSITE_SET_PRIMARY)

### Routes และเมนู

- **Admin**: `/เว็บที่ดูแล` — เมนู "เว็บที่ดูแล" (แสดงเฉพาะ role admin)
- **Instructor/Staff**: `/เว็บที่ฉันดูแล` — เมนู "เว็บที่ฉันดูแล" (แสดงเฉพาะ instructor, staff)

### ข้อมูลและ RLS

- ตาราง: `websites` (ผูก `branch_id`), `website_assignments` (user–website many-to-many, `is_primary` ต่อ user ได้ 1 เว็บ)
- RPC: `set_primary_website(p_user_id, p_website_id)` สำหรับสลับเว็บหลักแบบ atomic
- Audit entity: `managed_website`

---

## 6. ROLE_ADMIN_NOT_STAFF — Admin ไม่ใช่พนักงาน

# ปรับ Logic Role: Admin ไม่ใช่พนักงาน

เอกสารสรุปการแก้ไขตามความต้องการ "Admin เป็นผู้ดูแลระบบอย่างเดียว ไม่ลงเวลา/พัก/ขอลา/สลับกะ/ย้ายกะ และไม่ถูกนับในกติกาพัก/โควต้า"

### 1) รายการไฟล์ที่แก้ไข + เหตุผล

| ไฟล์ | การแก้ไข |
|------|----------|
| **supabase/sql/migrations/005_admin_not_staff_rls.sql** | (ใหม่) เพิ่มฟังก์ชัน `is_staff_or_instructor()` และแก้ RLS policy ของ work_logs, break_logs, holidays, shift_swaps, cross_branch_transfers ให้ **INSERT ได้เฉพาะเมื่อ user เป็น instructor หรือ staff** (admin ห้าม insert ลงตารางเหล่านี้ด้วยตัวเอง) |
| **frontend/src/lib/auth.tsx** | เพิ่ม `isEmployeeRole(role)` สำหรับเช็คบทบาทพนักงาน (instructor/staff) |
| **frontend/src/lib/breaks.ts** | `estimateStaffCount()` ปรับให้นับเฉพาะผู้ใช้ที่ **role เป็น instructor หรือ staff** (join กับ profiles, ไม่นับ admin) เพื่อใช้ในกติกาพัก (break concurrency) |
| **frontend/src/App.tsx** | เพิ่ม `staffOnly` ใน `ProtectedRoute`; กำหนด route **ลงเวลา, พัก, งานของฉัน** เป็น staff-only (admin จะถูก redirect ไป /dashboard) |
| **frontend/src/components/Nav.tsx** | กำหนด **ลงเวลา** และ **พัก** ให้แสดงเฉพาะ `roles: ['instructor', 'staff']` (admin ไม่เห็นเมนูนี้) |
| **frontend/src/pages/Dashboard.tsx** | แยก quick links: **Admin** เห็นเฉพาะ อนุมัติวันหยุด/สลับกะ/ย้ายกะ, ตารางกะรายเดือน, จัดหน้าที่, ตั้งค่า, ประวัติ; **Staff/Instructor** เห็น ลงเวลา, พัก, ตารางวันหยุด, จัดหน้าที่, ตารางงาน |
| **frontend/src/pages/DutyBoard.tsx** | โหลดรายชื่อ staff สำหรับจัดหน้าที่เฉพาะ **role in ('instructor', 'staff')** (admin ไม่ถูกแสดงในรายชื่อให้เลือกจัด) |
| **frontend/src/pages/HolidayGrid.tsx** | โหลด staff list สำหรับตารางวันหยุดเฉพาะ **instructor/staff** (ไม่แสดงแถวของ admin ในตาราง) |
| **frontend/src/pages/Timekeeping.tsx** | เพิ่ม runtime guard: ถ้า role เป็น admin ให้แสดงข้อความ "บัญชีผู้ดูแลระบบไม่สามารถทำรายการนี้ได้" ก่อนลงเวลา |
| **frontend/src/pages/Breaks.tsx** | เพิ่ม runtime guard ใน startBreak/endBreak: ถ้า role เป็น admin แสดงข้อความ "บัญชีผู้ดูแลระบบไม่สามารถทำรายการนี้ได้" |

### 2) RLS Policies SQL

- **ไฟล์:** `supabase/sql/migrations/005_admin_not_staff_rls.sql`
- **เนื้อหาหลัก:**
  - สร้างฟังก์ชัน `is_staff_or_instructor()` คืน true เฉพาะเมื่อ `profiles.role IN ('instructor', 'staff')`
  - แก้ **work_logs_insert**: `WITH CHECK (user_id = auth.uid() AND is_staff_or_instructor())`
  - แก้ **break_logs_insert**, **holidays_insert**, **shift_swaps_insert**, **transfers_insert** ในรูปแบบเดียวกัน
- **การรัน:** รันใน Supabase SQL Editor หลัง deploy หรือใช้ `supabase db push` (ถ้าใช้ CLI)

### 3) สรุปพฤติกรรมหลังแก้

#### Admin (ผู้ดูแลระบบ) ทำได้ / ทำไม่ได้

- **ทำได้:** ดู/จัดการ/อนุมัติ วันหยุด, สลับกะ, ย้ายกะ; ยืนยันตารางกะรายเดือน; จัดหน้าที่ (จัดให้ instructor/staff); ตั้งค่า; ประวัติ; คลังรูป/รหัสผ่าน/กลุ่มงาน; ตารางงาน (จัดการการ์ด)
- **ทำไม่ได้:** เลือกกะ/สาขาเพื่อลงข้อมูลแบบพนักงาน, ลงเวลา IN/OUT, เริ่มพัก/เลิกพัก, ขอวันหยุด, ขอสลับกะ, ขอย้ายกะข้ามสาขา, เปิดเมนู ลงเวลา/พัก/งานของฉัน (redirect ไป dashboard)
- **ไม่ถูกนับ:** จำนวนพนักงานในกติกาพัก (break concurrency) และในรายชื่อ staff สำหรับจัดหน้าที่/ตารางวันหยุด นับเฉพาะ instructor + staff

#### Instructor / Staff (พนักงานตามกะ) ทำได้

- เลือกสาขา + กะ (จำค่าล่าสุดได้), ลงเวลา, พัก/กินข้าวตามกติกา, ขอวันหยุด, ขอสลับกะ, ขอ/ย้ายกะข้ามสาขา, ดูจัดหน้าที่/ตารางงาน, งานของฉัน (Staff/Instructor)
- Instructor มีสิทธิ์มอบหมายงาน/ติดตามงานเพิ่ม แต่ยังอยู่ในระบบกะเหมือน Staff

#### UI/เมนู

- **role = Admin:** เมนูแสดงเฉพาะ แดชบอร์ด, ตารางวันหยุด, สลับกะ, ย้ายกะข้ามสาขา, ประวัติย้ายกะ, ตารางกะรายเดือน, จัดหน้าที่, ตารางงาน, คลังรูป, คลังรหัสผ่าน, กลุ่มงาน, ประวัติ, ตั้งค่า (ไม่มี ลงเวลา, พัก, งานของฉัน)
- **role = Instructor/Staff:** เมนูแสดง ลงเวลา, พัก, ตารางวันหยุด, สลับกะ, ย้ายกะ, ประวัติย้ายกะ, ตารางกะรายเดือน, จัดหน้าที่, ตารางงาน, งานของฉัน, ประวัติ (ไม่มี ตั้งค่า)

### 4) Breaking change และการทดสอบ

- **ไม่มี breaking change กับ flow หลัก:** ผู้ใช้เดิมที่ role = instructor หรือ staff ยังใช้ ลงเวลา/พัก/ขอลา/สลับกะ/ย้ายกะ ได้เหมือนเดิม
- **Admin:** ไม่สามารถเข้า path ลงเวลา, พัก, งานของฉัน (redirect อัตโนมัติ); เมนูและแดชบอร์ดแยกตาม role ชัดเจน
- **Build:** โครงสร้างและ route เดิมไม่ถูกลบ แค่เพิ่มเงื่อนไข role และ RLS; แนะนำให้รัน `npm run build` ใน frontend เพื่อยืนยันว่า build ผ่าน (รวม Cloudflare Pages)
