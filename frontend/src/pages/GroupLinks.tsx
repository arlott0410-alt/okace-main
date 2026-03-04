import { useState, useEffect, useMemo, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useDebouncedValue } from '../lib/useDebouncedValue';
import { useAuth } from '../lib/auth';
import { useBranchesShifts } from '../lib/BranchesShiftsContext';
import { useToast } from '../lib/ToastContext';
import type { GroupLinkRow } from '../lib/types';
import { ROLE_OPTIONS, getRoleLabel, resolveVisibleRoles, toCompactVisibleRoles } from '../lib/roleOptions';
import Button from '../components/ui/Button';
import PageModal from '../components/ui/PageModal';
import MultiSelect from '../components/ui/MultiSelect';

type WebsiteOption = { id: string; name: string; alias: string; branch_id?: string | null };

function getLinkWebsiteIds(link: GroupLinkRow): string[] {
  const fromJunction = (link.group_link_websites || []).map((x) => x.website_id);
  if (fromJunction.length) return fromJunction;
  if (link.website_id) return [link.website_id];
  return [];
}

/** All branch IDs for display and edit form. Merge branch_id (primary) + group_link_branches, dedupe. Save logic still uses first id as branch_id. */
function getLinkBranchIds(link: GroupLinkRow): string[] {
  const ids: string[] = [];
  if (link.branch_id) ids.push(link.branch_id);
  for (const j of link.group_link_branches || []) {
    if (j.branch_id) ids.push(j.branch_id);
  }
  return Array.from(new Set(ids));
}

function getPrimaryWebsiteId(link: GroupLinkRow): string | null {
  const ids = getLinkWebsiteIds(link);
  return ids[0] ?? null;
}

/** สีแยกตามเว็บ (ไม่ซ้ำ) — ใช้สำหรับ badge และขอบการ์ด */
const WEBSITE_PALETTE = [
  { bg: 'rgba(212,175,55,0.2)', border: 'rgba(212,175,55,0.5)', text: '#D4AF37' },   // ทอง (PG699 ฯลฯ)
  { bg: 'rgba(59,130,246,0.2)', border: 'rgba(59,130,246,0.5)', text: '#3B82F6' },   // น้ำเงิน
  { bg: 'rgba(16,185,129,0.2)', border: 'rgba(16,185,129,0.5)', text: '#10B981' },   // เขียว
  { bg: 'rgba(245,158,11,0.2)', border: 'rgba(245,158,11,0.5)', text: '#F59E0B' },   // ส้ม
  { bg: 'rgba(139,92,246,0.2)', border: 'rgba(139,92,246,0.5)', text: '#8B5CF6' },   // ม่วง
  { bg: 'rgba(236,72,153,0.2)', border: 'rgba(236,72,153,0.5)', text: '#EC4899' },   // ชมพู
  { bg: 'rgba(6,182,212,0.2)', border: 'rgba(6,182,212,0.5)', text: '#06B6D4' },     // ฟ้า
  { bg: 'rgba(239,68,68,0.2)', border: 'rgba(239,68,68,0.5)', text: '#EF4444' },   // แดง
];

function getWebsiteColor(websiteId: string | null, websites: WebsiteOption[]): typeof WEBSITE_PALETTE[0] {
  if (!websiteId) return WEBSITE_PALETTE[0];
  const idx = websites.findIndex((w) => w.id === websiteId);
  return WEBSITE_PALETTE[idx % WEBSITE_PALETTE.length] ?? WEBSITE_PALETTE[0];
}

