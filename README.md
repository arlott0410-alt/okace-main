# OKACE — ระบบลงเวลาและจัดการกะ

ระบบลงเวลา + ตารางวันหยุด/กะ + จัดหน้าที่ + คลังรูป + คลังรหัสผ่าน + ลิงก์กลุ่ม + ประวัติการทำรายการ  
ธีม Premium ดำ-ทอง (#0B0F1A / #D4AF37) ภาษาไทยทั้งระบบ

---

## ข้อกำหนดสำคัญ

- **ไม่ใช้ Node.js / Wrangler ในเครื่อง** — Deploy ผ่าน GitHub → Cloudflare Pages เท่านั้น
- **ฐานข้อมูล**: Supabase (Postgres + Auth + Realtime + Storage)
- **Environment Variables** ตั้งค่าทั้งหมดผ่าน Dashboard (Supabase + Cloudflare Pages)

---

## โครงสร้างโปรเจกต์

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
│       ├── schema.sql      # ตาราง, RLS, seed หลัก
│       └── migrations/     # SQL เพิ่มเติม 3 ไฟล์ (รันตามลำดับหลัง schema)
│           ├── README.md   # ลำดับ 01 → 02 → 03
│           ├── 01_consolidated_001_to_025.sql
│           ├── 02_enum_manager_only.sql
│           └── 03_002_to_057.sql
└── docs/
    └── DOCS.md        # เอกสารรวม (Setup, Build, Branch, เว็บที่ดูแล, Role)
```

---

## การ Deploy (ทำใน Dashboard)

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
   - ตั้ง Environment Variables ตาม `docs/DOCS.md`

3. **หลัง Deploy**  
   - สร้างผู้ใช้ใน Supabase Auth (สมัครหรือ Invite)  
   - เพิ่มแถวในตาราง `profiles` (id = auth.users.id, role = 'admin' / 'manager' / 'instructor_head' / 'instructor' / 'staff')

---

## Build (สำหรับ CI ของ Cloudflare)

- ในเครื่องไม่จำเป็นต้องรัน `npm install` / `npm run build`  
- Cloudflare Pages จะรันอัตโนมัติ:  
  - **Build command:** `npm ci && npm run build`  
  - **Output directory:** `dist`

---

## สิทธิ์ (Roles)

| Role | สิทธิ์หลัก |
|------|------------|
| ผู้ดูแลระบบ (admin) | จัดการสาขา/กะ/พนักงาน/ตั้งค่า/อนุมัติ/คลังรูป/คลังรหัสผ่าน/กลุ่มงาน/ประวัติ |
| ผู้จัดการ (manager) | เห็นทุกแผนก เหมือนแอดมิน; จัดการอนุมัติ/ตาราง/กลุ่มงาน/คลังรหัสผ่าน (แก้ไข user ได้) |
| หัวหน้าพนักงานประจำ (instructor_head) | เห็นทุกแผนกเหมือนผู้จัดการ; แก้ไข user ได้เฉพาะ instructor/staff ในแผนกตัวเอง |
| พนักงานประจำ (instructor) | ดูตารางกะ-วันหยุด, สร้าง-มอบหมายงาน, ลงเวลา, พัก |
| พนักงานออนไลน์ (staff) | ลงเวลา, พัก, ขอวันหยุด/สลับกะ/ย้ายกะ, ดูจัดหน้าที่/งานที่ได้รับมอบหมาย |

---

## ฟีเจอร์เพิ่ม (Backward Compatible)

- **กติกาพัก (Break Concurrency)** — ตั้งค่าต่อสาขา/กะ ใน ตั้งค่า > กติกาพัก; หน้า พัก มีปุ่มเริ่มพัก/เลิกพัก + Admin เห็นคนกำลังพักและประวัติ
- **ยืนยันตารางกะรายเดือน** — หน้า ตารางกะรายเดือน: Admin ยืนยัน/ปลดล็อก; หลังยืนยัน จัดหน้าที่ เป็น read-only
- **ย้ายกะข้ามสาขา + ประวัติ** — หน้า ย้ายกะข้ามสาขา (filter เดือน/สาขา/สถานะ, admin_note); หน้า ประวัติย้ายกะ แยกสำหรับดูประวัติ

## Migration (รันหลัง schema หลัก)

รันใน Supabase SQL Editor **ตามลำดับ**: **schema.sql** แล้ว **01 → 02 → … → 34**  
หรือรันไฟล์เดียว **migrations/full_install.sql** (รวม schema + 01 ถึง 34)  
รายการและคำอธิบาย: **[supabase/sql/migrations/README.md](supabase/sql/migrations/README.md)**  
(02 ต้องรันแยกเพราะ PostgreSQL ใช้ค่า enum ใหม่ได้หลัง commit)

## เอกสารเพิ่มเติม

- [docs/DOCS.md](docs/DOCS.md) — เอกสารรวม (Setup, Build, Branch Scope, เว็บที่ดูแล, Role Admin)
