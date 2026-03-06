# Cloudflare Setup (Workers Paid $5 plan)

เอกสารนี้เป็นขั้นตอนติดตั้งและผูก KV / Durable Objects / Environment Variables สำหรับโปรเจกต์ OKACE บน Cloudflare Pages โดยทุกฟีเจอร์เป็น **optional** — ถ้าไม่ได้ตั้งค่า ระบบทำงานเหมือนเดิม 100%

---

## A) Workers KV — Edge cache

KV ใช้สำหรับ:
- **allow_mobile_access** (middleware): cache ค่าปิด/เปิดมือถือ 60 วินาที
- **cache:branches** / **cache:shifts** (GET /api/cache/branches, /api/cache/shifts): cache รายการสาขา/กะ 5 นาที ลดการยิง Supabase เมื่อโหลดแอป

1. ใน Cloudflare Dashboard ไปที่ **Workers & Pages** → **KV** → **Create a namespace**
2. ตั้งชื่อ namespace (เช่น `OKACE_KV` หรือชื่อที่ต้องการ) → สร้าง
3. ไปที่ **Pages** → เลือกโปรเจกต์ frontend ของคุณ → **Settings** → **Functions**
4. ใน **KV namespace bindings** → **Add binding**
   - **Variable name**: `OKACE_KV` (ต้องใช้ชื่อนี้ในโค้ด)
   - **KV namespace**: เลือก namespace ที่สร้างในขั้น 1
5. Save

**Fallback:** ถ้าไม่ผูก `OKACE_KV` ระบบจะใช้ in-memory cache (allow_mobile) และดึง branches/shifts ตรงจาก Supabase ไม่พัง

---

## B) Durable Objects — Idempotency สำหรับ create-user / create-users

1. โปรเจกต์มีโฟลเดอร์ `workers/okace-idempotency` ที่มี Durable Object class `IdempotencyStore`
2. Deploy Worker นี้ผ่าน Cloudflare Dashboard หรือ Wrangler (จาก repo อื่นหรือ CI):
   - ใช้ `workers/okace-idempotency/wrangler.toml` และ `workers/okace-idempotency/src/`
   - หลัง deploy จะได้ **Durable Object namespace** (มี id)
3. ไปที่ **Pages** → โปรเจกต์ frontend → **Settings** → **Functions**
4. ใน **Durable Object bindings** → **Add binding**
   - **Variable name**: `OKACE_IDEMPOTENCY` (ต้องใช้ชื่อนี้ในโค้ด)
   - **Durable Object namespace**: เลือก namespace จากขั้น 2
5. Save

**Fallback:** ถ้าไม่ผูก `OKACE_IDEMPOTENCY` ระบบจะใช้ idempotency แบบ in-memory / แบบเดิมใน create-user และ create-users ไม่พัง

---

## C) Environment Variables

ตั้งค่าใน **Pages** → โปรเจกต์ → **Settings** → **Environment variables** (และถ้ามี **Functions** section ให้ตั้งให้ครบทั้ง Build และ Functions ตามที่ Cloudflare แสดง)

| Variable | ใช้ที่ | ค่า (placeholder) | หมายเหตุ |
|----------|--------|---------------------|----------|
| `SUPABASE_URL` | Functions | PLACEHOLDER | URL โปรเจกต์ Supabase (ใช้อยู่แล้ว) |
| `SUPABASE_ANON_KEY` | Functions | PLACEHOLDER | Anon key (ใช้อยู่แล้ว) |
| `SUPABASE_SERVICE_ROLE_KEY` | Functions | PLACEHOLDER | Service role key (ใช้อยู่แล้ว) |
| `TURNSTILE_ENABLED` | Functions | `true` หรือ `false` | เปิด/ปิด Turnstile ที่ Login |
| `TURNSTILE_SITE_KEY` | Frontend build (VITE_) | PLACEHOLDER | Site key จาก Cloudflare Turnstile |
| `TURNSTILE_SECRET_KEY` | Functions | PLACEHOLDER | Secret key สำหรับ verify (ห้ามใส่ใน frontend) |
| `IDEMPOTENCY_TTL_SECONDS` | Worker okace-idempotency | จำนวนวินาที (เช่น `600`) | Optional; default 10 นาที |
| `VITE_TURNSTILE_ENABLED` | Frontend build | `true` หรือ `false` | ต้องตรงกับ TURNSTILE_ENABLED |
| `VITE_TURNSTILE_SITE_KEY` | Frontend build | PLACEHOLDER | ตรงกับ Turnstile Site Key |
| `VITE_CF_IMAGE_BASE` | Frontend build | PLACEHOLDER โดเมน | Optional; สำหรับ Cloudflare Image Resizing |

- **ห้ามใส่ค่าลับจริงลงในเอกสารหรือใน repo** — ใช้ PLACEHOLDER และตั้งค่าจริงใน Dashboard เท่านั้น

---

## D) ยืนยัน Cache Headers

1. เปิดแอปจากโดเมนที่ deploy (เช่น `https://<project>.pages.dev`)
2. เปิด DevTools → **Network**
3. โหลดหน้าแรก แล้วเลือก request ที่เป็น **JS/CSS ใน `/assets/*`**
   - ตรวจว่า response header มี `Cache-Control: public, max-age=31536000, immutable` (หรือใกล้เคียง)
4. เลือก request ไปที่ **`/api/*`** (เช่น `/api/auth/resolve-email?...`)
   - ตรวจว่า response header มี `Cache-Control: no-store`

ถ้าตรงกัน แสดงว่า static assets ถูก cache และ API ไม่ถูก cache ตามที่ตั้งไว้

---

## สรุป Fallback

| ฟีเจอร์ | ถ้าไม่ตั้งค่า |
|--------|----------------|
| KV (`OKACE_KV`) | ใช้ in-memory cache 60s ต่อ isolate เหมือนเดิม |
| Durable Object (`OKACE_IDEMPOTENCY`) | ใช้ idempotency ใน create-user/create-users แบบเดิม (in-memory / ไม่มี DO) |
| Turnstile | หน้า Login ทำงานเหมือนเดิม ไม่มี widget ไม่เรียก verify-turnstile |
| Cloudflare Images (`VITE_CF_IMAGE_BASE`) | `buildCfImageUrl()` คืนค่า URL เดิม ไม่ transform |
