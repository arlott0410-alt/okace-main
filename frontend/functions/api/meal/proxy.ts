/**
 * POST /api/meal/proxy
 * Body: { action: 'slots'|'book'|'cancel', ...params }
 * Forwards to Supabase RPC with user's JWT (so RPC runs as auth.uid()).
 * Replaces direct supabase.rpc() from frontend for get_meal_slots_unified, book_meal_break, cancel_meal_break.
 */

type Env = { SUPABASE_URL?: string; SUPABASE_ANON_KEY?: string; VITE_SUPABASE_URL?: string; VITE_SUPABASE_ANON_KEY?: string };

function getEnv(env: Env): { base: string; apikey: string } | { ok: false; message: string } {
  const base = env.SUPABASE_URL || env.VITE_SUPABASE_URL || '';
  const apikey = env.SUPABASE_ANON_KEY || env.VITE_SUPABASE_ANON_KEY || '';
  if (!base || !base.startsWith('http')) return { ok: false, message: 'Server configuration error' };
  if (!apikey || apikey.length < 20) return { ok: false, message: 'SUPABASE_ANON_KEY or VITE_SUPABASE_ANON_KEY required for meal proxy' };
  return { base, apikey };
}

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  const envCheck = getEnv(env);
  if ('message' in envCheck) {
    return new Response(JSON.stringify({ error: envCheck.message }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
  const { base, apikey } = envCheck;
  const auth = request.headers.get('Authorization');
  if (!auth?.startsWith('Bearer ')) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: { 'Content-Type': 'application/json' } });
  }
  let body: { action?: string; p_work_date?: string; p_round_key?: string; p_slot_start_ts?: string; p_slot_end_ts?: string; p_break_log_id?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
  }
  const action = body?.action;
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    apikey,
    Authorization: auth,
  };

  if (action === 'slots') {
    const p_work_date = body.p_work_date;
    if (!p_work_date) {
      return new Response(JSON.stringify({ error: 'Missing p_work_date' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
    }
    const res = await fetch(`${base}/rest/v1/rpc/get_meal_slots_unified`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ p_work_date }),
    });
    const data = await res.json().catch(() => null);
    return new Response(JSON.stringify(data ?? null), { status: res.ok ? 200 : 400, headers: { 'Content-Type': 'application/json' } });
  }

  if (action === 'book') {
    const { p_work_date, p_round_key, p_slot_start_ts, p_slot_end_ts } = body;
    if (!p_work_date || !p_round_key || !p_slot_start_ts || !p_slot_end_ts) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
    }
    const res = await fetch(`${base}/rest/v1/rpc/book_meal_break`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ p_work_date, p_round_key, p_slot_start_ts, p_slot_end_ts }),
    });
    const data = await res.json().catch(() => ({}));
    return new Response(JSON.stringify(data), { status: res.ok ? 200 : 400, headers: { 'Content-Type': 'application/json' } });
  }

  if (action === 'cancel') {
    const p_break_log_id = body.p_break_log_id;
    if (!p_break_log_id) {
      return new Response(JSON.stringify({ error: 'Missing p_break_log_id' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
    }
    const res = await fetch(`${base}/rest/v1/rpc/cancel_meal_break`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ p_break_log_id }),
    });
    const data = await res.json().catch(() => ({}));
    return new Response(JSON.stringify(data), { status: res.ok ? 200 : 400, headers: { 'Content-Type': 'application/json' } });
  }

  return new Response(JSON.stringify({ error: 'Unknown action' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
};
