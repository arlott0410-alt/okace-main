import { useState, useEffect, useCallback } from 'react';
import { format } from 'date-fns';
import { th } from 'date-fns/locale';
import { supabase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import { useBranchesShifts } from '../lib/BranchesShiftsContext';
import { useToast } from '../lib/ToastContext';
import { getShiftKind, getShiftLabel } from '../lib/shiftIcons';
import type { ShiftChangeHistoryItemWithMeta } from '../lib/transfers';
import { listShiftChangeHistory, enrichShiftChangeHistoryWithMeta, cancelScheduledShiftChange, updateScheduledShiftChange } from '../lib/transfers';
import Button from '../components/ui/Button';
import Modal from '../components/ui/Modal';
import PaginationBar from '../components/ui/PaginationBar';
import { PageHeader } from '../components/layout';
import { BtnEdit, BtnCancel } from '../components/ui/ActionIcons';

const STATUS_LABEL: Record<string, string> = {
  pending: 'รออนุมัติ',
  approved: 'อนุมัติ',
  rejected: 'ปฏิเสธ',
  cancelled: 'ยกเลิก',
};

export default function TransferHistory() {
  const { user, profile } = useAuth();
  const { branches, shifts } = useBranchesShifts();
  const toast = useToast();
  const isAdmin = profile?.role === 'admin';
  const isManager = profile?.role === 'manager';
  const isInstructorHead = profile?.role === 'instructor_head';
  const canSeeAll = isAdmin || isManager || isInstructorHead;
  const canCancelOrEdit = isAdmin || isManager || isInstructorHead;
  const [list, setList] = useState<ShiftChangeHistoryItemWithMeta[]>([]);
  const [totalCount, setTotalCount] = useState(0);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(20);
  const [filters, setFilters] = useState({ month: '', branchId: '', status: '' });
  const [actionLoading, setActionLoading] = useState(false);
  const [editModal, setEditModal] = useState<ShiftChangeHistoryItemWithMeta | null>(null);
  const [editDate, setEditDate] = useState('');
  const [editToShiftId, setEditToShiftId] = useState('');

  const loadList = useCallback(async () => {
    const { data: items, totalCount: total } = await listShiftChangeHistory(
      { month: filters.month || undefined, branchId: filters.branchId || undefined, status: filters.status || undefined },
      { isAdmin, isManager, isInstructorHead, currentUserId: user?.id ?? '', myBranchId: profile?.default_branch_id ?? null },
      { page, pageSize }
    );
    setTotalCount(total);
    return enrichShiftChangeHistoryWithMeta(items, branches, shifts);
  }, [filters.month, filters.branchId, filters.status, page, pageSize, isAdmin, isManager, isInstructorHead, user?.id, profile?.default_branch_id, branches, shifts]);

  useEffect(() => {
    setPage(1);
  }, [filters.month, filters.branchId, filters.status]);

  useEffect(() => {
    let cancelled = false;
    loadList()
      .then((withMeta) => {
        if (!cancelled) setList(withMeta);
      })
      .catch(() => {
        if (!cancelled) toast.show('โหลดประวัติไม่สำเร็จ', 'error');
      });
    return () => { cancelled = true; };
  }, [loadList]);

  useEffect(() => {
    let debounceTimer: ReturnType<typeof setTimeout> | null = null;
    let mounted = true;
    const onEvent = () => {
      if (debounceTimer) clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        debounceTimer = null;
        if (!mounted) return;
        loadList().then((withMeta) => { if (mounted) setList(withMeta); });
      }, 350);
    };
    const channel = supabase
      .channel('transfer_history')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'cross_branch_transfers' }, onEvent)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'shift_swaps' }, onEvent)
      .subscribe();
    return () => {
      mounted = false;
      if (debounceTimer) clearTimeout(debounceTimer);
      supabase.removeChannel(channel);
    };
  }, [loadList]);

  const handleCancel = async (t: ShiftChangeHistoryItemWithMeta) => {
    if (!canCancelOrEdit || t.status !== 'approved') return;
    if (!window.confirm(`ยกเลิกการย้ายกะของ ${t.profile?.display_name || t.profile?.email || '-'} วันที่ ${t.start_date}?`)) return;
    setActionLoading(true);
    const { ok, error } = await cancelScheduledShiftChange(t.type, t.id);
    setActionLoading(false);
    if (ok) {
      toast.show('ยกเลิกแล้ว', 'success');
      loadList().then(setList);
    } else {
      toast.show(error || 'ยกเลิกไม่สำเร็จ', 'error');
    }
  };

  const openEditModal = (t: ShiftChangeHistoryItemWithMeta) => {
    setEditModal(t);
    setEditDate(t.start_date);
    setEditToShiftId(t.to_shift_id || '');
  };

  const handleEditSave = async () => {
    if (!editModal) return;
    if (editModal.type === 'swap' && editToShiftId === editModal.from_shift_id) {
      toast.show('ไม่สามารถแก้เป็นกะเดิมได้ หากไม่ต้องการย้ายกะแล้วให้ยกเลิกรายการแทน', 'error');
      return;
    }
    setActionLoading(true);
    const { ok, error } = await updateScheduledShiftChange(
      editModal.type,
      editModal.id,
      editDate,
      editToShiftId || editModal.to_shift_id || null
    );
    setActionLoading(false);
    if (ok) {
      toast.show('แก้ไขแล้ว', 'success');
      setEditModal(null);
      loadList().then(setList);
    } else {
      toast.show(error || 'แก้ไขไม่สำเร็จ', 'error');
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader title="ประวัติการย้ายกะ" sticky />

      <div className="flex flex-wrap items-end gap-4">
        <div>
          <label className="block text-gray-400 text-xs font-medium mb-1.5 uppercase tracking-wider">เดือน</label>
          <input
            type="month"
            value={filters.month}
            onChange={(e) => setFilters((f) => ({ ...f, month: e.target.value }))}
            className="h-9 min-w-[10rem] rounded-lg border border-premium-gold/25 bg-premium-dark px-3 text-white text-sm focus:outline-none focus:ring-1 focus:ring-premium-gold/50"
          />
        </div>
        {canSeeAll && (
          <div>
            <label className="block text-gray-400 text-xs font-medium mb-1.5 uppercase tracking-wider">แผนก</label>
            <select
              value={filters.branchId}
              onChange={(e) => setFilters((f) => ({ ...f, branchId: e.target.value }))}
              className="h-9 min-w-[10rem] rounded-lg border border-premium-gold/25 bg-premium-dark px-3 text-white text-sm focus:outline-none focus:ring-1 focus:ring-premium-gold/50"
            >
              <option value="">ทุกแผนก</option>
              {branches.map((b) => (
                <option key={b.id} value={b.id}>{b.name}</option>
              ))}
            </select>
          </div>
        )}
        <div>
          <label className="block text-gray-400 text-xs font-medium mb-1.5 uppercase tracking-wider">สถานะ</label>
          <select
            value={filters.status}
            onChange={(e) => setFilters((f) => ({ ...f, status: e.target.value }))}
            className="h-9 min-w-[10rem] rounded-lg border border-premium-gold/25 bg-premium-dark px-3 text-white text-sm focus:outline-none focus:ring-1 focus:ring-premium-gold/50"
          >
            <option value="">ทั้งหมด</option>
            {Object.entries(STATUS_LABEL).map(([k, v]) => (
              <option key={k} value={k}>{v}</option>
            ))}
          </select>
        </div>
      </div>

      <div className="overflow-x-auto rounded-xl border border-premium-gold/15 bg-premium-darker/30">
        <table className="w-full text-sm">
          <thead className="sticky-head bg-premium-darker/60">
            <tr>
              <th className="text-left p-3 border-b border-premium-gold/15 text-premium-gold font-medium">ผู้ขอ</th>
              <th className="text-left p-3 border-b border-premium-gold/15 text-premium-gold font-medium">จากแผนก/กะ → ไปแผนก/กะ</th>
              <th className="text-left p-3 border-b border-premium-gold/15 text-premium-gold font-medium">ช่วงวันที่</th>
              <th className="text-left p-3 border-b border-premium-gold/15 text-premium-gold font-medium">สถานะ</th>
              <th className="text-left p-3 border-b border-premium-gold/15 text-premium-gold font-medium">วันที่สร้าง</th>
              {canCancelOrEdit && <th className="text-left p-3 border-b border-premium-gold/15 text-premium-gold font-medium w-20">ดำเนินการ</th>}
            </tr>
          </thead>
          <tbody>
            {list.map((t) => (
              <tr key={`${t.type}-${t.id}`} className="border-b border-premium-gold/10 hover:bg-premium-gold/5">
                <td className="p-3 text-gray-200">{t.profile?.display_name || t.profile?.email || '-'}</td>
                <td className="p-3 text-gray-200">
                  {t.from_branch?.name ?? '—'}/{getShiftLabel(getShiftKind(t.from_shift))} → {t.to_branch?.name ?? '—'}/{getShiftLabel(getShiftKind(t.to_shift))}
                  {t.type === 'swap' && <span className="text-gray-500 text-xs ml-1">(สลับกะ)</span>}
                </td>
                <td className="p-3 text-gray-300">{t.start_date}{t.start_date !== t.end_date ? ` ถึง ${t.end_date}` : ''}</td>
                <td className="p-3">
                  <span className={t.status === 'approved' ? 'text-green-400' : t.status === 'rejected' ? 'text-red-400' : t.status === 'cancelled' ? 'text-gray-500' : 'text-amber-400'}>
                    {STATUS_LABEL[t.status] ?? t.status}
                  </span>
                </td>
                <td className="p-3 text-gray-400">{format(new Date(t.created_at), 'dd/MM/yyyy HH:mm', { locale: th })}</td>
                {canCancelOrEdit && (
                  <td className="p-3">
                    {t.status === 'approved' ? (
                      <div className="flex items-center gap-1">
                        <BtnEdit title="แก้ไข" onClick={() => openEditModal(t)} disabled={actionLoading} />
                        <BtnCancel title="ยกเลิก" onClick={() => handleCancel(t)} disabled={actionLoading} />
                      </div>
                    ) : (
                      <span className="text-gray-500">—</span>
                    )}
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {list.length === 0 && <p className="text-gray-500 mt-4">ไม่มีรายการ</p>}
      {(totalCount > 0 || list.length > 0) && (
        <PaginationBar
          page={page}
          pageSize={pageSize}
          totalCount={totalCount}
          onPageChange={setPage}
          onPageSizeChange={(n) => { setPageSize(n); setPage(1); }}
          pageSizeOptions={[10, 20, 50]}
          itemLabel="รายการ"
        />
      )}

      <Modal
        open={!!editModal}
        onClose={() => setEditModal(null)}
        title="แก้ไขการตั้งเวลาย้ายกะ"
        footer={
          <>
            <Button variant="ghost" onClick={() => setEditModal(null)}>ปิด</Button>
            <Button
              variant="gold"
              onClick={handleEditSave}
              loading={actionLoading}
              disabled={!!editModal && editModal.type === 'swap' && editToShiftId === editModal.from_shift_id}
            >
              บันทึก
            </Button>
          </>
        }
      >
        {editModal && (
          <div className="space-y-4">
            <p className="text-gray-300 text-sm">{editModal.profile?.display_name || editModal.profile?.email} — {editModal.type === 'swap' ? 'สลับกะ' : 'ย้ายแผนก'}</p>
            <div>
              <label className="block text-gray-400 text-sm mb-1">วันที่มีผล</label>
              <input
                type="date"
                value={editDate}
                onChange={(e) => setEditDate(e.target.value)}
                className="w-full bg-premium-dark border border-premium-gold/25 rounded-lg px-3 py-2 text-white"
              />
            </div>
            <div>
              <label className="block text-gray-400 text-sm mb-1">กะปลายทาง</label>
              <select
                value={editToShiftId}
                onChange={(e) => setEditToShiftId(e.target.value)}
                className="w-full bg-premium-dark border border-premium-gold/25 rounded-lg px-3 py-2 text-white"
              >
                {shifts.map((s) => (
                  <option key={s.id} value={s.id}>{getShiftLabel(getShiftKind(s))} ({s.name})</option>
                ))}
              </select>
            </div>
            {editModal.type === 'swap' && editToShiftId === editModal.from_shift_id && (
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
