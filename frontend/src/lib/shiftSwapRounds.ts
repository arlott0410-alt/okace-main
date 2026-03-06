/**
 * รอบสลับกะรายเดือน — หัวหน้าจัดการ
 * - ขอบเขต: ทั้งแผนก หรือเฉพาะเว็บ
 * - สุ่มดูตัวอย่าง → ยืนยันหรือแก้ไขได้
 * - คำนวณคู่จากจำนวนวัน+คน (สลับทั้งหมดทุกคน), หัวหน้าคู่กับหัวหน้าก่อน, กันวันหยุด
 */

import { supabase } from './supabase';
import type { ShiftSwapRound, ShiftSwapAssignment } from './types';

const SHIFT_CODE_MORNING = 'M';
const SHIFT_CODE_NIGHT = 'N';
const SHIFT_CODE_MIDDLE = 'A';

export type PreviewAssignment = {
  swap_date: string;
  user_id: string;
  from_shift_id: string;
  to_shift_id: string;
  partner_id: string;
};

export async function listRounds(branchId?: string): Promise<(ShiftSwapRound & { branch?: { id: string; name: string }; website?: { id: string; name: string } | null })[]> {
  let q = supabase
    .from('shift_swap_rounds')
    .select('*, branch:branches(id, name), website:websites(id, name)')
    .order('start_date', { ascending: false });
  if (branchId) q = q.eq('branch_id', branchId);
  const { data, error } = await q;
  if (error) return [];
  return (data || []) as (ShiftSwapRound & { branch?: { id: string; name: string }; website?: { id: string; name: string } | null })[];
}

export async function createRound(payload: {
  branch_id: string;
  website_id?: string | null;
  start_date: string;
  end_date: string;
  created_by: string;
}): Promise<ShiftSwapRound> {
  const { data, error } = await supabase
    .from('shift_swap_rounds')
    .insert({
      branch_id: payload.branch_id,
      website_id: payload.website_id || null,
      start_date: payload.start_date,
      end_date: payload.end_date,
      pairs_per_day: 0,
      status: 'draft',
      created_by: payload.created_by,
    })
    .select()
    .single();
  if (error) throw new Error(error.message);
  return data as ShiftSwapRound;
}

export async function updateRoundStatus(roundId: string, status: 'draft' | 'published'): Promise<void> {
  const { error } = await supabase.from('shift_swap_rounds').update({ status }).eq('id', roundId);
  if (error) throw new Error(error.message);
}

export async function deleteRound(roundId: string): Promise<void> {
  const { error } = await supabase.from('shift_swap_rounds').delete().eq('id', roundId);
  if (error) throw new Error(error.message);
}

export async function listAssignments(roundId: string): Promise<ShiftSwapAssignment[]> {
  const { data, error } = await supabase
    .from('shift_swap_assignments')
    .select('id, round_id, swap_date, user_id, from_shift_id, to_shift_id, partner_id, created_at')
    .eq('round_id', roundId)
    .order('swap_date')
    .order('user_id');
  if (error) return [];
  return (data || []) as ShiftSwapAssignment[];
}

async function getApprovedLeaveUserDates(branchId: string, startDate: string, endDate: string): Promise<Set<string>> {
  const { data } = await supabase
    .from('holidays')
    .select('user_id, holiday_date')
    .eq('branch_id', branchId)
    .eq('status', 'approved')
    .gte('holiday_date', startDate)
    .lte('holiday_date', endDate);
  const set = new Set<string>();
  (data || []).forEach((r: { user_id: string; holiday_date: string }) => set.add(`${r.user_id}:${r.holiday_date}`));
  return set;
}

