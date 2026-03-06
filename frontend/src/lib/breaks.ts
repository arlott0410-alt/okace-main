/**
 * Service: ระบบพัก (Break Concurrency)
 * - ดึงกติกาพักตามแผนก/กะ และจำนวนพนักงาน
 * - นับจำนวนคนที่กำลังพักอยู่
 */

import { supabase } from './supabase';
import type { BreakRule, BreakLog } from './types';
import type { UserGroup } from './types';

/** ดึงกติกาที่ใช้ได้: ตรงแผนก+กะ+user_group หรือ global (branch_id/shift_id เป็น null) */
export async function getBreakRules(branchId: string, shiftId: string, userGroup: UserGroup): Promise<BreakRule[]> {
  const { data, error } = await supabase
    .from('break_rules')
    .select('id, branch_id, shift_id, min_staff, max_staff, concurrent_breaks, user_group')
    .eq('user_group', userGroup)
    .or(`and(branch_id.eq.${branchId},shift_id.eq.${shiftId}),and(branch_id.is.null,shift_id.is.null)`)
    .order('min_staff');
  if (error) return [];
  return (data || []) as BreakRule[];
}

/** คืนค่าโควต้าพักพร้อมกันได้ ตามจำนวนพนักงาน (ใช้ rule ที่ min_staff <= staffCount <= max_staff) */
export function getConcurrentLimitForStaffCount(rules: BreakRule[], staffCount: number): number {
  const rule = rules.find((r) => staffCount >= r.min_staff && staffCount <= r.max_staff);
  return rule?.concurrent_breaks ?? 1;
}

/** นับจำนวนคนที่กำลังพักอยู่ (status = active) ในแผนก+กะ+วันที่+user_group */
export async function getActiveBreakCount(
  branchId: string,
  shiftId: string,
  breakDate: string,
  userGroup: UserGroup
): Promise<number> {
  const { count, error } = await supabase
    .from('break_logs')
    .select('id', { count: 'exact', head: true })
    .eq('branch_id', branchId)
    .eq('shift_id', shiftId)
    .eq('break_date', breakDate)
    .eq('status', 'active')
    .eq('user_group', userGroup)
    .or('break_type.is.null,break_type.eq.NORMAL');
  if (error) return 0;
  return count ?? 0;
}

/** รายชื่อคนที่กำลังพักอยู่ (สำหรับ Admin อาจส่ง userGroup เพื่อกรอง). Batch-fetch profiles เพื่อลด N+1 */
export async function getActiveBreaks(
  branchId: string,
  shiftId: string,
  breakDate: string,
  userGroup?: UserGroup
): Promise<(BreakLog & { profile?: { display_name: string | null; email: string } })[]> {
  let q = supabase
    .from('break_logs')
    .select('id, user_id, branch_id, shift_id, break_date, started_at, ended_at, status, user_group, break_type')
    .eq('branch_id', branchId)
    .eq('shift_id', shiftId)
    .eq('break_date', breakDate)
    .eq('status', 'active')
    .or('break_type.is.null,break_type.eq.NORMAL');
  if (userGroup) q = q.eq('user_group', userGroup);
  const { data, error } = await q.order('started_at', { ascending: false });
  if (error) return [];
  const list = (data || []) as BreakLog[];
  const userIds = [...new Set(list.map((log) => log.user_id).filter(Boolean))];
  let profileMap = new Map<string, { display_name: string | null; email: string }>();
  if (userIds.length > 0) {
    const { data: profiles } = await supabase
      .from('profiles')
      .select('id, display_name, email')
      .in('id', userIds);
    (profiles || []).forEach((p: { id: string; display_name: string | null; email: string }) => {
      profileMap.set(p.id, { display_name: p.display_name, email: p.email ?? '' });
    });
  }
  return list.map((log) => ({
    ...log,
    profile: profileMap.get(log.user_id),
  }));
}

const HISTORY_PAGE_SIZE = 20;

