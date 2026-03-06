/**
 * GET /api/cache/branches
 * Edge cache สำหรับรายการสาขา (active) — ลดการยิง Supabase
 * ต้องส่ง Authorization: Bearer <user JWT> (RLS)
 * Query: ?refresh=1 = ข้าม cache อัปเดตจาก Supabase แล้วเขียน KV ใหม่
 * ถ้าไม่มี OKACE_KV จะดึงจาก Supabase อย่างเดียว (ไม่พัง)
 */

const KV_KEY = 'cache:branches';
const TTL_SECONDS = 300; // 5 min
const SELECT = 'id,name,code,active,created_at,updated_at';

type Env = {
  SUPABASE_URL?: string;
  SUPABASE_ANON_KEY?: string;
  VITE_SUPABASE_URL?: string;
  VITE_SUPABASE_ANON_KEY?: string;
  OKACE_KV?: KVNamespace;
};

function getEnv(env: Env): { base: string; apikey: string } | null {
  const base = (env.SUPABASE_URL || env.VITE_SUPABASE_URL || '').replace(/\/$/, '');
  const apikey = env.SUPABASE_ANON_KEY || env.VITE_SUPABASE_ANON_KEY || '';
  if (!base || !base.startsWith('http') || !apikey || apikey.length < 20) return null;
  return { base, apikey };
}

export const onRequestGet: PagesFunction<Env> = async ({ request, env }) => {
  const auth = request.headers.get('Authorization');
  if (!auth?.startsWith('Bearer ')) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: { 'Content-Type': 'application/json' } });
  }
  const cfg = getEnv(env);
  if (!cfg) {
    return new Response(JSON.stringify({ error: 'Server configuration error' }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }

  const url = new URL(request.url);
  const forceRefresh = url.searchParams.get('refresh') === '1';

  if (env.OKACE_KV && !forceRefresh) {
    try {
      const raw = await env.OKACE_KV.get(KV_KEY);
      if (raw !== null) {
        return new Response(raw, {
          status: 200,
          headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
        });
      }
    } catch {
      /* fall through to fetch */
    }
  }

  const res = await fetch(`${cfg.base}/rest/v1/branches?active=eq.true&select=${SELECT}&order=name.asc`, {
    headers: {
      apikey: cfg.apikey,
      Authorization: auth,
      'Content-Type': 'application/json',
    },
  });
  if (!res.ok) {
    const body = await res.text();
    return new Response(JSON.stringify({ error: 'Upstream error', detail: body }), { status: res.status, headers: { 'Content-Type': 'application/json' } });
  }
  const data = await res.json();

  if (env.OKACE_KV) {
    try {
      await env.OKACE_KV.put(KV_KEY, JSON.stringify(data), { expirationTtl: TTL_SECONDS });
    } catch {
      /* ignore */
    }
  }

  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
};
