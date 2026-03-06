# การปรับปรุงระดับมืออาชีพ/Enterprise (ไม่กระทบ flow)

เอกสารสรุปสิ่งที่เพิ่มเข้าไปโดยไม่เปลี่ยน workflow หลักของระบบ

---

## 1) Error Boundary

- **ไฟล์:** `frontend/src/components/ErrorBoundary.tsx`
- **การใช้งาน:** ห่อ Layout ใน `App.tsx` — ถ้า component ลูก throw error จะแสดงหน้าข้อความ "เกิดข้อผิดพลาด" และปุ่ม "โหลดใหม่" แทน white screen
- **ผลกระทบ:** ไม่กระทบ flow — แค่จับ error แล้วให้ผู้ใช้กดโหลดใหม่ได้

---

## 2) Security headers (Edge)

- **ไฟล์:** `frontend/functions/_middleware.ts`
- **การใช้งาน:** ทุก response ถูกใส่ header:
  - `X-Frame-Options: DENY`
  - `X-Content-Type-Options: nosniff`
  - `Referrer-Policy: strict-origin-when-cross-origin`
- **ผลกระทบ:** ไม่กระทบ flow — แค่เพิ่มความปลอดภัยเบื้องต้น

---

## 3) Health check

- **Endpoint:** GET `/api/health`
- **ไฟล์:** `frontend/functions/api/health.ts`
- **การใช้งาน:** คืน `200` และ `{ "ok": true, "ts": "..." }` ไม่ยิง DB ใช้สำหรับ monitoring / uptime check
- **ผลกระทบ:** ไม่กระทบ flow — ใช้สำหรับตรวจสถานะระบบเท่านั้น

---

## 4) Rate limiting (เอกสาร)

- **ไฟล์:** `docs/CLOUDFLARE_SETUP_WORKERS_PAID_5USD.md` — เพิ่มหมวด E) Rate limiting
- **การใช้งาน:** แนะนำให้ตั้ง rate limit ที่ Cloudflare WAF สำหรับ `/login`, `/api/auth/*`, `/api/admin/*` ตามความเหมาะสม
- **ผลกระทบ:** ไม่มีในโค้ด — ถ้าตั้งที่ Cloudflare ต้องตั้งขีดจำกัดให้ไม่กระทบผู้ใช้ปกติ

---

## 5) Audit log สำหรับการแก้สาขา/กะ

- **ไฟล์:** `frontend/src/pages/Settings.tsx`
- **การใช้งาน:**
  - หลัง **แก้ไข/เพิ่มสาขา** (saveBranch) — เรียก `logAudit('update'|'create', 'branch', id, details, summary)`
  - หลัง **แก้เวลากะ** (saveShiftTimes) — เรียก `logAudit('update', 'shift', id, details, summary)`
- **ผลกระทบ:** ไม่กระทบ flow — แค่บันทึกประวัติใน `audit_logs` ตามเดิม

---

## สรุป

ทุกรายการเป็นการ **เพิ่มเฉพาะ** (additive) ไม่ลบหรือเปลี่ยน logic หลัก ระบบเดิมทำงานได้เหมือนเดิม และสามารถ deploy ผ่าน GitHub → Cloudflare ตามปกติ
