/**
 * ย้ายกะจำนวนมาก: โหมดย้ายไปกะปลายทาง | โหมดสลับกะจับคู่ (เช้า↔ดึก).
 * Only admin / manager / instructor_head.
 */

import { useState, useEffect, useMemo, useRef } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import { useBranchesShifts } from '../lib/BranchesShiftsContext';
import type { Profile, Shift } from '../lib/types';
import {
  fetchHolidayConflicts,
  applyBulkAssignment,
  applyPairedSwap,
  type ConflictSummary,
  type BulkConflictMode,
  type PairedSwapAssignment,
} from '../lib/bulkShiftAssignment';
import {
  listScheduledShiftChangesForBranch,
  cancelScheduledShiftChange,
  updateScheduledShiftChange,
  type ScheduledShiftChangeRecord,
} from '../lib/transfers';
import { getShiftKind } from '../lib/shiftIcons';
import Button from '../components/ui/Button';
import Modal, { ConfirmModal } from '../components/ui/Modal';
import { BtnEdit, BtnCancel } from '../components/ui/ActionIcons';
import BulkMoveTopBar from '../components/bulk-move/BulkMoveTopBar';
import StaffTable from '../components/bulk-move/StaffTable';
import SelectedCart from '../components/bulk-move/SelectedCart';

const EMPLOYEE_ROLES = ['instructor', 'staff', 'instructor_head'] as const;

/** วันพรุ่งนี้ YYYY-MM-DD (สำหรับ min วันที่ย้าย/สลับ — ตั้งได้ขั้นต่ำวันพรุ่งนี้) */
function getTomorrowStr(): string {
  const d = new Date();
  d.setDate(d.getDate() + 1);
  return d.toISOString().slice(0, 10);
}

type PageMode = 'bulk' | 'paired';

interface PersonWithShift {
  id: string;
  display_name: string;
  shiftId: string;
  shift: Shift;
  startTime: string;
}

/** คู่ที่หัวหน้าเลือกเองได้ + ระบบกำหนดวันสลับภายในช่วง */
interface PairedRowWithDate {
  morningId: string;
  nightId: string;
  swapDate: string;
}

/** คนที่ไม่มีคู่ (เช้า/ดึกเหลือ) — สลับคนเดียว มีวันสลับและเลือกไปกะได้ */
interface SoloRowWithDate {
  userId: string;
  swapDate: string;
  toShiftId: string;
}

/** สร้างรายการวันที่ในช่วง [start, end] */
function getDatesInRange(start: string, end: string): string[] {
  const out: string[] = [];
  const d = new Date(start);
  const endD = new Date(end);
  while (d <= endD) {
    out.push(d.toISOString().slice(0, 10));
    d.setDate(d.getDate() + 1);
  }
  return out;
}

