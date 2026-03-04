import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';
import { useDebouncedValue } from '../lib/useDebouncedValue';
import { useAuth } from '../lib/auth';
import { useBranchesShifts } from '../lib/BranchesShiftsContext';
import { useToast } from '../lib/ToastContext';
import type { ThirdPartyProviderRow } from '../lib/types';
import { ROLE_OPTIONS, resolveVisibleRoles, toCompactVisibleRoles } from '../lib/roleOptions';
import Button from '../components/ui/Button';
import PageModal from '../components/ui/PageModal';
import MultiSelect from '../components/ui/MultiSelect';
import PaginationBar from '../components/ui/PaginationBar';
import { BtnEdit, BtnDelete } from '../components/ui/ActionIcons';

/** คอลัมน์ที่ใช้แสดง/กรองในหน้านี้เท่านั้น — ลด payload */
const THIRD_PARTY_SELECT = 'id,provider_name,provider_code,logo_url,merchant_id,link_url,branch_id,website_id,visible_roles,sort_order,created_at';

const roleOptionsForSelect = ROLE_OPTIONS.map((r) => ({ id: r.value, label: r.label }));

export default function ThirdPartyProviders() {
  const { profile } = useAuth();
  const { branches } = useBranchesShifts();
  const toast = useToast();
  const isAdmin = profile?.role === 'admin';
  const isManager = profile?.role === 'manager';
  const isHead = profile?.role === 'instructor_head';
  const canEdit = isAdmin || isManager || isHead;

  const [selectedWebsiteId, setSelectedWebsiteId] = useState('');
  const [rows, setRows] = useState<ThirdPartyProviderRow[]>([]);
  const [websites, setWebsites] = useState<{ id: string; name: string; alias: string }[]>([]);
  const [search, setSearch] = useState('');
  const [branchFilterId, setBranchFilterId] = useState('');
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(20);
  const [totalCount, setTotalCount] = useState(0);
  const [modal, setModal] = useState<{ open: boolean; row?: ThirdPartyProviderRow | null }>({ open: false });
  const [formError, setFormError] = useState('');
  const [loading, setLoading] = useState(false);
  const [rowsLoading, setRowsLoading] = useState(false);
  const [lastSavedId, setLastSavedId] = useState<string | null>(null);

  const [form, setForm] = useState({
    provider_name: '',
    provider_code: '',
    logo_url: '',
    merchant_id: '',
    link_url: '',
    branch_id: '',
    branch_ids: [] as string[],
    website_id: '',
    visible_roles: [] as string[],
  });

  const requestIdRef = useRef(0);
  const cancelledRef = useRef(false);

  const debouncedSearch = useDebouncedValue(search, 300);

  const fetchRows = useCallback(
    async (websiteId: string) => {
      if (!websiteId) {
        setRows([]);
        setTotalCount(0);
        setRowsLoading(false);
        return;
      }
      const myId = ++requestIdRef.current;
      setRowsLoading(true);
      try {
        let q = supabase
          .from('third_party_providers')
          .select(THIRD_PARTY_SELECT, { count: 'exact' })
          .eq('website_id', websiteId)
          .order('sort_order', { ascending: true })
          .order('created_at', { ascending: false });
        if (branchFilterId) q = q.eq('branch_id', branchFilterId);
        const searchTrim = debouncedSearch.trim();
        if (searchTrim) {
          const esc = searchTrim.replace(/'/g, "''");
          q = q.or(`provider_name.ilike.%${esc}%,provider_code.ilike.%${esc}%,merchant_id.ilike.%${esc}%`);
        }
        const from = (page - 1) * pageSize;
        const { data, error, count } = await q.range(from, from + pageSize - 1);
        if (myId !== requestIdRef.current) return;
        if (error) {
          toast.show('โหลดรายการบุคคลที่สามไม่สำเร็จ: ' + (error.message || 'เกิดข้อผิดพลาด'), 'error');
          setRows([]);
          setTotalCount(0);
          return;
        }
        setRows((data || []) as ThirdPartyProviderRow[]);
        setTotalCount(typeof count === 'number' ? count : 0);
      } finally {
        if (requestIdRef.current === myId) setRowsLoading(false);
      }
    },
    [branchFilterId, debouncedSearch, page, pageSize, toast]
  );

  useEffect(() => {
    setPage(1);
  }, [selectedWebsiteId, branchFilterId, debouncedSearch]);

  useEffect(() => {
    if (!selectedWebsiteId) {
      setRows([]);
      setTotalCount(0);
      setRowsLoading(false);
      return;
    }
    cancelledRef.current = false;
    fetchRows(selectedWebsiteId);
    return () => {
      cancelledRef.current = true;
    };
  }, [selectedWebsiteId, fetchRows]);

  useEffect(() => {
    let cancelled = false;
    supabase
      .from('websites')
      .select('id, name, alias')
      .order('name')
      .then(({ data }) => {
        if (!cancelled) setWebsites((data || []) as { id: string; name: string; alias: string }[]);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const openModalForNew = () => {
    setForm({
      provider_name: '',
      provider_code: '',
      logo_url: '',
      merchant_id: '',
      link_url: '',
      branch_id: '',
      branch_ids: [],
      website_id: selectedWebsiteId,
      visible_roles: [],
    });
    setFormError('');
    setModal({ open: true, row: null });
  };

  const openModalForEdit = (row: ThirdPartyProviderRow) => {
    setForm({
      provider_name: row.provider_name || '',
      provider_code: row.provider_code || '',
      logo_url: row.logo_url || '',
      merchant_id: row.merchant_id || '',
      link_url: row.link_url || '',
      branch_id: row.branch_id || '',
      branch_ids: [],
      website_id: row.website_id || '',
      visible_roles: toCompactVisibleRoles(row.visible_roles),
    });
    setFormError('');
    setModal({ open: true, row });
  };

  const saveProvider = async () => {
    const nameTrim = form.provider_name.trim();
    if (!nameTrim) {
      setFormError('กรุณากรอกชื่อ Provider');
      return;
    }
    setFormError('');
    setLoading(true);
    const visibleRolesVal = (() => {
      const r = resolveVisibleRoles(form.visible_roles);
      return r.length ? r : null;
    })();
    const websiteIdForSave = modal.row ? modal.row.website_id : selectedWebsiteId;
    if (!websiteIdForSave) {
      setFormError('กรุณาเลือกเว็บก่อนเพิ่ม Provider');
      setLoading(false);
      return;
    }
    const basePayload = {
      provider_name: nameTrim,
      provider_code: form.provider_code.trim() || null,
      logo_url: form.logo_url.trim() || null,
      merchant_id: form.merchant_id.trim() || null,
      link_url: form.link_url.trim() || null,
      website_id: websiteIdForSave,
      visible_roles: visibleRolesVal as string[] | null,
    };
    try {
      if (modal.row?.id) {
        const payload = { ...basePayload, branch_id: form.branch_id || null };
        await supabase.from('third_party_providers').update(payload).eq('id', modal.row.id);
        toast.show('แก้ไขแล้ว');
        setLastSavedId(modal.row.id);
      } else {
        const branchIds = form.branch_ids?.filter(Boolean) ?? [];
        const toInsert = branchIds.length > 0 ? branchIds : [null];
        let lastId: string | null = null;
        for (const bid of toInsert) {
          const { data } = await supabase.from('third_party_providers').insert({ ...basePayload, branch_id: bid }).select('id').single();
          if (data?.id) lastId = data.id;
        }
        if (lastId) setLastSavedId(lastId);
        toast.show(branchIds.length > 1 ? `เพิ่ม Provider แล้ว (${branchIds.length} แผนก)` : 'เพิ่ม Provider แล้ว');
      }
      setModal({ open: false });
      setPage(1);
      fetchRows(selectedWebsiteId);
    } catch (e: unknown) {
      const msg = e && typeof e === 'object' && 'message' in e ? String((e as { message: string }).message) : 'เกิดข้อผิดพลาด';
      setFormError('บันทึกไม่สำเร็จ: ' + msg);
      toast.show('บันทึกไม่สำเร็จ: ' + msg, 'error');
    } finally {
      setLoading(false);
    }
  };

  const deleteProvider = async (id: string) => {
    if (!confirm('ลบรายการนี้?')) return;
    const { error } = await supabase.from('third_party_providers').delete().eq('id', id);
    if (error) {
      toast.show('ลบไม่สำเร็จ: ' + error.message, 'error');
      return;
    }
    toast.show('ลบแล้ว');
    fetchRows(selectedWebsiteId);
  };

  const hasWebsiteSelected = Boolean(selectedWebsiteId);

  return (
    <div>
      <div className="flex flex-wrap items-center justify-between gap-4 mb-4">
        <div>
          <h1 className="text-premium-gold text-xl font-semibold">บุคคลที่สาม (3rd Party)</h1>
          <p className="text-gray-400 text-sm mt-0.5">จัดการ Provider และลิงก์เข้าสู่ระบบ — เลือกเว็บก่อน</p>
        </div>
        {canEdit && hasWebsiteSelected && (
          <Button variant="gold" onClick={openModalForNew}>เพิ่ม Provider</Button>
        )}
      </div>

      {/* บังคับเลือกเว็บก่อน */}
      <div className="rounded-lg border border-premium-gold/20 bg-premium-darker/40 p-3 mb-4">
        <div className="flex flex-wrap items-end gap-3">
          <div className="flex-1 min-w-[200px]">
            <label className="block text-gray-400 text-xs mb-0.5">เลือกเว็บ *</label>
            <select
              value={selectedWebsiteId}
              onChange={(e) => setSelectedWebsiteId(e.target.value)}
              className="w-full bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white text-sm"
            >
              <option value="">— กรุณาเลือกเว็บ —</option>
              {websites.map((w) => (
                <option key={w.id} value={w.id}>{w.name} ({w.alias})</option>
              ))}
            </select>
          </div>
          {hasWebsiteSelected && (
            <>
              <input
                type="search"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="ค้นหา Provider…"
                className="bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white text-sm w-48 placeholder-gray-500"
              />
              <div>
                <label className="block text-gray-400 text-xs mb-0.5">แผนก</label>
                <select
                  value={branchFilterId}
                  onChange={(e) => setBranchFilterId(e.target.value)}
                  className="bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white text-sm min-w-[120px]"
                >
                  <option value="">ทุกแผนก</option>
                  {branches.map((b) => (
                    <option key={b.id} value={b.id}>{b.name}</option>
                  ))}
                </select>
              </div>
              <span className="text-gray-500 text-sm">{totalCount.toLocaleString()} รายการ</span>
            </>
          )}
        </div>
      </div>

      {/* Empty state: ยังไม่เลือกเว็บ */}
      {!hasWebsiteSelected && (
        <div className="rounded-lg border border-premium-gold/20 bg-premium-darker/30 py-12 text-center">
          <p className="text-premium-gold/90 font-medium">กรุณาเลือกเว็บก่อน</p>
          <p className="text-gray-400 text-sm mt-1">เลือกเว็บจาก dropdown ด้านบน เพื่อดูและจัดการ Provider ของเว็บนั้น</p>
        </div>
      )}

      {/* Table — แสดงเฉพาะเมื่อเลือกเว็บแล้ว */}
      {hasWebsiteSelected && (
      <div className="rounded-lg border border-premium-gold/20 overflow-hidden bg-premium-darker/30">
        {rowsLoading ? (
          <div className="flex justify-center py-16 text-gray-400"><span className="animate-pulse">กำลังโหลด...</span></div>
        ) : rows.length === 0 ? (
          <div className="py-12 text-center text-gray-400">ไม่พบรายการตามตัวกรอง</div>
        ) : (
          <>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="sticky top-0 z-10 border-b border-premium-gold/20 bg-premium-darker/80">
                <tr>
                  <th className="text-left py-3 px-3 text-premium-gold font-medium">THIRD PARTY</th>
                  <th className="text-left py-3 px-3 text-premium-gold font-medium">MERCHANT ID</th>
                  <th className="text-left py-3 px-3 text-premium-gold font-medium w-24">LINK</th>
                  {canEdit && <th className="text-left py-3 px-3 text-premium-gold font-medium w-24">การดำเนินการ</th>}
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => {
                  const isNew = lastSavedId === r.id;
                  return (
                    <tr
                      key={r.id}
                      className={`border-b border-premium-gold/10 transition-colors hover:bg-[#FFD700]/5 ${isNew ? 'bg-premium-gold/10' : ''}`}
                    >
                      <td className="py-3 px-3">
                        <div className="flex items-center gap-3">
                          <div className="w-10 h-10 rounded-lg border border-premium-gold/20 bg-premium-dark/60 flex items-center justify-center shrink-0 overflow-hidden">
                            {r.logo_url ? (
                              <img src={r.logo_url} alt="" className="w-full h-full object-contain" onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; (e.target as HTMLImageElement).nextElementSibling?.classList.remove('hidden'); }} />
                            ) : null}
                            <span className={`w-full h-full flex items-center justify-center text-premium-gold/60 text-lg ${r.logo_url ? 'hidden' : ''}`} aria-hidden>◇</span>
                          </div>
                          <div className="min-w-0">
                            <span className="font-semibold text-gray-200 block truncate">{r.provider_name}</span>
                            {r.provider_code && <span className="text-gray-500 text-xs block truncate">{r.provider_code}</span>}
                          </div>
                        </div>
                      </td>
                      <td className="py-3 px-3 text-gray-300">{r.merchant_id || '—'}</td>
                      <td className="py-3 px-3">
                        {r.link_url ? (
                          <button
                            type="button"
                            onClick={() => window.open(r.link_url!, '_blank')}
                            className="px-2 py-1 rounded bg-blue-500/20 text-blue-300 hover:bg-blue-500/30 text-xs"
                          >
                            เข้าสู่ระบบ
                          </button>
                        ) : (
                          '—'
                        )}
                      </td>
                      {canEdit && (
                        <td className="py-3 px-3">
                          <div className="flex items-center gap-0.5">
                            <BtnEdit onClick={() => openModalForEdit(r)} title="แก้ไข" />
                            <BtnDelete onClick={() => deleteProvider(r.id)} title="ลบ" />
                          </div>
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          <PaginationBar
            page={page}
            pageSize={pageSize}
            totalCount={totalCount}
            onPageChange={setPage}
            onPageSizeChange={(n) => { setPageSize(n); setPage(1); }}
            pageSizeOptions={[10, 20, 50]}
            itemLabel="รายการ"
          />
          </>
        )}
      </div>
      )}

      <PageModal open={modal.open} onClose={() => setModal({ open: false })} title={modal.row ? 'แก้ไข Provider' : 'เพิ่ม Provider'} onCancel={() => setModal({ open: false })} onSave={saveProvider} saveLoading={loading} saveLabel="บันทึก">
        <div className="space-y-4 okace-scroll max-h-[60vh] overflow-y-auto pr-2">
          {formError && <p className="text-red-400 text-sm">{formError}</p>}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-gray-400 text-sm mb-1">ชื่อ Provider *</label>
              <input value={form.provider_name} onChange={(e) => setForm((f) => ({ ...f, provider_name: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white" placeholder="เช่น RCPAY, 88OKPay" />
            </div>
            <div>
              <label className="block text-gray-400 text-sm mb-1">โค้ดย่อ</label>
              <input value={form.provider_code} onChange={(e) => setForm((f) => ({ ...f, provider_code: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white" placeholder="optional" />
            </div>
          </div>
          <div>
            <label className="block text-gray-400 text-sm mb-1">URL โลโก้</label>
            <div className="flex flex-wrap items-start gap-4">
              <div className="w-20 h-20 rounded-xl border border-premium-gold/30 bg-premium-dark/80 flex items-center justify-center overflow-hidden shrink-0 ring-1 ring-inset ring-premium-gold/10">
                {form.logo_url ? (
                  <>
                    <img src={form.logo_url} alt="" className="w-full h-full object-contain" onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; (e.target as HTMLImageElement).nextElementSibling?.classList.remove('hidden'); }} />
                    <span className="hidden w-full h-full flex items-center justify-center text-premium-gold/50 text-2xl" aria-hidden>◇</span>
                  </>
                ) : (
                  <span className="text-premium-gold/40 text-2xl" aria-hidden>◇</span>
                )}
              </div>
              <div className="flex-1 min-w-0">
                <input value={form.logo_url} onChange={(e) => setForm((f) => ({ ...f, logo_url: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white" placeholder="https://..." />
                <p className="text-gray-500 text-xs mt-1">ใส่ URL รูปโลโก้ Provider จะแสดงในตาราง</p>
              </div>
            </div>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-gray-400 text-sm mb-1">Merchant ID</label>
              <input value={form.merchant_id} onChange={(e) => setForm((f) => ({ ...f, merchant_id: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white" />
            </div>
            <div>
              <label className="block text-gray-400 text-sm mb-1">ลิงก์เข้าสู่ระบบ</label>
              <input value={form.link_url} onChange={(e) => setForm((f) => ({ ...f, link_url: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white" placeholder="https://..." />
            </div>
          </div>
          <div>
            <label className="block text-gray-400 text-sm mb-1">เว็บ</label>
            <div className="rounded-lg border border-premium-gold/20 bg-premium-dark/50 px-3 py-2 text-gray-300 text-sm">
              {(() => {
                const w = websites.find((x) => x.id === form.website_id);
                return w ? `${w.name} (${w.alias})` : (form.website_id ? '—' : '— เลือกเว็บด้านบนก่อน —');
              })()}
            </div>
          </div>
          {modal.row ? (
            <div>
              <label className="block text-gray-400 text-sm mb-1">แผนก</label>
              <select value={form.branch_id} onChange={(e) => setForm((f) => ({ ...f, branch_id: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white">
                <option value="">— ไม่ระบุ —</option>
                {branches.map((b) => (
                  <option key={b.id} value={b.id}>{b.name}</option>
                ))}
              </select>
            </div>
          ) : (
            <div>
              <MultiSelect
                label="แผนก (เลือกได้หลายแผนก)"
                options={branches.map((b) => ({ id: b.id, label: b.name }))}
                value={form.branch_ids}
                onChange={(branch_ids) => setForm((f) => ({ ...f, branch_ids }))}
                placeholder="เลือกแผนก — ไม่เลือก = ใช้ทุกแผนก"
                showChips
                searchable
              />
            </div>
          )}
          <div>
            <MultiSelect
              label="ตำแหน่งที่เห็นได้"
              options={roleOptionsForSelect}
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
