# OKACE – Performance & Bugfix Summary

## Phase 0: Hotspots and Bug Risks (Identified)

### Top 10 performance hotspots
1. **DutyBoard**: Fetched all profiles (instructor+staff) with `select('*')` on every branch/shift change; no branch filter.
2. **TransferHistory / CrossBranchTransfer**: N+1 — 5 `single()` per transfer (branches×2, shifts×2, profiles×1).
3. **HolidayGrid**: Many useEffects and parallel Supabase calls on mount.
4. **Settings**: Many Supabase calls; branches duplicated with context.
5. **BranchesShiftsContext**: No cache; refetched on every provider mount.
6. **DutyBoard**: duty_roles + staff + assignments fetched separately; realtime refetches full list.
7. **Breaks**: Multiple useEffects and history filters.
8. **ManagedWebsites**: Multiple useEffects.
9. **Search inputs**: No debounce → filter on every keystroke (ScheduleCards, PhotoVault, GroupLinks, MemberManagement).
10. **duty_assignments / duty_roles**: No indexes on (branch_id, shift_id, assignment_date) and (branch_id, sort_order).

### Top 10 bug risks
1. **setState on unmounted**: No cancelled flag in useEffect fetches.
2. **Race**: Slow async in TransferHistory could overwrite newer filter selection.
3. **CrossBranchTransfer**: loadList not in deps; list filtered client-side (by design).
4. **Realtime closure**: HolidayGrid realtime depends on start/end; deps kept in sync.
5. **DutyBoard staff**: Fetched without branch filter (intentional for dropdown).
6. **Null from .single()**: Some UI assumed .data exists; enrich now uses context + batch.
7. **TransferHistory realtime**: Full refetch + N+1 in callback; fixed with enrichTransfersWithMeta.
8. **Confirm then async**: User could navigate away; cancelled flag reduces setState after unmount.
9. **RLS / errors**: Some pages used alert(); now use toast for errors.
10. **Missing deps**: loadList wrapped in useCallback with correct deps; realtime subscribes with stable callback.

---

## Before vs After

| Area | Before | After |
|------|--------|--------|
| **Transfer history / CrossBranch transfer** | 5×N Supabase calls (N = number of transfers) | 1 list query + 1 batch profile query; branches/shifts from context |
| **Unmounted setState** | Possible in ScheduleCards, DutyBoard, TransferHistory, CrossBranchTransfer | Cancelled flag in key useEffects; BranchesShiftsContext uses mounted ref |
| **Error feedback** | alert() on CrossBranchTransfer errors | toast.show(..., 'error') |
| **Search** | Every keystroke triggered filter recalc | 300 ms debounce on ScheduleCards, PhotoVault, GroupLinks, MemberManagement |
| **Branches/shifts load** | No cache; refetch on every mount | withCache on initial load (60s TTL); refetch invalidates and loads fresh |
| **DutyBoard staff** | select('*') on profiles | select('id, display_name, email, role, default_branch_id, default_shift_id, active') |
| **Realtime + list** | TransferHistory realtime did full N+1 again | Realtime calls loadList() which uses enrichTransfersWithMeta (batch) |
| **DB indexes** | None on duty_assignments / duty_roles for main filters | 029_duty_indexes: idx_duty_assignments_branch_shift_date, idx_duty_roles_branch_sort, idx_website_assignments_user_website |

---

## Files changed

