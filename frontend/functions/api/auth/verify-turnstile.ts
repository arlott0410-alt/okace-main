/**
 * POST /api/auth/verify-turnstile
 * Body: { token: string }
 * Verifies Cloudflare Turnstile token. If TURNSTILE_SECRET_KEY or TURNSTILE_ENABLED not set, returns { ok: true } (no-op).
 */

const TURNSTILE_VERIFY_URL = 'https://challenges.cloudflare.com/turnstile/v0/siteverify';

type Env = {
  TURNSTILE_SECRET_KEY?: string;
  TURNSTILE_ENABLED?: string;
};

function isTurnstileEnabled(env: Env): boolean {
  return env.TURNSTILE_ENABLED === 'true' && !!env.TURNSTILE_SECRET_KEY && env.TURNSTILE_SECRET_KEY.length > 10;
}

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  if (!isTurnstileEnabled(env)) {
    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  }
  let body: { token?: string };
  try {
    body = (await request.json()) as { token?: string };
  } catch {
    return new Response(JSON.stringify({ ok: false, error: 'Invalid body' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
  }
  const token = typeof body?.token === 'string' ? body.token.trim() : '';
  if (!token || token.length > 2048) {
    return new Response(JSON.stringify({ ok: false, error: 'Missing or invalid token' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
  }
  try {
    const res = await fetch(TURNSTILE_VERIFY_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        secret: env.TURNSTILE_SECRET_KEY,
        response: token,
      }),
    });
    const data = (await res.json()) as { success?: boolean };
    const ok = data?.success === true;
    return new Response(JSON.stringify({ ok }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  } catch {
    return new Response(JSON.stringify({ ok: false }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  }
};
