import { useState, useEffect, useMemo, useRef } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../lib/auth';
import { useBranchesShifts } from '../lib/BranchesShiftsContext';
import { getShiftKind, getShiftLabel } from '../lib/shiftIcons';
import { getMyScheduledShiftChanges, type MyScheduledShiftChange } from '../lib/transfers';
import { fetchDashboardTodayStaff, type DashboardTodayStaffRow } from '../lib/dashboardTodayStaff';
import { supabase } from '../lib/supabase';
import { listMyWebsites } from '../lib/websites';
import type { Website } from '../lib/types';
import { PageHeader, PageCard, EmptyState } from '../components/layout';
import ProfileBar from '../components/ProfileBar';
import Modal from '../components/ui/Modal';
import Button from '../components/ui/Button';
import { BtnEdit, BtnDelete } from '../components/ui/ActionIcons';

type MyWebsiteRow = { id: string; website?: Website & { branch?: { name: string } }; is_primary?: boolean };

type DashboardShortcut = { id: string; url: string; title: string; icon_url: string | null; sort_order: number };

/** วันนี้ (date only) ใน timezone Bangkok สำหรับ query */
function todayDateString(): string {
  const now = new Date();
  const bkk = new Date(now.toLocaleString('en-US', { timeZone: 'Asia/Bangkok' }));
  return bkk.getFullYear() + '-' + String(bkk.getMonth() + 1).padStart(2, '0') + '-' + String(bkk.getDate()).padStart(2, '0');
}

/** นาฬิกาตามเวลาในเครื่องผู้ใช้ — แสดงใน header แดชบอร์ด */
function LocalClock() {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(t);
  }, []);
  const timeStr = now.toLocaleTimeString('th-TH', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
  const dateStr = now.toLocaleDateString('th-TH', { day: 'numeric', month: 'short', year: 'numeric' });
  return (
    <div
      className="flex items-center gap-2 rounded-lg border border-premium-gold/20 bg-premium-dark/60 px-3 py-1.5"
      title={`เวลาตามเครื่องคุณ · ${dateStr} ${timeStr}`}
      aria-live="polite"
      aria-label={`เวลา ${timeStr} วันที่ ${dateStr}`}
    >
      <span className="text-premium-gold/80 text-lg leading-none" aria-hidden>🕐</span>
      <div className="flex flex-col items-end leading-tight">
        <span className="text-premium-gold font-mono text-[15px] font-medium tabular-nums">{timeStr}</span>
        <span className="text-[11px] text-gray-500">{dateStr}</span>
      </div>
    </div>
  );
}

