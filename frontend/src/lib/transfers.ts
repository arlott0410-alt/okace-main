/**
 * Service: ย้ายกะข้ามแผนก (Cross-Branch Transfer) + ประวัติ + วันที่จะต้องย้ายกะ (แดชบอร์ด)
 */

import { supabase, getApiBase } from './supabase';
import type { CrossBranchTransfer, Branch, Shift, Profile } from './types';

/** รายการตั้งเวลาย้ายกะของตัวเอง (สำหรับแสดงในแดชบอร์ด) */
export interface MyScheduledShiftChange {
  type: 'swap' | 'transfer';
  start_date: string;
  from_shift_id: string;
  to_shift_id: string;
  branch_id?: string;
  from_branch_id?: string;
  to_branch_id?: string;
}

/** ดึงรายการย้ายกะที่ตั้งเวลาแล้ว (วันที่มีผล = วันนี้หรืออนาคต) สำหรับพนักงานดูในแดชบอร์ด */
export async function getMyScheduledShiftChanges(userId: string): Promise<MyScheduledShiftChange[]> {
  const today = new Date().toISOString().slice(0, 10);
  const out: MyScheduledShiftChange[] = [];
  const { data: swaps } = await supabase
    .from('shift_swaps')
    .select('start_date, from_shift_id, to_shift_id, branch_id')
    .eq('user_id', userId)
    .eq('status', 'approved')
    .gte('start_date', today)
    .order('start_date', { ascending: true });
  (swaps || []).forEach((r: { start_date: string; from_shift_id: string; to_shift_id: string; branch_id: string }) => {
    if (r.from_shift_id === r.to_shift_id) return;
    out.push({
      type: 'swap',
      start_date: r.start_date,
      from_shift_id: r.from_shift_id,
      to_shift_id: r.to_shift_id,
      branch_id: r.branch_id,
    });
  });
  const { data: transfers } = await supabase
    .from('cross_branch_transfers')
    .select('start_date, from_shift_id, to_shift_id, from_branch_id, to_branch_id')
    .eq('user_id', userId)
    .eq('status', 'approved')
    .gte('start_date', today)
    .order('start_date', { ascending: true });
  (transfers || []).forEach(
    (r: { start_date: string; from_shift_id: string; to_shift_id: string; from_branch_id: string; to_branch_id: string }) => {
      if (r.from_shift_id === r.to_shift_id) return;
      out.push({
        type: 'transfer',
        start_date: r.start_date,
        from_shift_id: r.from_shift_id,
        to_shift_id: r.to_shift_id,
        from_branch_id: r.from_branch_id,
        to_branch_id: r.to_branch_id,
      });
    }
  );
  out.sort((a, b) => a.start_date.localeCompare(b.start_date));
  return out;
}

/** ตรวจว่าผู้ใช้นี้มีรายการตั้งเวลาย้ายกะที่ยังมีผล (approved, start_date >= วันนี้) หรือไม่ — ใช้ปิดการแก้กะในจัดการสมาชิก */
export async function hasActiveScheduledShiftChange(userId: string): Promise<boolean> {
  const today = new Date().toISOString().slice(0, 10);
  const { data: swaps } = await supabase
    .from('shift_swaps')
    .select('id')
    .eq('user_id', userId)
    .eq('status', 'approved')
    .gte('start_date', today)
    .limit(1);
  if (swaps && swaps.length > 0) return true;
  const { data: transfers } = await supabase
    .from('cross_branch_transfers')
    .select('id')
    .eq('user_id', userId)
    .eq('status', 'approved')
    .gte('start_date', today)
    .limit(1);
  return !!(transfers && transfers.length > 0);
}

/** ค่าต่อวันสำหรับตารางวันหยุด: จากกะ → กะปลายทาง */
export interface ScheduledShiftChangeDay {
  from_shift_id: string;
  to_shift_id: string;
}

/** กะ/แผนกที่มีผลในวันนั้น (จากย้ายกะ/สลับกะที่ approved และ start_date <= date <= end_date) */
export interface EffectiveBranchShift {
  branch_id: string | null;
  shift_id: string | null;
}