function shuffle<T>(arr: T[]): T[] {
  const out = [...arr];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

type StaffEntry = { id: string; default_shift_id: string; role: string };

/** ดึงรายชื่อ staff ตามแผนก (และเว็บถ้าระบุ) รวมหัวหน้า */
async function getStaffForRound(branchId: string, websiteId: string | null): Promise<StaffEntry[]> {
  let profileIds: string[] | null = null;
  if (websiteId) {
    const { data: assign } = await supabase.from('website_assignments').select('user_id').eq('website_id', websiteId);
    profileIds = (assign || []).map((r: { user_id: string }) => r.user_id);
    if (profileIds.length === 0) return [];
  }
  const q = supabase
    .from('profiles')
    .select('id, default_shift_id, role')
    .eq('default_branch_id', branchId)
    .eq('active', true)
    .in('role', ['instructor', 'staff', 'instructor_head']);
  if (profileIds) q.in('id', profileIds);
  const { data } = await q;
  return (data || []) as StaffEntry[];
}

/** แยกกลุ่ม: หัวหน้า+พนักงานประจำ กับ พนักงานออนไลน์ */
const INSTRUCTOR_GROUP_ROLES = ['instructor_head', 'instructor'];
const STAFF_GROUP_ROLE = 'staff';

function buildMorningNightPools(
  people: StaffEntry[],
  morningShiftId: string,
  nightShiftId: string,
  middleShiftId: string | null
): { morningPool: StaffEntry[]; nightPool: StaffEntry[] } {
  const byShift = new Map<string, StaffEntry[]>();
  people.forEach((p) => {
    if (!p.default_shift_id) return;
    const list = byShift.get(p.default_shift_id) || [];
    list.push(p);
    byShift.set(p.default_shift_id, list);
  });
  const morningRaw = byShift.get(morningShiftId) || [];
  const nightRaw = byShift.get(nightShiftId) || [];
  const middleRaw = middleShiftId ? (byShift.get(middleShiftId) || []) : [];
  const middleShuffled = shuffle(middleRaw);
  const midHalf = Math.ceil(middleShuffled.length / 2);
  const morningPool = [...morningRaw];
  const nightPool = [...nightRaw];
  middleShuffled.forEach((p, i) => (i < midHalf ? morningPool.push(p) : nightPool.push(p)));
  return { morningPool, nightPool };
}

function distributePairsOverDays(totalPairs: number, numDays: number): number[] {
  const arr: number[] = [];
  let remaining = totalPairs;
  for (let i = 0; i < numDays; i++) {
    const slots = Math.ceil(remaining / (numDays - i));
    arr.push(slots);
    remaining -= slots;
  }
  return arr;
}

/** หัวหน้า+พนักงานประจำ: เรียงหัวหน้าก่อน */
function instructorOrder(arr: StaffEntry[]): StaffEntry[] {
  const heads = arr.filter((p) => p.role === 'instructor_head');
  const rest = arr.filter((p) => p.role !== 'instructor_head');
  return [...heads, ...rest];
}

/**
 * สุ่มดูตัวอย่าง — ไม่บันทึก DB
* - แยกกลุ่ม: (หัวหน้าพนักงานประจำ + พนักงานประจำ) กับ (พนักงานออนไลน์) — แต่ละกลุ่มสลับภายในกลุ่มเท่านั้น
* - กลุ่มหัวหน้า/พนักงานประจำ: หัวหน้าคู่กับหัวหน้าก่อน แล้วค่อยพนักงานประจำ
 * - กลุ่มพนักงานออนไลน์: สลับกันเอง
 * - กันวันหยุด (approved) ไม่ให้ชนวันสลับ
 */
export async function generatePreview(roundId: string): Promise<PreviewAssignment[]> {
  const { data: round, error: roundErr } = await supabase
    .from('shift_swap_rounds')
    .select('id, branch_id, website_id, start_date, end_date, pairs_per_day, status, created_by, created_at, updated_at')
    .eq('id', roundId)
    .single();
  if (roundErr || !round) throw new Error('ไม่พบรอบสลับกะ');

  const branchId = round.branch_id;
  const websiteId = round.website_id || null;
  const startDate = round.start_date;
  const endDate = round.end_date;

  const [shiftsRes, staff, leaveSet] = await Promise.all([
    supabase.from('shifts').select('id, code').in('code', [SHIFT_CODE_MORNING, SHIFT_CODE_NIGHT, SHIFT_CODE_MIDDLE]),
    getStaffForRound(branchId, websiteId),
    getApprovedLeaveUserDates(branchId, startDate, endDate),
  ]);

  const shiftList = (shiftsRes.data || []) as { id: string; code: string }[];
  const morningShift = shiftList.find((s) => s.code === SHIFT_CODE_MORNING);
  const nightShift = shiftList.find((s) => s.code === SHIFT_CODE_NIGHT);
  const middleShift = shiftList.find((s) => s.code === SHIFT_CODE_MIDDLE);
  if (!morningShift || !nightShift) throw new Error('ระบบต้องมีกะเช้า (M) และกะดึก (N)');

  const instructorStaff = staff.filter((p) => INSTRUCTOR_GROUP_ROLES.includes(p.role));
  const staffOnly = staff.filter((p) => p.role === STAFF_GROUP_ROLE);

  const { morningPool: instMorning, nightPool: instNight } = buildMorningNightPools(
    instructorStaff,
    morningShift.id,
    nightShift.id,
    middleShift?.id ?? null
  );
  const { morningPool: staffMorning, nightPool: staffNight } = buildMorningNightPools(
    staffOnly,
    morningShift.id,
    nightShift.id,
    middleShift?.id ?? null
  );

  const start = new Date(startDate);
  const end = new Date(endDate);
  const dates: string[] = [];
  for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) dates.push(d.toISOString().slice(0, 10));
  const numDays = dates.length;
  if (numDays === 0) return [];

  const totalPairsInst = Math.min(instMorning.length, instNight.length);
  const totalPairsStaff = Math.min(staffMorning.length, staffNight.length);
  const pairsPerDayInst = distributePairsOverDays(totalPairsInst, numDays);
  const pairsPerDayStaff = distributePairsOverDays(totalPairsStaff, numDays);

  const assignedInst = new Set<string>();
  const assignedStaff = new Set<string>();
  const result: PreviewAssignment[] = [];

  for (let dayIdx = 0; dayIdx < dates.length; dayIdx++) {
    const dateStr = dates[dayIdx];

    const morningAvailInst = instructorOrder(instMorning).filter((p) => !leaveSet.has(`${p.id}:${dateStr}`) && !assignedInst.has(p.id));
    const nightAvailInst = instructorOrder(instNight).filter((p) => !leaveSet.has(`${p.id}:${dateStr}`) && !assignedInst.has(p.id));
    const nInst = Math.min(pairsPerDayInst[dayIdx] ?? 0, morningAvailInst.length, nightAvailInst.length);
    for (let i = 0; i < nInst; i++) {
      const uidM = morningAvailInst[i];
      const uidN = nightAvailInst[i];
      if (!uidM || !uidN) break;
      assignedInst.add(uidM.id);
      assignedInst.add(uidN.id);
      result.push({ swap_date: dateStr, user_id: uidM.id, from_shift_id: uidM.default_shift_id, to_shift_id: nightShift.id, partner_id: uidN.id });
      result.push({ swap_date: dateStr, user_id: uidN.id, from_shift_id: uidN.default_shift_id, to_shift_id: morningShift.id, partner_id: uidM.id });
    }

    const morningAvailStaff = shuffle(staffMorning.filter((p) => !leaveSet.has(`${p.id}:${dateStr}`) && !assignedStaff.has(p.id)));
    const nightAvailStaff = shuffle(staffNight.filter((p) => !leaveSet.has(`${p.id}:${dateStr}`) && !assignedStaff.has(p.id)));
    const nStaff = Math.min(pairsPerDayStaff[dayIdx] ?? 0, morningAvailStaff.length, nightAvailStaff.length);
    for (let i = 0; i < nStaff; i++) {
      const uidM = morningAvailStaff[i];
      const uidN = nightAvailStaff[i];
      if (!uidM || !uidN) break;
      assignedStaff.add(uidM.id);
      assignedStaff.add(uidN.id);
      result.push({ swap_date: dateStr, user_id: uidM.id, from_shift_id: uidM.default_shift_id, to_shift_id: nightShift.id, partner_id: uidN.id });
      result.push({ swap_date: dateStr, user_id: uidN.id, from_shift_id: uidN.default_shift_id, to_shift_id: morningShift.id, partner_id: uidM.id });
    }
  }

  return result;
}

