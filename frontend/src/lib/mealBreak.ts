/**
 * Meal break booking (unified with break_logs, break_type='MEAL').
 * Uses /api/meal/proxy (no direct RPC from frontend).
 */

import { supabase, getApiBase } from './supabase';
import { withCache } from './queryCache';

export type MealSlotCapacity = {
  on_duty_count: number;
  max_concurrent: number;
  current_booked: number;
  is_full: boolean;
  /** รายการ user_id ของคนที่จองช่วงนี้แล้ว */
  booked_user_ids?: string[];
};

export type MealSlot = {
  slot_start: string;
  slot_end: string;
  slot_start_ts: string;
  slot_end_ts: string;
  booked_count: number;
  max_concurrent: number;
  is_booked_by_me: boolean;
  available: boolean;
  capacity?: MealSlotCapacity;
};

export type MealRound = {
  round_key: string;
  round_name: string;
  slots: MealSlot[];
};

export type MealBooking = {
  id: string;
  round_key: string;
  slot_start_ts: string;
  slot_end_ts: string;
};

export type MealSlotsResponse = {
  error?: string;
  work_date?: string;
  shift_start_ts?: string;
  shift_end_ts?: string;
  rounds?: MealRound[];
  my_bookings?: MealBooking[];
  meal_count?: number;
  /** จำนวนจองสูงสุดต่อวัน (จาก rounds_json.max_per_work_date) */
  max_per_work_date?: number;
  /** รายการ user_id ที่ระบบนับเป็น "อยู่ปฏิบัติ" สำหรับโควต้า */
  on_duty_user_ids?: string[];
};

async function mealProxy<T>(action: string, params: Record<string, unknown>): Promise<T> {
  await supabase.auth.refreshSession();
  const { data: { session } } = await supabase.auth.getSession();
  const token = session?.access_token ?? '';
  if (!token) throw new Error('กรุณาล็อกอินใหม่');
  const base = getApiBase();
  const res = await fetch(`${base}/api/meal/proxy`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ action, ...params }),
  });
  return res.json() as Promise<T>;
}

/** TTL แคช slot (วินาที) — ลดการยิง Worker เมื่อสลับ tab/refocus */
const MEAL_SLOTS_CACHE_TTL_MS = 45_000;

export async function fetchMealSlots(workDate: string): Promise<MealSlotsResponse | null> {
  try {
    const data = await withCache(
      'meal_slots',
      { work_date: workDate },
      () => mealProxy<MealSlotsResponse | null>('slots', { p_work_date: workDate }),
      MEAL_SLOTS_CACHE_TTL_MS
    );
    return data ?? null;
  } catch {
    return null;
  }
}

export async function bookMealBreak(
  workDate: string,
  roundKey: string,
  slotStartTs: string,
  slotEndTs: string
): Promise<{ ok: boolean; error?: string; id?: string }> {
  const out = await mealProxy<{ ok?: boolean; error?: string; id?: string }>('book', {
    p_work_date: workDate,
    p_round_key: roundKey,
    p_slot_start_ts: slotStartTs,
    p_slot_end_ts: slotEndTs,
  });
  return { ok: !!out?.ok, error: out?.error, id: out?.id };
}

export async function cancelMealBreak(breakLogId: string): Promise<{ ok: boolean; error?: string }> {
  const out = await mealProxy<{ ok?: boolean; error?: string }>('cancel', { p_break_log_id: breakLogId });
  return { ok: !!out?.ok, error: out?.error };
}
