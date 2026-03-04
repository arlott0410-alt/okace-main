import { useState, useEffect } from 'react';
import { format } from 'date-fns';
import { th } from 'date-fns/locale';
import { supabase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import { getStoredBranchId, getStoredShiftId, getMyUserGroup } from '../lib/auth';
import { useBranchesShifts } from '../lib/BranchesShiftsContext';
import type { BreakLog, UserGroup } from '../lib/types';
import Button from '../components/ui/Button';
import { logAudit } from '../lib/audit';
import {
  getBreakRules,
  getConcurrentLimitForStaffCount,
  getActiveBreakCount,
  getActiveBreaks,
  getBreakHistory,
  estimateStaffCount,
} from '../lib/breaks';
import { getShiftKind, getShiftIcon, getShiftLabel } from '../lib/shiftIcons';

export default function Breaks() {
  const { user, profile } = useAuth();
  const { branches, shifts } = useBranchesShifts();
  const isAdmin = profile?.role === 'admin';
  const canGlobalViewBreaks = ['admin', 'manager', 'instructor_head', 'instructor'].includes(profile?.role ?? '');
  const [branchId, setBranchId] = useState(getStoredBranchId() || profile?.default_branch_id || '');
  const [shiftId, setShiftId] = useState(getStoredShiftId() || profile?.default_shift_id || '');
  const [breakDate, setBreakDate] = useState(format(new Date(), 'yyyy-MM-dd'));
  const [activeBreak, setActiveBreak] = useState<BreakLog | null>(null);
  const [concurrentLimit, setConcurrentLimit] = useState(1);
  const [currentOnBreak, setCurrentOnBreak] = useState(0);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<{ type: 'ok' | 'err'; text: string } | null>(null);

  // Admin: คนที่กำลังพักอยู่ + ประวัติ
  const [activeBreaksList, setActiveBreaksList] = useState<(BreakLog & { profile?: { display_name: string | null; email: string } })[]>([]);
  const [historyList, setHistoryList] = useState<(BreakLog & { profiles?: { display_name: string | null } | null })[]>([]);
  const [historyTotalCount, setHistoryTotalCount] = useState(0);
  const [historyPage, setHistoryPage] = useState(1);
  const historyPageSize = 20;
  const [historyFilters, setHistoryFilters] = useState({ dateFrom: '', dateTo: '', branchId: '', shiftId: '', userGroup: '' as '' | UserGroup, searchName: '' });

  useEffect(() => {
    if (!branches.length || branchId) return;
    setBranchId(canGlobalViewBreaks ? branches[0].id : (profile?.default_branch_id || branches[0].id));
  }, [branches, canGlobalViewBreaks, profile?.default_branch_id, branchId]);
  useEffect(() => {
    if (!shifts.length || shiftId) return;
    setShiftId(shifts[0].id);
  }, [shifts, shiftId]);

  useEffect(() => {
    if (profile?.default_branch_id && !canGlobalViewBreaks && branchId !== profile.default_branch_id) {
      setBranchId(profile.default_branch_id);
    }
  }, [profile?.default_branch_id, canGlobalViewBreaks, branchId]);

  const myUserGroup = getMyUserGroup(profile);
  useEffect(() => {
    if (!branchId || !shiftId || !myUserGroup) return;
    (async () => {
      const rules = await getBreakRules(branchId, shiftId, myUserGroup);
      const staffCount = await estimateStaffCount(branchId, shiftId, breakDate, myUserGroup);
      setConcurrentLimit(getConcurrentLimitForStaffCount(rules, staffCount));
    })();
  }, [branchId, shiftId, breakDate, myUserGroup]);

  useEffect(() => {
    if (!user?.id || !branchId || !shiftId) return;
    supabase
      .from('break_logs')
      .select('*')
      .eq('user_id', user.id)
      .eq('break_date', breakDate)
      .eq('status', 'active')
      .or('break_type.is.null,break_type.eq.NORMAL')
      .maybeSingle()
      .then(({ data }) => setActiveBreak(data as BreakLog | null));
  }, [user?.id, branchId, shiftId, breakDate]);

  useEffect(() => {
    if (!branchId || !shiftId || !breakDate || !myUserGroup) return;
    getActiveBreakCount(branchId, shiftId, breakDate, myUserGroup).then(setCurrentOnBreak);
  }, [branchId, shiftId, breakDate, myUserGroup]);

  useEffect(() => {
    if (!canGlobalViewBreaks || !branchId || !shiftId) return;
    const ug = historyFilters.userGroup || undefined;
    getActiveBreaks(branchId, shiftId, breakDate, ug).then(setActiveBreaksList);
  }, [canGlobalViewBreaks, branchId, shiftId, breakDate, currentOnBreak, historyFilters.userGroup]);

  useEffect(() => {
    if (!canGlobalViewBreaks) return;
    getBreakHistory({
      branchId: historyFilters.branchId || undefined,
      shiftId: historyFilters.shiftId || undefined,
      dateFrom: historyFilters.dateFrom || undefined,
      dateTo: historyFilters.dateTo || undefined,
      userGroup: historyFilters.userGroup || undefined,
      searchName: historyFilters.searchName?.trim() || undefined,
      page: historyPage,
      pageSize: historyPageSize,
    }).then(({ data, totalCount }) => {
      setHistoryList(data);
      setHistoryTotalCount(totalCount);
    });
  }, [canGlobalViewBreaks, historyFilters.branchId, historyFilters.shiftId, historyFilters.dateFrom, historyFilters.dateTo, historyFilters.userGroup, historyFilters.searchName, historyPage, historyPageSize]);

  useEffect(() => {
    if (!canGlobalViewBreaks) return;
    const ug = historyFilters.userGroup || undefined;
    const channel = supabase
      .channel('break_logs_admin')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'break_logs' }, () => {
        if (myUserGroup) getActiveBreakCount(branchId, shiftId, breakDate, myUserGroup).then(setCurrentOnBreak);
        getActiveBreaks(branchId, shiftId, breakDate, ug).then(setActiveBreaksList);
      })
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [canGlobalViewBreaks, branchId, shiftId, breakDate, historyFilters.userGroup, myUserGroup]);

  const startBreak = async () => {
    if (!user?.id) return;
    if (profile?.role === 'admin') {
      setMessage({ type: 'err', text: 'บัญชีผู้ดูแลระบบไม่สามารถทำรายการนี้ได้' });
      return;
    }
    if (profile?.role === 'manager' && !myUserGroup) {
      setMessage({ type: 'err', text: 'ไม่พบกลุ่มผู้ใช้ (ผู้จัดการต้องมีแผนก/กะสำหรับลงพัก)' });
      return;
    }
    const userGroup = getMyUserGroup(profile);
    if (!userGroup) {
      setMessage({ type: 'err', text: 'ไม่พบกลุ่มผู้ใช้' });
      return;
    }
    const count = await getActiveBreakCount(branchId, shiftId, breakDate, userGroup);
    const rules = await getBreakRules(branchId, shiftId, userGroup);
    const staffCount = await estimateStaffCount(branchId, shiftId, breakDate, userGroup);
    const limit = getConcurrentLimitForStaffCount(rules, staffCount);
    if (count >= limit) {
      setMessage({ type: 'err', text: 'โควต้าพักเต็ม กรุณารอ' });
      return;
    }
    setLoading(true);
    setMessage(null);
    const { error } = await supabase.from('break_logs').insert({
      user_id: user.id,
      branch_id: branchId,
      shift_id: shiftId,
      break_date: breakDate,
      started_at: new Date().toISOString(),
      status: 'active',
      user_group: userGroup,
    });
    if (error) {
      setMessage({ type: 'err', text: error.message || 'เกิดข้อผิดพลาด' });
      setLoading(false);
      return;
    }
    await logAudit('break_start', 'break_logs', null, { break_date: breakDate });
    setMessage({ type: 'ok', text: 'เริ่มพักแล้ว' });
    setActiveBreak({ id: '', user_id: user.id, branch_id: branchId, shift_id: shiftId, break_date: breakDate, started_at: new Date().toISOString(), ended_at: null, status: 'active', user_group: userGroup });
    setCurrentOnBreak(count + 1);
    setLoading(false);
  };

  const endBreak = async () => {
    if (!activeBreak?.id) return;
    if (profile?.role === 'admin') {
      setMessage({ type: 'err', text: 'บัญชีผู้ดูแลระบบไม่สามารถทำรายการนี้ได้' });
      return;
    }
    setLoading(true);
    setMessage(null);
    const { error } = await supabase
      .from('break_logs')
      .update({ ended_at: new Date().toISOString(), status: 'ended' })
      .eq('id', activeBreak.id);
    if (error) {
      setMessage({ type: 'err', text: error.message || 'เกิดข้อผิดพลาด' });
      setLoading(false);
      return;
    }
    await logAudit('break_end', 'break_logs', activeBreak.id, {});
    setMessage({ type: 'ok', text: 'เลิกพักแล้ว' });
    setActiveBreak(null);
    setCurrentOnBreak((c) => Math.max(0, c - 1));
    setLoading(false);
  };

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <h1 className="text-premium-gold text-xl font-semibold">พัก</h1>
        {!isAdmin && myUserGroup && (
          <span className="text-sm px-2 py-0.5 rounded bg-premium-gold/20 text-premium-gold">
            {myUserGroup === 'INSTRUCTOR' ? 'โหมดพนักงานประจำ' : 'โหมดพนักงานออนไลน์'}
          </span>
        )}
      </div>

      <div className="flex flex-wrap gap-4 mb-6">
        {canGlobalViewBreaks && (
          <div>
            <label className="block text-gray-400 text-sm mb-1">แผนก</label>
            <select
              value={branchId}
              onChange={(e) => setBranchId(e.target.value)}
              className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white"
            >
              {branches.map((b) => (
                <option key={b.id} value={b.id}>{b.name}</option>
              ))}
            </select>
          </div>
        )}
        <div>
          <label className="block text-gray-400 text-sm mb-1">กะ</label>
          <select
            value={shiftId}
            onChange={(e) => setShiftId(e.target.value)}
            className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white"
          >
            {shifts.map((s) => (
              <option key={s.id} value={s.id}>{s.name}</option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-gray-400 text-sm mb-1">วันที่</label>
          <input
            type="date"
            value={breakDate}
            onChange={(e) => setBreakDate(e.target.value)}
            className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white"
          />
        </div>
      </div>

      <div className="border border-premium-gold/20 rounded-lg p-6 max-w-md">
        <p className="text-gray-400 text-sm">โควต้าพักในกะนี้: พักพร้อมกันได้ {concurrentLimit} คน (กำลังพักอยู่ {currentOnBreak} คน)</p>
        {activeBreak ? (
          <>
            <p className="text-premium-gold mt-2">คุณกำลังพัก เริ่มเมื่อ {format(new Date(activeBreak.started_at), 'HH:mm', { locale: th })}</p>
            <Button variant="outline" className="mt-4" onClick={endBreak} loading={loading}>เลิกพัก</Button>
          </>
        ) : (
          <Button
            variant="gold"
            className="mt-4"
            onClick={startBreak}
            disabled={currentOnBreak >= concurrentLimit}
            loading={loading}
          >
            เริ่มพัก
          </Button>
        )}
      </div>
      {message && <p className={`mt-2 ${message.type === 'ok' ? 'text-green-400' : 'text-red-400'}`}>{message.text}</p>}

      {/* Admin/Manager/หัวหน้า/พนักงานประจำ: คนที่กำลังพักอยู่ (Realtime) — ดูได้ทุกแผนก ทำรายการได้เฉพาะของตัวเอง */}
      {canGlobalViewBreaks && (
        <section className="mt-8">
          <div className="flex flex-wrap items-center gap-3 mb-3">
            <h2 className="text-premium-gold font-medium">คนที่กำลังพักอยู่ (อัปเดตแบบ Realtime)</h2>
            <select
              value={historyFilters.userGroup}
              onChange={(e) => setHistoryFilters((f) => ({ ...f, userGroup: e.target.value as '' | UserGroup }))}
              className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white text-sm"
            >
              <option value="">ทั้งหมด</option>
              <option value="INSTRUCTOR">พนักงานประจำ</option>
              <option value="STAFF">พนักงานออนไลน์</option>
              <option value="MANAGER">ผู้จัดการ</option>
            </select>
          </div>
          <p className="text-gray-400 text-sm mb-2">☀️ กะเช้า | 🌆 กะกลาง | 🌙 กะดึก</p>
          <div className="border border-premium-gold/20 rounded-lg overflow-hidden">
            <table className="w-full text-sm">
              <thead className="sticky-head">
                <tr>
                  <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">ชื่อ</th>
                  <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">เริ่มพักเมื่อ</th>
                </tr>
              </thead>
              <tbody>
                {activeBreaksList.length === 0 && (
                  <tr><td colSpan={2} className="p-4 text-gray-500">ไม่มีคนกำลังพักอยู่</td></tr>
                )}
                {activeBreaksList.map((log) => {
                  const shift = shifts.find((s) => s.id === log.shift_id);
                  const kind = getShiftKind(shift);
                  const icon = getShiftIcon(kind);
                  const label = getShiftLabel(kind);
                  const timeRange = shift?.start_time != null && shift?.end_time != null ? `${shift.start_time.slice(0, 5)}–${shift.end_time.slice(0, 5)}` : '';
                  const name = log.profile?.display_name || log.profile?.email || '-';
                  return (
                    <tr key={log.id} className="border-b border-premium-gold/10">
                      <td className="p-2">
                        <span className="flex items-center gap-2 min-w-0">
                          <span className="truncate">{name}</span>
                          <span className="shrink-0 inline-flex items-center justify-center w-6 h-6 rounded border border-premium-gold/40 bg-premium-gold/10 text-sm" title={timeRange ? `${label} ${timeRange}` : label}>
                            {icon}
                          </span>
                        </span>
                      </td>
                      <td className="p-2">{format(new Date(log.started_at), 'HH:mm น.', { locale: th })}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </section>
      )}

      {/* Admin/Manager/หัวหน้า/พนักงานประจำ: ประวัติการพักรายวัน/รายคน */}
      {canGlobalViewBreaks && (
        <section className="mt-8">
          <h2 className="text-premium-gold font-medium mb-3">ประวัติการพัก</h2>
          <div className="flex flex-wrap gap-2 mb-3">
            <input
              type="date"
              value={historyFilters.dateFrom}
              onChange={(e) => { setHistoryFilters((f) => ({ ...f, dateFrom: e.target.value })); setHistoryPage(1); }}
              className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white"
              placeholder="จากวันที่"
            />
            <input
              type="date"
              value={historyFilters.dateTo}
              onChange={(e) => { setHistoryFilters((f) => ({ ...f, dateTo: e.target.value })); setHistoryPage(1); }}
              className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white"
              placeholder="ถึงวันที่"
            />
            <select
              value={historyFilters.branchId}
              onChange={(e) => { setHistoryFilters((f) => ({ ...f, branchId: e.target.value })); setHistoryPage(1); }}
              className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white"
            >
              <option value="">ทุกแผนก</option>
              {branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
            </select>
            <select
              value={historyFilters.shiftId}
              onChange={(e) => { setHistoryFilters((f) => ({ ...f, shiftId: e.target.value })); setHistoryPage(1); }}
              className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white"
            >
              <option value="">ทุกกะ</option>
              {shifts.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
            <select
              value={historyFilters.userGroup}
              onChange={(e) => { setHistoryFilters((f) => ({ ...f, userGroup: e.target.value as '' | UserGroup })); setHistoryPage(1); }}
              className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white"
            >
              <option value="">ทุกกลุ่ม</option>
              <option value="INSTRUCTOR">พนักงานประจำ</option>
              <option value="STAFF">พนักงานออนไลน์</option>
              <option value="MANAGER">ผู้จัดการ</option>
            </select>
            <input
              type="text"
              value={historyFilters.searchName}
              onChange={(e) => { setHistoryFilters((f) => ({ ...f, searchName: e.target.value })); setHistoryPage(1); }}
              className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white min-w-[120px]"
              placeholder="ค้นหาชื่อ"
            />
          </div>
          <p className="text-gray-400 text-sm mb-2">☀️ กะเช้า | 🌆 กะกลาง | 🌙 กะดึก</p>
          <div className="border border-premium-gold/20 rounded-lg overflow-hidden">
            <table className="w-full text-sm">
              <thead className="sticky-head">
                <tr>
                  <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">ชื่อ</th>
                  <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">วันที่</th>
                  <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">เริ่ม</th>
                  <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">สิ้นสุด</th>
                  <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">สถานะ</th>
                </tr>
              </thead>
              <tbody>
                {historyList.map((log) => {
                  const shift = shifts.find((s) => s.id === log.shift_id);
                  const kind = getShiftKind(shift);
                  const icon = getShiftIcon(kind);
                  const label = getShiftLabel(kind);
                  const timeRange = shift?.start_time != null && shift?.end_time != null ? `${shift.start_time.slice(0, 5)}–${shift.end_time.slice(0, 5)}` : '';
                  const name = (log as { profiles?: { display_name: string | null } | null }).profiles?.display_name ?? '-';
                  return (
                    <tr key={log.id} className="border-b border-premium-gold/10">
                      <td className="p-2">
                        <span className="flex items-center gap-2 min-w-0">
                          <span className="truncate">{name}</span>
                          <span className="shrink-0 inline-flex items-center justify-center w-6 h-6 rounded border border-premium-gold/40 bg-premium-gold/10 text-sm" title={timeRange ? `${label} ${timeRange}` : label}>
                            {icon}
                          </span>
                        </span>
                      </td>
                      <td className="p-2">{log.break_date}</td>
                      <td className="p-2">{format(new Date(log.started_at), 'HH:mm', { locale: th })}</td>
                      <td className="p-2">{log.ended_at ? format(new Date(log.ended_at), 'HH:mm', { locale: th }) : '-'}</td>
                      <td className="p-2">{log.status === 'active' ? 'กำลังพัก' : 'เลิกพักแล้ว'}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          <div className="flex items-center gap-3 mt-2 text-sm text-premium-gold">
            <span>ทั้งหมด {historyTotalCount} รายการ</span>
            <button
              type="button"
              disabled={historyPage <= 1}
              onClick={() => setHistoryPage((p) => Math.max(1, p - 1))}
              className="px-2 py-1 rounded border border-premium-gold/30 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              ก่อนหน้า
            </button>
            <span>หน้า {historyPage} จาก {Math.max(1, Math.ceil(historyTotalCount / historyPageSize))}</span>
            <button
              type="button"
              disabled={historyPage >= Math.ceil(historyTotalCount / historyPageSize)}
              onClick={() => setHistoryPage((p) => p + 1)}
              className="px-2 py-1 rounded border border-premium-gold/30 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              ถัดไป
            </button>
          </div>
        </section>
      )}
    </div>
  );
}