/** บันทึกชุดตัวอย่างลง DB (ลบของเดิมแล้ว insert) */
export async function applyPreview(roundId: string, rows: PreviewAssignment[]): Promise<void> {
  await supabase.from('shift_swap_assignments').delete().eq('round_id', roundId);
  if (rows.length === 0) return;
  const inserts = rows.map((r) => ({
    round_id: roundId,
    swap_date: r.swap_date,
    user_id: r.user_id,
    from_shift_id: r.from_shift_id,
    to_shift_id: r.to_shift_id,
    partner_id: r.partner_id,
  }));
  const { error } = await supabase.from('shift_swap_assignments').insert(inserts);
  if (error) throw new Error(error.message);
}

export async function addManualAssignment(payload: {
  round_id: string;
  swap_date: string;
  user_id: string;
  from_shift_id: string;
  to_shift_id: string;
  partner_id: string | null;
}): Promise<void> {
  const { error } = await supabase.from('shift_swap_assignments').insert(payload);
  if (error) throw new Error(error.message);
}

export async function removeAssignment(assignmentId: string): Promise<void> {
  const { data: row } = await supabase.from('shift_swap_assignments').select('round_id, swap_date, partner_id').eq('id', assignmentId).single();
  const { error } = await supabase.from('shift_swap_assignments').delete().eq('id', assignmentId);
  if (error) throw new Error(error.message);
  if (row?.partner_id) {
    const { data: partner } = await supabase.from('shift_swap_assignments').select('id').eq('round_id', row.round_id).eq('swap_date', row.swap_date).eq('user_id', row.partner_id).maybeSingle();
    if (partner?.id) await supabase.from('shift_swap_assignments').delete().eq('id', partner.id);
  }
}