/**
 * คำนวณกะและแผนกที่มีผลสำหรับผู้ใช้ในวันที่กำหนด
 * ถ้ามีรายการย้ายกะ/สลับกะที่ approved และ date อยู่ใน [start_date, end_date] ใช้ to_shift / to_branch
 * ไม่มีก็ใช้ค่าจาก profile (fallback)
 */
export async function getEffectiveBranchAndShiftForDate(
  userId: string,
  dateStr: string,
  fallback: { branch_id: string | null; shift_id: string | null }
): Promise<EffectiveBranchShift> {
  const [swapsRes, transfersRes] = await Promise.all([
    supabase
      .from('shift_swaps')
      .select('start_date, end_date, branch_id, to_shift_id')
      .eq('user_id', userId)
      .eq('status', 'approved')
      .lte('start_date', dateStr)
      .or(`end_date.gte.${dateStr},end_date.is.null`),
    supabase
      .from('cross_branch_transfers')
      .select('start_date, end_date, to_branch_id, to_shift_id')
      .eq('user_id', userId)
      .eq('status', 'approved')
      .lte('start_date', dateStr)
      .or(`end_date.gte.${dateStr},end_date.is.null`),
  ]);
  const swaps = (swapsRes.data || []) as { start_date: string; end_date: string | null; branch_id: string; to_shift_id: string }[];
  const transfers = (transfersRes.data || []) as { start_date: string; end_date: string | null; to_branch_id: string; to_shift_id: string }[];
  const all = [
    ...swaps.filter((r) => r.end_date === null || r.end_date >= dateStr).map((r) => ({ start_date: r.start_date, branch_id: r.branch_id, shift_id: r.to_shift_id })),
    ...transfers.filter((r) => r.end_date === null || r.end_date >= dateStr).map((r) => ({ start_date: r.start_date, branch_id: r.to_branch_id, shift_id: r.to_shift_id })),
  ].filter((r) => r.branch_id && r.shift_id);
  if (all.length === 0) return { branch_id: fallback.branch_id, shift_id: fallback.shift_id };
  const latest = all.sort((a, b) => b.start_date.localeCompare(a.start_date))[0];
  return { branch_id: latest.branch_id, shift_id: latest.shift_id };
}

/** ตัวเลือกสำหรับ getEffectiveForStaffInMonth: กะดึก→อื่น วันเปลี่ยนกะถือเป็นวันหยุดในตัว (effective ยังเป็นกะดึกในวันนั้น) */
export interface EffectiveForMonthOptions {
  /** ถ้า from_shift = night และ to_shift ≠ night และ date = start_date ให้ใช้ from_shift (กะดึก) แทน to_shift */
  isNightShiftId?: (shiftId: string) => boolean;
}

/**
 * คำนวณกะ/แผนกที่มีผลสำหรับหลายคนทั้งเดือน — ใช้ในตารางวันหยุด (โควต้า + จอง)
 * กะดึก→เช้า/กลาง: วันเปลี่ยนกะ (start_date) ใช้กะดึกในวันนั้น เพราะหลังเลิกกะดึกเป็นวันถัดไป ระบบถือว่าวันนั้นเป็นวันหยุดในตัว
 * คืนค่า Map<userId, Map<dateStr, { branch_id, shift_id }>>
 */
