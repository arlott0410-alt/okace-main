/**
 * GET /api/auth/resolve-email?login_name=xxx
 * Returns email for login (replaces get_email_for_login RPC from frontend).
 * No auth required. Uses service role to query profiles.
 */

type Env = { SUPABASE_URL?: string; SUPABASE_SERVICE_ROLE_KEY?: string };

function checkEnv(env: Env): { ok: true } | { ok: false; message: string } {
  if (!env.SUPABASE_URL || !env.SUPABASE_URL.startsWith('http'))
    return { ok: false, message: 'Server configuration error' };
  if (!env.SUPABASE_SERVICE_ROLE_KEY || env.SUPABASE_SERVICE_ROLE_KEY.length < 20)
    return { ok: false, message: 'Server configuration error' };
  return { ok: true };
}

export const onRequestGet: PagesFunction<Env> = async ({ request, env }) => {
  const envCheck = checkEnv(env);
  if (!envCheck.ok) {
    return new Response(JSON.stringify({ error: envCheck.message }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
  const url = new URL(request.url);
  const loginName = url.searchParams.get('login_name')?.trim();
  if (!loginName) {
    return new Response(JSON.stringify({ error: 'Missing login_name' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
  }
  const key = env.SUPABASE_SERVICE_ROLE_KEY!;
  const base = env.SUPABASE_URL!;
  // Call existing DB function (single source of truth for trim/lower match)
  const res = await fetch(`${base}/rest/v1/rpc/get_email_for_login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: key, Authorization: `Bearer ${key}` },
    body: JSON.stringify({ login_name: loginName }),
  });
  if (!res.ok) {
    return new Response(JSON.stringify({ error: 'Lookup failed' }), { status: 502, headers: { 'Content-Type': 'application/json' } });
  }
  const email = (await res.json()) as string | null;
  return new Response(JSON.stringify({ email: email ?? null }), { status: 200, headers: { 'Content-Type': 'application/json' } });
};
