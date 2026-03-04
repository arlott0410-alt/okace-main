/**
 * Today's Staff from Holiday Grid — สำหรับแดชบอร์ด Supervisor/Manager/Admin
 * Present = ไม่มีแถว holidays วันนี้, Leave = มีแถว holidays (approved/pending). ไม่ใช้ attendance.
 * Single RPC call: rpc_manager_dashboard_today (scope optional) to reduce network and avoid second call for effective branch/shift.
 */

import { supabase } from './supabase';

export interface MealSlot {
  start: string;
  end: string | null;
}

export interface DashboardTodayStaffRow {
  staff_id: string;
  name: string | null;
  staff_code: string;
  role: string;
  default_branch_id?: string | null;
  default_shift_id?: string | null;
  shift_name: string | null;
  status: 'PRESENT' | 'LEAVE';
  leave_type: string | null;
  leave_reason: string | null;
  meal_slots: MealSlot[] | null;
  meal_start_time: string | null;
  meal_end_time: string | null;
}

/** วันนี้ YYYY-MM-DD ตาม Asia/Bangkok (single source of truth) */
export function getTodayBangkok(): string {
  return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Bangkok' });
}

/**
 * ดึงข้อมูลพนักงานวันนี้จาก RPC (1 call) — รองรับ scope แผนก/กะ ไม่ต้องโหลด effective แยก
 */
export async function fetchDashboardTodayStaff(opts?: {
  scope_branch_id?: string | null;
  scope_shift_id?: string | null;
}): Promise<DashboardTodayStaffRow[]> {
  const today = getTodayBangkok();
  const scopeBranch = opts?.scope_branch_id && opts.scope_branch_id.trim() !== '' ? opts.scope_branch_id : null;
  const scopeShift = opts?.scope_shift_id && opts.scope_shift_id.trim() !== '' ? opts.scope_shift_id : null;
  const { data, error } = await supabase.rpc('rpc_manager_dashboard_today', {
    p_today: today,
    p_scope_branch_id: scopeBranch,
    p_scope_shift_id: scopeShift,
  });
  if (error) throw new Error(error.message || 'Failed to load today staff');
  const rows = (data || []) as DashboardTodayStaffRow[];
  return rows;
}
