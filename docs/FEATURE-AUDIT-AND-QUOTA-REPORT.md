# รายงานตรวจสอบฟีเจอร์ระบบ OKACE + โควต้าและแนวทางจัดการ

อัปเดต: มี.ค. 2025 — จากการตรวจสอบ codebase ตามรายการตรวจสอบฟีเจอร์และโครงสร้าง routes/API

---

## 1. สรุปฟีเจอร์ตามบทบาท (เทียบกับรายการตรวจสอบ)

| ฟีเจอร์ | Path | บทบาท | สถานะ |
|--------|------|--------|--------|
| ล็อกอิน / ออกจากระบบ | `/login` | ทุกคน | มี route, Layout + sidebar หลังล็อกอิน |
| โปรไฟล์โหลดหลังล็อกอิน | Auth + Header | ทุกคน | โหลดชื่อ, role, แผนก/กะ — **ควรเพิ่ม error handling** (ดูหัวข้อ Bug) |
| แดชบอร์ด | `/dashboard` | ทุกคน | นาฬิกา+วันที่, หน้าที่วันนี้/เว็บที่ดูแล/ย้ายกะที่ค้าง, คนมาทำงานวันนี้ (หัวหน้า/แอดมิน), เมนูลัด — **shortcuts โหลดไม่มี .catch** |
| บัญชีของฉัน | `/บัญชีของฉัน` | ทุกคน | มี route |
| จัดการสมาชิก | `/จัดการสมาชิก` | admin, manager, instructor_head | มี route, แก้ไข/สร้าง bulk/รีเซ็ตรหัส — **กรองตามเว็บมีโอกาส loading ค้าง** |
| จองพักอาหาร | `/จองพักอาหาร` | instructor, staff, manager, instructor_head | มี route — **โหลด profile ไม่มี .catch** |
| ตารางวันหยุด | `/ตารางวันหยุด` | ทุกคน | RPC grid + CRUD, อนุมัติ/ปฏิเสธ — **RPC error ไม่แสดงข้อความ** |
| ตารางงาน | `/ตารางงาน` | ทุกคน | Schedule cards — **โหลด websites/schedule_cards ไม่มี .catch** |
| ย้ายกะจำนวนมาก | `/ย้ายกะจำนวนมาก` | admin, manager, instructor_head | มี route — **โหลด employees ไม่มี error/loading** |
| จัดหน้าที่ | `/จัดหน้าที่` | ทุกคน | RPC dutyboard — **RPC ไม่มี .catch → loading ค้างได้** |
| เว็บที่ดูแล | `/เว็บที่ดูแล` | admin, manager, instructor_head | มี route |
| เว็บที่ฉันดูแล | `/เว็บที่ฉันดูแล` | instructor, staff | มี route |
| ประวัติ | `/ประวัติ` | ทุกคน | Audit + shift/transfer history — redirect `/ประวัติย้ายกะ` → `/ประวัติ` |
| ตั้งค่า | `/ตั้งค่า` | admin, manager | มี route — **โหลดตั้งค่าเริ่มต้นไม่มี .catch** |
| ลงเวลา (Timekeeping) | — | — | **ไม่มี route** — หน้า Timekeeping.tsx มีแต่ไม่ได้ผูก path (ตามนโยบายเอาเมนูลงเวลาออกแล้ว) |

---

## 2. Bugs ที่พบ (และผลกระทบ)

### 2.1 ร้ายแรง (กระทบ UX / ค้างหน้า)

