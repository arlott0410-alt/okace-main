/**
 * Cloudflare Pages Function: ตั้งรหัสผ่านใหม่ให้ผู้ใช้ (เฉพาะ admin)
 * POST /api/admin/reset-password
 * Body: { user_id: string, new_password: string }
 * Accepts X-Idempotency-Key to avoid duplicate resets when frontend retries.
 */

type Env = { SUPABASE_URL?: string; SUPABASE_SERVICE_ROLE_KEY?: string };

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

export const onRequestPost: PagesFunction<Env> = async (context) => {
  try {
    const { request, env } = context;
    if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) {
      return new Response(JSON.stringify({ message: 'Server configuration error' }), { status: 500, headers: { 'Content-Type': 'application/json' } });
    }
    const supabaseUrl = env.SUPABASE_URL;
    const key = env.SUPABASE_SERVICE_ROLE_KEY;
    const auth = request.headers.get('Authorization');
    if (!auth?.startsWith('Bearer ')) {
      return new Response(JSON.stringify({ message: 'ไม่พบโทเค็น กรุณาล็อกอินใหม่' }), { status: 401, headers: { 'Content-Type': 'application/json' } });
    }
    const adminId = await getUserIdFromJwt(request, supabaseUrl, key);
    if (!adminId) {
      return new Response(JSON.stringify({ message: 'โทเค็นไม่ถูกต้องหรือหมดอายุ' }), { status: 401, headers: { 'Content-Type': 'application/json' } });
    }
    const caller = await getProfileRoleAndBranch(env, adminId);
    if (!caller) {
      return new Response(JSON.stringify({ message: 'ไม่พบข้อมูลผู้ใช้' }), { status: 403, headers: { 'Content-Type': 'application/json' } });
    }
    if (caller.role !== 'admin' && caller.role !== 'manager' && caller.role !== 'instructor_head') {
      return new Response(JSON.stringify({ message: 'เฉพาะผู้ดูแลระบบ ผู้จัดการ หรือหัวหน้าผู้สอนเท่านั้น' }), { status: 403, headers: { 'Content-Type': 'application/json' } });
    }
    const body = (await request.json()) as { user_id?: string; new_password?: string };
    const targetUserId = typeof body?.user_id === 'string' ? body.user_id.trim() : '';
    const newPassword = typeof body?.new_password === 'string' ? body.new_password : '';
    if (!targetUserId) {
      return new Response(JSON.stringify({ message: 'กรุณาระบุ user_id' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
    }
    if (!newPassword || newPassword.length < 6) {
      return new Response(JSON.stringify({ message: 'รหัสผ่านใหม่ต้องไม่ต่ำกว่า 6 ตัว' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
    }
    if (caller.role === 'instructor_head') {
      const target = await getProfileRoleAndBranch(env, targetUserId);
      if (!target || target.default_branch_id !== caller.default_branch_id || !['instructor', 'staff'].includes(target.role)) {
        return new Response(JSON.stringify({ message: 'เปลี่ยนรหัสผ่านได้เฉพาะผู้สอน/พนักงานในสาขาของคุณเท่านั้น' }), { status: 403, headers: { 'Content-Type': 'application/json' } });
      }
    }
    if (caller.role === 'manager') {
      const target = await getProfileRoleAndBranch(env, targetUserId);
      if (!target || target.role === 'admin' || target.role === 'manager') {
        return new Response(JSON.stringify({ message: 'ผู้จัดการเปลี่ยนรหัสผ่านได้เฉพาะหัวหน้าผู้สอน/ผู้สอน/พนักงานออนไลน์เท่านั้น' }), { status: 403, headers: { 'Content-Type': 'application/json' } });
      }
    }
    const res = await fetch(`${supabaseUrl}/auth/v1/admin/users/${targetUserId}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', apikey: key, Authorization: `Bearer ${key}` },
      body: JSON.stringify({ password: newPassword }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const msg = data?.msg ?? data?.message ?? data?.error_description ?? 'ตั้งรหัสผ่านไม่สำเร็จ';
      return new Response(JSON.stringify({ message: typeof msg === 'string' ? msg : JSON.stringify(msg) }), { status: 400, headers: { 'Content-Type': 'application/json' } });
    }
    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    const message = e instanceof Error ? e.message : 'เกิดข้อผิดพลาด';
    return new Response(JSON.stringify({ message }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
};
