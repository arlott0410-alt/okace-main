import { createContext, useContext, useState, useEffect, useCallback, useRef, type ReactNode } from 'react';
import { supabase } from './supabase';
import { withCache, invalidate } from './queryCache';
import type { Branch, Shift } from './types';

type ContextValue = {
  branches: Branch[];
  shifts: Shift[];
  loading: boolean;
  refetch: () => void;
};

const BranchesShiftsContext = createContext<ContextValue | null>(null);

const BRANCHES_KEY = { active: true };
const SHIFTS_KEY = { active: true };
const SLOW_CHANGE_TTL_MS = 10 * 60 * 1000; // 10 min client cache (เมื่อใช้ edge cache ก็ยังลด refetch ข้าม route)

/** ดึง branches/shifts จาก edge cache API (ถ้าสำเร็จ) ไม่ก็ fallback ตรง Supabase */
async function fetchFromEdgeCache(
  path: 'branches' | 'shifts',
  refresh = false
): Promise<{ data: Branch[] } | { data: Shift[] } | null> {
  const { data: { session } } = await supabase.auth.getSession();
  const token = session?.access_token;
  if (!token) return null;
  const url = `/api/cache/${path}${refresh ? '?refresh=1' : ''}`;
  try {
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) return null;
    const data = await res.json();
    if (!Array.isArray(data)) return null;
    return { data };
  } catch {
    return null;
  }
}

async function fetchBranchesDirect(): Promise<Branch[]> {
  const { data } = await supabase.from('branches').select('id, name, code, active, created_at, updated_at').eq('active', true).order('name');
  return (data || []) as Branch[];
}

async function fetchShiftsDirect(): Promise<Shift[]> {
  const { data } = await supabase.from('shifts').select('id, name, code, start_time, end_time, sort_order, active, created_at, updated_at').eq('active', true).order('sort_order');
  return (data || []) as Shift[];
}

export function BranchesShiftsProvider({ children }: { children: ReactNode }) {
  const [branches, setBranches] = useState<Branch[]>([]);
  const [shifts, setShifts] = useState<Shift[]>([]);
  const [loading, setLoading] = useState(true);
  const mounted = useRef(true);

  const refetch = useCallback(() => {
    setLoading(true);
    invalidate('branches');
    invalidate('shifts');
    (async () => {
      const [bRes, sRes] = await Promise.all([
        fetchFromEdgeCache('branches', true),
        fetchFromEdgeCache('shifts', true),
      ]);
      let b: Branch[], s: Shift[];
      if (bRes && 'data' in bRes && Array.isArray(bRes.data)) b = bRes.data as Branch[];
      else b = await fetchBranchesDirect();
      if (sRes && 'data' in sRes && Array.isArray(sRes.data)) s = sRes.data as Shift[];
      else s = await fetchShiftsDirect();
      if (mounted.current) {
        setBranches(b);
        setShifts(s);
      }
    })().finally(() => { if (mounted.current) setLoading(false); });
  }, []);

  useEffect(() => {
    mounted.current = true;
    setLoading(true);
    const load = async () => {
      const [bRes, sRes] = await Promise.all([
        fetchFromEdgeCache('branches'),
        fetchFromEdgeCache('shifts'),
      ]);
      let b: Branch[], s: Shift[];
      if (bRes && 'data' in bRes && Array.isArray(bRes.data)) b = bRes.data as Branch[];
      else {
        const p1 = withCache('branches', BRANCHES_KEY, fetchBranchesDirect, SLOW_CHANGE_TTL_MS);
        b = await p1;
      }
      if (sRes && 'data' in sRes && Array.isArray(sRes.data)) s = sRes.data as Shift[];
      else {
        const p2 = withCache('shifts', SHIFTS_KEY, fetchShiftsDirect, SLOW_CHANGE_TTL_MS);
        s = await p2;
      }
      if (mounted.current) {
        setBranches(b);
        setShifts(s);
      }
    };
    load().finally(() => { if (mounted.current) setLoading(false); });
    return () => { mounted.current = false; };
  }, []);

  const value: ContextValue = { branches, shifts, loading, refetch };
  return (
    <BranchesShiftsContext.Provider value={value}>
      {children}
    </BranchesShiftsContext.Provider>
  );
}

export function useBranchesShifts(): ContextValue {
  const ctx = useContext(BranchesShiftsContext);
  if (!ctx) {
    return {
      branches: [],
      shifts: [],
      loading: false,
      refetch: () => {},
    };
  }
  return ctx;
}