export default function MassShiftAssignment() {
  const { profile } = useAuth();
  const { branches, shifts } = useBranchesShifts();
  const isAdmin = profile?.role === 'admin';
  const isManager = profile?.role === 'manager';
  const isInstructorHead = profile?.role === 'instructor_head';
  const canAccess = isAdmin || isManager || isInstructorHead;

  const [employees, setEmployees] = useState<Profile[]>([]);
  const [filterBranchId, setFilterBranchId] = useState('');
  const [filterShiftId, setFilterShiftId] = useState('');
  const [search, setSearch] = useState('');
  const [searchInput, setSearchInput] = useState('');
  const searchDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => {
    const t = setTimeout(() => setSearch(searchInput), 300);
    searchDebounceRef.current = t;
    return () => clearTimeout(t);
  }, [searchInput]);
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [toShiftId, setToShiftId] = useState('');
  const [reason, setReason] = useState('');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [conflictSummary, setConflictSummary] = useState<ConflictSummary | null>(null);
  const [conflictMode, setConflictMode] = useState<BulkConflictMode>('SKIP_DAYS');
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<{ type: 'ok' | 'err'; text: string } | null>(null);

  const [pageMode, setPageMode] = useState<PageMode>('bulk');
  const [pairedMorningList, setPairedMorningList] = useState<PersonWithShift[]>([]);
  const [pairedNightList, setPairedNightList] = useState<PersonWithShift[]>([]);
  const [pairedRows, setPairedRows] = useState<PairedRowWithDate[]>([]);
  const [pairedMid, setPairedMid] = useState<PersonWithShift[]>([]);
  const [pairedBranchMorningShiftId, setPairedBranchMorningShiftId] = useState<string | null>(null);
  const [pairedBranchNightShiftId, setPairedBranchNightShiftId] = useState<string | null>(null);
  const [excludeFromSwap, setExcludeFromSwap] = useState<Set<string>>(new Set());
  const [midAssignTo, setMidAssignTo] = useState<Record<string, 'morning' | 'night' | 'stay'>>({});
  /** วันสลับของกะกลางแต่ละคน (มีวันที่สลับเหมือนคนอื่น) */
  const [midSwapDate, setMidSwapDate] = useState<Record<string, string>>({});
  /** วันหยุด/ลาของคนในคู่ (user_id -> Set<date>) ใช้ไม่เลือกวันสลับที่ชน และแสดงคำเตือน */
  const [pairedConflictMap, setPairedConflictMap] = useState<Record<string, Set<string>> | null>(null);
  /** คนไม่มีคู่ (เช้า/ดึกเหลือ) — สลับคนเดียว มีวันสลับและไปกะ */
  const [pairedSoloRows, setPairedSoloRows] = useState<SoloRowWithDate[]>([]);
  const [scheduledList, setScheduledList] = useState<ScheduledShiftChangeRecord[]>([]);
  const [editScheduled, setEditScheduled] = useState<{ record: ScheduledShiftChangeRecord; newDate: string; newToShiftId: string } | null>(null);
  const [confirmCancel, setConfirmCancel] = useState<ScheduledShiftChangeRecord | null>(null);

  const effectiveBranchForScheduled = filterBranchId || (isInstructorHead ? profile?.default_branch_id ?? '' : '');

  useEffect(() => {
    if (!canAccess) return;
    let q = supabase
      .from('profiles')
      .select('id, email, display_name, role, default_branch_id, default_shift_id, active')
      .eq('active', true)
      .in('role', [...EMPLOYEE_ROLES]);
    q.order('display_name').then(({ data }) => setEmployees((data || []) as Profile[]));
  }, [canAccess]);

  const filteredEmployees = useMemo(() => {
    return employees.filter((e) => {
      if (filterBranchId && e.default_branch_id !== filterBranchId) return false;
      if (filterShiftId && e.default_shift_id !== filterShiftId) return false;
      const term = search.trim().toLowerCase();
      if (term && !(e.display_name || '').toLowerCase().includes(term) && !(e.email || '').toLowerCase().includes(term)) return false;
      return true;
    });
  }, [employees, filterBranchId, filterShiftId, search]);

  /** ผู้ที่กำลังถูกตั้งเวลาย้ายกะอยู่ (มีรายการที่วันย้าย >= วันนี้) — ห้ามย้ายกะเพิ่มจนกว่าจะสิ้นสุดหรือยกเลิก */
  const scheduledActiveUserIds = useMemo(() => {
    const today = new Date().toISOString().slice(0, 10);
    return new Set(scheduledList.filter((r) => r.start_date >= today).map((r) => r.user_id));
  }, [scheduledList]);

  /** โหมด bulk: ไม่แสดงคนที่กำลังถูกตั้งเวลาย้ายกะอยู่ (กันชน + ป้องกันซ้อน) */
  const bulkExcludedUserIds = useMemo(
    () => new Set(scheduledActiveUserIds),
    [scheduledActiveUserIds]
  );

  /** โหมด bulk: รายชื่อหลังกรองและตัดคนที่ตั้งเวลาแล้วในวันย้าย */
  const bulkFilteredEmployees = useMemo(
    () => filteredEmployees.filter((e) => !bulkExcludedUserIds.has(e.id)),
    [filteredEmployees, bulkExcludedUserIds]
  );

  const removeOne = (id: string) => setSelectedIds((prev) => {
    const next = new Set(prev);
    next.delete(id);
    return next;
  });
  const toggleOne = (id: string) => setSelectedIds((prev) => {
    const next = new Set(prev);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    return next;
  });

  /** รายชื่อที่เลือกแล้ว เรียงตามชื่อ (แสดงฝั่งขวา) */
  const selectedEmployees = useMemo(() => {
    return Array.from(selectedIds)
      .map((id) => employees.find((e) => e.id === id))
      .filter((e): e is Profile => !!e)
      .sort((a, b) => (a.display_name || a.email || '').localeCompare(b.display_name || b.email || ''));
  }, [selectedIds, employees]);

  const selectAll = () => {
    const base = pageMode === 'bulk' ? bulkFilteredEmployees : filteredEmployees;
    setSelectedIds(new Set(base.map((e) => e.id)));
  };

  const clearSelection = () => {
    setSelectedIds(new Set());
  };

  const toggleExclude = (userId: string) => {
    setExcludeFromSwap((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
      return next;
    });
  };

  /** คนที่ถูกเลือกในคู่สลับแล้ว — ใช้ซิงค์รายการ realtime (ไม่โผล่ในคนสลับคนเดียว) */
  const pairedUsedInPairs = useMemo(() => {
    const set = new Set<string>();
    pairedRows.forEach((p) => {
      set.add(p.morningId);
      set.add(p.nightId);
    });
    return set;
  }, [pairedRows]);

  /** รายชื่อคนสลับคนเดียว (ไม่มีคู่) — ตัดคนที่ถูกเลือกไปจับคู่แล้ว ให้ข้อมูล realtime */
  const pairedSoloRowsFiltered = useMemo(
    () => pairedSoloRows.filter((s) => !pairedUsedInPairs.has(s.userId)),
    [pairedSoloRows, pairedUsedInPairs]
  );

  const runPairedAuto = async () => {
    const bid = filterBranchId || (isInstructorHead ? profile?.default_branch_id ?? '' : '');
    if (!bid || !startDate || !endDate || startDate > endDate) {
      setMessage({ type: 'err', text: 'กรุณาเลือกแผนก และช่วงวันที่ให้ถูกต้อง' });
      return;
    }
    setMessage(null);
    setLoading(true);
    try {
      const [rosterRes, profilesRes, scheduledForBranch] = await Promise.all([
        supabase
          .from('monthly_roster')
          .select('user_id, shift_id, work_date')
          .eq('branch_id', bid)
          .gte('work_date', startDate)
          .lte('work_date', endDate),
        supabase
          .from('profiles')
          .select('id, email, display_name, default_branch_id, default_shift_id')
          .eq('active', true)
          .in('role', [...EMPLOYEE_ROLES])
          .eq('default_branch_id', bid),
        listScheduledShiftChangesForBranch(bid),
      ]);
      const roster = (rosterRes.data || []) as { user_id: string; shift_id: string; work_date: string }[];
      const branchProfiles = (profilesRes.data || []) as Profile[];
      setScheduledList(scheduledForBranch);
      const today = new Date().toISOString().slice(0, 10);
      const excludedUserIds = new Set(
        scheduledForBranch
          .filter(
            (r) =>
              (r.start_date >= startDate && r.start_date <= endDate) || r.start_date >= today
          )
          .map((r) => r.user_id)
      );
      const userIdToShiftId = new Map<string, string>();
      roster.forEach((r) => {
        if (!userIdToShiftId.has(r.user_id)) userIdToShiftId.set(r.user_id, r.shift_id);
      });
      branchProfiles.forEach((p) => {
        if (!userIdToShiftId.has(p.id) && p.default_shift_id) userIdToShiftId.set(p.id, p.default_shift_id);
      });

      const morning: PersonWithShift[] = [];
      const mid: PersonWithShift[] = [];
      const night: PersonWithShift[] = [];
      let branchMorningShiftId: string | null = null;
      let branchNightShiftId: string | null = null;

      branchProfiles.forEach((p) => {
        if (excludedUserIds.has(p.id)) return;
        const shiftId = userIdToShiftId.get(p.id);
        if (!shiftId) return;
        const shift = shifts.find((s) => s.id === shiftId);
        if (!shift) return;
        const kind = getShiftKind(shift);
        const startTime = (shift.start_time || '').slice(0, 5) || '—';
        const row: PersonWithShift = {
          id: p.id,
          display_name: p.display_name || p.email || p.id,
          shiftId,
          shift,
          startTime,
        };
        if (kind === 'morning') {
          morning.push(row);
          if (!branchMorningShiftId) branchMorningShiftId = shiftId;
        } else if (kind === 'night') {
          night.push(row);
          if (!branchNightShiftId) branchNightShiftId = shiftId;
        } else if (kind === 'mid') {
          mid.push(row);
        }
      });

      const datesInRange = getDatesInRange(startDate, endDate);
      if (datesInRange.length === 0) {
        setMessage({ type: 'err', text: 'ช่วงวันที่ไม่ถูกต้อง' });
        setLoading(false);
        return;
      }
      const pairIds: PairedRowWithDate[] = [];
      const minLen = Math.min(morning.length, night.length);
      for (let i = 0; i < minLen; i++) {
        pairIds.push({
          morningId: morning[i].id,
          nightId: night[i].id,
          swapDate: datesInRange[i % datesInRange.length],
        });
      }
      const allIds = [...morning.map((m) => m.id), ...night.map((n) => n.id), ...mid.map((m) => m.id)];
      const { conflictMap } = await fetchHolidayConflicts(allIds, startDate, endDate, []);
      setPairedConflictMap(conflictMap);

      const usedOnDate = new Map<string, Set<string>>();
      const getUsed = (d: string) => {
        if (!usedOnDate.has(d)) usedOnDate.set(d, new Set());
        return usedOnDate.get(d)!;
      };
      const hasHoliday = (uid: string, d: string) => conflictMap[uid]?.has(d) ?? false;
      /** วันที่ทั้งคู่ไม่มีวันหยุด/ลา */
      const goodDatesForPair = (mid: string, nid: string) =>
        datesInRange.filter((d) => !hasHoliday(mid, d) && !hasHoliday(nid, d));
      /** วันที่คนเดียวไม่มีวันหยุด/ลา (ใช้กับคนไม่มีคู่และกะกลาง) */
      const goodDatesForOne = (uid: string) => datesInRange.filter((d) => !hasHoliday(uid, d));

      for (let i = 0; i < pairIds.length; i++) {
        const row = pairIds[i];
        getUsed(row.swapDate).add(row.morningId);
        getUsed(row.swapDate).add(row.nightId);
      }

      // ระบบไม่เลือกวันที่มีวันหยุด: ถ้าวันสลับเป็นวันหยุดของคนใดคนหนึ่ง ให้เปลี่ยนไปใช้วันที่ทั้งคู่ไม่มีวันหยุด
      for (let i = 0; i < pairIds.length; i++) {
        const row = pairIds[i];
        const d = row.swapDate;
        const badDate = hasHoliday(row.morningId, d) || hasHoliday(row.nightId, d);
        if (badDate) {
          const goodDates = goodDatesForPair(row.morningId, row.nightId)
            .sort((a, b) => getUsed(a).size - getUsed(b).size);
          if (goodDates.length > 0) {
            const newDate = goodDates[0];
            getUsed(d).delete(row.morningId);
            getUsed(d).delete(row.nightId);
            row.swapDate = newDate;
            getUsed(newDate).add(row.morningId);
            getUsed(newDate).add(row.nightId);
          }
        }
      }

      const shuffle = <T,>(arr: T[]): T[] => arr.slice().sort(() => Math.random() - 0.5);
      for (let i = 0; i < pairIds.length; i++) {
        const row = { ...pairIds[i] };
        const d = row.swapDate;
        const used = getUsed(d);
        if (hasHoliday(row.morningId, d)) {
          used.delete(row.morningId);
          const available = shuffle(morning.map((m) => m.id)).find(
            (id) => id !== row.nightId && !used.has(id) && !hasHoliday(id, d)
          );
          if (available) {
            row.morningId = available;
            used.add(available);
          } else {
            used.add(row.morningId);
          }
        }
        if (hasHoliday(row.nightId, d)) {
          used.delete(row.nightId);
          const available = shuffle(night.map((n) => n.id)).find(
            (id) => id !== row.morningId && !used.has(id) && !hasHoliday(id, d)
          );
          if (available) {
            row.nightId = available;
            used.add(available);
          } else {
            used.add(row.nightId);
          }
        }
        pairIds[i] = row;
      }
      setPairedMorningList(morning);
      setPairedNightList(night);
      setPairedRows(pairIds);
      setPairedMid(mid);
      setPairedBranchMorningShiftId(branchMorningShiftId);
      setPairedBranchNightShiftId(branchNightShiftId);
      setExcludeFromSwap(new Set());
      const stayMap: Record<string, 'morning' | 'night' | 'stay'> = {};
      const midDateMap: Record<string, string> = {};
      mid.forEach((m, i) => {
        stayMap[m.id] = 'stay';
        const goodDates = goodDatesForOne(m.id).sort((a, b) => getUsed(a).size - getUsed(b).size);
        const d = goodDates.length > 0 ? goodDates[0] : datesInRange[i % datesInRange.length];
        getUsed(d).add(m.id);
        midDateMap[m.id] = d;
      });
      setMidAssignTo(stayMap);
      setMidSwapDate(midDateMap);

      // คนไม่มีคู่ (เช้า/ดึกเหลือ) — ให้มีวันสลับและไปกะได้เหมือนกัน
      const soloRows: SoloRowWithDate[] = [];
      for (let i = minLen; i < morning.length; i++) {
        const p = morning[i];
        const goodDates = goodDatesForOne(p.id).sort((a, b) => getUsed(a).size - getUsed(b).size);
        const swapDate = goodDates.length > 0 ? goodDates[0] : datesInRange[i % datesInRange.length];
        getUsed(swapDate).add(p.id);
        soloRows.push({ userId: p.id, swapDate, toShiftId: p.shiftId });
      }
      for (let i = minLen; i < night.length; i++) {
        const p = night[i];
        const goodDates = goodDatesForOne(p.id).sort((a, b) => getUsed(a).size - getUsed(b).size);
        const swapDate = goodDates.length > 0 ? goodDates[0] : datesInRange[(minLen + i) % datesInRange.length];
        getUsed(swapDate).add(p.id);
        soloRows.push({ userId: p.id, swapDate, toShiftId: p.shiftId });
      }
      setPairedSoloRows(soloRows);

      setMessage({
        type: 'ok',
        text: `จับคู่แล้ว ${pairIds.length} คู่ (เช้า↔ดึก)${soloRows.length > 0 ? ` และ ${soloRows.length} คนสลับคนเดียว` : ''} — ระบบกำหนดวันสลับในช่วงให้แล้ว ตรวจวันหยุดแล้ว หัวหน้าแก้ไขวันสลับ/คู่ได้ แล้วกดยืนยัน`,
      });
    } catch (e) {
      setMessage({ type: 'err', text: e instanceof Error ? e.message : 'โหลดไม่สำเร็จ' });
    } finally {
      setLoading(false);
    }
  };

  const submitPaired = async () => {
    const bid = filterBranchId || (isInstructorHead ? profile?.default_branch_id ?? '' : '');
    if (!bid || !startDate || !endDate || startDate > endDate) {
      setMessage({ type: 'err', text: 'กรุณาเลือกแผนก และช่วงวันที่' });
      return;
    }
    const tomorrow = getTomorrowStr();
    if (startDate < tomorrow || endDate < tomorrow) {
      setMessage({ type: 'err', text: 'วันที่เริ่ม/สิ้นสุดต้องเป็นวันพรุ่งนี้ขึ้นไป (ตั้งได้ขั้นต่ำวันพรุ่งนี้)' });
      return;
    }
    const byDate = new Map<string, PairedSwapAssignment[]>();
    pairedRows.forEach((pair) => {
      const morning = pairedMorningList.find((m) => m.id === pair.morningId);
      const night = pairedNightList.find((n) => n.id === pair.nightId);
      if (!morning || !night) return;
      const morningEx = excludeFromSwap.has(morning.id);
      const nightEx = excludeFromSwap.has(night.id);
      const list = byDate.get(pair.swapDate) ?? [];
      if (!morningEx) list.push({ user_id: morning.id, to_shift_id: night.shiftId });
      if (!nightEx) list.push({ user_id: night.id, to_shift_id: morning.shiftId });
      byDate.set(pair.swapDate, list);
    });
    pairedSoloRowsFiltered.forEach((solo) => {
      const list = byDate.get(solo.swapDate) ?? [];
      list.push({ user_id: solo.userId, to_shift_id: solo.toShiftId });
      byDate.set(solo.swapDate, list);
    });
    const firstDate = pairedRows[0]?.swapDate ?? startDate;
    pairedMid.forEach((m) => {
      const assign = midAssignTo[m.id];
      const swapDate = midSwapDate[m.id] ?? firstDate;
      if (assign === 'morning' && pairedBranchMorningShiftId) {
        const list = byDate.get(swapDate) ?? [];
        list.push({ user_id: m.id, to_shift_id: pairedBranchMorningShiftId });
        byDate.set(swapDate, list);
      } else if (assign === 'night' && pairedBranchNightShiftId) {
        const list = byDate.get(swapDate) ?? [];
        list.push({ user_id: m.id, to_shift_id: pairedBranchNightShiftId });
        byDate.set(swapDate, list);
      }
    });
    let totalApplied = 0;
    let totalSkipped = 0;
    setMessage(null);
    setLoading(true);
    try {
      for (const [date, list] of byDate.entries()) {
        const deduped = list.reduce<PairedSwapAssignment[]>((acc, a) => {
          const idx = acc.findIndex((x) => x.user_id === a.user_id);
          if (idx >= 0) acc[idx] = a;
          else acc.push(a);
          return acc;
        }, []);
        if (deduped.length === 0) continue;
        const result = await applyPairedSwap(bid, date, date, deduped, reason.trim() || null);
        totalApplied += result.applied;
        totalSkipped += Object.keys(result.skipped_per_user).length;
      }
      if (totalApplied === 0 && totalSkipped === 0 && byDate.size === 0) {
        setMessage({ type: 'err', text: 'ไม่มีรายการที่จะย้าย — ล้าง "ไม่ย้าย" หรือเลือกไปเช้า/ดึก สำหรับกะกลาง' });
      } else {
        setMessage({
          type: 'ok',
          text: totalSkipped > 0
            ? `สลับกะแล้ว: อัปเดต ${totalApplied} คน; ข้าม ${totalSkipped} คน (วันหยุดหรือกำลังถูกตั้งเวลาย้ายกะอยู่)`
            : `สลับกะแล้ว: อัปเดต ${totalApplied} คน`,
        });
        setPairedMorningList([]);
        setPairedNightList([]);
        setPairedRows([]);
        setPairedMid([]);
        setPairedSoloRows([]);
        setPairedConflictMap(null);
        setExcludeFromSwap(new Set());
        setMidAssignTo({});
        setMidSwapDate({});
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'สลับกะจับคู่ไม่สำเร็จ';
      const text = msg.includes('START_DATE_MUST_BE_TOMORROW_OR_LATER')
        ? 'วันที่สลับต้องเป็นวันพรุ่งนี้ขึ้นไป'
        : msg.includes('SHIFT_CHANGE_OVERLAP_CONFLICT')
          ? 'มีผู้ใช้ในรายการที่มีย้ายกะ/สลับกะที่ยังมีผลอยู่ — กรุณายกเลิกหรือรอให้ครบก่อน'
          : msg;
      setMessage({ type: 'err', text });
    } finally {
      setLoading(false);
    }
  };

  const updatePairedPairMorning = (rowIndex: number, newMorningId: string) => {
    setPairedRows((prev) => {
      const next = [...prev];
      const oldId = next[rowIndex].morningId;
      if (oldId === newMorningId) return prev;
      next[rowIndex] = { ...next[rowIndex], morningId: newMorningId };
      const swapRow = next.findIndex((p, i) => i !== rowIndex && p.morningId === newMorningId);
      if (swapRow >= 0) next[swapRow] = { ...next[swapRow], morningId: oldId };
      return next;
    });
  };

  const updatePairedPairNight = (rowIndex: number, newNightId: string) => {
    setPairedRows((prev) => {
      const next = [...prev];
      const oldId = next[rowIndex].nightId;
      if (oldId === newNightId) return prev;
      next[rowIndex] = { ...next[rowIndex], nightId: newNightId };
      const swapRow = next.findIndex((p, i) => i !== rowIndex && p.nightId === newNightId);
      if (swapRow >= 0) next[swapRow] = { ...next[swapRow], nightId: oldId };
      return next;
    });
  };

  /** เมื่อเปลี่ยนคนในคู่ — ถ้าคนที่ถูกแทนที่ไม่ได้ไปอยู่คู่อื่น (สลับที่) ให้ไปโผล่ในคนสลับคนเดียว (realtime) */
  const handlePairedMorningChange = (rowIndex: number, newMorningId: string) => {
    const oldId = pairedRows[rowIndex]?.morningId;
    const willSwap = pairedRows.some((p, i) => i !== rowIndex && p.morningId === newMorningId);
    updatePairedPairMorning(rowIndex, newMorningId);
    if (oldId && oldId !== newMorningId && !willSwap) {
      const person = pairedMorningList.find((m) => m.id === oldId) || pairedNightList.find((n) => n.id === oldId);
      if (person && !pairedSoloRows.some((s) => s.userId === oldId)) {
        setPairedSoloRows((prev) => [...prev, { userId: oldId, swapDate: startDate, toShiftId: person.shiftId }]);
      }
    }
  };

  const handlePairedNightChange = (rowIndex: number, newNightId: string) => {
    const oldId = pairedRows[rowIndex]?.nightId;
    const willSwap = pairedRows.some((p, i) => i !== rowIndex && p.nightId === newNightId);
    updatePairedPairNight(rowIndex, newNightId);
    if (oldId && oldId !== newNightId && !willSwap) {
      const person = pairedNightList.find((n) => n.id === oldId) || pairedMorningList.find((m) => m.id === oldId);
      if (person && !pairedSoloRows.some((s) => s.userId === oldId)) {
        setPairedSoloRows((prev) => [...prev, { userId: oldId, swapDate: startDate, toShiftId: person.shiftId }]);
      }
    }
  };

  const updatePairedSwapDate = (rowIndex: number, newDate: string) => {
    setPairedRows((prev) => {
      const next = [...prev];
      if (next[rowIndex].swapDate === newDate) return prev;
      next[rowIndex] = { ...next[rowIndex], swapDate: newDate };
      return next;
    });
  };

  const updateSoloSwapDate = (rowIndex: number, newDate: string) => {
    setPairedSoloRows((prev) => {
      const next = [...prev];
      if (next[rowIndex].swapDate === newDate) return prev;
      next[rowIndex] = { ...next[rowIndex], swapDate: newDate };
      return next;
    });
  };

  const updateSoloToShift = (rowIndex: number, toShiftId: string) => {
    setPairedSoloRows((prev) => {
      const next = [...prev];
      next[rowIndex] = { ...next[rowIndex], toShiftId };
      return next;
    });
  };

  const updateMidSwapDate = (midId: string, newDate: string) => {
    setMidSwapDate((prev) => ({ ...prev, [midId]: newDate }));
  };

  /** แผนกปลายทาง = แผนกเดียวกัน (จากตัวกรอง หรือแผนกเดียวของคนที่เลือก) */
  const effectiveToBranchId = useMemo(() => {
    if (filterBranchId) return filterBranchId;
    const ids = Array.from(selectedIds);
    if (ids.length === 0) return null;
    const branchesOfSelected = ids.map((id) => employees.find((e) => e.id === id)?.default_branch_id).filter(Boolean);
    const first = branchesOfSelected[0];
    if (!first) return null;
    return branchesOfSelected.every((b) => b === first) ? first : null;
  }, [filterBranchId, selectedIds, employees]);

  const checkConflicts = async () => {
    const ids = Array.from(selectedIds);
    if (ids.length === 0) {
      setMessage({ type: 'err', text: 'กรุณาเลือกพนักงานอย่างน้อย 1 คน' });
      return;
    }
    if (!startDate) {
      setMessage({ type: 'err', text: 'กรุณาระบุวันที่ย้าย' });
      return;
    }
    setMessage(null);
    setLoading(true);
    try {
      const profilesForName = employees.filter((e) => ids.includes(e.id)).map((e) => ({ id: e.id, display_name: e.display_name ?? null }));
      const summary = await fetchHolidayConflicts(ids, startDate, startDate, profilesForName);
      setConflictSummary(summary);
    } catch (e) {
      setMessage({ type: 'err', text: e instanceof Error ? e.message : 'ตรวจสอบวันหยุดไม่สำเร็จ' });
      setConflictSummary(null);
    } finally {
      setLoading(false);
    }
  };

  const submitBulk = async () => {
    const ids = Array.from(selectedIds);
    if (ids.length === 0) {
      setMessage({ type: 'err', text: 'กรุณาเลือกพนักงานอย่างน้อย 1 คน' });
      return;
    }
    if (!startDate || !toShiftId) {
      setMessage({ type: 'err', text: 'กรุณาระบุวันที่ย้าย และกะปลายทาง' });
      return;
    }
    const tomorrow = getTomorrowStr();
    if (startDate < tomorrow) {
      setMessage({ type: 'err', text: 'วันที่ย้ายต้องเป็นวันพรุ่งนี้ขึ้นไป (ตั้งได้ขั้นต่ำวันพรุ่งนี้)' });
      return;
    }
    if (!effectiveToBranchId) {
      setMessage({ type: 'err', text: 'กรุณาเลือกแผนกต้นทาง (กรอง) หรือเลือกพนักงานจากแผนกเดียวกันเท่านั้น' });
      return;
    }
    if (conflictMode === 'BLOCK_ALL' && conflictSummary && conflictSummary.employeesWithConflicts > 0) {
      setMessage({
        type: 'err',
        text: `มีวันหยุดชน ${conflictSummary.employeesWithConflicts} คน กรณี BLOCK_ALL ไม่สามารถดำเนินการได้ กรุณาเปลี่ยนเป็น SKIP_DAYS หรือยกเลิกวันหยุดที่ชน`,
      });
      return;
    }
    setMessage(null);
    setLoading(true);
    try {
      const result = await applyBulkAssignment(ids, startDate, startDate, effectiveToBranchId, toShiftId, reason.trim() || null);
      const skippedCount = Object.keys(result.skipped_per_user).length;
      setMessage({
        type: 'ok',
        text: skippedCount > 0
          ? `ดำเนินการแล้ว: ย้ายกะ ${result.applied} คน (วันเดียว); ข้าม ${skippedCount} คน (วันหยุดหรือกำลังถูกตั้งเวลาย้ายกะอยู่)`
          : `ดำเนินการแล้ว: ย้ายกะ ${result.applied} คน (วันเดียว)`,
      });
      setConflictSummary(null);
      setSelectedIds(new Set());
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'ย้ายกะจำนวนมากไม่สำเร็จ';
      const text = msg.includes('START_DATE_MUST_BE_TOMORROW_OR_LATER')
        ? 'วันที่ย้ายต้องเป็นวันพรุ่งนี้ขึ้นไป'
        : msg.includes('SHIFT_CHANGE_OVERLAP_CONFLICT')
          ? 'มีผู้ใช้ในรายการที่มีย้ายกะ/สลับกะที่ยังมีผลอยู่ — กรุณายกเลิกหรือรอให้ครบก่อน'
          : msg;
      setMessage({ type: 'err', text });
    } finally {
      setLoading(false);
    }
  };

  const branchOptions = branches;

  const blockSubmit = conflictMode === 'BLOCK_ALL' && conflictSummary != null && conflictSummary.employeesWithConflicts > 0;
  const effectiveBranchForPaired = filterBranchId || (isInstructorHead ? profile?.default_branch_id ?? '' : '');

  useEffect(() => {
    if (!effectiveBranchForScheduled) {
      setScheduledList([]);
      return;
    }
    listScheduledShiftChangesForBranch(effectiveBranchForScheduled).then(setScheduledList);
  }, [effectiveBranchForScheduled]);

  if (!canAccess) {
    return (
      <div className="text-gray-400">
        เฉพาะผู้ดูแลระบบ / ผู้จัดการ / หัวหน้าพนักงานประจำ เท่านั้น
      </div>
    );
  }

  const refreshScheduledList = () => {
    if (effectiveBranchForScheduled) listScheduledShiftChangesForBranch(effectiveBranchForScheduled).then(setScheduledList);
  };

  const handleCancelScheduled = async (r: ScheduledShiftChangeRecord) => {
    setMessage(null);
    const res = await cancelScheduledShiftChange(r.type, r.id);
    if (res.ok) {
      setMessage({ type: 'ok', text: 'ยกเลิกการตั้งเวลาย้ายกะแล้ว' });
      setConfirmCancel(null);
      refreshScheduledList();
    } else {
      setMessage({ type: 'err', text: res.error ?? 'ยกเลิกไม่สำเร็จ' });
    }
  };

  const handleUpdateScheduled = async () => {
    if (!editScheduled) return;
    if (
      editScheduled.record.type === 'swap' &&
      editScheduled.newToShiftId === editScheduled.record.from_shift_id
    ) {
      setMessage({ type: 'err', text: 'ไม่สามารถแก้เป็นกะเดิมได้ หากไม่ต้องการย้ายกะแล้วให้ยกเลิกรายการแทน' });
      return;
    }
    setMessage(null);
    const res = await updateScheduledShiftChange(
      editScheduled.record.type,
      editScheduled.record.id,
      editScheduled.newDate,
      editScheduled.newToShiftId || null
    );
    if (res.ok) {
      setMessage({ type: 'ok', text: 'แก้ไขการตั้งเวลาย้ายกะแล้ว' });
      setEditScheduled(null);
      refreshScheduledList();
    } else {
      setMessage({ type: 'err', text: res.error ?? 'แก้ไขไม่สำเร็จ' });
    }
  };

  const getShiftName = (id: string) => shifts.find((s) => s.id === id)?.name ?? id.slice(0, 8);
  const getStaffName = (userId: string) => employees.find((e) => e.id === userId)?.display_name || employees.find((e) => e.id === userId)?.email || userId.slice(0, 8);
  const editScheduledIsSameShiftSwap = !!editScheduled
    && editScheduled.record.type === 'swap'
    && editScheduled.newToShiftId === editScheduled.record.from_shift_id;

  const movableCount = conflictSummary ? conflictSummary.totalSelected - conflictSummary.employeesWithConflicts : null;
  const blockedCount = conflictSummary?.employeesWithConflicts ?? null;
  const bulkSubmitLabel = blockSubmit ? 'มีวันหยุดชน' : selectedEmployees.length === 0 ? 'เลือกพนักงาน' : 'ย้ายที่เลือก';

  const minDate = useMemo(() => getTomorrowStr(), []);

  return (
    <div className="min-h-screen">
      <BulkMoveTopBar
        pageMode={pageMode}
        onPageModeChange={setPageMode}
        startDate={startDate}
        onStartDateChange={setStartDate}
        minDate={minDate}
        toShiftId={toShiftId}
        onToShiftIdChange={setToShiftId}
        reason={reason}
        onReasonChange={setReason}
        shifts={shifts}
        onMoveSelected={submitBulk}
        onClearSelection={clearSelection}
        onCheckHolidays={checkConflicts}
        loading={loading}
        totalCount={bulkFilteredEmployees.length}
        selectedCount={selectedEmployees.length}
        movableCount={conflictSummary ? movableCount ?? 0 : null}
        blockedCount={conflictSummary ? blockedCount : null}
        submitDisabled={blockSubmit || !toShiftId || !effectiveToBranchId || selectedEmployees.length === 0}
        submitLabel={bulkSubmitLabel}
      />

      <div className="px-4 md:px-5 pb-6">
      {/* รายการที่ตั้งเวลาแล้ว — หัวหน้ายกเลิกหรือแก้ไขได้ */}
      {effectiveBranchForScheduled && (
        <section className="mb-6 p-4 rounded-xl border border-premium-gold/10 bg-premium-darker/30">
          <h2 className="text-premium-gold/90 font-medium mb-2">รายการที่ตั้งเวลาแล้ว</h2>
          <p className="text-gray-400 text-xs mb-3">ยกเลิกหรือแก้ไขได้ถ้าตั้งผิด — ตารางวันหยุดและแดชบอร์ดพนักงานจะอัปเดตตาม</p>
          {scheduledList.length === 0 ? (
            <p className="text-gray-500 text-sm">ยังไม่มีรายการตั้งเวลาย้ายกะในแผนกนี้</p>
          ) : (
            <div className="overflow-x-auto border border-premium-gold/20 rounded-lg max-h-56 overflow-y-auto">
              <table className="w-full text-sm">
                <thead className="bg-premium-dark/80 sticky top-0">
                  <tr>
                    <th className="text-left py-2 px-2">ชื่อ</th>
                    <th className="text-left py-2 px-2">วันที่</th>
                    <th className="text-left py-2 px-2">จากกะ → กะปลายทาง</th>
                    <th className="text-left py-2 px-2 w-24">ประเภท</th>
                    <th className="text-left py-2 px-2 w-20">ดำเนินการ</th>
                  </tr>
                </thead>
                <tbody>
                  {scheduledList.map((r) => (
                    <tr key={`${r.type}-${r.id}`} className="border-t border-premium-gold/10">
                      <td className="py-1.5 px-2">{getStaffName(r.user_id)}</td>
                      <td className="py-1.5 px-2">{r.start_date}</td>
                      <td className="py-1.5 px-2 text-gray-300">{getShiftName(r.from_shift_id)} → {getShiftName(r.to_shift_id)}</td>
                      <td className="py-1.5 px-2 text-gray-400">{r.type === 'swap' ? 'สลับกะ' : 'ย้ายแผนก'}</td>
                      <td className="py-1.5 px-2">
                        <div className="flex items-center gap-1">
                          <BtnEdit title="แก้ไข" onClick={() => setEditScheduled({ record: r, newDate: r.start_date, newToShiftId: r.to_shift_id })} />
                          <BtnCancel title="ยกเลิก" onClick={() => setConfirmCancel(r)} />
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      )}

      {pageMode === 'paired' ? (
        <div className="grid gap-6 max-w-4xl">
          <>
            <section className="bg-premium-darker/50 rounded-xl p-4 border border-premium-gold/20">
              <h2 className="text-premium-gold/90 font-medium mb-3">ช่วงและแผนก</h2>
              <p className="text-gray-400 text-xs mb-1">เลือกแผนกและช่วงวันที่ แล้วกด &quot;โหลดและจับคู่อัตโนมัติ&quot; — ระบบจะ<strong>จัดทังกะในแผนก</strong>: จับคู่กะเช้า↔ดึก และคำนวณวันสลับภายในช่วงที่กำหนด <strong>คนที่ไม่มีคู่</strong>จะแสดงใน &quot;คนสลับคนเดียว&quot; กะกลางมีวันสลับแยกต่อคน ตรวจวันหยุดแล้ว <strong>คนที่อยู่ในรายการที่ตั้งเวลาแล้วในช่วงนี้จะไม่โผล่ในจับคู่ (กันช้ำซ้อน)</strong></p>
              <div className="flex flex-wrap gap-4 items-end">
                <div>
                  <label className="block text-gray-400 text-sm mb-1">แผนก <span className="text-amber-400">*</span></label>
                  <select
                    value={filterBranchId}
                    onChange={(e) => setFilterBranchId(e.target.value)}
                    className="bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white min-w-[160px]"
                  >
                    <option value="">-- เลือกแผนก --</option>
                    {branchOptions.map((b) => (
                      <option key={b.id} value={b.id}>{b.name}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="block text-gray-400 text-sm mb-1">วันที่เริ่ม</label>
                  <input type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} min={minDate} title="ตั้งได้ขั้นต่ำวันพรุ่งนี้" className="bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white" />
                </div>
                <div>
                  <label className="block text-gray-400 text-sm mb-1">วันที่สิ้นสุด</label>
                  <input type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} min={minDate} title="ตั้งได้ขั้นต่ำวันพรุ่งนี้" className="bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white" />
                </div>
                <div>
                  <label className="block text-gray-400 text-sm mb-1">เหตุผล (ถ้ามี)</label>
                  <input type="text" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="เหตุผล" className="bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white min-w-[140px]" />
                </div>
                <Button onClick={runPairedAuto} loading={loading} variant="gold">โหลดและจับคู่อัตโนมัติ</Button>
              </div>
            </section>

            {pairedRows.length > 0 || pairedMid.length > 0 || pairedSoloRowsFiltered.length > 0 ? (
              <>
                {pairedRows.length > 0 && (
                  <section className="bg-premium-darker/50 rounded-xl p-4 border border-premium-gold/20">
                    <h2 className="text-premium-gold/90 font-medium mb-2">คู่สลับ กะเช้า ↔ กะดึก</h2>
                    <p className="text-gray-400 text-xs mb-3">หัวหน้าแก้ไขคู่/วันสลับได้ · ติ๊ก &quot;ไม่ย้าย&quot; ถ้าอยู่กะเดิมได้ (ช้ำกะ)</p>
                    <div className="overflow-x-auto border border-premium-gold/20 rounded-lg max-h-72 overflow-y-auto">
                      <table className="w-full text-sm">
                        <thead className="bg-premium-dark/80 sticky top-0">
                          <tr>
                            <th className="text-left py-2 px-2">กะเช้า (เลือกคน · เวลาเริ่มกะ)</th>
                            <th className="text-left py-2 px-2 w-24">ไม่ย้าย</th>
                            <th className="text-left py-2 px-2">กะดึก (เลือกคน · เวลาเริ่มกะ)</th>
                            <th className="text-left py-2 px-2 w-24">ไม่ย้าย</th>
                            <th className="text-left py-2 px-2">วันสลับ</th>
                          </tr>
                        </thead>
                        <tbody>
                          {pairedRows.map((pair, idx) => {
                            const morning = pairedMorningList.find((m) => m.id === pair.morningId);
                            const night = pairedNightList.find((n) => n.id === pair.nightId);
                            return (
                              <tr key={idx} className="border-t border-premium-gold/10">
                                <td className="py-2 px-2">
                                  <select
                                    value={pair.morningId}
                                    onChange={(e) => handlePairedMorningChange(idx, e.target.value)}
                                    className="bg-premium-dark border border-premium-gold/30 rounded px-2 py-1 text-white text-sm w-full max-w-[180px]"
                                  >
                                    {pairedMorningList.map((m) => (
                                      <option key={m.id} value={m.id}>{m.display_name} · {m.startTime}</option>
                                    ))}
                                  </select>
                                </td>
                                <td className="py-2 px-2">
                                  {morning && (
                                    <label className="flex items-center gap-1">
                                      <input type="checkbox" checked={excludeFromSwap.has(morning.id)} onChange={() => toggleExclude(morning.id)} className="rounded border-premium-gold/40" />
                                      <span className="text-xs text-gray-400">ไม่ย้าย</span>
                                    </label>
                                  )}
                                </td>
                                <td className="py-2 px-2">
                                  <select
                                    value={pair.nightId}
                                    onChange={(e) => handlePairedNightChange(idx, e.target.value)}
                                    className="bg-premium-dark border border-premium-gold/30 rounded px-2 py-1 text-white text-sm w-full max-w-[180px]"
                                  >
                                    {pairedNightList.map((n) => (
                                      <option key={n.id} value={n.id}>{n.display_name} · {n.startTime}</option>
                                    ))}
                                  </select>
                                </td>
                                <td className="py-2 px-2">
                                  {night && (
                                    <label className="flex items-center gap-1">
                                      <input type="checkbox" checked={excludeFromSwap.has(night.id)} onChange={() => toggleExclude(night.id)} className="rounded border-premium-gold/40" />
                                      <span className="text-xs text-gray-400">ไม่ย้าย</span>
                                    </label>
                                  )}
                                </td>
                                <td className="py-2 px-2">
                                  <div>
                                    <input
                                      type="date"
                                      value={pair.swapDate}
                                      onChange={(e) => updatePairedSwapDate(idx, e.target.value)}
                                      min={startDate}
                                      max={endDate}
                                      className="bg-premium-dark border border-premium-gold/30 rounded px-2 py-1 text-white text-sm"
                                    />
                                    {pairedConflictMap && (pairedConflictMap[pair.morningId]?.has(pair.swapDate) || pairedConflictMap[pair.nightId]?.has(pair.swapDate)) && (
                                      <p className="text-amber-400 text-xs mt-0.5">วันนี้มีวันหยุด/ลาของคู่สลับ — ระบบจะไม่ย้ายกะวันนี้</p>
                                    )}
                                  </div>
                                </td>
                              </tr>
                            );
                          })}
                        </tbody>
                      </table>
                    </div>
                  </section>
                )}

                {pairedSoloRowsFiltered.length > 0 && (
                  <section className="bg-premium-darker/50 rounded-xl p-4 border border-premium-gold/20">
                    <h2 className="text-premium-gold/90 font-medium mb-2">คนสลับคนเดียว (ไม่มีคู่)</h2>
                    <p className="text-gray-400 text-xs mb-3">คนที่เหลือจากจับคู่เช้า↔ดึก — กำหนดวันสลับและเลือกไปกะได้ (หรืออยู่กะเดิม)</p>
                    <div className="overflow-x-auto border border-premium-gold/20 rounded-lg max-h-64 overflow-y-auto">
                      <table className="w-full text-sm">
                        <thead className="bg-premium-dark/80 sticky top-0">
                          <tr>
                            <th className="text-left py-2 px-2">ชื่อ</th>
                            <th className="text-left py-2 px-2">กะปัจจุบัน</th>
                            <th className="text-left py-2 px-2">วันสลับ</th>
                            <th className="text-left py-2 px-2">ไปกะ</th>
                          </tr>
                        </thead>
                        <tbody>
                          {pairedSoloRowsFiltered.map((solo) => {
                            const realIdx = pairedSoloRows.findIndex((s) => s.userId === solo.userId);
                            if (realIdx < 0) return null;
                            const person = pairedMorningList.find((m) => m.id === solo.userId) ?? pairedNightList.find((n) => n.id === solo.userId);
                            if (!person) return null;
                            const shiftName = person.shift?.name ?? '-';
                            return (
                              <tr key={solo.userId} className="border-t border-premium-gold/10">
                                <td className="py-2 px-2 font-medium text-gray-100">{person.display_name}</td>
                                <td className="py-2 px-2 text-gray-400">{shiftName} ({person.startTime})</td>
                                <td className="py-2 px-2">
                                  <input
                                    type="date"
                                    value={solo.swapDate}
                                    onChange={(e) => updateSoloSwapDate(realIdx, e.target.value)}
                                    min={startDate}
                                    max={endDate}
                                    className="bg-premium-dark border border-premium-gold/30 rounded px-2 py-1 text-white text-sm"
                                  />
                                  {pairedConflictMap?.[solo.userId]?.has(solo.swapDate) && (
                                    <p className="text-amber-400 text-xs mt-0.5">วันนี้มีวันหยุด/ลา — ระบบจะไม่ย้ายกะวันนี้</p>
                                  )}
                                </td>
                                <td className="py-2 px-2">
                                  <select
                                    value={solo.toShiftId}
                                    onChange={(e) => updateSoloToShift(realIdx, e.target.value)}
                                    className="bg-premium-dark border border-premium-gold/30 rounded px-2 py-1 text-white text-sm"
                                  >
                                    <option value={person.shiftId}>อยู่กะเดิม ({shiftName})</option>
                                    {pairedBranchMorningShiftId && person.shiftId !== pairedBranchMorningShiftId && (
                                      <option value={pairedBranchMorningShiftId}>กะเช้า</option>
                                    )}
                                    {pairedBranchNightShiftId && person.shiftId !== pairedBranchNightShiftId && (
                                      <option value={pairedBranchNightShiftId}>กะดึก</option>
                                    )}
                                  </select>
                                </td>
                              </tr>
                            );
                          })}
                        </tbody>
                      </table>
                    </div>
                  </section>
                )}

                {pairedMid.length > 0 && (
                  <section className="bg-premium-darker/50 rounded-xl p-4 border border-premium-gold/20">
                    <h2 className="text-premium-gold/90 font-medium mb-2">กะกลาง — เลือกไปเช้าหรือดึก</h2>
                    <p className="text-gray-400 text-xs mb-3">มีวันสลับแยกต่อคน แก้ไขได้</p>
                    <div className="overflow-x-auto border border-premium-gold/20 rounded-lg">
                      <table className="w-full text-sm">
                        <thead className="bg-premium-dark/80">
                          <tr>
                            <th className="text-left py-2 px-2">ชื่อ</th>
                            <th className="text-left py-2 px-2">กะปัจจุบัน (เวลาเริ่ม)</th>
                            <th className="text-left py-2 px-2">วันสลับ</th>
                            <th className="text-left py-2 px-2">ไปกะ</th>
                          </tr>
                        </thead>
                        <tbody>
                          {pairedMid.map((m) => (
                            <tr key={m.id} className="border-t border-premium-gold/10">
                              <td className="py-2 px-2 text-white">{m.display_name}</td>
                              <td className="py-2 px-2 text-gray-400">{m.shift.name} ({m.startTime})</td>
                              <td className="py-2 px-2">
                                <input
                                  type="date"
                                  value={midSwapDate[m.id] ?? startDate}
                                  onChange={(e) => updateMidSwapDate(m.id, e.target.value)}
                                  min={startDate}
                                  max={endDate}
                                  className="bg-premium-dark border border-premium-gold/30 rounded px-2 py-1 text-white text-sm"
                                />
                                {pairedConflictMap?.[m.id]?.has(midSwapDate[m.id] ?? startDate) && (
                                  <p className="text-amber-400 text-xs mt-0.5">วันนี้มีวันหยุด/ลา</p>
                                )}
                              </td>
                              <td className="py-2 px-2">
                                <select
                                  value={midAssignTo[m.id] ?? 'stay'}
                                  onChange={(e) => setMidAssignTo((prev) => ({ ...prev, [m.id]: e.target.value as 'morning' | 'night' | 'stay' }))}
                                  className="bg-premium-dark border border-premium-gold/30 rounded px-2 py-1 text-white text-sm"
                                >
                                  <option value="stay">อยู่กะกลาง (ไม่ย้าย)</option>
                                  <option value="morning">ไปกะเช้า</option>
                                  <option value="night">ไปกะดึก</option>
                                </select>
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </section>
                )}

                {message && <p className={message.type === 'ok' ? 'text-green-400' : 'text-red-400'}>{message.text}</p>}
                <div>
                  <Button onClick={submitPaired} loading={loading} disabled={!effectiveBranchForPaired || !startDate || !endDate || startDate > endDate} variant="gold">
                    ยืนยันสลับกะจับคู่
                  </Button>
                </div>
              </>
            ) : (
              <p className="text-gray-400 text-sm">เลือกแผนกและช่วงวันที่ แล้วกด &quot;โหลดและจับคู่อัตโนมัติ&quot;</p>
            )}
          </>
        </div>
      ) : (
        /* Bulk Transfer: dual-pane layout */
        <div className="w-full px-4 py-4 md:px-5">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 min-h-[calc(100vh-14rem)]">
            <div className="min-h-[320px] lg:min-h-0">
              <StaffTable
                staff={bulkFilteredEmployees}
                selectedIds={selectedIds}
                onToggleOne={toggleOne}
                onSelectAll={selectAll}
                onClearSelection={clearSelection}
                searchInput={searchInput}
                onSearchChange={setSearchInput}
                filterBranchId={filterBranchId}
                filterShiftId={filterShiftId}
                onFilterBranchChange={setFilterBranchId}
                onFilterShiftChange={setFilterShiftId}
                branchOptions={branchOptions}
                shiftOptions={shifts}
                conflictSummary={conflictSummary}
                transferDate={startDate}
                getBranchName={(id) => branches.find((b) => b.id === id)?.name ?? '—'}
                getShiftName={(id) => shifts.find((s) => s.id === id)?.name ?? '—'}
              />
            </div>
            <div className="min-h-[280px] lg:min-h-0">
              <SelectedCart
                selected={selectedEmployees}
                onRemoveOne={removeOne}
                onClearAll={clearSelection}
                onCheckHolidays={checkConflicts}
                loading={loading}
                conflictSummary={conflictSummary}
                conflictMode={conflictMode}
                onConflictModeChange={setConflictMode}
                transferDate={startDate}
                getBranchName={(id) => branches.find((b) => b.id === id)?.name ?? '—'}
                getShiftName={(id) => shifts.find((s) => s.id === id)?.name ?? '—'}
              />
            </div>
          </div>

          {message && <p className={`mt-4 text-[13px] ${message.type === 'ok' ? 'text-green-400' : 'text-red-400'}`}>{message.text}</p>}
        </div>
      )}
      </div>

      <ConfirmModal
        open={!!confirmCancel}
        onClose={() => setConfirmCancel(null)}
        onConfirm={async () => { if (confirmCancel) await handleCancelScheduled(confirmCancel); }}
        title="ยืนยันยกเลิกการตั้งเวลาย้ายกะ"
        message={confirmCancel ? `ยกเลิกการตั้งเวลาย้ายกะของ ${getStaffName(confirmCancel.user_id)} วันที่ ${confirmCancel.start_date}? ตารางกะและแดชบอร์ดจะอัปเดตตาม` : ''}
        confirmLabel="ยกเลิกการตั้งเวลา"
        cancelLabel="กลับ"
        variant="danger"
      />

      <Modal
        open={!!editScheduled}
        onClose={() => setEditScheduled(null)}
        title="แก้ไขการตั้งเวลาย้ายกะ"
        footer={
          <>
            <Button variant="ghost" onClick={() => setEditScheduled(null)}>ปิด</Button>
            <Button variant="gold" onClick={handleUpdateScheduled} disabled={!editScheduled?.newDate || editScheduledIsSameShiftSwap}>บันทึก</Button>
          </>
        }
      >
        {editScheduled && (
          <div className="space-y-3">
            <p className="text-gray-300 text-sm">{getStaffName(editScheduled.record.user_id)} — จากกะ {getShiftName(editScheduled.record.from_shift_id)} เป็นกะ {getShiftName(editScheduled.record.to_shift_id)}</p>
            <div>
              <label className="block text-gray-400 text-sm mb-1">วันที่ใหม่</label>
              <input
                type="date"
                value={editScheduled.newDate}
                onChange={(e) => setEditScheduled((prev) => prev ? { ...prev, newDate: e.target.value } : null)}
                className="bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white w-full"
              />
            </div>
            <div>
              <label className="block text-gray-400 text-sm mb-1">กะปลายทาง (ถ้าเปลี่ยน)</label>
              <select
                value={editScheduled.newToShiftId}
                onChange={(e) => setEditScheduled((prev) => prev ? { ...prev, newToShiftId: e.target.value } : null)}
                className="bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white w-full"
              >
                {shifts.map((s) => (
                  <option key={s.id} value={s.id}>{s.name}</option>
                ))}
              </select>
            </div>
            {editScheduledIsSameShiftSwap && (
              <p className="text-amber-300 text-sm">
                กะปลายทางตรงกับกะเดิมของรายการนี้แล้ว หากไม่ต้องการย้ายกะ ให้ยกเลิกรายการแทน
              </p>
            )}
          </div>
        )}
      </Modal>
    </div>
  );
}
