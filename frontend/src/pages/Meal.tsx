import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { format } from 'date-fns';
import { th } from 'date-fns/locale';
import { useAuth } from '../lib/auth';
import { useBranchesShifts } from '../lib/BranchesShiftsContext';
import { useToast } from '../lib/ToastContext';
import {
  fetchMealSlots,
  bookMealBreak,
  cancelMealBreak,
  type MealSlotsResponse,
  type MealSlot,
  type MealBooking,
} from '../lib/mealBreak';
import { resolveShift, getDefaultWorkDateForMeal } from '../lib/resolveShift';
import { supabase } from '../lib/supabase';

type SlotState = 'available' | 'full' | 'booked_by_me' | 'outside_shift' | 'before_shift_start';

/** จองได้เมื่อ "ตอนนี้" อยู่ในช่วงกะเท่านั้น — กะดึก (20:00–08:00) ถือว่าช่วงกะถึงเช้าวันถัดไป */
function isNowWithinShift(shiftStartTs: string | undefined, shiftEndTs: string | undefined, now: Date): boolean {
  if (!shiftStartTs) return false;
  const start = new Date(shiftStartTs);
  if (now < start) return false;
  if (!shiftEndTs) return true;
  return now < new Date(shiftEndTs);
}

function getSlotState(
  slot: MealSlot,
  shiftStartTs: string | undefined,
  shiftEndTs: string | undefined,
  now: Date
): SlotState {
  if (!shiftStartTs) return 'before_shift_start';
  if (!isNowWithinShift(shiftStartTs, shiftEndTs, now)) return 'before_shift_start';
  if (slot.is_booked_by_me) return 'booked_by_me';
  const full = slot.booked_count >= slot.max_concurrent;
  if (full) return 'full';
  const slotStart = new Date(slot.slot_start_ts);
  const slotEnd = new Date(slot.slot_end_ts);
  const shiftStart = new Date(shiftStartTs);
  const shiftEnd = shiftEndTs ? new Date(shiftEndTs) : null;
  if (slotStart < shiftStart) return 'outside_shift';
  if (shiftEnd != null && (slotEnd > shiftEnd || slotStart >= shiftEnd)) return 'outside_shift';
  return 'available';
}

