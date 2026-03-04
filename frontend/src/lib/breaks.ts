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
    .select('*')
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

/** รายชื่อคนที่กำลังพักอยู่ (สำหรับ Admin อาจส่ง userGroup เพื่อกรอง) */
export async function getActiveBreaks(
  branchId: string,
  shiftId: string,
  breakDate: string,
  userGroup?: UserGroup
): Promise<(BreakLog & { profile?: { display_name: string | null; email: string } })[]> {
  let q = supabase
    .from('break_logs')
    .select('*')
    .eq('branch_id', branchId)
    .eq('shift_id', shiftId)
    .eq('break_date', breakDate)
    .eq('status', 'active')
    .or('break_type.is.null,break_type.eq.NORMAL');
  if (userGroup) q = q.eq('user_group', userGroup);
  const { data, error } = await q.order('started_at', { ascending: false });
  if (error) return [];
  const list = (data || []) as BreakLog[];
  const withProfile = await Promise.all(
    list.map(async (log) => {
      const { data: p } = await supabase
        .from('profiles')
        .select('display_name, email')
        .eq('id', log.user_id)
        .single();
      return { ...log, profile: p ?? undefined };
    })
  );
  return withProfile;
}

const HISTORY_PAGE_SIZE = 20;

/** ประวัติการพัก (รายวัน/รายคน) — ส่ง userGroup, pagination, searchByName */
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
}): Promise<{ data: BreakLog[]; totalCount: number }> {
  const page = Math.max(1, filters.page ?? 1);
  const pageSize = Math.min(100, Math.max(1, filters.pageSize ?? HISTORY_PAGE_SIZE));
  let userIds: string[] | undefined;
  if (filters.searchName && filters.searchName.trim()) {
    const { data: profiles } = await supabase
      .from('profiles')
      .select('id')
      .ilike('display_name', `%${filters.searchName.trim()}%`);
    userIds = (profiles ?? []).map((p) => p.id);
    if (userIds.length === 0) return { data: [], totalCount: 0 };
  }
  let q = supabase
    .from('break_logs')
    .select('*, profiles(display_name)', { count: 'exact' })
    .or('break_type.is.null,break_type.eq.NORMAL')
    .order('started_at', { ascending: false })
    .range((page - 1) * pageSize, page * pageSize - 1);
  if (filters.branchId) q = q.eq('branch_id', filters.branchId);
  if (filters.shiftId) q = q.eq('shift_id', filters.shiftId);
  if (filters.userId) q = q.eq('user_id', filters.userId);
  if (userIds?.length) q = q.in('user_id', userIds);
  if (filters.userGroup) q = q.eq('user_group', filters.userGroup);
  if (filters.dateFrom) q = q.gte('break_date', filters.dateFrom);
  if (filters.dateTo) q = q.lte('break_date', filters.dateTo);
  const { data, error, count } = await q;
  if (error) return { data: [], totalCount: 0 };
  return { data: (data || []) as (BreakLog & { profiles: { display_name: string | null } | null })[], totalCount: count ?? 0 };
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
