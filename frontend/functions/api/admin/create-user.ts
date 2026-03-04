/**
 * Cloudflare Pages Function: สร้างผู้ใช้ใหม่ (เฉพาะ admin)
 * POST /api/admin/create-user
 * Body: { username, password, role, default_branch_id?, default_shift_id? }
 * หลังบ้านสร้างอีเมลภายใน (username@users.okace.local) ให้ Auth ใช้ ผู้ใช้ล็อกอินด้วยชื่อผู้ใช้เท่านั้น
 */

const INTERNAL_EMAIL_SUFFIX = '@users.okace.local';

function usernameToInternalEmail(username: string): string {
  const safe = username.trim().toLowerCase().replace(/\s+/g, '.').replace(/[^a-z0-9._-]/g, '');
  return (safe || 'user') + INTERNAL_EMAIL_SUFFIX;
}

type Env = {
  SUPABASE_URL?: string;
  SUPABASE_SERVICE_ROLE_KEY?: string;
  /** Optional: Durable Object namespace for cross-isolate idempotency. If not set, in-memory cache is used. */
  OKACE_IDEMPOTENCY?: DurableObjectNamespace;
};

async function getUserIdFromJwt(request: Request, supabaseUrl: string, serviceRoleKey: string): Promise<string | null> {
  const auth = request.headers.get('Authorization');
  if (!auth?.startsWith('Bearer ')) return null;
  const token = auth.slice(7);
  const res = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: {
      Authorization: `Bearer ${token}`,
      apikey: serviceRoleKey,
    },
  });
  if (!res.ok) return null;
  const data = await res.json();
  return data?.id ?? null;
}

async function getProfileRole(env: Env, userId: string): Promise<string | null> {
  const p = await getProfileRoleAndBranch(env, userId);
  return p?.role ?? null;
}

async function getProfileRoleAndBranch(env: Env, userId: string): Promise<{ role: string; default_branch_id: string | null } | null> {
  const url = env.SUPABASE_URL;
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;
  const res = await fetch(`${url}/rest/v1/profiles?id=eq.${userId}&select=role,default_branch_id`, {
    headers: { apikey: key, Authorization: `Bearer ${key}` },
  });
  if (!res.ok) return null;
  const data = await res.json();
  const row = Array.isArray(data) && data[0] ? data[0] : null;
  return row ? { role: row.role, default_branch_id: row.default_branch_id ?? null } : null;
}

function escapeIlike(value: string): string {
  return value.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
}

async function isUsernameOrEmailTaken(env: Env, username: string, internalEmail: string): Promise<boolean> {
  const url = env.SUPABASE_URL;
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return true;
  const ilikeValue = escapeIlike(username.trim());
  const res = await fetch(
    `${url}/rest/v1/profiles?or=(email.eq.${encodeURIComponent(internalEmail)},display_name.ilike.${encodeURIComponent(ilikeValue)})&select=id`,
    {
      headers: { apikey: key, Authorization: `Bearer ${key}` },
    }
  );
  if (!res.ok) return true;
  const data = await res.json();
  return Array.isArray(data) && data.length > 0;
}

async function createAuthUser(env: Env, email: string, password: string, displayName: string): Promise<{ id: string; email: string } | { error: string }> {
  const url = env.SUPABASE_URL;
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return { error: 'Server configuration error' };
  const res = await fetch(`${url}/auth/v1/admin/users`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: key,
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify({
      email,
      password,
      email_confirm: true,
      user_metadata: { display_name: displayName },
    }),
  });
  const data = await res.json();
  if (!res.ok) {
    const msg = data?.msg ?? data?.message ?? data?.error_description ?? 'สร้างผู้ใช้ไม่สำเร็จ';
    return { error: typeof msg === 'string' ? msg : JSON.stringify(msg) };
  }
  const id = data?.id ?? data?.user?.id;
  const outEmail = data?.email ?? data?.user?.email ?? email;
  if (!id) return { error: 'สร้างผู้ใช้ไม่สำเร็จ' };
  return { id, email: outEmail };
}

async function updateProfile(env: Env, userId: string, updates: { role: string; display_name?: string; default_branch_id?: string | null; default_shift_id?: string | null }): Promise<boolean> {
  const url = env.SUPABASE_URL;
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return false;
  const payload: Record<string, unknown> = { role: updates.role };
  if (updates.display_name !== undefined) payload.display_name = updates.display_name;
  if (updates.default_branch_id !== undefined) payload.default_branch_id = updates.default_branch_id || null;
  if (updates.default_shift_id !== undefined) payload.default_shift_id = updates.default_shift_id || null;
  const res = await fetch(`${url}/rest/v1/profiles?id=eq.${userId}`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      apikey: key,
      Authorization: `Bearer ${key}`,
      Prefer: 'return=minimal',
    },
    body: JSON.stringify(payload),
  });
  return res.ok;
}

