/**
 * Service: เว็บที่ดูแล (Managed Websites)
 * - Admin: เพิ่ม/แก้/ลบเว็บ, จัดการผู้ดูแล, ตั้งเว็บหลัก
 * - Instructor/Staff: ดูเฉพาะเว็บที่ตัวเองถูก assign
 */

import { supabase } from './supabase';
import { logAudit } from './audit';
import type { Website, WebsiteAssignment, Branch, Profile } from './types';

const ENTITY = 'managed_website';

/** รายการเว็บทั้งหมด (Admin เห็นทั้งหมด / Head เห็นเฉพาะที่ถูก assign) — ค้นหาชื่อหรือ alias */
export async function listWebsitesForAdmin(filters?: {
  search?: string;
}): Promise<(Website & { branch?: Branch })[]> {
  let q = supabase
    .from('websites')
    .select('*, branch:branches(id, name, code)')
    .order('name');
  if (filters?.search?.trim()) {
    const s = filters.search.trim();
    q = q.or(`name.ilike.%${s}%,alias.ilike.%${s}%`);
  }
  const { data, error } = await q;
  if (error) return [];
  return (data || []) as (Website & { branch?: Branch })[];
}

/** เว็บที่ฉันดูแล (Instructor/Staff) — เฉพาะที่ถูก assign */
export async function listMyWebsites(): Promise<(WebsiteAssignment & { website?: Website & { branch?: Branch } })[]> {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user?.id) return [];
  const { data, error } = await supabase
    .from('website_assignments')
    .select('*, website:websites(*, branch:branches(id, name, code))')
    .eq('user_id', user.id)
    .order('is_primary', { ascending: false });
  if (error) return [];
  return (data || []) as (WebsiteAssignment & { website?: Website & { branch?: Branch } })[];
}

/** Admin: สร้างเว็บ (ไม่บังคับแผนก; ชื่อและ alias ห้ามซ้ำ) */
export async function adminCreateWebsite(payload: {
  name: string;
  alias: string;
  url?: string | null;
  description?: string | null;
  logo_path?: string | null;
}): Promise<Website> {
  const name = payload.name.trim();
  const alias = payload.alias.trim();
  if (!name || !alias) throw new Error('กรุณากรอกชื่อเว็บและนามสกุล (alias)');
  const { data, error } = await supabase
    .from('websites')
    .insert({
      branch_id: null,
      name,
      alias,
      url: payload.url?.trim() || null,
      description: payload.description?.trim() || null,
      logo_path: payload.logo_path?.trim() || null,
      is_active: true,
    })
    .select()
    .single();
  if (error) {
    if (error.code === '23505') throw new Error('ชื่อเว็บหรือ alias ซ้ำ กรุณาใช้ชื่ออื่น');
    throw new Error(error.message);
  }
  await logAudit('WEBSITE_CREATE', ENTITY, data.id, { name: data.name, alias: data.alias });
  return data as Website;
}

/** Admin: แก้ไขเว็บ (ชื่อ/alias ห้ามซ้ำกับเว็บอื่น) */
export async function adminUpdateWebsite(
  id: string,
  payload: { name?: string; alias?: string; url?: string | null; description?: string | null; logo_path?: string | null; is_active?: boolean }
): Promise<void> {
  const { data: old } = await supabase.from('websites').select('id, name, alias, url, description, logo_path, branch_id, is_active, created_at, updated_at').eq('id', id).single();
  const update: Record<string, unknown> = {};
  if (payload.name !== undefined) update.name = payload.name.trim();
  if (payload.alias !== undefined) update.alias = payload.alias.trim();
  if (payload.url !== undefined) update.url = payload.url?.trim() || null;
  if (payload.description !== undefined) update.description = payload.description?.trim() || null;
  if (payload.logo_path !== undefined) update.logo_path = payload.logo_path?.trim() || null;
  if (payload.is_active !== undefined) update.is_active = payload.is_active;
  const { error } = await supabase.from('websites').update(update).eq('id', id);
  if (error) {
    if (error.code === '23505') throw new Error('ชื่อเว็บหรือ alias ซ้ำ กรุณาใช้ชื่ออื่น');
    throw new Error(error.message);
  }
  await logAudit('WEBSITE_UPDATE', ENTITY, id, { old: old ?? null, new: payload });
}

/** Admin: ลบเว็บ (และ assignments ที่ผูกอยู่จะถูกลบ CASCADE) */
export async function adminDeleteWebsite(id: string): Promise<void> {
  const { data: old } = await supabase.from('websites').select('id, name, alias, url, description, logo_path, branch_id, is_active, created_at, updated_at').eq('id', id).single();
  const { error } = await supabase.from('websites').delete().eq('id', id);
  if (error) throw new Error(error.message);
  await logAudit('WEBSITE_DELETE', ENTITY, id, { deleted: old ?? null });
}

/** Admin: มอบหมายเว็บให้ user (เลือกได้หลายคนต่อเว็บ) */
export async function adminAssignWebsiteToUser(websiteId: string, userId: string, roleOnWebsite?: string): Promise<void> {
  const { data: web } = await supabase.from('websites').select('id').eq('id', websiteId).single();
  if (!web) throw new Error('ไม่พบเว็บ');
  const { error } = await supabase.from('website_assignments').insert({
    website_id: websiteId,
    user_id: userId,
    is_primary: false,
    role_on_website: roleOnWebsite || 'viewer',
  });
  if (error) {
    const err = new Error(error.message) as Error & { code?: string };
    err.code = error.code;
    throw err;
  }
  await logAudit('WEBSITE_ASSIGN', ENTITY, websiteId, { user_id: userId, role: roleOnWebsite || 'viewer' });
}

