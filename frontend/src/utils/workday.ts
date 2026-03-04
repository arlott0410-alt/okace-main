/**
 * Workday interval and slot timestamp helpers for cross-midnight (night) shifts.
 * All times in HH:mm (24h). workdayDate is the calendar date of the shift "start" (YYYY-MM-DD).
 */

export interface WorkdayInterval {
  startAt: Date;
  endAt: Date;
}

/**
 * Returns the workday interval [startAt, endAt) in UTC.
 * If shiftEnd < shiftStart (e.g. 22:00–06:00), endAt is the next calendar day.
 */
export function getWorkdayInterval(
  workdayDate: string,
  shiftStartHHmm: string,
  shiftEndHHmm: string
): WorkdayInterval {
  const [sh, sm] = shiftStartHHmm.split(':').map(Number);
  const [eh, em] = shiftEndHHmm.split(':').map(Number);
  const startAt = new Date(`${workdayDate}T${String(sh).padStart(2, '0')}:${String(sm).padStart(2, '0')}:00.000Z`);
  let endAt = new Date(`${workdayDate}T${String(eh).padStart(2, '0')}:${String(em).padStart(2, '0')}:00.000Z`);
  if (endAt <= startAt) {
    const nextDay = new Date(workdayDate);
    nextDay.setUTCDate(nextDay.getUTCDate() + 1);
    const nextY = nextDay.getUTCFullYear();
    const nextM = String(nextDay.getUTCMonth() + 1).padStart(2, '0');
    const nextD = String(nextDay.getUTCDate()).padStart(2, '0');
    endAt = new Date(`${nextY}-${nextM}-${nextD}T${String(eh).padStart(2, '0')}:${String(em).padStart(2, '0')}:00.000Z`);
  }
  return { startAt, endAt };
}

/**
 * Normalizes a slot time to the correct timestamp. If the shift crosses midnight and
 * slotHHmm is before shiftStartHHmm (e.g. slot 02:00, shift 22:00–06:00), the slot is on the next day.
 */
export function normalizeSlotTimestamp(
  workdayDate: string,
  shiftStartHHmm: string,
  slotHHmm: string
): Date {
  const [slotH, slotM] = slotHHmm.split(':').map(Number);
  const [shiftStartH, shiftStartM] = shiftStartHHmm.split(':').map(Number);
  const slotMins = slotH * 60 + slotM;
  const shiftStartMins = shiftStartH * 60 + shiftStartM;
  const nextDay = new Date(workdayDate);
  nextDay.setUTCDate(nextDay.getUTCDate() + 1);
  const nextY = nextDay.getUTCFullYear();
  const nextM = String(nextDay.getUTCMonth() + 1).padStart(2, '0');
  const nextD = String(nextDay.getUTCDate()).padStart(2, '0');
  const baseDate = workdayDate;
  if (slotMins < shiftStartMins) {
    return new Date(`${nextY}-${nextM}-${nextD}T${String(slotH).padStart(2, '0')}:${String(slotM).padStart(2, '0')}:00.000Z`);
  }
  return new Date(`${baseDate}T${String(slotH).padStart(2, '0')}:${String(slotM).padStart(2, '0')}:00.000Z`);
}
