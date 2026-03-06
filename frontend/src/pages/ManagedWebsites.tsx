import { useState, useEffect, useMemo, useCallback, useRef } from 'react';
import { useAuth } from '../lib/auth';
import { supabase } from '../lib/supabase';
import { invalidate } from '../lib/queryCache';
import {
  listWebsitesForAdmin,
  listStaffForAssignments,
  listStaffForAssignmentsPaginated,
  listWebsitesForAdminPaginated,
  listAllAssignmentsForAdmin,
  adminCreateWebsite,
  adminUpdateWebsite,
  adminDeleteWebsite,
  adminAssignWebsiteToUser,
  adminUnassignWebsiteFromUser,
  adminSetPrimaryWebsite,
} from '../lib/websites';
import type { Website, Branch, Profile, Shift } from '../lib/types';
import type { AssignmentRow } from '../lib/websites';
import Button from '../components/ui/Button';
import Modal, { ConfirmModal } from '../components/ui/Modal';
import { PageHeader } from '../components/layout';
import { BtnEdit, BtnDelete } from '../components/ui/ActionIcons';
import { UserSiteTable, type UserSiteRow } from '../components/UserSiteTable';
import { UserSiteEditModal } from '../components/UserSiteEditModal';

function groupAssignmentsByUser(assignments: AssignmentRow[], staffList: Profile[]): UserSiteRow[] {
  const byUserId = new Map<string, { user: Profile; sites: AssignmentRow[] }>();
  for (const a of assignments) {
    const uid = a.user_id;
    if (!byUserId.has(uid)) {
      const user = (a as AssignmentRow).user ?? staffList.find((p) => p.id === uid);
      const fallbackProfile: Profile = { id: uid, email: '', display_name: null, role: 'instructor', default_branch_id: null, default_shift_id: null, active: true, created_at: '', updated_at: '' };
      byUserId.set(uid, { user: user ?? fallbackProfile, sites: [] });
    }
    byUserId.get(uid)!.sites.push(a);
  }
  const staffIds = new Set(staffList.map((p) => p.id));
  const rows: UserSiteRow[] = [];
  for (const p of staffList) {
    const entry = byUserId.get(p.id);
    const sites = entry?.sites ?? [];
    const mainSiteId = sites.find((s) => s.is_primary)?.website_id ?? null;
    rows.push({ user: entry?.user ?? p, sites, mainSiteId });
  }
  for (const [uid, entry] of byUserId) {
    if (staffIds.has(uid)) continue;
    const mainSiteId = entry.sites.find((s) => s.is_primary)?.website_id ?? null;
    rows.push({ user: entry.user, sites: entry.sites, mainSiteId });
  }
  return rows.sort((a, b) => (a.user.display_name || a.user.email || '').localeCompare(b.user.display_name || b.user.email || ''));
}

type Tab = 'websites' | 'assignments';
type BranchOption = { id: string; name: string; code?: string | null };
type ShiftOption = { id: string; name: string; code?: string | null };