function checkEnv(env: Env): { ok: true } | { ok: false; message: string } {
  if (!env.SUPABASE_URL || !env.SUPABASE_URL.startsWith('http')) {
    return { ok: false, message: 'Server configuration error: ตั้งค่า SUPABASE_URL ใน Cloudflare Pages > Settings > Environment variables (สำหรับ Functions)' };
  }
  if (!env.SUPABASE_SERVICE_ROLE_KEY || env.SUPABASE_SERVICE_ROLE_KEY.length < 20) {
    return { ok: false, message: 'Server configuration error: ตั้งค่า SUPABASE_SERVICE_ROLE_KEY ใน Cloudflare Pages > Settings > Environment variables (สำหรับ Functions)' };
  }
  return { ok: true };
}

/** In-memory idempotency fallback when OKACE_IDEMPOTENCY is not bound. */
const idempotencyCache = new Map<string, { status: number; body: string }>();

function hashPayload(body: string): string {
  let h = 0;
  for (let i = 0; i < body.length; i++) {
    const c = body.charCodeAt(i);
    h = ((h << 5) - h) + c | 0;
  }
  return String(h >>> 0);
}

async function ensureIdempotencyStored(
  env: Env,
  idempotencyKey: string,
  usedDo: boolean,
  status: number,
  body: string
): Promise<void> {
  if (usedDo && env.OKACE_IDEMPOTENCY) {
    try {
      const { idempotencyStore } = await import('../../_idempotency');
      await idempotencyStore(env.OKACE_IDEMPOTENCY, idempotencyKey, status, body);
    } catch {
      /* ignore */
    }
    return;
  }
  if (status >= 500) return;
  idempotencyCache.set(idempotencyKey, { status, body });
}

