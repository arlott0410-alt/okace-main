/**
 * Service: ยืนยันตารางกะรายเดือน (Monthly Roster Confirmation / Lock)
 */

import { supabase } from './supabase';
import type { MonthlyRosterStatus } from './types';

/** ดึงสถานะตารางกะของเดือน+แผนก */
export async function getRosterStatus(
  branchId: string,
  month: string
): Promise<MonthlyRosterStatus | null> {
  const monthStart = month + '-01';
  const { data, error } = await supabase
    .from('monthly_roster_status')
    .select('*')
    .eq('branch_id', branchId)
    .eq('month', monthStart)
    .maybeSingle();
  if (error || !data) return null;
  return data as MonthlyRosterStatus;
}

/** ยืนยันตาราง (ล็อก) */
export async function confirmRoster(
  branchId: string,
  month: string,
  confirmedBy: string
): Promise<{ error: Error | null }> {
  const monthDate = month + '-01';
  const existing = await getRosterStatus(branchId, month);
  if (existing) {
    const { error } = await supabase
      .from('monthly_roster_status')
      .update({
        status: 'CONFIRMED',
        confirmed_by: confirmedBy,
        confirmed_at: new Date().toISOString(),
        unlock_reason: null,
        unlocked_by: null,
        unlocked_at: null,
      })
      .eq('id', existing.id);
    return { error: error ?? null };
  }
  const { error } = await supabase.from('monthly_roster_status').insert({
    branch_id: branchId,
    month: monthDate,
    status: 'CONFIRMED',
    confirmed_by: confirmedBy,
    confirmed_at: new Date().toISOString(),
  });
  return { error: error ?? null };
}

/** ปลดล็อก พร้อมเหตุผล (บังคับ) */
export async function unlockRoster(
  branchId: string,
  month: string,
  unlockReason: string,
  unlockedBy: string
): Promise<{ error: Error | null }> {
  const existing = await getRosterStatus(branchId, month);
  if (!existing) return { error: null };
  const { error } = await supabase
    .from('monthly_roster_status')
    .update({
      status: 'DRAFT',
      unlock_reason: unlockReason,
      unlocked_by: unlockedBy,
      unlocked_at: new Date().toISOString(),
    })
    .eq('id', existing.id);
  return { error: error ?? null };
}

/** เช็คว่าตารางกะเดือนนี้ล็อกหรือยัง */
export function isRosterLocked(status: MonthlyRosterStatus | null): boolean {
  return status?.status === 'CONFIRMED';
}