/** วันที่สลับกะของฉัน (Dashboard) */
export async function getMySwapDates(userId: string): Promise<{ swap_date: string; from_shift_name: string; to_shift_name: string; round_id: string }[]> {
  const { data: assignments, error } = await supabase
    .from('shift_swap_assignments')
    .select('swap_date, from_shift_id, to_shift_id, round_id')
    .eq('user_id', userId)
    .gte('swap_date', new Date().toISOString().slice(0, 10))
    .order('swap_date');
  if (error || !assignments?.length) return [];

  const roundIds = [...new Set((assignments as { round_id: string }[]).map((a) => a.round_id))];
  const { data: rounds } = await supabase.from('shift_swap_rounds').select('id, status').in('id', roundIds);
  const publishedIds = new Set(((rounds || []) as { id: string; status: string }[]).filter((r) => r.status === 'published').map((r) => r.id));
  const filtered = (assignments as { round_id: string; swap_date: string; from_shift_id: string; to_shift_id: string }[]).filter((a) => publishedIds.has(a.round_id));
  if (filtered.length === 0) return [];

  const shiftIds = [...new Set(filtered.flatMap((r) => [r.from_shift_id, r.to_shift_id]))];
  const { data: shiftData } = await supabase.from('shifts').select('id, name').in('id', shiftIds);
  const shiftNames = Object.fromEntries(((shiftData || []) as { id: string; name: string }[]).map((s) => [s.id, s.name]));

  return filtered.map((r) => ({
    swap_date: r.swap_date,
    from_shift_name: shiftNames[r.from_shift_id] || '-',
    to_shift_name: shiftNames[r.to_shift_id] || '-',
    round_id: r.round_id,
  }));
}

/** ตารางสลับกะทั้งแผนก (พนักงานดู) — เฉพาะรอบที่เผยแพร่แล้ว ในแผนกของตัวเอง */
export async function listPublishedAssignmentsByBranch(branchId: string): Promise<{ swap_date: string; user_id: string; user_name: string; from_shift_name: string; to_shift_name: string }[]> {
  const { data: rounds } = await supabase.from('shift_swap_rounds').select('id').eq('branch_id', branchId).eq('status', 'published');
  const roundIds = ((rounds || []) as { id: string }[]).map((r) => r.id);
  if (roundIds.length === 0) return [];

  const { data: rows, error } = await supabase
    .from('shift_swap_assignments')
    .select('swap_date, user_id, from_shift_id, to_shift_id')
    .in('round_id', roundIds)
    .gte('swap_date', new Date().toISOString().slice(0, 10))
    .order('swap_date')
    .order('user_id');
  if (error || !rows?.length) return [];

  const userIds = [...new Set((rows as { user_id: string }[]).map((r) => r.user_id))];
  const shiftIds = [...new Set((rows as { from_shift_id: string; to_shift_id: string }[]).flatMap((r) => [r.from_shift_id, r.to_shift_id]))];
  const [profilesRes, shiftsRes] = await Promise.all([
    supabase.from('profiles').select('id, display_name, email').in('id', userIds),
    supabase.from('shifts').select('id, name').in('id', shiftIds),
  ]);
  const profileNames = Object.fromEntries(((profilesRes.data || []) as { id: string; display_name: string | null; email: string }[]).map((p) => [p.id, p.display_name || p.email || p.id]));
  const shiftNames = Object.fromEntries(((shiftsRes.data || []) as { id: string; name: string }[]).map((s) => [s.id, s.name]));

  return (rows as { swap_date: string; user_id: string; from_shift_id: string; to_shift_id: string }[]).map((r) => ({
    swap_date: r.swap_date,
    user_id: r.user_id,
    user_name: profileNames[r.user_id] || r.user_id,
    from_shift_name: shiftNames[r.from_shift_id] || '-',
    to_shift_name: shiftNames[r.to_shift_id] || '-',
  }));
}