export const onRequestPost: PagesFunction<Env> = async (context) => {
  const { request, env } = context;
  let idempotencyKey = '';
  let usedDo = false;
  try {
    const bodyText = await request.clone().text();
    idempotencyKey = request.headers.get('X-Idempotency-Key') ?? 'hash-' + hashPayload(bodyText);

    if (env.OKACE_IDEMPOTENCY) {
      try {
        const { idempotencyCheckOrReserve } = await import('../../_idempotency');
        const result = await idempotencyCheckOrReserve(env.OKACE_IDEMPOTENCY, idempotencyKey);
        if (result.hit === true) {
          return new Response(result.body, { status: result.status, headers: { 'Content-Type': 'application/json' } });
        }
        usedDo = true;
      } catch {
        /* fallback to in-memory */
      }
    } else if (idempotencyCache.has(idempotencyKey)) {
      const cached = idempotencyCache.get(idempotencyKey)!;
      return new Response(cached.body, { status: cached.status, headers: { 'Content-Type': 'application/json' } });
    }

    const envCheck = checkEnv(env);
    if (!envCheck.ok) {
      return new Response(JSON.stringify({ message: envCheck.message }), { status: 500, headers: { 'Content-Type': 'application/json' } });
    }
    const supabaseUrl = env.SUPABASE_URL!;
    const serviceRoleKey = env.SUPABASE_SERVICE_ROLE_KEY ?? '';
    const auth = request.headers.get('Authorization');
    if (!auth?.startsWith('Bearer ')) {
      const msg = JSON.stringify({ message: 'ไม่พบโทเค็น กรุณาล็อกอินใหม่' });
      await ensureIdempotencyStored(env, idempotencyKey, usedDo, 401, msg);
      return new Response(msg, { status: 401, headers: { 'Content-Type': 'application/json' } });
    }
    const userId = await getUserIdFromJwt(request, supabaseUrl, serviceRoleKey);
    if (!userId) {
      const msg = JSON.stringify({ message: 'โทเค็นไม่ถูกต้องหรือหมดอายุ กรุณาออกจากระบบแล้วล็อกอินใหม่ (ถ้าตั้งค่า env แล้วยังไม่ได้: ตรวจสอบว่า SUPABASE_URL ใน Cloudflare Pages = URL โปรเจกต์ Supabase เดียวกับที่ใช้ในแอป)' });
      await ensureIdempotencyStored(env, idempotencyKey, usedDo, 401, msg);
      return new Response(msg, { status: 401, headers: { 'Content-Type': 'application/json' } });
    }
    const caller = await getProfileRoleAndBranch(env, userId);
    if (!caller) {
      const msg = JSON.stringify({ message: 'ไม่พบข้อมูลผู้ใช้' });
      await ensureIdempotencyStored(env, idempotencyKey, usedDo, 403, msg);
      return new Response(msg, { status: 403, headers: { 'Content-Type': 'application/json' } });
    }
    if (caller.role !== 'admin' && caller.role !== 'manager' && caller.role !== 'instructor_head') {
      const msg = JSON.stringify({ message: 'เฉพาะผู้ดูแลระบบ ผู้จัดการ หรือหัวหน้าผู้สอนเท่านั้น' });
      await ensureIdempotencyStored(env, idempotencyKey, usedDo, 403, msg);
      return new Response(msg, { status: 403, headers: { 'Content-Type': 'application/json' } });
    }
    let body: { username?: string; password?: string; role?: string; default_branch_id?: string; default_shift_id?: string };
    try {
      body = JSON.parse(bodyText) as typeof body;
    } catch {
      body = {};
    }
    if (!body || typeof body !== 'object') {
      const err = JSON.stringify({ message: 'Invalid body' });
      await ensureIdempotencyStored(env, idempotencyKey, usedDo, 400, err);
      return new Response(err, { status: 400, headers: { 'Content-Type': 'application/json' } });
    }
    const username = typeof body?.username === 'string' ? body.username.trim() : '';
    const password = typeof body?.password === 'string' ? body.password : '';
    const allowedRoles = ['admin', 'manager', 'instructor_head', 'instructor', 'staff'] as const;
    let appRole: string = allowedRoles.includes(body?.role as typeof allowedRoles[number]) ? body!.role : 'staff';
    let default_branch_id: string | null = typeof body?.default_branch_id === 'string' && body.default_branch_id ? body.default_branch_id : null;
    const default_shift_id = typeof body?.default_shift_id === 'string' && body.default_shift_id ? body.default_shift_id : null;

    if (caller.role === 'instructor_head') {
      if (!caller.default_branch_id) {
        const msg = JSON.stringify({ message: 'หัวหน้าผู้สอนต้องมีสาขาประจำ' });
        await ensureIdempotencyStored(env, idempotencyKey, usedDo, 403, msg);
        return new Response(msg, { status: 403, headers: { 'Content-Type': 'application/json' } });
      }
      if (appRole === 'admin' || appRole === 'instructor_head' || appRole === 'manager') {
        const msg = JSON.stringify({ message: 'หัวหน้าผู้สอนสร้างได้เฉพาะบทบาท ผู้สอน หรือ พนักงานออนไลน์' });
        await ensureIdempotencyStored(env, idempotencyKey, usedDo, 403, msg);
        return new Response(msg, { status: 403, headers: { 'Content-Type': 'application/json' } });
      }
      default_branch_id = caller.default_branch_id;
    }

    if (caller.role === 'manager') {
      if (appRole === 'admin' || appRole === 'manager') {
        const msg = JSON.stringify({ message: 'ผู้จัดการสร้างได้เฉพาะบทบาท หัวหน้าผู้สอน ผู้สอน หรือ พนักงานออนไลน์' });
        await ensureIdempotencyStored(env, idempotencyKey, usedDo, 403, msg);
        return new Response(msg, { status: 403, headers: { 'Content-Type': 'application/json' } });
      }
    }

    if (!username) {
      const msg = JSON.stringify({ message: 'กรุณากรอกชื่อผู้ใช้' });
      await ensureIdempotencyStored(env, idempotencyKey, usedDo, 400, msg);
      return new Response(msg, { status: 400, headers: { 'Content-Type': 'application/json' } });
    }
    if (!password || password.length < 6) {
      const msg = JSON.stringify({ message: 'รหัสผ่านต้องไม่ต่ำกว่า 6 ตัว' });
      await ensureIdempotencyStored(env, idempotencyKey, usedDo, 400, msg);
      return new Response(msg, { status: 400, headers: { 'Content-Type': 'application/json' } });
    }

    const internalEmail = usernameToInternalEmail(username);
    const taken = await isUsernameOrEmailTaken(env, username, internalEmail);
    if (taken) {
      const msg = JSON.stringify({ message: 'ชื่อผู้ใช้นี้มีในระบบแล้ว' });
      await ensureIdempotencyStored(env, idempotencyKey, usedDo, 400, msg);
      return new Response(msg, { status: 400, headers: { 'Content-Type': 'application/json' } });
    }

    const result = await createAuthUser(env, internalEmail, password, username);
    if ('error' in result) {
      const msg = JSON.stringify({ message: result.error });
      await ensureIdempotencyStored(env, idempotencyKey, usedDo, 400, msg);
      return new Response(msg, { status: 400, headers: { 'Content-Type': 'application/json' } });
    }
    let updated = await updateProfile(env, result.id, {
      role: appRole,
      display_name: username,
      default_branch_id,
      default_shift_id,
    });
    if (!updated) {
      await new Promise((r) => setTimeout(r, 600));
      updated = await updateProfile(env, result.id, {
        role: appRole,
        display_name: username,
        default_branch_id,
        default_shift_id,
      });
    }
    const okBody = JSON.stringify({ id: result.id, username });
    await ensureIdempotencyStored(env, idempotencyKey, usedDo, 200, okBody);
    return new Response(okBody, { status: 200, headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    const message = e instanceof Error ? e.message : 'เกิดข้อผิดพลาด';
    const body = JSON.stringify({ message });
    if (idempotencyKey) {
      await ensureIdempotencyStored(env, idempotencyKey, usedDo, 500, body);
    }
    return new Response(body, { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
};
