import { useState, useEffect, useCallback, useRef } from 'react';
import { format } from 'date-fns';
import { useDebouncedValue } from '../lib/useDebouncedValue';
import { th } from 'date-fns/locale';
import { supabase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import { useBranchesShifts } from '../lib/BranchesShiftsContext';
import { useToast } from '../lib/ToastContext';
import { ROLE_OPTIONS, getRoleLabel, resolveVisibleRoles, toCompactVisibleRoles } from '../lib/roleOptions';
import Button from '../components/ui/Button';
import PageModal from '../components/ui/PageModal';
import MultiSelect from '../components/ui/MultiSelect';
import { BtnDownload, BtnEdit, BtnDelete } from '../components/ui/ActionIcons';
import PaginationBar from '../components/ui/PaginationBar';

const BUCKET = 'vault';
const BRANCH_ALL = '__all__';
const DEFAULT_PAGE_SIZE = 10;
const PAGE_SIZE_OPTIONS = [10, 20, 50];

type FileVaultRow = {
  id: string;
  branch_id: string | null;
  website_id: string | null;
  file_path: string;
  file_name: string;
  topic: string | null;
  visible_roles: string[] | null;
  uploaded_by: string | null;
  created_at: string;
};

const ALLOWED_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.zip', '.pdf', '.xlsx', '.xls', '.doc', '.docx', '.txt', '.csv'];
const ACCEPT = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'application/zip', 'application/x-zip-compressed', 'application/pdf', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/vnd.ms-excel', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'text/plain', 'text/csv'].join(',');

function hasAllowedExtension(name: string): boolean {
  return ALLOWED_EXTENSIONS.some((ext) => name.toLowerCase().endsWith(ext));
}

function getFileExtension(name: string): string {
  const i = name.lastIndexOf('.');
  return i >= 0 ? name.slice(i).toLowerCase() : '';
}

const ICON_SIZE = 20;

/** ไอคอนตามนามสกุลไฟล์ — ใช้ในตารางคลังเก็บไฟล์ */
function FileTypeIcon({ fileName, className = '' }: { fileName: string; className?: string }) {
  const ext = getFileExtension(fileName);
  const c = className || 'text-premium-gold/80 flex-shrink-0';
  const common = { width: ICON_SIZE, height: ICON_SIZE, className: c, 'aria-hidden': true as const };

  if (['.zip'].includes(ext)) {
    return (
      <svg {...common} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M21 8V6a2 2 0 00-2-2H5a2 2 0 00-2 2v2m18 0v10a2 2 0 01-2 2H5a2 2 0 01-2-2V8m18 0H3m0 0h4m14 0H7m0 0v10" />
      </svg>
    );
  }
  if (['.pdf'].includes(ext)) {
    return (
      <svg {...common} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z" />
        <path d="M14 2v6h6M9 13h6M9 17h6" />
      </svg>
    );
  }
  if (['.xlsx', '.xls', '.csv'].includes(ext)) {
    return (
      <svg {...common} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M3 3h18v18H3zM3 9h18M3 15h18M9 3v18M15 3v18" />
      </svg>
    );
  }
  if (['.doc', '.docx', '.txt'].includes(ext)) {
    return (
      <svg {...common} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z" />
        <path d="M14 2v6h6M16 13H8M16 17H8M10 9H8" />
      </svg>
    );
  }
  if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].includes(ext)) {
    return (
      <svg {...common} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <rect x="3" y="3" width="18" height="18" rx="2" />
        <circle cx="8.5" cy="8.5" r="1.5" />
        <path d="M21 15l-5-5L5 21" />
      </svg>
    );
  }
  return (
    <svg {...common} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z" />
      <path d="M14 2v6h6" />
    </svg>
  );
}

