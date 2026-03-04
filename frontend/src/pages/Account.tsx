import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import Button from '../components/ui/Button';
import ProfileBar from '../components/ProfileBar';

function ensureHttps(url: string): string {
  const t = url.trim();
  if (!t) return '';
  if (t.startsWith('http://') || t.startsWith('https://')) return t;
  return 'https://' + t;
}

export default function Account() {
  const { profile, refreshProfile } = useAuth();
  const [form, setForm] = useState({
    email: '',
    telegram: '',
    lock_code: '',
    email_code: '',
    computer_code: '',
    work_access_code: '',
    two_fa: '',
    avatar_url: '',
    link1_url: '',
    link2_url: '',
    note_title: '',
    note_body: '',
  });
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<{ type: 'ok' | 'err'; text: string } | null>(null);
  const [passwordForm, setPasswordForm] = useState({ newPassword: '', confirmPassword: '' });
  const [passwordLoading, setPasswordLoading] = useState(false);
  const [passwordMessage, setPasswordMessage] = useState<{ type: 'ok' | 'err'; text: string } | null>(null);

  useEffect(() => {
    if (!profile) return;
    setForm({
      email: profile.email ?? '',
      telegram: profile.telegram ?? '',
      lock_code: profile.lock_code ?? '',
      email_code: profile.email_code ?? '',
      computer_code: profile.computer_code ?? '',
      work_access_code: profile.work_access_code ?? '',
      two_fa: profile.two_fa ?? '',
      avatar_url: profile.avatar_url ?? '',
      link1_url: profile.link1_url ?? '',
      link2_url: profile.link2_url ?? '',
      note_title: profile.note_title ?? '',
      note_body: profile.note_body ?? '',
    });
  }, [profile]);

  const handleSave = async () => {
    if (!profile?.id) return;
    setMessage(null);
    setLoading(true);
    try {
      const payload = {
        email: form.email.trim() || (profile?.email ?? ''),
        telegram: form.telegram.trim() || null,
        lock_code: form.lock_code.trim() || null,
        email_code: form.email_code.trim() || null,
        computer_code: form.computer_code.trim() || null,
        work_access_code: form.work_access_code.trim() || null,
        two_fa: form.two_fa.trim() || null,
        avatar_url: form.avatar_url.trim() ? ensureHttps(form.avatar_url) : null,
        link1_url: form.link1_url.trim() ? ensureHttps(form.link1_url) : null,
        link2_url: form.link2_url.trim() ? ensureHttps(form.link2_url) : null,
        note_title: form.note_title.trim() || null,
        note_body: form.note_body.trim() || null,
      };
      const { error } = await supabase.from('profiles').update(payload).eq('id', profile.id).select().single();
      if (error) throw error;
      await refreshProfile();
      setMessage({ type: 'ok', text: 'บันทึกข้อมูลเรียบร้อยแล้ว' });
    } catch (e) {
      setMessage({ type: 'err', text: e instanceof Error ? e.message : 'บันทึกไม่สำเร็จ' });
    } finally {
      setLoading(false);
    }
  };

  const handleChangePassword = async () => {
    const newP = passwordForm.newPassword.trim();
    const confirm = passwordForm.confirmPassword.trim();
    setPasswordMessage(null);
    if (!newP || newP.length < 6) {
      setPasswordMessage({ type: 'err', text: 'รหัสผ่านใหม่ต้องมีอย่างน้อย 6 ตัวอักษร' });
      return;
    }
    if (newP !== confirm) {
      setPasswordMessage({ type: 'err', text: 'รหัสผ่านใหม่กับยืนยันไม่ตรงกัน' });
      return;
    }
    setPasswordLoading(true);
    try {
      const { error } = await supabase.auth.updateUser({ password: newP });
      if (error) throw error;
      setPasswordMessage({ type: 'ok', text: 'เปลี่ยนรหัสผ่านเรียบร้อยแล้ว' });
      setPasswordForm({ newPassword: '', confirmPassword: '' });
    } catch (e) {
      setPasswordMessage({ type: 'err', text: e instanceof Error ? e.message : 'เปลี่ยนรหัสผ่านไม่สำเร็จ' });
    } finally {
      setPasswordLoading(false);
    }
  };

  const inputClass = 'w-full rounded-lg border border-premium-gold/25 bg-premium-dark text-white text-sm px-3 py-2 focus:outline-none focus:ring-1 focus:ring-premium-gold/50';
  const labelClass = 'block text-gray-400 text-xs font-medium mb-1';
  const readOnlyClass = inputClass + ' opacity-90 cursor-default';

  return (
    <div className="space-y-6">
      <h1 className="text-premium-gold text-xl font-semibold">บัญชีของฉัน</h1>

      <ProfileBar profile={profile ?? null} />

      <section className="rounded-lg border border-premium-gold/20 bg-premium-darker/50 p-4 max-w-md">
        <h2 className="text-premium-gold font-semibold text-sm mb-3">เปลี่ยนรหัสผ่าน</h2>
        <div className="space-y-3 mb-3">
          <div>
            <label className={labelClass}>รหัสผ่านใหม่</label>
            <input
              type="password"
              value={passwordForm.newPassword}
              onChange={(e) => setPasswordForm((f) => ({ ...f, newPassword: e.target.value }))}
              placeholder="อย่างน้อย 6 ตัวอักษร"
              className={inputClass}
              autoComplete="new-password"
            />
          </div>
          <div>
            <label className={labelClass}>ยืนยันรหัสผ่านใหม่</label>
            <input
              type="password"
              value={passwordForm.confirmPassword}
              onChange={(e) => setPasswordForm((f) => ({ ...f, confirmPassword: e.target.value }))}
              placeholder="กรอกรหัสผ่านอีกครั้ง"
              className={inputClass}
              autoComplete="new-password"
            />
          </div>
        </div>
        {passwordMessage && <p className={`text-sm mb-2 ${passwordMessage.type === 'ok' ? 'text-green-400' : 'text-red-400'}`}>{passwordMessage.text}</p>}
        <Button variant="gold" onClick={handleChangePassword} loading={passwordLoading}>เปลี่ยนรหัสผ่าน</Button>
      </section>

      <section className="rounded-lg border border-premium-gold/20 bg-premium-darker/50 p-4">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-4">
          <div>
            <label className={labelClass}>เบอร์ TELEGRAM</label>
            <input type="text" value={form.telegram} onChange={(e) => setForm((f) => ({ ...f, telegram: e.target.value }))} placeholder="TELEGRAM" className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>รหัสล็อค</label>
            <input type="text" value={form.lock_code} onChange={(e) => setForm((f) => ({ ...f, lock_code: e.target.value }))} placeholder="รหัสล็อค" className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>อีเมล</label>
            <input type="email" value={form.email} onChange={(e) => setForm((f) => ({ ...f, email: e.target.value }))} placeholder="อีเมลที่ต้องการใช้" className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>รหัส EMAIL</label>
            <input type="text" value={form.email_code} onChange={(e) => setForm((f) => ({ ...f, email_code: e.target.value }))} placeholder="รหัส EMAIL" className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>รหัสคอม</label>
            <input type="text" value={form.computer_code} onChange={(e) => setForm((f) => ({ ...f, computer_code: e.target.value }))} placeholder="รหัสคอม" className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>รหัสเข้างาน</label>
            <input type="text" value={form.work_access_code} onChange={(e) => setForm((f) => ({ ...f, work_access_code: e.target.value }))} placeholder="รหัสเข้างาน" className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>2FA</label>
            <input type="text" value={form.two_fa} onChange={(e) => setForm((f) => ({ ...f, two_fa: e.target.value }))} placeholder="2FA" className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>รูปโปรไฟล์ (URL)</label>
            <input type="url" value={form.avatar_url} onChange={(e) => setForm((f) => ({ ...f, avatar_url: e.target.value }))} placeholder="https://..." className={inputClass} />
          </div>
        </div>

        <div className="border-t border-premium-gold/15 pt-4 mt-4">
          <h2 className="text-premium-gold font-semibold text-sm mb-3 flex items-center gap-2">
            <span className="text-amber-400">★</span> ลิงก์ส่วนตัว & บันทึก
          </h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-4">
            <div>
              <label className={labelClass}>ชื่อลิงก์ 1</label>
              <input type="url" value={form.link1_url} onChange={(e) => setForm((f) => ({ ...f, link1_url: e.target.value }))} placeholder="URL..." className={inputClass} />
            </div>
            <div>
              <label className={labelClass}>ชื่อลิงก์ 2</label>
              <input type="url" value={form.link2_url} onChange={(e) => setForm((f) => ({ ...f, link2_url: e.target.value }))} placeholder="URL..." className={inputClass} />
            </div>
          </div>
          <div className="space-y-3">
            <div>
              <label className={labelClass}>หัวข้อบันทึก</label>
              <input type="text" value={form.note_title} onChange={(e) => setForm((f) => ({ ...f, note_title: e.target.value }))} placeholder="เขียนบันทึก..." className={inputClass} />
            </div>
            <div>
              <label className={labelClass}>เขียนบันทึก</label>
              <textarea value={form.note_body} onChange={(e) => setForm((f) => ({ ...f, note_body: e.target.value }))} placeholder="เขียนบันทึก..." rows={4} className={inputClass} />
            </div>
          </div>
        </div>

        <div className="flex flex-wrap items-center justify-between gap-3 mt-6 pt-4 border-t border-premium-gold/15">
          <div>
            <label className={labelClass}>ชื่อที่แสดง (display_name)</label>
            <input type="text" value={profile?.display_name ?? profile?.email ?? ''} readOnly className={readOnlyClass} />
          </div>
          <div>
            {message && <p className={`text-sm mb-2 ${message.type === 'ok' ? 'text-green-400' : 'text-red-400'}`}>{message.text}</p>}
            <Button variant="gold" onClick={handleSave} loading={loading}>บันทึกข้อมูล</Button>
          </div>
        </div>
      </section>
    </div>
  );
}
