/**
 * POST /api/shifts/proxy
 * Body: { action: 'apply-bulk'|'apply-paired'|'cancel-scheduled'|'update-scheduled', ...params }
 * Forwards to Supabase RPC with user's JWT. Replaces direct supabase.rpc() from frontend.
 */

type Env = { SUPABASE_URL?: string; SUPABASE_ANON_KEY?: string; VITE_SUPABASE_URL?: string; VITE_SUPABASE_ANON_KEY?: string };

function getEnv(env: Env): { base: string; apikey: string } | { ok: false; message: string } {
  const base = env.SUPABASE_URL || env.VITE_SUPABASE_URL || '';
  const apikey = env.SUPABASE_ANON_KEY || env.VITE_SUPABASE_ANON_KEY || '';
  if (!base || !base.startsWith('http')) return { ok: false, message: 'Server configuration error' };
  if (!apikey || apikey.length < 20) return { ok: false, message: 'SUPABASE_ANON_KEY or VITE_SUPABASE_ANON_KEY required for shifts proxy' };
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
  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
  }
  const action = body?.action as string | undefined;
  const headers: Record<string, string> = { 'Content-Type': 'application/json', apikey, Authorization: auth };

  const rpc = async (name: string, params: Record<string, unknown>) => {
    const res = await fetch(`${base}/rest/v1/rpc/${name}`, { method: 'POST', headers, body: JSON.stringify(params) });
    const data = await res.json().catch(() => ({}));
    return new Response(JSON.stringify(data), { status: res.ok ? 200 : 400, headers: { 'Content-Type': 'application/json' } });
  };

  if (action === 'apply-bulk') {
    return rpc('apply_bulk_assignment', {
      p_employee_ids: body.p_employee_ids,
      p_start_date: body.p_start_date,
      p_end_date: body.p_end_date,
      p_to_branch_id: body.p_to_branch_id,
      p_to_shift_id: body.p_to_shift_id,
      p_reason: body.p_reason ?? null,
    });
  }
  if (action === 'apply-paired') {
    return rpc('apply_paired_swap', {
      p_branch_id: body.p_branch_id,
      p_start_date: body.p_start_date,
      p_end_date: body.p_end_date,
      p_assignments: body.p_assignments,
      p_reason: body.p_reason ?? null,
    });
  }
  if (action === 'cancel-scheduled') {
    return rpc('cancel_scheduled_shift_change', { p_type: body.p_type, p_id: body.p_id });
  }
  if (action === 'update-scheduled') {
    return rpc('update_scheduled_shift_change', {
      p_type: body.p_type,
      p_id: body.p_id,
      p_new_start_date: body.p_new_start_date,
      p_new_to_shift_id: body.p_new_to_shift_id ?? null,
    });
  }

  return new Response(JSON.stringify({ error: 'Unknown action' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
};
