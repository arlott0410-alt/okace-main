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

export function BranchesShiftsProvider({ children }: { children: ReactNode }) {
  const [branches, setBranches] = useState<Branch[]>([]);
  const [shifts, setShifts] = useState<Shift[]>([]);
  const [loading, setLoading] = useState(true);
  const mounted = useRef(true);

  const refetch = useCallback(() => {
    setLoading(true);
    invalidate('branches');
    invalidate('shifts');
    Promise.all([
      supabase.from('branches').select('id, name, code, active, created_at, updated_at').eq('active', true).order('name').then(({ data }) => data || []),
      supabase.from('shifts').select('id, name, code, start_time, end_time, sort_order, active, created_at, updated_at').eq('active', true).order('sort_order').then(({ data }) => data || []),
    ]).then(([b, s]) => {
      if (mounted.current) {
        setBranches((b || []) as Branch[]);
        setShifts((s || []) as Shift[]);
      }
    }).finally(() => { if (mounted.current) setLoading(false); });
  }, []);

  useEffect(() => {
    mounted.current = true;
    setLoading(true);
    const SLOW_CHANGE_TTL_MS = 10 * 60 * 1000; // 10 min for branches/shifts (reduce refetch across route changes)
    const load = async () => {
      const p1 = withCache('branches', BRANCHES_KEY, async () => {
        const { data } = await supabase.from('branches').select('id, name, code, active, created_at, updated_at').eq('active', true).order('name');
        return data || [];
      }, SLOW_CHANGE_TTL_MS);
      const p2 = withCache('shifts', SHIFTS_KEY, async () => {
        const { data } = await supabase.from('shifts').select('id, name, code, start_time, end_time, sort_order, active, created_at, updated_at').eq('active', true).order('sort_order');
        return data || [];
      }, SLOW_CHANGE_TTL_MS);
      const [b, s] = await Promise.all([p1, p2]);
      if (mounted.current) {
        setBranches((b || []) as Branch[]);
        setShifts((s || []) as Shift[]);
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
