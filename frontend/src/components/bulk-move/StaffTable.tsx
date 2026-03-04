/**
 * Left pane: staff list with search, filter chips, checkbox table, status badges.
 */

import { useState, useEffect } from 'react';
import type { Profile } from '../../lib/types';
import type { ConflictSummary } from '../../lib/bulkShiftAssignment';

const PAGE_SIZE = 20;

export interface StaffTableProps {
  staff: Profile[];
  selectedIds: Set<string>;
  onToggleOne: (id: string) => void;
  onSelectAll: () => void;
  onClearSelection: () => void;
  searchInput: string;
  onSearchChange: (value: string) => void;
  filterBranchId: string;
  filterShiftId: string;
  onFilterBranchChange: (value: string) => void;
  onFilterShiftChange: (value: string) => void;
  branchOptions: Array<{ id: string; name: string }>;
  shiftOptions: Array<{ id: string; name: string }>;
  conflictSummary: ConflictSummary | null;
  transferDate: string;
  getBranchName: (id: string | null) => string;
  getShiftName: (id: string | null) => string;
}

export default function StaffTable({
  staff,
  selectedIds,
  onToggleOne,
  onSelectAll,
  onClearSelection,
  searchInput,
  onSearchChange,
  filterBranchId,
  filterShiftId,
  onFilterBranchChange,
  onFilterShiftChange,
  branchOptions,
  shiftOptions,
  conflictSummary,
  transferDate,
  getBranchName,
  getShiftName,
}: StaffTableProps) {
  const totalPages = Math.max(1, Math.ceil(staff.length / PAGE_SIZE));
  const [page, setPage] = useState(1);
  useEffect(() => setPage(1), [staff.length, filterBranchId, filterShiftId]);
  const slice = staff.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const hasConflict = (userId: string) =>
    (transferDate && conflictSummary?.conflictMap[userId]?.has(transferDate)) ?? false;

  return (
    <div className="flex flex-col h-full min-h-0 rounded-xl bg-premium-darker/30 border border-premium-gold/10 overflow-hidden">
      <div className="p-4 border-b border-premium-gold/10 space-y-3 shrink-0">
        <h2 className="text-premium-gold/90 font-semibold text-[15px]">รายชื่อพนักงาน</h2>
        <input
          type="text"
          value={searchInput}
          onChange={(e) => onSearchChange(e.target.value)}
          placeholder="ค้นหา (ชื่อ / อีเมล)"
          className="w-full h-9 rounded-lg border border-premium-gold/20 bg-premium-dark/80 text-white text-sm px-3 placeholder-gray-500"
        />
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-gray-500 text-xs">แผนก</span>
          <select
            value={filterBranchId}
            onChange={(e) => onFilterBranchChange(e.target.value)}
            className="h-8 rounded-lg border border-premium-gold/20 bg-premium-dark/80 text-white text-[13px] px-2 min-w-[100px]"
          >
            <option value="">ทุกแผนก</option>
            {branchOptions.map((b) => (
              <option key={b.id} value={b.id}>{b.name}</option>
            ))}
          </select>
          <span className="text-gray-500 text-xs ml-2">กะ</span>
          <select
            value={filterShiftId}
            onChange={(e) => onFilterShiftChange(e.target.value)}
            className="h-8 rounded-lg border border-premium-gold/20 bg-premium-dark/80 text-white text-[13px] px-2 min-w-[100px]"
          >
            <option value="">ทุกกะ</option>
            {shiftOptions.map((s) => (
              <option key={s.id} value={s.id}>{s.name}</option>
            ))}
          </select>
        </div>
        <div className="flex items-center gap-2">
          <button type="button" onClick={onSelectAll} className="text-[12px] text-premium-gold hover:underline">
            เลือกทั้งหมด
          </button>
          <span className="text-gray-500">|</span>
          <button type="button" onClick={onClearSelection} className="text-[12px] text-gray-400 hover:text-white hover:underline">
            ล้างการเลือก
          </button>
        </div>
      </div>

      <div className="flex-1 min-h-0 overflow-auto">
        <table className="w-full text-[13px]">
          <thead className="bg-premium-dark/60 sticky top-0 z-10">
            <tr>
              <th className="text-left py-2.5 px-4 w-10">
                <input
                  type="checkbox"
                  checked={staff.length > 0 && staff.every((e) => selectedIds.has(e.id))}
                  onChange={(e) => (e.target.checked ? onSelectAll() : onClearSelection())}
                  className="rounded border-premium-gold/40 text-premium-gold"
                />
              </th>
              <th className="text-left py-2.5 px-4 font-medium text-premium-gold/90">ชื่อ</th>
              <th className="text-left py-2.5 px-4 font-medium text-gray-400">แผนก / กะ</th>
              {conflictSummary != null && transferDate && (
                <th className="text-left py-2.5 px-4 font-medium text-gray-400 w-24">สถานะ</th>
              )}
            </tr>
          </thead>
          <tbody>
            {slice.map((e) => (
              <tr
                key={e.id}
                onClick={() => onToggleOne(e.id)}
                className="border-t border-premium-gold/10 hover:bg-premium-gold/10 cursor-pointer transition"
              >
                <td className="py-2 px-4" onClick={(ev) => ev.stopPropagation()}>
                  <input
                    type="checkbox"
                    checked={selectedIds.has(e.id)}
                    onChange={() => onToggleOne(e.id)}
                    className="rounded border-premium-gold/40 text-premium-gold"
                  />
                </td>
                <td className="py-2 px-4 font-medium text-gray-100">{e.display_name || e.email || e.id}</td>
                <td className="py-2 px-4 text-gray-500">{getBranchName(e.default_branch_id)} / {getShiftName(e.default_shift_id)}</td>
                {conflictSummary != null && transferDate && (
                  <td className="py-2 px-4">
                    {hasConflict(e.id) ? (
                      <span className="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-medium bg-amber-500/20 text-amber-400 border border-amber-500/30">ติดวันหยุด</span>
                    ) : (
                      <span className="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-medium bg-green-500/15 text-green-400 border border-green-500/25">OK</span>
                    )}
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
        {staff.length === 0 && (
          <div className="flex flex-col items-center justify-center py-12 text-center px-4">
            <p className="text-gray-500 text-sm">ไม่มีพนักงานตามตัวกรอง</p>
          </div>
        )}
      </div>

      {staff.length > 0 && (
        <div className="flex items-center justify-between gap-2 px-4 py-2 border-t border-premium-gold/10 shrink-0 bg-premium-dark/40 text-[12px] text-gray-400">
          <span>หน้า {page} / {totalPages} (แสดงทีละ {PAGE_SIZE} คน)</span>
          <div className="flex gap-1">
            <button
              type="button"
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={page <= 1}
              className="px-2 py-1 rounded border border-premium-gold/30 text-premium-gold disabled:opacity-50 disabled:cursor-not-allowed text-sm hover:bg-premium-gold/10"
            >
              ก่อนหน้า
            </button>
            <button
              type="button"
              onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
              disabled={page >= totalPages}
              className="px-2 py-1 rounded border border-premium-gold/30 text-premium-gold disabled:opacity-50 disabled:cursor-not-allowed text-sm hover:bg-premium-gold/10"
            >
              ถัดไป
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
