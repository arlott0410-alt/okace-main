import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import { useBranchesShifts } from '../lib/BranchesShiftsContext';
import type { Profile } from '../lib/types';
import {
  listRounds,
  createRound,
  updateRoundStatus,
  deleteRound,
  listAssignments,
  generatePreview,
  applyPreview,
  addManualAssignment,
  removeAssignment,
  listPublishedAssignmentsByBranch,
} from '../lib/shiftSwapRounds';
import type { ShiftSwapRound, ShiftSwapAssignment } from '../lib/types';
import type { PreviewAssignment } from '../lib/shiftSwapRounds';
import Button from '../components/ui/Button';
import Modal, { ConfirmModal } from '../components/ui/Modal';
import { BtnDelete } from '../components/ui/ActionIcons';

export default function ShiftSwap() {
  const { user, profile } = useAuth();
  const { branches, shifts } = useBranchesShifts();
  const isAdmin = profile?.role === 'admin';
  const isManager = profile?.role === 'manager';
  const isInstructorHead = profile?.role === 'instructor_head';
  const canManageRounds = isAdmin || isManager || isInstructorHead;

  const [rounds, setRounds] = useState<(ShiftSwapRound & { branch?: { id: string; name: string }; website?: { id: string; name: string } | null })[]>([]);
  const [websites, setWebsites] = useState<{ id: string; name: string; branch_id: string }[]>([]);
  const [branchId, setBranchId] = useState(profile?.default_branch_id ?? '');
  const [selectedRoundId, setSelectedRoundId] = useState<string | null>(null);
  const [assignments, setAssignments] = useState<ShiftSwapAssignment[]>([]);
  const [previewRows, setPreviewRows] = useState<PreviewAssignment[] | null>(null);
  const [profilesInRound, setProfilesInRound] = useState<Profile[]>([]);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState('');

  const [showCreateRound, setShowCreateRound] = useState(false);
  const [newRoundStart, setNewRoundStart] = useState('');
  const [newRoundEnd, setNewRoundEnd] = useState('');
  const [newRoundWebsiteId, setNewRoundWebsiteId] = useState<string>('');

  const [showManualPair, setShowManualPair] = useState(false);
  const [manualDate, setManualDate] = useState('');
  const [manualUserA, setManualUserA] = useState('');
  const [manualUserB, setManualUserB] = useState('');

  const [confirmDeleteRound, setConfirmDeleteRound] = useState<string | null>(null);
  const [confirmDeleteAssign, setConfirmDeleteAssign] = useState<string | null>(null);

  const [staffTable, setStaffTable] = useState<{ swap_date: string; user_name: string; from_shift_name: string; to_shift_name: string }[]>([]);

  useEffect(() => {
    if (!canManageRounds) return;
    listRounds(undefined).then(setRounds);
  }, [canManageRounds]);

  useEffect(() => {
    if (!branchId) setBranchId(profile?.default_branch_id ?? branches[0]?.id ?? '');
  }, [profile?.default_branch_id, branches, branchId]);

  useEffect(() => {
    if (branchId) {
      supabase.from('websites').select('id, name, branch_id').eq('branch_id', branchId).order('name').then(({ data }) => setWebsites((data || []) as { id: string; name: string; branch_id: string }[]));
    } else setWebsites([]);
  }, [branchId]);

  useEffect(() => {
    if (selectedRoundId) listAssignments(selectedRoundId).then(setAssignments);
    else setAssignments([]);
    setPreviewRows(null);
  }, [selectedRoundId]);

  const selectedRound = rounds.find((r) => r.id === selectedRoundId);
  useEffect(() => {
    if (!canManageRounds || !selectedRound) {
      setProfilesInRound([]);
      return;
    }
    const profileCols = 'id, email, display_name, role, default_branch_id, default_shift_id, active, created_at, updated_at';
    let q = supabase
      .from('profiles')
      .select(profileCols)
      .eq('default_branch_id', selectedRound.branch_id)
      .eq('active', true)
      .in('role', ['instructor', 'staff', 'instructor_head']);
    if (selectedRound.website_id) {
      supabase.from('website_assignments').select('user_id').eq('website_id', selectedRound.website_id).then(({ data: assign }) => {
        const ids = (assign || []).map((r: { user_id: string }) => r.user_id);
        if (ids.length === 0) return setProfilesInRound([]);
        supabase.from('profiles').select(profileCols).eq('default_branch_id', selectedRound.branch_id).eq('active', true).in('role', ['instructor', 'staff', 'instructor_head']).in('id', ids).order('display_name').then(({ data }) => setProfilesInRound((data || []) as Profile[]));
      });
    } else {
      q.order('display_name').then(({ data }) => setProfilesInRound((data || []) as Profile[]));
    }
  }, [canManageRounds, selectedRound?.id, selectedRound?.branch_id, selectedRound?.website_id]);

  useEffect(() => {
    if (canManageRounds || !profile?.default_branch_id) return;
    listPublishedAssignmentsByBranch(profile.default_branch_id).then(setStaffTable);
  }, [canManageRounds, profile?.default_branch_id]);

  const shiftNames = Object.fromEntries(shifts.map((s) => [s.id, s.name]));
  const profileNames = Object.fromEntries(profilesInRound.map((p) => [p.id, p.display_name || p.email || p.id]));

  const handleCreateRound = async () => {
    if (!user?.id || !branchId || !newRoundStart || !newRoundEnd) {
      setErr('กรุณาเลือกแผนก และกรอกช่วงวันที่');
      return;
    }
    setErr('');
    setLoading(true);
    try {
      const r = await createRound({
        branch_id: branchId,
        website_id: newRoundWebsiteId || null,
        start_date: newRoundStart,
        end_date: newRoundEnd,
        created_by: user.id,
      });
      setRounds((prev) => [r as ShiftSwapRound & { branch?: { id: string; name: string }; website?: { id: string; name: string } | null }, ...prev]);
      setSelectedRoundId(r.id);
      setShowCreateRound(false);
      setNewRoundStart('');
      setNewRoundEnd('');
      setNewRoundWebsiteId('');
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'เกิดข้อผิดพลาด');
    } finally {
      setLoading(false);
    }
  };

  const handlePreview = async () => {
    if (!selectedRoundId) return;
    setErr('');
    setLoading(true);
    try {
      const rows = await generatePreview(selectedRoundId);
      setPreviewRows(rows);
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'เกิดข้อผิดพลาด');
    } finally {
      setLoading(false);
    }
  };

  const handleApplyPreview = async () => {
    if (!selectedRoundId || !previewRows?.length) return;
    setLoading(true);
    try {
      await applyPreview(selectedRoundId, previewRows);
      setPreviewRows(null);
      listAssignments(selectedRoundId).then(setAssignments);
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'เกิดข้อผิดพลาด');
    } finally {
      setLoading(false);
    }
  };

  const handlePublish = async () => {
    if (!selectedRoundId) return;
    setLoading(true);
    try {
      await updateRoundStatus(selectedRoundId, 'published');
      setRounds((prev) => prev.map((r) => (r.id === selectedRoundId ? { ...r, status: 'published' as const } : r)));
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'เกิดข้อผิดพลาด');
    } finally {
      setLoading(false);
    }
  };

  const handleDeleteRound = async (id: string) => {
    setLoading(true);
    try {
      await deleteRound(id);
      setRounds((prev) => prev.filter((r) => r.id !== id));
      if (selectedRoundId === id) setSelectedRoundId(null);
      setConfirmDeleteRound(null);
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'เกิดข้อผิดพลาด');
    } finally {
      setLoading(false);
    }
  };

  const handleAddManualPair = async () => {
    if (!selectedRoundId || !manualDate || !manualUserA || !manualUserB || manualUserA === manualUserB) {
      setErr('กรุณาเลือกวันที่ และคนสองคนที่ต่างกัน');
      return;
    }
    const pa = profilesInRound.find((p) => p.id === manualUserA);
    const pb = profilesInRound.find((p) => p.id === manualUserB);
    if (!pa?.default_shift_id || !pb?.default_shift_id) {
      setErr('ทั้งสองคนต้องมีกะประจำตัว');
      return;
    }
    setErr('');
    setLoading(true);
    try {
      await addManualAssignment({
        round_id: selectedRoundId,
        swap_date: manualDate,
        user_id: manualUserA,
        from_shift_id: pa.default_shift_id,
        to_shift_id: pb.default_shift_id,
        partner_id: manualUserB,
      });
      await addManualAssignment({
        round_id: selectedRoundId,
        swap_date: manualDate,
        user_id: manualUserB,
        from_shift_id: pb.default_shift_id,
        to_shift_id: pa.default_shift_id,
        partner_id: manualUserA,
      });
      listAssignments(selectedRoundId).then(setAssignments);
      setShowManualPair(false);
      setManualDate('');
      setManualUserA('');
      setManualUserB('');
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'เกิดข้อผิดพลาด');
    } finally {
      setLoading(false);
    }
  };

  const handleRemoveAssignment = async (id: string) => {
    setLoading(true);
    try {
      await removeAssignment(id);
      if (selectedRoundId) listAssignments(selectedRoundId).then(setAssignments);
      setConfirmDeleteAssign(null);
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'เกิดข้อผิดพลาด');
    } finally {
      setLoading(false);
    }
  };

  const dateRange = selectedRound ? (() => {
    const s = new Date(selectedRound.start_date);
    const e = new Date(selectedRound.end_date);
    const out: string[] = [];
    for (let d = new Date(s); d <= e; d.setDate(d.getDate() + 1)) out.push(d.toISOString().slice(0, 10));
    return out;
  })() : [];

  const displayRows = previewRows !== null ? previewRows.map((r, i) => ({ key: `preview-${i}`, swap_date: r.swap_date, user_id: r.user_id, from_shift_id: r.from_shift_id, to_shift_id: r.to_shift_id, partner_id: r.partner_id, id: '' })) : assignments;
  const isPreview = previewRows !== null;

  if (!canManageRounds) {
    return (
      <div>
        <h1 className="text-premium-gold text-xl font-semibold mb-4">ตารางสลับกะ</h1>
        <p className="text-gray-400 text-sm mb-4">ดูวันที่สลับกะของทุกคนในแผนก (รอบที่หัวหน้าเผยแพร่แล้ว)</p>
        <div className="overflow-x-auto border border-premium-gold/20 rounded-lg">
          <table className="w-full text-sm">
            <thead>
              <tr>
                <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">วันที่</th>
                <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">ชื่อ</th>
                <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">จากกะ → เป็นกะ</th>
              </tr>
            </thead>
            <tbody>
              {staffTable.map((row, i) => (
                <tr key={`${row.swap_date}-${row.user_name}-${i}`} className="border-b border-premium-gold/10">
                  <td className="p-2 text-gray-200">{row.swap_date}</td>
                  <td className="p-2">{row.user_name}</td>
                  <td className="p-2">{row.from_shift_name} → {row.to_shift_name}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {staffTable.length === 0 && <p className="text-gray-500 text-sm mt-2">ยังไม่มีตารางสลับกะที่เผยแพร่ในแผนกของคุณ</p>}
      </div>
    );
  }

  return (
    <div>
      <h1 className="text-premium-gold text-xl font-semibold mb-4">สลับกะ</h1>
      {err && <p className="text-red-400 text-sm mb-2">{err}</p>}

      <section className="mb-8">
        <div className="flex flex-wrap items-center gap-4 mb-4">
          {(isAdmin || isManager) && (
            <div>
              <label className="block text-gray-400 text-sm mb-1">แผนก</label>
              <select value={branchId} onChange={(e) => setBranchId(e.target.value)} className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white">
                {branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
              </select>
            </div>
          )}
          <Button variant="gold" onClick={() => setShowCreateRound(true)} className="self-end">สร้างรอบสลับกะ</Button>
        </div>

        <div className="mb-4">
          <label className="block text-gray-400 text-sm mb-1">เลือกรอบ</label>
          <select
            value={selectedRoundId ?? ''}
            onChange={(e) => setSelectedRoundId(e.target.value || null)}
            className="bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white min-w-[300px]"
          >
            <option value="">-- เลือกรอบ --</option>
            {rounds.map((r) => (
              <option key={r.id} value={r.id}>
                {(r as { branch?: { name: string } }).branch?.name ?? r.branch_id} {r.website_id ? `| เว็บ ${(r as { website?: { name: string } }).website?.name ?? ''}` : '| ทั้งแผนก'} | {r.start_date} ถึง {r.end_date} | {r.status === 'draft' ? 'แบบร่าง' : 'เผยแพร่แล้ว'}
              </option>
            ))}
          </select>
        </div>

        {selectedRound && (
          <>
            <div className="flex flex-wrap gap-2 mb-4">
              {selectedRound.status === 'draft' && (
                <>
                  {!isPreview ? (
                    <Button variant="gold" onClick={handlePreview} loading={loading}>สุ่มดูตัวอย่าง</Button>
                  ) : (
                    <>
                      <Button variant="gold" onClick={handleApplyPreview} loading={loading}>ใช้ชุดนี้</Button>
                      <Button variant="ghost" onClick={handlePreview} loading={loading}>สุ่มใหม่</Button>
                    </>
                  )}
                  <Button variant="ghost" onClick={() => setShowManualPair(true)}>เพิ่มคู่สลับกะ (แมนนวล)</Button>
                  <Button variant="ghost" onClick={handlePublish} loading={loading}>เผยแพร่ (แจ้งพนักงาน)</Button>
                </>
              )}
              {selectedRound.status === 'draft' && (
                <Button variant="danger" onClick={() => setConfirmDeleteRound(selectedRound.id)}>ลบรอบ</Button>
              )}
            </div>

            {(isPreview || assignments.length > 0) && (
              <div className="overflow-x-auto border border-premium-gold/20 rounded-lg mb-4">
                {isPreview && <p className="p-2 text-premium-gold/90 text-sm">ตัวอย่างการสุ่ม — ตรวจสอบแล้วกด &quot;ใช้ชุดนี้&quot; หรือ &quot;สุ่มใหม่&quot;</p>}
                <table className="w-full text-sm">
                  <thead>
                    <tr>
                      <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">วันที่</th>
                      <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">ผู้สลับ (จากกะ → เป็นกะ)</th>
                      <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">คู่กับ</th>
                      {selectedRound.status === 'draft' && !isPreview && <th className="text-left p-2 border-b border-premium-gold/20 text-premium-gold">การดำเนินการ</th>}
                    </tr>
                  </thead>
                  <tbody>
                    {displayRows.map((a, idx) => (
                      <tr key={a.id || `row-${idx}`} className="border-b border-premium-gold/10">
                        <td className="p-2 text-gray-200">{a.swap_date}</td>
                        <td className="p-2">{profileNames[a.user_id] ?? a.user_id} ({shiftNames[a.from_shift_id]} → {shiftNames[a.to_shift_id]})</td>
                        <td className="p-2 text-gray-400">{a.partner_id ? (profileNames[a.partner_id] ?? a.partner_id) : '-'}</td>
                        {selectedRound.status === 'draft' && !isPreview && 'id' in a && a.id && (
                          <td className="p-2">
                            <BtnDelete onClick={() => setConfirmDeleteAssign(a.id)} title="ลบ" />
                          </td>
                        )}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </>
        )}
      </section>

      <Modal open={showCreateRound} onClose={() => setShowCreateRound(false)} title="สร้างรอบสลับกะ" footer={
        <>
          <Button variant="ghost" onClick={() => setShowCreateRound(false)}>ยกเลิก</Button>
          <Button variant="gold" onClick={handleCreateRound} loading={loading}>สร้าง</Button>
        </>
      }>
        <div className="space-y-3">
          <div>
            <label className="block text-gray-400 text-sm mb-1">ขอบเขต</label>
            <select value={newRoundWebsiteId} onChange={(e) => setNewRoundWebsiteId(e.target.value)} className="w-full bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white">
              <option value="">ทั้งแผนก</option>
              {websites.map((w) => <option key={w.id} value={w.id}>เว็บ {w.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className="block text-gray-400 text-sm mb-1">เริ่มวันที่</label>
              <input type="date" value={newRoundStart} onChange={(e) => setNewRoundStart(e.target.value)} className="w-full bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white" />
            </div>
            <div>
              <label className="block text-gray-400 text-sm mb-1">ถึงวันที่</label>
              <input type="date" value={newRoundEnd} onChange={(e) => setNewRoundEnd(e.target.value)} className="w-full bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white" />
            </div>
          </div>
          <p className="text-gray-500 text-xs">ระบบจะคำนวณจำนวนคู่จากจำนวนวันและจำนวนพนักงาน (สลับทั้งหมดทุกคน) หัวหน้าคู่กับหัวหน้าก่อน และกันวันหยุดที่จองแล้ว</p>
        </div>
      </Modal>

      <Modal open={showManualPair} onClose={() => setShowManualPair(false)} title="เพิ่มคู่สลับกะ (แมนนวล)" footer={
        <>
          <Button variant="ghost" onClick={() => setShowManualPair(false)}>ยกเลิก</Button>
          <Button variant="gold" onClick={handleAddManualPair} loading={loading}>เพิ่ม</Button>
        </>
      }>
        <div className="space-y-3">
          <div>
            <label className="block text-gray-400 text-sm mb-1">วันที่สลับ</label>
            <select value={manualDate} onChange={(e) => setManualDate(e.target.value)} className="w-full bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white">
              <option value="">-- เลือกวันที่ --</option>
              {dateRange.map((d) => <option key={d} value={d}>{d}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-gray-400 text-sm mb-1">คนที่ 1</label>
            <select value={manualUserA} onChange={(e) => setManualUserA(e.target.value)} className="w-full bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white">
              <option value="">-- เลือก --</option>
              {profilesInRound.map((p) => <option key={p.id} value={p.id}>{p.display_name || p.email} ({shifts.find((s) => s.id === p.default_shift_id)?.name ?? '-'})</option>)}
            </select>
          </div>
          <div>
            <label className="block text-gray-400 text-sm mb-1">คนที่ 2 (คู่สลับ)</label>
            <select value={manualUserB} onChange={(e) => setManualUserB(e.target.value)} className="w-full bg-premium-darker border border-premium-gold/30 rounded px-3 py-2 text-white">
              <option value="">-- เลือก --</option>
              {profilesInRound.map((p) => <option key={p.id} value={p.id}>{p.display_name || p.email} ({shifts.find((s) => s.id === p.default_shift_id)?.name ?? '-'})</option>)}
            </select>
          </div>
        </div>
      </Modal>

      <ConfirmModal open={!!confirmDeleteRound} onClose={() => setConfirmDeleteRound(null)} onConfirm={() => { if (confirmDeleteRound) void handleDeleteRound(confirmDeleteRound); }} title="ยืนยันลบรอบ" message="การลบจะทำให้รายการสลับกะในรอบนี้หายทั้งหมด" confirmLabel="ลบ" variant="danger" loading={loading} />
      <ConfirmModal open={!!confirmDeleteAssign} onClose={() => setConfirmDeleteAssign(null)} onConfirm={() => { if (confirmDeleteAssign) void handleRemoveAssignment(confirmDeleteAssign); }} title="ยืนยันลบคู่สลับกะ" message="จะลบคู่นี้ออกจากรอบ" confirmLabel="ลบ" variant="danger" loading={loading} />
    </div>
  );
}
