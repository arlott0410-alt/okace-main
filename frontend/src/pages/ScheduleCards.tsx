import { useState, useEffect, useMemo } from 'react';
import MultiSelect from '../components/ui/MultiSelect';
import { supabase } from '../lib/supabase';
import { useDebouncedValue } from '../lib/useDebouncedValue';
import { useAuth } from '../lib/auth';
import { useBranchesShifts } from '../lib/BranchesShiftsContext';
import { useToast } from '../lib/ToastContext';
import { ROLE_OPTIONS, resolveVisibleRoles, toCompactVisibleRoles, HEAD_AND_ABOVE, HEAD_AND_ABOVE_ROLES } from '../lib/roleOptions';
import type { ScheduleCard as ScheduleCardType } from '../lib/types';
import Button from '../components/ui/Button';
import PageModal from '../components/ui/PageModal';
import { BtnEdit, BtnDelete } from '../components/ui/ActionIcons';

const CARD_TYPES = [
  { value: 'link', label: 'ลิงก์' },
  { value: 'sheet', label: 'ชีต' },
  { value: 'form', label: 'ฟอร์ม' },
];

const PRESET_COLORS = [
  { value: '#D4AF37', name: 'ทอง' },
  { value: '#3B82F6', name: 'น้ำเงิน' },
  { value: '#10B981', name: 'เขียว' },
  { value: '#F59E0B', name: 'ส้ม' },
  { value: '#EF4444', name: 'แดง' },
  { value: '#8B5CF6', name: 'ม่วง' },
  { value: '#06B6D4', name: 'ฟ้า' },
  { value: '#EC4899', name: 'ชมพู' },
  { value: '#6B7280', name: 'เทา' },
  { value: '#84CC16', name: 'เหลืองเขียว' },
];

const PAGE_SIZE = 40;

