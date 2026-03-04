/**
 * Sticky top action bar for Bulk Shift Transfer (ย้ายกะจำนวนมาก).
 * Title + tabs, destination controls, primary/secondary actions, summary counters.
 */

import Button from '../ui/Button';
import type { Shift } from '../../lib/types';

type PageMode = 'bulk' | 'paired';

export interface BulkMoveTopBarProps {
  pageMode: PageMode;
  onPageModeChange: (mode: PageMode) => void;
  /** Destination controls (bulk mode) */
  startDate: string;
  onStartDateChange: (value: string) => void;
  toShiftId: string;
  onToShiftIdChange: (value: string) => void;
  reason: string;
  onReasonChange: (value: string) => void;
  shifts: Shift[];
  /** Actions */
  onMoveSelected: () => void;
  onClearSelection: () => void;
  onCheckHolidays: () => void;
  loading: boolean;
  /** Counters */
  totalCount: number;
  selectedCount: number;
  movableCount: number | null;
  blockedCount: number | null;
  /** Submit disabled (e.g. block when BLOCK_ALL + has conflicts) */
  submitDisabled: boolean;
  submitLabel: string;
  /** วันที่เลือกได้ขั้นต่ำ (วันพรุ่งนี้) — ป้องกันเลือกวันนี้ */
  minDate?: string;
}

export default function BulkMoveTopBar({
  pageMode,
  onPageModeChange,
  startDate,
  onStartDateChange,
  toShiftId,
  onToShiftIdChange,
  reason,
  onReasonChange,
  shifts,
  onMoveSelected,
  onClearSelection,
  onCheckHolidays,
  loading,
  totalCount,
  selectedCount,
  movableCount,
  blockedCount,
  submitDisabled,
  submitLabel,
  minDate,
}: BulkMoveTopBarProps) {
  return (
    <header className="sticky top-0 z-20 bg-premium-dark/95 backdrop-blur border-b border-premium-gold/10 px-4 py-4 shadow-lg">
      <div className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-4">
            <h1 className="text-premium-gold text-xl font-semibold">ย้ายกะ (จำนวนมาก)</h1>
            <nav className="flex rounded-lg border border-premium-gold/20 overflow-hidden bg-premium-darker/40 p-0.5">
              <button
                type="button"
                onClick={() => onPageModeChange('bulk')}
                className={`px-4 py-2 rounded-md text-sm font-medium transition ${pageMode === 'bulk' ? 'bg-premium-gold/20 text-premium-gold' : 'text-gray-400 hover:text-white'}`}
              >
                ย้ายไปกะปลายทาง
              </button>
              <button
                type="button"
                onClick={() => onPageModeChange('paired')}
                className={`px-4 py-2 rounded-md text-sm font-medium transition ${pageMode === 'paired' ? 'bg-premium-gold/20 text-premium-gold' : 'text-gray-400 hover:text-white'}`}
              >
                สลับกะจับคู่ (เช้า↔ดึก)
              </button>
            </nav>
          </div>

          {pageMode === 'bulk' && (
            <>
              <div className="flex flex-wrap items-center gap-3">
                <div>
                  <label className="sr-only">วันที่ย้าย (ขั้นต่ำวันพรุ่งนี้)</label>
                  <input
                    type="date"
                    value={startDate}
                    min={minDate}
                    onChange={(e) => onStartDateChange(e.target.value)}
                    className="h-9 rounded-lg border border-premium-gold/25 bg-premium-darker/60 text-white text-sm px-3"
                    title="ตั้งได้ขั้นต่ำวันพรุ่งนี้"
                  />
                </div>
                <div>
                  <label className="sr-only">กะปลายทาง</label>
                  <select
                    value={toShiftId}
                    onChange={(e) => onToShiftIdChange(e.target.value)}
                    className="h-9 rounded-lg border border-premium-gold/25 bg-premium-darker/60 text-white text-sm px-3 min-w-[120px]"
                  >
                    <option value="">-- เลือกกะ --</option>
                    {shifts.map((s) => (
                      <option key={s.id} value={s.id}>{s.name}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="sr-only">เหตุผล</label>
                  <input
                    type="text"
                    value={reason}
                    onChange={(e) => onReasonChange(e.target.value)}
                    placeholder="เหตุผล (ถ้ามี)"
                    className="h-9 rounded-lg border border-premium-gold/25 bg-premium-darker/60 text-white text-sm px-3 w-40"
                  />
                </div>
              </div>

              <div className="flex flex-wrap items-center gap-2">
                <Button onClick={onCheckHolidays} loading={loading} variant="ghost" className="h-9 px-3 text-sm">
                  ตรวจวันหยุด
                </Button>
                <Button onClick={onClearSelection} variant="outline" className="h-9 px-3 text-sm" disabled={selectedCount === 0}>
                  ล้างการเลือก
                </Button>
                <Button onClick={onMoveSelected} loading={loading} disabled={submitDisabled} variant="gold" className="h-9 px-4 text-sm">
                  {submitLabel}
                </Button>
              </div>
            </>
          )}
        </div>

        {pageMode === 'bulk' && (
          <div className="flex flex-wrap items-center gap-5 text-sm">
            <span className="text-gray-400">ทั้งหมด <strong className="text-gray-200">{totalCount}</strong> คน</span>
            <span className="text-gray-400">เลือกแล้ว <strong className="text-premium-gold">{selectedCount}</strong> คน</span>
            {movableCount != null && blockedCount != null && selectedCount > 0 && (
              <>
                <span className="text-gray-400">ย้ายได้ <strong className="text-green-400">{movableCount}</strong> คน</span>
                {blockedCount > 0 && (
                  <span className="text-gray-400">ติดวันหยุด <strong className="text-amber-400">{blockedCount}</strong> คน</span>
                )}
              </>
            )}
          </div>
        )}
      </div>
    </header>
  );
}