| ตำแหน่ง | ปัญหา | ผลกระทบ |
|---------|--------|---------|
| **DutyBoard.tsx** — `refetchDutyBoard` | `supabase.rpc('rpc_dutyboard', ...).then(...)` ไม่มี `.catch` | ถ้า RPC ล้ม (เครือข่าย/DB) Promise reject → `setLoading(false)` ไม่ถูกเรียก → **หน้าโหลดค้าง** และไม่มีข้อความ error |
| **Dashboard.tsx** — `loadShortcuts` | `supabase.from('dashboard_shortcuts').select(...).then(...)` ไม่มี `.catch` / loading / error state | ล้มแล้ว shortcuts ว่าง ไม่มี feedback |
| **HolidayGrid.tsx** — RPC | `rpc_holiday_grid` เมื่อ error แค่ clear data ไม่มีข้อความแจ้งผู้ใช้ | ผู้ใช้ไม่รู้ว่าโหลดไม่สำเร็จ |
| **Settings.tsx** — โหลดเริ่มต้น | หลาย `.from(...).then(({ data }) => set...)` ใน useEffect ไม่มี `.catch` | โหลดไม่ครบหรือล้มบางส่วน → ตั้งค่าแสดงไม่ครบ/ไม่ชัด |
| **MassShiftAssignment** — โหลด employees | `.from('profiles').select(...).then(...)` ไม่มี `.catch` / loading | ล้มแล้วรายชื่อว่าง ไม่มีข้อความแจ้ง |
| **ScheduleCards** | โหลด websites + schedule_cards ไม่มี `.catch` | ล้มแล้วข้อมูลไม่โหลด ไม่มี feedback |
| **Meal.tsx** | โหลด profile (onDutyUserIds / allBookedUserIds) ไม่มี `.catch` | ล้มแล้วอาจแสดงจำนวน/รายชื่อผิด |
| **Auth (lib/auth.tsx)** | `getSession()` / `fetchProfile()` ไม่มี `.catch` | โปรไฟล์โหลดไม่สำเร็จ → profile เป็น null โดยไม่มี retry/ข้อความ |

### 2.2 ปานกลาง

| ตำแหน่ง | ปัญหา |
|---------|--------|
| **MemberManagement** — filter ตามเว็บ | เมื่อ `filterWebsiteId` มีค่าแต่ `userIdsByWebsite[filterWebsiteId]` ยังไม่โหลด หรือ request ล้ม → state ไม่สอดคล้อง อาจ loading ค้างหรือแสดงผิด |
| **Timekeeping** | หน้าไม่มี route = dead code (ไม่กระทบการใช้งาน แต่อาจสับสนถ้ามีลิงก์ไป) |

---

## 3. โควต้า Cloudflare + Supabase ที่เปลือง

### 3.1 Supabase

| รูปแบบ | ตำแหน่ง / ฟังก์ชัน | ปัญหา |
|--------|---------------------|--------|
| **ดึงรายการเต็มไม่มี limit** | `listAllAssignmentsForAdmin()` — `website_assignments` + join websites, branches, profiles | ทุกครั้งเปิด tab "จัดการผู้ดูแล" ดึง assignment ทั้งหมด → ข้อมูลเยอะ = read สูง |
| | `listStaffForAssignments()` — profiles ทั้งหมด role instructor/staff/instructor_head | ใช้ใน ManagedWebsites (และที่อื่น) ไม่มี limit → โตตามจำนวนคน |
| | **MassShiftAssignment** — โหลด profiles ทั้งหมดใน `.in('role', [...])` | หนึ่ง query ใหญ่ต่อการเปิดหน้า |
| **โหลดซ้ำโดยไม่แคช** | **Settings**, **HolidayGrid**, **ManagedWebsites** | โหลดใหม่ทุกครั้งที่เข้า/สลับ tab — ไม่ใช้ `queryCache` (มีแค่ branches/shifts ใช้ cache 10 นาที) |
| **RPC + query เพิ่มหลัง RPC** | **HolidayGrid** | หลัง RPC grid แล้วเมื่อ `staffList` เปลี่ยน (รวมจาก realtime) มี 2 useEffect แต่ละอันเรียก 2 query → รวม 4 query ต่อการอัปเดต staffList |
| **Realtime กว้าง** | `shift_swaps`, `cross_branch_transfers`, `holidays`, `break_logs`, `duty_assignments` | ทุก insert/update/delete ในตารางเหล่านี้ trigger refetch ในหลายหน้า → write เยอะ = realtime + refetch เยอะ |
| **History — shift history** | ดึงสูงสุด 500 แถวแล้ว filter ตามวันที่ใน memory + enrich ด้วย profile | ช่วงวันที่กว้างหรือ branch busy = หนึ่ง request หนัก |

