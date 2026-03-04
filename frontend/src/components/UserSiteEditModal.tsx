import { useState, useEffect } from 'react';
import type { Profile, Website } from '../lib/types';
import type { AssignmentRow } from '../lib/websites';
import Button from './ui/Button';
import Modal from './ui/Modal';

type Props = {
  open: boolean;
  onClose: () => void;
  user: Profile | null;
  initialSites: AssignmentRow[];
  allWebsites: Website[];
  onAssign: (websiteId: string, userId: string) => Promise<void>;
  onUnassign: (assignmentId: string) => Promise<void>;
  onSetPrimary: (userId: string, websiteId: string) => Promise<void>;
  loading?: boolean;
};

export function UserSiteEditModal({
  open,
  onClose,
  user,
  initialSites,
  allWebsites,
  onAssign,
  onUnassign,
  onSetPrimary,
  loading: externalLoading = false,
}: Props) {
  const [checkedIds, setCheckedIds] = useState<Set<string>>(new Set());
  const [mainSiteId, setMainSiteId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const loading = externalLoading || saving;

  useEffect(() => {
    if (!open || !user) return;
    const ids = new Set(initialSites.map((a) => a.website_id));
    const main = initialSites.find((a) => a.is_primary)?.website_id ?? null;
    setCheckedIds(ids);
    setMainSiteId(main);
  }, [open, user?.id, initialSites]);

  const toggleSite = (websiteId: string) => {
    setCheckedIds((prev) => {
      const next = new Set(prev);
      if (next.has(websiteId)) next.delete(websiteId);
      else next.add(websiteId);
      return next;
    });
  };

  useEffect(() => {
    if (!open) return;
    if (mainSiteId && !checkedIds.has(mainSiteId)) {
      const first = [...checkedIds][0] ?? null;
      setMainSiteId(first);
    }
  }, [open, mainSiteId, checkedIds]);

  const handleSave = async () => {
    if (!user) return;
    const initialIds = new Set(initialSites.map((a) => a.website_id));
    const toUnassign = initialSites.filter((a) => !checkedIds.has(a.website_id)).map((a) => a.id);
    const toAssign = [...checkedIds].filter((id) => !initialIds.has(id));
    const newMain = mainSiteId && checkedIds.has(mainSiteId) ? mainSiteId : null;

    setSaving(true);
    try {
      for (const assignmentId of toUnassign) {
        await onUnassign(assignmentId);
      }
      for (const websiteId of toAssign) {
        await onAssign(websiteId, user.id);
      }
      if (newMain) {
        await onSetPrimary(user.id, newMain);
      }
      onClose();
    } catch (e) {
      throw e;
    } finally {
      setSaving(false);
    }
  };

  const displayName = user?.display_name || user?.email || 'ผู้ใช้';

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={`แก้ไขเว็บของผู้ใช้: ${displayName}`}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>ยกเลิก</Button>
          <Button variant="gold" onClick={handleSave} loading={loading}>บันทึก</Button>
        </>
      }
    >
      <div className="space-y-4">
        <div>
          <p className="text-gray-400 text-sm mb-2">เลือกเว็บที่ผู้ใช้ดูแล (เช็ค = มอบหมายแล้ว)</p>
          <div className="max-h-64 overflow-y-auto space-y-2 pr-1">
            {allWebsites.length === 0 ? (
              <p className="text-gray-500 text-sm">ไม่มีเว็บในระบบ</p>
            ) : (
              allWebsites.map((w) => (
                <label key={w.id} className="flex items-center gap-3 cursor-pointer group py-2 px-3 rounded border border-premium-gold/10 hover:bg-premium-gold/5">
                  <input
                    type="checkbox"
                    checked={checkedIds.has(w.id)}
                    onChange={() => toggleSite(w.id)}
                    className="rounded border-premium-gold/50 text-premium-gold focus:ring-premium-gold/30"
                  />
                  <span className="text-gray-200 group-hover:text-white">{w.name}</span>
                  <span className="font-mono text-premium-gold/80 text-sm">({w.alias})</span>
                  {checkedIds.has(w.id) && (
                    <span className="ml-auto flex items-center gap-2">
                      <input
                        type="radio"
                        name="main-site"
                        checked={mainSiteId === w.id}
                        onChange={() => setMainSiteId(w.id)}
                        className="text-premium-gold focus:ring-premium-gold/30"
                      />
                      <span className="text-premium-gold text-sm">ตั้งเป็นเว็บหลัก</span>
                    </span>
                  )}
                </label>
              ))
            )}
          </div>
        </div>
        {checkedIds.size > 0 && (
          <p className="text-gray-500 text-xs">
            เว็บหลักปัจจุบัน: {mainSiteId ? allWebsites.find((w) => w.id === mainSiteId)?.name ?? mainSiteId : '—'}
          </p>
        )}
      </div>
    </Modal>
  );
}