export default function ManagedWebsites() {
  const { profile } = useAuth();
  const isAdmin = profile?.role === 'admin';
  const isManager = profile?.role === 'manager';
  const isInstructorHead = profile?.role === 'instructor_head';
  const canManageWebsites = isAdmin || isManager || isInstructorHead;

  /** เปลี่ยนเว็บหลักได้เฉพาะแอดมิน/ผู้จัดการ/หัวหน้า — หัวหน้ามีสิทธิ์เท่าผู้จัดการ (เห็นทุกแผนก) */
  const canSetPrimaryFor = (_a: AssignmentRow) => isAdmin || isManager || isInstructorHead;
  const [tab, setTab] = useState<Tab>('websites');
  const [websites, setWebsites] = useState<(Website & { branch?: Branch })[]>([]);
  const [search, setSearch] = useState('');
  const [modalWebsite, setModalWebsite] = useState<{ open: boolean; website?: Website | null }>({ open: false });
  const [formWebsite, setFormWebsite] = useState({ name: '', alias: '', url: '', description: '', logo_path: '' });
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState('');

  const [staffList, setStaffList] = useState<Profile[]>([]);
  const [selectedUserIds, setSelectedUserIds] = useState<string[]>([]);
  const [selectedWebsiteIds, setSelectedWebsiteIds] = useState<string[]>([]);
  const [allAssignments, setAllAssignments] = useState<AssignmentRow[]>([]);
  const [modalAssign, setModalAssign] = useState(false);
  const [assignWebsiteId, setAssignWebsiteId] = useState('');
  const [confirmUnassign, setConfirmUnassign] = useState<string | null>(null);
  const [confirmDelete, setConfirmDelete] = useState<string | null>(null);
  const [editModalRow, setEditModalRow] = useState<UserSiteRow | null>(null);

  // Assignment tab: filter & pagination state (dropdown options from select id,name,code)
  const [branches, setBranches] = useState<BranchOption[]>([]);
  const [shifts, setShifts] = useState<ShiftOption[]>([]);
  const [userSearch, setUserSearch] = useState('');
  const [userSearchDebounced, setUserSearchDebounced] = useState('');
  const [branchId, setBranchId] = useState('');
  const [shiftId, setShiftId] = useState('');
  const [roleFilter, setRoleFilter] = useState('');
  const [staffPage, setStaffPage] = useState<Profile[]>([]);
  const [staffOffset, setStaffOffset] = useState(0);
  const [staffHasMore, setStaffHasMore] = useState(false);
  const [staffLoading, setStaffLoading] = useState(false);
  const [webSearch, setWebSearch] = useState('');
  const [webSearchDebounced, setWebSearchDebounced] = useState('');
  const [websitesPage, setWebsitesPage] = useState<(Website & { branch?: Branch })[]>([]);
  const [webOffset, setWebOffset] = useState(0);
  const [webHasMore, setWebHasMore] = useState(false);
  const [webLoading, setWebLoading] = useState(false);
  const staffScrollRef = useRef<HTMLDivElement>(null);
  const webScrollRef = useRef<HTMLDivElement>(null);
  const PAGE_SIZE = 50;

  // Debounce search (300ms)
  useEffect(() => {
    const t = setTimeout(() => setUserSearchDebounced(userSearch), 300);
    return () => clearTimeout(t);
  }, [userSearch]);
  useEffect(() => {
    const t = setTimeout(() => setWebSearchDebounced(webSearch), 300);
    return () => clearTimeout(t);
  }, [webSearch]);

  const toggleUserSelection = (id: string) => {
    setSelectedUserIds((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  };
  const toggleWebsiteSelection = (id: string) => {
    setSelectedWebsiteIds((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  };
  const selectAllFilteredUsers = () => {
    const ids = new Set(selectedUserIds);
    staffPage.forEach((p) => ids.add(p.id));
    setSelectedUserIds(Array.from(ids));
  };
  const clearAllUsers = () => setSelectedUserIds([]);
  const selectAllFilteredWebsites = () => {
    const ids = new Set(selectedWebsiteIds);
    websitesPage.forEach((w) => ids.add(w.id));
    setSelectedWebsiteIds(Array.from(ids));
  };
  const clearAllWebsites = () => setSelectedWebsiteIds([]);

  useEffect(() => {
    if (!canManageWebsites) return;
    listWebsitesForAdmin(search ? { search } : {}).then(setWebsites);
  }, [canManageWebsites, search]);

  useEffect(() => {
    if (!canManageWebsites) return;
    listStaffForAssignments().then(setStaffList);
  }, [canManageWebsites]);

  useEffect(() => {
    if (tab === 'assignments' && canManageWebsites) {
      listAllAssignmentsForAdmin().then(setAllAssignments);
      listWebsitesForAdmin({}).then(setWebsites);
      supabase.from('branches').select('id, name, code').eq('active', true).order('name').then(({ data }) => setBranches(data || []));
      supabase.from('shifts').select('id, name, code').eq('active', true).order('sort_order').then(({ data }) => setShifts(data || []));
    }
  }, [tab, canManageWebsites]);

  // Staff table: fetch first page when filters change
  const fetchStaffPage = useCallback(
    (offset: number, append: boolean) => {
      if (!canManageWebsites || tab !== 'assignments') return;
      setStaffLoading(true);
      listStaffForAssignmentsPaginated({
        search: userSearchDebounced || undefined,
        branch_id: branchId || undefined,
        shift_id: shiftId || undefined,
        role: roleFilter || undefined,
        limit: PAGE_SIZE,
        offset,
      }).then(({ data, hasMore }) => {
        setStaffLoading(false);
        if (append) setStaffPage((prev) => [...prev, ...data]);
        else setStaffPage(data);
        setStaffHasMore(hasMore);
        setStaffOffset(offset + data.length);
      }).catch(() => setStaffLoading(false));
    },
    [canManageWebsites, tab, userSearchDebounced, branchId, shiftId, roleFilter]
  );

  useEffect(() => {
    if (tab !== 'assignments') return;
    setStaffOffset(0);
    fetchStaffPage(0, false);
  }, [tab, userSearchDebounced, branchId, shiftId, roleFilter]);

  const loadMoreStaff = useCallback(() => {
    if (staffLoading || !staffHasMore) return;
    fetchStaffPage(staffOffset, true);
  }, [staffLoading, staffHasMore, staffOffset, fetchStaffPage]);

  // Website table: fetch first page when search change
  const fetchWebsitesPage = useCallback(
    (offset: number, append: boolean) => {
      if (!canManageWebsites || tab !== 'assignments') return;
      setWebLoading(true);
      listWebsitesForAdminPaginated({
        search: webSearchDebounced || undefined,
        limit: PAGE_SIZE,
        offset,
      }).then(({ data, hasMore }) => {
        setWebLoading(false);
        if (append) setWebsitesPage((prev) => [...prev, ...data]);
        else setWebsitesPage(data);
        setWebHasMore(hasMore);
        setWebOffset(offset + data.length);
      }).catch(() => setWebLoading(false));
    },
    [canManageWebsites, tab, webSearchDebounced]
  );

  useEffect(() => {
    if (tab !== 'assignments') return;
    setWebOffset(0);
    fetchWebsitesPage(0, false);
  }, [tab, webSearchDebounced]);

  const loadMoreWebsites = useCallback(() => {
    if (webLoading || !webHasMore) return;
    fetchWebsitesPage(webOffset, true);
  }, [webLoading, webHasMore, webOffset, fetchWebsitesPage]);

  const saveWebsite = async () => {
    setErr('');
    if (!formWebsite.name.trim() || !formWebsite.alias.trim()) {
      setErr('กรุณากรอกชื่อเว็บ และนามสกุล (alias)');
      return;
    }
    setLoading(true);
    try {
      if (modalWebsite.website?.id) {
        await adminUpdateWebsite(modalWebsite.website.id, {
          name: formWebsite.name.trim(),
          alias: formWebsite.alias.trim(),
          url: formWebsite.url.trim() || null,
          description: formWebsite.description.trim() || null,
          logo_path: formWebsite.logo_path.trim() || null,
        });
      } else {
        await adminCreateWebsite({
          name: formWebsite.name.trim(),
          alias: formWebsite.alias.trim(),
          url: formWebsite.url.trim() || null,
          description: formWebsite.description.trim() || null,
          logo_path: formWebsite.logo_path.trim() || null,
        });
      }
      setModalWebsite({ open: false });
      refetchWebsites();
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'เกิดข้อผิดพลาด');
    } finally {
      setLoading(false);
    }
  };

  const refetchWebsites = () => {
    listWebsitesForAdmin(search ? { search } : {}).then(setWebsites);
  };

  /** โหลด assignments ใหม่หลัง mutate — ล้าง cache ก่อนเพื่อให้ได้ข้อมูลล่าสุด */
  const refetchAssignments = useCallback(() => {
    invalidate('website_assignments');
    listAllAssignmentsForAdmin().then(setAllAssignments);
  }, []);

  const deleteWebsite = async (id: string) => {
    setLoading(true);
    try {
      await adminDeleteWebsite(id);
      setConfirmDelete(null);
      refetchWebsites();
      if (tab === 'assignments') refetchAssignments();
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'เกิดข้อผิดพลาด');
    } finally {
      setLoading(false);
    }
  };

  const addAssignment = async () => {
    if (!selectedUserIds.length || !assignWebsiteId) return;
    setLoading(true);
    setErr('');
    try {
      for (const uid of selectedUserIds) {
        try {
          await adminAssignWebsiteToUser(assignWebsiteId, uid);
        } catch (e: unknown) {
          const err = e as { code?: string };
          if (err?.code !== '23505') throw e;
        }
      }
      setModalAssign(false);
      setAssignWebsiteId('');
      refetchAssignments();
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'เกิดข้อผิดพลาด');
    } finally {
      setLoading(false);
    }
  };

  const batchAssign = async () => {
    if (!selectedUserIds.length || !selectedWebsiteIds.length) {
      setErr('กรุณาเลือกอย่างน้อย 1 ผู้ใช้ และ 1 เว็บ');
      return;
    }
    setLoading(true);
    setErr('');
    let assigned = 0;
    let skipped = 0;
    try {
      const existing = new Set(allAssignments.map((a) => `${a.user_id}:${a.website_id}`));
      for (const uid of selectedUserIds) {
        for (const wid of selectedWebsiteIds) {
          if (existing.has(`${uid}:${wid}`)) {
            skipped += 1;
            continue;
          }
          try {
            await adminAssignWebsiteToUser(wid, uid);
            assigned += 1;
            existing.add(`${uid}:${wid}`);
          } catch (e: unknown) {
            const err = e as { message?: string };
            if (err?.message?.includes('duplicate') || (e as { code?: string })?.code === '23505') skipped += 1;
            else throw e;
          }
        }
      }
      refetchAssignments();
      setSelectedWebsiteIds([]);
      if (assigned) setErr('');
      if (skipped && !assigned) setErr('รายการที่เลือกมีอยู่แล้วทั้งหมด');
      else if (assigned && skipped) setErr(`มอบหมายแล้ว ${assigned} รายการ (ข้าม ${skipped} ที่มีอยู่แล้ว)`);
      else if (assigned) setErr(`มอบหมายแล้ว ${assigned} รายการ`);
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'เกิดข้อผิดพลาด');
    } finally {
      setLoading(false);
    }
  };

  const unassign = async (assignmentId: string) => {
    setLoading(true);
    try {
      await adminUnassignWebsiteFromUser(assignmentId);
      setConfirmUnassign(null);
      refetchAssignments();
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'เกิดข้อผิดพลาด');
    } finally {
      setLoading(false);
    }
  };

  const setPrimary = async (userId: string, websiteId: string) => {
    setLoading(true);
    try {
      await adminSetPrimaryWebsite(userId, websiteId);
      refetchAssignments();
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'เกิดข้อผิดพลาด');
    } finally {
      setLoading(false);
    }
  };

  const assignOneAndRefetch = async (websiteId: string, userId: string) => {
    await adminAssignWebsiteToUser(websiteId, userId);
    refetchAssignments();
  };

  const groupedRows = useMemo(
    () => groupAssignmentsByUser(allAssignments, staffList),
    [allAssignments, staffList]
  );

  if (!canManageWebsites) {
    return (
      <div>
        <p className="text-gray-400">ไม่มีสิทธิ์เข้าหน้าจัดการเว็บที่ดูแล</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <PageHeader title="เว็บที่ดูแล" sticky />
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          onClick={() => setTab('websites')}
          className={`px-3 py-2 rounded font-medium transition ${tab === 'websites' ? 'bg-premium-gold/20 text-premium-gold border border-premium-gold/40' : 'text-gray-400 hover:text-premium-gold border border-premium-gold/20'}`}
        >
          รายการเว็บทั้งหมด
        </button>
        <button
          type="button"
          onClick={() => setTab('assignments')}
          className={`px-3 py-2 rounded font-medium transition ${tab === 'assignments' ? 'bg-premium-gold/20 text-premium-gold border border-premium-gold/40' : 'text-gray-400 hover:text-premium-gold border border-premium-gold/20'}`}
        >
          จัดการผู้ดูแลเว็บ
        </button>
      </div>

      {err && <p className={`text-sm mb-2 ${err.startsWith('มอบหมายแล้ว') || err.startsWith('รายการที่เลือก') ? 'text-green-400' : 'text-red-400'}`}>{err}</p>}

      {tab === 'websites' && (
        <>
          <div className="flex flex-wrap gap-4 mb-4">
            <div>
              <label className="block text-gray-400 text-sm mb-1">ค้นหา</label>
              <input type="text" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="ชื่อหรือ alias" className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white w-48" />
            </div>
            <Button variant="gold" className="self-end" onClick={() => { setFormWebsite({ name: '', alias: '', url: '', description: '', logo_path: '' }); setErr(''); setModalWebsite({ open: true, website: null }); }}>เพิ่มเว็บ</Button>
          </div>
          <div className="overflow-x-auto border border-premium-gold/20 rounded-lg">
            <table className="w-full text-sm">
              <thead>
                <tr>
                  <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">โลโก้</th>
                  <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">ชื่อเว็บ</th>
                  <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">นามสกุล (alias)</th>
                  <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">URL</th>
                  <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">สถานะ</th>
                  <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">การดำเนินการ</th>
                </tr>
              </thead>
              <tbody>
                {websites.map((w) => (
                  <tr key={w.id} className="border-b border-premium-gold/10">
                    <td className="p-2">
                      {w.logo_path ? (
                        <img src={w.logo_path} alt="" className="w-8 h-8 object-contain rounded" />
                      ) : (
                        <span className="text-gray-500 text-xs">—</span>
                      )}
                    </td>
                    <td className="p-2 text-gray-200">{w.name}</td>
                    <td className="p-2 font-mono text-premium-gold">{w.alias}</td>
                    <td className="p-2 text-gray-400 max-w-[180px]">
                      {w.url ? (
                        <a href={w.url} target="_blank" rel="noopener noreferrer" className="text-premium-gold hover:underline truncate block">
                          {w.url}
                        </a>
                      ) : (
                        '—'
                      )}
                    </td>
                    <td className="p-2">{w.is_active ? <span className="text-green-400">เปิด</span> : <span className="text-gray-500">ปิด</span>}</td>
                    <td className="p-2">
                      <span className="inline-flex items-center gap-0.5">
                        <BtnEdit onClick={() => { setFormWebsite({ name: w.name, alias: w.alias, url: w.url || '', description: w.description || '', logo_path: w.logo_path || '' }); setModalWebsite({ open: true, website: w }); }} title="แก้ไข" />
                        <BtnDelete onClick={() => setConfirmDelete(w.id)} title="ลบ" />
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}

      {tab === 'assignments' && (
        <>
          <div className="flex flex-wrap gap-4 mb-4">
            <div className="rounded-xl border border-premium-gold/25 bg-premium-darker/60 p-3 flex-1 min-w-0">
              <h3 className="text-premium-gold font-semibold text-sm mb-2">เลือกผู้ใช้ (พนักงานประจำ/พนักงานออนไลน์)</h3>
              <div className="flex flex-wrap items-center gap-2 mb-2">
                <input
                  type="text"
                  value={userSearch}
                  onChange={(e) => setUserSearch(e.target.value)}
                  placeholder="ค้นหาชื่อหรืออีเมล"
                  className="bg-premium-dark border border-premium-gold/30 rounded px-2.5 py-1.5 text-white text-sm w-40"
                />
                <select value={branchId} onChange={(e) => setBranchId(e.target.value)} className="bg-premium-dark border border-premium-gold/30 rounded px-2.5 py-1.5 text-white text-sm min-w-[100px]">
                  <option value="">แผนก</option>
                  {branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
                </select>
                <select value={shiftId} onChange={(e) => setShiftId(e.target.value)} className="bg-premium-dark border border-premium-gold/30 rounded px-2.5 py-1.5 text-white text-sm min-w-[100px]">
                  <option value="">กะ</option>
                  {shifts.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select>
                <select value={roleFilter} onChange={(e) => setRoleFilter(e.target.value)} className="bg-premium-dark border border-premium-gold/30 rounded px-2.5 py-1.5 text-white text-sm min-w-[110px]">
                  <option value="">บทบาท</option>
                  <option value="instructor">พนักงานประจำ</option>
                  <option value="instructor_head">หัวหน้าพนักงานประจำ</option>
                  <option value="staff">พนักงานออนไลน์</option>
                </select>
                <label className="flex items-center gap-1.5 text-gray-400 text-sm cursor-pointer">
                  <input type="checkbox" onChange={(e) => { if (e.target.checked) selectAllFilteredUsers(); }} className="rounded border-premium-gold/50 text-premium-gold" />
                  <span>เลือกทั้งหมดที่กรอง</span>
                </label>
                <button type="button" onClick={clearAllUsers} className="text-xs text-gray-400 hover:text-white">ล้างการเลือก</button>
              </div>
              <div
                ref={staffScrollRef}
                className="overflow-y-auto border border-premium-gold/20 rounded-lg"
                style={{ height: 300 }}
                onScroll={(e) => {
                  const el = e.currentTarget;
                  if (el.scrollHeight - el.scrollTop - el.clientHeight < 80) loadMoreStaff();
                }}
              >
                <table className="w-full text-sm">
                  <thead className="sticky top-0 bg-premium-darker z-10">
                    <tr>
                      <th className="text-left w-10 p-2 border-b border-premium-gold/20 text-premium-gold font-medium">เลือก</th>
                      <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold font-medium">ชื่อ</th>
                      <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold font-medium">แผนก</th>
                      <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold font-medium">กะ</th>
                    </tr>
                  </thead>
                  <tbody>
                    {staffPage.map((p) => (
                      <tr key={p.id} className="border-b border-premium-gold/10 hover:bg-premium-gold/5">
                        <td className="p-2">
                          <input type="checkbox" checked={selectedUserIds.includes(p.id)} onChange={() => toggleUserSelection(p.id)} className="rounded border-premium-gold/50 text-premium-gold" />
                        </td>
                        <td className="p-2 text-gray-200">{p.display_name || p.email || p.id}</td>
                        <td className="p-2 text-gray-400 text-xs">{(p as Profile & { branch?: Branch }).branch?.name ?? '—'}</td>
                        <td className="p-2 text-gray-400 text-xs">{(p as Profile & { shift?: Shift }).shift?.name ?? '—'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                {staffLoading && <p className="text-center text-gray-500 text-xs py-2">กำลังโหลด...</p>}
                {!staffLoading && staffPage.length === 0 && <p className="text-center text-gray-500 text-sm py-4">ไม่มีรายชื่อตามตัวกรอง</p>}
              </div>
              <div className="mt-2 flex flex-wrap items-center gap-1.5">
                <span className="text-gray-500 text-xs">เลือกแล้ว {selectedUserIds.length} คน</span>
                {selectedUserIds.length > 0 && (
                  <>
                    <span className="text-gray-600">|</span>
                    {(selectedUserIds.length > 20 ? selectedUserIds.slice(0, 5) : selectedUserIds).map((id) => {
                      const name = staffList.find((x) => x.id === id)?.display_name || staffList.find((x) => x.id === id)?.email || id.slice(0, 8);
                      return (
                        <span key={id} className="inline-flex items-center gap-1 bg-premium-gold/20 text-premium-gold rounded px-1.5 py-0.5 text-xs">
                          {name}
                          <button type="button" onClick={() => toggleUserSelection(id)} className="hover:text-white" aria-label="ลบ">×</button>
                        </span>
                      );
                    })}
                    {selectedUserIds.length > 20 && <span className="text-premium-gold/80 text-xs">+{selectedUserIds.length - 5}</span>}
                  </>
                )}
              </div>
            </div>

            <div className="rounded-xl border border-premium-gold/25 bg-premium-darker/60 p-3 flex-1 min-w-0">
              <h3 className="text-premium-gold font-semibold text-sm mb-2">เลือกเว็บที่จะให้ดูแล</h3>
              <div className="flex flex-wrap items-center gap-2 mb-2">
                <input
                  type="text"
                  value={webSearch}
                  onChange={(e) => setWebSearch(e.target.value)}
                  placeholder="ค้นหาเว็บ"
                  className="bg-premium-dark border border-premium-gold/30 rounded px-2.5 py-1.5 text-white text-sm w-40"
                />
                <label className="flex items-center gap-1.5 text-gray-400 text-sm cursor-pointer">
                  <input type="checkbox" onChange={(e) => { if (e.target.checked) selectAllFilteredWebsites(); }} className="rounded border-premium-gold/50 text-premium-gold" />
                  <span>เลือกทั้งหมดที่กรอง</span>
                </label>
                <button type="button" onClick={clearAllWebsites} className="text-xs text-gray-400 hover:text-white">ล้างการเลือก</button>
              </div>
              <div
                ref={webScrollRef}
                className="overflow-y-auto border border-premium-gold/20 rounded-lg"
                style={{ height: 300 }}
                onScroll={(e) => {
                  const el = e.currentTarget;
                  if (el.scrollHeight - el.scrollTop - el.clientHeight < 80) loadMoreWebsites();
                }}
              >
                <table className="w-full text-sm">
                  <thead className="sticky top-0 bg-premium-darker z-10">
                    <tr>
                      <th className="text-left w-10 p-2 border-b border-premium-gold/20 text-premium-gold font-medium">เลือก</th>
                      <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold font-medium">ชื่อ (alias)</th>
                    </tr>
                  </thead>
                  <tbody>
                    {websitesPage.map((w) => (
                      <tr key={w.id} className="border-b border-premium-gold/10 hover:bg-premium-gold/5">
                        <td className="p-2">
                          <input type="checkbox" checked={selectedWebsiteIds.includes(w.id)} onChange={() => toggleWebsiteSelection(w.id)} className="rounded border-premium-gold/50 text-premium-gold" />
                        </td>
                        <td className="p-2 text-gray-200">{w.name} <span className="font-mono text-premium-gold/80 text-xs">({w.alias})</span></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                {webLoading && <p className="text-center text-gray-500 text-xs py-2">กำลังโหลด...</p>}
                {!webLoading && websitesPage.length === 0 && <p className="text-center text-gray-500 text-sm py-4">ไม่มีเว็บตามตัวกรอง</p>}
              </div>
              <div className="mt-2 flex flex-wrap items-center gap-1.5">
                <span className="text-gray-500 text-xs">เลือกแล้ว {selectedWebsiteIds.length} เว็บ</span>
                {selectedWebsiteIds.length > 0 && (
                  <>
                    <span className="text-gray-600">|</span>
                    {(selectedWebsiteIds.length > 20 ? selectedWebsiteIds.slice(0, 5) : selectedWebsiteIds).map((id) => {
                      const w = websitesPage.find((x) => x.id === id) || websites.find((x) => x.id === id);
                      const label = w ? `${w.name} (${w.alias})` : id.slice(0, 8);
                      return (
                        <span key={id} className="inline-flex items-center gap-1 bg-premium-gold/20 text-premium-gold rounded px-1.5 py-0.5 text-xs max-w-[140px] truncate" title={label}>
                          {label}
                          <button type="button" onClick={() => toggleWebsiteSelection(id)} className="hover:text-white shrink-0" aria-label="ลบ">×</button>
                        </span>
                      );
                    })}
                    {selectedWebsiteIds.length > 20 && <span className="text-premium-gold/80 text-xs">+{selectedWebsiteIds.length - 5}</span>}
                  </>
                )}
              </div>
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-3 mb-4">
            <Button variant="gold" onClick={batchAssign} loading={loading} disabled={!selectedUserIds.length || !selectedWebsiteIds.length}>
              มอบหมายเว็บที่เลือกให้ผู้ใช้ที่เลือก
            </Button>
            <Button variant="ghost" className="text-gray-400" onClick={() => { setAssignWebsiteId(''); setModalAssign(true); }} disabled={!selectedUserIds.length}>เพิ่มเว็บให้ผู้ใช้ที่เลือก (ทีละเว็บ)</Button>
          </div>

          <div>
            <h3 className="text-premium-gold font-semibold mb-3">รายการที่มอบหมายแล้ว</h3>
            <UserSiteTable
              rows={groupedRows}
              canSetPrimary={canSetPrimaryFor}
              onSetPrimary={setPrimary}
              onRequestUnassign={(assignmentId) => setConfirmUnassign(assignmentId)}
              onEdit={(user, sites, mainSiteId) => setEditModalRow({ user, sites, mainSiteId })}
            />
          </div>
        </>
      )}

      <Modal open={modalWebsite.open} onClose={() => setModalWebsite({ open: false })} title={modalWebsite.website ? 'แก้ไขเว็บ' : 'เพิ่มเว็บ'} footer={
        <>
          <Button variant="ghost" onClick={() => setModalWebsite({ open: false })}>ยกเลิก</Button>
          <Button variant="gold" onClick={saveWebsite} loading={loading}>บันทึก</Button>
        </>
      }>
        <div className="space-y-3">
          <div>
            <label className="block text-gray-400 text-sm mb-1">ชื่อเว็บ *</label>
            <input value={formWebsite.name} onChange={(e) => setFormWebsite((f) => ({ ...f, name: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white" placeholder="ชื่อเว็บ" />
          </div>
          <div>
            <label className="block text-gray-400 text-sm mb-1">นามสกุล (alias) *</label>
            <input value={formWebsite.alias} onChange={(e) => setFormWebsite((f) => ({ ...f, alias: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white font-mono" placeholder="รหัสสั้นหรือ suffix" />
          </div>
          <div>
            <label className="block text-gray-400 text-sm mb-1">URL</label>
            <input value={formWebsite.url} onChange={(e) => setFormWebsite((f) => ({ ...f, url: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white" placeholder="https://..." />
          </div>
          <div>
            <label className="block text-gray-400 text-sm mb-1">คำอธิบาย</label>
            <input value={formWebsite.description} onChange={(e) => setFormWebsite((f) => ({ ...f, description: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white" placeholder="คำอธิบาย (ถ้ามี)" />
          </div>
          <div>
            <label className="block text-gray-400 text-sm mb-1">โลโก้เว็บ (ไม่บังคับ)</label>
            <input
              type="url"
              value={formWebsite.logo_path}
              onChange={(e) => setFormWebsite((f) => ({ ...f, logo_path: e.target.value }))}
              className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white text-sm"
              placeholder="https://... URL รูปโลโก้"
            />
            {formWebsite.logo_path && (
              <img
                src={formWebsite.logo_path}
                alt=""
                className="mt-2 w-16 h-16 object-contain rounded border border-premium-gold/20"
                onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; }}
              />
            )}
          </div>
        </div>
      </Modal>

      <Modal open={modalAssign} onClose={() => setModalAssign(false)} title="เพิ่มเว็บให้ผู้ใช้ที่เลือก" footer={
        <>
          <Button variant="ghost" onClick={() => setModalAssign(false)}>ยกเลิก</Button>
          <Button variant="gold" onClick={addAssignment} loading={loading} disabled={!assignWebsiteId}>เพิ่ม</Button>
        </>
      }>
        <div>
          <label className="block text-gray-400 text-sm mb-1">เลือกเว็บ (จะมอบหมายให้ผู้ใช้ที่เลือกทั้งหมด)</label>
          <select value={assignWebsiteId} onChange={(e) => setAssignWebsiteId(e.target.value)} className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white">
            <option value="">-- เลือกเว็บ --</option>
            {websites.filter((w) => selectedUserIds.some((uid) => !allAssignments.some((a) => a.user_id === uid && a.website_id === w.id))).map((w) => <option key={w.id} value={w.id}>{w.name} ({w.alias})</option>)}
          </select>
        </div>
      </Modal>

      <UserSiteEditModal
        open={editModalRow !== null}
        onClose={() => setEditModalRow(null)}
        user={editModalRow?.user ?? null}
        initialSites={editModalRow?.sites ?? []}
        allWebsites={websites}
        onAssign={async (websiteId, userId) => {
          try {
            await assignOneAndRefetch(websiteId, userId);
          } catch (e) {
            setErr(e instanceof Error ? e.message : 'เกิดข้อผิดพลาด');
            throw e;
          }
        }}
        onUnassign={async (assignmentId) => {
          try {
            await adminUnassignWebsiteFromUser(assignmentId);
            refetchAssignments();
          } catch (e) {
            setErr(e instanceof Error ? e.message : 'เกิดข้อผิดพลาด');
            throw e;
          }
        }}
        onSetPrimary={async (userId, websiteId) => {
          try {
            await adminSetPrimaryWebsite(userId, websiteId);
            refetchAssignments();
          } catch (e) {
            setErr(e instanceof Error ? e.message : 'เกิดข้อผิดพลาด');
            throw e;
          }
        }}
      />

      <ConfirmModal open={confirmUnassign !== null} onClose={() => setConfirmUnassign(null)} onConfirm={async () => { if (confirmUnassign) await unassign(confirmUnassign); }} title="ยืนยันเอาออก" message="ต้องการเอาเว็บนี้ออกจากรายการที่ผู้ใช้ดูแลใช่หรือไม่?" confirmLabel="เอาออก" variant="danger" loading={loading} />
      <ConfirmModal open={confirmDelete !== null} onClose={() => setConfirmDelete(null)} onConfirm={async () => { if (confirmDelete) await deleteWebsite(confirmDelete); }} title="ยืนยันลบเว็บ" message="การลบจะทำให้รายการมอบหมายที่ผูกกับเว็บนี้หายไปด้วย ยืนยันลบใช่หรือไม่?" confirmLabel="ลบ" variant="danger" loading={loading} />
    </div>
  );
}