export async function getEffectiveForStaffInMonth(
  staffIds: string[],
  monthStart: string,
  monthEnd: string,
  fallbacks: Map<string, { branch_id: string | null; shift_id: string | null }>,
  options?: EffectiveForMonthOptions
): Promise<Map<string, Map<string, EffectiveBranchShift>>> {
  const result = new Map<string, Map<string, EffectiveBranchShift>>();
  if (staffIds.length === 0) return result;
  const isNight = options?.isNightShiftId;

  const [swapsRes, transfersRes] = await Promise.all([
    supabase
      .from('shift_swaps')
      .select('user_id, start_date, end_date, branch_id, from_shift_id, to_shift_id')
      .in('user_id', staffIds)
      .eq('status', 'approved')
      .lte('start_date', monthEnd)
      .or(`end_date.gte.${monthStart},end_date.is.null`),
    supabase
      .from('cross_branch_transfers')
      .select('user_id, start_date, end_date, to_branch_id, from_shift_id, to_shift_id')
      .in('user_id', staffIds)
      .eq('status', 'approved')
      .lte('start_date', monthEnd)
      .or(`end_date.gte.${monthStart},end_date.is.null`),
  ]);

  type Row = { start_date: string; end_date: string | null; branch_id: string; shift_id: string; from_shift_id: string };
  const swaps = (swapsRes.data || []) as { user_id: string; start_date: string; end_date: string | null; branch_id: string; from_shift_id: string; to_shift_id: string }[];
  const transfers = (transfersRes.data || []) as { user_id: string; start_date: string; end_date: string | null; to_branch_id: string; from_shift_id: string; to_shift_id: string }[];
  const byUser = new Map<string, Row[]>();
  const add = (user_id: string, start_date: string, end_date: string | null, branch_id: string, to_shift_id: string, from_shift_id: string) => {
    if (!byUser.has(user_id)) byUser.set(user_id, []);
    byUser.get(user_id)!.push({ start_date, end_date, branch_id, shift_id: to_shift_id, from_shift_id });
  };
  swaps.forEach((r) => add(r.user_id, r.start_date, r.end_date, r.branch_id, r.to_shift_id, r.from_shift_id));
  transfers.forEach((r) => add(r.user_id, r.start_date, r.end_date, r.to_branch_id, r.to_shift_id, r.from_shift_id));

  for (const uid of staffIds) {
    const fallback = fallbacks.get(uid) ?? { branch_id: null, shift_id: null };
    const allChanges = byUser.get(uid) ?? [];
    const dayMap = new Map<string, EffectiveBranchShift>();
    let d = monthStart;
    while (d <= monthEnd) {
      const records = allChanges.filter((r) => r.start_date <= d && (r.end_date === null || r.end_date >= d));
      const latest = records.sort((a, b) => b.start_date.localeCompare(a.start_date))[0];
      if (latest) {
        let shift_id = latest.shift_id;
        if (d === latest.start_date && isNight && isNight(latest.from_shift_id) && !isNight(latest.shift_id)) {
          shift_id = latest.from_shift_id;
        }
        dayMap.set(d, { branch_id: latest.branch_id, shift_id });
      } else {
        const futureChanges = allChanges.filter((r) => r.start_date > d).sort((a, b) => a.start_date.localeCompare(b.start_date));
        const firstFuture = futureChanges[0];
        if (firstFuture) {
          dayMap.set(d, { branch_id: firstFuture.branch_id, shift_id: firstFuture.from_shift_id });
        } else {
          dayMap.set(d, { branch_id: fallback.branch_id, shift_id: fallback.shift_id });
        }
      }
      const next = new Date(d + 'T12:00:00');
      next.setDate(next.getDate() + 1);
      d = next.toISOString().slice(0, 10);
    }
    result.set(uid, dayMap);
  }
  return result;
}

/** Map: user_id -> Map<dateStr, { from_shift_id, to_shift_id }> สำหรับตารางวันหยุด (ยึดจากกะปัจจุบัน→กะปลายทาง) */
export async function getScheduledShiftChangeDatesByUser(
  staffIds: string[],
  monthStart: string,
  monthEnd: string
): Promise<Map<string, Map<string, ScheduledShiftChangeDay>>> {
  const map = new Map<string, Map<string, ScheduledShiftChangeDay>>();
  if (staffIds.length === 0) return map;
  const { data: swaps } = await supabase
    .from('shift_swaps')
    .select('user_id, start_date, from_shift_id, to_shift_id')
    .in('user_id', staffIds)
    .eq('status', 'approved')
    .gte('start_date', monthStart)
    .lte('start_date', monthEnd);
  (swaps || []).forEach((r: { user_id: string; start_date: string; from_shift_id: string; to_shift_id: string }) => {
    if (r.from_shift_id === r.to_shift_id) return;
    if (!map.has(r.user_id)) map.set(r.user_id, new Map());
    map.get(r.user_id)!.set(r.start_date, { from_shift_id: r.from_shift_id, to_shift_id: r.to_shift_id });
  });
  const { data: transfers } = await supabase
    .from('cross_branch_transfers')
    .select('user_id, start_date, from_shift_id, to_shift_id')
    .in('user_id', staffIds)
    .eq('status', 'approved')
    .gte('start_date', monthStart)
    .lte('start_date', monthEnd);
  (transfers || []).forEach((r: { user_id: string; start_date: string; from_shift_id: string; to_shift_id: string }) => {
    if (r.from_shift_id === r.to_shift_id) return;
    if (!map.has(r.user_id)) map.set(r.user_id, new Map());
    map.get(r.user_id)!.set(r.start_date, { from_shift_id: r.from_shift_id, to_shift_id: r.to_shift_id });
  });
  return map;
}

