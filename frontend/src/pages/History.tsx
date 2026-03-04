import { useState, useEffect, useCallback } from 'react';
import { format, subDays } from 'date-fns';
import { th } from 'date-fns/locale';
import { supabase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import { useBranchesShifts } from '../lib/BranchesShiftsContext';
import type { AuditLogRow, AuditLogDetail } from '../lib/types';
import type { ShiftChangeHistoryItemWithMeta } from '../lib/transfers';
import { listShiftChangeHistory, enrichShiftChangeHistoryWithMeta } from '../lib/transfers';

const PAGE_SIZE = 50;
const ENTITY_OPTIONS = [
  { value: '', label: 'ทั้งหมด' },
  { value: 'work_logs', label: 'เข้างาน/ออกงาน' },
  { value: 'holidays', label: 'วันหยุด' },
  { value: 'shift_swaps', label: 'สลับกะ' },
  { value: 'cross_branch_transfers', label: 'ย้ายกะข้ามแผนก' },
  { value: 'duty_assignments', label: 'จัดหน้าที่' },
  { value: 'managed_website', label: 'เว็บที่ดูแล' },
  { value: 'profiles', label: 'สมาชิก' },
  { value: 'schedule_cards', label: 'ตารางงาน' },
  { value: 'file_vault', label: 'คลังเก็บไฟล์' },
  { value: 'group_links', label: 'ศูนย์รวมกลุ่มงาน' },
];

/** คำอธิบายการกระทำเป็นภาษาไทย — อ่านง่าย ไม่ใช้รหัส */
const ACTION_LABELS: Record<string, string> = {
  user_update: 'แก้ไขสมาชิก',
  user_create: 'เพิ่มสมาชิก',
  holiday_book: 'จองวันหยุด/ลา',
  holiday_add: 'เพิ่มวันหยุด/ลาให้พนักงาน',
  holiday_edit: 'แก้ไขวันหยุด/ลา',
  holiday_remove: 'ลบวันหยุด/ลา',
  holiday_approve: 'อนุมัติวันลา',
  holiday_reject: 'ไม่อนุมัติวันลา',
  duty_assign: 'จัดคนเข้าหน้าที่',
  duty_clear: 'ล้างการจัดหน้าที่',
  duty_random: 'สุ่มจัดหน้าที่อัตโนมัติ',
  roster_confirm: 'ยืนยันตารางกะ',
  roster_unlock: 'ปลดล็อกตารางกะ',
  meal_book: 'จองพักอาหาร',
  meal_cancel: 'ยกเลิกจองพัก',
  break_start: 'เริ่มพัก',
  break_end: 'สิ้นสุดพัก',
  work_log: 'ลงเวลา',
  WEBSITE_CREATE: 'สร้างเว็บที่ดูแล',
  WEBSITE_UPDATE: 'แก้ไขเว็บที่ดูแล',
  WEBSITE_DELETE: 'ลบเว็บที่ดูแล',
  WEBSITE_ASSIGN: 'มอบหมายคนดูแลเว็บ',
  WEBSITE_UNASSIGN: 'ยกเลิกการมอบหมายเว็บ',
  WEBSITE_SET_PRIMARY: 'ตั้งเว็บหลัก',
  schedule_card_create: 'สร้างการ์ดตารางงาน',
  schedule_card_update: 'แก้ไขการ์ดตารางงาน',
  schedule_card_delete: 'ลบการ์ดตารางงาน',
  file_vault_create: 'อัปโหลดไฟล์',
  file_vault_update: 'แก้ไขหัวข้อไฟล์',
  file_vault_delete: 'ลบไฟล์',
  group_link_create: 'สร้างกลุ่มงาน',
  group_link_update: 'แก้ไขกลุ่มงาน',
  group_link_delete: 'ลบกลุ่มงาน',
};

/** คำอธิบายโมดูลเป็นภาษาไทย */
const ENTITY_LABELS: Record<string, string> = Object.fromEntries(
  ENTITY_OPTIONS.filter((o) => o.value).map((o) => [o.value, o.label])
);

/** เป้าหมายอ่านง่ายตาม entity เมื่อไม่มี summary_text */
const ENTITY_TARGET_FALLBACK: Record<string, string> = {
  holidays: 'รายการวันหยุด/ลา',
  duty_assignments: 'รายการจัดหน้าที่',
  shift_swaps: 'รายการสลับกะ',
  cross_branch_transfers: 'รายการย้ายกะข้ามแผนก',
  profiles: 'รายการสมาชิก',
  managed_website: 'รายการเว็บที่ดูแล',
  break_logs: 'รายการพัก',
  work_logs: 'รายการลงเวลา',
  monthly_roster_status: 'ตารางกะ',
  schedule_cards: 'ตารางงาน',
  file_vault: 'คลังเก็บไฟล์',
  group_links: 'ศูนย์รวมกลุ่มงาน',
};

function defaultDateRange() {
  const end = new Date();
  const start = subDays(end, 7);
  return {
    from: format(start, 'yyyy-MM-dd'),
    to: format(end, 'yyyy-MM-dd'),
  };
}

export type UnifiedLogRow =
  | (AuditLogRow & { isShift?: false })
  | {
      id: string;
      created_at: string;
      actor_id: string | null;
      action: string;
      entity: string;
      entity_id: string | null;
      summary_text: string | null;
      profiles?: { display_name: string | null; email: string | null } | null;
      isShift: true;
      shiftItem: ShiftChangeHistoryItemWithMeta;
    };

const STATUS_LABEL: Record<string, string> = {
  pending: 'รออนุมัติ',
  approved: 'อนุมัติแล้ว',
  rejected: 'ปฏิเสธ',
  cancelled: 'ยกเลิก',
};

function shiftRowToUnified(t: ShiftChangeHistoryItemWithMeta): UnifiedLogRow {
  const fromLabel = t.from_branch?.name && t.from_shift?.name ? `${t.from_branch.name}/${t.from_shift.name}` : '—';
  const toLabel = t.to_branch?.name && t.to_shift?.name ? `${t.to_branch.name}/${t.to_shift.name}` : '—';
  const who = t.profile?.display_name || t.profile?.email || '—';
  const actionLabel = t.type === 'swap' ? 'สลับกะ (รับกะ)' : 'ย้ายกะข้ามแผนก';
  const statusText = STATUS_LABEL[t.status] || t.status;
  const summary = `${who}: ${fromLabel} → ${toLabel} เริ่ม ${t.start_date} (${statusText})`;
  return {
    id: `${t.type}-${t.id}`,
    created_at: t.created_at,
    actor_id: t.user_id,
    action: actionLabel,
    entity: t.type === 'swap' ? 'shift_swaps' : 'cross_branch_transfers',
    entity_id: t.id,
    summary_text: summary,
    profiles: t.profile ? { display_name: t.profile.display_name ?? null, email: t.profile.email ?? null } : null,
    isShift: true,
    shiftItem: t,
  };
}

export default function History() {
  const { profile, user } = useAuth();
  const { branches, shifts } = useBranchesShifts();
  const isAdmin = profile?.role === 'admin';
  const isManager = profile?.role === 'manager';
  const isInstructorHead = profile?.role === 'instructor_head';

  const [filterFrom, setFilterFrom] = useState(() => defaultDateRange().from);
  const [filterTo, setFilterTo] = useState(() => defaultDateRange().to);
  const [filterModule, setFilterModule] = useState('');
  const [filterAction, setFilterAction] = useState('');
  const [auditLogs, setAuditLogs] = useState<AuditLogRow[]>([]);
  const [shiftLogs, setShiftLogs] = useState<UnifiedLogRow[]>([]);
  const [lastCreatedAt, setLastCreatedAt] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(false);
  const [detailId, setDetailId] = useState<string | null>(null);
  const [detail, setDetail] = useState<AuditLogDetail | null>(null);
  const [detailShift, setDetailShift] = useState<ShiftChangeHistoryItemWithMeta | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);

  const start = filterFrom;
  const end = filterTo;
  const startTs = `${start}T00:00:00Z`;
  const endTs = `${end}T23:59:59.999Z`;

  const fetchAuditPage = useCallback(
    async (cursor: string | null) => {
      setLoading(true);
      const cols = 'id, created_at, actor_id, action, entity, entity_id, summary_text';
      let q = supabase
        .from('audit_logs')
        .select(`${cols}, profiles!actor_id(display_name, email)`)
        .gte('created_at', startTs)
        .lte('created_at', endTs)
        .order('created_at', { ascending: false })
        .limit(PAGE_SIZE);
      if (filterModule && filterModule !== 'shift_swaps' && filterModule !== 'cross_branch_transfers') q = q.eq('entity', filterModule);
      if (filterAction) q = q.eq('action', filterAction);
      if (cursor) q = q.lt('created_at', cursor);

      const { data, error } = await q;
      setLoading(false);
      if (error) {
        setHasMore(false);
        return;
      }
      const raw = (data || []) as Array<Omit<AuditLogRow, 'profiles'> & { profiles?: { display_name: string | null; email: string | null } | Array<{ display_name: string | null; email: string | null }> | null }>;
      const list: AuditLogRow[] = raw.map((row) => ({
        ...row,
        profiles: Array.isArray(row.profiles) ? row.profiles[0] ?? null : row.profiles ?? null,
      }));
      if (cursor) {
        setAuditLogs((prev) => [...prev, ...list]);
      } else {
        setAuditLogs(list);
      }
      setHasMore(list.length === PAGE_SIZE);
      if (list.length > 0) setLastCreatedAt(list[list.length - 1].created_at);
      else setLastCreatedAt(null);
    },
    [startTs, endTs, filterModule, filterAction]
  );

  const fetchShiftHistory = useCallback(async () => {
    const month = start.slice(0, 7);
    const opts = { isAdmin, isManager, isInstructorHead, currentUserId: user?.id ?? '', myBranchId: profile?.default_branch_id ?? null };
    const { data: items } = await listShiftChangeHistory(
      { month, status: undefined },
      opts,
      { page: 1, pageSize: 500 }
    );
    const withMeta = await enrichShiftChangeHistoryWithMeta(items, branches, shifts);
    const inRange = withMeta.filter((t) => t.created_at >= startTs && t.created_at <= endTs);
    const filtered =
      filterModule === 'cross_branch_transfers' ? inRange.filter((t) => t.type === 'transfer') : filterModule === 'shift_swaps' ? inRange.filter((t) => t.type === 'swap') : inRange;
    setShiftLogs(filtered.map(shiftRowToUnified));
  }, [start, startTs, endTs, filterModule, isAdmin, isManager, isInstructorHead, user?.id, profile?.default_branch_id, branches, shifts]);

  useEffect(() => {
    setLastCreatedAt(null);
    setHasMore(true);
    if (filterModule !== 'shift_swaps' && filterModule !== 'cross_branch_transfers') {
      fetchAuditPage(null);
    } else {
      setAuditLogs([]);
      setHasMore(false);
    }
  }, [fetchAuditPage, filterModule]);

  useEffect(() => {
    if (filterModule === '' || filterModule === 'shift_swaps' || filterModule === 'cross_branch_transfers') {
      fetchShiftHistory();
    } else {
      setShiftLogs([]);
    }
  }, [filterModule, fetchShiftHistory]);

  const logs: UnifiedLogRow[] = (() => {
    const auditRows: UnifiedLogRow[] = auditLogs.map((r) => ({ ...r, isShift: false as const }));
    const combined = filterModule === 'shift_swaps' || filterModule === 'cross_branch_transfers' ? shiftLogs : [...auditRows, ...shiftLogs];
    return combined.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
  })();

  const loadMore = () => {
    if (loading || !hasMore || !lastCreatedAt) return;
    fetchAuditPage(lastCreatedAt);
  };

  const openDetail = async (row: UnifiedLogRow) => {
    setDetailId(row.id);
    setDetail(null);
    setDetailShift(null);
    if (row.isShift && 'shiftItem' in row) {
      setDetailShift(row.shiftItem);
      setDetailLoading(false);
      return;
    }
    setDetailLoading(true);
    const { data } = await supabase
      .from('audit_logs')
      .select('id, details_json, created_at')
      .eq('id', row.id)
      .single();
    setDetailLoading(false);
    setDetail((data as AuditLogDetail) || null);
  };

  const closeDetail = () => {
    setDetailId(null);
    setDetail(null);
    setDetailShift(null);
  };

  const actorName = (row: UnifiedLogRow) =>
    row.profiles?.display_name || row.profiles?.email || '—';
  const actionLabel = (action: string) =>
    ACTION_LABELS[action] || action;
  const entityLabel = (entity: string) =>
    ENTITY_LABELS[entity] || entity;
  /** เป้าหมาย: อ่านง่าย ไม่ใช้รหัส/UUID — ใช้ summary_text หรือคำอธิบายตามโมดูล */
  const targetDisplay = (row: UnifiedLogRow) => {
    if (row.summary_text && String(row.summary_text).trim()) return String(row.summary_text).trim();
    if (row.entity && ENTITY_TARGET_FALLBACK[row.entity]) return ENTITY_TARGET_FALLBACK[row.entity];
    return '—';
  };

  return (
    <div>
      <h1 className="text-premium-gold text-xl font-semibold mb-4">ประวัติการทำรายการ</h1>

      {/* Compact filter row — single line */}
      <div className="flex flex-wrap items-center gap-2 mb-4">
        <input
          type="date"
          value={filterFrom}
          onChange={(e) => setFilterFrom(e.target.value)}
          className="bg-premium-dark border border-premium-gold/30 rounded px-2.5 py-1.5 text-white text-sm"
        />
        <span className="text-gray-500 text-sm">–</span>
        <input
          type="date"
          value={filterTo}
          onChange={(e) => setFilterTo(e.target.value)}
          className="bg-premium-dark border border-premium-gold/30 rounded px-2.5 py-1.5 text-white text-sm"
        />
        <select
          value={filterModule}
          onChange={(e) => setFilterModule(e.target.value)}
          className="bg-premium-dark border border-premium-gold/30 rounded px-2.5 py-1.5 text-white text-sm min-w-[140px]"
        >
          {ENTITY_OPTIONS.map((o) => (
            <option key={o.value || 'all'} value={o.value}>{o.label}</option>
          ))}
        </select>
        <input
          type="text"
          value={filterAction}
          onChange={(e) => setFilterAction(e.target.value)}
          placeholder="การกระทำ"
          className="bg-premium-dark border border-premium-gold/30 rounded px-2.5 py-1.5 text-white text-sm w-40"
        />
      </div>

      <div className="overflow-x-auto border border-premium-gold/20 rounded-lg">
        <table className="w-full text-sm">
          <thead className="sticky-head">
            <tr>
              <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold whitespace-nowrap">เวลา</th>
              <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold whitespace-nowrap">ผู้ทำ</th>
              <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold whitespace-nowrap">การกระทำ</th>
              <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold whitespace-nowrap">เป้าหมาย</th>
              <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold whitespace-nowrap">โมดูล</th>
              <th className="w-14 p-2 border-b border-premium-gold/20 text-premium-gold"></th>
            </tr>
          </thead>
          <tbody>
            {logs.map((log) => (
              <tr key={log.id} className="border-b border-premium-gold/10">
                <td className="px-2 py-1.5 text-gray-400 whitespace-nowrap">
                  {format(new Date(log.created_at), 'dd/MM HH:mm', { locale: th })}
                </td>
                <td className="px-2 py-1.5 text-gray-300 truncate max-w-[140px]" title={actorName(log)}>
                  {actorName(log)}
                </td>
                <td className="px-2 py-1.5 text-gray-300">{actionLabel(log.action)}</td>
                <td className="px-2 py-1.5 text-gray-400 truncate max-w-[280px]" title={log.summary_text || ''}>
                  {targetDisplay(log)}
                </td>
                <td className="px-2 py-1.5 text-gray-400">{entityLabel(log.entity)}</td>
                <td className="px-2 py-1.5">
                  <button
                    type="button"
                    onClick={() => openDetail(log)}
                    className="text-premium-gold hover:underline text-xs py-1 px-2 rounded border border-premium-gold/40"
                  >
                    ดู
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {loading && auditLogs.length === 0 && shiftLogs.length === 0 && (
        <p className="text-gray-500 text-sm mt-2">กำลังโหลด...</p>
      )}
      {!loading && logs.length === 0 && (
        <p className="text-gray-500 text-sm mt-2">ไม่มีรายการในช่วงที่เลือก</p>
      )}
      {hasMore && auditLogs.length > 0 && (filterModule === '' || (filterModule !== 'shift_swaps' && filterModule !== 'cross_branch_transfers')) && (
        <div className="mt-3">
          <button
            type="button"
            onClick={loadMore}
            disabled={loading}
            className="text-premium-gold hover:underline text-sm disabled:opacity-50"
          >
            {loading ? 'กำลังโหลด...' : 'โหลดเพิ่ม'}
          </button>
        </div>
      )}

      {/* Lazy detail modal */}
      {detailId && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/60"
          onClick={closeDetail}
          role="dialog"
          aria-modal="true"
          aria-labelledby="detail-title"
        >
          <div
            className="bg-premium-darker border border-premium-gold/30 rounded-lg shadow-xl max-w-lg w-full mx-4 max-h-[80vh] overflow-hidden flex flex-col"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="p-4 border-b border-premium-gold/20 flex justify-between items-center">
              <h2 id="detail-title" className="text-premium-gold font-medium">รายละเอียด</h2>
              <button
                type="button"
                onClick={closeDetail}
                className="text-gray-400 hover:text-white text-xl leading-none"
                aria-label="ปิด"
              >
                ×
              </button>
            </div>
            <div className="p-4 overflow-y-auto text-sm">
              {detailLoading && <p className="text-gray-500">กำลังโหลด...</p>}
              {!detailLoading && detail && <DetailContent detail={detail} />}
              {!detailLoading && detailShift && <ShiftDetailContent item={detailShift} />}
              {!detailLoading && !detail && !detailShift && <p className="text-gray-500">ไม่พบข้อมูล</p>}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function DetailContent({ detail }: { detail: AuditLogDetail }) {
  const d = detail.details_json as Record<string, unknown> | null | undefined;
  if (!d || typeof d !== 'object') {
    return (
      <pre className="text-gray-400 whitespace-pre-wrap break-all">
        {detail.details_json != null ? JSON.stringify(detail.details_json, null, 2) : '—'}
      </pre>
    );
  }
  const before = d.before_json ?? d.before;
  const after = d.after_json ?? d.after;
  const reason = d.reason ?? d.reject_reason;
  const leaveType = d.leave_type;
  const date = d.date ?? d.holiday_date ?? d.logical_date;

  return (
    <div className="space-y-3 text-gray-300">
      {detail.created_at && (
        <p><span className="text-gray-500">เวลา:</span> {format(new Date(detail.created_at), 'dd/MM/yyyy HH:mm', { locale: th })}</p>
      )}
      {reason != null && <p><span className="text-gray-500">เหตุผล:</span> {String(reason)}</p>}
      {leaveType != null && <p><span className="text-gray-500">ประเภทวันลา:</span> {String(leaveType)}</p>}
      {date != null && <p><span className="text-gray-500">วันที่:</span> {String(date)}</p>}
      {before != null && (
        <div>
          <p className="text-gray-500 mb-1">ก่อนแก้ไข</p>
          <pre className="bg-black/30 rounded p-2 text-xs overflow-x-auto">{JSON.stringify(before, null, 2)}</pre>
        </div>
      )}
      {after != null && (
        <div>
          <p className="text-gray-500 mb-1">หลังแก้ไข</p>
          <pre className="bg-black/30 rounded p-2 text-xs overflow-x-auto">{JSON.stringify(after, null, 2)}</pre>
        </div>
      )}
      {before == null && after == null && (
        <pre className="text-gray-400 whitespace-pre-wrap break-all">{JSON.stringify(d, null, 2)}</pre>
      )}
    </div>
  );
}

function ShiftDetailContent({ item }: { item: ShiftChangeHistoryItemWithMeta }) {
  const fromLabel = item.from_branch?.name && item.from_shift?.name ? `${item.from_branch.name} / ${item.from_shift.name}` : '—';
  const toLabel = item.to_branch?.name && item.to_shift?.name ? `${item.to_branch.name} / ${item.to_shift.name}` : '—';
  const who = item.profile?.display_name || item.profile?.email || '—';
  const statusText = STATUS_LABEL[item.status] || item.status;
  return (
    <div className="space-y-3 text-gray-300">
      {item.created_at && (
        <p><span className="text-gray-500">วันที่สร้าง:</span> {format(new Date(item.created_at), 'dd/MM/yyyy HH:mm', { locale: th })}</p>
      )}
      <p><span className="text-gray-500">ผู้ขอ:</span> {who}</p>
      <p><span className="text-gray-500">ประเภท:</span> {item.type === 'swap' ? 'สลับกะในแผนก' : 'ย้ายกะข้ามแผนก'}</p>
      <p><span className="text-gray-500">จากแผนก/กะ:</span> {fromLabel}</p>
      <p><span className="text-gray-500">ไปแผนก/กะ:</span> {toLabel}</p>
      <p><span className="text-gray-500">ช่วงวันที่:</span> {item.start_date}{item.end_date ? ` ถึง ${item.end_date}` : ''}</p>
      <p><span className="text-gray-500">สถานะ:</span> {statusText}</p>
    </div>
  );
}
