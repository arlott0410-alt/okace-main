# RPC Refactor Inventory (STEP 1)

## All RPCs currently used by frontend

| # | RPC name | Called from | Classification |
|---|----------|-------------|----------------|
| 1 | `rpc_manager_dashboard_today` | `frontend/src/lib/dashboardTodayStaff.ts` | **A) KEEP** — (1) Manager/Supervisor Dashboard Today |
| 2 | `cancel_scheduled_shift_change` | `frontend/src/lib/transfers.ts` | **B) REMOVE** — replace with direct update or API |
| 3 | `update_scheduled_shift_change` | `frontend/src/lib/transfers.ts` | **B) REMOVE** — replace with direct update or API |
| 4 | `get_meal_slots_unified` | `frontend/src/lib/mealBreak.ts` | **B) REMOVE** — replace with API that calls DB server-side |
| 5 | `book_meal_break` | `frontend/src/lib/mealBreak.ts` | **B) REMOVE** — replace with API or direct insert |
| 6 | `cancel_meal_break` | `frontend/src/lib/mealBreak.ts` | **B) REMOVE** — replace with API or direct update |
| 7 | `apply_bulk_assignment` | `frontend/src/lib/bulkShiftAssignment.ts` | **B) REMOVE** — replace with API that calls DB server-side |
| 8 | `apply_paired_swap` | `frontend/src/lib/bulkShiftAssignment.ts` | **B) REMOVE** — replace with API that calls DB server-side |
| 9 | `set_primary_website` | `frontend/src/lib/websites.ts` | **B) REMOVE** — replace with direct updates |
| 10 | `get_email_for_login` | `frontend/src/pages/Login.tsx` | **B) REMOVE** — replace with API (anon cannot query profiles safely) |

## Final state: RPC allowed ONLY in 3 places

1. **Dashboard Today** — `rpc_manager_dashboard_today` (already exists), called from `dashboardTodayStaff.ts` (used by Dashboard.tsx).
2. **DutyBoard** — `rpc_dutyboard(p_date, scope)` (to add), called only from DutyBoard page or a single DutyBoard data module.
3. **HolidayGrid** — `rpc_holiday_grid(month_start, month_end, scope)` (to add), called only from HolidayGrid page or a single HolidayGrid data module.

## SQL functions (DB) — not dropped

- `get_email_for_login`, `set_primary_website`, `get_meal_slots_unified`, `book_meal_break`, `cancel_meal_break`, `apply_bulk_assignment`, `apply_paired_swap`, `cancel_scheduled_shift_change`, `update_scheduled_shift_change` remain in DB. Frontend will no longer call them via `supabase.rpc()`. Where needed, Cloudflare Pages Functions (server-side) will call them via service role.

---

## STEP 7 — Verification checklist (post-refactor)

### 1) RPC count — frontend uses exactly 3 RPCs

| RPC | File |
|-----|------|
| `rpc_manager_dashboard_today` | `frontend/src/lib/dashboardTodayStaff.ts` |
| `rpc_dutyboard` | `frontend/src/pages/DutyBoard.tsx` |
| `rpc_holiday_grid` | `frontend/src/pages/HolidayGrid.tsx` |

**Grep result:** `supabase.rpc(` appears only in these 3 files.

### 2) Files changed in this refactor

- **Frontend:** `Login.tsx`, `websites.ts`, `transfers.ts`, `mealBreak.ts`, `bulkShiftAssignment.ts`, `DutyBoard.tsx`, `HolidayGrid.tsx`, `dashboardTodayStaff.ts` (no change to last — already used RPC).
- **Pages Functions (new):** `frontend/functions/api/auth/resolve-email.ts`, `frontend/functions/api/meal/proxy.ts`, `frontend/functions/api/shifts/proxy.ts`.
- **Migrations:** `supabase/sql/migrations/20_performance_indexes_and_rpcs.sql` (existing), `supabase/sql/migrations/21_rpc_dutyboard_holiday_grid_only.sql` (new: rpc_dutyboard, rpc_holiday_grid, idx_holidays_user_id_holiday_date).
- **Docs:** `docs/RPC_REFACTOR_INVENTORY.md`.

### 3) TypeScript build

- No local Node/npm per project rules; static validation only. Linter: no errors on `HolidayGrid.tsx`, `DutyBoard.tsx`. Imports and types are consistent.

### 4) No behavior change

- **Dashboard Today:** Still uses `rpc_manager_dashboard_today`; same scope and columns.
- **DutyBoard:** Single `rpc_dutyboard` returns duty_roles, assignments, staff (with effective branch/shift), leave_user_ids, roster_status, websites; UI logic unchanged.
- **HolidayGrid:** Single `rpc_holiday_grid` returns staff + holidays in month; filters (branch, only-my-data) applied in RPC; realtime and mutate refetches still use direct `from('holidays').select(...)`.

### 5) Before/after request counts (per full load)

| Screen | Before | After |
|--------|--------|-------|
| DutyBoard load | Multiple: duty_roles, profiles, assignments, holidays, getEffectiveForStaffInMonth, getRosterStatus, websites | **1** (`rpc_dutyboard`) |
| HolidayGrid month load | profiles + website_assignments (primaries) + holidays (3+ queries) | **1** (`rpc_holiday_grid`) + leave_types, quota_tiers, meal_settings, websites, booking_config (unchanged, small) |
| Manager Dashboard Today | Already 1 (`rpc_manager_dashboard_today`) | **1** (unchanged) |
