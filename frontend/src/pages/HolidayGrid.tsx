import { useState, useEffect, useMemo, useRef } from 'react';
import { format, startOfMonth, endOfMonth, getDaysInMonth, addMonths, subMonths } from 'date-fns';
import { th } from 'date-fns/locale';
import ExcelJS from 'exceljs';
import { supabase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import { getMyUserGroup } from '../lib/auth';
import { useBranchesShifts } from '../lib/BranchesShiftsContext';
import type { AppRole, Holiday, HolidayBookingConfig, HolidayQuotaDimension, HolidayQuotaTier, LeaveType, Profile } from '../lib/types';
import type { UserGroup } from '../lib/types';
import { getShiftKind, getShiftIcon, getShiftLabel, getShiftShortLabel, getShiftCellLetter, type ShiftKind } from '../lib/shiftIcons';
import Button from '../components/ui/Button';
import Modal, { ConfirmModal } from '../components/ui/Modal';
import { PageHeader } from '../components/layout';
import { logAudit } from '../lib/audit';
import { getScheduledShiftChangeDatesByUser, getEffectiveForStaffInMonth, type EffectiveBranchShift } from '../lib/transfers';

/** Admin / manager / instructor_head can create, update, delete holidays for ANY user (including self) and choose leave type. */
function isPrivilegedHolidayEditor(role: AppRole | undefined): boolean {
  return role === 'admin' || role === 'manager' || role === 'instructor_head';
}

export default function HolidayGrid() {
  const { user, profile } = useAuth();
  const { branches, shifts } = useBranchesShifts();
  const isAdmin = profile?.role === 'admin';
  const isInstructorHead = profile?.role === 'instructor_head';
  const isManager = profile?.role === 'manager';
  const isInstructor = profile?.role === 'instructor';
  const canManageHolidays = isPrivilegedHolidayEditor(profile?.role);
  const isGlobalViewer = ['admin', 'manager', 'instructor_head', 'instructor'].includes(profile?.role ?? '');
  const [branchId, setBranchId] = useState<string>('');
  const [shiftId, setShiftId] = useState<string>('');
  const [month, setMonth] = useState(() => format(new Date(), 'yyyy-MM'));
  const [holidays, setHolidays] = useState<Holiday[]>([]);
  const [staffList, setStaffList] = useState<Array<Pick<Profile, 'id' | 'email' | 'role' | 'default_branch_id' | 'default_shift_id'> & { display_name: string; primary_website_id?: string | null }>>([]);
  const [websites, setWebsites] = useState<Array<{ id: string; name: string; alias: string }>>([]);
  const [websiteFilter, setWebsiteFilter] = useState<string>('');
  const [searchName, setSearchName] = useState('');
  const [onlyMyData, setOnlyMyData] = useState(false);
  const [modal, setModal] = useState<{ type: 'request' | 'approve' | 'reject' | 'add_for' | 'edit_for' | 'remove_for'; date?: string; holiday?: Holiday; staffId?: string; staffName?: string } | null>(null);
  const [reason, setReason] = useState('');
  const [rejectReason, setRejectReason] = useState('');
  const [loading, setLoading] = useState(false);
  const [userGroupFilter, setUserGroupFilter] = useState<'' | UserGroup>('');
  const [shiftKindFilter, setShiftKindFilter] = useState<'' | ShiftKind>('');
  const [bookingConfig, setBookingConfig] = useState<HolidayBookingConfig | null>(null);
  const [quotaTiers, setQuotaTiers] = useState<HolidayQuotaTier[]>([]);
  const [scopeHolidayQuotaByWebsite, setScopeHolidayQuotaByWebsite] = useState<boolean>(true);
  const [globalMaxHolidayDaysPerMonth, setGlobalMaxHolidayDaysPerMonth] = useState<number | null>(null);
  const [leaveTypes, setLeaveTypes] = useState<LeaveType[]>([]);
  const [addEditLeaveType, setAddEditLeaveType] = useState<string>('X');
  const [addForExemptQuota, setAddForExemptQuota] = useState(false);
  const [myPrimaryWebsiteId, setMyPrimaryWebsiteId] = useState<string | null>(null);
  const [scheduledShiftChangeDatesByUser, setScheduledShiftChangeDatesByUser] = useState<Map<string, Map<string, { from_shift_id: string; to_shift_id: string }>>>(new Map());
  /** กะ/แผนกที่มีผลต่อวัน (จากย้ายกะ) — ใช้โควต้าวันหยุดและจองให้ตรงกับวันนั้น */
  const [effectiveByUserByDate, setEffectiveByUserByDate] = useState<Map<string, Map<string, EffectiveBranchShift>>>(new Map());
  const [hoverCol, setHoverCol] = useState<number | null>(null);
  const hasInitialBranch = useRef(false);
  const hasInitialShift = useRef(false);

  useEffect(() => {
    if (!user?.id) return;
    supabase.from('website_assignments').select('website_id').eq('user_id', user.id).eq('is_primary', true).maybeSingle().then(({ data }) => setMyPrimaryWebsiteId(data?.website_id ?? null));
  }, [user?.id]);

  useEffect(() => {
    if (modal?.type === 'add_for') setAddForExemptQuota(false);
  }, [modal?.type, modal?.staffId, modal?.date]);

  const myUserGroup = getMyUserGroup(profile);
  const canEditThisBranch = isAdmin || isManager || isInstructorHead;
  const canOnlySelfHoliday = isInstructor && !canEditThisBranch;
  const monthDate = useMemo(() => new Date(month + '-01'), [month]);
  const daysInMonth = getDaysInMonth(monthDate);
  const dayNumbers = Array.from({ length: daysInMonth }, (_, i) => i + 1);

  /** กะดึก = กะที่เลิกงานเป็นวันถัดไป — ใช้กับกติกา "วันเปลี่ยนกะดึก→อื่น = วันหยุดในตัว" */
  const isNightShiftId = useMemo(() => {
    return (shiftId: string) => getShiftKind(shifts.find((s) => s.id === shiftId)) === 'night';
  }, [shifts]);

  /** วันเปลี่ยนกะดึก→เช้า/กลาง: พนักงานไม่มาทำงานในวันนั้น (ถือเป็นวันหยุดในตัว) — ไม่นับในโควต้า */
  const changeRestDayUserIdsByDate = useMemo(() => {
    const map = new Map<string, Set<string>>();
    dayNumbers.forEach((day) => {
      const d = format(new Date(monthDate.getFullYear(), monthDate.getMonth(), day), 'yyyy-MM-dd');
      const set = new Set<string>();
      staffList.forEach((s) => {
        const change = scheduledShiftChangeDatesByUser.get(s.id)?.get(d);
        if (change && isNightShiftId(change.from_shift_id) && !isNightShiftId(change.to_shift_id)) set.add(s.id);
      });
      if (set.size) map.set(d, set);
    });
    return map;
  }, [staffList, scheduledShiftChangeDatesByUser, monthDate, dayNumbers, isNightShiftId]);

  useEffect(() => {
    if (!branches.length) return;
    if (hasInitialBranch.current) return;
    hasInitialBranch.current = true;
    setBranchId(isGlobalViewer ? '' : (profile?.default_branch_id || branches[0].id));
  }, [branches, isGlobalViewer, profile?.default_branch_id]);
  useEffect(() => {
    if (!shifts.length) return;
    if (hasInitialShift.current) return;
    hasInitialShift.current = true;
    setShiftId('');
  }, [shifts]);

  useEffect(() => {
    if (profile?.default_branch_id && !isGlobalViewer && branchId !== profile.default_branch_id) {
      setBranchId(profile.default_branch_id);
    }
  }, [profile?.default_branch_id, isGlobalViewer, branchId]);

  useEffect(() => {
    Promise.all([
      supabase.from('websites').select('id, name, alias').order('name').then(({ data }) => data || []),
      supabase.from('holiday_quota_tiers').select('id, dimension, user_group, max_people, max_leave, sort_order').order('dimension').order('user_group').order('max_people').then(({ data }) => (data || []) as HolidayQuotaTier[]),
      supabase.from('meal_settings').select('scope_holiday_quota_by_website, max_holiday_days_per_person_per_month').eq('is_enabled', true).order('effective_from', { ascending: false }).limit(1).maybeSingle().then(({ data }) => data as { scope_holiday_quota_by_website?: boolean; max_holiday_days_per_person_per_month?: number | null } | null),
      supabase.from('leave_types').select('code, name, color, description').order('code').then(({ data }) => (data || []) as LeaveType[]),
    ]).then(([websitesData, quotaData, mealRow, leaveData]) => {
      setWebsites(websitesData as Array<{ id: string; name: string; alias: string }>);
      setQuotaTiers(quotaData);
      setScopeHolidayQuotaByWebsite(mealRow?.scope_holiday_quota_by_website !== false);
      setGlobalMaxHolidayDaysPerMonth(mealRow?.max_holiday_days_per_person_per_month ?? null);
      setLeaveTypes(leaveData);
    });
  }, []);

  const effectiveBranchId = branchId || (isGlobalViewer ? null : (profile?.default_branch_id ?? null));

  /** Single RPC load for HolidayGrid: staff (minimal + primary_website_id) + holidays in month range. Request id guard to avoid applying stale result when deps change quickly */
  const holidayGridRequestIdRef = useRef(0);
  useEffect(() => {
    if (!effectiveBranchId && !isGlobalViewer) return;
    const requestId = ++holidayGridRequestIdRef.current;
    const start = format(startOfMonth(monthDate), 'yyyy-MM-dd');
    const end = format(endOfMonth(monthDate), 'yyyy-MM-dd');
    const onlyMyUserId = onlyMyData && user?.id ? user.id : null;
    supabase
      .rpc('rpc_holiday_grid', {
        p_month_start: start,
        p_month_end: end,
        p_branch_id: effectiveBranchId,
        p_only_my_user_id: onlyMyUserId,
      })
      .then(({ data, error }) => {
        if (requestId !== holidayGridRequestIdRef.current) return;
        if (error || !data?.[0]) {
          setStaffList([]);
          setHolidays([]);
          return;
        }
        const row = data[0] as { staff?: unknown[]; holidays?: unknown[] };
        const staff = Array.isArray(row.staff) ? row.staff : [];
        const staffListTyped = staff.map((s: unknown) => {
          const x = s as Record<string, unknown>;
          return {
            id: x.id as string,
            email: (x.email as string) ?? '',
            role: (x.role as AppRole) ?? 'staff',
            default_branch_id: (x.default_branch_id as string | null) ?? null,
            default_shift_id: (x.default_shift_id as string | null) ?? null,
            display_name: (x.display_name as string) ?? (x.email as string) ?? '',
            primary_website_id: (x.primary_website_id as string | null) ?? null,
          };
        });
        setStaffList(staffListTyped);
        const hol = Array.isArray(row.holidays) ? (row.holidays as Holiday[]) : [];
        setHolidays(hol);
      });
  }, [effectiveBranchId, month, onlyMyData, user?.id, isGlobalViewer, monthDate]);

  useEffect(() => {
    supabase.from('holiday_booking_config').select('id, target_year_month, open_from, open_until, max_days_per_person').eq('target_year_month', month).maybeSingle().then(({ data }) => setBookingConfig(data as HolidayBookingConfig | null));
  }, [month]);

  useEffect(() => {
    if (modal?.type === 'edit_for' && modal?.holiday) {
      setReason(modal.holiday.reason || '');
      setAddEditLeaveType(modal.holiday.leave_type || 'X');
    }
    if (modal?.type === 'add_for') {
      setReason('');
      setAddEditLeaveType('X');
    }
  }, [modal?.type, modal?.holiday?.id, modal?.staffId]);

  useEffect(() => {
    const start = format(startOfMonth(monthDate), 'yyyy-MM-dd');
    const end = format(endOfMonth(monthDate), 'yyyy-MM-dd');
    const ids = staffList.map((s) => s.id);
    if (ids.length === 0) {
      setScheduledShiftChangeDatesByUser(new Map());
      setEffectiveByUserByDate(new Map());
      return;
    }
    getScheduledShiftChangeDatesByUser(ids, start, end).then(setScheduledShiftChangeDatesByUser);
    const fallbacks = new Map(staffList.map((s) => [s.id, { branch_id: s.default_branch_id ?? null, shift_id: s.default_shift_id ?? null }]));
    const isNight = (shiftId: string) => getShiftKind(shifts.find((s) => s.id === shiftId)) === 'night';
    getEffectiveForStaffInMonth(ids, start, end, fallbacks, { isNightShiftId: isNight }).then(setEffectiveByUserByDate);
  }, [staffList, monthDate, shifts]);

  useEffect(() => {
    const start = format(startOfMonth(monthDate), 'yyyy-MM-dd');
    const end = format(endOfMonth(monthDate), 'yyyy-MM-dd');
    const ids = staffList.map((s) => s.id);
    if (ids.length === 0) return;
    let debounceTimer: ReturnType<typeof setTimeout> | null = null;
    const refresh = () => {
      if (debounceTimer) clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        debounceTimer = null;
        getScheduledShiftChangeDatesByUser(ids, start, end).then(setScheduledShiftChangeDatesByUser);
        const fallbacks = new Map(staffList.map((s) => [s.id, { branch_id: s.default_branch_id ?? null, shift_id: s.default_shift_id ?? null }]));
        const isNight = (shiftId: string) => getShiftKind(shifts.find((s) => s.id === shiftId)) === 'night';
        getEffectiveForStaffInMonth(ids, start, end, fallbacks, { isNightShiftId: isNight }).then(setEffectiveByUserByDate);
      }, 400);
    };
    const channel = supabase
      .channel('holiday-grid-shift-changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'shift_swaps' }, refresh)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'cross_branch_transfers' }, refresh)
      .subscribe();
    return () => {
      if (debounceTimer) clearTimeout(debounceTimer);
      supabase.removeChannel(channel);
    };
  }, [staffList, monthDate, shifts]);

  useEffect(() => {
    if (!effectiveBranchId && !isAdmin) return;
    const start = format(startOfMonth(monthDate), 'yyyy-MM-dd');
    const end = format(endOfMonth(monthDate), 'yyyy-MM-dd');
    let debounceTimer: ReturnType<typeof setTimeout> | null = null;
    const channel = supabase
      .channel('holidays-changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'holidays' }, () => {
        if (debounceTimer) clearTimeout(debounceTimer);
        debounceTimer = setTimeout(() => {
          debounceTimer = null;
          let q = supabase.from('holidays').select('id, user_id, branch_id, shift_id, holiday_date, status, reason, leave_type, user_group, is_quota_exempt, approved_by, approved_at, reject_reason, created_at, updated_at').gte('holiday_date', start).lte('holiday_date', end);
          if (effectiveBranchId) q = q.eq('branch_id', effectiveBranchId);
          if (onlyMyData && user?.id) q = q.eq('user_id', user.id);
          q.then(({ data }) => setHolidays(data || []));
        }, 300);
      })
      .subscribe();
    return () => {
      if (debounceTimer) clearTimeout(debounceTimer);
      supabase.removeChannel(channel);
    };
  }, [effectiveBranchId, month, monthDate, onlyMyData, user?.id, isAdmin]);

  /** พนักงานออนไลน์ (staff) เห็นทุกคนในแผนกเดียวกันเหมือนหัวหน้า (กะเช้า/ดึก/กลาง) เพื่อดูกะทำงานของเพื่อนในแผนก */
  const effectiveUserGroup = (isAdmin || isManager || isInstructorHead || isInstructor)
    ? (userGroupFilter || null)
    : (profile?.role === 'staff' ? null : (myUserGroup ?? (profile?.role === 'instructor_head' ? 'INSTRUCTOR' : null)));
  function getUserGroupFromRole(role: AppRole): UserGroup | null {
    if (role === 'instructor' || role === 'instructor_head') return 'INSTRUCTOR';
    if (role === 'staff') return 'STAFF';
    if (role === 'manager') return 'MANAGER';
    return null;
  }

  const displayHolidays = useMemo(() => {
    if (!effectiveUserGroup) return holidays;
    return holidays.filter((h) => h.user_group === effectiveUserGroup);
  }, [holidays, effectiveUserGroup]);

  const leaveTypesMap = useMemo(() => {
    const m: Record<string, LeaveType> = {};
    leaveTypes.forEach((lt) => { m[lt.code] = lt; });
    if (!m.X) m.X = { code: 'X', name: 'วันหยุด', color: '#9CA3AF', description: null };
    return m;
  }, [leaveTypes]);

  const filteredStaff = useMemo(() => {
    let list = staffList;
    if (effectiveUserGroup) list = list.filter((s) => getUserGroupFromRole(s.role) === effectiveUserGroup);
    if (searchName.trim()) {
      const q = searchName.trim().toLowerCase();
      list = list.filter((s) => (s.display_name || s.email).toLowerCase().includes(q));
    } else {
      if (!onlyMyData && shiftId) list = list.filter((s) => s.default_shift_id === shiftId);
      if (websiteFilter) list = list.filter((s) => s.primary_website_id === websiteFilter);
    }
    if (shiftKindFilter && list.length > 0) {
      list = list.filter((s) => {
        const shift = shifts.find((x) => x.id === s.default_shift_id);
        return getShiftKind(shift) === shiftKindFilter;
      });
    }
    return list;
  }, [staffList, effectiveUserGroup, shiftId, websiteFilter, searchName, onlyMyData, shiftKindFilter, shifts]);

  /** ชื่อแสดงรูปแบบ แผนก-ชื่อที่แสดง (เช่น AM-AA) — หัวหน้าต่อท้าย -TT (เช่น FT-JUKI-TT) */
  const getDisplayLabel = (s: { default_branch_id: string | null; display_name: string; email: string; role?: string }) => {
    const branchName = branches.find((b) => b.id === s.default_branch_id)?.name ?? '—';
    const base = `${branchName}-${s.display_name || s.email}`;
    return s.role === 'instructor_head' ? `${base}-TT` : base;
  };

  /** ลำดับ role สำหรับเรียง: ผู้จัดการบนสุด ถัดไปหัวหน้า แล้วพนักงาน (กลุ่มเดียวกัน แผนกเดียวกัน กะเดียวกัน) */
  const getRoleSortOrder = (role: AppRole): number => {
    switch (role) {
      case 'manager': return 0;
      case 'instructor_head': return 1;
      case 'instructor': return 2;
      case 'staff': return 3;
      default: return 4;
    }
  };

  /** ลำดับ user_group สำหรับเรียงกลุ่มเดียวกัน (INSTRUCTOR ก่อน STAFF) */
  const getUserGroupSortKey = (role: AppRole): string => {
    const g = getUserGroupFromRole(role);
    if (g === 'INSTRUCTOR') return '0';
    if (g === 'STAFF') return '1';
    if (g === 'MANAGER') return '';
    return '2';
  };

  /** เรียงตาม กลุ่ม(role) → แผนกเดียวกัน → กะเดียวกัน → กลุ่ม(user_group): ผู้จัดการบนสุด ถัดไปหัวหน้า+พนักงานที่อยู่แผนก+กะเดียวกัน */
  const sortedStaff = useMemo(() => {
    const list = [...filteredStaff];
    list.sort((a, b) => {
      const roleOrderA = getRoleSortOrder(a.role);
      const roleOrderB = getRoleSortOrder(b.role);
      if (roleOrderA !== roleOrderB) return roleOrderA - roleOrderB;
      const branchA = branches.find((x) => x.id === a.default_branch_id)?.name ?? '\uffff';
      const branchB = branches.find((x) => x.id === b.default_branch_id)?.name ?? '\uffff';
      if (branchA !== branchB) return branchA.localeCompare(branchB);
      const shiftA = shifts.find((x) => x.id === a.default_shift_id)?.name ?? '\uffff';
      const shiftB = shifts.find((x) => x.id === b.default_shift_id)?.name ?? '\uffff';
      if (shiftA !== shiftB) return shiftA.localeCompare(shiftB);
      const groupA = getUserGroupSortKey(a.role);
      const groupB = getUserGroupSortKey(b.role);
      if (groupA !== groupB) return groupA.localeCompare(groupB);
      return getDisplayLabel(a).localeCompare(getDisplayLabel(b));
    });
    return list;
  }, [filteredStaff, branches, shifts]);

  /** สมาชิกในแผนกนี้ที่ยังไม่มีกะ (จะไม่แสดงในตารางจนกว่าจะกำหนดกะ) */
  const staffWithoutShiftInBranch = useMemo(() => {
    if (onlyMyData) return 0;
    return staffList.filter((s) => (s.role === 'instructor' || s.role === 'staff') && !s.default_shift_id).length;
  }, [staffList, onlyMyData]);

  const getHoliday = (userId: string, day: number) => {
    const d = format(new Date(monthDate.getFullYear(), monthDate.getMonth(), day), 'yyyy-MM-dd');
    return displayHolidays.find((h) => h.user_id === userId && h.holiday_date === d);
  };

  /** โควต้าวันหยุด: เมื่อหลาย tier ตรง (totalPeople <= max_people) ให้ใช้ค่าที่จำกัดที่สุด = MIN(max_leave) (เหมือนโควต้าพักอาหาร) */
  function getMaxLeaveFromTiers(dimension: HolidayQuotaDimension, group: UserGroup, totalPeople: number): number {
    if (dimension === 'combined') {
      const tiers = quotaTiers.filter(
        (t) => t.dimension === 'combined' && (t.user_group === group || t.user_group == null)
      );
      const matching = tiers.filter((t) => totalPeople <= t.max_people);
      if (matching.length === 0) return 0;
      const withBestSpec = matching.some((t) => t.user_group != null)
        ? matching.filter((t) => t.user_group === group)
        : matching;
      return Math.min(...withBestSpec.map((t) => t.max_leave));
    }
    const tiers = quotaTiers.filter((t) => t.dimension === dimension && t.user_group === group);
    const matching = tiers.filter((t) => totalPeople <= t.max_people);
    if (matching.length === 0) return 0;
    return Math.min(...matching.map((t) => t.max_leave));
  }

  /** คนในขอบเขตรวม: แผนก+กะ+กลุ่ม (+เว็บถ้าเปิด) — ใช้กับโควตาแบบ combined */
  const staffInScope = useMemo(() => {
    if (!effectiveUserGroup || !effectiveBranchId) return [];
    return staffList.filter(
      (s) =>
        s.default_branch_id === effectiveBranchId &&
        s.default_shift_id === shiftId &&
        getUserGroupFromRole(s.role) === effectiveUserGroup &&
        (!scopeHolidayQuotaByWebsite || s.primary_website_id === myPrimaryWebsiteId)
    );
  }, [staffList, effectiveUserGroup, effectiveBranchId, shiftId, scopeHolidayQuotaByWebsite, myPrimaryWebsiteId]);

  const scopeStaffIds = useMemo(() => new Set(staffInScope.map((s) => s.id)), [staffInScope]);

  const totalsForGroup = useMemo(() => {
    if (!effectiveUserGroup) return { branch: 0, shift: 0, website: 0, combined: 0 };
    const withGroup = staffList.filter((s) => getUserGroupFromRole(s.role) === effectiveUserGroup);
    return {
      branch: withGroup.length,
      shift: shiftId ? withGroup.filter((s) => s.default_shift_id === shiftId).length : 0,
      website: myPrimaryWebsiteId ? withGroup.filter((s) => s.primary_website_id === myPrimaryWebsiteId).length : 0,
      combined: staffInScope.length,
    };
  }, [staffList, effectiveUserGroup, shiftId, myPrimaryWebsiteId, staffInScope.length]);

  /** โควต้านับเฉพาะวันหยุด (leave_type X) ที่ไม่ยกเว้นโควตา — วันลาอื่นๆ (ลากิจ, ลาพักร้อน, ขาดงาน ฯลฯ) ไม่นับรวมโควต้า */
  const isQuotaCounted = (h: Holiday) =>
    (h.leave_type === 'X' || h.leave_type == null) && h.is_quota_exempt !== true;

  const usedForDay = (day: number) => {
    const d = format(new Date(monthDate.getFullYear(), monthDate.getMonth(), day), 'yyyy-MM-dd');
    return displayHolidays.filter((h) => h.holiday_date === d && (h.status === 'approved' || h.status === 'pending') && isQuotaCounted(h)).length;
  };

  /** ใช้ไปแล้วในวันนี้เฉพาะคนในขอบเขตรวม (แผนก+กะ+กลุ่ม+เว็บถ้าเปิด) */
  const usedForDayInScope = (day: number) => {
    const d = format(new Date(monthDate.getFullYear(), monthDate.getMonth(), day), 'yyyy-MM-dd');
    return displayHolidays.filter((h) => h.holiday_date === d && (h.status === 'approved' || h.status === 'pending') && isQuotaCounted(h) && scopeStaffIds.has(h.user_id)).length;
  };

  /** ใช้ไปแล้วในวันนี้เฉพาะกะที่เลือก (สำหรับโควต้ามิติกะ แบบเก่า) */
  const usedForDayByShift = (day: number) => {
    const d = format(new Date(monthDate.getFullYear(), monthDate.getMonth(), day), 'yyyy-MM-dd');
    return displayHolidays.filter((h) => h.holiday_date === d && (h.status === 'approved' || h.status === 'pending') && isQuotaCounted(h) && h.shift_id === shiftId).length;
  };

  const usedForDayByWebsite = (day: number, websiteId: string | null) => {
    if (!websiteId) return 0;
    const d = format(new Date(monthDate.getFullYear(), monthDate.getMonth(), day), 'yyyy-MM-dd');
    return displayHolidays.filter((h) => h.holiday_date === d && (h.status === 'approved' || h.status === 'pending') && isQuotaCounted(h) && staffList.find((s) => s.id === h.user_id)?.primary_website_id === websiteId).length;
  };

  const hasCombinedTiers = useMemo(
    () => quotaTiers.some((t) => t.dimension === 'combined' && (t.user_group === effectiveUserGroup || t.user_group == null)),
    [quotaTiers, effectiveUserGroup]
  );

  const quotaForDayFromTiers = (day: number): { maxLeave: number; used: number; full: boolean } => {
    if (!effectiveUserGroup) return { maxLeave: 1, used: 0, full: false };
    if (hasCombinedTiers) {
      const maxLeave = getMaxLeaveFromTiers('combined', effectiveUserGroup, totalsForGroup.combined);
      const used = usedForDayInScope(day);
      return { maxLeave: maxLeave || 999, used, full: maxLeave > 0 && used >= maxLeave };
    }
    const usedBranch = usedForDay(day);
    const usedShift = usedForDayByShift(day);
    const usedWebsite = usedForDayByWebsite(day, myPrimaryWebsiteId);
    const maxBranch = getMaxLeaveFromTiers('branch', effectiveUserGroup, totalsForGroup.branch);
    const maxShift = getMaxLeaveFromTiers('shift', effectiveUserGroup, totalsForGroup.shift);
    const maxWebsite = getMaxLeaveFromTiers('website', effectiveUserGroup, totalsForGroup.website);
    const maxLeave = Math.min(maxBranch || 999, maxShift || 999, maxWebsite || 999);
    const used = usedBranch;
    const full = (maxBranch > 0 && usedBranch >= maxBranch) || (maxShift > 0 && usedShift >= maxShift) || (maxWebsite > 0 && usedWebsite >= maxWebsite);
    return { maxLeave, used, full };
  };

  /** กะ/แผนกที่มีผลสำหรับ staff ในวันนั้น (จากย้ายกะ หรือค่าโปรไฟล์) */
  const getEffectiveOnDay = (staffId: string, day: number): EffectiveBranchShift => {
    const d = format(new Date(monthDate.getFullYear(), monthDate.getMonth(), day), 'yyyy-MM-dd');
    const byDate = effectiveByUserByDate.get(staffId);
    if (byDate?.has(d)) return byDate.get(d)!;
    const s = staffList.find((x) => x.id === staffId);
    return { branch_id: s?.default_branch_id ?? null, shift_id: s?.default_shift_id ?? null };
  };

  /** โควต้าสำหรับวันนี้และขอบเขตของ staff นั้น — ใช้กะ/แผนกที่มีผลในวันนั้น (หลังย้ายกะ) */
  const getQuotaForDayAndStaff = (
    day: number,
    staff: { id: string; default_branch_id: string | null; default_shift_id: string | null; role: string; primary_website_id?: string | null }
  ): { maxLeave: number; used: number; full: boolean } => {
    const d = format(new Date(monthDate.getFullYear(), monthDate.getMonth(), day), 'yyyy-MM-dd');
    const ug = getUserGroupFromRole(staff.role as AppRole);
    const eff = getEffectiveOnDay(staff.id, day);
    if (!ug || !eff.branch_id || !eff.shift_id) return { maxLeave: 999, used: 0, full: false };
    const changeRestDayIds = changeRestDayUserIdsByDate.get(d);
    const scopeStaff = staffList.filter(
      (s) => {
        if (changeRestDayIds?.has(s.id)) return false;
        const seff = getEffectiveOnDay(s.id, day);
        return seff.branch_id === eff.branch_id && seff.shift_id === eff.shift_id && getUserGroupFromRole(s.role) === ug && (!scopeHolidayQuotaByWebsite || s.primary_website_id === staff.primary_website_id);
      }
    );
    const totalPeople = scopeStaff.length;
    const scopeIds = new Set(scopeStaff.map((s) => s.id));
    const used = displayHolidays.filter(
      (h) =>
        h.holiday_date === d &&
        (h.status === 'approved' || h.status === 'pending') &&
        isQuotaCounted(h) &&
        scopeIds.has(h.user_id)
    ).length;
    const maxLeave = hasCombinedTiers ? (getMaxLeaveFromTiers('combined', ug, totalPeople) || 999) : (quotaForDayFromTiers(day).maxLeave || 999);
    return { maxLeave, used, full: maxLeave > 0 && used >= maxLeave };
  };

  /** โควต้าสำหรับวันและขอบเขตของคนที่จอง — ใช้กะ/แผนก effective ในวันนั้น และไม่นับคนที่วันเปลี่ยนกะดึก→อื่น */
  const getQuotaForDateAndScope = (
    dateStr: string,
    resolvedBranchId: string,
    resolvedShiftId: string,
    ug: UserGroup,
    targetPrimaryWebsiteId: string | null
  ): { used: number; maxLeave: number; full: boolean } => {
    const changeRestDayIds = changeRestDayUserIdsByDate.get(dateStr);
    const scopeStaff = staffList.filter((s) => {
      if (changeRestDayIds?.has(s.id)) return false;
      const eff = effectiveByUserByDate.get(s.id)?.get(dateStr) ?? { branch_id: s.default_branch_id, shift_id: s.default_shift_id };
      return eff.branch_id === resolvedBranchId && eff.shift_id === resolvedShiftId && getUserGroupFromRole(s.role) === ug && (!scopeHolidayQuotaByWebsite || s.primary_website_id === targetPrimaryWebsiteId);
    });
    const totalPeople = scopeStaff.length;
    const scopeIds = new Set(scopeStaff.map((s) => s.id));
    const used = displayHolidays.filter(
      (h) =>
        h.holiday_date === dateStr &&
        (h.status === 'approved' || h.status === 'pending') &&
        isQuotaCounted(h) &&
        scopeIds.has(h.user_id)
    ).length;
    const maxLeave = hasCombinedTiers
      ? (getMaxLeaveFromTiers('combined', ug, totalPeople) || 999)
      : Math.min(
          getMaxLeaveFromTiers('branch', ug, staffList.filter((s) => getUserGroupFromRole(s.role) === ug).length) || 999,
          getMaxLeaveFromTiers('shift', ug, staffList.filter((s) => s.default_shift_id === resolvedShiftId && getUserGroupFromRole(s.role) === ug).length) || 999,
          getMaxLeaveFromTiers('website', ug, staffList.filter((s) => s.primary_website_id === targetPrimaryWebsiteId && getUserGroupFromRole(s.role) === ug).length) || 999
        );
    return { used, maxLeave, full: maxLeave > 0 && used >= maxLeave };
  };

  const handleRequestHoliday = async (dateStr: string, forUserId?: string, options?: { leave_type?: string; is_quota_exempt?: boolean }) => {
    const targetUserId = forUserId || user?.id;
    if (!targetUserId) return;
    const targetStaff = forUserId ? staffList.find((s) => s.id === forUserId) : null;
    const effectiveOnDate = effectiveByUserByDate.get(targetUserId)?.get(dateStr);
    const resolvedBranchId = effectiveOnDate?.branch_id ?? (branchId || (forUserId ? targetStaff?.default_branch_id : profile?.default_branch_id)) ?? null;
    const resolvedShiftId = effectiveOnDate?.shift_id ?? (shiftId || (forUserId ? targetStaff?.default_shift_id : profile?.default_shift_id)) ?? null;
    if (!resolvedBranchId || !resolvedShiftId) {
      alert('ไม่สามารถจองได้: ยังไม่ได้กำหนดแผนก/กะ');
      return;
    }
    const ug = forUserId ? (targetStaff ? getUserGroupFromRole(targetStaff.role) : null) : (getMyUserGroup(profile) ?? (profile?.role === 'instructor_head' ? 'INSTRUCTOR' : null));
    if (!ug) {
      alert('เฉพาะพนักงานประจำหรือพนักงานออนไลน์เท่านั้นที่จองวันหยุดได้');
      return;
    }
    const isExempt = !!(forUserId && canManageHolidays && options?.is_quota_exempt);
    if (!isExempt) {
      const targetPrimaryWebsiteId = forUserId ? (targetStaff?.primary_website_id ?? null) : myPrimaryWebsiteId;
      const { maxLeave, full } = getQuotaForDateAndScope(dateStr, resolvedBranchId, resolvedShiftId, ug, targetPrimaryWebsiteId);
      if (full) {
        alert(`โควต้าวันนี้เต็มแล้ว (หยุดได้ ${maxLeave} คน/วัน ในกลุ่มแผนกกะเดียวกัน${scopeHolidayQuotaByWebsite ? ' และเว็บเดียวกัน' : ''})`);
        return;
      }
    }
    const monthStart = format(startOfMonth(new Date(dateStr)), 'yyyy-MM-dd');
    const monthEnd = format(endOfMonth(new Date(dateStr)), 'yyyy-MM-dd');
    const existingInMonth = displayHolidays.filter(
      (h) => h.user_id === targetUserId && h.holiday_date >= monthStart && h.holiday_date <= monthEnd && (h.status === 'approved' || h.status === 'pending') && isQuotaCounted(h)
    ).length;
    const globalMax = globalMaxHolidayDaysPerMonth ?? 999;
    const willCountTowardQuota = ((forUserId && canManageHolidays ? options?.leave_type : 'X') ?? 'X') === 'X' && !(forUserId && canManageHolidays && options?.is_quota_exempt);
    if (willCountTowardQuota && existingInMonth >= globalMax) {
      alert(`เกินกติกากลาง: แต่ละคนจองวันหยุดได้สูงสุด ${globalMax} วัน/เดือน (คนนี้มี ${existingInMonth} วันแล้วในเดือนนี้)`);
      return;
    }
    setLoading(true);
    const payload: Record<string, unknown> = {
      user_id: targetUserId,
      branch_id: resolvedBranchId,
      shift_id: resolvedShiftId,
      holiday_date: dateStr,
      status: 'approved',
      reason: reason.trim() || null,
      user_group: ug,
    };
    if (forUserId && canManageHolidays) {
      payload.leave_type = options?.leave_type ?? 'X';
      payload.is_quota_exempt = options?.is_quota_exempt ?? false;
    }
    const { error } = await supabase.from('holidays').insert(payload);
    setLoading(false);
    if (error) {
      alert(error.message || 'เกิดข้อผิดพลาด');
      return;
    }
    const targetName = staffList.find((s) => s.id === targetUserId)?.display_name || staffList.find((s) => s.id === targetUserId)?.email || '—';
    await logAudit(forUserId ? 'holiday_add' : 'holiday_book', 'holidays', null, { holiday_date: dateStr, user_id: targetUserId }, forUserId ? `เพิ่มวันลา วันที่ ${dateStr} ให้ ${targetName}` : `จองวันหยุด/ลา วันที่ ${dateStr}`);
    setModal(null);
    setReason('');
    setAddEditLeaveType('X');
    const start = format(startOfMonth(monthDate), 'yyyy-MM-dd');
    const end = format(endOfMonth(monthDate), 'yyyy-MM-dd');
    let q = supabase.from('holidays').select('id, user_id, branch_id, shift_id, holiday_date, status, reason, leave_type, user_group, is_quota_exempt, approved_by, approved_at, reject_reason, created_at, updated_at').gte('holiday_date', start).lte('holiday_date', end);
    if (effectiveBranchId) q = q.eq('branch_id', effectiveBranchId);
    q.then(({ data }) => setHolidays(data || []));
  };

  const handleEditHoliday = async (holidayId: string, leaveType: string, newReason: string) => {
    setLoading(true);
    const { error } = await supabase.from('holidays').update({
      leave_type: leaveType,
      reason: newReason.trim() || null,
    }).eq('id', holidayId);
    setLoading(false);
    if (error) {
      alert(error.message || 'เกิดข้อผิดพลาด');
      return;
    }
    await logAudit('holiday_edit', 'holidays', holidayId, { leave_type: leaveType }, `แก้ไขวันหยุด/ลา ประเภท ${leaveType}`);
    setModal(null);
    setAddEditLeaveType('X');
    const start = format(startOfMonth(monthDate), 'yyyy-MM-dd');
    const end = format(endOfMonth(monthDate), 'yyyy-MM-dd');
    let q = supabase.from('holidays').select('id, user_id, branch_id, shift_id, holiday_date, status, reason, leave_type, user_group, is_quota_exempt, approved_by, approved_at, reject_reason, created_at, updated_at').gte('holiday_date', start).lte('holiday_date', end);
    if (effectiveBranchId) q = q.eq('branch_id', effectiveBranchId);
    q.then(({ data }) => setHolidays(data || []));
  };

  const handleRemoveHoliday = async (holidayId: string) => {
    setLoading(true);
    await supabase.from('holidays').delete().eq('id', holidayId);
    await logAudit('holiday_remove', 'holidays', holidayId, {}, 'ลบรายการวันหยุด/ลา');
    setLoading(false);
    setModal(null);
    const start = format(startOfMonth(monthDate), 'yyyy-MM-dd');
    const end = format(endOfMonth(monthDate), 'yyyy-MM-dd');
    let q = supabase.from('holidays').select('id, user_id, branch_id, shift_id, holiday_date, status, reason, leave_type, user_group, is_quota_exempt, approved_by, approved_at, reject_reason, created_at, updated_at').gte('holiday_date', start).lte('holiday_date', end);
    if (effectiveBranchId) q = q.eq('branch_id', effectiveBranchId);
    q.then(({ data }) => setHolidays(data || []));
  };

  const handleApprove = async (holidayId: string) => {
    setLoading(true);
    const { error } = await supabase.from('holidays').update({ status: 'approved', approved_by: user?.id, approved_at: new Date().toISOString() }).eq('id', holidayId);
    setLoading(false);
    if (error) {
      alert(error.message || 'เกิดข้อผิดพลาด');
      return;
    }
    await logAudit('holiday_approve', 'holidays', holidayId, {}, 'อนุมัติวันลา');
    setModal(null);
    const start = format(startOfMonth(monthDate), 'yyyy-MM-dd');
    const end = format(endOfMonth(monthDate), 'yyyy-MM-dd');
    let q = supabase.from('holidays').select('id, user_id, branch_id, shift_id, holiday_date, status, reason, leave_type, user_group, is_quota_exempt, approved_by, approved_at, reject_reason, created_at, updated_at').gte('holiday_date', start).lte('holiday_date', end);
    if (effectiveBranchId) q = q.eq('branch_id', effectiveBranchId);
    q.then(({ data }) => setHolidays(data || []));
  };

  const handleReject = async (holidayId: string) => {
    if (!rejectReason.trim()) {
      alert('กรุณาระบุเหตุผลในการปฏิเสธ');
      return;
    }
    setLoading(true);
    const { error } = await supabase.from('holidays').update({ status: 'rejected', approved_by: user?.id, approved_at: new Date().toISOString(), reject_reason: rejectReason }).eq('id', holidayId);
    setLoading(false);
    if (error) {
      alert(error.message || 'เกิดข้อผิดพลาด');
      return;
    }
    await logAudit('holiday_reject', 'holidays', holidayId, { reject_reason: rejectReason }, `ไม่อนุมัติวันลา: ${rejectReason.slice(0, 80)}`);
    setModal(null);
    setRejectReason('');
    const start = format(startOfMonth(monthDate), 'yyyy-MM-dd');
    const end = format(endOfMonth(monthDate), 'yyyy-MM-dd');
    let q = supabase.from('holidays').select('id, user_id, branch_id, shift_id, holiday_date, status, reason, leave_type, user_group, is_quota_exempt, approved_by, approved_at, reject_reason, created_at, updated_at').gte('holiday_date', start).lte('holiday_date', end);
    if (effectiveBranchId) q = q.eq('branch_id', effectiveBranchId);
    q.then(({ data }) => setHolidays(data || []));
  };

  /** ส่งออก Excel (exceljs): Row1 ชื่อรายงาน+เดือน, Row2 legend, Row3 header, แถวหัวกลุ่ม+แถวพนักงาน, freeze 3 แถว 4 คอลัมน์ */
  const exportExcel = async () => {
    const thinBorder = { top: { style: 'thin' as const }, left: { style: 'thin' as const }, bottom: { style: 'thin' as const }, right: { style: 'thin' as const } };
    const hexToArgb = (hex: string) => 'FF' + (hex.replace(/^#/, '') || '000000');

    const totalCols = 4 + dayNumbers.length;
    const monthTitle = format(monthDate, 'MMMM yyyy', { locale: th });

    const getCellValue = (staff: (typeof sortedStaff)[0], day: number): { text: string; fill?: string; isShiftChange?: boolean } => {
      const dateStr = format(new Date(monthDate.getFullYear(), monthDate.getMonth(), day), 'yyyy-MM-dd');
      const h = getHoliday(staff.id, day);
      if (h) {
        const lt = leaveTypesMap[h.leave_type || 'X'];
        return { text: (lt?.code || h.leave_type || 'X').slice(0, 2).toUpperCase(), fill: lt?.color || '#4B5563' };
      }
      const shiftChangeDay = scheduledShiftChangeDatesByUser.get(staff.id)?.get(dateStr);
      if (shiftChangeDay) {
        const fromLabel = getShiftShortLabel(shifts.find((s) => s.id === shiftChangeDay.from_shift_id));
        const toLabel = getShiftShortLabel(shifts.find((s) => s.id === shiftChangeDay.to_shift_id));
        return { text: `${fromLabel}→${toLabel}`, fill: '#0ea5e9', isShiftChange: true };
      }
      return { text: '' };
    };

    const isWeekend = (day: number) => {
      const d = new Date(monthDate.getFullYear(), monthDate.getMonth(), day);
      const dayOfWeek = d.getDay();
      return dayOfWeek === 0 || dayOfWeek === 6;
    };

    const userGroupLabel = (role: AppRole): string => {
      const g = getUserGroupFromRole(role);
      if (g === 'INSTRUCTOR') return 'หัวหน้า/พนักงานประจำ';
      if (g === 'STAFF') return 'พนักงานออนไลน์';
      if (g === 'MANAGER') return 'ผู้จัดการ';
      return '—';
    };

    const wb = new ExcelJS.Workbook();
    const ws = wb.addWorksheet('วันหยุด');

    const setCell = (row: number, col: number, value: string | number, opts?: { fill?: string; border?: boolean }) => {
      const cell = ws.getCell(row, col);
      cell.value = value;
      if (opts?.border !== false) cell.border = thinBorder;
      if (opts?.fill) cell.fill = { type: 'pattern', pattern: 'solid' as const, fgColor: { argb: hexToArgb(opts.fill) } };
    };

    let currentRow = 1;

    ws.getRow(currentRow).height = 22;
    ws.getCell(currentRow, 1).value = `ตารางวันหยุด - ${monthTitle}`;
    ws.mergeCells(currentRow, 1, currentRow, totalCols);
    ws.getCell(currentRow, 1).border = thinBorder;
    ws.getCell(currentRow, 1).alignment = { vertical: 'middle' };
    currentRow++;

    const legendParts = ['กะเช้า ☀️ (D)', 'กะกลาง 🌆 (+)', 'กะดึก 🌙 (N)', ...leaveTypes.map((lt) => `${lt.name}`), 'เปลี่ยนกะ (เช้า↔กลาง↔ดึก)', '◇ ไม่หักโควตา', 'โควต้า ดูจากตารางด้านล่าง'];
    ws.getRow(currentRow).height = 22;
    ws.getCell(currentRow, 1).value = `ความหมาย: ${legendParts.join(' | ')}`;
    ws.mergeCells(currentRow, 1, currentRow, totalCols);
    ws.getCell(currentRow, 1).border = thinBorder;
    ws.getCell(currentRow, 1).alignment = { vertical: 'middle', wrapText: true };
    currentRow++;

    const headerRow = currentRow;
    ws.getRow(headerRow).height = 22;
    ['กลุ่ม', 'แผนก', 'กะ', 'ชื่อ'].forEach((v, i) => setCell(headerRow, i + 1, v));
    dayNumbers.forEach((d, i) => setCell(headerRow, 5 + i, d));
    currentRow++;

    const groups = (() => {
      const result: { branchName: string; shiftName: string; staff: (typeof sortedStaff)[0][] }[] = [];
      let lastKey = '';
      let current: (typeof sortedStaff)[0][] = [];
      sortedStaff.forEach((s) => {
        const key = `${s.default_branch_id ?? ''}|${s.default_shift_id ?? ''}`;
        if (key !== lastKey) {
          if (current.length) {
            const first = current[0];
            result.push({
              branchName: branches.find((b) => b.id === first.default_branch_id)?.name ?? '—',
              shiftName: shifts.find((x) => x.id === first.default_shift_id)?.name ?? '—',
              staff: current,
            });
          }
          current = [];
          lastKey = key;
        }
        current.push(s);
      });
      if (current.length) {
        const first = current[0];
        result.push({
          branchName: branches.find((b) => b.id === first.default_branch_id)?.name ?? '—',
          shiftName: shifts.find((x) => x.id === first.default_shift_id)?.name ?? '—',
          staff: current,
        });
      }
      return result;
    })();

    for (const group of groups) {
      ws.getRow(currentRow).height = 22;
      const groupTitle = `${group.branchName} - ${group.shiftName}`;
      ws.getCell(currentRow, 1).value = groupTitle;
      ws.mergeCells(currentRow, 1, currentRow, totalCols);
      ws.getCell(currentRow, 1).border = thinBorder;
      ws.getCell(currentRow, 1).alignment = { vertical: 'middle' };
      currentRow++;

      for (const staff of group.staff) {
        ws.getRow(currentRow).height = 20;
        const branchName = branches.find((b) => b.id === staff.default_branch_id)?.name ?? '—';
        const shiftName = shifts.find((x) => x.id === staff.default_shift_id)?.name ?? '—';
        setCell(currentRow, 1, userGroupLabel(staff.role as AppRole));
        setCell(currentRow, 2, branchName);
        setCell(currentRow, 3, shiftName);
        setCell(currentRow, 4, getDisplayLabel(staff));
        dayNumbers.forEach((day, i) => {
          const col = 5 + i;
          const { text, fill } = getCellValue(staff, day);
          const fillOpt = fill ? { fill } : (isWeekend(day) ? { fill: '#f3f4f6' } : {});
          setCell(currentRow, col, text, { ...fillOpt, border: true });
          if (text && fill) {
            const cell = ws.getCell(currentRow, col);
            cell.font = { color: { argb: 'FFFFFFFF' }, size: 10 };
          }
        });
        currentRow++;
      }
    }

    const dayColWidth = 3;
    ws.getColumn(1).width = 12;
    ws.getColumn(2).width = 12;
    ws.getColumn(3).width = 10;
    ws.getColumn(4).width = 18;
    for (let i = 5; i <= totalCols; i++) ws.getColumn(i).width = dayColWidth;

    ws.views = [{ state: 'frozen', xSplit: 4, ySplit: 3, topLeftCell: 'E4' }];

    const buffer = await wb.xlsx.writeBuffer();
    const blob = new Blob([buffer], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `ตารางวันหยุด_${month}.xlsx`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const today = format(new Date(), 'yyyy-MM-dd');
  const isBookingOpen = useMemo(() => {
    if (!bookingConfig) return false;
    return today >= bookingConfig.open_from && today <= bookingConfig.open_until;
  }, [bookingConfig, today]);

  /** จำนวนวันที่จองในเดือน (นับเฉพาะวันหยุดที่หักโควตา สำหรับเช็ค max_days_per_person) */
  const myBookedDaysInMonth = useMemo(() => {
    if (!user?.id) return 0;
    return displayHolidays.filter((h) => h.user_id === user.id && (h.status === 'approved' || h.status === 'pending') && isQuotaCounted(h)).length;
  }, [displayHolidays, user?.id]);

  const canRequest = (day: number) => {
    if (!bookingConfig && !canManageHolidays) return false;
    const d = format(new Date(monthDate.getFullYear(), monthDate.getMonth(), day), 'yyyy-MM-dd');
    const existing = displayHolidays.find((h) => h.user_id === user?.id && h.holiday_date === d);
    if (existing) return false;
    const { full } = quotaForDayFromTiers(day);
    if (full) return false;
    const maxDays = globalMaxHolidayDaysPerMonth ?? bookingConfig?.max_days_per_person ?? 999;
    if (myBookedDaysInMonth >= maxDays && !canManageHolidays) return false;
    if (!isBookingOpen && !canManageHolidays) return false;
    return true;
  };

  /** พนักงานลบวันหยุดตัวเองได้เฉพาะในช่วงเวลาจอง หรือถ้าเป็นหัวหน้า/แอดมิน */
  const canDeleteOwnHoliday = useMemo(
    () => !!user && (canManageHolidays || (bookingConfig != null && isBookingOpen)),
    [user, canManageHolidays, bookingConfig, isBookingOpen]
  );

  const subtitle = !isAdmin && myUserGroup
    ? (myUserGroup === 'INSTRUCTOR' ? 'โหมดพนักงานประจำ' : myUserGroup === 'MANAGER' ? 'โหมดผู้จัดการ' : 'โหมดพนักงานออนไลน์')
    : !isBookingOpen && !canManageHolidays && bookingConfig
      ? `ปิดจองวันหยุดเดือนนี้แล้ว (เปิดจอง ${bookingConfig.open_from} – ${bookingConfig.open_until})`
      : !isBookingOpen && !canManageHolidays && !bookingConfig
        ? 'ยังไม่เปิดจองวันหยุดเดือนนี้'
        : undefined;

  return (
    <div className="space-y-5">
      <PageHeader
        title="ตารางวันหยุด"
        subtitle={subtitle}
        sticky
      />

      {/* แถบฟิลเตอร์ */}
      <div className="rounded-[10px] border border-[rgba(255,215,0,0.12)] bg-[rgba(11,15,26,0.6)] p-4">
        <div className="flex flex-wrap items-end gap-4">
          {(isAdmin || profile?.role === 'manager' || isInstructorHead || isInstructor) && (
            <div>
              <label className="block text-gray-400 text-xs font-medium mb-1.5 uppercase tracking-wider">กลุ่ม</label>
              <select
                value={userGroupFilter}
                onChange={(e) => setUserGroupFilter(e.target.value as '' | UserGroup)}
                className="h-9 min-w-[10rem] rounded-lg border border-premium-gold/25 bg-premium-dark text-white text-sm px-3 focus:outline-none focus:ring-1 focus:ring-premium-gold/50"
              >
                <option value="">ทั้งหมด</option>
                <option value="INSTRUCTOR">หัวหน้า/พนักงานประจำ</option>
                <option value="STAFF">พนักงานออนไลน์</option>
                <option value="MANAGER">ผู้จัดการ</option>
              </select>
            </div>
          )}
          {isGlobalViewer && (
            <div>
              <label className="block text-gray-400 text-xs font-medium mb-1.5 uppercase tracking-wider">แผนก</label>
              <select value={branchId} onChange={(e) => setBranchId(e.target.value)} className="h-9 min-w-[10rem] rounded-lg border border-premium-gold/25 bg-premium-dark text-white text-sm px-3 focus:outline-none focus:ring-1 focus:ring-premium-gold/50">
                <option value="">ทุกแผนก</option>
                {branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
              </select>
            </div>
          )}
          <div>
            <label className="block text-gray-400 text-xs font-medium mb-1.5 uppercase tracking-wider">ประเภทกะ</label>
            <div className="inline-flex rounded-lg border border-premium-gold/25 bg-premium-dark p-0.5" role="group">
              {(['', 'morning', 'mid', 'night'] as const).map((kind) => (
                <button
                  key={kind || 'all'}
                  type="button"
                  onClick={() => setShiftKindFilter(kind)}
                  className={`inline-flex items-center justify-center w-9 h-8 rounded-md text-sm transition-colors ${shiftKindFilter === kind ? 'bg-premium-gold/25 text-premium-gold' : 'text-gray-400 hover:text-premium-gold/90 hover:bg-premium-gold/10'}`}
                  title={kind ? getShiftLabel(kind) : 'ทั้งหมด'}
                >
                  {kind ? getShiftIcon(kind) : '•'}
                </button>
              ))}
            </div>
          </div>
          <div>
            <label className="block text-gray-400 text-xs font-medium mb-1.5 uppercase tracking-wider">เว็บหลัก</label>
            <select value={websiteFilter} onChange={(e) => setWebsiteFilter(e.target.value)} className="h-9 min-w-[10rem] rounded-lg border border-premium-gold/25 bg-premium-dark text-white text-sm px-3 focus:outline-none focus:ring-1 focus:ring-premium-gold/50">
              <option value="">ทั้งหมด</option>
              {websites.map((w) => <option key={w.id} value={w.id}>{w.name} ({w.alias})</option>)}
            </select>
          </div>
          <div>
            <label className="block text-gray-400 text-xs font-medium mb-1.5 uppercase tracking-wider">เดือน</label>
            <div className="flex items-center gap-1 rounded-lg border border-premium-gold/25 bg-premium-dark overflow-hidden">
              <button type="button" onClick={() => setMonth(format(subMonths(monthDate, 1), 'yyyy-MM'))} className="h-9 w-9 flex items-center justify-center text-premium-gold hover:bg-premium-gold/10 transition-colors">‹</button>
              <input type="month" value={month} onChange={(e) => setMonth(e.target.value)} className="h-9 w-36 bg-transparent text-white text-sm px-2 border-0 focus:outline-none" />
              <button type="button" onClick={() => setMonth(format(addMonths(monthDate, 1), 'yyyy-MM'))} className="h-9 w-9 flex items-center justify-center text-premium-gold hover:bg-premium-gold/10 transition-colors">›</button>
            </div>
          </div>
          <div>
            <label className="block text-gray-400 text-xs font-medium mb-1.5 uppercase tracking-wider">ค้นหา</label>
            <input
              type="text"
              placeholder="ชื่อพนักงาน"
              value={searchName}
              onChange={(e) => setSearchName(e.target.value)}
              className="h-9 w-44 rounded-lg border border-premium-gold/25 bg-premium-dark text-white text-sm px-3 placeholder-gray-500 focus:outline-none focus:ring-1 focus:ring-premium-gold/50"
            />
          </div>
          <label className="flex items-center gap-2 h-9 cursor-pointer text-gray-400 hover:text-premium-gold/90 text-sm" title={!isGlobalViewer ? 'ยกเลิกเพื่อดูวันลาและเปลี่ยนกะของคนในแผนก' : undefined}>
            <input type="checkbox" checked={onlyMyData} onChange={(e) => setOnlyMyData(e.target.checked)} className="rounded border-premium-gold/40 text-premium-gold focus:ring-premium-gold/50" />
            <span>เฉพาะของฉัน</span>
          </label>
          {isGlobalViewer && (
            <Button variant="outline" className="h-9 shrink-0" onClick={exportExcel}>
              ส่งออก Excel
            </Button>
          )}
        </div>
      </div>

      {canManageHolidays && (() => {
        const pending = holidays.filter((h) => h.status === 'pending');
        if (pending.length === 0) return null;
        return (
          <div className="rounded-xl border border-amber-500/25 bg-amber-500/5 px-4 py-3">
            <p className="text-amber-200/90 text-sm font-medium mb-2">คำขอรออนุมัติ ({pending.length})</p>
            <div className="flex flex-wrap gap-3">
              {pending.map((h) => {
                const staff = staffList.find((s) => s.id === h.user_id);
                return (
                  <span key={h.id} className="inline-flex items-center gap-2 text-sm rounded-lg bg-premium-dark/60 px-3 py-1.5">
                    <span className="text-gray-300">{staff ? getDisplayLabel(staff) : h.user_id.slice(0, 8)} — {h.holiday_date}</span>
                    <button type="button" className="text-emerald-400 hover:underline text-xs font-medium" onClick={() => setModal({ type: 'approve', holiday: h })}>อนุมัติ</button>
                    <button type="button" className="text-red-400 hover:underline text-xs font-medium" onClick={() => setModal({ type: 'reject', holiday: h })}>ปฏิเสธ</button>
                  </span>
                );
              })}
            </div>
          </div>
        );
      })()}

      {/* Legend */}
      <div className="flex flex-wrap items-center gap-2 rounded-lg border border-premium-gold/10 bg-premium-darker/30 px-3 py-2">
        <span className="text-gray-500 text-xs font-medium uppercase tracking-wider mr-1">ความหมาย:</span>
        <span className="inline-flex items-center gap-1.5 px-2 py-1 rounded-md bg-premium-dark/60 text-gray-400 text-xs">
          <span>☀️</span> กะเช้า
        </span>
        <span className="inline-flex items-center gap-1.5 px-2 py-1 rounded-md bg-premium-dark/60 text-gray-400 text-xs">
          <span>🌆</span> กะกลาง
        </span>
        <span className="inline-flex items-center gap-1.5 px-2 py-1 rounded-md bg-premium-dark/60 text-gray-400 text-xs">
          <span>🌙</span> กะดึก
        </span>
        <span className="inline-flex items-center gap-1.5 px-2 py-1 rounded-md bg-premium-dark/60 text-gray-400 text-xs" title="ตัวอักษรในเซลล์วันทำงาน">
          ในเซลล์: <strong className="text-sky-300">D</strong>=กะเช้า · <strong className="text-sky-300">N</strong>=กะดึก · <strong className="text-premium-gold">+</strong>=กะกลาง
        </span>
        {leaveTypes.map((lt) => (
          <span key={lt.code} className="inline-flex items-center gap-1.5 px-2 py-1 rounded-md bg-premium-dark/60 text-gray-400 text-xs">
            <span className="w-3 h-3 rounded shrink-0 border border-white/10" style={{ backgroundColor: lt.color || '#9CA3AF' }} />
            {lt.name}
          </span>
        ))}
        <span className="inline-flex items-center gap-1.5 px-2 py-1 rounded-md bg-premium-dark/60 text-gray-400 text-xs" title="วันที่จะต้องเปลี่ยนกะ: เช้า→ดึก = ทำงานกะดึกในวันนั้น, ดึก→เช้า = ทำงานกะเช้า, กลาง→เช้า/กลาง→ดึก = ทำงานกะปลายทางในวันนั้น">
          <span className="w-3 h-3 rounded shrink-0 bg-sky-600/90 border border-sky-400/50" />
          เปลี่ยนกะ (เช้า↔กลาง↔ดึก)
        </span>
        <span className="inline-flex items-center gap-1.5 px-2 py-1 rounded-md bg-premium-dark/60 text-gray-400 text-xs" title="ไม่หักโควตา">
          ◇ ไม่หักโควตา
        </span>
        <span className="flex-1" />
        <span className="text-gray-500 text-xs">โควต้า: ดูจากตารางด้านล่าง</span>
      </div>

      {staffWithoutShiftInBranch > 0 && isGlobalViewer && (
        <div className="rounded-lg border border-amber-500/20 bg-amber-500/5 px-4 py-2.5 text-amber-200/90 text-sm">
          มีสมาชิก <strong>{staffWithoutShiftInBranch}</strong> คนที่ยังไม่ได้กำหนดกะ — กำหนดได้ที่ <strong>จัดการสมาชิก</strong>
        </div>
      )}

      <div className="overflow-x-auto rounded-xl border border-premium-gold/15 shadow-sm">
        <table className="w-full border-collapse text-sm">
          <thead className="sticky-head bg-premium-darker/60">
            <tr>
              <th className="sticky-col min-w-[160px] text-left py-3 px-3 border-b border-r border-premium-gold/15 text-premium-gold font-medium text-xs uppercase tracking-wider">ชื่อ</th>
              {dayNumbers.map((d) => (
                <th
                  key={d}
                  className={`min-w-[36px] py-2.5 px-1 border-b border-premium-gold/15 text-center text-premium-gold/90 font-medium text-xs transition-shadow ${hoverCol === d ? 'shadow-[inset_-6px_0_12px_rgba(212,175,55,0.12),inset_6px_0_12px_rgba(212,175,55,0.12)]' : ''}`}
                  onMouseEnter={() => setHoverCol(d)}
                  onMouseLeave={() => setHoverCol(null)}
                >
                  <span>{d}</span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {sortedStaff.map((staff) => (
              <tr key={staff.id} className="border-b border-premium-gold/10 hover:bg-premium-gold/5 transition-colors">
                <td className="sticky-col py-2 px-3 border-r border-premium-gold/15 font-medium text-gray-200">
                  <span className="flex items-center gap-2 min-w-0">
                    <span className="truncate">{getDisplayLabel(staff)}</span>
                    {(() => {
                      const shift = shifts.find((s) => s.id === staff.default_shift_id);
                      const kind = getShiftKind(shift);
                      const icon = getShiftIcon(kind);
                      const label = getShiftLabel(kind);
                      const timeRange = shift?.start_time != null && shift?.end_time != null ? `${shift.start_time.slice(0, 5)}–${shift.end_time.slice(0, 5)}` : '';
                      return (
                        <span
                          className="shrink-0 inline-flex items-center justify-center w-6 h-6 rounded-md border border-premium-gold/30 bg-premium-gold/10 text-sm"
                          title={[timeRange ? `${label} ${timeRange}` : label, 'โปรไฟล์กะอัปเดต 00:01 น. (วันที่มีผล)'].filter(Boolean).join(' · ')}
                        >
                          {icon}
                        </span>
                      );
                    })()}
                  </span>
                </td>
                {dayNumbers.map((day) => {
                  const h = getHoliday(staff.id, day);
                  const dateStr = format(new Date(monthDate.getFullYear(), monthDate.getMonth(), day), 'yyyy-MM-dd');
                  const shiftChangeDay = scheduledShiftChangeDatesByUser.get(staff.id)?.get(dateStr);
                  const isShiftChangeDay = !!shiftChangeDay;
                  const isMe = staff.id === user?.id;
                  const canReq = isMe && canRequest(day);
                  const { full } = hasCombinedTiers ? getQuotaForDayAndStaff(day, staff) : quotaForDayFromTiers(day);
                  const canAddFor = canEditThisBranch && !h && !full && (isBookingOpen || canManageHolidays) && (!isMe || canManageHolidays) && (bookingConfig != null || canManageHolidays);
                  const lt = h ? leaveTypesMap[h.leave_type || 'X'] : null;
                  const code = (lt?.code || h?.leave_type || 'X').slice(0, 2).toUpperCase();
                  const bgColor = lt?.color || '#4B5563';
                  const clickable = !!h && (canEditThisBranch || (isMe && canDeleteOwnHoliday));
                  const handleClick = () => {
                    if (!h) return;
                    if (canEditThisBranch && (!isMe || canManageHolidays)) {
                      setAddEditLeaveType(h.leave_type || 'X');
                      setReason(h.reason ?? '');
                      setModal({ type: 'edit_for', holiday: h, staffName: getDisplayLabel(staff) });
                    } else if (isMe && canDeleteOwnHoliday) {
                      setModal({ type: 'remove_for', holiday: h, staffName: getDisplayLabel(staff) });
                    }
                  };
                  return (
                    <td
                      key={day}
                      className={`p-0.5 text-center align-middle transition-shadow ${hoverCol === day ? 'shadow-[inset_-6px_0_12px_rgba(212,175,55,0.12),inset_6px_0_12px_rgba(212,175,55,0.12)]' : ''}`}
                      onMouseEnter={() => setHoverCol(day)}
                      onMouseLeave={() => setHoverCol(null)}
                    >
                      <div
                        className={`w-[34px] h-[30px] min-w-[34px] mx-auto flex items-center justify-center rounded-[4px] text-[12px] font-semibold ${
                          clickable || canReq || canAddFor ? 'cursor-pointer' : 'cursor-default'
                        } transition-transform duration-150`}
                        style={{}}
                      >
                        {h ? (
                          <div
                            onClick={clickable ? handleClick : undefined}
                            style={{
                              width: '100%',
                              height: '100%',
                              display: 'flex',
                              alignItems: 'center',
                              justifyContent: 'center',
                              backgroundColor: bgColor,
                              color: '#ffffff',
                              textShadow: '0 1px 2px rgba(0,0,0,0.6)',
                              boxShadow: '0 0 0 rgba(0,0,0,0)',
                              border: h.is_quota_exempt ? '1px solid #FFD700' : 'none',
                            }}
                            className="hover:shadow-[0_0_6px_rgba(212,175,55,0.5)] hover:-translate-y-px"
                            title={`${lt?.name || h.leave_type || ''} (${code})${h.is_quota_exempt ? ' | ไม่หักโควตา' : ''}`}
                          >
                            {code}
                          </div>
                        ) : isShiftChangeDay && shiftChangeDay ? (
                          (() => {
                            const fromS = shifts.find((s) => s.id === shiftChangeDay.from_shift_id);
                            const toS = shifts.find((s) => s.id === shiftChangeDay.to_shift_id);
                            const fromShort = getShiftShortLabel(fromS);
                            const toShort = getShiftShortLabel(toS);
                            const hyphenLabel = `${fromShort}-${toShort}`;
                            return (
                              <div
                                className="w-full h-full flex items-center justify-center rounded-[4px] text-[10px] font-medium bg-sky-300/50 text-white border border-sky-400/60"
                                title={`วันนั้นทำงานกะ${toShort} (เปลี่ยนกะ: ${fromShort}→${toShort})`}
                              >
                                {hyphenLabel}
                              </div>
                            );
                          })()
                        ) : (() => {
                          const effectiveShiftId = effectiveByUserByDate.get(staff.id)?.get(dateStr)?.shift_id ?? staff.default_shift_id;
                          const effectiveShift = shifts.find((s) => s.id === effectiveShiftId);
                          const cellLetter = getShiftCellLetter(effectiveShift);
                          const shiftLabel = effectiveShift ? [getShiftLabel(getShiftKind(effectiveShift)), effectiveShift.start_time && effectiveShift.end_time ? `${effectiveShift.start_time.slice(0, 5)}–${effectiveShift.end_time.slice(0, 5)}` : ''].filter(Boolean).join(' ') : '';
                          const baseCellStyle = {
                            width: '100%',
                            height: '100%',
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                          };
                          const letterCellClass = cellLetter === '+' ? 'border border-dashed border-premium-gold/40 text-premium-gold' : cellLetter === 'D' ? 'bg-sky-800/80 text-white font-semibold border border-sky-500/60' : 'bg-indigo-900/80 text-white font-semibold border border-indigo-500/60';
                          return isMe ? (
                            full ? (
                              <span className="inline-block w-full h-full" title="โควต้าวันนี้เต็มแล้ว" aria-label="โควต้าเต็ม" />
                            ) : canAddFor ? (
                              <div
                                onClick={() => setModal({ type: 'add_for', date: dateStr, staffId: staff.id, staffName: getDisplayLabel(staff) })}
                                style={baseCellStyle}
                                className={`hover:shadow-[0_0_6px_rgba(212,175,55,0.5)] hover:-translate-y-px text-sm ${letterCellClass}`}
                                title={shiftLabel ? `กะ${shiftLabel} · เพิ่มวันหยุด/วันลา` : 'เพิ่มวันหยุด/วันลา (เลือกประเภทได้)'}
                              >
                                {cellLetter}
                              </div>
                            ) : canReq ? (
                              <div
                                onClick={() => setModal({ type: 'request', date: dateStr })}
                                style={baseCellStyle}
                                className={`hover:shadow-[0_0_6px_rgba(212,175,55,0.5)] hover:-translate-y-px ${letterCellClass}`}
                                title={shiftLabel ? `กะ${shiftLabel} · จองวันหยุด` : 'จองวันหยุด'}
                              >
                                {cellLetter}
                              </div>
                            ) : (
                              <div style={baseCellStyle} className={`text-gray-500 ${letterCellClass}`} title={shiftLabel || undefined}>
                                {cellLetter}
                              </div>
                            )
                          ) : canAddFor ? (
                            <div
                              onClick={() => setModal({ type: 'add_for', date: dateStr, staffId: staff.id, staffName: getDisplayLabel(staff) })}
                              style={baseCellStyle}
                              className={`hover:shadow-[0_0_6px_rgba(212,175,55,0.5)] hover:-translate-y-px text-sm ${letterCellClass}`}
                              title={shiftLabel ? `กะ${shiftLabel} · เพิ่มวันหยุดให้` : 'เพิ่มวันหยุดให้'}
                            >
                              {cellLetter}
                            </div>
                          ) : full ? (
                            <span className="inline-block w-full h-full" title="โควต้าวันนี้เต็มแล้ว" aria-label="โควต้าเต็ม" />
                          ) : canOnlySelfHoliday && !isMe ? (
                            <div style={baseCellStyle} className={`text-gray-500 cursor-default ${letterCellClass}`} title={shiftLabel ? `กะ${shiftLabel} · ทำรายการได้เฉพาะของตนเอง` : 'ทำรายการได้เฉพาะของตนเอง'}>
                              {cellLetter}
                            </div>
                          ) : (
                            <div style={baseCellStyle} className={`text-gray-500 ${letterCellClass}`} title={shiftLabel || undefined}>
                              {cellLetter}
                            </div>
                          );
                        })()}
                      </div>
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Modal open={modal?.type === 'request'} onClose={() => setModal(null)} title="จองวันหยุด" footer={
        <>
          <Button variant="ghost" onClick={() => setModal(null)}>ยกเลิก</Button>
          <Button variant="gold" onClick={() => modal?.date && handleRequestHoliday(modal.date)} loading={loading}>บันทึก</Button>
        </>
      }>
        {modal?.date && (
          <>
            <p className="text-gray-300 mb-2">วันที่ {format(new Date(modal.date), 'd MMM yyyy', { locale: th })}</p>
            <label className="block text-gray-400 text-sm mb-1">เหตุผล (ไม่บังคับ)</label>
            <textarea value={reason} onChange={(e) => setReason(e.target.value)} className="w-full px-3 py-2 rounded bg-premium-dark border border-premium-gold/30 text-white" rows={2} placeholder="เหตุผล (ถ้ามี)" />
          </>
        )}
      </Modal>

      <Modal open={modal?.type === 'add_for'} onClose={() => setModal(null)} title="เพิ่มวันหยุด" footer={
        <>
          <Button variant="ghost" onClick={() => setModal(null)}>ยกเลิก</Button>
          <Button variant="gold" onClick={() => modal?.date && modal?.staffId && handleRequestHoliday(modal.date, modal.staffId, { leave_type: addEditLeaveType, is_quota_exempt: addForExemptQuota })} loading={loading}>บันทึก</Button>
        </>
      }>
        {modal?.type === 'add_for' && modal?.date && (
          <>
            <p className="text-gray-300 mb-3">เพิ่มวันหยุดให้ <strong>{modal.staffName}</strong> วันที่ {format(new Date(modal.date), 'd MMM yyyy', { locale: th })} — ตามกติกากลางและโควต้าขั้น (ยกเว้นโควต้าได้ถ้าเลือกด้านล่าง)</p>
            <div className="mb-2">
              <label className="block text-gray-400 text-sm mb-1">ประเภทการลา</label>
              <select value={addEditLeaveType} onChange={(e) => setAddEditLeaveType(e.target.value)} className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white">
                {leaveTypes.map((lt) => (
                  <option key={lt.code} value={lt.code}>{lt.name}</option>
                ))}
              </select>
            </div>
            <label className="flex items-center gap-2 text-gray-400 text-sm mb-2">
              <input type="checkbox" checked={addForExemptQuota} onChange={(e) => setAddForExemptQuota(e.target.checked)} className="rounded border-premium-gold/40" />
              <span>ไม่นับในโควต้า (ยกเว้นพิเศษ)</span>
            </label>
            <label className="block text-gray-400 text-sm mb-1">เหตุผล (ไม่บังคับ)</label>
            <input type="text" value={reason} onChange={(e) => setReason(e.target.value)} className="w-full px-3 py-2 rounded bg-premium-dark border border-premium-gold/30 text-white" placeholder="เหตุผล" />
          </>
        )}
      </Modal>

      <Modal open={modal?.type === 'edit_for'} onClose={() => setModal(null)} title="แก้ไขวันหยุด" footer={
        <>
          <Button variant="ghost" onClick={() => setModal(null)}>ยกเลิก</Button>
          <Button variant="danger" onClick={() => modal?.holiday && handleRemoveHoliday(modal.holiday.id)} loading={loading}>ลบ</Button>
          <Button variant="gold" onClick={() => modal?.holiday && handleEditHoliday(modal.holiday.id, addEditLeaveType, reason)} loading={loading}>บันทึก</Button>
        </>
      }>
        {modal?.type === 'edit_for' && modal?.holiday && (
          <>
            <p className="text-gray-300 mb-3">{modal.staffName} — วันที่ {format(new Date(modal.holiday.holiday_date), 'd MMM yyyy', { locale: th })} (ไม่หักโควตา)</p>
            <div className="mb-2">
              <label className="block text-gray-400 text-sm mb-1">ประเภทการลา</label>
              <select value={addEditLeaveType} onChange={(e) => setAddEditLeaveType(e.target.value)} className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white">
                {leaveTypes.map((lt) => (
                  <option key={lt.code} value={lt.code}>{lt.name}</option>
                ))}
              </select>
            </div>
            <label className="block text-gray-400 text-sm mb-1">เหตุผล</label>
            <input type="text" value={reason} onChange={(e) => setReason(e.target.value)} className="w-full px-3 py-2 rounded bg-premium-dark border border-premium-gold/30 text-white" placeholder="เหตุผล" />
          </>
        )}
      </Modal>

      <ConfirmModal open={modal?.type === 'remove_for'} onClose={() => setModal(null)} title="ลบวันหยุด" message={modal?.type === 'remove_for' && modal?.staffName ? `ยืนยันลบวันหยุดของ ${modal.staffName}?` : 'ยืนยันลบวันหยุด?'} onConfirm={async () => modal?.holiday && await handleRemoveHoliday(modal.holiday.id)} confirmLabel="ลบ" loading={loading} />

      <ConfirmModal open={modal?.type === 'approve'} onClose={() => setModal(null)} title="อนุมัติวันหยุด" message="ยืนยันการอนุมัติ?" onConfirm={async () => modal?.holiday && await handleApprove(modal.holiday.id)} confirmLabel="อนุมัติ" loading={loading} />
      <Modal open={modal?.type === 'reject'} onClose={() => setModal(null)} title="ปฏิเสธวันหยุด" footer={
        <>
          <Button variant="ghost" onClick={() => setModal(null)}>ยกเลิก</Button>
          <Button variant="danger" onClick={() => modal?.holiday && handleReject(modal.holiday.id)} disabled={!rejectReason.trim()} loading={loading}>ปฏิเสธ</Button>
        </>
      }>
        <label className="block text-gray-400 text-sm mb-1">เหตุผลในการปฏิเสธ (บังคับ)</label>
        <textarea value={rejectReason} onChange={(e) => setRejectReason(e.target.value)} className="w-full px-3 py-2 rounded bg-premium-dark border border-premium-gold/30 text-white" rows={3} />
      </Modal>
    </div>
  );
}