/** รายการตั้งเวลาย้ายกะ (สำหรับหัวหน้าเห็นและยกเลิก/แก้ไข) */
export interface ScheduledShiftChangeRecord {
  type: 'swap' | 'transfer';
  id: string;
  user_id: string;
  start_date: string;
  from_shift_id: string;
  to_shift_id: string;
  branch_id?: string;
  to_branch_id?: string;
  from_branch_id?: string;
}

/** ดึงรายการตั้งเวลาย้ายกะที่ approved ในแผนก (สำหรับหัวหน้า) */
export async function listScheduledShiftChangesForBranch(
  branchId: string
): Promise<ScheduledShiftChangeRecord[]> {
  const out: ScheduledShiftChangeRecord[] = [];
  const { data: swaps } = await supabase
    .from('shift_swaps')
    .select('id, user_id, start_date, from_shift_id, to_shift_id, branch_id')
    .eq('branch_id', branchId)
    .eq('status', 'approved')
    .order('start_date', { ascending: true });
  (swaps || []).forEach((r: { id: string; user_id: string; start_date: string; from_shift_id: string; to_shift_id: string; branch_id: string }) => {
    out.push({
      type: 'swap',
      id: r.id,
      user_id: r.user_id,
      start_date: r.start_date,
      from_shift_id: r.from_shift_id,
      to_shift_id: r.to_shift_id,
      branch_id: r.branch_id,
    });
  });
  const { data: transfers } = await supabase
    .from('cross_branch_transfers')
    .select('id, user_id, start_date, from_shift_id, to_shift_id, from_branch_id, to_branch_id')
    .or(`from_branch_id.eq.${branchId},to_branch_id.eq.${branchId}`)
    .eq('status', 'approved')
    .order('start_date', { ascending: true });
  (transfers || []).forEach(
    (r: { id: string; user_id: string; start_date: string; from_shift_id: string; to_shift_id: string; from_branch_id: string; to_branch_id: string }) => {
      out.push({
        type: 'transfer',
        id: r.id,
        user_id: r.user_id,
        start_date: r.start_date,
        from_shift_id: r.from_shift_id,
        to_shift_id: r.to_shift_id,
        from_branch_id: r.from_branch_id,
        to_branch_id: r.to_branch_id,
      });
    }
  );
  out.sort((a, b) => a.start_date.localeCompare(b.start_date));
  return out;
}

export async function cancelScheduledShiftChange(
  type: 'swap' | 'transfer',
  id: string
): Promise<{ ok: boolean; error?: string }> {
  await supabase.auth.refreshSession();
  const { data: { session } } = await supabase.auth.getSession();
  const token = session?.access_token ?? '';
  if (!token) return { ok: false, error: 'กรุณาล็อกอินใหม่' };
  const base = getApiBase();
  const res = await fetch(`${base}/api/shifts/proxy`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ action: 'cancel-scheduled', p_type: type, p_id: id }),
  });
  const r = (await res.json().catch(() => ({}))) as { ok?: boolean; error?: string };
  if (!res.ok) return { ok: false, error: r.error ?? 'ยกเลิกไม่สำเร็จ' };
  return { ok: !!r.ok, error: r.error };
}

