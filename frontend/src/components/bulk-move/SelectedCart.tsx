/**
 * Right pane: selected staff list, remove icon, validation summary, empty state.
 */

import { useState } from 'react';
import Button from '../ui/Button';
import type { Profile } from '../../lib/types';
import type { ConflictSummary } from '../../lib/bulkShiftAssignment';
import type { BulkConflictMode } from '../../lib/bulkShiftAssignment';

export interface SelectedCartProps {
  selected: Profile[];
  onRemoveOne: (id: string) => void;
  onClearAll: () => void;
  onCheckHolidays: () => void;
  loading: boolean;
  conflictSummary: ConflictSummary | null;
  conflictMode: BulkConflictMode;
  onConflictModeChange: (mode: BulkConflictMode) => void;
  transferDate: string;
  getBranchName: (id: string | null) => string;
  getShiftName: (id: string | null) => string;
}

export default function SelectedCart({
  selected,
  onRemoveOne,
  onClearAll,
  onCheckHolidays,
  loading,
  conflictSummary,
  conflictMode,
  onConflictModeChange,
  transferDate,
  getBranchName,
  getShiftName,
}: SelectedCartProps) {
  const [expandBlocked, setExpandBlocked] = useState(false);
  const movable = conflictSummary ? conflictSummary.totalSelected - conflictSummary.employeesWithConflicts : null;
  const blocked = conflictSummary?.employeesWithConflicts ?? 0;

  return (
    <div className="flex flex-col h-full min-h-0 rounded-xl bg-premium-darker/30 border border-premium-gold/10 overflow-hidden">
      <div className="p-4 border-b border-premium-gold/10 flex items-center justify-between gap-2 shrink-0">
        <h2 className="text-premium-gold/90 font-semibold text-[15px]">
          พนักงานที่เลือกแล้ว <span className="text-gray-400 font-normal">({selected.length})</span>
        </h2>
        {selected.length > 0 && (
          <button type="button" onClick={onClearAll} className="text-[12px] text-gray-400 hover:text-white hover:underline">
            ล้างการเลือก
          </button>
        )}
      </div>

      <div className="flex-1 min-h-0 overflow-auto p-4">
        {selected.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center px-4">
            <div className="w-16 h-16 rounded-full bg-premium-gold/10 border border-premium-gold/20 flex items-center justify-center text-premium-gold/60 text-2xl mb-4">↑</div>
            <p className="text-gray-400 text-sm font-medium">ยังไม่มีผู้ถูกเลือก</p>
            <p className="text-gray-500 text-xs mt-1">เลือกช่องจากตารางฝั่งซ้าย หรือกด &quot;เลือกทั้งหมด&quot;</p>
          </div>
        ) : (
          <ul className="space-y-1">
            {selected.map((e) => (
              <li
                key={e.id}
                className="flex items-center justify-between gap-2 py-2.5 px-3 rounded-lg hover:bg-premium-gold/5 transition"
              >
                <div className="min-w-0 flex-1">
                  <p className="font-medium text-gray-100 truncate text-sm">{e.display_name || e.email || e.id}</p>
                  <p className="text-[12px] text-gray-500 truncate">{getBranchName(e.default_branch_id)} / {getShiftName(e.default_shift_id)}</p>
                </div>
                <button
                  type="button"
                  onClick={() => onRemoveOne(e.id)}
                  className="shrink-0 w-8 h-8 flex items-center justify-center rounded-lg text-gray-400 hover:text-red-400 hover:bg-red-500/10 transition"
                  title="เอาออก"
                >
                  ×
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>

      {selected.length > 0 && (
        <div className="p-4 border-t border-premium-gold/10 shrink-0 space-y-3 bg-premium-dark/30">
          <Button onClick={onCheckHolidays} loading={loading} variant="ghost" className="h-8 px-3 text-xs w-full">
            ตรวจวันหยุด
          </Button>
          {conflictSummary != null && transferDate && (
            <div className="rounded-lg border border-premium-gold/15 bg-premium-darker/50 p-3 text-[13px] space-y-2">
              <p className="text-gray-300">
                ย้ายได้ <strong className="text-green-400">{movable ?? conflictSummary.totalSelected}</strong> คน
                {blocked > 0 && (
                  <> · ติดวันหยุด <strong className="text-amber-400">{blocked}</strong> คน</>
                )}
              </p>
              <div className="flex flex-wrap gap-3 text-xs">
                <label className="flex items-center gap-1.5 cursor-pointer">
                  <input type="radio" checked={conflictMode === 'SKIP_DAYS'} onChange={() => onConflictModeChange('SKIP_DAYS')} className="text-premium-gold" />
                  <span className="text-gray-400">ข้ามเฉพาะวันที่ชน</span>
                </label>
                <label className="flex items-center gap-1.5 cursor-pointer">
                  <input type="radio" checked={conflictMode === 'BLOCK_ALL'} onChange={() => onConflictModeChange('BLOCK_ALL')} className="text-premium-gold" />
                  <span className="text-gray-400">ไม่ดำเนินการถ้ามีวันหยุดชน</span>
                </label>
              </div>
              {blocked > 0 && conflictSummary.conflictList.length > 0 && (
                <div className="mt-2">
                  <button
                    type="button"
                    onClick={() => setExpandBlocked(!expandBlocked)}
                    className="text-premium-gold/90 text-xs hover:underline"
                  >
                    {expandBlocked ? 'ซ่อนรายชื่อ' : 'ดูรายชื่อที่ติดวันหยุด'}
                  </button>
                  {expandBlocked && (
                    <ul className="mt-1.5 text-gray-400 text-xs space-y-0.5 max-h-24 overflow-y-auto">
                      {conflictSummary.conflictList.map((c) => (
                        <li key={c.user_id}>{c.display_name}: {c.dates.join(', ')}</li>
                      ))}
                    </ul>
                  )}
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
