# การตรวจสอบ Edge Cache (KV สำหรับ branches/shifts)

## 1) จุดที่ตรวจแล้ว — ไม่กระทบ workflow อื่น

### 1.1 ผู้ใช้ Context (useBranchesShifts)
ทุกจุดที่ใช้ `branches` / `shifts` / `refetch` ได้รับข้อมูลจาก Context เหมือนเดิม (shape เป็น `Branch[]` / `Shift[]`) ไม่มีการยิง Supabase ตรงสำหรับรายการสาขา/กะจากหน้าหลัก — มีแค่ใน Context เอง

| หน้า/โมดูล | การใช้ | ผลกระทบ |
|------------|--------|----------|
| Dashboard | branches, shifts | อ่านจาก Context — ไม่กระทบ |
| Settings | shifts, refetchBranchesShifts | หลังแก้กะเรียก refetch (มี ?refresh=1); หลังแก้สาขาเรียก refetchBranchesShifts แล้ว — อัป Context + KV |
| DutyBoard, HolidayGrid, MassShiftAssignment, Meal, TransferHistory, Timekeeping, Breaks, ShiftSwap, History, GroupLinks, PhotoVault, ScheduleCards, MemberManagement, ThirdPartyProviders | branches และ/หรือ shifts | อ่านจาก Context — ไม่กระทบ |
| BulkMoveTopBar (ผ่าน MassShiftAssignment) | shifts | อ่านจาก Context — ไม่กระทบ |
| resolveShift.ts | ใช้ shifts จาก context (ผ่าน caller) | ไม่กระทบ |

### 1.2 โหลด branches/shifts แยกจาก Context (ไม่ผ่าน edge cache)
- **Settings.tsx** — `loadBranches()` โหลด branches ทั้งหมด (รวม inactive) สำหรับตารางในหน้าการตั้งค่า เป็น state แยก ไม่ใช้จาก Context สำหรับตารางนี้ — **ไม่กระทบ**
- **ManagedWebsites.tsx** — โหลด branches/shifts ตรงจาก Supabase สำหรับ dropdown ในหน้านั้น — **ไม่เกี่ยวกับ Context ไม่กระทบ**
- **shiftSwapRounds.ts** — ใช้ `supabase.from('shifts')` โดยตรงสำหรับ logic ภายใน — **ไม่กระทบ**

### 1.3 Auth และ Layout
- **BranchesShiftsProvider** อยู่ภายใน **Layout** ซึ่งอยู่ใน **ProtectedRoute** — โหลด branches/shifts หลังล็อกอินแล้ว จึงมี session และส่ง `Authorization: Bearer <token>` ไปที่ edge API ได้ — **ไม่กระทบ**
- ถ้า edge API คืน 401 หรือ error → fallback ไปดึงตรงจาก Supabase + client cache — **ไม่พัง**

### 1.4 Middleware
- `/api/*` ได้รับ `Cache-Control: no-store` อยู่แล้ว — **ไม่กระทบ**
- การเข้า `/api/cache/branches` และ `/api/cache/shifts` จากมือถือขึ้นกับ allow_mobile_access เหมือน API อื่น — **ไม่กระทบ**

### 1.5 RLS
- Edge API ส่งต่อ JWT ไปที่ Supabase ดังนั้น RLS ยังใช้กับ request ที่ดึงจาก Supabase — **ไม่กระทบ**

---

## 2) การแก้เพิ่มเติมที่ทำในรอบนี้
- **Settings: saveBranch()** — เรียก `refetchBranchesShifts()` หลังบันทึกสาขา เพื่อให้ Context และ edge cache อัปเดตทัน (สอดคล้องกับ saveShiftTimes ที่มี refetch อยู่แล้ว)

---

## 3) ข้อดี / ข้อเสีย หลังทำ Edge Cache

### ข้อดี
- **ลดการยิง Supabase** — รายการสาขา/กะ (active) ถูก cache ที่ edge 5 นาที หลายคนใช้ค่า cache ชุดเดียวกัน → จำนวน request ไป Supabase ลดลง
- **โหลดแอปเร็วขึ้นได้** — เมื่อ cache ถูกที่ edge การโหลด dashboard/หน้าอื่นที่พึ่ง branches/shifts จะได้จาก edge แทนการรอ Supabase (โดยเฉพาะผู้ใช้ที่อยู่ใกล้ edge)
- **ไม่บังคับใช้ KV** — ถ้าไม่ผูก OKACE_KV ระบบดึงตรงจาก Supabase + client cache เหมือนเดิม
- **หลังแอดมินแก้สาขา/กะ** — เรียก refetch (ใช้ ?refresh=1) ได้ข้อมูลล่าสุดและอัป KV

### ข้อเสีย
- **ความล้าของข้อมูล (staleness)** — ถ้าไม่มีใคร refetch และแอดมินเพิ่งแก้สาขา/กะ ผู้ใช้รายอื่นอาจเห็นของเก่าถึง 5 นาที (TTL edge)
- **ความซับซ้อน** — มี API เพิ่ม 2 ตัว และ logic ใน Context ที่ต้อง fallback

---

## 4) โหลดไวขึ้นไหม / เบาขึ้นไหม

### โหลดไวขึ้นไหม
- **ได้เมื่อมี KV และ cache hit** — request ไป `/api/cache/branches` และ `/api/cache/shifts` ได้ response จาก edge (KV) โดยไม่ต้องรอ Supabase → ลด latency สำหรับการโหลดรายการสาขา/กะ
- **ครั้งแรกหรือ cache miss** — ความเร็วใกล้เคียงเดิม (อาจมี overhead เล็กน้อยจากการเรียก API แทน Supabase ตรง)
- **ไม่มี KV** — ใช้ fallback ตรง Supabase + client cache ความเร็วเท่าเดิม

### เบาขึ้นไหม (ภาระระบบ)
- **Supabase เบาลง** — การอ่าน branches/shifts (active) จากหลายผู้ใช้ถูกตอบจาก edge cache แทนการยิง Supabase ซ้ำ → **จำนวน read ไป Supabase ลดลงชัดเจน** เมื่อมี traffic
- **Cloudflare** — มีการอ่าน/เขียน KV เพิ่ม (cache:branches, cache:shifts) ตามการใช้งาน ภายในแผนที่มี KV อยู่แล้ว

---

## 5) สรุป
- ตรวจทุกจุดที่ใช้ branches/shifts และ refetch แล้ว **ไม่มี workflow อื่นเสีย**
- หลังทำ edge cache: **ข้อดี** คือลดภาระ Supabase และโหลดเร็วขึ้นได้เมื่อ cache hit; **ข้อเสีย** คือความล้าของข้อมูลได้ถึง TTL และความซับซ้อนเพิ่ม
- **โหลดไวขึ้น** ได้เมื่อมี KV และ cache hit; **ระบบเบาขึ้น** ที่ Supabase เพราะ read ซ้ำลดลง