export default function ScheduleCards() {
  const { profile } = useAuth();
  const { branches } = useBranchesShifts();
  const toast = useToast();
  const isAdmin = profile?.role === 'admin';
  const isManager = profile?.role === 'manager';
  const isHead = profile?.role === 'instructor_head';
  const canEdit = isAdmin || isManager || isHead;
  const myBranchId = profile?.default_branch_id ?? null;

  const [cards, setCards] = useState<ScheduleCardType[]>([]);
  const [websites, setWebsites] = useState<{ id: string; name: string; logo_path?: string | null }[]>([]);
  const [formError, setFormError] = useState('');
  const [branchFilterId, setBranchFilterId] = useState<string>('');
  const [websiteFilter, setWebsiteFilter] = useState('');
  const [roleFilter, setRoleFilter] = useState('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [modal, setModal] = useState<{ open: boolean; card?: ScheduleCardType | null }>({ open: false });
  const [lastSavedId, setLastSavedId] = useState<string | null>(null);
  const [form, setForm] = useState({
    title: '',
    url: '',
    icon_url: '',
    color_tag: '#D4AF37',
    scope: 'all',
    card_type: 'link',
    branch_ids: [] as string[],
    visible_roles: [] as string[],
    website_ids: [] as string[],
  });
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    supabase.from('websites').select('id, name, logo_path').order('name').then(({ data }) => setWebsites((data || []) as { id: string; name: string; logo_path?: string | null }[]));
  }, []);

  useEffect(() => {
    let cancelled = false;
    const q = supabase.from('schedule_cards').select('*, website:websites(id, name, logo_path), branch:branches(id, name)').order('sort_order');
    q.then(({ data }) => {
      if (!cancelled) setCards((data || []) as ScheduleCardType[]);
    });
    return () => { cancelled = true; };
  }, []);

  /** รวมแถวซ้ำ (title, url, website_id เดียวกัน) เป็นหนึ่งการ์ด — แผนกรวมใน branch_ids */
  const mergedCards = useMemo(() => {
    const key = (c: ScheduleCardType) => `${c.title}\t${c.url ?? ''}\t${c.website_id ?? ''}`;
    const groups = new Map<string, { card: ScheduleCardType; groupIds: string[] }>();
    for (const c of cards) {
      const k = key(c);
      const bids = c.branch_ids ?? (c.branch_id ? [c.branch_id] : []);
      if (!groups.has(k)) {
        groups.set(k, {
          card: { ...c, branch_ids: [...bids] },
          groupIds: [c.id],
        });
      } else {
        const g = groups.get(k)!;
        const allBids = [...new Set([...(g.card.branch_ids ?? []), ...bids])];
        g.card = { ...g.card, branch_ids: allBids };
        g.groupIds.push(c.id);
      }
    }
    return Array.from(groups.values()).map(({ card, groupIds }) => ({ ...card, groupIds }));
  }, [cards]);

  const debouncedSearch = useDebouncedValue(search, 300);
  const filteredCards = useMemo(() => {
    let list = mergedCards;
    if (branchFilterId && (isAdmin || isManager || isHead)) {
      list = list.filter(
        (c) =>
          c.branch_id === branchFilterId ||
          (Array.isArray(c.branch_ids) && c.branch_ids.length > 0 && c.branch_ids.includes(branchFilterId))
      );
    }
    if (debouncedSearch.trim()) {
      const q = debouncedSearch.trim().toLowerCase();
      list = list.filter((c) => c.title.toLowerCase().includes(q));
    }
    if (websiteFilter) {
      list = list.filter((c) => c.website_id === websiteFilter);
    }
    if (roleFilter) {
      list = list.filter((c) => {
        const roles = (c as ScheduleCardType).visible_roles ?? [];
        if (!Array.isArray(roles)) return false;
        if (roles.length === 0) return true;
        if (roleFilter === HEAD_AND_ABOVE) {
          return HEAD_AND_ABOVE_ROLES.every((r) => roles.includes(r));
        }
        return roles.includes(roleFilter);
      });
    }
    return list;
  }, [mergedCards, branchFilterId, isAdmin, isManager, isHead, debouncedSearch, websiteFilter, roleFilter]);

  const totalPages = Math.max(1, Math.ceil(filteredCards.length / PAGE_SIZE));
  const paginatedCards = useMemo(() => filteredCards.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE), [filteredCards, page]);

  const saveCard = async () => {
    setFormError('');
    if (!form.title.trim()) {
      setFormError('กรุณากรอกชื่อหัวข้อ');
      return;
    }
    const urlTrim = form.url.trim();
    if (!urlTrim) {
      setFormError('กรุณากรอก URL (บังคับ)');
      return;
    }
    if (isHead && !myBranchId) {
      setFormError('หัวหน้าพนักงานประจำต้องมีแผนกในโปรไฟล์ก่อนเพิ่มการ์ด');
      return;
    }
    if ((isAdmin || isManager || isHead) && form.branch_ids.length === 0) {
      setFormError('กรุณาเลือกอย่างน้อย 1 แผนก');
      return;
    }
    setLoading(true);
    const branchIds = form.branch_ids.length ? form.branch_ids : (isHead && myBranchId ? [myBranchId] : []);
    const firstBranch = branchIds[0] ?? null;
    const firstWebsite = form.website_ids.length ? form.website_ids[0] ?? null : null;
    const basePayload = {
      title: form.title.trim(),
      url: urlTrim,
      icon_url: form.icon_url.trim() || null,
      color_tag: form.color_tag || null,
      scope: form.scope,
      card_type: form.card_type,
      visible_roles: (() => { const r = resolveVisibleRoles(form.visible_roles); return r.length ? r : null; })(),
      branch_id: firstBranch,
      branch_ids: branchIds.length ? branchIds : null,
      website_id: firstWebsite,
      created_by: profile?.id ?? null,
    };
    let savedId: string | null = null;
    const cardWithGroup = modal.card as (ScheduleCardType & { groupIds?: string[] }) | undefined;
    if (modal.card?.id) {
      savedId = modal.card.id;
      const { created_by: _drop, ...updatePayload } = basePayload;
      await supabase.from('schedule_cards').update(updatePayload).eq('id', modal.card.id).select('id').single();
      const groupIds = cardWithGroup?.groupIds ?? [];
      for (const id of groupIds) {
        if (id !== modal.card!.id) {
          await supabase.from('schedule_cards').delete().eq('id', id);
        }
      }
    } else {
      const { data: ins } = await supabase.from('schedule_cards').insert(basePayload).select('id').single();
      savedId = ins?.id ?? null;
    }
    setLoading(false);
    setModal({ open: false });
    const { data } = await supabase.from('schedule_cards').select('*, website:websites(id, name, logo_path), branch:branches(id, name)').order('sort_order');
    setCards((data || []) as ScheduleCardType[]);
    if (savedId) {
      setLastSavedId(savedId);
      toast.show(modal.card ? 'แก้ไขการ์ดแล้ว' : 'เพิ่มการ์ดแล้ว');
    }
  };

  const deleteCard = async (id: string) => {
    if (!confirm('ลบการ์ดนี้?')) return;
    await supabase.from('schedule_cards').delete().eq('id', id);
    setCards((prev) => prev.filter((c) => c.id !== id));
    toast.show('ลบการ์ดแล้ว');
  };

  const roleOptionsForSelect = ROLE_OPTIONS.map((r) => ({ id: r.value, label: r.label }));

  return (
    <div>
      <h1 className="text-premium-gold text-xl font-semibold mb-4">ตารางงาน</h1>

      {/* Filter bar */}
      <div className="rounded-lg border border-premium-gold/20 bg-premium-darker/40 p-3 mb-4">
        <div className="flex flex-wrap items-end gap-3">
          <input type="text" placeholder="ค้นหา…" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1); }} className="bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white text-sm w-44 placeholder-gray-500" />
          {(isAdmin || isManager || isHead) && (
            <div>
              <label className="block text-gray-400 text-xs mb-0.5">แผนก</label>
              <select value={branchFilterId} onChange={(e) => { setBranchFilterId(e.target.value); setPage(1); }} className="bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white text-sm min-w-[140px]">
                <option value="">ทั้งหมด</option>
                {branches.map((b) => (
                  <option key={b.id} value={b.id}>{b.name}</option>
                ))}
              </select>
            </div>
          )}
          <div>
            <label className="block text-gray-400 text-xs mb-0.5">เว็บ</label>
            <select value={websiteFilter} onChange={(e) => { setWebsiteFilter(e.target.value); setPage(1); }} className="bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white text-sm min-w-[140px]">
              <option value="">ทั้งหมด</option>
              {websites.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-gray-400 text-xs mb-0.5">ตำแหน่ง</label>
            <select value={roleFilter} onChange={(e) => { setRoleFilter(e.target.value); setPage(1); }} className="bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white text-sm min-w-[160px]">
              <option value="">ทั้งหมด</option>
              {ROLE_OPTIONS.map((r) => <option key={r.value} value={r.value}>{r.label}</option>)}
            </select>
          </div>
          <span className="text-gray-500 text-sm">{filteredCards.length} รายการ</span>
          {canEdit && (
            <Button variant="gold" className="ml-auto" onClick={() => {
              setForm({
                title: '',
                url: '',
                icon_url: '',
                color_tag: '#D4AF37',
                scope: 'all',
                card_type: 'link',
                branch_ids: (isAdmin || isManager || isHead) ? (branchFilterId ? [branchFilterId] : []) : (isHead && myBranchId ? [myBranchId] : []),
                visible_roles: [],
                website_ids: [],
              });
              setModal({ open: true, card: null });
            }}>
              เพิ่มการ์ด
            </Button>
          )}
        </div>
      </div>

      {/* Card Grid (Shortcuts style) */}
      <div className="rounded-lg border border-premium-gold/20 overflow-hidden bg-premium-darker/30">
        {filteredCards.length === 0 ? (
          <div className="py-12 text-center text-gray-400">ไม่พบการ์ดตามตัวกรอง</div>
        ) : (
          <>
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-4 p-4">
              {paginatedCards.map((card) => {
                const iconUrl = (card as ScheduleCardType).icon_url ?? (card as ScheduleCardType).website?.logo_path ?? null;
                const isNew = lastSavedId === card.id;
                return (
                  <div
                    key={card.id}
                    onClick={() => { if (card.url) window.open(card.url, '_blank'); }}
                    className={`group rounded-xl border bg-black/40 min-h-[140px] p-6 relative cursor-pointer transition-all duration-200 border-[#FFD700]/20 hover:bg-black/55 hover:shadow-[0_0_0_1px_rgba(255,215,0,0.25)] ${isNew ? 'ring-1 ring-inset ring-premium-gold/40 bg-premium-gold/10' : ''}`}
                  >
                    <div className="flex flex-col items-center justify-center h-full min-h-[100px] text-center">
                      <div className="w-16 h-16 flex items-center justify-center shrink-0 mb-2">
                        {iconUrl ? (
                          <>
                            <img src={iconUrl} alt="" className="w-16 h-16 object-contain rounded" onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; (e.target as HTMLImageElement).nextElementSibling?.classList.remove('hidden'); }} />
                            <span className="hidden w-16 h-16 flex items-center justify-center text-premium-gold text-3xl" aria-hidden>🔗</span>
                          </>
                        ) : (
                          <span className="w-16 h-16 flex items-center justify-center rounded bg-premium-gold/15 text-premium-gold text-3xl" aria-hidden>🔗</span>
                        )}
                      </div>
                      <span className="text-[13px] font-medium text-gray-200 block truncate w-full px-1" style={{ color: card.color_tag || undefined }}>{card.title}</span>
                    </div>
                    <div className="absolute bottom-2 right-2 flex items-center gap-0.5" onClick={(e) => e.stopPropagation()}>
                      {canEdit && (
                        <>
                          <BtnEdit onClick={() => {
                            const bids = (card as ScheduleCardType & { branch_ids?: string[] | null }).branch_ids ?? (card.branch_id ? [card.branch_id] : []);
                            setForm({
                              title: card.title,
                              url: card.url || '',
                              icon_url: (card as ScheduleCardType).icon_url || '',
                              color_tag: card.color_tag || '#D4AF37',
                              scope: card.scope,
                              card_type: card.card_type,
                              branch_ids: bids.length ? bids : [],
                              visible_roles: toCompactVisibleRoles(card.visible_roles),
                              website_ids: card.website_id ? [card.website_id] : [],
                            });
                            setFormError('');
                            setModal({ open: true, card });
                          }} title="แก้ไข" />
                          <BtnDelete onClick={() => {
                            const groupIds = (card as ScheduleCardType & { groupIds?: string[] }).groupIds;
                            if (groupIds && groupIds.length > 0) {
                              if (!confirm('ลบการ์ดนี้? (รวมทุกแผนกที่ผูกไว้)')) return;
                              Promise.all(groupIds.map((id) => supabase.from('schedule_cards').delete().eq('id', id))).then(() => {
                                setCards((prev) => prev.filter((c) => !groupIds.includes(c.id)));
                                toast.show('ลบการ์ดแล้ว');
                              });
                            } else {
                              deleteCard(card.id);
                            }
                          }} title="ลบ" />
                        </>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
            {totalPages > 1 && (
              <div className="flex items-center justify-between px-3 py-2 border-t border-premium-gold/20 text-sm text-gray-400">
                <span>หน้า {page} / {totalPages}</span>
                <div className="flex gap-2">
                  <button type="button" onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page <= 1} className="px-2 py-1 rounded border border-premium-gold/30 text-premium-gold disabled:opacity-50">ก่อนหน้า</button>
                  <button type="button" onClick={() => setPage((p) => Math.min(totalPages, p + 1))} disabled={page >= totalPages} className="px-2 py-1 rounded border border-premium-gold/30 text-premium-gold disabled:opacity-50">ถัดไป</button>
                </div>
              </div>
            )}
          </>
        )}
      </div>

      <PageModal open={modal.open} onClose={() => setModal({ open: false })} title={modal.card ? 'แก้ไขการ์ด' : 'เพิ่มการ์ด'} onCancel={() => setModal({ open: false })} onSave={saveCard} saveLoading={loading}>
        <div className="space-y-4">
          {formError && <p className="text-red-400 text-sm">{formError}</p>}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-gray-400 text-sm mb-1">ชื่อหัวข้อ *</label>
              <input value={form.title} onChange={(e) => setForm((f) => ({ ...f, title: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white" placeholder="ชื่อการ์ด" />
            </div>
            <div>
              <label className="block text-gray-400 text-sm mb-1">URL *</label>
              <input value={form.url} onChange={(e) => setForm((f) => ({ ...f, url: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white" placeholder="https://..." />
            </div>
          </div>
          <div>
            <label className="block text-gray-400 text-sm mb-1">ลิงก์รูปไอคอน</label>
            <input value={form.icon_url} onChange={(e) => setForm((f) => ({ ...f, icon_url: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white" placeholder="https://... (ไม่บังคับ)" />
            <p className="text-gray-500 text-xs mt-0.5">ใส่ URL รูปไอคอนจะแสดงบนการ์ด — ไม่ยึดตามเว็บ</p>
          </div>
          <div>
            <label className="block text-gray-400 text-sm mb-1">สี</label>
            <div className="flex flex-wrap gap-2 mt-1">
              {PRESET_COLORS.map((c) => (
                <button key={c.value} type="button" title={c.name} onClick={() => setForm((f) => ({ ...f, color_tag: c.value }))} className={`w-8 h-8 rounded-full border-2 transition-transform hover:scale-110 ${form.color_tag === c.value ? 'border-white ring-2 ring-premium-gold' : 'border-premium-gold/30'}`} style={{ backgroundColor: c.value }} />
              ))}
            </div>
          </div>
          <section className="rounded-lg border border-premium-gold/20 bg-premium-darker/50 p-3">
            <h4 className="text-premium-gold/90 text-sm font-medium mb-3">สิทธิ์การมองเห็น</h4>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {(isAdmin || isManager || isHead) && <MultiSelect label="แผนก" options={branches.map((b) => ({ id: b.id, label: b.name }))} value={form.branch_ids} onChange={(branch_ids) => setForm((f) => ({ ...f, branch_ids }))} placeholder="เลือกแผนก (ได้หลายแผนก)" showChips searchable />}
              <MultiSelect label="เว็บที่เห็นได้" options={websites.map((w) => ({ id: w.id, label: w.name }))} value={form.website_ids} onChange={(website_ids) => setForm((f) => ({ ...f, website_ids }))} placeholder="เลือกเว็บ" allId="" allLabel="ทั้งหมด" showChips searchable />
              <MultiSelect label="ตำแหน่งที่เห็นได้" options={roleOptionsForSelect} value={form.visible_roles} onChange={(visible_roles) => setForm((f) => ({ ...f, visible_roles }))} placeholder="ไม่เลือก = ทุกตำแหน่ง" showChips searchable />
            </div>
          </section>
          <div>
            <label className="block text-gray-400 text-sm mb-1">ประเภท</label>
            <select value={form.card_type} onChange={(e) => setForm((f) => ({ ...f, card_type: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white">
              {CARD_TYPES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select>
          </div>
        </div>
      </PageModal>
    </div>
  );
}
