/**
 * Cloudflare Pages Function: สร้างผู้ใช้หลายคนพร้อมกัน (เฉพาะ admin)
 * POST /api/admin/create-users
 * Body: { usernames: string[], password, role?, default_branch_id?, default_shift_id? }
 */

const INTERNAL_EMAIL_SUFFIX = '@users.okace.local';

function usernameToInternalEmail(username: string): string {
  const safe = username.trim().toLowerCase().replace(/\s+/g, '.').replace(/[^a-z0-9._-]/g, '');
  return (safe || 'user') + INTERNAL_EMAIL_SUFFIX;
}

type Env = {
  SUPABASE_URL?: string;
  SUPABASE_SERVICE_ROLE_KEY?: string;
  /** Optional: Durable Object namespace for cross-isolate idempotency. If not set, no idempotency cache. */
  OKACE_IDEMPOTENCY?: DurableObjectNamespace;
};

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
}

async function getUserIdFromJwt(request: Request, supabaseUrl: string, serviceRoleKey: string): Promise<string | null> {
  const auth = request.headers.get('Authorization');
  if (!auth?.startsWith('Bearer ')) return null;
  const token = auth.slice(7);
  const res = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${token}`, apikey: serviceRoleKey },
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

/** Batch check: returns Set of internal emails and Set of display_names (lowercase) that already exist. */
async function batchGetTakenUsernamesAndEmails(
  env: Env,
  usernames: string[],
  internalEmails: string[]
): Promise<{ takenEmails: Set<string>; takenDisplayNamesLower: Set<string> }> {
  const url = env.SUPABASE_URL;
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  const takenEmails = new Set<string>();
  const takenDisplayNamesLower = new Set<string>();
  if (!url || !key || (internalEmails.length === 0 && usernames.length === 0)) return { takenEmails, takenDisplayNamesLower };

  const orParts: string[] = [];
  for (const e of internalEmails) orParts.push(`email.eq.${encodeURIComponent(e)}`);
  for (const u of usernames) orParts.push(`display_name.ilike.${encodeURIComponent(escapeIlike(u.trim()))}`);
  if (orParts.length === 0) return { takenEmails, takenDisplayNamesLower };
  const orClause = orParts.join(',');

  const res = await fetch(
    `${url}/rest/v1/profiles?or=(${orClause})&select=email,display_name`,
    { headers: { apikey: key, Authorization: `Bearer ${key}` } }
  );
  if (!res.ok) return { takenEmails, takenDisplayNamesLower };
  const data = (await res.json()) as { email?: string; display_name?: string }[];
  if (!Array.isArray(data)) return { takenEmails, takenDisplayNamesLower };
  for (const row of data) {
    if (row.email) takenEmails.add(row.email);
    if (row.display_name) takenDisplayNamesLower.add(String(row.display_name).trim().toLowerCase());
  }
  return { takenEmails, takenDisplayNamesLower };
}

function normalizeAuthError(data: unknown): string {
  const msg = (data && typeof data === 'object' && ('msg' in data || 'message' in data || 'error_description' in data))
    ? String((data as { msg?: string; message?: string; error_description?: string }).msg ?? (data as { message?: string }).message ?? (data as { error_description?: string }).error_description ?? '')
    : '';
  const detail = (data && typeof data === 'object' && 'details' in data) ? String((data as { details?: string }).details) : '';
  let out = (msg || 'สร้างผู้ใช้ไม่สำเร็จ').trim();
  if (detail) out += ` (${detail})`;
  if (/database error|constraint|profiles.*branch/i.test(out)) {
    out += ' — แนะนำ: รัน migration 012_handle_new_user_branch_fallback.sql ใน Supabase และตรวจสอบว่ามีสาขาอย่างน้อย 1 แห่ง';
  }
  return out;
}

async function createAuthUser(env: Env, email: string, password: string, displayName: string): Promise<{ id: string; email: string } | { error: string }> {
  const url = env.SUPABASE_URL;
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return { error: 'Server configuration error' };
  const res = await fetch(`${url}/auth/v1/admin/users`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: key, Authorization: `Bearer ${key}` },
    body: JSON.stringify({ email, password, email_confirm: true, user_metadata: { display_name: displayName } }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    return { error: normalizeAuthError(data) };
  }
  const id = data?.id ?? data?.user?.id;
  if (!id) return { error: 'สร้างผู้ใช้ไม่สำเร็จ' };
  return { id, email: data?.email ?? data?.user?.email ?? email };
}

async function updateProfile(env: Env, userId: string, updates: { role: string; display_name?: string; default_branch_id?: string | null; default_shift_id?: string | null }): Promise<{ ok: boolean; error?: string }> {
  const url = env.SUPABASE_URL;
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return { ok: false, error: 'Server configuration error' };
  const payload: Record<string, unknown> = { role: updates.role };
  if (updates.display_name !== undefined) payload.display_name = updates.display_name;
  if (updates.default_branch_id !== undefined) payload.default_branch_id = updates.default_branch_id || null;
  if (updates.default_shift_id !== undefined) payload.default_shift_id = updates.default_shift_id || null;
  const res = await fetch(`${url}/rest/v1/profiles?id=eq.${userId}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', apikey: key, Authorization: `Bearer ${key}`, Prefer: 'return=minimal' },
    body: JSON.stringify(payload),
  });
  if (res.ok) return { ok: true };
  const data = await res.json().catch(() => ({}));
  const msg = (data && typeof data === 'object' && 'message' in data) ? String((data as { message?: string }).message) : res.statusText || 'อัปเดต profile ไม่สำเร็จ';
  return { ok: false, error: msg };
}

