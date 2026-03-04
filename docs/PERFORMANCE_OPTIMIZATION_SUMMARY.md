# Performance Optimization Summary

## List of files changed

### Cloudflare Pages Functions
- `frontend/functions/api/admin/create-user.ts` — Idempotency (X-Idempotency-Key or hash of body); in-request cache for duplicate prevention.
- `frontend/functions/api/admin/create-users.ts` — Batch duplicate check (one Supabase query for all usernames/emails); max 50 per request; response shape: `created`, `skipped_duplicates`, `failed` (with `reason`).
- `frontend/functions/api/admin/reset-password.ts` — Documented X-Idempotency-Key support (no logic change).

### Frontend
- `frontend/src/lib/adminApi.ts` — X-Idempotency-Key header on create-user, create-users, reset-password; `CreateUsersResult` type: added `skipped_duplicates`, `failed[].reason`.
- `frontend/src/pages/MemberManagement.tsx` — Submit disabled while in-flight (bulk + reset password); cap 50 users with message; display `skipped_duplicates` and `failed[].reason`.
- `frontend/src/lib/dashboardTodayStaff.ts` — Switched to RPC `rpc_manager_dashboard_today` with optional `scope_branch_id` / `scope_shift_id`; added `getTodayBangkok()`.
- `frontend/src/pages/Dashboard.tsx` — Single RPC call for “Today” section with scope; removed second call to `getEffectiveForStaffInMonth`.
- `frontend/src/lib/BranchesShiftsContext.tsx` — Cache TTL for branches/shifts set to 10 minutes.

### Supabase
- `supabase/sql/migrations/20_performance_indexes_and_rpcs.sql` — New migration (indexes + helper + RPC).
- `supabase/sql/verify_rpc_manager_dashboard_today.sql` — Minimal verification script for RPC.

---

## New migration SQL (20_performance_indexes_and_rpcs.sql)

### Indexes
- **holidays**: `idx_holidays_holiday_date_user_id` on `(holiday_date, user_id)`.
- **break_logs**: `idx_break_logs_break_date_user_id` on `(break_date, user_id)`.
- **profiles**: `idx_profiles_default_branch_id`, `idx_profiles_role`.
- **cross_branch_transfers**: `idx_cross_branch_transfers_created_at`, `idx_cross_branch_transfers_from_branch_created`, `idx_cross_branch_transfers_to_branch_created`.
- **shift_swaps**: `idx_shift_swaps_created_at`, `idx_shift_swaps_branch_created`.

### RPC definitions (in same migration)

1. **get_effective_branch_shift_for_date(p_user_id, p_date, p_fallback_branch, p_fallback_shift)**  
   Returns `(branch_id, shift_id)` for a user on a date from approved `shift_swaps` / `cross_branch_transfers`, else fallback.

2. **rpc_manager_dashboard_today(p_today, p_scope_branch_id, p_scope_shift_id)**  
   Returns table: `staff_id`, `name`, `staff_code`, `role`, `shift_name`, `status` (PRESENT/LEAVE), `leave_type`, `leave_reason`, `meal_slots`, `meal_start_time`, `meal_end_time`.  
   - `p_today` defaults to `(now() AT TIME ZONE 'Asia/Bangkok')::date`.  
   - Optional scope: when `p_scope_branch_id` / `p_scope_shift_id` are set, only staff whose **effective** branch/shift for that date match are returned.  
   - Single source of truth for “today” = Asia/Bangkok; no new ABSENT concept (not-in-holidays = PRESENT).

---

## Before/after: pages that went from N calls → 1 call

| Page / section              | Before                                                                 | After                                                                 |
|-----------------------------|------------------------------------------------------------------------|-----------------------------------------------------------------------|
| **Manager Dashboard “Today”** | 2: `dashboard_today_staff` view + `getEffectiveForStaffInMonth(ids, today, today, …)` | 1: `rpc_manager_dashboard_today(today, scope_branch_id, scope_shift_id)` |
| **DutyBoard**               | Unchanged (multiple queries: duty_roles, profiles, assignments, holidays, effective, roster, websites). Optional future: single RPC returning JSON. | —                                                                     |
| **HolidayGrid**             | Unchanged (profiles, holidays, website_assignments, booking_config, quota_tiers, leave_types, shift changes, effective). Optional future: single RPC. | —                                                                     |

---

## Realtime changes

- **No realtime logic was removed.**  
- **DutyBoard**: Still subscribes to `duty_assignments` (all events); on event it refetches with current `branch_id`, `shift_id`, `assignment_date`. To reduce load you could narrow the channel filter (e.g. by `branch_id`/`shift_id`/`assignment_date`) when the Supabase Realtime API supports it for `postgres_changes`.  
- **Dashboard**: Realtime for `shift_swaps` and `cross_branch_transfers` (scheduled changes) unchanged.  
- **HolidayGrid**: Realtime for `holidays` and for shift changes unchanged.  
- Optimistic UI was not added; refetches still occur after mutations.

---

## Verification

1. **Fewer network calls**  
   - Dashboard “Today”: one RPC instead of view + effective call.  
   - Bulk create-users: one batch duplicate check instead of N `isUsernameOrEmailTaken` calls.

2. **Same visible results**  
   - Today overview: still Name | Shift | Status (PRESENT/LEAVE) | Leave type/reason | Meal time; scope by branch/shift is applied in DB.  
   - Bulk create: same created/skipped/failed semantics; `skipped_duplicates` separated from `failed`.

3. **SQL verification**  
   - Run `supabase/sql/verify_rpc_manager_dashboard_today.sql` in Supabase SQL Editor after applying migration 20.

4. **TypeScript / lint**  
   - No npm/wrangler run required (GitHub → Cloudflare deploy).  
   - Static check: no lint/type errors on modified frontend files.

---

## Notes

- **rpc_dutyboard** and **rpc_holiday_grid** were not implemented; migration 20 only adds indexes and `rpc_manager_dashboard_today` (and helper). They can be added later as single-call RPCs returning JSON if desired.
- Single source of truth for “today”: Asia/Bangkok in RPC default and in `getTodayBangkok()` in `dashboardTodayStaff.ts`.
- Idempotency in Functions uses in-request cache (no KV); frontend sends X-Idempotency-Key and disables submit while in-flight to avoid duplicate submissions.