export default function Dashboard() {
  const { profile } = useAuth();
  const { shifts, branches } = useBranchesShifts();
  const [scheduledChanges, setScheduledChanges] = useState<MyScheduledShiftChange[]>([]);
  const isAdmin = profile?.role === 'admin';
  const isManager = profile?.role === 'manager';
  const isInstructorHead = profile?.role === 'instructor_head';
  const isStaffOrInstructor = profile?.role === 'instructor' || profile?.role === 'staff';
  const showScheduledChanges = isStaffOrInstructor || isManager;
  const showTodayStaff = isAdmin || isManager || isInstructorHead;

  const [todayStaffRows, setTodayStaffRows] = useState<DashboardTodayStaffRow[]>([]);
  const [todayStaffBranchId, setTodayStaffBranchId] = useState<string>(() => profile?.default_branch_id || '');
  const [todayStaffShiftId, setTodayStaffShiftId] = useState<string>(() => profile?.default_shift_id || '');
  const [todayStaffLoading, setTodayStaffLoading] = useState(false);
  const todayStaffRequestRef = useRef({ branchId: '', shiftId: '' });

  /** หน้าที่ของฉันวันนี้ (สำหรับ staff/instructor) */
  const [myDutyNames, setMyDutyNames] = useState<string[]>([]);
  /** เว็บที่ฉันดูแล (สำหรับ staff/instructor) — แสดงบนแดชบอร์ดแทนเมนู */
  const [myWebsites, setMyWebsites] = useState<MyWebsiteRow[]>([]);
  /** เมนูลัด (แสดงทุก role; แก้ไขได้เฉพาะ admin/manager/หัวหน้า) */
  const [shortcuts, setShortcuts] = useState<DashboardShortcut[]>([]);
  const [shortcutModal, setShortcutModal] = useState<{ open: boolean; editing: DashboardShortcut | null }>({ open: false, editing: null });
  const [shortcutForm, setShortcutForm] = useState({ url: '', title: '', icon_url: '' });

  useEffect(() => {
    if (!showTodayStaff || !todayStaffBranchId || !todayStaffShiftId) {
      setTodayStaffRows([]);
      return;
    }
    setTodayStaffLoading(true);
    const branchId = todayStaffBranchId;
    const shiftId = todayStaffShiftId;
    todayStaffRequestRef.current = { branchId, shiftId };
    fetchDashboardTodayStaff({
      scope_branch_id: branchId,
      scope_shift_id: shiftId,
    })
      .then((rows) => {
        if (todayStaffRequestRef.current.branchId === branchId && todayStaffRequestRef.current.shiftId === shiftId) {
          setTodayStaffRows(rows);
        }
      })
      .finally(() => { if (todayStaffRequestRef.current.branchId === branchId && todayStaffRequestRef.current.shiftId === shiftId) setTodayStaffLoading(false); });
  }, [showTodayStaff, todayStaffBranchId, todayStaffShiftId]);

  const todayStaffInScope = useMemo(() => todayStaffRows, [todayStaffRows]);

  const todayStaffSummary = useMemo(() => {
    const present = todayStaffInScope.filter((r) => r.status === 'PRESENT').length;
    const leave = todayStaffInScope.filter((r) => r.status === 'LEAVE').length;
    const mealCount = todayStaffInScope.filter((r) => (Array.isArray(r.meal_slots) && r.meal_slots.length > 0) || r.meal_start_time != null).length;
    return { total: todayStaffInScope.length, present, leave, mealCount };
  }, [todayStaffInScope]);

  const branchesForTodayStaff = (isAdmin || isManager || isInstructorHead) ? branches : branches.filter((b) => b.id === profile?.default_branch_id);

  useEffect(() => {
    if (!showTodayStaff || todayStaffBranchId) return;
    const next = profile?.default_branch_id || branchesForTodayStaff[0]?.id || '';
    if (next) setTodayStaffBranchId(next);
  }, [showTodayStaff, profile?.default_branch_id, todayStaffBranchId, branchesForTodayStaff]);

  useEffect(() => {
    if (!showTodayStaff || todayStaffShiftId) return;
    const next = profile?.default_shift_id || shifts[0]?.id || '';
    if (next) setTodayStaffShiftId(next);
  }, [showTodayStaff, profile?.default_shift_id, todayStaffShiftId, shifts]);

  useEffect(() => {
    if (!profile?.id || !showScheduledChanges) return;
    getMyScheduledShiftChanges(profile.id).then(setScheduledChanges);
  }, [profile?.id, showScheduledChanges]);

  /** โหลดหน้าที่ของฉันวันนี้ (พนักงานที่ถูกจัดแล้ว) */
  useEffect(() => {
    if (!profile?.id || !isStaffOrInstructor) {
      setMyDutyNames([]);
      return;
    }
    const today = todayDateString();
    supabase
      .from('duty_assignments')
      .select('duty_role_id, duty_roles(name)')
      .eq('user_id', profile.id)
      .eq('assignment_date', today)
      .then(({ data }) => {
        const names: string[] = [];
        (data || []).forEach((row: { duty_roles?: { name: string } | { name: string }[] | null }) => {
          const dr = row.duty_roles;
          const name = Array.isArray(dr) ? dr[0]?.name : dr?.name;
          if (name) names.push(name);
        });
        setMyDutyNames(names);
      });
  }, [profile?.id, isStaffOrInstructor]);

  /** โหลดเว็บที่ฉันดูแล (พนักงานประจำ/ออนไลน์ — แสดงบนแดชบอร์ด) */
  useEffect(() => {
    if (!isStaffOrInstructor) {
      setMyWebsites([]);
      return;
    }
    listMyWebsites().then((data) => setMyWebsites((data || []) as MyWebsiteRow[]));
  }, [isStaffOrInstructor]);

  /** โหลดเมนูลัด (ทุกคนเห็น) */
  const loadShortcuts = () => {
    supabase.from('dashboard_shortcuts').select('id, url, title, icon_url, sort_order').order('sort_order').then(({ data }) => setShortcuts((data || []) as DashboardShortcut[]));
  };
  useEffect(() => { loadShortcuts(); }, []);

  useEffect(() => {
    if (!profile?.id || !showScheduledChanges) return;
    let debounceTimer: ReturnType<typeof setTimeout> | null = null;
    const refresh = () => {
      if (debounceTimer) clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        debounceTimer = null;
        getMyScheduledShiftChanges(profile!.id).then(setScheduledChanges);
      }, 300);
    };
    const channel = supabase
      .channel('dashboard-scheduled-shifts')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'shift_swaps' }, refresh)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'cross_branch_transfers' }, refresh)
      .subscribe();
    return () => {
      if (debounceTimer) clearTimeout(debounceTimer);
      supabase.removeChannel(channel);
    };
  }, [profile?.id, showScheduledChanges]);

  const getShiftLabelById = (id: string) => getShiftLabel(getShiftKind(shifts.find((s) => s.id === id)));
  const getBranchName = (id: string) => branches.find((b) => b.id === id)?.name ?? '';
  const canEditShortcuts = isAdmin || isManager || isInstructorHead;

  const openShortcutEdit = (s: DashboardShortcut | null) => {
    setShortcutModal({ open: true, editing: s });
    setShortcutForm(s ? { url: s.url, title: s.title, icon_url: s.icon_url || '' } : { url: '', title: '', icon_url: '' });
  };
  const saveShortcut = async () => {
    if (!shortcutForm.title.trim() || !shortcutForm.url.trim()) return;
    const payload = { url: shortcutForm.url.trim(), title: shortcutForm.title.trim(), icon_url: shortcutForm.icon_url.trim() || null };
    if (shortcutModal.editing) {
      await supabase.from('dashboard_shortcuts').update(payload).eq('id', shortcutModal.editing.id);
    } else {
      await supabase.from('dashboard_shortcuts').insert(payload);
    }
    loadShortcuts();
    setShortcutForm({ url: '', title: '', icon_url: '' });
    setShortcutModal((prev) => ({ ...prev, editing: null }));
  };
  const deleteShortcut = async (id: string) => {
    if (!confirm('ลบเมนูลัดนี้?')) return;
    await supabase.from('dashboard_shortcuts').delete().eq('id', id);
    loadShortcuts();
    if (shortcutModal.editing?.id === id) setShortcutModal({ open: false, editing: null });
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="แดชบอร์ด"
        subtitle={
          isAdmin
            ? 'จัดการระบบและอนุมัติรายการเท่านั้น (แอดมินไม่ลงเวลา/พัก)'
            : isManager
              ? 'จัดการทุกแผนก และใช้เมนูพนักงานได้'
              : undefined
        }
        actions={<LocalClock />}
      />

      <ProfileBar profile={profile ?? null} />

      {/* เมนูลัด (Shortcuts) — แสดงทุกคน; แก้ไขได้เฉพาะ admin/manager/หัวหน้า */}
      <PageCard
        title="เมนูลัด (Shortcuts)"
        actions={canEditShortcuts ? <button type="button" onClick={() => openShortcutEdit(null)} className="text-[12px] text-premium-gold hover:underline">จัดการเมนูลัด</button> : undefined}
      >
        {shortcuts.length === 0 ? (
          <p className="text-[13px] text-gray-400">ยังไม่มีเมนูลัด — {canEditShortcuts ? 'กด "จัดการเมนูลัด" เพื่อเพิ่ม' : 'แอดมิน/ผู้จัดการ/หัวหน้าสามารถเพิ่มได้'}</p>
        ) : (
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
            {shortcuts.map((s) => {
              const isExternal = s.url.startsWith('http://') || s.url.startsWith('https://');
              return (
                <div
                  key={s.id}
                  className="relative flex flex-col rounded-[10px] border border-premium-gold/20 bg-premium-dark/40 hover:border-premium-gold/40 hover:bg-premium-gold/5 transition min-h-[120px]"
                >
                  <a
                    href={s.url}
                    target={isExternal ? '_blank' : undefined}
                    rel={isExternal ? 'noopener noreferrer' : undefined}
                    className="flex flex-col items-center justify-center gap-2 p-4 pt-4 pb-10 text-center flex-1"
                  >
                    {s.icon_url ? (
                      <img src={s.icon_url} alt="" className="w-16 h-16 object-contain rounded" />
                    ) : (
                      <span className="w-16 h-16 flex items-center justify-center rounded bg-premium-gold/15 text-premium-gold text-3xl" aria-hidden>🔗</span>
                    )}
                    <span className="text-[13px] font-medium text-gray-200 truncate w-full">{s.title}</span>
                  </a>
                  {canEditShortcuts && (
                    <div className="absolute bottom-2 right-2 flex items-center gap-1">
                      <BtnEdit title="แก้ไข" onClick={() => openShortcutEdit(s)} />
                      <BtnDelete title="ลบ" onClick={() => deleteShortcut(s.id)} />
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </PageCard>

      {/* Today's Staff (from Holiday Grid) — บนสุด · Supervisor / Manager / Admin. หัวหน้าเห็นทุกแผนก ค่าเริ่มต้น=แผนกตัวเอง */}
      {showTodayStaff && (
        <PageCard
          title="พนักงานวันนี้ (จากตารางวันหยุด)"
          actions={<Link to="/จัดหน้าที่" className="text-[12px] text-premium-gold hover:underline">จัดหน้าที่</Link>}
        >
          <p className="text-[13px] text-gray-400 mb-3">มาทำงาน = ไม่มีวันหยุด/ลาวันนี้ · ลา = มีรายการวันหยุด (อนุมัติ/รอ) · Timezone Asia/Bangkok</p>
          <div className="flex flex-wrap items-center gap-3 mb-4">
            <label className="text-[12px] text-gray-500">แผนก</label>
            <select
              value={todayStaffBranchId}
              onChange={(e) => setTodayStaffBranchId(e.target.value)}
              className="h-8 rounded-lg border border-premium-gold/20 bg-premium-dark/80 text-white text-[13px] px-2 min-w-[120px]"
            >
              {branchesForTodayStaff.map((b) => (
                <option key={b.id} value={b.id}>{b.name}</option>
              ))}
            </select>
            <label className="text-[12px] text-gray-500">กะ</label>
            <select
              value={todayStaffShiftId}
              onChange={(e) => setTodayStaffShiftId(e.target.value)}
              className="h-8 rounded-lg border border-premium-gold/20 bg-premium-dark/80 text-white text-[13px] px-2 min-w-[100px]"
            >
              {shifts.map((s) => (
                <option key={s.id} value={s.id}>{s.name}</option>
              ))}
            </select>
          </div>
          {todayStaffLoading ? (
            <p className="text-[13px] text-gray-500">กำลังโหลด...</p>
          ) : (
            <>
              <div className="flex flex-wrap gap-3 mb-4">
                <span className="inline-flex items-center px-3 py-1.5 rounded-lg bg-premium-gold/10 text-premium-gold text-[13px]">ทั้งหมด {todayStaffSummary.total} คน</span>
                <span className="inline-flex items-center px-3 py-1.5 rounded-lg bg-green-500/15 text-green-400 text-[13px]">มาทำงาน {todayStaffSummary.present}</span>
                <span className="inline-flex items-center px-3 py-1.5 rounded-lg bg-amber-500/15 text-amber-400 text-[13px]">ลา {todayStaffSummary.leave}</span>
                <span className="inline-flex items-center px-3 py-1.5 rounded-lg bg-premium-gold/10 text-gray-300 text-[13px]">จองพักอาหาร {todayStaffSummary.mealCount}</span>
              </div>
              {todayStaffInScope.length === 0 ? (
                <EmptyState message="ไม่มีพนักงานในขอบเขตที่เลือก" />
              ) : (
                <div className="overflow-x-auto border border-premium-gold/20 rounded-lg">
                  <table className="w-full text-[13px]">
                    <thead className="bg-premium-dark/60">
                      <tr>
                        <th className="text-left py-2 px-3 font-medium text-premium-gold/90">ชื่อ</th>
                        <th className="text-left py-2 px-3 font-medium text-gray-400">กะ</th>
                        <th className="text-left py-2 px-3 font-medium text-gray-400 w-24">สถานะ</th>
                        <th className="text-left py-2 px-3 font-medium text-gray-400">ลา / เหตุผล</th>
                        <th className="text-left py-2 px-3 font-medium text-gray-400">เวลาพักอาหาร</th>
                      </tr>
                    </thead>
                    <tbody>
                      {todayStaffInScope.map((r) => (
                        <tr key={r.staff_id} className="border-t border-premium-gold/10">
                          <td className="py-2 px-3 text-gray-200">{r.name || r.staff_code || r.staff_id.slice(0, 8)}</td>
                          <td className="py-2 px-3 text-gray-400">{r.shift_name ?? '—'}</td>
                          <td className="py-2 px-3">
                            {r.status === 'PRESENT' ? (
                              <span className="inline-flex px-2 py-0.5 rounded text-[11px] font-medium bg-green-500/20 text-green-400">มาทำงาน</span>
                            ) : (
                              <span className="inline-flex px-2 py-0.5 rounded text-[11px] font-medium bg-amber-500/20 text-amber-400">ลา</span>
                            )}
                          </td>
                          <td className="py-2 px-3 text-gray-400 text-[12px]">
                            {r.status === 'LEAVE' && (r.leave_type || r.leave_reason) ? `${r.leave_type ?? ''} ${r.leave_reason ?? ''}`.trim() : '—'}
                          </td>
                          <td className="py-2 px-3 text-gray-400 text-[12px]">
                            {(() => {
                              const raw = r.meal_slots;
                              const slots = Array.isArray(raw) && raw.length > 0 ? raw : (r.meal_start_time != null ? [{ start: r.meal_start_time, end: r.meal_end_time }] : []);
                              if (slots.length === 0) return '—';
                              return slots
                                .map((slot) =>
                                  `${new Date(slot.start).toLocaleTimeString('th-TH', { hour: '2-digit', minute: '2-digit' })}${slot.end != null ? ` – ${new Date(slot.end).toLocaleTimeString('th-TH', { hour: '2-digit', minute: '2-digit' })}` : ''}`
                                )
                                .join(', ');
                            })()}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </>
          )}
        </PageCard>
      )}

      {/* Staff / Instructor (ไม่รวมหัวหน้า): Primary actions + 3 คอลัมน์ หน้าที่ของฉันวันนี้ | ตารางของฉัน | เว็บที่ฉันดูแล */}
      {isStaffOrInstructor && (
        <>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <Link
              to="/จองพักอาหาร"
              className="flex items-center justify-center gap-2 px-4 py-3 rounded-[10px] border border-[rgba(255,215,0,0.12)] bg-[rgba(11,15,26,0.6)] hover:border-premium-gold/30 hover:bg-premium-gold/5 text-[13px] font-medium text-premium-gold transition"
            >
              จองเวลาพักอาหาร
            </Link>
            <Link
              to="/ตารางวันหยุด"
              className="flex items-center justify-center gap-2 px-4 py-3 rounded-[10px] border border-[rgba(255,215,0,0.12)] bg-[rgba(11,15,26,0.6)] hover:border-premium-gold/30 hover:bg-premium-gold/5 text-[13px] font-medium text-premium-gold transition"
            >
              ขอลาวันหยุด
            </Link>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <PageCard title="หน้าที่ของฉันวันนี้">
              {myDutyNames.length > 0 ? (
                <p className="text-[15px] font-medium text-premium-gold">{myDutyNames.join(', ')}</p>
              ) : (
                <p className="text-[13px] text-gray-400">ยังไม่มีหน้าที่ถูกจัดวันนี้</p>
              )}
            </PageCard>

            <PageCard title="ตารางของฉัน / วันที่จะย้ายกะ">
              {showScheduledChanges && scheduledChanges.length > 0 ? (
                <ul className="space-y-2 text-[13px]">
                  {scheduledChanges.map((c, i) => (
                    <li key={`${c.type}-${c.start_date}-${i}`} className="text-gray-200">
                      <span className="text-premium-gold font-medium">{c.start_date}</span>
                      {' — จาก '}
                      {getShiftLabelById(c.from_shift_id)}
                      {' เป็น '}
                      {getShiftLabelById(c.to_shift_id)}
                      {c.type === 'transfer' && c.from_branch_id && c.to_branch_id && (
                        <span className="text-gray-500"> ({getBranchName(c.from_branch_id)} → {getBranchName(c.to_branch_id)})</span>
                      )}
                    </li>
                  ))}
                </ul>
              ) : (
                <EmptyState message="ไม่มีกะที่ถูกกำหนดย้ายในอนาคต" />
              )}
            </PageCard>
          </div>

          {/* เว็บที่ฉันดูแล — แถวของตัวเอง (แบบเมนูลัด), การ์ดเล็ก 1:1 ต่อ 1 เว็บ */}
          <PageCard title="เว็บที่ฉันดูแล" actions={myWebsites.length > 0 ? <Link to="/เว็บที่ฉันดูแล" className="text-[12px] text-premium-gold hover:underline">รายละเอียด</Link> : undefined}>
            {myWebsites.length === 0 ? (
              <p className="text-[13px] text-gray-400">ยังไม่มีเว็บที่คุณดูแล</p>
            ) : (
              <div className="grid grid-cols-4 sm:grid-cols-6 md:grid-cols-8 lg:grid-cols-10 gap-2">
                {myWebsites.map((a) => {
                  const w = a.website;
                  const hasUrl = w?.url?.trim();
                  const label = w?.name ?? w?.alias ?? '—';
                  const cardContent = (
                    <>
                      {w?.logo_path ? (
                        <>
                          <img src={w.logo_path} alt="" className="w-10 h-10 object-contain rounded flex-shrink-0" onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; (e.target as HTMLImageElement).nextElementSibling?.classList.remove('hidden'); }} />
                          <span className="hidden w-10 h-10 flex items-center justify-center rounded bg-premium-gold/15 text-premium-gold text-xl flex-shrink-0" aria-hidden>🌐</span>
                        </>
                      ) : (
                        <span className="w-10 h-10 flex items-center justify-center rounded bg-premium-gold/15 text-premium-gold text-xl flex-shrink-0" aria-hidden>🌐</span>
                      )}
                      <span className="text-[11px] font-medium text-gray-200 truncate w-full leading-tight" title={label}>{label}</span>
                    </>
                  );
                  return (
                    <div
                      key={a.id}
                      className={`relative flex flex-col items-center justify-center rounded-[10px] border border-premium-gold/20 bg-premium-dark/40 aspect-square w-full min-w-0 ${hasUrl ? 'hover:border-premium-gold/40 hover:bg-premium-gold/5 transition' : ''}`}
                    >
                      {hasUrl ? (
                        <a
                          href={hasUrl}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="flex flex-col items-center justify-center gap-1 p-2 text-center flex-1 min-w-0 w-full"
                        >
                          {cardContent}
                        </a>
                      ) : (
                        <div className="flex flex-col items-center justify-center gap-1 p-2 text-center flex-1 min-w-0 w-full opacity-90">
                          {cardContent}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </PageCard>
        </>
      )}

      {/* Instructor Head: แสดงเฉพาะบล็อกพนักงานวันนี้ (ไม่แสดงปุ่มลัด + 3 การ์ด) */}

      {/* Manager: แสดงเฉพาะ greeting + subtitle (ลบบล็อกปุ่มลัด คิวอนุมัติ เว็บที่ดูแล ตารางของฉัน ตามที่กรอบแดง) */}
      {isManager && null}

      {/* Admin: System Overview + Audit & Logs + Admin Actions + Usage */}
      {isAdmin && (
        <>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <Link to="/จัดการสมาชิก" className="p-4 rounded-[10px] border border-[rgba(255,215,0,0.12)] bg-[rgba(11,15,26,0.6)] hover:border-premium-gold/30 transition">
              <p className="text-[12px] text-gray-500 uppercase tracking-wider">สมาชิก</p>
              <p className="text-[13px] text-gray-300 mt-1">จัดการผู้ใช้</p>
            </Link>
            <Link to="/เว็บที่ดูแล" className="p-4 rounded-[10px] border border-[rgba(255,215,0,0.12)] bg-[rgba(11,15,26,0.6)] hover:border-premium-gold/30 transition">
              <p className="text-[12px] text-gray-500 uppercase tracking-wider">เว็บที่ดูแล</p>
              <p className="text-[13px] text-gray-300 mt-1">Managed Websites</p>
            </Link>
            <Link to="/ประวัติ" className="p-4 rounded-[10px] border border-[rgba(255,215,0,0.12)] bg-[rgba(11,15,26,0.6)] hover:border-premium-gold/30 transition">
              <p className="text-[12px] text-gray-500 uppercase tracking-wider">ประวัติ</p>
              <p className="text-[13px] text-gray-300 mt-1">Audit / Logs</p>
            </Link>
            <Link to="/ตั้งค่า" className="p-4 rounded-[10px] border border-[rgba(255,215,0,0.12)] bg-[rgba(11,15,26,0.6)] hover:border-premium-gold/30 transition">
              <p className="text-[12px] text-gray-500 uppercase tracking-wider">ตั้งค่า</p>
              <p className="text-[13px] text-gray-300 mt-1">ระบบ</p>
            </Link>
          </div>
        </>
      )}

      {/* Fallback quick links when no role-specific block (e.g. no role yet) */}
      {!isAdmin && !isManager && !isInstructorHead && !isStaffOrInstructor && (
        <PageCard title="ลิงก์ด่วน">
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            <Link to="/ตารางวันหยุด" className="p-3 rounded-lg border border-premium-gold/20 text-[13px] text-premium-gold hover:bg-premium-gold/5">ตารางวันหยุด</Link>
            <Link to="/จัดหน้าที่" className="p-3 rounded-lg border border-premium-gold/20 text-[13px] text-premium-gold hover:bg-premium-gold/5">จัดหน้าที่</Link>
            <Link to="/บัญชีของฉัน" className="p-3 rounded-lg border border-premium-gold/20 text-[13px] text-premium-gold hover:bg-premium-gold/5">บัญชีของฉัน</Link>
          </div>
        </PageCard>
      )}

      {/* Modal จัดการเมนูลัด (เพิ่ม/แก้ไข/ลบ) */}
      <Modal
        open={shortcutModal.open}
        onClose={() => setShortcutModal({ open: false, editing: null })}
        title={shortcutModal.editing ? 'แก้ไขเมนูลัด' : 'เพิ่มเมนูลัด'}
        footer={
          <>
            <Button variant="ghost" onClick={() => setShortcutModal({ open: false, editing: null })}>ปิด</Button>
            <Button variant="gold" onClick={saveShortcut} disabled={!shortcutForm.title.trim() || !shortcutForm.url.trim()}>บันทึก</Button>
          </>
        }
      >
        <div className="space-y-4">
          <div>
            <label className="block text-gray-400 text-xs font-medium mb-1">ลิงก์ (URL) *</label>
            <input
              type="url"
              value={shortcutForm.url}
              onChange={(e) => setShortcutForm((f) => ({ ...f, url: e.target.value }))}
              placeholder="https://..."
              className="w-full rounded-lg border border-premium-gold/25 bg-premium-dark text-white text-sm px-3 py-2 focus:outline-none focus:ring-1 focus:ring-premium-gold/50"
            />
          </div>
          <div>
            <label className="block text-gray-400 text-xs font-medium mb-1">หัวข้อ *</label>
            <input
              type="text"
              value={shortcutForm.title}
              onChange={(e) => setShortcutForm((f) => ({ ...f, title: e.target.value }))}
              placeholder="ชื่อเมนู"
              className="w-full rounded-lg border border-premium-gold/25 bg-premium-dark text-white text-sm px-3 py-2 focus:outline-none focus:ring-1 focus:ring-premium-gold/50"
            />
          </div>
          <div>
            <label className="block text-gray-400 text-xs font-medium mb-1">ไอคอน/โลโก้ (URL, ไม่บังคับ)</label>
            <input
              type="url"
              value={shortcutForm.icon_url}
              onChange={(e) => setShortcutForm((f) => ({ ...f, icon_url: e.target.value }))}
              placeholder="https://... รูปภาพ"
              className="w-full rounded-lg border border-premium-gold/25 bg-premium-dark text-white text-sm px-3 py-2 focus:outline-none focus:ring-1 focus:ring-premium-gold/50"
            />
          </div>
        </div>
      </Modal>
    </div>
  );
}
