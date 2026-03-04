import { useState, useEffect, useCallback, useRef } from 'react';
import { useLocation } from 'react-router-dom';
import { useDebouncedValue } from '../lib/useDebouncedValue';
import { supabase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import { createUsers, resetUserPassword } from '../lib/adminApi';
import { hasActiveScheduledShiftChange } from '../lib/transfers';
import { useBranchesShifts } from '../lib/BranchesShiftsContext';
import { canManageRole, getAllowedRoleValues } from '../lib/roles';
import { logAudit } from '../lib/audit';
import type { AppRole } from '../lib/adminApi';
import Button from '../components/ui/Button';
import Modal, { ConfirmModal } from '../components/ui/Modal';
import PaginationBar from '../components/ui/PaginationBar';

const ROLE_OPTIONS: { value: AppRole; label: string }[] = [
  { value: 'admin', label: 'ผู้ดูแลระบบ' },
  { value: 'manager', label: 'ผู้จัดการ' },
  { value: 'instructor_head', label: 'หัวหน้าพนักงานประจำ' },
  { value: 'instructor', label: 'พนักงานประจำ' },
  { value: 'staff', label: 'พนักงานออนไลน์' },
];

const ROLE_LABEL: Record<string, string> = {
  admin: 'ผู้ดูแลระบบ',
  manager: 'ผู้จัดการ',
  instructor_head: 'หัวหน้าพนักงานประจำ',
  instructor: 'พนักงานประจำ',
  staff: 'พนักงานออนไลน์',
};

function IconBtn({ onClick, disabled, title, iconD, className = '' }: { onClick: () => void; disabled?: boolean; title: string; iconD: string; className?: string }) {
  return (
    <button
      type="button"
      title={title}
      onClick={onClick}
      disabled={disabled}
      className={`p-1.5 rounded hover:bg-white/10 text-gray-300 hover:text-premium-gold disabled:opacity-40 disabled:cursor-not-allowed ${className}`}
    >
      <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
        <path strokeLinecap="round" strokeLinejoin="round" d={iconD} />
      </svg>
    </button>
  );
}
const ICON = {
  edit: 'M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z',
  key: 'M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z',
  ban: 'M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636',
  check: 'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z',
};

type ProfileRow = {
  id: string; email: string; display_name: string | null; role: string; default_branch_id: string | null; default_shift_id: string | null; active: boolean;
  telegram?: string | null; lock_code?: string | null; email_code?: string | null; computer_code?: string | null; work_access_code?: string | null; two_fa?: string | null;
  avatar_url?: string | null; link1_url?: string | null; link2_url?: string | null; note_title?: string | null; note_body?: string | null;
};

export default function MemberManagement() {
  const { profile } = useAuth();
  const location = useLocation();
  const { branches, shifts } = useBranchesShifts();
  const isAdmin = profile?.role === 'admin';
  const isManager = profile?.role === 'manager';
  const isInstructorHead = profile?.role === 'instructor_head';
  const canManageMembers = isAdmin || isManager || isInstructorHead;
  const [members, setMembers] = useState<ProfileRow[]>([]);
  const [search, setSearch] = useState('');
  const [modal, setModal] = useState(false);
  const [bulkNames, setBulkNames] = useState('');
  const [bulkPassword, setBulkPassword] = useState('');
  const [bulkRole, setBulkRole] = useState<AppRole>('staff');
  const [bulkBranchId, setBulkBranchId] = useState('');
  const [bulkShiftId, setBulkShiftId] = useState('');
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<{ type: 'ok' | 'err'; text: string } | null>(null);
  const [lastResult, setLastResult] = useState<{ created: number; skipped_duplicates: string[]; failed: { username: string; reason: string }[] } | null>(null);

  const [editTarget, setEditTarget] = useState<ProfileRow | null>(null);
  const [editForm, setEditForm] = useState<{ display_name: string; role: AppRole; default_branch_id: string; default_shift_id: string }>({ display_name: '', role: 'staff', default_branch_id: '', default_shift_id: '' });
  const [editLoading, setEditLoading] = useState(false);
  const [editTargetHasScheduledShift, setEditTargetHasScheduledShift] = useState(false);

  const [passwordTarget, setPasswordTarget] = useState<ProfileRow | null>(null);
  const [passwordNew, setPasswordNew] = useState('');
  const [passwordConfirm, setPasswordConfirm] = useState('');
  const [passwordLoading, setPasswordLoading] = useState(false);

  const [deleteTarget, setDeleteTarget] = useState<{ row: ProfileRow; action: 'deactivate' | 'activate' } | null>(null);
  const [deleteLoading, setDeleteLoading] = useState(false);

  const [filterBranchId, setFilterBranchId] = useState('');
  const myBranchId = profile?.default_branch_id ?? '';
  const [filterWebsiteId, setFilterWebsiteId] = useState('');
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(20);
  const [totalCount, setTotalCount] = useState(0);
  const [membersLoading, setMembersLoading] = useState(false);
  const [websites, setWebsites] = useState<{ id: string; name: string; alias: string; branch_id: string }[]>([]);
  const [userIdsByWebsite, setUserIdsByWebsite] = useState<Record<string, string[]>>({});
  const [memberManagedWebsites, setMemberManagedWebsites] = useState<Record<string, string>>({});
  const [assignmentsRefreshKey, setAssignmentsRefreshKey] = useState(0);
  const refreshListKeyRef = useRef(0);

  const PROFILE_SELECT = 'id, email, display_name, role, default_branch_id, default_shift_id, active, telegram, lock_code, email_code, computer_code, work_access_code, two_fa, avatar_url, link1_url, link2_url, note_title, note_body';

  const fetchMembers = useCallback(
    async (p: number, size: number, searchQ: string, branchId: string, websiteId: string, websiteUserIds: string[] | undefined) => {
      if (!canManageMembers) return;
      const myId = ++refreshListKeyRef.current;
      setMembersLoading(true);
      try {
        let q = supabase
          .from('profiles')
          .select(PROFILE_SELECT, { count: 'exact' })
          .order('display_name', { ascending: true });
        if (websiteId && websiteUserIds !== undefined) {
          if (websiteUserIds.length === 0) {
            if (myId === refreshListKeyRef.current) {
              setMembers([]);
              setTotalCount(0);
            }
            return;
          }
          q = q.in('id', websiteUserIds);
        }
        if (branchId) q = q.eq('default_branch_id', branchId);
        const searchTrim = searchQ.trim();
        if (searchTrim) {
          const esc = searchTrim.replace(/'/g, "''");
          q = q.or(`display_name.ilike.%${esc}%,email.ilike.%${esc}%`);
        }
        const from = (p - 1) * size;
        const { data, error, count } = await q.range(from, from + size - 1);
        if (myId !== refreshListKeyRef.current) return;
        if (error) {
          setMembers([]);
          setTotalCount(0);
          return;
        }
        setMembers((data || []) as ProfileRow[]);
        setTotalCount(typeof count === 'number' ? count : 0);
      } finally {
        if (myId === refreshListKeyRef.current) setMembersLoading(false);
      }
    },
    [canManageMembers]
  );

  const refetchMembers = useCallback(() => {
    setAssignmentsRefreshKey((k) => k + 1);
  }, []);

  const debouncedSearch = useDebouncedValue(search, 300);

  useEffect(() => {
    if (!canManageMembers) return;
    const websiteIds = filterWebsiteId ? userIdsByWebsite[filterWebsiteId] : undefined;
    if (filterWebsiteId && websiteIds === undefined) {
      supabase
        .from('website_assignments')
        .select('user_id')
        .eq('website_id', filterWebsiteId)
        .then(({ data }) => {
          const ids = (data || []).map((r: { user_id: string }) => r.user_id);
          setUserIdsByWebsite((prev) => ({ ...prev, [filterWebsiteId]: ids }));
        });
      return;
    }
    fetchMembers(page, pageSize, debouncedSearch, filterBranchId, filterWebsiteId, websiteIds);
  }, [canManageMembers, page, pageSize, debouncedSearch, filterBranchId, filterWebsiteId, userIdsByWebsite, fetchMembers, assignmentsRefreshKey]);

  useEffect(() => {
    if (isAdmin || isManager || isInstructorHead) return;
    if (myBranchId && filterBranchId !== myBranchId) setFilterBranchId(myBranchId);
  }, [isAdmin, isManager, isInstructorHead, myBranchId, filterBranchId]);

  useEffect(() => {
    if (!canManageMembers) return;
    supabase.from('websites').select('id, name, alias, branch_id').order('name').then(({ data }) => setWebsites((data || []) as { id: string; name: string; alias: string; branch_id: string }[]));
  }, [canManageMembers]);

  useEffect(() => {
    if (canManageMembers && location.pathname === '/จัดการสมาชิก') {
      setAssignmentsRefreshKey((k) => k + 1);
    }
  }, [canManageMembers, location.pathname]);

  useEffect(() => {
    setPage(1);
  }, [debouncedSearch, filterBranchId, filterWebsiteId]);

  useEffect(() => {
    if (!canManageMembers || members.length === 0) return;
    const memberIds = members.map((m) => m.id);
    supabase
      .from('website_assignments')
      .select('user_id, is_primary, website:websites(name, alias)')
      .in('user_id', memberIds)
      .then(({ data }) => {
        type Row = { user_id: string; is_primary: boolean; website: { name: string; alias: string } | { name: string; alias: string }[] | null };
        const rows = (data || []) as unknown as Row[];
        const byUser: Record<string, { name: string; is_primary: boolean }[]> = {};
        rows.forEach((r) => {
          if (!byUser[r.user_id]) byUser[r.user_id] = [];
          const w = Array.isArray(r.website) ? r.website[0] ?? null : r.website;
          const name = w?.name || w?.alias || '-';
          byUser[r.user_id].push({ name, is_primary: Boolean(r.is_primary) });
        });
        const map: Record<string, string> = {};
        Object.keys(byUser).forEach((uid) => {
          const list = byUser[uid];
          list.sort((a, b) => (b.is_primary ? 1 : 0) - (a.is_primary ? 1 : 0));
          map[uid] = list.map((x) => (x.is_primary ? `${x.name} (หลัก)` : x.name)).join(', ');
        });
        setMemberManagedWebsites(map);
      });
  }, [canManageMembers, members, assignmentsRefreshKey]);

  /** หัวหน้าแก้ไขได้เฉพาะผู้ใช้ระดับต่ำกว่า (instructor, staff) — ผู้จัดการและแอดมินเห็นทุกแผนกและจัดการได้ตามระดับ */
  const canEditMember = (m: ProfileRow) => {
    if (profile?.id === m.id) return false;
    if (!profile?.role) return false;
    if (!canManageRole(profile.role, m.role)) return false;
    if (isAdmin || isManager || isInstructorHead) return true;
    return m.default_branch_id === profile?.default_branch_id;
  };

  const submitBulk = async () => {
    const usernames = bulkNames
      .split(/\n/)
      .map((s) => s.trim())
      .filter(Boolean);
    if (usernames.length === 0) {
      setMessage({ type: 'err', text: 'กรุณากรอกชื่อผู้ใช้อย่างน้อย 1 รายการ (หนึ่งชื่อต่อหนึ่งแถว)' });
      return;
    }
    if (usernames.length > 50) {
      setMessage({ type: 'err', text: 'รับได้สูงสุด 50 คนต่อครั้ง กรุณาลดรายการหรือแบ่งส่งหลายรอบ' });
      return;
    }
    if (!bulkPassword || bulkPassword.length < 6) {
      setMessage({ type: 'err', text: 'รหัสผ่านต้องไม่ต่ำกว่า 6 ตัว' });
      return;
    }
    const bulkRoleNeedsBranchShift = ['staff', 'instructor', 'manager', 'instructor_head'].includes(bulkRole);
    if (bulkRoleNeedsBranchShift) {
      if (!effectiveBulkBranchId?.trim()) {
        setMessage({ type: 'err', text: 'กรุณาเลือกแผนกเริ่มต้น (จำเป็นสำหรับบทบาทนี้)' });
        return;
      }
      if (!bulkShiftId?.trim()) {
        setMessage({ type: 'err', text: 'กรุณาเลือกกะเริ่มต้น (จำเป็นสำหรับบทบาทนี้)' });
        return;
      }
    }
    setMessage(null);
    setLastResult(null);
    setLoading(true);
    try {
      const result = await createUsers({
        usernames,
        password: bulkPassword,
        role: bulkRole,
        default_branch_id: effectiveBulkBranchId || null,
        default_shift_id: bulkShiftId || null,
      });
      setLastResult({ created: result.created.length, skipped_duplicates: result.skipped_duplicates ?? [], failed: result.failed ?? [] });
      if (result.created.length > 0) {
        logAudit('user_create', 'profiles', null, { role: bulkRole, branch_id: effectiveBulkBranchId || undefined });
        const skipMsg = (result.skipped_duplicates?.length ?? 0) > 0 ? ` ข้ามซ้ำ ${result.skipped_duplicates!.length} คน` : '';
        const failMsg = result.failed.length > 0 ? ` ไม่สำเร็จ ${result.failed.length} คน` : '';
        setMessage({ type: 'ok', text: `สร้างสำเร็จ ${result.created.length} คน${skipMsg}${failMsg}` });
        setBulkNames((result.skipped_duplicates?.length ? result.skipped_duplicates.join('\n') + '\n' : '') + (result.failed.length > 0 ? result.failed.map((f) => f.username).join('\n') : ''));
        refetchMembers();
        setPage(1);
        setModal(false);
      } else if ((result.skipped_duplicates?.length ?? 0) + result.failed.length === 0) {
        setMessage({ type: 'err', text: 'สร้างไม่สำเร็จ' });
      } else {
        setMessage({ type: 'err', text: result.failed[0]?.reason ?? (result.skipped_duplicates?.length ? 'ชื่อผู้ใช้มีในระบบแล้ว' : 'สร้างไม่สำเร็จ') });
      }
    } catch (e) {
      setMessage({ type: 'err', text: e instanceof Error ? e.message : 'เกิดข้อผิดพลาด' });
    } finally {
      setLoading(false);
    }
  };

  if (!canManageMembers) {
    return (
      <div>
        <p className="text-gray-400">เฉพาะผู้ดูแลระบบ ผู้จัดการ หรือหัวหน้าพนักงานประจำเท่านั้น</p>
      </div>
    );
  }

  const allowedRoleValues = getAllowedRoleValues(profile?.role ?? '');
  const bulkRoleOptions = ROLE_OPTIONS.filter((o) => allowedRoleValues.includes(o.value));
  const showBranchSelector = isAdmin || isManager || isInstructorHead;
  const effectiveBulkBranchId = showBranchSelector ? bulkBranchId : (profile?.default_branch_id ?? '');

  return (
    <div>
      <h1 className="text-premium-gold text-xl font-semibold mb-4">จัดการสมาชิก</h1>

      <section className="mb-6">
        <Button variant="gold" onClick={() => { setModal(true); setMessage(null); setLastResult(null); setBulkNames(''); setBulkPassword(''); setBulkRole(bulkRoleOptions[0]?.value ?? 'staff'); setBulkBranchId(showBranchSelector ? (isAdmin ? (branches[0]?.id ?? '') : (profile?.default_branch_id ?? '')) : (profile?.default_branch_id ?? '')); setBulkShiftId(shifts[0]?.id ?? ''); }}>
          สร้างผู้ใช้หลายคน
        </Button>
      </section>

      {message && (
        <p className={`mb-3 text-sm ${message.type === 'ok' ? 'text-green-400' : 'text-red-400'}`}>{message.text}</p>
      )}
      <section>
        <h2 className="text-premium-gold font-medium mb-2">รายชื่อสมาชิก</h2>
        <div className="flex flex-wrap items-center gap-3 mb-3">
          <input
            type="text"
            placeholder="ค้นหาชื่อหรืออีเมล"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full max-w-xs bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white"
          />
          {showBranchSelector && (
            <div className="flex items-center gap-2">
              <label className="text-gray-400 text-sm whitespace-nowrap">แผนก</label>
              <select
                value={filterBranchId}
                onChange={(e) => setFilterBranchId(e.target.value)}
                className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white min-w-[6rem]"
              >
                <option value="">ทั้งหมด</option>
                {branches.map((b) => (
                  <option key={b.id} value={b.id}>{b.name}</option>
                ))}
              </select>
            </div>
          )}
          <div className="flex items-center gap-2">
            <label className="text-gray-400 text-sm whitespace-nowrap">เว็บที่ดูแล</label>
            <select
              value={filterWebsiteId}
              onChange={(e) => setFilterWebsiteId(e.target.value)}
              className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white min-w-[10rem]"
            >
              <option value="">ทั้งหมด</option>
              {websites.map((w) => (
                <option key={w.id} value={w.id}>{w.name} ({w.alias})</option>
              ))}
            </select>
          </div>
        </div>
        {membersLoading && <p className="text-gray-400 text-sm mb-2">กำลังโหลด...</p>}
        <div className="overflow-x-auto border border-premium-gold/20 rounded-lg">
          <table className="w-full text-sm">
            <thead>
              <tr>
                <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">ชื่อผู้ใช้</th>
                <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">บทบาท</th>
                <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">แผนก</th>
                <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">เว็บที่ดูแล</th>
                <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">กะ</th>
                <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">การดำเนินการ</th>
              </tr>
            </thead>
            <tbody>
              {members.map((m) => {
                const canEdit = canEditMember(m);
                return (
                  <tr key={m.id} className={`border-b border-premium-gold/10 ${m.active === false ? 'opacity-60' : ''}`}>
                    <td className="p-2 text-gray-200">{m.display_name || m.email || '-'}{m.active === false ? ' (ปิดใช้งาน)' : ''}</td>
                    <td className="p-2 text-gray-400">{ROLE_LABEL[m.role] ?? m.role}</td>
                    <td className="p-2 text-gray-400">{branches.find((b) => b.id === m.default_branch_id)?.name ?? '-'}</td>
                    <td className="p-2 text-gray-400">{memberManagedWebsites[m.id] || '-'}</td>
                    <td className="p-2 text-gray-400">{shifts.find((s) => s.id === m.default_shift_id)?.name ?? '-'}</td>
                    <td className="p-2">
                      <div className="flex flex-wrap gap-0.5">
                        <IconBtn title="แก้ไข" iconD={ICON.edit} disabled={!canEdit} onClick={() => { setEditTarget(m); setEditForm({ display_name: m.display_name ?? '', role: (m.role as AppRole), default_branch_id: m.default_branch_id ?? '', default_shift_id: m.default_shift_id ?? '' }); setEditTargetHasScheduledShift(false); hasActiveScheduledShiftChange(m.id).then(setEditTargetHasScheduledShift); }} />
                        <IconBtn title="เปลี่ยนรหัสผ่าน" iconD={ICON.key} disabled={!canEdit} onClick={() => { setPasswordTarget(m); setPasswordNew(''); setPasswordConfirm(''); }} />
                        {m.active !== false ? (
                          <IconBtn title="ปิดใช้งาน" iconD={ICON.ban} disabled={!canEdit} onClick={() => setDeleteTarget({ row: m, action: 'deactivate' })} />
                        ) : (
                          <IconBtn title="เปิดใช้งาน" iconD={ICON.check} disabled={!canEdit} onClick={() => setDeleteTarget({ row: m, action: 'activate' })} />
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <PaginationBar
          page={page}
          pageSize={pageSize}
          totalCount={totalCount}
          onPageChange={setPage}
          onPageSizeChange={setPageSize}
          pageSizeOptions={[10, 20, 50]}
          itemLabel="รายการ"
        />
      </section>

      <Modal
        open={!!editTarget}
        onClose={() => { setEditTarget(null); setEditTargetHasScheduledShift(false); }}
        title="แก้ไขข้อมูลสมาชิก"
        footer={
          <>
            <Button variant="ghost" onClick={() => setEditTarget(null)}>ปิด</Button>
            <Button variant="gold" loading={editLoading} onClick={async () => {
              if (!editTarget) return;
              const roleNeedsBranchShift = ['staff', 'instructor', 'manager', 'instructor_head'].includes(editForm.role);
              if (roleNeedsBranchShift) {
                if (showBranchSelector && !editForm.default_branch_id?.trim()) {
                  setMessage({ type: 'err', text: 'กรุณาเลือกแผนกเริ่มต้น (จำเป็นสำหรับบทบาทนี้)' });
                  return;
                }
                if (!editForm.default_shift_id?.trim()) {
                  setMessage({ type: 'err', text: 'กรุณาเลือกกะเริ่มต้น (จำเป็นสำหรับบทบาทนี้)' });
                  return;
                }
              }
              setEditLoading(true);
              setMessage(null);
              try {
                const payload = {
                  display_name: editForm.display_name.trim() || null,
                  role: editForm.role,
                  default_branch_id: (showBranchSelector ? editForm.default_branch_id : profile?.default_branch_id) || null,
                  default_shift_id: editForm.default_shift_id || null,
                };
                const { error } = await supabase.from('profiles').update(payload).eq('id', editTarget.id);
                if (error) throw error;
                logAudit('user_update', 'profiles', editTarget.id, { role: editForm.role });
                refetchMembers();
                setEditTarget(null);
              } catch (e) {
                setMessage({ type: 'err', text: e instanceof Error ? e.message : 'แก้ไขไม่สำเร็จ' });
              } finally {
                setEditLoading(false);
              }
            }}>บันทึก</Button>
          </>
        }
      >
        {editTarget && (
          <div className="space-y-3">
            <div>
              <label className="block text-gray-400 text-sm mb-1">ชื่อผู้ใช้ (display_name)</label>
              <input value={editForm.display_name} onChange={(e) => setEditForm((f) => ({ ...f, display_name: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white" />
            </div>
            <div>
              <label className="block text-gray-400 text-sm mb-1">บทบาท</label>
              <select value={editForm.role} onChange={(e) => setEditForm((f) => ({ ...f, role: e.target.value as AppRole }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white">
                {bulkRoleOptions.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
              </select>
            </div>
            {showBranchSelector ? (
              <div>
                <label className="block text-gray-400 text-sm mb-1">แผนกเริ่มต้น</label>
                <select value={editForm.default_branch_id} onChange={(e) => setEditForm((f) => ({ ...f, default_branch_id: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white">
                  <option value="">— ไม่ระบุ —</option>
                  {branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
                </select>
              </div>
            ) : (
              <div>
                <label className="block text-gray-400 text-sm mb-1">แผนก</label>
                <p className="text-premium-gold">{branches.find((b) => b.id === profile?.default_branch_id)?.name ?? 'แผนกของคุณ'}</p>
              </div>
            )}
            <div>
              <label className="block text-gray-400 text-sm mb-1">กะเริ่มต้น</label>
              <select value={editForm.default_shift_id} onChange={(e) => setEditForm((f) => ({ ...f, default_shift_id: e.target.value }))} disabled={editTargetHasScheduledShift} className={`w-full rounded px-3 py-2 text-white ${editTargetHasScheduledShift ? 'bg-premium-darker border border-premium-gold/20 cursor-not-allowed opacity-80' : 'bg-premium-dark border border-premium-gold/30'}`}>
                <option value="">— ไม่ระบุ —</option>
                {shifts.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
              {editTargetHasScheduledShift && (
                <p className="text-amber-400 text-xs mt-1">ไม่สามารถเปลี่ยนกะได้ เนื่องจากมีรายการตั้งเวลาย้ายกะที่ยังมีผล — กรุณายกเลิกหรือรอให้ครบก่อน (ยกเลิกได้ที่ ย้ายกะจำนวนมาก / ประวัติการทำรายการ)</p>
              )}
            </div>
            <div className="pt-3 mt-3 border-t border-premium-gold/15">
              <p className="text-premium-gold font-medium text-sm mb-2">ข้อมูลที่เจ้าตัวกรอก (บัญชีของฉัน)</p>
              <div className="overflow-x-auto rounded border border-premium-gold/15">
                <table className="w-full text-[13px]">
                  <tbody>
                    {[
                      { label: 'เบอร์ TELEGRAM', value: editTarget.telegram },
                      { label: 'รหัสล็อค', value: editTarget.lock_code },
                      { label: 'รหัส EMAIL', value: editTarget.email_code },
                      { label: 'รหัสคอม', value: editTarget.computer_code },
                      { label: 'รหัสเข้างาน', value: editTarget.work_access_code },
                      { label: '2FA', value: editTarget.two_fa },
                      { label: 'รูปโปรไฟล์', value: editTarget.avatar_url, isUrl: true },
                      { label: 'ลิงก์ 1', value: editTarget.link1_url, isUrl: true },
                      { label: 'ลิงก์ 2', value: editTarget.link2_url, isUrl: true },
                      { label: 'หัวข้อบันทึก', value: editTarget.note_title },
                      { label: 'เขียนบันทึก', value: editTarget.note_body },
                    ].map(({ label, value, isUrl }) => (
                      <tr key={label} className="border-b border-premium-gold/10">
                        <td className="py-1.5 px-2 text-gray-400 w-36">{label}</td>
                        <td className="py-1.5 px-2 text-gray-200">
                          {value ? (isUrl ? <a href={value.startsWith('http') ? value : `https://${value}`} target="_blank" rel="noopener noreferrer" className="text-premium-gold hover:underline truncate block max-w-[200px]">{value}</a> : <span className="break-words">{value}</span>) : '—'}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        )}
      </Modal>

      <Modal
        open={!!passwordTarget}
        onClose={() => setPasswordTarget(null)}
        title="เปลี่ยนรหัสผ่าน"
        footer={
          <>
            <Button variant="ghost" onClick={() => setPasswordTarget(null)}>ปิด</Button>
            <Button variant="gold" loading={passwordLoading} disabled={passwordLoading} onClick={async () => {
              if (!passwordTarget) return;
              if (passwordNew.length < 6) { setMessage({ type: 'err', text: 'รหัสผ่านต้องไม่ต่ำกว่า 6 ตัว' }); return; }
              if (passwordNew !== passwordConfirm) { setMessage({ type: 'err', text: 'รหัสผ่านไม่ตรงกัน' }); return; }
              setPasswordLoading(true);
              setMessage(null);
              try {
                await resetUserPassword(passwordTarget.id, passwordNew);
                setPasswordTarget(null);
                setMessage({ type: 'ok', text: 'ตั้งรหัสผ่านใหม่เรียบร้อย' });
              } catch (e) {
                setMessage({ type: 'err', text: e instanceof Error ? e.message : 'ตั้งรหัสผ่านไม่สำเร็จ' });
              } finally {
                setPasswordLoading(false);
              }
            }}>ตั้งรหัสผ่านใหม่</Button>
          </>
        }
      >
        {passwordTarget && (
          <div className="space-y-3">
            <p className="text-gray-400 text-sm">ผู้ใช้: {passwordTarget.display_name || passwordTarget.email}</p>
            <div>
              <label className="block text-gray-400 text-sm mb-1">รหัสผ่านใหม่ (ไม่ต่ำกว่า 6 ตัว)</label>
              <input type="password" value={passwordNew} onChange={(e) => setPasswordNew(e.target.value)} className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white" />
            </div>
            <div>
              <label className="block text-gray-400 text-sm mb-1">ยืนยันรหัสผ่านใหม่</label>
              <input type="password" value={passwordConfirm} onChange={(e) => setPasswordConfirm(e.target.value)} className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white" />
            </div>
          </div>
        )}
      </Modal>

      <ConfirmModal
        open={!!deleteTarget}
        onClose={() => setDeleteTarget(null)}
        onConfirm={async () => {
          if (!deleteTarget) return;
          setDeleteLoading(true);
          try {
            const { error } = await supabase.from('profiles').update({ active: deleteTarget.action === 'deactivate' ? false : true }).eq('id', deleteTarget.row.id);
            if (error) throw error;
            refetchMembers();
            setDeleteTarget(null);
          } catch (e) {
            setMessage({ type: 'err', text: e instanceof Error ? e.message : 'ดำเนินการไม่สำเร็จ' });
          } finally {
            setDeleteLoading(false);
          }
        }}
        title={deleteTarget?.action === 'deactivate' ? 'ปิดใช้งานสมาชิก' : 'เปิดใช้งานสมาชิก'}
        message={deleteTarget ? (deleteTarget.action === 'deactivate' ? <>ยืนยันปิดใช้งาน <strong>{deleteTarget.row.display_name || deleteTarget.row.email}</strong> หรือไม่? ผู้ใช้จะล็อกอินไม่ได้จนกว่าจะเปิดใช้งานใหม่</> : <>ยืนยันเปิดใช้งาน <strong>{deleteTarget.row.display_name || deleteTarget.row.email}</strong> กลับมา?</>) : null}
        confirmLabel={deleteTarget?.action === 'deactivate' ? 'ปิดใช้งาน' : 'เปิดใช้งาน'}
        variant="danger"
        loading={deleteLoading}
      />

      <Modal
        open={modal}
        onClose={() => setModal(false)}
        title="สร้างผู้ใช้หลายคน"
        footer={
          <>
            <Button variant="ghost" onClick={() => setModal(false)}>ปิด</Button>
            <Button variant="gold" onClick={submitBulk} loading={loading} disabled={loading}>สร้างทั้งหมด</Button>
          </>
        }
      >
        <div className="space-y-3">
          <p className="text-gray-400 text-sm">กรอกชื่อผู้ใช้ทีละแถว (หนึ่งชื่อต่อหนึ่งแถว) รหัสผ่านและบทบาทใช้ร่วมกันทุกคน</p>
          {message && <p className={message.type === 'ok' ? 'text-green-400 text-sm' : 'text-red-400 text-sm'}>{message.text}</p>}
          {lastResult && (lastResult.skipped_duplicates?.length > 0 || lastResult.failed.length > 0) && (
            <div className="text-amber-400 text-sm">
              {lastResult.skipped_duplicates?.length > 0 && <span>ข้ามซ้ำ: {lastResult.skipped_duplicates.join(', ')}</span>}
              {lastResult.skipped_duplicates?.length > 0 && lastResult.failed.length > 0 && ' · '}
              {lastResult.failed.length > 0 && <span>ไม่สำเร็จ: {lastResult.failed.map((f) => `${f.username} (${f.reason})`).join(', ')}</span>}
            </div>
          )}
          <div>
            <label className="block text-gray-400 text-sm mb-1">ชื่อผู้ใช้ (หนึ่งชื่อต่อหนึ่งแถว) *</label>
            <textarea
              value={bulkNames}
              onChange={(e) => setBulkNames(e.target.value)}
              rows={6}
              className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white font-mono text-sm"
              placeholder="PHET&#10;ARLOTT&#10;..."
            />
          </div>
          <div>
            <label className="block text-gray-400 text-sm mb-1">รหัสผ่านร่วมกัน (ไม่ต่ำกว่า 6 ตัว) *</label>
            <input type="password" value={bulkPassword} onChange={(e) => setBulkPassword(e.target.value)} className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white" />
          </div>
          <div>
            <label className="block text-gray-400 text-sm mb-1">บทบาท</label>
            <select value={bulkRole} onChange={(e) => setBulkRole(e.target.value as AppRole)} className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white">
              {bulkRoleOptions.map((o) => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </select>
          </div>
          {showBranchSelector ? (
            <div>
              <label className="block text-gray-400 text-sm mb-1">แผนกเริ่มต้น {['staff', 'instructor', 'manager', 'instructor_head'].includes(bulkRole) && <span className="text-amber-400">*</span>}</label>
              <select value={bulkBranchId} onChange={(e) => setBulkBranchId(e.target.value)} className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white">
                <option value="">— ไม่ระบุ —</option>
                {branches.map((b) => (
                  <option key={b.id} value={b.id}>{b.name}</option>
                ))}
              </select>
              {['staff', 'instructor', 'manager', 'instructor_head'].includes(bulkRole) && !bulkBranchId && <p className="text-amber-400/90 text-xs mt-0.5">จำเป็นสำหรับบทบาทนี้</p>}
            </div>
          ) : (
            <div>
              <label className="block text-gray-400 text-sm mb-1">แผนก</label>
              <p className="text-premium-gold">{branches.find((b) => b.id === profile?.default_branch_id)?.name ?? 'แผนกของคุณ'}</p>
            </div>
          )}
          <div>
            <label className="block text-gray-400 text-sm mb-1">กะเริ่มต้น {['staff', 'instructor', 'manager', 'instructor_head'].includes(bulkRole) && <span className="text-amber-400">*</span>}</label>
            <select value={bulkShiftId} onChange={(e) => setBulkShiftId(e.target.value)} className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white">
              <option value="">— ไม่ระบุ —</option>
              {shifts.map((s) => (
                <option key={s.id} value={s.id}>{s.name}</option>
              ))}
            </select>
            {['staff', 'instructor', 'manager', 'instructor_head'].includes(bulkRole) && !bulkShiftId && <p className="text-amber-400/90 text-xs mt-0.5">จำเป็นสำหรับบทบาทนี้</p>}
          </div>
        </div>
      </Modal>
    </div>
  );
}
