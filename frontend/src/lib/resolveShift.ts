/**
 * Shared shift resolution for Breaks and Meal booking.
 * Uses profile.default_shift_id and shifts from BranchesShiftsContext.
 * Workday = date of shift start; night shift end is next calendar day.
 */

import type { Shift } from './types';

export type ResolvedShift = {
  shiftId: string;
  shift: Shift;
  shiftStartTs: Date;
  shiftEndTs: Date;
  workDate: string; // yyyy-MM-dd
};

/**
 * Resolve shift bounds for a work_date. Returns null if profile has no default_shift_id
 * or shift not found in list or shift has no start_time.
 */
export function resolveShift(
  defaultShiftId: string | null | undefined,
  shifts: Shift[],
  workDate: string // yyyy-MM-dd
): ResolvedShift | null {
  if (!defaultShiftId || !workDate) return null;
  const shift = shifts.find((s) => s.id === defaultShiftId);
  if (!shift || shift.start_time == null) return null;

  const [startH, startM] = shift.start_time.trim().slice(0, 5).split(':').map(Number);
  const shiftStartTs = new Date(workDate + 'T00:00:00');
  shiftStartTs.setHours(startH, startM || 0, 0, 0);

  let shiftEndTs: Date;
  if (shift.end_time != null) {
    const [endH, endM] = shift.end_time.trim().slice(0, 5).split(':').map(Number);
    shiftEndTs = new Date(workDate + 'T00:00:00');
    shiftEndTs.setHours(endH, endM || 0, 0, 0);
    if (shiftEndTs <= shiftStartTs) {
      shiftEndTs.setDate(shiftEndTs.getDate() + 1);
    }
  } else {
    shiftEndTs = new Date(shiftStartTs.getTime() + 12 * 60 * 60 * 1000);
  }

  return { shiftId: shift.id, shift, shiftStartTs, shiftEndTs, workDate };
}

/**
 * คืน work_date ที่เหมาะสมสำหรับจองพักอาหารเมื่อเปิดหน้า
 * กะดึก (ข้ามเที่ยงคืน): ถ้าตอนนี้อยู่หลัง 00:00 แต่ยังอยู่ในกะที่เริ่มเมื่อวาน ให้ใช้เมื่อวานเป็น work_date
 */
export function getDefaultWorkDateForMeal(
  defaultShiftId: string | null | undefined,
  shifts: Shift[],
  now: Date = new Date()
): string {
  const today = now.getFullYear() + '-' + String(now.getMonth() + 1).padStart(2, '0') + '-' + String(now.getDate()).padStart(2, '0');
  if (!defaultShiftId || !shifts.length) return today;
  const shift = shifts.find((s) => s.id === defaultShiftId);
  if (!shift?.start_time || !shift?.end_time) return today;
  const [startH, startM] = shift.start_time.trim().slice(0, 5).split(':').map(Number);
  const [endH, endM] = shift.end_time.trim().slice(0, 5).split(':').map(Number);
  const startMinutes = startH * 60 + (startM || 0);
  const endMinutes = endH * 60 + (endM || 0);
  const isNightShift = endMinutes <= startMinutes;
  if (!isNightShift) return today;
  const currentMinutes = now.getHours() * 60 + now.getMinutes();
  if (currentMinutes >= 0 && currentMinutes < endMinutes) {
    const yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    return yesterday.getFullYear() + '-' + String(yesterday.getMonth() + 1).padStart(2, '0') + '-' + String(yesterday.getDate()).padStart(2, '0');
  }
  return today;
}
