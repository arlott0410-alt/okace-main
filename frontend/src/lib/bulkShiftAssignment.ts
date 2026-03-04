/**
 * Bulk shift assignment with holiday conflict guard.
 * Holidays with status IN ('approved','pending') are treated as reserved; those dates are skipped or block.
 */

import { supabase, getApiBase } from './supabase';

export type BulkConflictMode = 'SKIP_DAYS' | 'BLOCK_ALL';

export interface HolidayConflictRow {
  user_id: string;
  holiday_date: string;
}

export interface ConflictSummary {
  /** user_id -> set of date strings (YYYY-MM-DD) */
  conflictMap: Record<string, Set<string>>;
  /** For UI: list of { user_id, display_name, dates } */
  conflictList: Array<{ user_id: string; display_name: string; dates: string[] }>;
  totalSelected: number;
  employeesWithConflicts: number;
}

/**
 * Fetch holidays in range for given users with status IN ('approved','pending').
 */
export async function fetchHolidayConflicts(
  employeeIds: string[],
  startDate: string,
  endDate: string,
  profiles?: Array<{ id: string; display_name: string | null }>
): Promise<ConflictSummary> {
  if (employeeIds.length === 0) {
    return {
      conflictMap: {},
      conflictList: [],
      totalSelected: 0,
      employeesWithConflicts: 0,
    };
  }

  const { data: rows, error } = await supabase
    .from('holidays')
    .select('user_id, holiday_date')
    .in('user_id', employeeIds)
    .gte('holiday_date', startDate)
    .lte('holiday_date', endDate)
    .in('status', ['approved', 'pending']);

  if (error) {
    throw new Error(error.message || 'Failed to load holidays');
  }

  const list = (rows ?? []) as HolidayConflictRow[];
  const conflictMap: Record<string, Set<string>> = {};
  for (const r of list) {
    if (!conflictMap[r.user_id]) conflictMap[r.user_id] = new Set();
    conflictMap[r.user_id].add(r.holiday_date);
  }

  const conflictList: ConflictSummary['conflictList'] = Object.entries(conflictMap).map(
    ([uid, set]) => {
      const p = profiles?.find((x) => x.id === uid);
      return {
        user_id: uid,
        display_name: p?.display_name ?? p?.id ?? uid,
        dates: Array.from(set).sort(),
      };
    }
  );

  return {
    conflictMap,
    conflictList,
    totalSelected: employeeIds.length,
    employeesWithConflicts: conflictList.length,
  };
}

export interface ApplyBulkResult {
  applied: number;
  skipped_per_user: Record<string, string[]>;
}

/**
 * Apply bulk assignment via /api/shifts/proxy. Server rechecks holidays and skips conflict dates (SKIP_DAYS).
 * For BLOCK_ALL: call this only when conflictSummary.employeesWithConflicts === 0; otherwise UI should block.
 */
export async function applyBulkAssignment(
  employeeIds: string[],
  startDate: string,
  endDate: string,
  toBranchId: string,
  toShiftId: string,
  reason: string | null
): Promise<ApplyBulkResult> {
  await supabase.auth.refreshSession();
  const { data: { session } } = await supabase.auth.getSession();
  const token = session?.access_token ?? '';
  if (!token) throw new Error('กรุณาล็อกอินใหม่');
  const base = getApiBase();
  const res = await fetch(`${base}/api/shifts/proxy`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      action: 'apply-bulk',
      p_employee_ids: employeeIds,
      p_start_date: startDate,
      p_end_date: endDate,
      p_to_branch_id: toBranchId,
      p_to_shift_id: toShiftId,
      p_reason: reason || null,
    }),
  });
  const raw = (await res.json().catch(() => null)) as { applied?: number; skipped_per_user?: Record<string, string[]> } | null;
  if (!res.ok) {
    throw new Error((raw as { error?: string })?.error || 'Bulk assignment failed');
  }
  return {
    applied: raw?.applied ?? 0,
    skipped_per_user: raw?.skipped_per_user ?? {},
  };
}

/** Assignment for paired swap: each user gets their own to_shift_id */
export interface PairedSwapAssignment {
  user_id: string;
  to_shift_id: string;
}

/**
 * Apply paired swap via /api/shifts/proxy: each person moves to their assigned shift (same branch); holiday dates skipped.
 */
export async function applyPairedSwap(
  branchId: string,
  startDate: string,
  endDate: string,
  assignments: PairedSwapAssignment[],
  reason: string | null
): Promise<ApplyBulkResult> {
  await supabase.auth.refreshSession();
  const { data: { session } } = await supabase.auth.getSession();
  const token = session?.access_token ?? '';
  if (!token) throw new Error('กรุณาล็อกอินใหม่');
  const base = getApiBase();
  const res = await fetch(`${base}/api/shifts/proxy`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      action: 'apply-paired',
      p_branch_id: branchId,
      p_start_date: startDate,
      p_end_date: endDate,
      p_assignments: assignments,
      p_reason: reason || null,
    }),
  });
  const raw = (await res.json().catch(() => null)) as { applied?: number; skipped_per_user?: Record<string, string[]> } | null;
  if (!res.ok) {
    throw new Error((raw as { error?: string })?.error || 'สลับกะจับคู่ไม่สำเร็จ');
  }
  return {
    applied: raw?.applied ?? 0,
    skipped_per_user: raw?.skipped_per_user ?? {},
  };
}