export default function GroupLinks() {
  const { profile } = useAuth();
  const { branches } = useBranchesShifts();
  const toast = useToast();
  const isAdmin = profile?.role === 'admin';
  const isManager = profile?.role === 'manager';
  const isInstructorHead = profile?.role === 'instructor_head';
  const canEditLinks = isAdmin || isManager || isInstructorHead;
  const [links, setLinks] = useState<GroupLinkRow[]>([]);
  const [websites, setWebsites] = useState<WebsiteOption[]>([]);
  const [websiteFilter, setWebsiteFilter] = useState('');
  const [branchFilterId, setBranchFilterId] = useState('');
  const [searchQuery, setSearchQuery] = useState('');
  const [modal, setModal] = useState<{ open: boolean; link?: GroupLinkRow | null }>({ open: false });
  const [form, setForm] = useState({
    title: '',
    url: '',
    description: '',
    branch_ids: [] as string[],
    website_id: '',
    visible_roles: [] as string[],
  });
  const [formError, setFormError] = useState('');
  const [loading, setLoading] = useState(false);
  const [linksLoading, setLinksLoading] = useState(true);
  const [lastSavedId, setLastSavedId] = useState<string | null>(null);

  const fetchLinks = useCallback(() => {
    setLinksLoading(true);
    supabase.from('group_links').select('*, group_link_websites(website_id), group_link_branches(branch_id)').order('sort_order').then(({ data, error }) => {
      setLinks((data || []) as GroupLinkRow[]);
      setLinksLoading(false);
      if (error) toast.show('โหลดรายการกลุ่มงานไม่สำเร็จ: ' + (error.message || 'เกิดข้อผิดพลาด'), 'error');
    });
  }, [toast]);

  useEffect(() => {
    fetchLinks();
  }, [fetchLinks]);

  useEffect(() => {
    supabase.from('websites').select('id, name, alias, branch_id').order('name').then(({ data }) => setWebsites((data || []) as WebsiteOption[]));
  }, []);

  const debouncedSearch = useDebouncedValue(searchQuery, 300);
  const filteredLinks = useMemo(() => {
    return links.filter((l) => {
      const linkBranchIds = getLinkBranchIds(l);
      if (branchFilterId && !linkBranchIds.includes(branchFilterId)) return false;
      const linkWebIds = getLinkWebsiteIds(l);
      if (websiteFilter && (linkWebIds.length === 0 || !linkWebIds.includes(websiteFilter))) return false;
      const q = debouncedSearch.trim().toLowerCase();
      if (q && !(l.title || '').toLowerCase().includes(q) && !(l.description || '').toLowerCase().includes(q)) return false;
      return true;
    });
  }, [links, branchFilterId, websiteFilter, debouncedSearch]);

  const canEditLink = (_link: GroupLinkRow) => canEditLinks;

  const saveLink = async () => {
    const urlTrim = form.url.trim();
    if (!urlTrim) {
      setFormError('กรุณากรอก URL (ลิงก์)');
      return;
    }
    setFormError('');
    setLoading(true);
    const branchIds = form.branch_ids.filter(Boolean);
    const branchIdForRow = branchIds[0] || null;
    const visibleRolesVal = (() => { const r = resolveVisibleRoles(form.visible_roles); return r.length ? r : null; })();
    let savedId: string | null = null;
    try {
      if (modal.link?.id) {
        savedId = modal.link.id;
        const { error: updErr } = await supabase.from('group_links').update({
          title: form.title,
          url: form.url || null,
          description: form.description || null,
          branch_id: branchIdForRow,
          website_id: null,
          visible_roles: visibleRolesVal as string[] | null,
        }).eq('id', modal.link.id);
        if (updErr) throw updErr;
        await supabase.from('group_link_websites').delete().eq('group_link_id', modal.link.id);
        await supabase.from('group_link_branches').delete().eq('group_link_id', modal.link.id);
        if (form.website_id) {
          await supabase.from('group_link_websites').insert({ group_link_id: modal.link.id, website_id: form.website_id });
        }
        for (const bid of branchIds) {
          await supabase.from('group_link_branches').insert({ group_link_id: modal.link.id, branch_id: bid });
        }
      } else {
        const createdBy = profile?.id ?? null;
        const { data: inserted, error: insErr } = await supabase.from('group_links').insert({
          title: form.title,
          url: form.url || null,
          description: form.description || null,
          branch_id: branchIdForRow,
          website_id: null,
          visible_roles: visibleRolesVal as string[] | null,
          created_by: createdBy,
        }).select('id').single();
        if (insErr) throw insErr;
        if (inserted?.id) {
          savedId = inserted.id;
          if (form.website_id) {
            await supabase.from('group_link_websites').insert({ group_link_id: inserted.id, website_id: form.website_id });
          }
          for (const bid of branchIds) {
            await supabase.from('group_link_branches').insert({ group_link_id: inserted.id, branch_id: bid });
          }
        }
      }
      setModal({ open: false });
      setFormError('');
      fetchLinks();
      if (savedId) {
        setLastSavedId(savedId);
        toast.show(modal.link ? 'แก้ไขลิงก์แล้ว' : 'เพิ่มลิงก์แล้ว');
      }
    } catch (e: unknown) {
      const msg = e && typeof e === 'object' && 'message' in e ? String((e as { message: string }).message) : 'เกิดข้อผิดพลาด';
      setFormError('บันทึกไม่สำเร็จ: ' + msg);
      toast.show('บันทึกไม่สำเร็จ: ' + msg, 'error');
    } finally {
      setLoading(false);
    }
  };

  const deleteLink = async (id: string) => {
    if (!confirm('ลบลิงก์นี้?')) return;
    await supabase.from('group_links').delete().eq('id', id);
    setLinks((prev) => prev.filter((l) => l.id !== id));
    toast.show('ลบลิงก์แล้ว');
  };

  const copyUrl = (url: string) => {
    navigator.clipboard.writeText(url);
    toast.show('คัดลอกลิงก์แล้ว');
  };

  const openModalForNew = () => {
    setForm({ title: '', url: '', description: '', branch_ids: [], website_id: '', visible_roles: [] });
    setModal({ open: true, link: null });
  };

  const openModalForEdit = (link: GroupLinkRow) => {
    setForm({
      title: link.title || '',
      url: link.url || '',
      description: link.description || '',
      branch_ids: getLinkBranchIds(link),
      website_id: getPrimaryWebsiteId(link) || '',
      visible_roles: toCompactVisibleRoles(link.visible_roles),
    });
    setModal({ open: true, link });
  };

  return (
    <div>
      <div className="flex flex-wrap items-center justify-between gap-4 mb-4">
        <div>
          <h1 className="text-premium-gold text-xl font-semibold">ศูนย์รวมกลุ่มงาน</h1>
          <p className="text-gray-400 text-sm mt-0.5">รวมลิงก์กลุ่มประสานงาน แยกตามเว็บ</p>
        </div>
        {canEditLinks && (
          <Button variant="gold" onClick={openModalForNew}>เพิ่มกลุ่มใหม่</Button>
        )}
      </div>

      {/* Filter: เลือกเว็บ (ปุ่ม) + แผนก + ค้นหา */}
      <div className="rounded-lg border border-premium-gold/20 bg-premium-darker/40 p-3 mb-4">
        <div className="flex flex-wrap items-end gap-3">
          <div className="flex flex-wrap gap-1.5 items-center">
            <span className="text-gray-400 text-sm mr-1">เลือกเว็บ:</span>
            <button
              type="button"
              onClick={() => setWebsiteFilter('')}
              className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${!websiteFilter ? 'bg-premium-gold/20 text-premium-gold border border-premium-gold/40' : 'bg-premium-dark border border-premium-gold/20 text-gray-300 hover:bg-premium-gold/10'}`}
            >
              ทั้งหมด
            </button>
            {websites.map((w) => (
              <button
                key={w.id}
                type="button"
                onClick={() => setWebsiteFilter(websiteFilter === w.id ? '' : w.id)}
                className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${websiteFilter === w.id ? 'bg-premium-gold/20 text-premium-gold border border-premium-gold/40' : 'bg-premium-dark border border-premium-gold/20 text-gray-300 hover:bg-premium-gold/10'}`}
              >
                {w.alias || w.name}
              </button>
            ))}
          </div>
          <div>
            <label className="block text-gray-400 text-xs mb-0.5">แผนก</label>
            <select
              value={branchFilterId}
              onChange={(e) => setBranchFilterId(e.target.value)}
              className="bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white text-sm min-w-[140px]"
            >
              <option value="">ทุกแผนก</option>
              {branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
            </select>
          </div>
          <input
            type="search"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="ค้นหา…"
            className="bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white text-sm w-44 placeholder-gray-500"
          />
          <span className="text-gray-500 text-sm">{filteredLinks.length} รายการ</span>
        </div>
      </div>

      {/* Card grid */}
      <div className="min-h-[200px]">
        {linksLoading ? (
          <div className="flex items-center justify-center py-16 text-gray-400"><span className="animate-pulse">กำลังโหลด...</span></div>
        ) : filteredLinks.length === 0 ? (
          <div className="py-12 text-center text-gray-400 rounded-lg border border-premium-gold/20 bg-premium-darker/30">
            <p className="text-sm">ไม่พบลิงก์กลุ่มตามตัวกรองที่เลือก</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
            {filteredLinks.map((link) => {
              const webId = getPrimaryWebsiteId(link);
              const website = websites.find((w) => w.id === webId);
              const alias = website?.alias || website?.name || '—';
              const linkBranchIds = getLinkBranchIds(link);
              const branchNames = linkBranchIds.length ? linkBranchIds.map((id) => branches.find((b) => b.id === id)?.name).filter(Boolean).join(', ') : null;
              const isNew = lastSavedId === link.id;
              const webColor = getWebsiteColor(webId, websites);
              return (
                <div
                  key={link.id}
                  onClick={link.url ? () => window.open(link.url!, '_blank') : undefined}
                  role={link.url ? 'button' : undefined}
                  className={`rounded-xl border bg-premium-darker/50 overflow-hidden transition-all ${link.url ? 'cursor-pointer hover:opacity-95' : ''} ${isNew ? 'ring-2 ring-premium-gold/50 border-premium-gold/40' : ''}`}
                  style={!isNew ? { borderColor: webColor.border, borderWidth: '1px' } : undefined}
                >
                  <div className="p-4">
                    <div className="flex items-start justify-between gap-2 mb-2">
                      <span className="font-medium text-sm px-2 py-0.5 rounded" style={{ backgroundColor: webColor.bg, color: webColor.text }}>{alias}</span>
                      {canEditLink(link) && (
                        <div className="flex gap-1 shrink-0" onClick={(e) => e.stopPropagation()}>
                          <button type="button" aria-label="แก้ไข" className="p-1.5 rounded text-gray-400 hover:text-premium-gold hover:bg-premium-gold/10" onClick={() => openModalForEdit(link)}>
                            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z" /></svg>
                          </button>
                          <button type="button" aria-label="ลบ" className="p-1.5 rounded text-gray-400 hover:text-red-400 hover:bg-red-500/10" onClick={() => deleteLink(link.id)}>
                            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>
                          </button>
                        </div>
                      )}
                    </div>
                    <h3 className="text-gray-200 font-medium truncate mb-1" title={link.title || ''}>{link.title || '—'}</h3>
                    {branchNames && <p className="text-gray-500 text-xs mb-1">{branchNames}</p>}
                    {(() => { const vr = toCompactVisibleRoles(link.visible_roles); return vr.length ? <p className="text-gray-500 text-xs mb-3">ตำแหน่งที่เห็น: {vr.map(getRoleLabel).join(', ')}</p> : <span className="block mb-3" />; })()}
                    <div className="flex flex-wrap gap-2" onClick={(e) => e.stopPropagation()}>
                      {link.url && (
                        <>
                          <a href={link.url} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-premium-gold/15 text-premium-gold hover:bg-premium-gold/25 text-sm font-medium">
                            เข้าร่วม
                          </a>
                          <button type="button" onClick={() => copyUrl(link.url!)} className="p-1.5 rounded-lg border border-premium-gold/30 text-gray-400 hover:text-premium-gold hover:bg-premium-gold/10" aria-label="คัดลอกลิงก์">
                            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h2m2 4h10a2 2 0 012 2v2m-4 4v6a2 2 0 01-2 2h-8a2 2 0 01-2-2v-8a2 2 0 012-2h2" /></svg>
                          </button>
                        </>
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      <PageModal open={modal.open} onClose={() => { setModal({ open: false }); setFormError(''); }} title={modal.link ? 'แก้ไขลิงก์' : 'เพิ่มลิงก์ใหม่'} onCancel={() => setModal({ open: false })} onSave={saveLink} saveLoading={loading} saveLabel="บันทึกข้อมูล">
        <div className="space-y-4">
          {formError && <p className="text-red-400 text-sm">{formError}</p>}
          <div>
            <label className="block text-gray-400 text-sm mb-1">ชื่อกลุ่ม / ช่อง</label>
            <input value={form.title} onChange={(e) => setForm((f) => ({ ...f, title: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white" placeholder="เช่น กลุ่มแจ้งถอน, บอทสลิป..." />
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-gray-400 text-sm mb-1">เว็บ/ทีม</label>
              <select value={form.website_id} onChange={(e) => setForm((f) => ({ ...f, website_id: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white">
                <option value="">— เลือกเว็บ —</option>
                {websites.map((w) => <option key={w.id} value={w.id}>{w.name} ({w.alias})</option>)}
              </select>
            </div>
            <div>
              <MultiSelect
                label="แผนก"
                options={branches.map((b) => ({ id: b.id, label: b.name }))}
                value={form.branch_ids}
                onChange={(branch_ids) => setForm((f) => ({ ...f, branch_ids }))}
                placeholder="เลือกแผนก (ได้หลายแผนก)"
                showChips
                searchable
              />
            </div>
          </div>
          <div>
            <label className="block text-gray-400 text-sm mb-1">ลิงก์ (URL) <span className="text-red-400">*</span></label>
            <input type="url" value={form.url} onChange={(e) => { setForm((f) => ({ ...f, url: e.target.value })); setFormError(''); }} className={`w-full bg-premium-dark rounded-lg px-3 py-2 text-white ${formError ? 'border border-red-400' : 'border border-premium-gold/30'}`} placeholder="https://t.me/..." />
            {formError && <p className="text-red-400 text-xs mt-1">{formError}</p>}
          </div>
          <div>
            <label className="block text-gray-400 text-sm mb-1">คำอธิบาย (ไม่บังคับ)</label>
            <textarea value={form.description} onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white" rows={2} placeholder="คำอธิบายเพิ่มเติม" />
          </div>
          <div>
            <MultiSelect
              label="ตำแหน่งที่เห็นได้"
              options={ROLE_OPTIONS.map((r) => ({ id: r.value, label: r.label }))}
              value={form.visible_roles}
              onChange={(visible_roles) => setForm((f) => ({ ...f, visible_roles }))}
              placeholder="ไม่เลือก = ทุกตำแหน่ง"
              showChips
              searchable
            />
          </div>
        </div>
      </PageModal>
    </div>
  );
}
