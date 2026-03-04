import { useMemo, useState, useEffect } from 'react';
import type { Profile } from '../lib/types';
import type { AssignmentRow } from '../lib/websites';
import type { Website } from '../lib/types';
import { BtnEdit } from './ui/ActionIcons';

export type UserSiteRow = {
  user: Profile;
  sites: AssignmentRow[];
  mainSiteId: string | null;
};

const PER_PAGE_OPTIONS = [10, 20, 50] as const;

type Props = {
  rows: UserSiteRow[];
  canSetPrimary: (a: AssignmentRow) => boolean;
  onSetPrimary: (userId: string, websiteId: string) => void;
  onRequestUnassign: (assignmentId: string) => void;
  onEdit: (user: Profile, sites: AssignmentRow[], mainSiteId: string | null) => void;
};

export function UserSiteTable({ rows, canSetPrimary, onSetPrimary, onRequestUnassign, onEdit }: Props) {
  const [search, setSearch] = useState('');
  const [sortAz, setSortAz] = useState<boolean>(true);
  const [page, setPage] = useState(1);
  const [perPage, setPerPage] = useState<number>(10);

  const filteredAndSorted = useMemo(() => {
    const name = (r: UserSiteRow) => (r.user.display_name || r.user.email || '').toLowerCase();
    let list = rows.filter((r) => !search.trim() || name(r).includes(search.trim().toLowerCase()));
    list = [...list].sort((a, b) => {
      const na = name(a);
      const nb = name(b);
      return sortAz ? na.localeCompare(nb) : nb.localeCompare(na);
    });
    return list;
  }, [rows, search, sortAz]);

  const total = filteredAndSorted.length;
  const maxPage = Math.max(1, Math.ceil(total / perPage));
  const safePage = Math.min(page, maxPage);
  const start = (safePage - 1) * perPage;
  const pageRows = useMemo(
    () => filteredAndSorted.slice(start, start + perPage),
    [filteredAndSorted, start, perPage]
  );

  useEffect(() => {
    if (safePage !== page) setPage(safePage);
  }, [safePage, page]);

  return (
    <div className="rounded-xl border border-premium-gold/20 overflow-hidden">
      <div className="flex flex-wrap items-center gap-3 px-4 py-3 border-b border-premium-gold/20 bg-premium-darker/40">
        <input
          type="text"
          value={search}
          onChange={(e) => { setSearch(e.target.value); setPage(1); }}
          placeholder="ค้นหาผู้ใช้..."
          className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white text-sm w-48"
        />
        <button
          type="button"
          onClick={() => setSortAz((v) => !v)}
          className="text-gray-400 hover:text-premium-gold text-sm"
        >
          เรียง A–Z / Z–A
        </button>
        <span className="text-gray-500 text-sm ml-auto">แสดง</span>
        <select
          value={perPage}
          onChange={(e) => { setPerPage(Number(e.target.value)); setPage(1); }}
          className="bg-premium-darker border border-premium-gold/30 rounded px-2 py-1.5 text-white text-sm"
        >
          {PER_PAGE_OPTIONS.map((n) => (
            <option key={n} value={n}>{n} รายการ</option>
          ))}
        </select>
        <span className="text-gray-500 text-sm">
          หน้า {safePage} / {maxPage} (ทั้งหมด {total} คน)
        </span>
        <button
          type="button"
          onClick={() => setPage((p) => Math.max(1, p - 1))}
          disabled={safePage <= 1}
          className="px-2 py-1 rounded border border-premium-gold/30 text-premium-gold text-sm disabled:opacity-50 disabled:cursor-not-allowed hover:bg-premium-gold/10"
        >
          ก่อนหน้า
        </button>
        <button
          type="button"
          onClick={() => setPage((p) => Math.min(maxPage, p + 1))}
          disabled={safePage >= maxPage}
          className="px-2 py-1 rounded border border-premium-gold/30 text-premium-gold text-sm disabled:opacity-50 disabled:cursor-not-allowed hover:bg-premium-gold/10"
        >
          ถัดไป
        </button>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr>
              <th className="text-left p-3 border-b border-premium-gold/20 text-premium-gold">ผู้ใช้</th>
              <th className="text-left p-3 border-b border-premium-gold/20 text-premium-gold">เว็บที่ดูแล</th>
              <th className="text-left p-3 border-b border-premium-gold/20 text-premium-gold">เว็บหลัก</th>
              <th className="text-left p-3 border-b border-premium-gold/20 text-premium-gold">การดำเนินการ</th>
            </tr>
          </thead>
          <tbody>
            {pageRows.length === 0 ? (
              <tr>
                <td colSpan={4} className="p-4 text-center text-gray-500">
                  {rows.length === 0 ? 'ยังไม่มีรายการมอบหมาย' : 'ไม่พบผู้ใช้ที่ตรงกับคำค้น'}
                </td>
              </tr>
            ) : (
              pageRows.map((row) => (
                <tr key={row.user.id} className="border-b border-premium-gold/10 hover:bg-premium-gold/5">
                  <td className="p-3 text-gray-200">{row.user.display_name || row.user.email || '-'}</td>
                  <td className="p-3">
                    <SiteBadges
                      sites={row.sites}
                      mainSiteId={row.mainSiteId}
                      canSetPrimary={canSetPrimary}
                      onSetPrimary={onSetPrimary}
                      onRequestUnassign={onRequestUnassign}
                    />
                  </td>
                  <td className="p-3">
                    {row.mainSiteId ? (
                      <span className="text-premium-gold font-medium">
                        {row.sites.find((s) => s.website_id === row.mainSiteId)?.website?.name ?? row.sites.find((s) => s.website_id === row.mainSiteId)?.website?.alias ?? '—'}
                      </span>
                    ) : (
                      <span className="text-gray-500">—</span>
                    )}
                  </td>
                  <td className="p-3">
                    <BtnEdit onClick={() => onEdit(row.user, row.sites, row.mainSiteId)} title="แก้ไข" />
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function SiteBadges({
  sites,
  mainSiteId,
  canSetPrimary,
  onSetPrimary,
  onRequestUnassign,
}: {
  sites: AssignmentRow[];
  mainSiteId: string | null;
  canSetPrimary: (a: AssignmentRow) => boolean;
  onSetPrimary: (userId: string, websiteId: string) => void;
  onRequestUnassign: (assignmentId: string) => void;
}) {
  if (sites.length === 0) {
    return <span className="text-gray-500 text-sm">ยังไม่มีเว็บ</span>;
  }
  const website = (a: AssignmentRow): Website | undefined => (a as { website?: Website }).website;
  return (
    <div className="flex flex-wrap gap-1.5">
      {sites.map((a) => {
        const w = website(a);
        const name = w?.name ?? w?.alias ?? a.website_id;
        const alias = w?.alias;
        const isMain = a.website_id === mainSiteId;
        return (
          <span
            key={a.id}
            className={`inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs border ${
              isMain ? 'bg-premium-gold/25 border-premium-gold/50 text-premium-gold' : 'bg-premium-darker border-premium-gold/30 text-gray-300'
            }`}
            title={alias ? `${name} (${alias})` : name}
          >
            <span>{isMain ? `${name} (หลัก)` : name}</span>
            {!isMain && canSetPrimary(a) && (
              <button
                type="button"
                className="text-premium-gold/80 hover:text-premium-gold ml-0.5"
                onClick={() => onSetPrimary(a.user_id, a.website_id)}
                title="ตั้งเป็นเว็บหลัก"
              >
                ★
              </button>
            )}
            <button
              type="button"
              className="text-red-400/80 hover:text-red-400 ml-0.5"
              onClick={() => onRequestUnassign(a.id)}
              title="เอาออก"
              aria-label="เอาออก"
            >
              ×
            </button>
          </span>
        );
      })}
    </div>
  );
}