function checkEnv(env: Env): { ok: true } | { ok: false; message: string } {
  if (!env.SUPABASE_URL || !env.SUPABASE_URL.startsWith('http')) {
    return { ok: false, message: 'Server configuration error: ตั้งค่า SUPABASE_URL ใน Cloudflare Pages' };
  }
  if (!env.SUPABASE_SERVICE_ROLE_KEY || env.SUPABASE_SERVICE_ROLE_KEY.length < 20) {
    return { ok: false, message: 'Server configuration error: ตั้งค่า SUPABASE_SERVICE_ROLE_KEY ใน Cloudflare Pages' };
  }
  return { ok: true };
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
        /* no idempotency */
      }
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
      const msg = JSON.stringify({ message: 'โทเค็นไม่ถูกต้องหรือหมดอายุ กรุณาออกจากระบบแล้วล็อกอินใหม่' });
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

    let body: {
      usernames?: string[];
      password?: string;
      role?: string;
      default_branch_id?: string;
      default_shift_id?: string;
    };
    try {
      body = JSON.parse(bodyText) as typeof body;
    } catch {
      body = {};
    }
    const rawNames = Array.isArray(body?.usernames) ? body.usernames : [];
    const usernames = rawNames.map((u) => (typeof u === 'string' ? u.trim() : '')).filter(Boolean);
    const password = typeof body?.password === 'string' ? body.password : '';
    const allowedRoles = ['admin', 'manager', 'instructor_head', 'instructor', 'staff'] as const;
    let appRole: string = allowedRoles.includes(body?.role as typeof allowedRoles[number]) ? body!.role : 'staff';
    let default_branch_id: string | null = typeof body?.default_branch_id === 'string' && body.default_branch_id ? body.default_branch_id : null;
    const default_shift_id = typeof body?.default_shift_id === 'string' && body.default_shift_id ? body.default_shift_id : null;

    if (caller.role === 'instructor_head') {
      if (appRole === 'admin' || appRole === 'instructor_head' || appRole === 'manager') {
        appRole = 'staff';
      }
      /* หัวหน้าผู้สอนสามารถสร้างผู้ใช้ในแผนกอื่นได้ — ใช้ default_branch_id จาก body (ไม่บังคับเป็นแผนกของหัวหน้า) */
    }

    if (caller.role === 'manager') {
      if (appRole === 'admin' || appRole === 'manager') {
        appRole = 'staff';
      }
    }

    if (usernames.length === 0) {
      const msg = JSON.stringify({ message: 'กรุณากรอกชื่อผู้ใช้อย่างน้อย 1 รายการ' });
      await ensureIdempotencyStored(env, idempotencyKey, usedDo, 400, msg);
      return new Response(msg, { status: 400, headers: { 'Content-Type': 'application/json' } });
    }
    if (!password || password.length < 6) {
      const msg = JSON.stringify({ message: 'รหัสผ่านต้องไม่ต่ำกว่า 6 ตัว' });
      await ensureIdempotencyStored(env, idempotencyKey, usedDo, 400, msg);
      return new Response(msg, { status: 400, headers: { 'Content-Type': 'application/json' } });
    }

    const MAX_BULK = 50;
    const toProcess = usernames.slice(0, MAX_BULK);
    if (usernames.length > MAX_BULK) {
      const msg = JSON.stringify({ message: `รับได้สูงสุด ${MAX_BULK} คนต่อครั้ง — กรุณาส่ง ${usernames.length - MAX_BULK} คนในรอบถัดไป` });
      await ensureIdempotencyStored(env, idempotencyKey, usedDo, 400, msg);
      return new Response(msg, { status: 400, headers: { 'Content-Type': 'application/json' } });
    }

    const internalEmails = toProcess.map((u) => usernameToInternalEmail(u));
    const { takenEmails, takenDisplayNamesLower } = await batchGetTakenUsernamesAndEmails(env, toProcess, internalEmails);

    const created: { id: string; username: string }[] = [];
    const skipped_duplicates: string[] = [];
    const failed: { username: string; reason: string }[] = [];

    for (let i = 0; i < toProcess.length; i++) {
      const username = toProcess[i];
      const internalEmail = internalEmails[i];
      const taken = takenEmails.has(internalEmail) || takenDisplayNamesLower.has(username.trim().toLowerCase());
      if (taken) {
        skipped_duplicates.push(username);
        continue;
      }
      const result = await createAuthUser(env, internalEmail, password, username);
      if ('error' in result) {
        failed.push({ username, reason: result.error });
        continue;
      }
      let updateResult = await updateProfile(env, result.id, {
        role: appRole,
        display_name: username,
        default_branch_id,
        default_shift_id,
      });
      if (!updateResult.ok) {
        await new Promise((r) => setTimeout(r, 400));
        updateResult = await updateProfile(env, result.id, {
          role: appRole,
          display_name: username,
          default_branch_id,
          default_shift_id,
        });
      }
      if (!updateResult.ok) {
        failed.push({ username, reason: updateResult.error ?? 'อัปเดตข้อมูลสมาชิกไม่สำเร็จ' });
        continue;
      }
      created.push({ id: result.id, username });
    }

    const okBody = JSON.stringify({ created, skipped_duplicates, failed });
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