### 3.2 Cloudflare Workers

| รูปแบบ | ตำแหน่ง | ปัญหา |
|--------|---------|--------|
| **Meal** | `/api/meal/proxy` — slots / book / cancel | ทุกการโหลด slot หรือกดจอง/ยกเลิก = 1 invocation; สลับ tab/refocus อาจ refetch บ่อย |
| **Shifts** | `/api/shifts/proxy` — apply/cancel ย้ายกะ | ตามการใช้งาน ไม่ได้เกินจำเป็น |
| **Auth** | verify-turnstile, resolve-email | ตามการล็อกอิน |
| **Admin** | create-user, create-users, reset-password | ตามการจัดการสมาชิก |

---

## 4. แนวทางจัดการแบบมืออาชีพ

### 4.1 Bug — ทำทันที

1. **ทุก Promise จาก Supabase/API** ที่อัปเดต state (loading/data): ใช้ `.catch()` และใน catch อย่างน้อย `setLoading(false)` และ `setError(ข้อความ)` (หรือ toast) เพื่อไม่ให้หน้าค้างและแจ้งผู้ใช้
2. **DutyBoard**: เพิ่ม `.catch` ใน `refetchDutyBoard` แล้วใน catch เรียก `setLoading(false)` และแสดง toast/ข้อความ error
3. **Dashboard shortcuts**: เพิ่ม error state + `.catch` ใน loadShortcuts และแสดงข้อความถ้าล้ม
4. **Settings / HolidayGrid / MassShiftAssignment / ScheduleCards / Meal / Auth**: เพิ่มการจัดการ error (และ loading ที่ขาด) ใน path โหลดข้อมูลหลัก

### 4.2 โควต้า Supabase

1. **จำกัดขนาดรายการ**
   - **listAllAssignmentsForAdmin**: เพิ่ม pagination หรือ `.limit(n)` + "โหลดเพิ่ม" หรือ filter ตาม branch/website เพื่อลดจำนวนแถวต่อครั้ง
   - **listStaffForAssignments**: ถ้าใช้แค่เลือกคน/แสดงชื่อ ไม่จำเป็นต้องดึงทั้งองค์กร — ใช้ `listStaffForAssignmentsPaginated` แทนและโหลดตามหน้าที่
   - **MassShiftAssignment**: พิจารณา pagination หรือ limit แรก (เช่น 200 คน) แล้วโหลดเพิ่มเมื่อเลื่อนหรือค้นหา

2. **แคช**
   - ใช้ `queryCache.withCache()` สำหรับข้อมูลที่เปลี่ยนไม่บ่อย: สร้าง key จาก table + filter (เช่น branch_id, month) ใส่ TTL สั้น (เช่น 1–2 นาที) สำหรับ Settings, HolidayGrid, ManagedWebsites (รายการเว็บ/สาขา)
   - หลัง mutation (สร้าง/แก้/ลบ) เรียก `invalidate(table)` หรือ `invalidatePrefix(prefix)` เพื่อไม่ให้ข้อมูลเก่าค้าง

3. **HolidayGrid — ลด query หลัง RPC**
   - รวม logic ใน `getScheduledShiftChangeDatesByUser` และ `getEffectiveForStaffInMonth` เป็น RPC เดียวหรือ batch ให้ backend คืนค่าพร้อม grid จะได้ไม่ต้องยิง 4 query ต่อการอัปเดต staffList
   - หรือ debounce การ refetch หลัง realtime (เช่น 2–3 วินาที) เพื่อรวมหลาย event เป็นครั้งเดียว

4. **Realtime**
   - ใช้ filter ตาม row ถ้า backendรองรับ (เช่น `eq('branch_id', branchId)`) เพื่อลดจำนวน event ที่ส่งถึง client
   - พิจารณาปิด realtime ในหน้าที่ไม่จำเป็นต้องเห็นทันที (เช่น History) หรือใช้ polling ช่วงสั้นแทน

