import { useState, useEffect } from 'react';
import { format } from 'date-fns';
import { th } from 'date-fns/locale';
import { supabase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import {
  getStoredBranchId,
  setStoredBranchId,
  getStoredShiftId,
  setStoredShiftId,
} from '../lib/auth';
import { useBranchesShifts } from '../lib/BranchesShiftsContext';
import type { WorkLog } from '../lib/types';
import Button from '../components/ui/Button';
import { logAudit } from '../lib/audit';

export default function Timekeeping() {
  const { user, profile } = useAuth();
  const { branches, shifts } = useBranchesShifts();
  const isAdmin = profile?.role === 'admin';
  const isAdminOrManager = profile?.role === 'admin' || profile?.role === 'manager';
  const [branchId, setBranchId] = useState<string>(getStoredBranchId() || profile?.default_branch_id || '');
  const [shiftId, setShiftId] = useState<string>(getStoredShiftId() || profile?.default_shift_id || '');
  const [logicalDate, setLogicalDate] = useState(format(new Date(), 'yyyy-MM-dd'));
  const [todayLogs, setTodayLogs] = useState<WorkLog[]>([]);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<{ type: 'ok' | 'err'; text: string } | null>(null);

  useEffect(() => {
    if (!branches.length || branchId) return;
    setBranchId((isAdmin || isAdminOrManager) ? branches[0].id : (profile?.default_branch_id || branches[0].id));
  }, [branches, isAdmin, isAdminOrManager, profile?.default_branch_id, branchId]);
  useEffect(() => {
    if (!shifts.length || shiftId) return;
    setShiftId(shifts[0].id);
  }, [shifts, shiftId]);

  useEffect(() => {
    if (profile?.default_branch_id && !isAdminOrManager && branchId !== profile.default_branch_id) {
      setBranchId(profile.default_branch_id);
    }
  }, [profile?.default_branch_id, isAdminOrManager, branchId]);

  useEffect(() => {
    if (branchId) setStoredBranchId(branchId);
  }, [branchId]);
  useEffect(() => {
    if (shiftId) setStoredShiftId(shiftId);
  }, [shiftId]);

  useEffect(() => {
    if (!user?.id || !branchId || !shiftId) return;
    const date = logicalDate;
    supabase
      .from('work_logs')
      .select('id, user_id, branch_id, shift_id, logical_date, log_type, logged_at, created_at, user_group')
      .eq('user_id', user.id)
      .eq('logical_date', date)
      .order('logged_at', { ascending: true })
      .then(({ data }) => setTodayLogs(data || []));
  }, [user?.id, branchId, shiftId, logicalDate]);

  const hasIn = todayLogs.some((l) => l.log_type === 'IN');
  const hasOut = todayLogs.some((l) => l.log_type === 'OUT');
  const lastIn = todayLogs.filter((l) => l.log_type === 'IN').pop();
  const lastOut = todayLogs.filter((l) => l.log_type === 'OUT').pop();

  const handleLog = async (logType: 'IN' | 'OUT') => {
    if (!user?.id) return;
    if (profile?.role === 'admin') {
      setMessage({ type: 'err', text: 'บัญชีผู้ดูแลระบบไม่สามารถทำรายการนี้ได้' });
      return;
    }
    if (logType === 'OUT' && !hasIn) {
      setMessage({ type: 'err', text: 'กรุณาลงเวลาเข้างานก่อน' });
      return;
    }
    if (logType === 'IN' && hasIn) {
      setMessage({ type: 'err', text: 'ลงเวลาเข้างานแล้วในวันนี้' });
      return;
    }
    if (logType === 'OUT' && hasOut) {
      setMessage({ type: 'err', text: 'ลงเวลาออกงานแล้วในวันนี้' });
      return;
    }
    const userGroup = getMyUserGroup(profile);
    if (!userGroup) {
      setMessage({ type: 'err', text: 'ไม่พบกลุ่มผู้ใช้ (เฉพาะพนักงานประจำหรือพนักงานออนไลน์เท่านั้นที่ลงเวลาได้)' });
      return;
    }
    setLoading(true);
    setMessage(null);
    const { error } = await supabase.from('work_logs').insert({
      user_id: user.id,
      branch_id: branchId,
      shift_id: shiftId,
      logical_date: logicalDate,
      log_type: logType,
      user_group: userGroup,
    });
    if (error) {
      setMessage({ type: 'err', text: error.message || 'เกิดข้อผิดพลาด' });
      setLoading(false);
      return;
    }
    await logAudit('work_log', 'work_logs', null, { log_type: logType, logical_date: logicalDate });
    setMessage({ type: 'ok', text: logType === 'IN' ? 'ลงเวลาเข้างานแล้ว' : 'ลงเวลาออกงานแล้ว' });
    setTodayLogs((prev) => [...prev, { id: '', user_id: user.id, branch_id: branchId, shift_id: shiftId, logical_date: logicalDate, log_type: logType, logged_at: new Date().toISOString(), created_at: '' }]);
    setLoading(false);
  };

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <h1 className="text-premium-gold text-xl font-semibold">ลงเวลา</h1>
      </div>

      <div className="flex flex-wrap gap-4 mb-6">
        {isAdminOrManager && (
          <div>
            <label className="block text-gray-400 text-sm mb-1">แผนก</label>
            <select
              value={branchId}
              onChange={(e) => setBranchId(e.target.value)}
              className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white"
            >
              <option value="">-- เลือกแผนก --</option>
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
            <option value="">-- เลือกกะ --</option>
            {shifts.map((s) => (
              <option key={s.id} value={s.id}>{s.name}</option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-gray-400 text-sm mb-1">วันที่ทำงาน</label>
          <input
            type="date"
            value={logicalDate}
            onChange={(e) => setLogicalDate(e.target.value)}
            className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white"
          />
        </div>
      </div>

      <div className="border border-premium-gold/20 rounded-lg p-6 mb-4 max-w-md">
        <p className="text-gray-300 mb-2">สถานะวันนี้ ({logicalDate})</p>
        {todayLogs.length === 0 && <p className="text-gray-500">ยังไม่มีการลงเวลา</p>}
        {lastIn && <p className="text-premium-gold">เข้างาน: {format(new Date(lastIn.logged_at), 'HH:mm', { locale: th })}</p>}
        {lastOut && <p className="text-premium-gold">ออกงาน: {format(new Date(lastOut.logged_at), 'HH:mm', { locale: th })}</p>}

        <div className="flex gap-3 mt-4">
          <Button
            variant="gold"
            onClick={() => handleLog('IN')}
            disabled={!branchId || !shiftId || hasIn || loading}
            loading={loading}
          >
            เข้างาน
          </Button>
          <Button
            variant="outline"
            onClick={() => handleLog('OUT')}
            disabled={!branchId || !shiftId || !hasIn || hasOut || loading}
            loading={loading}
          >
            ออกงาน
          </Button>
        </div>
      </div>

      {message && (
        <p className={message.type === 'ok' ? 'text-green-400' : 'text-red-400'}>{message.text}</p>
      )}
    </div>
  );
}