/** ประวัติการพัก (รายวัน/รายคน) — ส่ง userGroup, pagination, searchByName. ใช้ hasMore แทน exact count เพื่อลด row reads */
export async function getBreakHistory(filters: {
  branchId?: string;
  shiftId?: string;
  dateFrom?: string;
  dateTo?: string;
  userId?: string;
  userGroup?: UserGroup;
  page?: number;
  pageSize?: number;
  searchName?: string;
}): Promise<{ data: (BreakLog & { profiles: { display_name: string | null } | null })[]; hasMore: boolean }> {
  const page = Math.max(1, filters.page ?? 1);
  const pageSize = Math.min(100, Math.max(1, filters.pageSize ?? HISTORY_PAGE_SIZE));
  let userIds: string[] | undefined;
  if (filters.searchName && filters.searchName.trim()) {
    const { data: profiles } = await supabase
      .from('profiles')
      .select('id')
      .ilike('display_name', `%${filters.searchName.trim()}%`);
    userIds = (profiles ?? []).map((p) => p.id);
    if (userIds.length === 0) return { data: [], hasMore: false };
  }
  const from = (page - 1) * pageSize;
  let q = supabase
    .from('break_logs')
    .select('id, user_id, branch_id, shift_id, break_date, started_at, ended_at, status, user_group, break_type, profiles(display_name)')
    .or('break_type.is.null,break_type.eq.NORMAL')
    .order('started_at', { ascending: false })
    .range(from, from + pageSize);
  if (filters.branchId) q = q.eq('branch_id', filters.branchId);
  if (filters.shiftId) q = q.eq('shift_id', filters.shiftId);
  if (filters.userId) q = q.eq('user_id', filters.userId);
  if (userIds?.length) q = q.in('user_id', userIds);
  if (filters.userGroup) q = q.eq('user_group', filters.userGroup);
  if (filters.dateFrom) q = q.gte('break_date', filters.dateFrom);
  if (filters.dateTo) q = q.lte('break_date', filters.dateTo);
  const { data, error } = await q;
  if (error) return { data: [], hasMore: false };
  const rawRows = (data || []) as Array<BreakLog & { profiles?: { display_name: string | null } | { display_name: string | null }[] | null }>;
  const rows: (BreakLog & { profiles: { display_name: string | null } | null })[] = rawRows.map((r) => {
    const profiles = r.profiles == null ? null : Array.isArray(r.profiles) ? (r.profiles[0] ?? null) : r.profiles;
    const { profiles: _p, ...rest } = r;
    return { ...rest, profiles };
  });
  const hasMore = rows.length > pageSize;
  const dataSlice = hasMore ? rows.slice(0, pageSize) : rows;
  return { data: dataSlice, hasMore };
}

/** ประมาณจำนวนพนักงานในแผนก+กะในวันนั้น ในกลุ่มที่กำหนด (จาก monthly_roster + profiles.role) — นับเฉพาะ role ที่ตรง user_group */
export async function estimateStaffCount(
  branchId: string,
  shiftId: string,
  date: string,
  userGroup: UserGroup
): Promise<number> {
  const roleMatch = userGroup === 'INSTRUCTOR' ? 'instructor' : userGroup === 'MANAGER' ? 'manager' : 'staff';
  const { data: rows, error } = await supabase
    .from('monthly_roster')
    .select('user_id, profiles(role)')
    .eq('branch_id', branchId)
    .eq('shift_id', shiftId)
    .eq('work_date', date);
  if (error) return 0;
  const list = (rows || []) as Array<{ user_id: string; profiles: { role: string } | { role: string }[] | null }>;
  const getRole = (r: (typeof list)[0]) => {
    const p = r.profiles;
    if (!p) return null;
    return Array.isArray(p) ? p[0]?.role : p.role;
  };
  const staffCount = list.filter((r) => getRole(r) === roleMatch).length;
  return staffCount > 0 ? staffCount : 5;
}