export async function updateScheduledShiftChange(
  type: 'swap' | 'transfer',
  id: string,
  newStartDate: string,
  newToShiftId?: string | null
): Promise<{ ok: boolean; error?: string }> {
  await supabase.auth.refreshSession();
  const { data: { session } } = await supabase.auth.getSession();
  const token = session?.access_token ?? '';
  if (!token) return { ok: false, error: 'กรุณาล็อกอินใหม่' };
  const base = getApiBase();
  const res = await fetch(`${base}/api/shifts/proxy`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      action: 'update-scheduled',
      p_type: type,
      p_id: id,
      p_new_start_date: newStartDate,
      p_new_to_shift_id: newToShiftId ?? null,
    }),
  });
  const r = (await res.json().catch(() => ({}))) as { ok?: boolean; error?: string };
  if (!res.ok) return { ok: false, error: r.error ?? 'อัปเดตไม่สำเร็จ' };
  return { ok: !!r.ok, error: r.error };
}

export interface TransferFilters {
  month?: string;
  branchId?: string;
  userId?: string;
  status?: string;
}

/** ดึงรายการย้ายกะ (Admin ได้ทั้งหมด, Staff ได้เฉพาะของตัวเอง) */
export async function listTransfers(
  filters: TransferFilters,
  isAdmin: boolean,
  currentUserId: string
): Promise<CrossBranchTransfer[]> {
  let q = supabase
    .from('cross_branch_transfers')
    .select('id, user_id, from_branch_id, to_branch_id, from_shift_id, to_shift_id, start_date, end_date, reason, status, approved_by, approved_at, reject_reason, admin_note, created_at, skipped_dates')
    .order('created_at', { ascending: false });
  if (!isAdmin) q = q.eq('user_id', currentUserId);
  if (filters.userId) q = q.eq('user_id', filters.userId);
  if (filters.branchId) {
    q = q.or(`from_branch_id.eq.${filters.branchId},to_branch_id.eq.${filters.branchId}`);
  }
  if (filters.status) q = q.eq('status', filters.status);
  const { data, error } = await q;
  if (error) return [];
  let list = (data || []) as CrossBranchTransfer[];
  if (filters.month) {
    list = list.filter((t) => {
      const m = t.start_date.slice(0, 7);
      const m2 = t.end_date.slice(0, 7);
      return m === filters.month || m2 === filters.month;
    });
  }
  return list;
}

export type TransferWithMeta = CrossBranchTransfer & {
  from_branch?: Branch | null;
  to_branch?: Branch | null;
  from_shift?: Shift | null;
  to_shift?: Shift | null;
  profile?: Profile | null;
};

/** รายการประวัติย้ายกะรวม (สลับกะในแผนก + ย้ายข้ามแผนก) สำหรับหน้า ประวัติการย้ายกะ */
export interface ShiftChangeHistoryItem {
  type: 'swap' | 'transfer';
  id: string;
  user_id: string;
  start_date: string;
  end_date: string;
  status: string;
  created_at: string;
  from_branch_id: string;
  to_branch_id: string;
  from_shift_id: string;
  to_shift_id: string;
  from_branch?: Branch | null;
  to_branch?: Branch | null;
  from_shift?: Shift | null;
  to_shift?: Shift | null;
  profile?: Profile | null;
}

export interface ShiftChangeHistoryFilters {
  month?: string;
  branchId?: string;
  status?: string;
}

/** รายการประวัติ + meta (branch, shift, profile) สำหรับแสดงใน UI */
export type ShiftChangeHistoryItemWithMeta = ShiftChangeHistoryItem & {
  from_branch?: Branch | null;
  to_branch?: Branch | null;
  from_shift?: Shift | null;
  to_shift?: Shift | null;
  profile?: Profile | null;
};

export interface ListShiftChangeHistoryResult {
  data: ShiftChangeHistoryItem[];
  totalCount: number;
}