export default function PhotoVault() {
  const { profile } = useAuth();
  const { branches } = useBranchesShifts();
  const toast = useToast();
  const isAdmin = profile?.role === 'admin';
  const isManager = profile?.role === 'manager';
  const isHead = profile?.role === 'instructor_head';
  const canEdit = isAdmin || isManager || isHead;

  const [branchFilterId, setBranchFilterId] = useState<string>('');
  const [websiteId, setWebsiteId] = useState<string>('');
  const [websites, setWebsites] = useState<{ id: string; name: string }[]>([]);
  const [files, setFiles] = useState<FileVaultRow[]>([]);
  const [creatorNames, setCreatorNames] = useState<Record<string, string>>({});
  const [search, setSearch] = useState('');
  const [roleFilter, setRoleFilter] = useState('');
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(DEFAULT_PAGE_SIZE);
  const [totalCount, setTotalCount] = useState(0);
  const [filesLoading, setFilesLoading] = useState(false);
  const requestIdRef = useRef(0);
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState('');
  const [editId, setEditId] = useState<string | null>(null);
  const [editTopic, setEditTopic] = useState('');
  const [uploadModal, setUploadModal] = useState(false);
  const [lastSavedId, setLastSavedId] = useState<string | null>(null);
  const WEBSITE_ALL = '';
  const [uploadForm, setUploadForm] = useState({
    uploadBranches: [] as string[],
    uploadWebsites: [] as string[],
    visible_roles: [] as string[],
    topic: '',
    files: null as FileList | null,
  });

  useEffect(() => {
    supabase.from('websites').select('id, name').order('name').then(({ data }) => setWebsites((data || []) as { id: string; name: string }[]));
  }, []);

  const debouncedSearch = useDebouncedValue(search, 300);

  const fetchFiles = useCallback(async () => {
    const myId = ++requestIdRef.current;
    setFilesLoading(true);
    try {
      let q = supabase
        .from('file_vault')
        .select('id, branch_id, website_id, file_path, file_name, topic, visible_roles, uploaded_by, created_at', { count: 'exact' })
        .order('created_at', { ascending: false });
      if (branchFilterId) q = q.eq('branch_id', branchFilterId);
      if (websiteId) q = q.eq('website_id', websiteId);
      const searchTrim = debouncedSearch.trim();
      if (searchTrim) {
        const esc = searchTrim.replace(/'/g, "''");
        q = q.or(`file_name.ilike.%${esc}%,topic.ilike.%${esc}%`);
      }
      if (roleFilter) {
        const safe = roleFilter.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
        q = q.or(`visible_roles.is.null,visible_roles.cs.{"${safe}"}`);
      }
      const from = (page - 1) * pageSize;
      const { data, error, count } = await q.range(from, from + pageSize - 1);
      if (myId !== requestIdRef.current) return;
      if (error) {
        setFiles([]);
        setTotalCount(0);
        return;
      }
      setFiles((data || []) as FileVaultRow[]);
      setTotalCount(typeof count === 'number' ? count : 0);
    } finally {
      if (requestIdRef.current === myId) setFilesLoading(false);
    }
  }, [branchFilterId, websiteId, debouncedSearch, roleFilter, page, pageSize]);

  useEffect(() => {
    fetchFiles();
  }, [fetchFiles]);

  useEffect(() => {
    setPage(1);
  }, [debouncedSearch, roleFilter, branchFilterId, websiteId]);

  useEffect(() => {
    const ids = [...new Set(files.map((f) => f.uploaded_by).filter(Boolean))] as string[];
    if (ids.length === 0) {
      setCreatorNames({});
      return;
    }
    supabase.from('profiles').select('id, display_name, email').in('id', ids).then(({ data }) => {
      const map: Record<string, string> = {};
      (data || []).forEach((p: { id: string; display_name: string | null; email: string | null }) => {
        map[p.id] = p.display_name?.trim() || p.email || '—';
      });
      setCreatorNames(map);
    });
  }, [files]);

  const submitUpload = async () => {
    const { uploadBranches, uploadWebsites, visible_roles, topic, files: fileList } = uploadForm;
    if (!fileList?.length || !canEdit) return;
    const useBranchAll = uploadBranches.length === 0 || uploadBranches.includes(BRANCH_ALL);
    const useWebsiteAll = uploadWebsites.length === 0 || uploadWebsites.includes(WEBSITE_ALL);
    if (!useBranchAll && uploadBranches.length === 0) {
      setUploadError('กรุณาเลือกแผนกหรือทุกแผนก');
      return;
    }
    const invalid = Array.from(fileList).filter((f) => !hasAllowedExtension(f.name));
    if (invalid.length) {
      setUploadError(`รองรับเฉพาะ: ${ALLOWED_EXTENSIONS.join(', ')}`);
      return;
    }
    setUploadError('');
    setUploading(true);
    const branchesForInsert: (string | null)[] = useBranchAll ? [null] : uploadBranches.filter((id) => id !== BRANCH_ALL);
    const websitesForInsert: (string | null)[] = useWebsiteAll ? [null] : uploadWebsites.filter((id) => id !== WEBSITE_ALL);
    const userId = (await supabase.auth.getUser()).data.user?.id ?? null;
    const rolesVal = (() => { const r = resolveVisibleRoles(visible_roles); return r.length ? r : null; })();
    const prefix = 'branch-all/website-all/';
    const insertedIds: string[] = [];
    for (let i = 0; i < fileList.length; i++) {
      const file = fileList[i];
      const safeName = `${crypto.randomUUID()}-${file.name.replace(/[^\w.\-ก-๙]/g, '_')}`;
      const path = prefix + safeName;
      const { error: upErr } = await supabase.storage.from(BUCKET).upload(path, file, { upsert: true });
      if (upErr) {
        setUploadError(`Storage: ${file.name} — ${upErr.message}`);
        setUploading(false);
        return;
      }
      for (const b of branchesForInsert) {
        for (const w of websitesForInsert) {
          const { data: ins, error: insErr } = await supabase.from('file_vault').insert({
            branch_id: b,
            website_id: w,
            visible_roles: rolesVal,
            file_path: path,
            file_name: file.name,
            topic: topic.trim() || null,
            uploaded_by: userId,
          }).select('id').single();
          if (insErr) {
            setUploadError(`บันทึก: ${file.name} — ${insErr.message}`);
            setUploading(false);
            return;
          }
          if (ins?.id) insertedIds.push(ins.id);
        }
      }
    }
    setUploading(false);
    setUploadModal(false);
    setUploadForm((f) => ({ ...f, files: null, topic: '' }));
    if (insertedIds[0]) setLastSavedId(insertedIds[0]);
    toast.show('อัปโหลดไฟล์แล้ว');
    setPage(1);
    fetchFiles();
  };

  const handleUpdateTopic = async (id: string) => {
    const { error } = await supabase.from('file_vault').update({ topic: editTopic.trim() || null }).eq('id', id);
    if (!error) {
      setFiles((prev) => prev.map((f) => (f.id === id ? { ...f, topic: editTopic.trim() || null } : f)));
      setEditId(null);
      setEditTopic('');
      toast.show('บันทึกหัวข้อแล้ว');
    }
  };

  const handleDelete = async (row: FileVaultRow) => {
    if (!canEdit || !confirm(`ลบไฟล์ "${row.file_name}"?`)) return;
    await supabase.storage.from(BUCKET).remove([row.file_path]);
    await supabase.from('file_vault').delete().eq('id', row.id);
    toast.show('ลบไฟล์แล้ว');
    fetchFiles();
  };

  const downloadOne = (path: string, name: string) => {
    supabase.storage.from(BUCKET).download(path).then(({ data }) => {
      if (!data) return;
      const a = document.createElement('a');
      a.href = URL.createObjectURL(data);
      a.download = name;
      a.click();
      URL.revokeObjectURL(a.href);
    });
  };

  const branchOptions = branches.map((b) => ({ id: b.id, label: b.name }));
  const websiteOptions = websites.map((w) => ({ id: w.id, label: w.name }));
  const roleOptionsForSelect = ROLE_OPTIONS.map((r) => ({ id: r.value, label: r.label }));

  return (
    <div>
      <h1 className="text-premium-gold text-xl font-semibold mb-4">คลังเก็บไฟล์</h1>

      {/* Filter bar */}
      <div className="rounded-lg border border-premium-gold/20 bg-premium-darker/40 p-3 mb-4">
        <div className="flex flex-wrap items-end gap-3">
          <input type="text" placeholder="ค้นหา…" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1); }} className="bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white text-sm w-44 placeholder-gray-500" />
          <div>
            <label className="block text-gray-400 text-xs mb-0.5">แผนก</label>
            <select value={branchFilterId} onChange={(e) => { setBranchFilterId(e.target.value); setPage(1); }} className="bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white text-sm min-w-[140px]">
              <option value="">ทั้งหมด</option>
              {branches.map((b) => (
                <option key={b.id} value={b.id}>{b.name}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-gray-400 text-xs mb-0.5">เว็บ</label>
            <select value={websiteId} onChange={(e) => { setWebsiteId(e.target.value); setPage(1); }} className="bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white text-sm min-w-[140px]">
              <option value="">ทั้งหมด</option>
              {websites.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
            </select>
          </div>
          {(isAdmin || isManager || isHead) && (
            <div>
              <label className="block text-gray-400 text-xs mb-0.5">ตำแหน่ง</label>
              <select value={roleFilter} onChange={(e) => { setRoleFilter(e.target.value); setPage(1); }} className="bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white text-sm min-w-[120px]">
                <option value="">ทั้งหมด</option>
                {ROLE_OPTIONS.map((r) => <option key={r.value} value={r.value}>{r.label}</option>)}
              </select>
            </div>
          )}
          <span className="text-gray-500 text-sm">{totalCount.toLocaleString()} รายการ</span>
          {canEdit && <Button variant="gold" className="ml-auto" onClick={() => { setUploadForm((f) => ({ ...f, uploadBranches: branchFilterId ? [branchFilterId] : f.uploadBranches })); setUploadModal(true); }}>อัปโหลด</Button>}
        </div>
      </div>
      {uploadError && <p className="text-red-400 text-sm mb-2" role="alert">{uploadError}</p>}

      {/* Table */}
      <div className="rounded-lg border border-premium-gold/20 overflow-hidden bg-premium-darker/30">
        {filesLoading && <div className="py-4 text-center text-gray-400 text-sm">กำลังโหลด...</div>}
        {!filesLoading && files.length === 0 ? (
          <div className="py-12 text-center text-gray-400">ไม่มีไฟล์ตามตัวกรอง</div>
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="w-full text-base">
                <thead>
                  <tr className="border-b border-premium-gold/20 bg-premium-darker/50">
                    <th className="text-left py-4 px-3 text-premium-gold font-medium">ชื่อ / หัวข้อ</th>
                    <th className="text-left py-4 px-3 text-premium-gold font-medium">แผนก</th>
                    <th className="text-left py-4 px-3 text-premium-gold font-medium">เว็บ</th>
                    <th className="text-left py-4 px-3 text-premium-gold font-medium">ตำแหน่งที่เห็น</th>
                    <th className="text-left py-4 px-3 text-premium-gold font-medium">วันที่</th>
                    <th className="text-left py-4 px-3 text-premium-gold font-medium">ผู้สร้าง</th>
                    <th className="text-left py-4 px-3 text-premium-gold font-medium w-32">การดำเนินการ</th>
                  </tr>
                </thead>
                <tbody>
                  {files.map((f) => {
                    const editing = editId === f.id;
                    return (
                      <tr key={f.id} className={`border-b border-premium-gold/10 hover:bg-premium-gold/5 ${lastSavedId === f.id ? 'bg-premium-gold/15 ring-1 ring-inset ring-premium-gold/40' : ''}`}>
                        <td className="py-4 px-3">
                          <div className="flex items-center gap-2 min-w-0">
                            <FileTypeIcon fileName={f.file_name} />
                            <div className="min-w-0 flex-1">
                              {f.topic && <span className="text-premium-gold/90 block text-sm">{f.topic}</span>}
                              <span className="text-gray-200 truncate block max-w-[200px]" title={f.file_name}>{f.file_name}</span>
                            </div>
                          </div>
                        </td>
                        <td className="py-4 px-3 text-gray-400">{f.branch_id ? branches.find((b) => b.id === f.branch_id)?.name ?? '—' : 'ทุกแผนก'}</td>
                        <td className="py-4 px-3 text-gray-400">{f.website_id ? websites.find((w) => w.id === f.website_id)?.name ?? '—' : '—'}</td>
                        <td className="py-4 px-3 text-gray-400">{(() => { const vr = toCompactVisibleRoles(f.visible_roles); return vr.length ? vr.map(getRoleLabel).join(', ') : 'ทุกตำแหน่ง'; })()}</td>
                        <td className="py-4 px-3 text-gray-400">{format(new Date(f.created_at), 'dd/MM/yy', { locale: th })}</td>
                        <td className="py-4 px-3 text-gray-400">{f.uploaded_by ? (creatorNames[f.uploaded_by] ?? '…') : '—'}</td>
                        <td className="py-4 px-3">
                          <div className="flex flex-wrap gap-0.5 items-center">
                            <BtnDownload onClick={() => downloadOne(f.file_path, f.file_name)} title="ดาวน์โหลด" />
                            {canEdit && (
                              <>
                                {editing ? (
                                  <>
                                    <input type="text" value={editTopic} onChange={(e) => setEditTopic(e.target.value)} placeholder="หัวข้อ" className="w-24 text-xs bg-premium-dark border border-premium-gold/30 rounded px-2 py-0.5 text-white" />
                                    <button type="button" className="text-xs text-premium-gold hover:underline ml-1" onClick={() => handleUpdateTopic(f.id)}>บันทึก</button>
                                    <button type="button" className="text-xs text-gray-400 hover:underline" onClick={() => { setEditId(null); setEditTopic(''); }}>ยกเลิก</button>
                                  </>
                                ) : (
                                  <>
                                    <BtnEdit onClick={() => { setEditId(f.id); setEditTopic(f.topic || ''); }} title="แก้ไข" />
                                    <BtnDelete onClick={() => handleDelete(f)} title="ลบ" />
                                  </>
                                )}
                              </>
                            )}
                          </div>
                        </td>
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
              pageSizeOptions={PAGE_SIZE_OPTIONS}
              itemLabel="รายการ"
            />
          </>
        )}
      </div>

      <PageModal open={uploadModal} onClose={() => !uploading && setUploadModal(false)} title="อัปโหลดไฟล์ — กำหนดสิทธิการแสดง" footer={
        <> <Button variant="ghost" onClick={() => setUploadModal(false)} disabled={uploading}>ยกเลิก</Button> <Button variant="gold" onClick={submitUpload} loading={uploading} disabled={!uploadForm.files?.length}>อัปโหลด</Button> </>
      }>
        <div className="space-y-4">
          <section className="rounded-lg border border-premium-gold/20 bg-premium-darker/50 p-3">
            <h4 className="text-premium-gold/90 text-sm font-medium mb-3">สิทธิ์การมองเห็น</h4>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <MultiSelect label="แผนกที่เห็นได้" options={[{ id: BRANCH_ALL, label: 'ทุกแผนก' }, ...branchOptions]} value={uploadForm.uploadBranches} onChange={(uploadBranches) => setUploadForm((f) => ({ ...f, uploadBranches }))} placeholder="เลือกแผนก (ได้หลายแผนก)" allId={BRANCH_ALL} allLabel="ทุกแผนก" showChips searchable />
              <MultiSelect label="เว็บที่เห็นได้" options={websiteOptions} value={uploadForm.uploadWebsites} onChange={(uploadWebsites) => setUploadForm((f) => ({ ...f, uploadWebsites }))} placeholder="เลือกเว็บ" allId={WEBSITE_ALL} allLabel="ทั้งหมด" showChips searchable />
              <MultiSelect label="ตำแหน่งที่เห็นได้" options={roleOptionsForSelect} value={uploadForm.visible_roles} onChange={(visible_roles) => setUploadForm((f) => ({ ...f, visible_roles }))} placeholder="ไม่เลือก = ทุกตำแหน่ง" showChips searchable className="md:col-span-2" />
            </div>
          </section>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-gray-400 text-sm mb-1">หัวข้อไฟล์</label>
              <input type="text" value={uploadForm.topic} onChange={(e) => setUploadForm((f) => ({ ...f, topic: e.target.value }))} className="w-full bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white" placeholder="หัวข้อหรือคำอธิบาย" />
            </div>
            <div>
              <label className="block text-gray-400 text-sm mb-1">เลือกไฟล์ *</label>
              <input type="file" multiple accept={ACCEPT} className="w-full bg-premium-dark border border-premium-gold/30 rounded-lg px-3 py-2 text-white text-sm" onChange={(e) => setUploadForm((f) => ({ ...f, files: e.target.files }))} />
              {uploadForm.files?.length ? <p className="text-gray-500 text-xs mt-1">เลือกแล้ว {uploadForm.files.length} ไฟล์</p> : null}
            </div>
          </div>
        </div>
      </PageModal>
    </div>
  );
}
