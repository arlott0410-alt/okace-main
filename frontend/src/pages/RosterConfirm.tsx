import { useState, useEffect } from 'react';
import { format } from 'date-fns';
import { th } from 'date-fns/locale';
import { supabase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import { useBranchesShifts } from '../lib/BranchesShiftsContext';
import type { MonthlyRosterStatus } from '../lib/types';
import Button from '../components/ui/Button';
import Modal from '../components/ui/Modal';
import { getRosterStatus, confirmRoster, unlockRoster, isRosterLocked } from '../lib/roster';
import { logAudit } from '../lib/audit';

export default function RosterConfirm() {
  const { user, profile } = useAuth();
  const { branches } = useBranchesShifts();
  const isAdminOrManager = profile?.role === 'admin' || profile?.role === 'manager';
  const [month, setMonth] = useState(format(new Date(), 'yyyy-MM'));
  const [branchId, setBranchId] = useState('');
  const [status, setStatus] = useState<MonthlyRosterStatus | null>(null);
  const [modal, setModal] = useState<{ type: 'confirm' | 'unlock' } | null>(null);
  const [unlockReason, setUnlockReason] = useState('');
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<{ type: 'ok' | 'err'; text: string } | null>(null);

  useEffect(() => {
    if (profile?.default_branch_id && !isAdminOrManager && !branchId) setBranchId(profile.default_branch_id);
  }, [profile?.default_branch_id, isAdminOrManager, branchId]);

  useEffect(() => {
    if (profile?.default_branch_id && !isAdminOrManager && branchId !== profile.default_branch_id) {
      setBranchId(profile.default_branch_id);
    }
  }, [profile?.default_branch_id, isAdminOrManager, branchId]);

  useEffect(() => {
    if (!branchId || !month) return;
    getRosterStatus(branchId, month).then(setStatus);
  }, [branchId, month]);

  useEffect(() => {
    if (!branchId) return;
    let debounceTimer: ReturnType<typeof setTimeout> | null = null;
    let mounted = true;
    const channel = supabase
      .channel('roster_status')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'monthly_roster_status' }, () => {
        if (debounceTimer) clearTimeout(debounceTimer);
        debounceTimer = setTimeout(() => {
          debounceTimer = null;
          if (!mounted) return;
          getRosterStatus(branchId, month).then((s) => { if (mounted) setStatus(s); });
        }, 300);
      })
      .subscribe();
    return () => {
      mounted = false;
      if (debounceTimer) clearTimeout(debounceTimer);
      supabase.removeChannel(channel);
    };
  }, [branchId, month]);

  const locked = isRosterLocked(status);

  const handleConfirm = async () => {
    if (!user?.id || !branchId) return;
    setLoading(true);
    setMessage(null);
    const { error } = await confirmRoster(branchId, month, user.id);
    setLoading(false);
    if (error) {
      setMessage({ type: 'err', text: error.message || 'เกิดข้อผิดพลาด' });
      return;
    }
    await logAudit('roster_confirm', 'monthly_roster_status', null, { branch_id: branchId, month });
    setMessage({ type: 'ok', text: 'ยืนยันตารางกะแล้ว' });
    setModal(null);
    getRosterStatus(branchId, month).then(setStatus);
  };

  const handleUnlock = async () => {
    if (!unlockReason.trim()) {
      setMessage({ type: 'err', text: 'กรุณากรอกเหตุผลในการปลดล็อก' });
      return;
    }
    if (!user?.id || !branchId) return;
    setLoading(true);
    setMessage(null);
    const { error } = await unlockRoster(branchId, month, unlockReason.trim(), user.id);
    setLoading(false);
    if (error) {
      setMessage({ type: 'err', text: error.message || 'เกิดข้อผิดพลาด' });
      return;
    }
    await logAudit('roster_unlock', 'monthly_roster_status', null, { branch_id: branchId, month, reason: unlockReason });
    setMessage({ type: 'ok', text: 'ปลดล็อกตารางกะแล้ว' });
    setModal(null);
    setUnlockReason('');
    getRosterStatus(branchId, month).then(setStatus);
  };

  return (
    <div>
      <h1 className="text-premium-gold text-xl font-semibold mb-4">ตารางกะรายเดือน</h1>

      <div className="flex flex-wrap gap-4 mb-6">
        <div>
          <label className="block text-gray-400 text-sm mb-1">เดือน</label>
          <input
            type="month"
            value={month}
            onChange={(e) => setMonth(e.target.value)}
            className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white"
          />
        </div>
        {isAdminOrManager && (
          <div>
            <label className="block text-gray-400 text-sm mb-1">แผนก</label>
            <select
              value={branchId}
              onChange={(e) => setBranchId(e.target.value)}
              className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white"
            >
              <option value="">ทุกแผนก</option>
              {branches.map((b) => (
                <option key={b.id} value={b.id}>{b.name}</option>
              ))}
            </select>
          </div>
        )}
      </div>

      {branchId && (
        <>
          <div className={`rounded-lg border p-4 mb-6 ${locked ? 'border-amber-500/50 bg-amber-500/5' : 'border-premium-gold/20 bg-premium-darker/50'}`}>
            <div className="flex items-center justify-between flex-wrap gap-2">
              <div>
                <span className="text-gray-400 text-sm">สถานะตารางกะ: </span>
                <span className={locked ? 'text-amber-400 font-medium' : 'text-premium-gold font-medium'}>
                  {locked ? 'ล็อกแล้ว (CONFIRMED)' : 'แบบร่าง (DRAFT)'}
                </span>
                {status?.confirmed_at && (
                  <p className="text-gray-500 text-sm mt-1">
                    ยืนยันเมื่อ {format(new Date(status.confirmed_at), 'dd/MM/yyyy HH:mm', { locale: th })}
                  </p>
                )}
              </div>
              {isAdminOrManager && (
                <div className="flex gap-2">
                  {!locked ? (
                    <Button variant="gold" onClick={() => setModal({ type: 'confirm' })}>
                      ยืนยันตารางเดือนนี้
                    </Button>
                  ) : (
                    <Button variant="outline" onClick={() => setModal({ type: 'unlock' })}>
                      ปลดล็อก
                    </Button>
                  )}
                </div>
              )}
            </div>
          </div>

          {!isAdminOrManager && locked && (
            <p className="text-gray-400 text-sm mb-4">ตารางกะเดือนนี้ถูกยืนยันแล้ว ไม่สามารถแก้ไขได้</p>
          )}
        </>
      )}

      {message && <p className={`mb-4 ${message.type === 'ok' ? 'text-green-400' : 'text-red-400'}`}>{message.text}</p>}

      <Modal
        open={modal?.type === 'confirm'}
        onClose={() => setModal(null)}
        title="ยืนยันตารางกะรายเดือน"
        footer={
          <>
            <Button variant="ghost" onClick={() => setModal(null)}>ยกเลิก</Button>
            <Button variant="gold" onClick={handleConfirm} loading={loading}>ยืนยัน</Button>
          </>
        }
      >
        <p className="text-gray-300">เมื่อยืนยันแล้ว Staff และ Instructor จะไม่สามารถแก้ไขตารางกะของเดือนนี้ได้ คุณต้องการยืนยันหรือไม่?</p>
      </Modal>

      <Modal
        open={modal?.type === 'unlock'}
        onClose={() => { setModal(null); setUnlockReason(''); }}
        title="ปลดล็อกตารางกะ"
        footer={
          <>
            <Button variant="ghost" onClick={() => { setModal(null); setUnlockReason(''); }}>ยกเลิก</Button>
            <Button variant="gold" onClick={handleUnlock} disabled={!unlockReason.trim()} loading={loading}>ปลดล็อก</Button>
          </>
        }
      >
        <label className="block text-gray-400 text-sm mb-1">เหตุผลในการปลดล็อก (บังคับ)</label>
        <textarea
          value={unlockReason}
          onChange={(e) => setUnlockReason(e.target.value)}
          className="w-full bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white"
          rows={3}
          placeholder="กรุณาระบุเหตุผล"
        />
      </Modal>
    </div>
  );
}