/** Admin: เอาเว็บออกจาก user */
export async function adminUnassignWebsiteFromUser(assignmentId: string): Promise<void> {
  const { data: row } = await supabase.from('website_assignments').select('id, website_id, user_id').eq('id', assignmentId).single();
  if (!row) throw new Error('ไม่พบรายการ');
  const { error } = await supabase.from('website_assignments').delete().eq('id', assignmentId);
  if (error) throw new Error(error.message);
  await logAudit('WEBSITE_UNASSIGN', ENTITY, row.website_id, { user_id: row.user_id, assignment_id: assignmentId });
}

/** Admin: ตั้งเว็บหลัก (direct updates — atomic per table) */
export async function adminSetPrimaryWebsite(userId: string, websiteId: string): Promise<void> {
  const { error: off } = await supabase.from('website_assignments').update({ is_primary: false }).eq('user_id', userId);
  if (off) throw new Error(off.message);
  const { error: on } = await supabase.from('website_assignments').update({ is_primary: true }).eq('user_id', userId).eq('website_id', websiteId);
  if (on) throw new Error(on.message);
  await logAudit('WEBSITE_SET_PRIMARY', ENTITY, websiteId, { user_id: userId });
}

/** Admin: รายการ assignment ต่อ user (สำหรับ Tab จัดการผู้ดูแล) */
export async function listAssignmentsByUser(userId: string): Promise<(WebsiteAssignment & { website?: Website & { branch?: Branch } })[]> {
  const { data, error } = await supabase
    .from('website_assignments')
    .select('*, website:websites(*, branch:branches(id, name, code))')
    .eq('user_id', userId)
    .order('is_primary', { ascending: false });
  if (error) return [];
  return (data || []) as (WebsiteAssignment & { website?: Website & { branch?: Branch } })[];
}

export type AssignmentRow = WebsiteAssignment & {
  website?: Website & { branch?: Branch };
  user?: Profile;
};

/** Admin: รายการ assignment ทั้งหมด (สำหรับ Tab จัดการผู้ดูแล — แสดงตารางรวม) */
export async function listAllAssignmentsForAdmin(): Promise<AssignmentRow[]> {
  const { data, error } = await supabase
    .from('website_assignments')
    .select('*, website:websites(*, branch:branches(id, name, code)), user:profiles(id, display_name, email, default_branch_id)')
    .order('user_id')
    .order('is_primary', { ascending: false });
  if (error) return [];
  return (data || []) as AssignmentRow[];
}

/** Admin: รายชื่อผู้ใช้ที่มอบหมายเว็บได้ (instructor, staff, instructor_head) */
export async function listStaffForAssignments(): Promise<Profile[]> {
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .in('role', ['instructor', 'staff', 'instructor_head'])
    .eq('active', true)
    .order('display_name');
  if (error) return [];
  return (data || []) as Profile[];
}

export type StaffListFilters = {
  search?: string;
  branch_id?: string;
  shift_id?: string;
  role?: string;
  limit: number;
  offset: number;
};

/** Admin: รายชื่อผู้ใช้แบบแบ่งหน้า + filter. ใช้ limit+1 แทน exact count เพื่อลด row reads */
export async function listStaffForAssignmentsPaginated(
  filters: StaffListFilters
): Promise<{ data: Profile[]; hasMore: boolean }> {
  const limit = Math.min(Math.max(1, filters.limit || 50), 100);
  const offset = Math.max(0, filters.offset || 0);
  let q = supabase
    .from('profiles')
    .select('id, display_name, email, role, default_branch_id, default_shift_id, active, created_at, updated_at, branch:branches(id, name, code), shift:shifts(id, name, code)')
    .in('role', ['instructor', 'staff', 'instructor_head'])
    .eq('active', true)
    .order('display_name')
    .range(offset, offset + limit);
  if (filters.search?.trim()) {
    const s = filters.search.trim();
    q = q.or(`display_name.ilike.%${s}%,email.ilike.%${s}%`);
  }
  if (filters.branch_id) q = q.eq('default_branch_id', filters.branch_id);
  if (filters.shift_id) q = q.eq('default_shift_id', filters.shift_id);
  if (filters.role) q = q.eq('role', filters.role);
  const { data, error } = await q;
  if (error) return { data: [], hasMore: false };
  const list = (data || []) as unknown as Profile[];
  const hasMore = list.length > limit;
  const dataSlice = hasMore ? list.slice(0, limit) : list;
  return { data: dataSlice, hasMore };
}

export type WebsiteListFilters = {
  search?: string;
  limit: number;
  offset: number;
};

/** Admin: รายการเว็บแบบแบ่งหน้า. ใช้ limit+1 แทน exact count เพื่อลด row reads */
export async function listWebsitesForAdminPaginated(
  filters: WebsiteListFilters
): Promise<{ data: (Website & { branch?: Branch })[]; hasMore: boolean }> {
  const limit = Math.min(Math.max(1, filters.limit || 50), 100);
  const offset = Math.max(0, filters.offset || 0);
  let q = supabase
    .from('websites')
    .select('id, name, alias, branch_id, url, description, logo_path, is_active, created_at, updated_at, branch:branches(id, name, code)')
    .order('name')
    .range(offset, offset + limit);
  if (filters.search?.trim()) {
    const s = filters.search.trim();
    q = q.or(`name.ilike.%${s}%,alias.ilike.%${s}%`);
  }
  const { data, error } = await q;
  if (error) return { data: [], hasMore: false };
  const list = (data || []) as unknown as (Website & { branch?: Branch })[];
  const hasMore = list.length > limit;
  const dataSlice = hasMore ? list.slice(0, limit) : list;
  return { data: dataSlice, hasMore };
}
