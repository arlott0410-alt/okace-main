import { useState, useEffect, useMemo, useCallback, useRef } from 'react';
import { format } from 'date-fns';
import { supabase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import { getStoredBranchId, getStoredShiftId } from '../lib/auth';
import { useBranchesShifts } from '../lib/BranchesShiftsContext';
import { useToast } from '../lib/ToastContext';
import type { DutyRole, DutyAssignment, Profile, MonthlyRosterStatus } from '../lib/types';
import Button from '../components/ui/Button';
import Modal from '../components/ui/Modal';
import { PageHeader, PageCard } from '../components/layout';
import { BtnEdit, BtnDelete } from '../components/ui/ActionIcons';
import { logAudit } from '../lib/audit';
import { isRosterLocked } from '../lib/roster';
import type { EffectiveBranchShift } from '../lib/transfers';

type WebsiteOption = { id: string; name: string };
type AutoFilter = { sameBranch: boolean; sameShift: boolean; sameWebsite: boolean };

export default function DutyBoard() {
  const { user, profile } = useAuth();
  const { branches, shifts } = useBranchesShifts();
  const toast = useToast();
  const isAdmin = profile?.role === 'admin';
  const isManager = profile?.role === 'manager';
  const isInstructorHead = profile?.role === 'instructor_head';
  const canManageDutyRoles = isAdmin || isManager || isInstructorHead;
  const canArrangeDuties = isAdmin || isManager || isInstructorHead;
  const branchesForSelect = (isAdmin || isManager || isInstructorHead) ? branches : branches.filter((b) => b.id === profile?.default_branch_id);

  const [branchId, setBranchId] = useState(getStoredBranchId() || profile?.default_branch_id || '');
  const [shiftId, setShiftId] = useState(getStoredShiftId() || profile?.default_shift_id || '');
  const [assignmentDate, setAssignmentDate] = useState(format(new Date(), 'yyyy-MM-dd'));
  const [dutyRoles, setDutyRoles] = useState<DutyRole[]>([]);
  const [assignments, setAssignments] = useState<DutyAssignment[]>([]);
  const [staff, setStaff] = useState<Profile[]>([]);
  const [draggedUser, setDraggedUser] = useState<string | null>(null);
  const [dropTargetRoleId, setDropTargetRoleId] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [rosterLocked, setRosterLocked] = useState(false);
  /** กลุ่มผู้ใช้สำหรับ scope (INSTRUCTOR / STAFF เท่านั้น — ไม่โหลด manager) */
  const [userGroupFilter, setUserGroupFilter] = useState<'INSTRUCTOR' | 'STAFF'>('STAFF');
  /** กะ/แผนกที่มีผลต่อวันที่เลือก (จากย้ายกะ/โอน) — ใช้คำนวณ eligible scope */
  const [effectiveByUserByDate, setEffectiveByUserByDate] = useState<Map<string, Map<string, EffectiveBranchShift>>>(new Map());
  /** คนที่หยุด/ลาวันนี้ (approved/pending) — กรองตามวันที่เท่านั้น ไม่ใช้ branch/shift */
  const [leaveIdsForDate, setLeaveIdsForDate] = useState<Set<string>>(new Set());
  /** ตัวกรองสำหรับสุ่มจัด (คงที่หลังลบ UI ตัวกรอง) */
  const autoFilter: AutoFilter = { sameBranch: true, sameShift: true, sameWebsite: false };
  const selectedWebsiteId = '';

  const [modalRole, setModalRole] = useState<{ open: boolean; role?: DutyRole | null }>({ open: false, role: null });
  const [roleName, setRoleName] = useState('');
  const [roleSearch, setRoleSearch] = useState('');
  /** ใช้จัดอัตโนมัติครั้งเดียวต่อ (branch, shift, date) เมื่อยังไม่มีรายการ */
  const autoAssignedKeyRef = useRef<string>('');
  const prevLoadingRef = useRef<boolean>(false);

  const refetchDutyBoard = useCallback(() => {
    if (!branchId || !shiftId || !assignmentDate) return;
    setLoading(true);
    const date = assignmentDate;
    supabase.rpc('rpc_dutyboard', { p_date: date, p_branch_id: branchId, p_shift_id: shiftId }).then(({ data, error }) => {
      setLoading(false);
      if (error || !data?.[0]) return;
      const row = data[0] as { duty_roles?: DutyRole[]; assignments?: DutyAssignment[]; staff?: (Profile & { effective_branch_id?: string | null; effective_shift_id?: string | null })[]; leave_user_ids?: string[]; roster_status?: { status?: string } | null; websites?: WebsiteOption[] };
      setDutyRoles(Array.isArray(row.duty_roles) ? row.duty_roles : []);
      setAssignments(Array.isArray(row.assignments) ? row.assignments : []);
      setStaff(Array.isArray(row.staff) ? row.staff as Profile[] : []);
      setLeaveIdsForDate(new Set(Array.isArray(row.leave_user_ids) ? row.leave_user_ids : []));
      setRosterLocked(isRosterLocked((row.roster_status ?? null) as MonthlyRosterStatus | null));
      if (Array.isArray(row.staff)) {
        const map = new Map<string, Map<string, EffectiveBranchShift>>();
        row.staff.forEach((s: Profile & { effective_branch_id?: string | null; effective_shift_id?: string | null }) => {
          if (!map.has(s.id)) map.set(s.id, new Map());
          map.get(s.id)!.set(date, { branch_id: s.effective_branch_id ?? null, shift_id: s.effective_shift_id ?? null });
        });
        setEffectiveByUserByDate(map);
      }
    });
  }, [branchId, shiftId, assignmentDate]);

  const filteredDutyRoles = useMemo(() => {
    if (!roleSearch.trim()) return dutyRoles;
    const q = roleSearch.trim().toLowerCase();
    return dutyRoles.filter((r) => r.name.toLowerCase().includes(q));
  }, [dutyRoles, roleSearch]);

  /** Eligible scope: กลุ่มที่เลือก (พนักงานประจำ=INSTRUCTOR / พนักงานออนไลน์=STAFF) + effective แผนก/กะในวันที่เลือก */
  const staffInScope = useMemo(() => {
    if (!branchId || !shiftId) return [];
    const group = userGroupFilter;
    return staff.filter((s) => {
      const role = (s.role ?? '') as string;
      const matchGroup =
        group === 'INSTRUCTOR' ? (role === 'instructor' || role === 'instructor_head') : group === 'STAFF' ? role === 'staff' : false;
      if (!matchGroup) return false;
      const dayMap = effectiveByUserByDate.get(s.id);
      const eff = dayMap?.get(assignmentDate);
      const bid = eff?.branch_id ?? s.default_branch_id ?? null;
      const sid = eff?.shift_id ?? s.default_shift_id ?? null;
      return bid === branchId && sid === shiftId;
    });
  }, [staff, branchId, shiftId, assignmentDate, userGroupFilter, effectiveByUserByDate]);
  /** คนที่มาทำงานวันนี้ = ใน scope ลบคนที่หยุด/ลาวันนั้น (holiday filter by user_id only) */
  const workingTodayUserIds = useMemo(() => {
    const set = new Set(staffInScope.map((s) => s.id));
    leaveIdsForDate.forEach((id) => set.delete(id));
    return set;
  }, [staffInScope, leaveIdsForDate]);
  const staffWorkingToday = useMemo(() => staffInScope.filter((s) => workingTodayUserIds.has(s.id)), [staffInScope, workingTodayUserIds]);
  const staffNotWorkingToday = useMemo(() => staffInScope.filter((s) => !workingTodayUserIds.has(s.id)), [staffInScope, workingTodayUserIds]);

  const saveDutyRole = async () => {
    if (!branchId || !roleName.trim()) return;
    if (modalRole.role?.id) {
      await supabase.from('duty_roles').update({ name: roleName.trim() }).eq('id', modalRole.role.id);
    } else {
      await supabase.from('duty_roles').insert({ branch_id: branchId, name: roleName.trim(), sort_order: dutyRoles.length });
    }
    setModalRole({ open: false, role: null });
    setRoleName('');
    refetchDutyBoard();
    toast.show(modalRole.role ? 'แก้ไขหน้าที่แล้ว' : 'เพิ่มหน้าที่แล้ว');
  };

  const deleteDutyRole = async (id: string) => {
    if (!confirm('ลบหน้าที่นี้?')) return;
    await supabase.from('duty_roles').delete().eq('id', id);
    refetchDutyBoard();
    toast.show('ลบหน้าที่แล้ว');
  };

  useEffect(() => {
    if (!branchId && profile?.default_branch_id) setBranchId(profile.default_branch_id);
  }, [profile?.default_branch_id, branchId]);

  useEffect(() => {
    if (profile?.default_branch_id && !canArrangeDuties && branchId !== profile.default_branch_id) {
      setBranchId(profile.default_branch_id);
    }
  }, [profile?.default_branch_id, canArrangeDuties, branchId]);

  /** Single RPC load for DutyBoard (duty_roles, assignments, staff, leave_user_ids, roster_status, websites) */
  useEffect(() => {
    if (!branchId || !shiftId || !assignmentDate) return;
    refetchDutyBoard();
  }, [refetchDutyBoard, branchId, shiftId, assignmentDate]);

  /** จัดอัตโนมัติรายวัน: หลังโหลดเสร็จถ้าวันนั้นยังไม่มีรายการ ให้ระบบจัดให้ครั้งเดียว (หัวหน้าแก้ไขได้ภายหลัง) */
  useEffect(() => {
    const justFinishedLoading = prevLoadingRef.current && !loading;
    prevLoadingRef.current = loading;
    if (!canArrangeDuties || rosterLocked || loading) return;
    if (!justFinishedLoading || assignments.length > 0 || dutyRoles.length === 0) return;
    const pool = staffWorkingToday.length > 0 ? staffWorkingToday : staffInScope.filter((u) => !leaveIdsForDate.has(u.id));
    if (pool.length === 0) return;
    const key = `${branchId}|${shiftId}|${assignmentDate}`;
    if (autoAssignedKeyRef.current === key) return;
    autoAssignedKeyRef.current = key;
    randomAssign();
  }, [canArrangeDuties, rosterLocked, loading, assignments.length, dutyRoles.length, staffWorkingToday.length, staffInScope.length, branchId, shiftId, assignmentDate]);

  /** ปรับกลุ่มที่เลือกเมื่อ staff ไม่มีคนในกลุ่มนั้น (ใช้กลุ่มแรกที่มี) */
  useEffect(() => {
    if (staff.length === 0) return;
    const hasStaff = staff.some((s) => s.role === 'staff');
    const hasInstructor = staff.some((s) => s.role === 'instructor' || s.role === 'instructor_head');
    if (userGroupFilter === 'STAFF' && !hasStaff && hasInstructor) setUserGroupFilter('INSTRUCTOR');
    else if (userGroupFilter === 'INSTRUCTOR' && !hasInstructor && hasStaff) setUserGroupFilter('STAFF');
  }, [staff, userGroupFilter]);

  useEffect(() => {
    if (!branchId || !shiftId || !assignmentDate) return;
    let debounceTimer: ReturnType<typeof setTimeout> | null = null;
    let mounted = true;
    const channel = supabase
      .channel('duty_assignments')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'duty_assignments' }, () => {
        if (debounceTimer) clearTimeout(debounceTimer);
        debounceTimer = setTimeout(() => {
          debounceTimer = null;
          if (!mounted) return;
          supabase
            .from('duty_assignments')
            .select('id, branch_id, shift_id, duty_role_id, user_id, assignment_date')
            .eq('branch_id', branchId)
            .eq('shift_id', shiftId)
            .eq('assignment_date', assignmentDate)
            .then(({ data }) => { if (mounted) setAssignments(data || []); });
        }, 300);
      })
      .subscribe();
    return () => {
      mounted = false;
      if (debounceTimer) clearTimeout(debounceTimer);
      supabase.removeChannel(channel);
    };
  }, [branchId, shiftId, assignmentDate]);

  const getAssignments = (roleId: string) => assignments.filter((a) => a.duty_role_id === roleId);
  const getUsersForRole = (roleId: string): Profile[] =>
    getAssignments(roleId)
      .map((a) => (a.user_id ? staff.find((s) => s.id === a.user_id) : null))
      .filter((p): p is Profile => p != null);

  const handleDrop = async (roleId: string, userIdFromDrop?: string) => {
    if (!canArrangeDuties || rosterLocked) return;
    const userId = (userIdFromDrop && userIdFromDrop.trim()) || draggedUser;
    if (!userId) {
      toast.show('ไม่สามารถระบุผู้ใช้ได้ — ลองลากชื่อมาวางที่ช่อง "วางที่นี่" อีกครั้ง', 'error');
      return;
    }
    setDraggedUser(null);
    const role = dutyRoles.find((r) => r.id === roleId);
    if (!role) return;
    if (assignments.some((a) => a.duty_role_id === roleId && a.user_id === userId)) {
      toast.show('คนนี้อยู่ในหน้าที่นี้แล้ว', 'info');
      return;
    }
    setLoading(true);
    const { error } = await supabase.from('duty_assignments').insert({
      branch_id: branchId,
      shift_id: shiftId,
      duty_role_id: roleId,
      user_id: userId,
      assignment_date: assignmentDate,
    });
    if (error) {
      if (error.code === '23505') {
        const { data } = await supabase.from('duty_assignments').select('id, branch_id, shift_id, duty_role_id, user_id, assignment_date').eq('branch_id', branchId).eq('shift_id', shiftId).eq('assignment_date', assignmentDate);
        setAssignments(data || []);
        toast.show(
          'ไม่สามารถเพิ่มได้ — คนนี้อยู่ในหน้าที่นี้แล้ว หรือฐานข้อมูลยังจำกัดหนึ่งคนต่อหนึ่งหน้าที่ (ให้รัน migration 22_duty_assignments_ensure_multi_user.sql ใน Supabase)',
          'error'
        );
      } else {
        toast.show(`เพิ่มไม่ได้: ${error.message}`, 'error');
      }
      setLoading(false);
      return;
    }
    const roleName = dutyRoles.find((r) => r.id === roleId)?.name ?? '—';
    const userName = staff.find((s) => s.id === userId)?.display_name || staff.find((s) => s.id === userId)?.email || '—';
    await logAudit('duty_assign', 'duty_assignments', null, { duty_role_id: roleId, user_id: userId, assignment_date: assignmentDate }, `จัด ${userName} ในหน้าที่ ${roleName} วันที่ ${assignmentDate}`);
    const { data } = await supabase.from('duty_assignments').select('id, branch_id, shift_id, duty_role_id, user_id, assignment_date').eq('branch_id', branchId).eq('shift_id', shiftId).eq('assignment_date', assignmentDate);
    setAssignments(data || []);
    setLoading(false);
    toast.show('จัดหน้าที่แล้ว', 'success');
  };

  const clearAll = async () => {
    if (!canArrangeDuties || rosterLocked) return;
    if (!confirm('ล้างการจัดหน้าที่ทั้งหมดในวันนี้?')) return;
    setLoading(true);
    await supabase
      .from('duty_assignments')
      .delete()
      .eq('branch_id', branchId)
      .eq('shift_id', shiftId)
      .eq('assignment_date', assignmentDate);
    await logAudit('duty_clear', 'duty_assignments', null, { assignment_date: assignmentDate }, `ล้างการจัดหน้าที่ทั้งหมด วันที่ ${assignmentDate}`);
    setAssignments([]);
    setLoading(false);
  };

  const randomAssign = async () => {
    if (!canArrangeDuties || dutyRoles.length === 0) return;
    if (branchId && staffInScope.length === 0) {
      toast.show('ไม่มีพนักงานในขอบเขตนี้ (กลุ่ม/แผนก/กะ) — ตรวจสอบการจัดกะหรือกลุ่ม', 'error');
      return;
    }
    if (!branchId && staff.length === 0) return;
    if (rosterLocked) {
      toast.show('ตารางกะยืนยันแล้ว — ไม่สามารถสุ่มจัดได้', 'error');
      return;
    }
    setLoading(true);
    // ใช้รายชื่อ "มาทำงานวันนี้" เป็นหลัก — สุ่มให้ครบทุกคนในรายชื่อที่แสดง (ไม่ให้คนว่าง)
    const poolBase = staffWorkingToday.length > 0 ? staffWorkingToday : staffInScope;
    let pool: Profile[] = poolBase;

    if (staffWorkingToday.length === 0 && staffInScope.length > 0) {
      pool = pool.filter((u) => !leaveIdsForDate.has(u.id));
      toast.show('ไม่มีตารางกะในวันนี้ — ใช้เฉพาะคนที่ไม่ลาวันนี้ (อาจไม่ตรงกับตารางจริง)', 'info');
    } else if (staffWorkingToday.length > 0) {
      // มีคนมาทำงานวันนี้: ไม่กรอง sameBranch/sameShift (รายชื่อแสดงอยู่แล้วตรงกลุ่ม/แผนก/กะ) — เฉพาะเว็บถ้าเลือก
      if (autoFilter.sameWebsite && selectedWebsiteId) {
        const { data: assignRows } = await supabase.from('website_assignments').select('user_id').eq('website_id', selectedWebsiteId);
        const userIdsWithWebsite = new Set((assignRows || []).map((r: { user_id: string }) => r.user_id));
        pool = pool.filter((u) => userIdsWithWebsite.has(u.id));
      }
    } else {
      if (autoFilter.sameBranch) {
        pool = pool.filter((u) => (effectiveByUserByDate.get(u.id)?.get(assignmentDate)?.branch_id ?? u.default_branch_id) === branchId);
      }
      if (autoFilter.sameShift) {
        pool = pool.filter((u) => (effectiveByUserByDate.get(u.id)?.get(assignmentDate)?.shift_id ?? u.default_shift_id) === shiftId);
      }
      if (autoFilter.sameWebsite && selectedWebsiteId) {
        const { data: assignRows } = await supabase.from('website_assignments').select('user_id').eq('website_id', selectedWebsiteId);
        const userIdsWithWebsite = new Set((assignRows || []).map((r: { user_id: string }) => r.user_id));
        pool = pool.filter((u) => userIdsWithWebsite.has(u.id));
      }
    }

    if (pool.length === 0) {
      toast.show('ไม่พบพนักงานที่ตรงกับเงื่อนไข', 'error');
      setLoading(false);
      return;
    }

    await supabase
      .from('duty_assignments')
      .delete()
      .eq('branch_id', branchId)
      .eq('shift_id', shiftId)
      .eq('assignment_date', assignmentDate);

    const shuffled = [...pool].sort(() => Math.random() - 0.5);
    for (let i = 0; i < shuffled.length; i++) {
      const roleIndex = i % dutyRoles.length;
      const roleId = dutyRoles[roleIndex].id;
      const userId = shuffled[i].id;
      await supabase.from('duty_assignments').insert({
        branch_id: branchId,
        shift_id: shiftId,
        duty_role_id: roleId,
        user_id: userId,
        assignment_date: assignmentDate,
      });
    }
    await logAudit('duty_random', 'duty_assignments', null, { assignment_date: assignmentDate }, `สุ่มจัดหน้าที่อัตโนมัติ วันที่ ${assignmentDate}`);
    const { data } = await supabase
      .from('duty_assignments')
      .select('id, branch_id, shift_id, duty_role_id, user_id, assignment_date')
      .eq('branch_id', branchId)
      .eq('shift_id', shiftId)
      .eq('assignment_date', assignmentDate);
    setAssignments(data || []);
    toast.show(`สุ่มจัดให้ครบ ${pool.length} คนแล้ว`, 'info');
    setLoading(false);
  };

  const removeAssignment = async (assignmentId: string) => {
    if (!canArrangeDuties || rosterLocked) return;
    setLoading(true);
    await supabase.from('duty_assignments').delete().eq('id', assignmentId);
    setAssignments((prev) => prev.filter((a) => a.id !== assignmentId));
    setLoading(false);
  };

  const myAssignment = !canArrangeDuties ? assignments.find((a) => a.user_id === user?.id) : null;
  const myRole = myAssignment ? dutyRoles.find((r) => r.id === myAssignment.duty_role_id) : null;

  return (
    <div className="space-y-4">
      <PageHeader title="จัดหน้าที่" sticky />

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div className="w-full max-w-xl space-y-4">
          <PageCard
            title="ตัวกรองและวันที่"
            actions={
              canArrangeDuties ? (
                <span className="flex flex-wrap items-center gap-1.5">
                  {rosterLocked && <span className="text-amber-400 text-[11px]">ตารางกะยืนยันแล้ว</span>}
                  <Button variant="outline" onClick={randomAssign} loading={loading} disabled={rosterLocked} title="จัดอัตโนมัติจากคนที่มาทำงานวันนี้" className="px-2.5 py-1 text-[12px]">สุ่มจัด</Button>
                  <Button variant="ghost" onClick={clearAll} loading={loading} disabled={rosterLocked} className="px-2.5 py-1 text-[12px]">ล้างทั้งหมด</Button>
                </span>
              ) : undefined
            }
          >
            <div className="flex flex-wrap items-end gap-2">
              {canArrangeDuties && (
                <>
                  <div>
                    <label className="okace-label text-[11px]">กลุ่ม</label>
                    <select value={userGroupFilter} onChange={(e) => setUserGroupFilter(e.target.value as 'INSTRUCTOR' | 'STAFF')} className="okace-input min-w-0 w-[140px] text-[13px] py-1.5">
                      <option value="INSTRUCTOR">พนักงานประจำ (หน้างาน)</option>
                      <option value="STAFF">พนักงานออนไลน์</option>
                    </select>
                  </div>
                  <div>
                    <label className="okace-label text-[11px]">แผนก</label>
                    <select value={branchId} onChange={(e) => setBranchId(e.target.value)} className="okace-input min-w-0 w-[100px] text-[13px] py-1.5">
                      {branchesForSelect.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
                    </select>
                  </div>
                </>
              )}
              <div>
                <label className="okace-label text-[11px]">กะ</label>
                <select value={shiftId} onChange={(e) => setShiftId(e.target.value)} className="okace-input min-w-0 w-[90px] text-[13px] py-1.5">
                  {shifts.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select>
              </div>
              <div>
                <label className="okace-label text-[11px]">วันที่</label>
                <input type="date" value={assignmentDate} onChange={(e) => setAssignmentDate(e.target.value)} className="okace-input w-[120px] text-[13px] py-1.5" />
              </div>
            </div>
          </PageCard>

          {canManageDutyRoles && (
            <PageCard
              title="รายการหน้าที่ (ต่อแผนก)"
              actions={
                <Button variant="outline" onClick={() => { setModalRole({ open: true, role: null }); setRoleName(''); }}>เพิ่มหน้าที่</Button>
              }
            >
              <p className="text-[13px] text-gray-400 mb-3">แผนก: {branchesForSelect.find((b) => b.id === branchId)?.name ?? (branchId || '— เลือกแผนกด้านบน —')}</p>
              {branchId && (
                <>
                  <div className="flex flex-wrap items-center gap-3 mb-3">
                    <input type="text" placeholder="ค้นหา…" value={roleSearch} onChange={(e) => setRoleSearch(e.target.value)} className="okace-input w-44 placeholder-gray-500" />
                    {filteredDutyRoles.length > 0 && <span className="text-gray-500 text-[12px]">{filteredDutyRoles.length} รายการ</span>}
                  </div>
                  <div className="rounded-lg border border-premium-gold/20 overflow-hidden bg-premium-darker/30">
                    {filteredDutyRoles.length === 0 ? (
                      <p className="py-6 text-center text-gray-500 text-sm">ยังไม่มีรายการหน้าที่ หรือไม่พบตามคำค้น</p>
                    ) : (
                      <table className="w-full text-sm">
                        <thead>
                          <tr className="border-b border-premium-gold/20 bg-premium-darker/50">
                            <th className="text-left p-3 text-premium-gold font-medium">ชื่อหน้าที่</th>
                            <th className="text-left p-3 text-premium-gold font-medium w-28">การดำเนินการ</th>
                          </tr>
                        </thead>
                        <tbody>
                          {filteredDutyRoles.map((r) => (
                            <tr key={r.id} className="border-b border-premium-gold/10 hover:bg-premium-gold/5">
                              <td className="p-3 text-gray-200">{r.name}</td>
                              <td className="p-3">
                                <span className="inline-flex items-center gap-0.5">
                                  <BtnEdit onClick={() => { setRoleName(r.name); setModalRole({ open: true, role: r }); }} title="แก้ไข" />
                                  <BtnDelete onClick={() => deleteDutyRole(r.id)} title="ลบ" />
                                </span>
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    )}
                  </div>
                </>
              )}
            </PageCard>
          )}
        </div>

        {canArrangeDuties && (
          <div>
            <p className="text-gray-400 text-sm mb-1">{rosterLocked ? 'ตารางกะล็อกแล้ว (อ่านอย่างเดียว)' : 'ลากชื่อไปวางที่หน้าที่'}</p>
            {branchId && staffInScope.length === 0 ? (
              <p className="text-amber-400/90 text-sm mb-2">ไม่มีพนักงานในขอบเขตนี้ (กลุ่ม {userGroupFilter} / แผนก {branchesForSelect.find((b) => b.id === branchId)?.name ?? '—'} / กะ {shifts.find((s) => s.id === shiftId)?.name ?? '—'}) — ไปที่จัดการสมาชิกหรือตรวจสอบย้ายกะ/โอน</p>
            ) : (
              <p className="text-premium-gold/90 text-sm mb-2">วันนี้ (กลุ่ม {userGroupFilter} / แผนก {branchesForSelect.find((b) => b.id === branchId)?.name ?? '—'} / กะ {shifts.find((s) => s.id === shiftId)?.name ?? '—'}) มาทำงาน {staffWorkingToday.length} คน{staffNotWorkingToday.length > 0 ? ` (ไม่มาทำงาน ${staffNotWorkingToday.length} คน)` : ''}</p>
            )}
            <div className="flex flex-wrap gap-2 mb-4">
              {staffWorkingToday.map((s) => (
                <span
                  key={s.id}
                  draggable={!rosterLocked}
                  onDragStart={(e) => {
                    if (rosterLocked) return;
                    e.dataTransfer.setData('text/plain', s.id);
                    e.dataTransfer.effectAllowed = 'copy';
                    setDraggedUser(s.id);
                  }}
                  onDragEnd={() => { setDraggedUser(null); setDropTargetRoleId(null); }}
                  className={`px-3 py-1.5 rounded border border-premium-gold/40 bg-premium-gold/10 ${rosterLocked ? 'cursor-not-allowed opacity-80' : 'cursor-grab active:cursor-grabbing'}`}
                >
                  {s.display_name || s.email}
                </span>
              ))}
              {staffNotWorkingToday.map((s) => (
                <span
                  key={s.id}
                  draggable={!rosterLocked}
                  onDragStart={(e) => {
                    if (rosterLocked) return;
                    e.dataTransfer.setData('text/plain', s.id);
                    e.dataTransfer.effectAllowed = 'copy';
                    setDraggedUser(s.id);
                  }}
                  onDragEnd={() => { setDraggedUser(null); setDropTargetRoleId(null); }}
                  className={`px-3 py-1.5 rounded border border-premium-gold/20 bg-premium-darker/80 text-gray-500 ${rosterLocked ? 'cursor-not-allowed opacity-80' : 'cursor-grab active:cursor-grabbing'}`}
                  title="ไม่มีในตารางกะวันนี้หรือหยุด/ลา"
                >
                  {s.display_name || s.email}
                </span>
              ))}
            </div>
            <div className="space-y-4">
              {dutyRoles.map((role) => {
                const assignees = getUsersForRole(role.id);
                const roleAssignments = getAssignments(role.id);
                const isDropTarget = dropTargetRoleId === role.id;
                return (
                  <div
                    key={role.id}
                    onDragOver={!rosterLocked ? (e) => { e.preventDefault(); e.dataTransfer.dropEffect = 'copy'; setDropTargetRoleId(role.id); } : undefined}
                    onDragLeave={!rosterLocked ? () => setDropTargetRoleId((id) => (id === role.id ? null : id)) : undefined}
                    onDrop={!rosterLocked ? (e) => { e.preventDefault(); setDropTargetRoleId(null); const uid = e.dataTransfer.getData('text/plain'); handleDrop(role.id, uid || undefined); } : undefined}
                    className={`rounded-xl border-2 p-4 min-h-[88px] ${rosterLocked ? 'opacity-90 border-premium-gold/20 bg-premium-darker/40' : isDropTarget ? 'border-premium-gold bg-premium-gold/10' : 'border-premium-gold/30 bg-premium-darker/50'} ${!rosterLocked ? 'cursor-pointer' : ''}`}
                  >
                    <div className="flex items-center justify-between gap-2 mb-3">
                      <h3 className="text-premium-gold font-semibold text-[15px]">{role.name}</h3>
                      {assignees.length > 0 && (
                        <span className="text-[12px] text-gray-500">({assignees.length} คน)</span>
                      )}
                    </div>
                    <div className="flex flex-wrap items-center gap-2 min-h-[44px]">
                      {assignees.map((p, idx) => {
                        const assignmentId = roleAssignments[idx]?.id;
                        return (
                          <span key={p.id} className="inline-flex items-center gap-1 px-3 py-1.5 rounded-lg bg-premium-gold/15 border border-premium-gold/30 text-gray-200 text-[13px] shrink-0">
                            {p.display_name || p.email}
                            {canArrangeDuties && !rosterLocked && assignmentId && (
                              <button type="button" onClick={() => removeAssignment(assignmentId)} className="text-gray-400 hover:text-red-400 leading-none" title="เอาออก">×</button>
                            )}
                          </span>
                        );
                      })}
                      {!rosterLocked && (
                        <>
                          <select
                            value=""
                            onChange={(e) => {
                              const uid = e.target.value;
                              e.target.value = '';
                              if (uid) handleDrop(role.id, uid);
                            }}
                            className="okace-input min-w-[120px] text-[13px] py-1.5 shrink-0"
                            title="เลือกชื่อลงหน้าที่"
                          >
                            <option value="">+ เลือกชื่อ</option>
                            {staffWorkingToday
                              .filter((s) => !assignees.some((p) => p.id === s.id))
                              .map((s) => (
                                <option key={s.id} value={s.id}>{s.display_name || s.email}</option>
                              ))}
                            {staffNotWorkingToday
                              .filter((s) => !assignees.some((p) => p.id === s.id))
                              .map((s) => (
                                <option key={s.id} value={s.id}>{s.display_name || s.email} (ไม่มาวันนี้)</option>
                              ))}
                          </select>
                          <span
                            onDragOver={(e) => { e.preventDefault(); e.stopPropagation(); e.dataTransfer.dropEffect = 'copy'; setDropTargetRoleId(role.id); }}
                            onDragLeave={() => setDropTargetRoleId((id) => (id === role.id ? null : id))}
                            onDrop={(e) => { e.preventDefault(); e.stopPropagation(); setDropTargetRoleId(null); const uid = e.dataTransfer.getData('text/plain'); handleDrop(role.id, uid || undefined); }}
                            className={`inline-flex items-center justify-center min-w-[80px] min-h-[40px] px-3 py-2 rounded-lg border-2 border-dashed text-[12px] shrink-0 ${isDropTarget ? 'border-premium-gold bg-premium-gold/20 text-premium-gold' : 'border-premium-gold/40 text-gray-500 hover:border-premium-gold/60 hover:text-gray-400'}`}
                            title="หรือลากชื่อมาวาง"
                          >
                            ลากวาง
                          </span>
                        </>
                      )}
                      {assignees.length === 0 && rosterLocked && <span className="text-gray-500 text-[13px]">ยังไม่มีผู้ถูกจัด</span>}
                    </div>
                  </div>
                );
              })}
            </div>
            {dutyRoles.length === 0 && <p className="text-gray-500">ยังไม่มีรายการหน้าที่ กดปุ่ม &quot;เพิ่มหน้าที่&quot; ในบล็อกรายการหน้าที่ (ต่อแผนก) ด้านซ้าย</p>}
          </div>
        )}
      </div>

      {!canArrangeDuties && myRole && (
        <div className="border border-premium-gold/30 rounded-lg p-4 mb-6 inline-block">
          <p className="text-gray-400 text-sm">หน้าที่ของคุณในวันนี้</p>
          <p className="text-premium-gold text-lg font-medium">{myRole.name}</p>
        </div>
      )}

      <Modal open={modalRole.open} onClose={() => setModalRole({ open: false, role: null })} title={modalRole.role ? 'แก้ไขหน้าที่' : 'เพิ่มหน้าที่'} footer={
        <>
          <Button variant="ghost" onClick={() => setModalRole({ open: false, role: null })}>ยกเลิก</Button>
          <Button variant="gold" onClick={saveDutyRole} disabled={!roleName.trim()}>บันทึก</Button>
        </>
      }>
        <label className="block text-gray-400 text-sm mb-1">ชื่อหน้าที่</label>
        <input value={roleName} onChange={(e) => setRoleName(e.target.value)} className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white" placeholder="เช่น ฝาก-ถอน, แชท" />
      </Modal>
    </div>
  );
}
