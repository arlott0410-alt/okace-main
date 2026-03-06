import React, { createContext, useContext, useEffect, useState } from 'react';
import { User } from '@supabase/supabase-js';
import { supabase } from './supabase';
import type { Profile } from './types';
import type { UserGroup } from './types';

type AuthContextType = {
  user: User | null;
  profile: Profile | null;
  loading: boolean;
  signOut: () => Promise<void>;
  refreshProfile: () => Promise<void>;
};

const AuthContext = createContext<AuthContextType | null>(null);

const STORAGE_BRANCH = 'okace_last_branch_id';
const STORAGE_SHIFT = 'okace_last_shift_id';

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}

/** บทบาทที่เป็นพนักงานตามกะ (ลงเวลา/พัก/ขอลาได้) — ไม่รวม admin */
export function isEmployeeRole(role: string | undefined): boolean {
  return role === 'manager' || role === 'instructor_head' || role === 'instructor' || role === 'staff';
}

/** คืนค่า user_group สำหรับลงเวลา/พัก/วันหยุด — ใช้จาก role เท่านั้น (ห้ามรับจาก client) */
export function getMyUserGroup(profile: Profile | null): UserGroup | null {
  if (!profile) return null;
  if (profile.role === 'instructor' || profile.role === 'instructor_head') return 'INSTRUCTOR';
  if (profile.role === 'staff') return 'STAFF';
  if (profile.role === 'manager') return 'MANAGER';
  return null;
}

export function getStoredBranchId(): string | null {
  return localStorage.getItem(STORAGE_BRANCH);
}
export function setStoredBranchId(id: string) {
  localStorage.setItem(STORAGE_BRANCH, id);
}
export function getStoredShiftId(): string | null {
  return localStorage.getItem(STORAGE_SHIFT);
}
export function setStoredShiftId(id: string) {
  localStorage.setItem(STORAGE_SHIFT, id);
}

async function fetchProfile(userId: string): Promise<Profile | null> {
  const { data, error } = await supabase
    .from('profiles')
    .select('id, email, display_name, role, default_branch_id, default_shift_id, active, created_at, updated_at, telegram, lock_code, email_code, computer_code, work_access_code, two_fa, avatar_url, link1_url, link2_url, note_title, note_body, branch:branches(id, name, code), shift:shifts(id, name, code, start_time, end_time, sort_order)')
    .eq('id', userId)
    .single();
  if (error || !data) return null;
  return data as unknown as Profile & { branch?: unknown; shift?: unknown };
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [loading, setLoading] = useState(true);

  const refreshProfile = async () => {
    if (!user) return;
    const p = await fetchProfile(user.id);
    setProfile(p);
  };

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null);
      if (session?.user) {
        fetchProfile(session.user.id).then(setProfile);
      } else {
        setProfile(null);
      }
      setLoading(false);
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange(async (_event, session) => {
      if (session?.user) {
        setUser(session.user);
        fetchProfile(session.user.id).then(setProfile);
        return;
      }
      // ยืนยันอีกครั้งก่อนเคลียร์ — ลด auth flicker เมื่อ session กลายเป็น null ชั่วคราว
      const { data } = await supabase.auth.getSession();
      if (!data.session?.user) {
        setUser(null);
        setProfile(null);
      }
    });

    return () => subscription.unsubscribe();
  }, []);

  const signOut = async () => {
    await supabase.auth.signOut();
    setUser(null);
    setProfile(null);
  };

  return (
    <AuthContext.Provider value={{ user, profile, loading, signOut, refreshProfile }}>
      {children}
    </AuthContext.Provider>
  );
}
