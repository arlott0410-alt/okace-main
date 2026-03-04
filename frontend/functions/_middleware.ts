/**
 * Middleware: บล็อกการเข้าผ่านมือถือเมื่อ allow_mobile_access = false
 * อ่านค่าจาก app_settings (Supabase) พร้อม cache 60 วินาที
 */

type Env = {
  SUPABASE_URL?: string;
  SUPABASE_ANON_KEY?: string;
  VITE_SUPABASE_URL?: string;
  VITE_SUPABASE_ANON_KEY?: string;
};

function getEnv(env: Env): { base: string; apikey: string } | null {
  const base = env.SUPABASE_URL || env.VITE_SUPABASE_URL || '';
  const apikey = env.SUPABASE_ANON_KEY || env.VITE_SUPABASE_ANON_KEY || '';
  if (!base || !base.startsWith('http') || !apikey || apikey.length < 20) return null;
  return { base: base.replace(/\/$/, ''), apikey };
}

let cached: { v: boolean | null; at: number } = { v: null, at: 0 };
const TTL_MS = 60_000;

function isMobileRequest(request: Request): boolean {
  const ua = request.headers.get('user-agent') || '';
  const secChUaMobile = request.headers.get('sec-ch-ua-mobile');
  if (secChUaMobile === '?1') return true;
  const mobileRegex = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini|Mobile|mobile/i;
  return mobileRegex.test(ua);
}

async function getAllowMobile(env: Env): Promise<boolean> {
  const now = Date.now();
  if (cached.v !== null && now - cached.at < TTL_MS) return cached.v;

  const cfg = getEnv(env);
  if (!cfg) {
    cached = { v: false, at: now };
    return false;
  }

  const url = `${cfg.base}/rest/v1/app_settings?key=eq.allow_mobile_access&select=value_bool`;

  try {
    const res = await fetch(url, {
      headers: {
        apikey: cfg.apikey,
        Authorization: `Bearer ${cfg.apikey}`,
        'Content-Type': 'application/json',
      },
    });

    if (!res.ok) {
      cached = { v: false, at: now };
      return false;
    }

    const data = (await res.json()) as unknown;
    const v = Array.isArray(data) && data[0]?.value_bool === true;
    cached = { v, at: now };
    return v;
  } catch {
    cached = { v: false, at: now };
    return false;
  }
}

const MOBILE_BLOCK_HTML = `<!DOCTYPE html>
<html lang="th">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ไม่รองรับการเข้าผ่านมือถือ</title>
  <style>
    body { font-family: system-ui, sans-serif; background: #0f1419; color: #e7e9ea; min-height: 100vh; display: flex; align-items: center; justify-content: center; margin: 0; padding: 1rem; }
    .box { max-width: 360px; text-align: center; }
    h1 { font-size: 1.25rem; margin-bottom: 0.75rem; }
    p { color: #8b98a5; font-size: 0.9375rem; line-height: 1.5; }
  </style>
</head>
<body>
  <div class="box">
    <h1>ไม่รองรับการเข้าผ่านมือถือ</h1>
    <p>ระบบนี้เปิดให้ใช้งานจากเครื่องคอมพิวเตอร์ (Desktop) เท่านั้น กรุณาเข้าใช้งานจาก PC หรือ Notebook</p>
  </div>
</body>
</html>`;

export const onRequest: PagesFunction<Env> = async (context) => {
  const { request, env, next } = context;

  if (!isMobileRequest(request)) {
    return next();
  }

  const allow = await getAllowMobile(env);
  if (allow) {
    return next();
  }

  return new Response(MOBILE_BLOCK_HTML, {
    status: 403,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
    },
  });
};
