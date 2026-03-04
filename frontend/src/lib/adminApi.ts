import { getApiBase } from './supabase';
import { supabase } from './supabase';

export type AppRole = 'admin' | 'manager' | 'instructor_head' | 'instructor' | 'staff';

export interface CreateUserBody {
  username: string;
  password: string;
  role?: AppRole;
  default_branch_id?: string | null;
  default_shift_id?: string | null;
}

export async function createUser(body: CreateUserBody): Promise<{ id: string; username: string }> {
  const base = getApiBase();
  await supabase.auth.refreshSession();
  const { data: { session } } = await supabase.auth.getSession();
  const token = session?.access_token ?? '';
  if (!token) {
    throw new Error('กรุณาล็อกอินใหม่ก่อนสร้างผู้ใช้ (โทเค็นไม่พบหรือหมดอายุ)');
  }
  const idemKey = typeof crypto !== 'undefined' && crypto.randomUUID ? crypto.randomUUID() : `cu-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const res = await fetch(`${base}/api/admin/create-user`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}`, 'X-Idempotency-Key': idemKey },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const msg = (data as { message?: string }).message;
    if (res.status === 401) {
      throw new Error(msg || 'โทเค็นไม่ถูกต้องหรือหมดอายุ กรุณาออกจากระบบแล้วล็อกอินใหม่');
    }
    throw new Error(msg || 'สร้างผู้ใช้ไม่สำเร็จ');
  }
  return data as { id: string; username: string };
}

export interface CreateUsersBody {
  usernames: string[];
  password: string;
  role?: AppRole;
  default_branch_id?: string | null;
  default_shift_id?: string | null;
}

export interface CreateUsersResult {
  created: { id: string; username: string }[];
  skipped_duplicates: string[];
  failed: { username: string; reason: string }[];
}

export async function createUsers(body: CreateUsersBody): Promise<CreateUsersResult> {
  const base = getApiBase();
  await supabase.auth.refreshSession();
  const { data: { session } } = await supabase.auth.getSession();
  const token = session?.access_token ?? '';
  if (!token) {
    throw new Error('กรุณาล็อกอินใหม่ก่อนสร้างผู้ใช้');
  }
  const idemKey = typeof crypto !== 'undefined' && crypto.randomUUID ? crypto.randomUUID() : `bulk-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const res = await fetch(`${base}/api/admin/create-users`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}`, 'X-Idempotency-Key': idemKey },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const msg = (data as { message?: string }).message;
    if (res.status === 401) {
      throw new Error(msg || 'โทเค็นไม่ถูกต้องหรือหมดอายุ กรุณาออกจากระบบแล้วล็อกอินใหม่');
    }
    throw new Error(msg || 'สร้างผู้ใช้ไม่สำเร็จ');
  }
  return data as CreateUsersResult;
}

/** Admin: ตั้งรหัสผ่านใหม่ให้ผู้ใช้ */
export async function resetUserPassword(userId: string, newPassword: string): Promise<void> {
  const base = getApiBase();
  await supabase.auth.refreshSession();
  const { data: { session } } = await supabase.auth.getSession();
  const token = session?.access_token ?? '';
  if (!token) throw new Error('กรุณาล็อกอินใหม่');
  const idemKey = `rp-${userId}-${Date.now()}`;
  const res = await fetch(`${base}/api/admin/reset-password`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}`, 'X-Idempotency-Key': idemKey },
    body: JSON.stringify({ user_id: userId, new_password: newPassword }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const msg = (data as { message?: string }).message;
    if (res.status === 401) throw new Error(msg || 'โทเค็นไม่ถูกต้องหรือหมดอายุ');
    throw new Error(msg || 'ตั้งรหัสผ่านไม่สำเร็จ');
  }
}
