# คู่มือตั้งค่าแรก — OKACE (Cloudflare + Supabase ผ่าน GitHub)

รันใหม่ทั้งหมดผ่าน **Dashboard** เท่านั้น — ไม่ใช้ Node / Wrangler / local

---

## สรุปภาพรวม

| ส่วน | ทำที่ | สรุป |
|------|--------|------|
| ฐานข้อมูล | **Supabase** → SQL Editor | รัน SQL ครั้งแรก (schema + migrations หรือ full_install) |
| Storage + Realtime + Auth | **Supabase** → Storage / Database / Auth | สร้าง bucket, เปิด Realtime, ตั้ง Redirect URL |
| แอป Frontend + API | **Cloudflare Pages** | เชื่อม GitHub, ตั้ง Root/Build/Output + Environment Variables |
| Cron (ย้ายกะอัตโนมัติ) | **Supabase** → SQL (pg_cron) | ตัวเลือก — รันหลัง DB พร้อม |

---

## ขั้นที่ 1: Supabase — ฐานข้อมูล

### 1.1 สร้างโปรเจกต์

1. [supabase.com](https://supabase.com) → **New Project**
2. ตั้งชื่อ, เลือก Region, ใส่รหัสผ่าน Database
3. รอสร้างเสร็จ → **Project Settings** → **API** จดค่า:
   - **Project URL** (เช่น `https://xxxx.supabase.co`)
   - **anon public** (สำหรับ Frontend + Functions)
   - **service_role** (สำหรับ Functions เท่านั้น — ห้ามเปิดเผยฝั่ง Client)

### 1.2 รัน SQL (ครั้งแรก — เลือกอย่างใดอย่างหนึ่ง)

**ตัวเลือก A — แนะนำ (รันไฟล์เดียว)**

1. เปิด **SQL Editor**
2. เปิดไฟล์ใน repo: **`supabase/sql/migrations/full_install.sql`**
3. คัดลอกเนื้อหาทั้งหมด → วางใน SQL Editor → **Run**

**ตัวเลือก B — รันแยกไฟล์**

1. รัน **`supabase/sql/schema.sql`** ก่อน (จาก `supabase/sql/schema.sql`)
2. รันตามลำดับ: **01** → **02** → **03** → … → **34** จากโฟลเดอร์ `supabase/sql/migrations/`  
   (รายละเอียดลำดับและชื่อไฟล์ดูใน **`supabase/sql/migrations/README.md`**)

ถ้าเจอ error เรื่อง `ALTER TYPE ... ADD VALUE` ใน 01 ให้รันเฉพาะบรรทัดนั้นแยกครั้งเดียว แล้วรันส่วนที่เหลือของ 01 ต่อ

---

## ขั้นที่ 2: Supabase — Storage, Realtime, Auth

### 2.1 Storage bucket (คลังรูป)

1. **Storage** → **New bucket**
2. ชื่อ: **`vault`**
3. ตั้ง **Public** ตามต้องการ (ดูรูปผ่าน URL)
4. สร้าง Policy:
   - **Upload**: INSERT, roles = authenticated, WITH CHECK = `bucket_id = 'vault'`
   - **Read**: SELECT, roles = authenticated, USING = `bucket_id = 'vault'`

(รายละเอียด RLS storage ใน `full_install` / migrations มีการสร้าง policy บน `storage.objects` อยู่แล้ว ถ้ารัน full_install แล้วอาจมี policy จาก migration — ตรวจสอบใน Storage → Policies)

### 2.2 เปิด Realtime

ใน **SQL Editor** รัน:

```sql
ALTER PUBLICATION supabase_realtime ADD TABLE holidays;
ALTER PUBLICATION supabase_realtime ADD TABLE shift_swaps;
ALTER PUBLICATION supabase_realtime ADD TABLE cross_branch_transfers;
ALTER PUBLICATION supabase_realtime ADD TABLE duty_assignments;
ALTER PUBLICATION supabase_realtime ADD TABLE monthly_roster_status;
ALTER PUBLICATION supabase_realtime ADD TABLE monthly_roster;
ALTER PUBLICATION supabase_realtime ADD TABLE break_logs;
```

ถ้าตารางใดขึ้น "already member" ให้ข้ามบรรทัดนั้น

### 2.3 Auth — Redirect URLs

1. **Authentication** → **URL Configuration**
2. **Redirect URLs** เพิ่ม:
   - `https://<your-pages-name>.pages.dev/**`
   - โดเมน custom (ถ้ามี) เช่น `https://yourdomain.com/**`

### 2.4 สร้างผู้ใช้ Admin แรก

1. **Authentication** → **Users** → **Add user** → สร้าง user (Email + Password)
2. จด **User UID** (UUID)
3. ใน **SQL Editor** รัน (แทนที่ `USER_UID`, `EMAIL`, ชื่อจริง; branch/shift จะใช้แถวแรกของตาราง):

```sql
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

ถ้าไม่มีแถวใน `branches` / `shifts` ต้อง seed หรือเพิ่มแถวในตารางนั้นก่อน (schema/migrations มี seed ตาม repo)

---

## ขั้นที่ 3: Cloudflare Pages

### 3.1 สร้างโปรเจกต์จาก GitHub

1. [dash.cloudflare.com](https://dash.cloudflare.com) → **Workers & Pages** → **Create** → **Pages** → **Connect to Git**
2. เลือก GitHub แล้วเลือก repo โปรเจกต์
3. ตั้งค่า Build:
   - **Production branch**: `main` (หรือ branch หลัก)
   - **Root directory**: **`frontend`**
   - **Build command**: `npm ci && npm run build`  
     ถ้าไม่มี `package-lock.json` ใน repo ให้ใช้ `npm install && npm run build`
   - **Build output directory**: **`dist`**
4. **Save and Deploy**

### 3.2 Environment Variables

ไปที่ **Settings** → **Environment variables** ของโปรเจกต์ Pages

**ใช้ตอน Build (ไม่ลับ):**

| Name | Value | หมายเหตุ |
|------|--------|----------|
| `VITE_SUPABASE_URL` | Project URL จาก Supabase | บังคับ |
| `VITE_SUPABASE_ANON_KEY` | anon public key จาก Supabase | บังคับ |
| `VITE_API_BASE` | เว้นว่าง หรือ URL แอป (เช่น `https://okace.pages.dev`) | ใช้เรียก /api/* ถ้า cross-origin |

**ใช้ตอนรัน Functions (ลับ — ใส่ Encrypted):**

| Name | Value | หมายเหตุ |
|------|--------|----------|
| `SUPABASE_URL` | Project URL จาก Supabase | ต้องเหมือน VITE_SUPABASE_URL |
| `SUPABASE_ANON_KEY` | anon public จาก Supabase | สำหรับ proxy / ตรวจ role |
| `SUPABASE_SERVICE_ROLE_KEY` | service_role จาก Supabase | สร้าง user, reset password, บาง RPC — ห้ามเปิดเผยฝั่ง Client |
| `ENCRYPTION_KEY` | Base64 key 32 bytes (AES-256) | สร้างด้วย `openssl rand -base64 32` (รันที่อื่นแล้ววางค่า) — ใช้คลังรหัสผ่าน |

เลือก **Production** (และ **Preview** ถ้าต้องการทดสอบ branch อื่น) ให้ครบทุกตัวแปร

### 3.3 Deploy หลังตั้งค่า

หลังเพิ่ม/แก้ Environment Variables ให้ **Retry deployment** หรือ push commit ใหม่ แล้วเปิด URL แอป (เช่น `https://<project>.pages.dev`) ล็อกอินด้วยบัญชี Admin ที่สร้างในขั้น 2.4

---

## ขั้นที่ 4 (ตัวเลือก): Cron — ย้ายกะอัตโนมัติทุกวัน

ถ้าต้องการให้ระบบอัปเดตกะ (ย้ายกะ/สลับกะ) อัตโนมัติทุกวัน 00:01 (Asia/Bangkok):

1. เปิด **Database** → **Extensions** → เปิดใช้ **pg_cron** (หรือรัน `CREATE EXTENSION IF NOT EXISTS pg_cron;`)
2. ใน **SQL Editor** รันเนื้อหาจาก **`supabase/sql/cron_apply_shift_changes_setup.sql`**  
   (จะลงทะเบียน job `apply_shift_changes_daily` เรียก `run_apply_shift_changes_and_log()` — ฟังก์ชันนี้มีอยู่แล้วจาก migration 17 / full_install)

ตรวจสอบว่า job ถูกสร้าง: `SELECT jobid, jobname, schedule, command FROM cron.job;`

---

## Checklist สรุป

- [ ] Supabase: สร้าง Project + จด URL, anon key, service_role key
- [ ] Supabase: รัน SQL ครั้งแรก — **full_install.sql** หรือ **schema.sql** แล้ว 01→34
- [ ] Supabase: สร้าง Storage bucket **vault** + Policy
- [ ] Supabase: เปิด Realtime ตามตาราง (holidays, shift_swaps, … break_logs)
- [ ] Supabase: ตั้ง Redirect URLs ใน Auth
- [ ] Supabase: สร้าง User + แถว **profiles** role admin
- [ ] Cloudflare Pages: เชื่อม GitHub, Root = **frontend**, Build = **npm ci && npm run build** (หรือ npm install), Output = **dist**
- [ ] Cloudflare Pages: ตั้ง VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY, VITE_API_BASE
- [ ] Cloudflare Pages: ตั้ง SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY, ENCRYPTION_KEY (Production + Preview ตามต้องการ)
- [ ] Deploy แล้วล็อกอินทดสอบ
- [ ] (ตัวเลือก) Supabase: รัน **cron_apply_shift_changes_setup.sql** สำหรับย้ายกะอัตโนมัติ

ทำครบตามนี้ ระบบพร้อมใช้งานบน Cloudflare + Supabase โดยไม่ต้องรัน Node/Wrangler/local.
