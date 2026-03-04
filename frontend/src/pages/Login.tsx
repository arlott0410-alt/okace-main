import { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase, getApiBase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import Button from '../components/ui/Button';

const TURNSTILE_SCRIPT_URL = 'https://challenges.cloudflare.com/turnstile/v0/api.js';

function isTurnstileEnabled(): boolean {
  return import.meta.env.VITE_TURNSTILE_ENABLED === 'true' && !!import.meta.env.VITE_TURNSTILE_SITE_KEY;
}

export default function Login() {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [turnstileToken, setTurnstileToken] = useState('');
  const turnstileContainerRef = useRef<HTMLDivElement>(null);
  const turnstileWidgetIdRef = useRef<string | null>(null);
  const navigate = useNavigate();
  const { profile, user } = useAuth();
  const turnstileEnabled = isTurnstileEnabled();

  useEffect(() => {
    if (!turnstileEnabled || !turnstileContainerRef.current) return;
    const siteKey = import.meta.env.VITE_TURNSTILE_SITE_KEY as string;
    const loadScript = (): void => {
      const g = globalThis as { turnstile?: { render: (el: HTMLElement, opts: { sitekey: string; callback: (token: string) => void }) => string } };
      if (g.turnstile && turnstileContainerRef.current) {
        turnstileWidgetIdRef.current = g.turnstile.render(turnstileContainerRef.current, {
          sitekey: siteKey,
          callback: (token: string) => setTurnstileToken(token),
        });
      }
    };
    if ((globalThis as { turnstile?: unknown }).turnstile) {
      loadScript();
      return;
    }
    const script = document.createElement('script');
    script.src = TURNSTILE_SCRIPT_URL;
    script.async = true;
    script.onload = loadScript;
    document.head.appendChild(script);
    return () => {
      const g = globalThis as { turnstile?: { remove: (id: string) => void } };
      if (g.turnstile && turnstileWidgetIdRef.current) {
        try { g.turnstile.remove(turnstileWidgetIdRef.current); } catch { /* ignore */ }
      }
    };
  }, [turnstileEnabled]);

  if (user && profile) {
    navigate('/dashboard', { replace: true });
    return null;
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const loginName = username.trim();
      if (!loginName) {
        setError('กรุณากรอกชื่อผู้ใช้');
        return;
      }
      if (turnstileEnabled && !turnstileToken) {
        setError('กรุณายืนยัน Turnstile');
        return;
      }
      const base = getApiBase();
      if (turnstileEnabled) {
        const verifyRes = await fetch(`${base}/api/auth/verify-turnstile`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ token: turnstileToken }),
        });
        const verifyJson = (await verifyRes.json().catch(() => ({}))) as { ok?: boolean };
        if (!verifyJson.ok) {
          setError('กรุณายืนยัน Turnstile');
          return;
        }
      }
      const res = await fetch(`${base}/api/auth/resolve-email?login_name=${encodeURIComponent(loginName)}`);
      const json = (await res.json().catch(() => ({}))) as { email?: string | null; error?: string };
      if (!res.ok || json.error) {
        setError('ไม่พบชื่อผู้ใช้นี้ในระบบ');
        return;
      }
      const email = json.email ?? null;
      if (!email) {
        setError('ไม่พบชื่อผู้ใช้นี้ในระบบ');
        return;
      }
      const { data, error: signError } = await supabase.auth.signInWithPassword({ email, password });
      if (signError) {
        setError(signError.message === 'Invalid login credentials' ? 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง' : signError.message);
        return;
      }
      if (data.user) {
        const { data: prof } = await supabase.from('profiles').select('id').eq('id', data.user.id).single();
        if (!prof) {
          setError('ไม่พบโปรไฟล์ผู้ใช้ กรุณาติดต่อผู้ดูแลระบบ');
          await supabase.auth.signOut();
          return;
        }
        navigate('/dashboard', { replace: true });
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-premium-dark p-4">
      <div className="w-full max-w-sm border border-premium-gold/30 rounded-lg bg-premium-darker/80 p-6 shadow-xl">
        <div className="flex flex-col items-center mb-6">
          <img src="/okace-logo.png" alt="OKACE" className="h-16 w-auto object-contain mb-3" />
          <h1 className="text-gray-300 text-lg font-medium">เข้าสู่ระบบ</h1>
        </div>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-gray-300 text-sm mb-1">ชื่อผู้ใช้</label>
            <input
              type="text"
              autoComplete="username"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              className="w-full px-3 py-2 rounded bg-premium-dark border border-premium-gold/30 text-white placeholder-gray-500 focus:outline-none focus:ring-1 focus:ring-premium-gold"
              placeholder="ชื่อผู้ใช้ หรือ อีเมล"
              required
            />
          </div>
          <div>
            <label className="block text-gray-300 text-sm mb-1">รหัสผ่าน</label>
            <input
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full px-3 py-2 rounded bg-premium-dark border border-premium-gold/30 text-white placeholder-gray-500 focus:outline-none focus:ring-1 focus:ring-premium-gold"
              placeholder="รหัสผ่าน"
              required
            />
          </div>
          {turnstileEnabled && <div ref={turnstileContainerRef} className="flex justify-center min-h-[65px]" />}
          {error && <p className="text-red-400 text-sm">{error}</p>}
          <Button type="submit" className="w-full" loading={loading}>เข้าสู่ระบบ</Button>
        </form>
      </div>
    </div>
  );
}
