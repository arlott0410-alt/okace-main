/**
 * Middleware: บล็อกการเข้าผ่านมือถือเมื่อ allow_mobile_access = false
 * อ่านค่าจาก app_settings (Supabase) พร้อม cache 60 วินาที
 * ถ้ามี KV binding (OKACE_KV) ใช้ distributed cache; ไม่มี则 fallback in-memory
 */

const KV_KEY_ALLOW_MOBILE = 'app_settings:allow_mobile_access';
const TTL_DEFAULT_SECONDS = 60;

export type Env = {
  SUPABASE_URL?: string;
  SUPABASE_ANON_KEY?: string;
  VITE_SUPABASE_URL?: string;
  VITE_SUPABASE_ANON_KEY?: string;
  /** Optional: KV namespace for edge-wide cache. If not bound, in-memory cache is used. */
  OKACE_KV?: KVNamespace;
};

function getEnv(env: Env): { base: string; apikey: string } | null {
  const base = env.SUPABASE_URL || env.VITE_SUPABASE_URL || '';
  const apikey = env.SUPABASE_ANON_KEY || env.VITE_SUPABASE_ANON_KEY || '';
  if (!base || !base.startsWith('http') || !apikey || apikey.length < 20) return null;
  return { base: base.replace(/\/$/, ''), apikey };
}

let memoryCached: { v: boolean | null; at: number } = { v: null, at: 0 };
const TTL_MS = TTL_DEFAULT_SECONDS * 1000;

function isMobileRequest(request: Request): boolean {
  const ua = request.headers.get('user-agent') || '';
  const secChUaMobile = request.headers.get('sec-ch-ua-mobile');
  if (secChUaMobile === '?1') return true;
  const mobileRegex = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini|Mobile|mobile/i;
  return mobileRegex.test(ua);
}

async function fetchAllowMobileFromSupabase(env: Env): Promise<boolean> {
  const cfg = getEnv(env);
  if (!cfg) return false;
  const url = `${cfg.base}/rest/v1/app_settings?key=eq.allow_mobile_access&select=value_bool`;
  try {
    const res = await fetch(url, {
      headers: {
        apikey: cfg.apikey,
        Authorization: `Bearer ${cfg.apikey}`,
        'Content-Type': 'application/json',
      },
    });
    if (!res.ok) return false;
    const data = (await res.json()) as unknown;
    return Array.isArray(data) && data[0]?.value_bool === true;
  } catch {
    return false;
  }
}

async function getAllowMobile(env: Env): Promise<boolean> {
  const now = Date.now();

  if (env.OKACE_KV) {
    try {
      const raw = await env.OKACE_KV.get(KV_KEY_ALLOW_MOBILE);
      if (raw !== null) {
        const v = raw === 'true';
        return v;
      }
    } catch {
      /* KV error: fall through to fetch and in-memory fallback */
    }
  }

  if (memoryCached.v !== null && now - memoryCached.at < TTL_MS) {
    return memoryCached.v;
  }

  const v = await fetchAllowMobileFromSupabase(env);
  memoryCached = { v, at: now };

  if (env.OKACE_KV) {
    try {
      await env.OKACE_KV.put(KV_KEY_ALLOW_MOBILE, v ? 'true' : 'false', { expirationTtl: TTL_DEFAULT_SECONDS });
    } catch {
      /* ignore; in-memory already set */
    }
  }

  return v;
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

  let res: Response;
  if (!isMobileRequest(request)) {
    res = await next();
  } else {
    const allow = await getAllowMobile(env);
    if (allow) {
      res = await next();
    } else {
      res = new Response(MOBILE_BLOCK_HTML, {
        status: 403,
        headers: {
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'no-store',
        },
      });
    }
  }

  if (new URL(request.url).pathname.startsWith('/api/')) {
    const h = new Headers(res.headers);
    h.set('Cache-Control', 'no-store');
    return new Response(res.body, { status: res.status, statusText: res.statusText, headers: h });
  }
  return res;
};