export default function Meal() {
  const { user, profile } = useAuth();
  const toast = useToast();
  const { shifts } = useBranchesShifts();
  const [workDate, setWorkDate] = useState(() => format(new Date(), 'yyyy-MM-dd'));

  /** กะดึก: หลังเที่ยงคืนให้ default work_date เป็นเมื่อวาน (วันเริ่มกะ) เพื่อให้จองพักหลังเที่ยงคืนได้ */
  const defaultWorkDateSet = useRef(false);
  useEffect(() => {
    if (defaultWorkDateSet.current || !profile?.default_shift_id || !shifts?.length) return;
    const suggested = getDefaultWorkDateForMeal(profile.default_shift_id, shifts, new Date());
    setWorkDate(suggested);
    defaultWorkDateSet.current = true;
  }, [profile?.default_shift_id, shifts]);
  const [data, setData] = useState<MealSlotsResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<{ type: 'ok' | 'err'; text: string } | null>(null);
  const [openRoundKey, setOpenRoundKey] = useState<string | null>(null);
  const [bookedUserNames, setBookedUserNames] = useState<Record<string, string>>({});
  const [onDutyNames, setOnDutyNames] = useState<Record<string, string>>({});

  const resolved = resolveShift(profile?.default_shift_id ?? null, shifts, workDate);

  const onDutyUserIds = useMemo(() => {
    const arr = data?.on_duty_user_ids;
    return Array.isArray(arr) ? arr : [];
  }, [data?.on_duty_user_ids]);

  useEffect(() => {
    if (onDutyUserIds.length === 0) {
      setOnDutyNames({});
      return;
    }
    supabase
      .from('profiles')
      .select('id, display_name, email')
      .in('id', onDutyUserIds)
      .then(({ data: profiles }) => {
        const map: Record<string, string> = {};
        (profiles ?? []).forEach((p: { id: string; display_name: string | null; email: string | null }) => {
          map[p.id] = p.display_name?.trim() || p.email || '—';
        });
        setOnDutyNames(map);
      });
  }, [onDutyUserIds.join(',')]);

  const allBookedUserIds = useMemo(() => {
    const ids = new Set<string>();
    (data?.rounds ?? []).forEach((r) => {
      r.slots.forEach((s) => {
        const arr = s.capacity?.booked_user_ids;
        if (Array.isArray(arr)) arr.forEach((id) => ids.add(id));
      });
    });
    return [...ids];
  }, [data?.rounds]);

  useEffect(() => {
    if (allBookedUserIds.length === 0) {
      setBookedUserNames({});
      return;
    }
    supabase
      .from('profiles')
      .select('id, display_name, email')
      .in('id', allBookedUserIds)
      .then(({ data: profiles }) => {
        const map: Record<string, string> = {};
        (profiles ?? []).forEach((p: { id: string; display_name: string | null; email: string | null }) => {
          map[p.id] = p.display_name?.trim() || p.email || '—';
        });
        setBookedUserNames(map);
      });
  }, [allBookedUserIds.join(',')]);

  const fetchSlots = useCallback(async (pWorkDate: string) => {
    if (!user?.id) return;
    setLoading(true);
    setMessage(null);
    const payload = await fetchMealSlots(pWorkDate);
    setLoading(false);
    setData(payload ?? null);
    if (payload?.error) {
      const text = (payload.error.includes('SUPABASE_ANON_KEY') || payload.error.includes('meal proxy'))
        ? 'ไม่สามารถเชื่อมต่อบริการจองพัก — ผู้ดูแลระบบกรุณาตั้งค่า SUPABASE_URL และ SUPABASE_ANON_KEY ใน Cloudflare Pages (Environment variables)'
        : payload.error;
      setMessage({ type: 'err', text });
    }
    if (payload?.rounds?.length && !openRoundKey) setOpenRoundKey(payload.rounds[0]?.round_key ?? null);
  }, [user?.id, openRoundKey]);

  useEffect(() => {
    if (!workDate || !resolved) return;
    fetchSlots(workDate);
  }, [workDate, resolved?.shiftId, fetchSlots]);

  /** Refetch เมื่อกลับมาเปิดแท็บ เพื่อให้โควต้า/คนอยู่ปฏิบัติตรงกติกาแบบ realtime */
  useEffect(() => {
    const onVisible = () => {
      if (document.visibilityState === 'visible' && workDate && resolved) fetchSlots(workDate);
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => document.removeEventListener('visibilitychange', onVisible);
  }, [workDate, resolved, fetchSlots]);

  useEffect(() => {
    if (data?.rounds?.length && !openRoundKey) setOpenRoundKey(data.rounds[0]?.round_key ?? null);
  }, [data?.rounds, openRoundKey]);

  const clearMessage = () => setMessage(null);

  const handleBook = async (roundKey: string, slot: MealSlot) => {
    if (!user?.id || !data?.work_date) return;
    if (resolved && !isNowWithinShift(resolved.shiftStartTs.toISOString(), resolved.shiftEndTs.toISOString(), new Date())) {
      setMessage({ type: 'err', text: 'จองได้เฉพาะเมื่ออยู่ภายในเวลากะ (ยังไม่เข้ากะหรือกะสิ้นสุดแล้ว)' });
      toast.show('จองได้เฉพาะเมื่ออยู่ภายในเวลากะ', 'error');
      return;
    }
    if (myBookedRoundKeys.has(roundKey)) {
      setMessage({ type: 'err', text: 'คุณจองรอบนี้แล้ว (1 slot ต่อรอบ)' });
      return;
    }
    clearMessage();
    const result = await bookMealBreak(data.work_date, roundKey, slot.slot_start_ts, slot.slot_end_ts);
    if (!result.ok) {
      const msg = result.error === 'slot_outside_shift' ? 'ช่วงเวลานี้นอกเวลากะของคุณ — กรุณาเลือก slot ภายในกะ' : (result.error ?? 'จองไม่สำเร็จ');
      setMessage({ type: 'err', text: msg });
      toast.show(msg, 'error');
      return;
    }
    toast.show('จองสำเร็จ');
    setMessage({ type: 'ok', text: 'จองสำเร็จ' });
    fetchSlots(data.work_date);
  };

  const handleCancel = async (bookingId: string) => {
    clearMessage();
    const result = await cancelMealBreak(bookingId);
    if (!result.ok) {
      setMessage({ type: 'err', text: result.error ?? 'ยกเลิกไม่สำเร็จ' });
      toast.show(result.error ?? 'ยกเลิกไม่สำเร็จ', 'error');
      return;
    }
    toast.show('ยกเลิกการจองแล้ว');
    setMessage({ type: 'ok', text: 'ยกเลิกการจองแล้ว' });
    if (data?.work_date) fetchSlots(data.work_date);
  };

  const now = new Date();
  const myBookedRoundKeys = new Set((data?.my_bookings ?? []).map((b) => b.round_key));
  const maxPerWorkday = data?.max_per_work_date ?? 2;
  const mealCount = data?.meal_count ?? 0;
  const remaining = Math.max(0, maxPerWorkday - mealCount);
  const canBookMore = mealCount < maxPerWorkday;
  // ใช้เวลากะจาก resolved (local) — กะดึกข้ามเที่ยงคืน: shiftEndTs อยู่วันถัดไป (resolveShift ทำให้แล้ว)
  const shiftStartTs = resolved ? resolved.shiftStartTs.toISOString() : (data?.shift_start_ts ?? undefined);
  const shiftEndTs = resolved ? resolved.shiftEndTs.toISOString() : (data?.shift_end_ts ?? undefined);
  const isWithinShift = isNowWithinShift(shiftStartTs, shiftEndTs, now);
  const isAfterShiftEnd = !isWithinShift && shiftEndTs ? now >= new Date(shiftEndTs) : false;

  const canInteract = profile && ['instructor', 'staff', 'instructor_head'].includes(profile.role);

  if (!resolved) {
    return (
      <div className="max-w-2xl mx-auto p-4 space-y-2">
        <h1 className="text-xl font-semibold text-premium-gold">จองเวลาพักทานอาหาร</h1>
        <p className="text-amber-400">กรุณาตั้งแผนก / กะ / เว็บหลักในโปรไฟล์ หรือไม่พบกะที่เปิดใช้</p>
      </div>
    );
  }

  return (
    <div className="flex gap-6 max-w-5xl mx-auto">
      <div className="flex-1 min-w-0 space-y-4">
      <div className="flex flex-wrap items-center gap-4">
        <h1 className="text-xl font-semibold text-premium-gold">จองเวลาพักทานอาหาร</h1>
        <label className="flex items-center gap-2 text-gray-300">
          <span>วันปฏิบัติงาน (workday):</span>
          <input
            type="date"
            value={workDate}
            onChange={(e) => setWorkDate(e.target.value)}
            className="rounded-lg bg-premium-dark/80 border border-gray-600 text-white px-3 py-1.5"
          />
        </label>
        {shiftStartTs && shiftEndTs && (
          <span className="text-gray-400 text-sm">
            กะ {format(new Date(shiftStartTs), 'HH:mm', { locale: th })} – {format(new Date(shiftEndTs), 'HH:mm', { locale: th })}
          </span>
        )}
        <span className="text-premium-gold font-medium">คุณจองได้อีก {remaining}/{maxPerWorkday} ครั้งวันนี้</span>
      </div>
      <p className="text-gray-500 text-sm">1 slot ต่อรอบ</p>

      {!isWithinShift && (shiftStartTs || shiftEndTs) && (
        <div className="rounded-lg border border-amber-500/50 bg-amber-500/10 px-4 py-3 text-amber-200 text-sm">
          {isAfterShiftEnd
            ? `กะสิ้นสุดแล้ว (กะถึง ${shiftEndTs ? format(new Date(shiftEndTs), 'HH:mm', { locale: th }) : ''}) — จองได้เฉพาะเมื่ออยู่ภายในเวลากะ`
            : `จองได้เมื่อถึงเวลาเข้ากะแล้วเท่านั้น — กะเริ่ม ${shiftStartTs ? format(new Date(shiftStartTs), 'HH:mm', { locale: th }) : ''} (กะดึกข้ามเที่ยงคืนจะถึงเช้าวันถัดไป)`}
        </div>
      )}

      {message && (
        <div
          className={`rounded-lg px-4 py-2 ${message.type === 'ok' ? 'bg-green-900/40 text-green-300' : 'bg-red-900/40 text-red-300'}`}
        >
          {message.text}
        </div>
      )}

      {loading && <p className="text-gray-400 animate-pulse">กำลังโหลด...</p>}

      {!loading && data?.error && !(data.rounds?.length) && (
        <p className="text-amber-400">
          {data.error === 'missing_branch_shift_website'
            ? 'กรุณาตั้งแผนก / กะ / เว็บหลักในโปรไฟล์'
            : data.error === 'shift_not_found'
              ? 'ไม่พบกะ'
              : data.error.includes('SUPABASE_ANON_KEY') || data.error.includes('meal proxy')
                ? 'ไม่สามารถเชื่อมต่อบริการจองพัก — ผู้ดูแลระบบกรุณาตั้งค่า SUPABASE_URL และ SUPABASE_ANON_KEY ใน Cloudflare Pages (Environment variables)'
                : data.error}
        </p>
      )}

      {!loading && data?.rounds?.length === 0 && !data.error && (
        <p className="text-gray-400">ยังไม่มีรอบพักอาหารที่เปิดใช้ (แอดมินตั้งค่าใน ตั้งค่า → จองพักอาหาร)</p>
      )}

      <div className="space-y-2">
        {(data?.rounds ?? []).map((round) => {
          const isOpen = openRoundKey === round.round_key;
          return (
            <div key={round.round_key} className="rounded-xl bg-premium-dark/60 border border-gray-700 overflow-hidden">
              <button
                type="button"
                onClick={() => setOpenRoundKey(isOpen ? null : round.round_key)}
                className="w-full flex items-center justify-between px-4 py-3 text-left text-premium-gold font-medium hover:bg-premium-gold/10 transition-colors"
              >
                <span>{round.round_name || round.round_key}</span>
                <span className="text-gray-400">{isOpen ? '▼' : '▶'}</span>
              </button>
              {isOpen && (
                <div className="px-4 pb-4 pt-1 grid grid-cols-2 sm:grid-cols-3 gap-2">
                  {round.slots.map((slot) => {
                    const state = getSlotState(slot, shiftStartTs, shiftEndTs, now);
                    const canCancel = state === 'booked_by_me' && new Date(slot.slot_start_ts) > now;
                    const booking: MealBooking | undefined = (data?.my_bookings ?? []).find(
                      (b) => b.round_key === round.round_key && b.slot_start_ts === slot.slot_start_ts
                    );
                    const label = `${slot.slot_start}–${slot.slot_end} (${slot.booked_count}/${slot.max_concurrent})`;

                    return (
                      <div
                        key={`${slot.slot_start}-${slot.slot_end}`}
                        className={`rounded-lg border p-3 ${
                          state === 'booked_by_me'
                            ? 'border-premium-gold/50 bg-premium-gold/10'
                            : state === 'full'
                              ? 'border-gray-600 bg-gray-800/50'
                              : state === 'before_shift_start' || state === 'outside_shift'
                                ? 'border-gray-600 bg-gray-800/30 opacity-75'
                                : 'border-gray-600 bg-premium-dark/80'
                        }`}
                      >
                        <div className="text-sm text-gray-300">{label}</div>
                        {state === 'full' && <div className="text-amber-400 text-xs mt-1">เต็ม</div>}
                        {state === 'before_shift_start' && (
                          <div className="text-gray-500 text-xs mt-1">ยังไม่ถึงเวลาเข้ากะ</div>
                        )}
                        {state === 'outside_shift' && (
                          <div className="text-gray-500 text-xs mt-1">นอกช่วงกะ</div>
                        )}
                        {state === 'booked_by_me' && booking && (
                          <div className="mt-2">
                            <span className="text-premium-gold text-xs">จองแล้ว</span>
                            {canCancel && canInteract && (
                              <button
                                type="button"
                                onClick={() => handleCancel(booking.id)}
                                className="ml-2 text-red-400 hover:text-red-300 text-xs underline"
                              >
                                ยกเลิก
                              </button>
                            )}
                          </div>
                        )}
                        {state === 'available' && (
                          <button
                            type="button"
                            disabled={!canBookMore || !canInteract}
                            onClick={() => canBookMore && canInteract && handleBook(round.round_key, slot)}
                            className="mt-2 rounded-lg bg-premium-gold/20 text-premium-gold px-3 py-1.5 text-sm hover:bg-premium-gold/30 disabled:opacity-50 disabled:cursor-not-allowed"
                          >
                            จอง
                          </button>
                        )}
                        {slot.capacity && (
                          <div className="text-gray-500 text-xs mt-1 space-y-0.5">
                            <div>อยู่ปฏิบัติ {slot.capacity.on_duty_count}{!canInteract && ' — ดูได้เฉย ๆ'}</div>
                            {Array.isArray(slot.capacity.booked_user_ids) && slot.capacity.booked_user_ids.length > 0 && (
                              <div className="text-premium-gold/90">จองแล้ว: {slot.capacity.booked_user_ids.map((id) => bookedUserNames[id] ?? id).join(', ')}</div>
                            )}
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          );
        })}
      </div>
      </div>

      {/* ฝั่งขวา: คนที่ระบบนับเป็น "อยู่ปฏิบัติ" */}
      {!loading && data && !data.error && (
        <aside className="w-56 flex-shrink-0">
          <div className="rounded-xl bg-premium-dark/60 border border-premium-gold/20 p-4 sticky top-4">
            <h3 className="text-premium-gold font-medium text-sm mb-2">คนที่ระบบนับ (อยู่ปฏิบัติ)</h3>
            <p className="text-gray-500 text-xs mb-2">กลุ่ม+แผนก+กะเดียวกัน{data.rounds?.length ? ' — ใช้คำนวณโควต้า' : ''}</p>
            {onDutyUserIds.length === 0 ? (
              <p className="text-gray-500 text-xs">—</p>
            ) : (
              <ul className="text-gray-300 text-sm space-y-1">
                {onDutyUserIds.map((id) => (
                  <li key={id}>{onDutyNames[id] ?? id}</li>
                ))}
              </ul>
            )}
            {onDutyUserIds.length > 0 && (
              <p className="text-gray-500 text-xs mt-2">รวม {onDutyUserIds.length} คน</p>
            )}
          </div>
        </aside>
      )}
    </div>
  );
}