/** ดึงประวัติย้ายกะรวมจาก view (shift_swaps + cross_branch_transfers) — server-side pagination + month ใน query */
export async function listShiftChangeHistory(
  filters: ShiftChangeHistoryFilters,
  options: { isAdmin: boolean; isManager: boolean; isInstructorHead: boolean; currentUserId: string; myBranchId: string | null },
  pagination: { page: number; pageSize: number }
): Promise<ListShiftChangeHistoryResult> {
  const { isAdmin, isManager, isInstructorHead, currentUserId } = options;
  const canSeeAllBranches = isAdmin || isManager || isInstructorHead;
  const { page, pageSize } = pagination;

  let q = supabase
    .from('shift_change_history_view')
    .select('type, id, user_id, start_date, end_date, status, created_at, from_branch_id, to_branch_id, from_shift_id, to_shift_id', { count: 'exact' })
    .order('created_at', { ascending: false });

  if (!canSeeAllBranches) q = q.eq('user_id', currentUserId);
  if (filters.branchId) q = q.or(`from_branch_id.eq.${filters.branchId},to_branch_id.eq.${filters.branchId}`);
  if (filters.status) q = q.eq('status', filters.status);
  if (filters.month) {
    const monthStart = `${filters.month}-01`;
    const year = parseInt(filters.month.slice(0, 4), 10);
    const month = parseInt(filters.month.slice(5, 7), 10);
    const lastDay = new Date(year, month, 0);
    const monthEnd = lastDay.toISOString().slice(0, 10);
    q = q.gte('start_date', monthStart).lte('start_date', monthEnd);
  }

  const from = (page - 1) * pageSize;
  const { data, error, count } = await q.range(from, from + pageSize - 1);

  if (error) return { data: [], totalCount: 0 };

  const rows = (data || []) as ShiftChangeHistoryItem[];
  return { data: rows, totalCount: typeof count === 'number' ? count : 0 };
}

/** เพิ่ม branch/shift/profile ให้รายการประวัติ */
export async function enrichShiftChangeHistoryWithMeta(
  items: ShiftChangeHistoryItem[],
  branches: Branch[],
  shifts: Shift[]
): Promise<ShiftChangeHistoryItemWithMeta[]> {
  const userIds = [...new Set(items.map((t) => t.user_id).filter(Boolean))];
  const branchMap = new Map(branches.map((b) => [b.id, b]));
  const shiftMap = new Map(shifts.map((s) => [s.id, s]));
  let profileMap = new Map<string, Profile | null>();
  if (userIds.length > 0) {
    const { data: profiles } = await supabase
      .from('profiles')
      .select('id, email, display_name, role, default_branch_id, default_shift_id, active, created_at, updated_at')
      .in('id', userIds);
    profileMap = new Map((profiles || []).map((p) => [p.id, p as Profile]));
  }
  return items.map((t) => ({
    ...t,
    from_branch: branchMap.get(t.from_branch_id) ?? null,
    to_branch: branchMap.get(t.to_branch_id) ?? null,
    from_shift: shiftMap.get(t.from_shift_id) ?? null,
    to_shift: shiftMap.get(t.to_shift_id) ?? null,
    profile: profileMap.get(t.user_id) ?? null,
  }));
}

/**
 * Enrich transfer list with branch/shift from context and batch-fetch profiles (avoids N+1).
 */
export async function enrichTransfersWithMeta(
  items: CrossBranchTransfer[],
  branches: Branch[],
  shifts: Shift[]
): Promise<TransferWithMeta[]> {
  const userIds = [...new Set(items.map((t) => t.user_id).filter(Boolean))];
  const branchMap = new Map(branches.map((b) => [b.id, b]));
  const shiftMap = new Map(shifts.map((s) => [s.id, s]));
  let profileMap = new Map<string, Profile | null>();
  if (userIds.length > 0) {
    const { data: profiles } = await supabase
      .from('profiles')
      .select('id, email, display_name, role, default_branch_id, default_shift_id, active, created_at, updated_at')
      .in('id', userIds);
    profileMap = new Map((profiles || []).map((p) => [p.id, p as Profile]));
  }
  return items.map((t) => ({
    ...t,
    from_branch: branchMap.get(t.from_branch_id) ?? null,
    to_branch: branchMap.get(t.to_branch_id) ?? null,
    from_shift: shiftMap.get(t.from_shift_id) ?? null,
    to_shift: shiftMap.get(t.to_shift_id) ?? null,
    profile: profileMap.get(t.user_id) ?? null,
  }));
}
