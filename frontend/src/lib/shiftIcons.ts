/**
 * Single source of truth for shift type → icon and label.
 * Do NOT store icons in display_name; render dynamically from shift data.
 */

export type ShiftKind = 'morning' | 'mid' | 'night' | 'unknown';

/** Parse "HH:MM" or "HH:mm:ss" to minutes since midnight. Returns null if invalid. */
function parseTimeToMinutes(t: string | null | undefined): number | null {
  if (t == null || typeof t !== 'string') return null;
  const trimmed = t.trim();
  const match = trimmed.match(/^(\d{1,2}):(\d{2})(?::\d{2})?$/);
  if (!match) return null;
  const h = parseInt(match[1], 10);
  const m = parseInt(match[2], 10);
  if (h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

/**
 * Determine shift kind from shift start_time (preferred) or name.
 * - morning: 04:00–11:59
 * - mid: 12:00–17:59
 * - night: 18:00–03:59 (includes times after midnight)
 */
export function getShiftKind(shift: { start_time?: string | null; end_time?: string | null; name?: string | null } | null | undefined): ShiftKind {
  if (!shift) return 'unknown';
  const startMin = parseTimeToMinutes(shift.start_time);
  if (startMin !== null) {
    if (startMin >= 4 * 60 && startMin < 12 * 60) return 'morning';   // 04:00–11:59
    if (startMin >= 12 * 60 && startMin < 18 * 60) return 'mid';     // 12:00–17:59
    if (startMin >= 18 * 60 || startMin < 4 * 60) return 'night';    // 18:00–03:59
  }
  const name = (shift.name || '').toLowerCase();
  if (name.includes('เช้า') || name.includes('morning') || name.includes('กลางวัน')) return 'morning';
  if (name.includes('กลาง') || name.includes('mid') || name.includes('บ่าย')) return 'mid';
  if (name.includes('ดึก') || name.includes('night') || name.includes('กลางคืน')) return 'night';
  return 'unknown';
}

export function getShiftIcon(kind: ShiftKind): string {
  switch (kind) {
    case 'morning': return '☀️';
    case 'mid': return '🌆';
    case 'night': return '🌙';
    default: return '•';
  }
}

export function getShiftLabel(kind: ShiftKind): string {
  switch (kind) {
    case 'morning': return 'กะเช้า';
    case 'mid': return 'กะกลาง';
    case 'night': return 'กะดึก';
    default: return 'กะ';
  }
}

/** ป้ายสั้นสำหรับใช้ในตาราง/ปุ่ม: เช้า, กลาง, ดึก */
export function getShiftShortLabel(shift: { start_time?: string | null; name?: string | null } | null | undefined): string {
  const kind = getShiftKind(shift);
  switch (kind) {
    case 'morning': return 'เช้า';
    case 'mid': return 'กลาง';
    case 'night': return 'ดึก';
    default: return 'กะ';
  }
}

/** ตัวอักษรในเซลล์ตารางวันหยุด: กะเช้า = D, กะดึก = N, กะกลาง = + */
export function getShiftCellLetter(shift: { start_time?: string | null; name?: string | null } | null | undefined): 'D' | 'N' | '+' {
  const kind = getShiftKind(shift);
  switch (kind) {
    case 'morning': return 'D';
    case 'night': return 'N';
    case 'mid':
    default: return '+';
  }
}

/** ข้อความเปลี่ยนกะ: จากกะ→เป็นกะ เช่น "เช้า→ดึก" "ดึก→เช้า" "กลาง→เช้า" "กลาง→ดึก" */
export function getShiftChangeLabel(
  fromShift: { start_time?: string | null; name?: string | null } | null | undefined,
  toShift: { start_time?: string | null; name?: string | null } | null | undefined
): string {
  const from = getShiftShortLabel(fromShift);
  const to = getShiftShortLabel(toShift);
  return `${from}→${to}`;
}