5. **History — shift**
   - ดึงตามช่วงวันที่ที่ server (limit + filter วันที่ที่ DB) แทนการดึง 500 แถวแล้ว filter ใน memory
   - ถ้ามี RPC สำหรับประวัติย้ายกะ ให้รับ `date_from`, `date_to` แล้วคืนเฉพาะช่วงนั้น

### 4.3 โควต้า Cloudflare Workers

1. **Meal**
   - แคชผลลัพธ์ slot ในฝั่ง Worker (หรือ Supabase) ด้วย TTL สั้น (เช่น 30–60 วินาที) เพื่อลดการยิง DB ซ้ำเมื่อ refocus/สลับ tab
   - ฝั่ง frontend: debounce การ refetch slot เมื่อกลับมา focus หรือลดความถี่ถ้าไม่จำเป็นต้อง realtime ทุกวินาที

2. **ทั่วไป**
   - ใช้ Cache API ใน Worker สำหรับ response ที่ไม่เปลี่ยนบ่อย (ตามนโยบายแอป)
   - จำกัดขนาด request/response และใช้ compression ถ้าส่ง payload ใหญ่

### 4.4 สิ่งที่มีอยู่แล้วและควรคงไว้

- **BranchesShiftsContext** ใช้ `queryCache` TTL 10 นาที สำหรับ branches/shifts — ลดการโหลดซ้ำข้าม route
- **MemberManagement** ใช้ pagination สำหรับ `fetchMembers`
- **History (audit)** ใช้ cursor pagination (PAGE_SIZE 50)
- **listStaffForAssignmentsPaginated** มี limit/offset และ filter — ควรใช้แทน listStaffForAssignments ในจุดที่เหมาะ

---

## 5. Verification (Static)

- ตรวจจาก codebase เท่านั้น ไม่รัน local
- โครงสร้าง route ตรงกับ `App.tsx`; ฟีเจอร์หลัก (ล็อกอิน, แดชบอร์ด, จองพักอาหาร, ตารางวันหยุด, จัดหน้าที่, ประวัติ, ตั้งค่า ฯลฯ) มีครบตาม role
- การแก้ที่แนะนำเป็นแบบไม่ breaking: เพิ่ม error/loading และ limit/pagination/cache โดยไม่ลบ column/table หรือเปลี่ยน RLS/role เดิม

---

## 6. สิ่งที่ implement แล้ว (ประหยัดโควต้า)

- **websites.ts**: `listAllAssignmentsForAdmin()` ใช้ `withCache` TTL 1 นาที + `.limit(2000)`; `listStaffForAssignments()` ใช้ `withCache` TTL 2 นาที
- **ManagedWebsites**: หลัง mutate (มอบหมาย/เอาออก/ตั้งหลัก) เรียก `invalidate('website_assignments')` แล้ว `refetchAssignments()` เพื่อให้ cache ไม่ค้าง
- **mealBreak.ts**: `fetchMealSlots(workDate)` ใช้ `withCache('meal_slots', { work_date }, ...)` TTL 45 วินาที
- **Meal.tsx**: หลังจอง/ยกเลิกสำเร็จ เรียก `invalidate('meal_slots')` แล้วโหลด slot ใหม่
- **MassShiftAssignment**: โหลด employees ผ่าน `withCache('profiles', { list: 'mass_shift_employees' }, ...)` TTL 2 นาที
- **HolidayGrid**: debounce realtime จาก 400ms เป็น 700ms เพื่อลดจำนวนครั้งที่ยิง 4 query หลังอัปเดต staffList
- **Settings**: โหลด holiday_booking_config, holiday_quota_tiers, meal_quota_rules, leave_types ผ่าน `withCache` TTL 2 นาที; หลัง save/delete แต่ละตาราง เรียก `invalidate(ตาราง)` แล้ว refetch

---

*รายงานนี้ใช้เป็น checklist แก้ bug และลดโควต้าได้ตามลำดับความสำคัญ*