| File | Change |
|------|--------|
| `frontend/src/lib/queryCache.ts` | **New**. In-memory cache with TTL, dedupe in-flight, invalidate(table). |
| `frontend/src/lib/useDebouncedValue.ts` | **New**. useDebouncedValue(value, delayMs). |
| `frontend/src/lib/transfers.ts` | Added enrichTransfersWithMeta(); listTransfers return type explicit; TransferWithMeta type. |
| `frontend/src/lib/BranchesShiftsContext.tsx` | Initial load via withCache; refetch invalidates + direct fetch; mounted ref to avoid setState after unmount. |
| `frontend/src/pages/TransferHistory.tsx` | loadList with listTransfers + enrichTransfersWithMeta; useCallback; cancelled flag; toast on error; realtime uses loadList. |
| `frontend/src/pages/CrossBranchTransfer.tsx` | loadList with enrichTransfersWithMeta; useCallback; cancelled flag; toast instead of alert; TransferWithMeta type. |
| `frontend/src/pages/ScheduleCards.tsx` | Cancelled flag in cards useEffect; useDebouncedValue(search, 300) for filteredCards. |
| `frontend/src/pages/DutyBoard.tsx` | Cancelled flags in duty_roles, staff, assignments, roster status useEffects; profiles select only needed columns. |
| `frontend/src/pages/PhotoVault.tsx` | useDebouncedValue(search, 300) for filteredFiles. |
| `frontend/src/pages/GroupLinks.tsx` | useDebouncedValue(searchQuery, 300) for filteredLinks. |
| `frontend/src/pages/MemberManagement.tsx` | useDebouncedValue(search, 300); filteredMembers in useMemo with debouncedSearch. |
| `supabase/sql/migrations/029_duty_indexes.sql` | **New**. Indexes for duty_assignments, duty_roles, website_assignments. |

---

## Testing checklist (non-dev)

1. **ตารางงาน (ScheduleCards)**  
   - เปิดหน้า → ตรวจว่าโหลดการ์ดได้โดยไม่ต้องเลือกสาขาก่อน.  
   - เลือกหลายสาขาในตัวกรอง → แสดงเฉพาะการ์ดของสาขาที่เลือก.  
   - พิมพ์ในช่องค้นหา → รายการกรองหลังหยุดพิมพ์ ~0.3 วินาที (ไม่กระพริบทุกตัวอักษร).  

2. **ย้ายกะข้ามสาขา (CrossBranchTransfer)**  
   - เปิดหน้า → ตรวจว่ารายการโหลดและแสดงชื่อสาขา/กะ/ผู้ใช้ (ไม่ใช่ UID).  
   - ส่งคำขอ / อนุมัติ / ปฏิเสธ → ข้อความแจ้ง error ผ่าน toast ไม่ใช่ alert.  

3. **ประวัติการย้ายกะข้ามสาขา (TransferHistory)**  
   - เปิดหน้า → รายการโหลด; คอลัมน์แสดงชื่อสาขา/กะ/ผู้ใช้.  
   - เปลี่ยนเดือน/สาขา/สถานะ → รายการอัปเดต.  

4. **จัดหน้าที่ (DutyBoard)**  
   - เปลี่ยนสาขา/กะ/วันที่ → หน้าที่และผู้เข้ากะโหลดถูกต้อง; ไม่มี loading ค้างหลังสลับหน้ามาอื่น.  

5. **คลังเก็บไฟล์ / กลุ่มงาน / จัดการสมาชิก**  
   - ช่องค้นหา: พิมพ์แล้วรอสักครู่ → รายการกรองตามคำค้น (debounce).  

6. **Deploy**  
   - Push ขึ้น GitHub → ใช้ Cloudflare Pages build ตามปกติ; ไม่ต้องรัน node/wrangler local.  

---

## SQL migration (029)

**File:** `supabase/sql/migrations/029_duty_indexes.sql`

**How to run:**  
Supabase Dashboard → SQL Editor → New query → วางเนื้อหาไฟล์ → Run.

**Contents:**  
- `idx_duty_assignments_branch_shift_date` on `duty_assignments(branch_id, shift_id, assignment_date)`  
- `idx_duty_roles_branch_sort` on `duty_roles(branch_id, sort_order)`  
- `idx_website_assignments_user_website` on `website_assignments(user_id, website_id)`  

---

## Static verification

- TypeScript: compiles.  
- Lint: no new errors on changed files.  
- No change to product flow except: error UX (alert → toast), and performance (cache, debounce, batch, indexes).  
- No new frameworks; no requirement to run node/wrangler locally; deploy via GitHub → Cloudflare only.
