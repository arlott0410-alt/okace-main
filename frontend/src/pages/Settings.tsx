import { useState, useEffect } from 'react';
import { format } from 'date-fns';
import { supabase } from '../lib/supabase';
import { withCache, invalidate } from '../lib/queryCache';
import { useAuth } from '../lib/auth';
import { useBranchesShifts } from '../lib/BranchesShiftsContext';
import type { Branch, HolidayBookingConfig, HolidayQuotaTier, Shift, MealSettings, MealQuotaRule, LeaveType } from '../lib/types';
import type { UserGroup } from '../lib/types';
import Button from '../components/ui/Button';
import Modal from '../components/ui/Modal';
import { BtnEdit, BtnDelete } from '../components/ui/ActionIcons';

/** คืนค่า HH:mm สำหรับ input type="time" (รับจาก DB เป็น HH:mm:ss ได้) */
function toTimeInputValue(t: string | null | undefined): string {
  if (t == null || t === '') return '';
  const part = t.trim().slice(0, 5);
  return /^\d{2}:\d{2}$/.test(part) ? part : '';
}

/** ส่งค่าเวลาไปยัง API (HH:mm หรือ HH:mm:ss) */
function toTimePayload(v: string): string {
  if (!v || v.length === 0) return '';
  return /^\d{2}:\d{2}$/.test(v) ? `${v}:00` : v;
}

export default function Settings() {
  const { profile } = useAuth();
  const { shifts, refetch: refetchBranchesShifts } = useBranchesShifts();
  const [allowMobile, setAllowMobile] = useState<boolean>(false);
  const [loadingAllowMobile, setLoadingAllowMobile] = useState<boolean>(true);
  const [branches, setBranches] = useState<Branch[]>([]);
  const [modalBranch, setModalBranch] = useState<{ open: boolean; branch?: Branch | null }>({ open: false, branch: null });
  const [branchForm, setBranchForm] = useState({ name: '', code: '', active: true });
  const [bookingConfigs, setBookingConfigs] = useState<HolidayBookingConfig[]>([]);
  const [modalBooking, setModalBooking] = useState<{ open: boolean; config?: HolidayBookingConfig | null }>({ open: false, config: null });
  const [bookingForm, setBookingForm] = useState({ target_year_month: '', open_from: '', open_until: '', max_days_per_person: 4 });
  const [quotaTiers, setQuotaTiers] = useState<HolidayQuotaTier[]>([]);
  const [modalQuotaTier, setModalQuotaTier] = useState<{ open: boolean; tier?: HolidayQuotaTier | null }>({ open: false, tier: null });
  const [quotaTierForm, setQuotaTierForm] = useState<{ max_people: number; max_leave: number }>({ max_people: 4, max_leave: 1 });
  const [modalShift, setModalShift] = useState<{ open: boolean; shift: Shift | null }>({ open: false, shift: null });
  const [shiftForm, setShiftForm] = useState({ start_time: '', end_time: '' });
  const [mealSettings, setMealSettings] = useState<MealSettings | null>(null);
  const [mealQuotaRules, setMealQuotaRules] = useState<MealQuotaRule[]>([]);
  const [mealSettingsForm, setMealSettingsForm] = useState({ is_enabled: true, max_per_work_date: 2, scope_meal_quota_by_website: true, scope_holiday_quota_by_website: true, max_holiday_days_per_person_per_month: 4 });
  const [rounds, setRounds] = useState<Array<{ name: string; slots: Array<{ start: string; end: string }> }>>([]);
  const [modalMealQuota, setModalMealQuota] = useState<{ open: boolean; rule?: MealQuotaRule | null }>({ open: false, rule: null });
  const [mealQuotaForm, setMealQuotaForm] = useState<{ branch_id: string; shift_id: string; website_id: string; user_group: UserGroup | ''; on_duty_threshold: number; max_concurrent: number }>({
    branch_id: '',
    shift_id: '',
    website_id: '',
    user_group: '',
    on_duty_threshold: 0,
    max_concurrent: 1,
  });
  const [leaveTypes, setLeaveTypes] = useState<LeaveType[]>([]);
  const [modalLeaveType, setModalLeaveType] = useState<{ open: boolean; leaveType?: LeaveType | null }>({ open: false, leaveType: null });
  const [leaveTypeForm, setLeaveTypeForm] = useState({ code: '', name: '', color: '#9CA3AF', description: '' });
  const [applyShiftLoading, setApplyShiftLoading] = useState(false);
  const [applyShiftResult, setApplyShiftResult] = useState<{ count: number } | { error: string } | null>(null);

  const loadBranches = () => {
    supabase.from('branches').select('id, name, code, active, created_at, updated_at').order('name').then(({ data }) => setBranches(data || []));
  };

  async function loadAllowMobile() {
    setLoadingAllowMobile(true);
    const { data, error } = await supabase
      .from('app_settings')
      .select('value_bool')
      .eq('key', 'allow_mobile_access')
      .maybeSingle();
    if (!error && data) setAllowMobile(!!data.value_bool);
    else setAllowMobile(false);
    setLoadingAllowMobile(false);
  }

  async function toggleAllowMobile(next: boolean) {
    setAllowMobile(next);
    const { error } = await supabase
      .from('app_settings')
      .update({ value_bool: next })
      .eq('key', 'allow_mobile_access');
    if (error) {
      await loadAllowMobile();
      alert('ไม่มีสิทธิ์เปลี่ยนการตั้งค่านี้ หรือเกิดข้อผิดพลาด');
    }
  }

  const SETTINGS_CACHE_TTL_MS = 120_000; // 2 นาที — ลดโควต้าเมื่อสลับกลับมาเปิดตั้งค่า

  useEffect(() => {
    loadBranches();
    loadAllowMobile();
    const loadBooking = () => Promise.resolve(supabase.from('holiday_booking_config').select('id, target_year_month, open_from, open_until, max_days_per_person').order('target_year_month')).then(({ data }) => (data || []) as HolidayBookingConfig[]);
    const loadQuotaTiers = () => Promise.resolve(supabase.from('holiday_quota_tiers').select('id, dimension, user_group, max_people, max_leave, sort_order').order('dimension').order('user_group').order('max_people')).then(({ data }) => (data || []) as HolidayQuotaTier[]);
    const loadMealRules = () => Promise.resolve(supabase.from('meal_quota_rules').select('id, branch_id, shift_id, website_id, user_group, on_duty_threshold, max_concurrent').order('on_duty_threshold')).then(({ data }) => (data || []) as MealQuotaRule[]);
    const loadLeaveTypes = () => Promise.resolve(supabase.from('leave_types').select('code, name, color, description').order('code')).then(({ data }) => (data || []) as LeaveType[]);
    withCache('holiday_booking_config', {}, loadBooking, SETTINGS_CACHE_TTL_MS).then(setBookingConfigs);
    withCache('holiday_quota_tiers', {}, loadQuotaTiers, SETTINGS_CACHE_TTL_MS).then(setQuotaTiers);
    loadMealSettings();
    withCache('meal_quota_rules', {}, loadMealRules, SETTINGS_CACHE_TTL_MS).then(setMealQuotaRules);
    withCache('leave_types', {}, loadLeaveTypes, SETTINGS_CACHE_TTL_MS).then(setLeaveTypes);
  }, []);


  const saveBranch = async () => {
    if (!branchForm.name.trim()) return;
    if (modalBranch.branch?.id) {
      await supabase.from('branches').update({ name: branchForm.name.trim(), code: branchForm.code.trim() || null, active: branchForm.active }).eq('id', modalBranch.branch.id);
    } else {
      await supabase.from('branches').insert({ name: branchForm.name.trim(), code: branchForm.code.trim() || null, active: true });
    }
    setModalBranch({ open: false, branch: null });
    loadBranches();
    refetchBranchesShifts(); // อัป Context + edge cache ให้หน้าอื่นเห็นสาขาล่าสุด
  };

  /** บันทึกกติกากลางวันหยุด (วัน/คน/เดือน) — ใช้บังคับไม่ให้หัวหน้าตั้งเกินโควตา */
  const saveGlobalHolidayDays = async () => {
    const val = mealSettingsForm.max_holiday_days_per_person_per_month ?? 4;
    if (val < 1) return;
    if (mealSettings?.id) {
      await supabase.from('meal_settings').update({ max_holiday_days_per_person_per_month: val }).eq('id', mealSettings.id);
    } else {
      await supabase.from('meal_settings').insert({
        effective_from: format(new Date(), 'yyyy-MM-dd'),
        is_enabled: true,
        rounds_json: { max_per_work_date: 2, rounds: [] },
        max_holiday_days_per_person_per_month: val,
      });
    }
    loadMealSettings();
  };

  const saveBookingConfig = async () => {
    if (!bookingForm.target_year_month || !bookingForm.open_from || !bookingForm.open_until) {
      alert('กรุณากรอกเดือนเป้าหมาย และช่วงวันที่เปิดจอง');
      return;
    }
    const globalMaxDays = mealSettingsForm.max_holiday_days_per_person_per_month ?? 4;
    if (modalBooking.config?.id) {
      await supabase.from('holiday_booking_config').update({
        open_from: bookingForm.open_from,
        open_until: bookingForm.open_until,
        max_days_per_person: globalMaxDays,
      }).eq('id', modalBooking.config.id);
    } else {
      await supabase.from('holiday_booking_config').upsert({
        target_year_month: bookingForm.target_year_month,
        open_from: bookingForm.open_from,
        open_until: bookingForm.open_until,
        max_days_per_person: globalMaxDays,
      }, { onConflict: 'target_year_month' });
    }
    setModalBooking({ open: false, config: null });
    invalidate('holiday_booking_config');
    supabase.from('holiday_booking_config').select('id, target_year_month, open_from, open_until, max_days_per_person').order('target_year_month').then(({ data }) => setBookingConfigs((data || []) as HolidayBookingConfig[]));
  };

  const saveQuotaTier = async () => {
    if (quotaTierForm.max_people < 1 || quotaTierForm.max_leave < 0) return;
    if (modalQuotaTier.tier?.id) {
      await supabase.from('holiday_quota_tiers').update({ max_people: quotaTierForm.max_people, max_leave: quotaTierForm.max_leave }).eq('id', modalQuotaTier.tier.id);
    } else {
      const combinedNullTiers = quotaTiers.filter((t) => t.dimension === 'combined' && t.user_group == null);
      const nextOrder = Math.max(0, ...combinedNullTiers.map((t) => (t.sort_order ?? 0) + 1));
      await supabase.from('holiday_quota_tiers').insert({ dimension: 'combined', user_group: null, max_people: quotaTierForm.max_people, max_leave: quotaTierForm.max_leave, sort_order: nextOrder });
    }
    setModalQuotaTier({ open: false, tier: null });
    invalidate('holiday_quota_tiers');
    supabase.from('holiday_quota_tiers').select('id, dimension, user_group, max_people, max_leave, sort_order').order('dimension').order('user_group').order('max_people').then(({ data }) => setQuotaTiers((data || []) as HolidayQuotaTier[]));
  };

  const deleteQuotaTier = async (id: string) => {
    if (!confirm('ลบเงื่อนไขนี้?')) return;
    await supabase.from('holiday_quota_tiers').delete().eq('id', id);
    invalidate('holiday_quota_tiers');
    setQuotaTiers((prev) => prev.filter((t) => t.id !== id));
  };

  const filteredHolidayQuotaTiers = quotaTiers
    .filter((t) => t.dimension === 'combined' && t.user_group == null)
    .slice()
    .sort((a, b) => {
      if ((a.sort_order ?? 0) !== (b.sort_order ?? 0)) return (a.sort_order ?? 0) - (b.sort_order ?? 0);
      return a.max_people - b.max_people;
    });

  const saveShiftTimes = async () => {
    if (!modalShift.shift?.id) return;
    const start = toTimePayload(shiftForm.start_time);
    const end = toTimePayload(shiftForm.end_time);
    if (!start || !end) {
      alert('กรุณาระบุเวลาเริ่มงานและเวลาเลิกงาน');
      return;
    }
    await supabase.from('shifts').update({ start_time: start, end_time: end }).eq('id', modalShift.shift.id);
    setModalShift({ open: false, shift: null });
    refetchBranchesShifts();
  };

  const loadMealSettings = () => {
    supabase.from('meal_settings').select('id, effective_from, is_enabled, rounds_json, scope_meal_quota_by_website, scope_holiday_quota_by_website, max_holiday_days_per_person_per_month').order('effective_from', { ascending: false }).limit(1).maybeSingle().then(({ data }) => {
      setMealSettings((data || null) as MealSettings | null);
      if (data) {
        const json = (data as MealSettings).rounds_json ?? {};
        setMealSettingsForm({
          is_enabled: (data as MealSettings).is_enabled,
          max_per_work_date: (json.max_per_work_date as number | undefined) ?? 2,
          scope_meal_quota_by_website: (data as MealSettings).scope_meal_quota_by_website !== false,
          scope_holiday_quota_by_website: (data as MealSettings).scope_holiday_quota_by_website !== false,
          max_holiday_days_per_person_per_month: (data as MealSettings).max_holiday_days_per_person_per_month ?? 4,
        });
        const uiRounds = Array.isArray(json.rounds)
          ? (json.rounds as Array<{ name?: string; slots?: Array<{ start: string; end: string }> }>).map((r) => ({
              name: r.name ?? '',
              slots: (r.slots ?? []).map((s) => ({ start: s.start, end: s.end })),
            }))
          : [];
        setRounds(uiRounds);
      } else {
        setMealSettingsForm({ is_enabled: true, max_per_work_date: 2, scope_meal_quota_by_website: true, scope_holiday_quota_by_website: true, max_holiday_days_per_person_per_month: 4 });
        setRounds([]);
      }
    });
  };

  const saveMealSettings = async () => {
    const safeRounds = rounds.map((r, idx) => ({
      key: `round_${idx}`,
      name: r.name || `รอบที่ ${idx + 1}`,
      slots: r.slots
        .filter((s) => s.start && s.end)
        .map((s) => ({ start: s.start, end: s.end })),
    }));
    const roundsJson: MealSettings['rounds_json'] = {
      max_per_work_date: mealSettingsForm.max_per_work_date ?? 2,
      rounds: safeRounds,
    };
    if (mealSettings?.id) {
      await supabase.from('meal_settings').update({
        is_enabled: mealSettingsForm.is_enabled,
        rounds_json: roundsJson,
        scope_meal_quota_by_website: mealSettingsForm.scope_meal_quota_by_website,
        scope_holiday_quota_by_website: mealSettingsForm.scope_holiday_quota_by_website,
        max_holiday_days_per_person_per_month: mealSettingsForm.max_holiday_days_per_person_per_month ?? 4,
      }).eq('id', mealSettings.id);
    } else {
      await supabase.from('meal_settings').insert({
        effective_from: format(new Date(), 'yyyy-MM-dd'),
        is_enabled: mealSettingsForm.is_enabled,
        rounds_json: roundsJson,
        scope_meal_quota_by_website: mealSettingsForm.scope_meal_quota_by_website,
        scope_holiday_quota_by_website: mealSettingsForm.scope_holiday_quota_by_website,
        max_holiday_days_per_person_per_month: mealSettingsForm.max_holiday_days_per_person_per_month ?? 4,
      });
    }
    loadMealSettings();
  };

  const saveMealQuotaRule = async () => {
    if (mealQuotaForm.on_duty_threshold < 0 || mealQuotaForm.max_concurrent < 1) {
      alert('กรุณากรอกคน (≤) และจองพร้อมกันได้ที่ถูกต้อง');
      return;
    }
    if (mealQuotaForm.max_concurrent > mealQuotaForm.on_duty_threshold) {
      alert('จองพร้อมกันได้ต้องไม่เกินจำนวนคนอยู่ปฏิบัติ (เป็นขั้น)');
      return;
    }
    const branchId = mealQuotaForm.branch_id || null;
    const shiftId = mealQuotaForm.shift_id || null;
    const websiteId = mealQuotaForm.website_id || null;
    const userGroup = mealQuotaForm.user_group || null;
    if (modalMealQuota.rule?.id) {
      await supabase.from('meal_quota_rules').update({
        on_duty_threshold: mealQuotaForm.on_duty_threshold,
        max_concurrent: mealQuotaForm.max_concurrent,
      }).eq('id', modalMealQuota.rule.id);
    } else {
      await supabase.from('meal_quota_rules').insert({
        branch_id: branchId,
        shift_id: shiftId,
        website_id: websiteId,
        user_group: userGroup,
        on_duty_threshold: mealQuotaForm.on_duty_threshold,
        max_concurrent: mealQuotaForm.max_concurrent,
      });
    }
    setModalMealQuota({ open: false, rule: null });
    invalidate('meal_quota_rules');
    supabase.from('meal_quota_rules').select('id, branch_id, shift_id, website_id, user_group, on_duty_threshold, max_concurrent').order('on_duty_threshold').then(({ data }) => setMealQuotaRules((data || []) as MealQuotaRule[]));
  };

  const saveLeaveType = async () => {
    if (!leaveTypeForm.code.trim() || !leaveTypeForm.name.trim()) {
      alert('กรุณากรอกรหัสและชื่อ');
      return;
    }
    if (modalLeaveType.leaveType?.code) {
      await supabase.from('leave_types').update({ name: leaveTypeForm.name.trim(), color: leaveTypeForm.color || null, description: leaveTypeForm.description.trim() || null }).eq('code', modalLeaveType.leaveType.code);
    } else {
      await supabase.from('leave_types').insert({ code: leaveTypeForm.code.trim().toUpperCase(), name: leaveTypeForm.name.trim(), color: leaveTypeForm.color || null, description: leaveTypeForm.description.trim() || null });
    }
    setModalLeaveType({ open: false, leaveType: null });
    invalidate('leave_types');
    supabase.from('leave_types').select('code, name, color, description').order('code').then(({ data }) => setLeaveTypes((data || []) as LeaveType[]));
  };

  const deleteLeaveType = async (code: string) => {
    if (code === 'X' || !confirm('ลบประเภทการลานี้? (ถ้ามีการใช้งานอยู่จะผิดพลาด)')) return;
    await supabase.from('leave_types').delete().eq('code', code);
    invalidate('leave_types');
    setLeaveTypes((prev) => prev.filter((lt) => lt.code !== code));
    setModalLeaveType({ open: false, leaveType: null });
  };

  const cardClass = 'rounded-lg border border-premium-gold/15 p-3 sm:p-4';
  const sectionHeaderClass = 'flex flex-wrap items-center justify-between gap-2 mb-2';
  const sectionTitleClass = 'text-premium-gold font-semibold text-[15px]';
  const tableWrapClass = 'overflow-x-auto rounded border border-premium-gold/15';
  const tableClass = 'w-full text-[13px]';
  const thClass = 'text-left px-2 py-2 border-b border-premium-gold/20 text-premium-gold font-medium';
  const tdClass = 'px-2 py-2 border-b border-premium-gold/10 text-gray-200';
  const actionColClass = 'w-20 px-2 py-2 border-b border-premium-gold/10';
  const iconBtnClass = 'w-7 h-7 shrink-0 inline-flex items-center justify-center';
  const btnCompact = 'h-8 px-3 text-[13px] border border-premium-gold text-premium-gold hover:bg-premium-gold/10 rounded font-medium transition';

  const gridRow2 = 'grid grid-cols-1 md:grid-cols-2 gap-3';
  const sectionGap = 'mb-3';
  const colStack = 'flex flex-col gap-3 min-w-0';

  const isAdmin = profile?.role === 'admin';
  const canRunApplyShift = isAdmin || profile?.role === 'manager' || profile?.role === 'instructor_head';

  /** วันนี้ (YYYY-MM-DD) ตาม timezone Asia/Bangkok สำหรับ apply_scheduled_shift_changes_for_date */
  function todayBangkok(): string {
    return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Bangkok' });
  }

  const runApplyShiftChangesToday = async () => {
    setApplyShiftResult(null);
    setApplyShiftLoading(true);
    try {
      const { data, error } = await supabase.rpc('apply_scheduled_shift_changes_for_date', { p_date: todayBangkok() });
      if (error) throw error;
      setApplyShiftResult({ count: typeof data === 'number' ? data : 0 });
    } catch (e) {
      setApplyShiftResult({ error: e instanceof Error ? e.message : 'เกิดข้อผิดพลาด' });
    } finally {
      setApplyShiftLoading(false);
    }
  };

  return (
    <div className="w-full max-w-full px-4 py-4 md:py-5">
      <h1 className="text-premium-gold text-[18px] font-semibold mb-4">ตั้งค่า</h1>

      {/* การเข้าถึงผ่านมือถือ (Desktop-only toggle) — เฉพาะ Admin แก้ไขได้ */}
      <section className={`${cardClass} ${sectionGap}`}>
        <div className={sectionHeaderClass}>
          <h2 className={sectionTitleClass}>การเข้าถึงผ่านมือถือ</h2>
        </div>
        <p className="text-gray-500/90 text-[12px] mb-3">เปิดหรือปิดการเข้าใช้งานจากมือถือ/แท็บเล็ต — ปิด = อนุญาตเฉพาะ Desktop เท่านั้น (ทั้งเว็บและ API)</p>
        {loadingAllowMobile ? (
          <p className="text-gray-400 text-[13px]">กำลังโหลด...</p>
        ) : !isAdmin ? (
          <p className="text-amber-200/90 text-[13px]">เฉพาะ Admin เท่านั้นที่เปลี่ยนการตั้งค่านี้ได้</p>
        ) : (
          <div className="flex flex-wrap items-center gap-4">
            <button
              type="button"
              onClick={() => toggleAllowMobile(true)}
              className={`h-9 px-4 rounded font-medium text-[13px] transition ${allowMobile ? 'bg-premium-gold text-premium-dark border border-premium-gold' : 'border border-premium-gold/40 text-premium-gold/80 hover:bg-premium-gold/10'}`}
            >
              เปิดให้มือถือเข้า
            </button>
            <button
              type="button"
              onClick={() => toggleAllowMobile(false)}
              className={`h-9 px-4 rounded font-medium text-[13px] transition ${!allowMobile ? 'bg-premium-gold text-premium-dark border border-premium-gold' : 'border border-premium-gold/40 text-premium-gold/80 hover:bg-premium-gold/10'}`}
            >
              ปิด (Desktop only)
            </button>
            <span className="text-gray-400 text-[13px]">
              สถานะปัจจุบัน: <strong className={allowMobile ? 'text-green-400' : 'text-amber-400'}>{allowMobile ? 'เปิดให้มือถือเข้า' : 'ปิด — Desktop only'}</strong>
            </span>
          </div>
        )}
      </section>

      {/* ย้ายกะอัตโนมัติ — อัปเดตโปรไฟล์กะเมื่อถึงวันที่มีการตั้งไว้ (ต้องมี Cron หรือกดปุ่ม) */}
      {canRunApplyShift && (
        <section className={`${cardClass} ${sectionGap}`}>
          <div className={sectionHeaderClass}>
            <h2 className={sectionTitleClass}>ย้ายกะอัตโนมัติ</h2>
          </div>
          <p className="text-gray-500/90 text-[12px] mb-3">
            เมื่อถึงวันที่มีการตั้งเวลาย้ายกะ/สลับกะ ระบบจะอัปเดต <strong>กะ/แผนกในโปรไฟล์</strong> ให้ตรงกับกะปลายทาง — <strong className="text-premium-gold/90">ตั้ง Cron ใน Supabase แล้วจะอัตโนมัติทุกวัน (00:01 น.) ไม่ต้องมากดปุ่มทุกวัน</strong> หรือกดปุ่มด้านล่างเพื่ออัปเดตวันนี้ทันที
          </p>
          <div className="flex flex-wrap items-center gap-3">
            <Button variant="gold" onClick={runApplyShiftChangesToday} loading={applyShiftLoading} disabled={applyShiftLoading}>
              อัปเดตกะตามกำหนดวันนี้
            </Button>
            {applyShiftResult && (
              <span className="text-[13px]">
                {'count' in applyShiftResult ? (
                  <span className="text-green-400">อัปเดตแล้ว {applyShiftResult.count} รายการ — แนะนำให้พนักงานรีเฟรชหรือออก/เข้าสู่ระบบเพื่อเห็นกะใหม่</span>
                ) : (
                  <span className="text-red-400">{applyShiftResult.error}</span>
                )}
              </span>
            )}
          </div>
          <p className="text-gray-500/80 text-[11px] mt-2">ตั้ง Cron: ดูไฟล์ <code className="bg-premium-dark px-1 rounded">supabase/sql/cron_apply_shift_changes_setup.sql</code></p>
        </section>
      )}

      {/* แถว 1: จัดการแผนก | จัดการกะ — 2 คอลัมน์บนจอใหญ่ */}
      <div className={`${gridRow2} ${sectionGap}`}>
        <section className={`${cardClass} min-w-0`}>
          <div className={sectionHeaderClass}>
            <h2 className={sectionTitleClass}>จัดการแผนก</h2>
            <button type="button" className={btnCompact} onClick={() => { setBranchForm({ name: '', code: '', active: true }); setModalBranch({ open: true, branch: null }); }}>เพิ่มแผนก</button>
          </div>
          <p className="text-gray-500/90 text-[12px] mb-2">เพิ่ม/แก้ไข/ปิดใช้แผนก — พนักงานประจำและพนักงานออนไลน์ต้องมีแผนกประจำ</p>
          <div className={tableWrapClass}>
            <table className={tableClass}>
              <thead>
                <tr>
                  <th className={thClass}>ชื่อ</th>
                  <th className={thClass}>รหัส</th>
                  <th className={thClass}>สถานะ</th>
                  <th className={`${thClass} w-20`}>ดำเนินการ</th>
                </tr>
              </thead>
              <tbody>
                {branches.map((b) => (
                  <tr key={b.id} className="border-b border-premium-gold/10 h-9 min-h-[36px]">
                    <td className={tdClass}>{b.name}</td>
                    <td className={`${tdClass} font-mono text-premium-gold/90 text-[12px]`}>{b.code ?? '-'}</td>
                    <td className={tdClass}>{b.active ? <span className="text-green-400 text-[12px]">เปิด</span> : <span className="text-gray-500 text-[12px]">ปิด</span>}</td>
                    <td className={actionColClass}>
                      <BtnEdit className={iconBtnClass} onClick={() => { setBranchForm({ name: b.name, code: b.code || '', active: b.active }); setModalBranch({ open: true, branch: b }); }} title="แก้ไข" />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        <section className={`${cardClass} min-w-0`}>
          <div className={sectionHeaderClass}>
            <h2 className={sectionTitleClass}>จัดการกะ (เวลาทำงาน)</h2>
          </div>
          <p className="text-gray-500/90 text-[12px] mb-2">ตั้งเวลาเริ่มงาน–เลิกงานของแต่ละกะ — กะดึกข้ามเที่ยงคืน ตั้งเลิกงานเป็นเวลาวันถัดไป (เช่น 08:00)</p>
          <div className={tableWrapClass}>
            <table className={tableClass}>
              <thead>
                <tr>
                  <th className={thClass}>ชื่อกะ</th>
                  <th className={thClass}>เริ่ม</th>
                  <th className={thClass}>เลิก</th>
                  <th className={`${thClass} w-20`}>ดำเนินการ</th>
                </tr>
              </thead>
              <tbody>
                {shifts.map((s) => (
                  <tr key={s.id} className="border-b border-premium-gold/10 h-9 min-h-[36px]">
                    <td className={tdClass}>{s.name}</td>
                    <td className={`${tdClass} text-gray-400 font-mono`}>{s.start_time ? s.start_time.slice(0, 5) : '—'}</td>
                    <td className={`${tdClass} text-gray-400 font-mono`}>{s.end_time ? s.end_time.slice(0, 5) : '—'}</td>
                    <td className={actionColClass}>
                      <BtnEdit className={iconBtnClass} onClick={() => { setShiftForm({ start_time: toTimeInputValue(s.start_time), end_time: toTimeInputValue(s.end_time) }); setModalShift({ open: true, shift: s }); }} title="ตั้งเวลา" />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      </div>

      {/* แถว 2: จองเวลาพักทานอาหาร — เต็มความกว้าง (เนื้อหามาก) */}
      <section className={`${cardClass} ${sectionGap}`}>
        <div className={sectionHeaderClass}>
          <h2 className={sectionTitleClass}>จองเวลาพักทานอาหาร</h2>
          <button type="button" className={btnCompact} onClick={saveMealSettings}>บันทึกตั้งค่าพักอาหาร</button>
        </div>
        <p className="text-gray-500/90 text-[12px] mb-2">เปิด/ปิดการจองพักอาหาร · รอบและช่วงเวลา · โควต้าตามจำนวนคนอยู่ปฏิบัติ</p>
        <p className="text-amber-200/80 text-[12px] mb-2">แต่ละคนจองได้สูงสุด {mealSettingsForm.max_per_work_date ?? 2} ช่วงต่อวัน และ 1 ช่วงต่อรอบ</p>
        <div className="space-y-2 mb-3 p-3 rounded border border-premium-gold/15 bg-premium-dark/30">
          <div className="flex flex-wrap items-center gap-4">
            <label className="flex items-center gap-2 text-gray-300 text-[13px]">
              <span>จำนวนจองสูงสุดต่อวัน:</span>
              <input
                type="number"
                min={1}
                max={10}
                value={mealSettingsForm.max_per_work_date ?? 2}
                onChange={(e) => setMealSettingsForm((f) => ({ ...f, max_per_work_date: Math.max(1, parseInt(String(e.target.value), 10) || 2) }))}
                className="w-14 rounded border border-premium-gold/40 bg-premium-dark px-2 py-1 text-white text-[13px]"
              />
            </label>
            <label className="flex items-center gap-2 text-gray-300 text-[13px]">
              <input
                type="checkbox"
                checked={mealSettingsForm.is_enabled}
                onChange={(e) => setMealSettingsForm((f) => ({ ...f, is_enabled: e.target.checked }))}
                className="rounded border-premium-gold/40"
              />
              <span>เปิดใช้งานจองพักอาหาร</span>
            </label>
            <label className="flex items-center gap-2 text-gray-300 text-[13px]">
              <input
                type="checkbox"
                checked={mealSettingsForm.scope_meal_quota_by_website}
                onChange={(e) => setMealSettingsForm((f) => ({ ...f, scope_meal_quota_by_website: e.target.checked }))}
                className="rounded border-premium-gold/40"
              />
              <span>ใช้เว็บหลักเดียวกันในการนับโควต้า (แยกโควต้าตามเว็บ)</span>
            </label>
          </div>

          <div>
            <div className="flex items-center justify-between gap-2 mb-1.5">
              <h3 className="text-premium-gold/90 font-semibold text-[13px]">รอบและช่วงเวลา</h3>
              <button type="button" className={btnCompact} onClick={() => setRounds((prev) => [...prev, { name: '', slots: [] }])}>เพิ่มรอบ</button>
            </div>
            <div className="space-y-1.5">
              {rounds.map((round, idx) => (
                <div key={idx} className="border border-premium-gold/15 rounded p-2 bg-premium-dark/50">
                  <div className="flex flex-wrap items-center gap-2 mb-1.5">
                    <input
                      type="text"
                      value={round.name}
                      onChange={(e) =>
                        setRounds((prev) =>
                          prev.map((r, i) => (i === idx ? { ...r, name: e.target.value } : r))
                        )
                      }
                      className="flex-1 min-w-[8rem] h-8 bg-premium-dark border border-premium-gold/30 rounded px-2 text-white text-[13px]"
                      placeholder={`รอบที่ ${idx + 1}`}
                    />
                    <button type="button" className={btnCompact} onClick={() =>
                      setRounds((prev) =>
                        prev.map((r, i) =>
                          i === idx ? { ...r, slots: [...r.slots, { start: '', end: '' }] } : r
                        )
                      )
                    }>เพิ่มช่วงเวลา</button>
                    <button type="button" className="h-8 px-3 text-[13px] text-red-400 hover:bg-red-400/10 rounded transition" onClick={() => setRounds((prev) => prev.filter((_, i) => i !== idx))}>ลบรอบ</button>
                  </div>
                  {round.slots.length > 0 && (
                    <div className="flex flex-wrap gap-1.5">
                      {round.slots.map((slot, sIdx) => (
                        <div
                          key={sIdx}
                          className="flex items-center gap-1.5 h-7 px-2 rounded border border-premium-gold/25 bg-premium-dark/80"
                        >
                          <input
                            type="time"
                            value={slot.start}
                            onChange={(e) =>
                              setRounds((prev) =>
                                prev.map((r, i) =>
                                  i === idx
                                    ? {
                                        ...r,
                                        slots: r.slots.map((s, j) =>
                                          j === sIdx ? { ...s, start: e.target.value } : s
                                        ),
                                      }
                                    : r
                                )
                              )
                            }
                            className="bg-transparent border-0 rounded px-1 py-0.5 text-[12px] text-white w-[72px]"
                          />
                          <span className="text-gray-400 text-[12px]">–</span>
                          <input
                            type="time"
                            value={slot.end}
                            onChange={(e) =>
                              setRounds((prev) =>
                                prev.map((r, i) =>
                                  i === idx
                                    ? {
                                        ...r,
                                        slots: r.slots.map((s, j) =>
                                          j === sIdx ? { ...s, end: e.target.value } : s
                                        ),
                                      }
                                    : r
                                )
                              )
                            }
                            className="bg-transparent border-0 rounded px-1 py-0.5 text-[12px] text-white w-[72px]"
                          />
                          <button
                            type="button"
                            className="text-red-400/90 hover:text-red-400 text-[12px] p-0.5"
                            onClick={() =>
                              setRounds((prev) =>
                                prev.map((r, i) =>
                                  i === idx ? { ...r, slots: r.slots.filter((_, j) => j !== sIdx) } : r
                                )
                              )
                            }
                            aria-label="ลบช่วง"
                          >
                            ✕
                          </button>
                        </div>
                      ))}
                    </div>
                  )}
                  {round.slots.length === 0 && (
                    <p className="text-gray-500 text-[12px]">ยังไม่มีช่วงเวลาในรอบนี้</p>
                  )}
                </div>
              ))}
              {rounds.length === 0 && (
                <p className="text-gray-500 text-[12px]">ยังไม่ได้กำหนดรอบพักอาหาร</p>
              )}
            </div>
          </div>
        </div>
      </section>

      {/* แถว 3: คอลัมน์ซ้าย = โควต้าพักอาหาร + กติกาโควต้าวันหยุด | คอลัมน์ขวา = ตั้งค่าจองวันหยุด + ประเภทการลา */}
      <div className={`grid grid-cols-1 lg:grid-cols-2 gap-4 ${sectionGap}`}>
        <div className={colStack}>
          <section className={`${cardClass} min-w-0`}>
            <div className={sectionHeaderClass}>
              <h2 className={sectionTitleClass}>โควต้าพักอาหาร</h2>
              <button
                type="button"
                className={btnCompact}
                onClick={() => {
                  setMealQuotaForm({
                    branch_id: '',
                    shift_id: '',
                    website_id: '',
                    user_group: '',
                    on_duty_threshold: 10,
                    max_concurrent: 2,
                  });
                  setModalMealQuota({ open: true, rule: null });
                }}
              >
                เพิ่มโควต้า
              </button>
            </div>
            <p className="text-gray-500/90 text-[12px] mb-2">
              การนับ: แผนก+กะ+กลุ่ม{mealSettingsForm.scope_meal_quota_by_website ? '+เว็บ' : ''} — คนอยู่ปฏิบัติ ≤ X → จองพร้อมกันได้ Y คน
            </p>
            <div className={tableWrapClass}>
              <table className={tableClass}>
                <thead>
                  <tr>
                    <th className={thClass}>คนอยู่ปฏิบัติ (≤)</th>
                    <th className={thClass}>จองได้ (คน)</th>
                    <th className={`${thClass} w-20`}>ดำเนินการ</th>
                  </tr>
                </thead>
                <tbody>
                  {mealQuotaRules
                    .slice()
                    .sort((a, b) => a.on_duty_threshold - b.on_duty_threshold)
                    .map((r) => (
                    <tr key={r.id} className="border-b border-premium-gold/10 h-9 min-h-[36px]">
                      <td className={tdClass}>{r.on_duty_threshold}</td>
                      <td className={tdClass}>{r.max_concurrent}</td>
                      <td className={actionColClass}>
                        <span className="inline-flex items-center gap-0.5">
                          <BtnEdit className={iconBtnClass} onClick={() => {
                            setMealQuotaForm({
                              branch_id: r.branch_id ?? '',
                              shift_id: r.shift_id ?? '',
                              website_id: r.website_id ?? '',
                              user_group: (r.user_group ?? '') as UserGroup | '',
                              on_duty_threshold: r.on_duty_threshold,
                              max_concurrent: r.max_concurrent,
                            });
                            setModalMealQuota({ open: true, rule: r });
                          }} title="แก้ไข" />
                          <BtnDelete className={iconBtnClass} onClick={async () => {
                            if (confirm('ลบ?')) {
                              await supabase.from('meal_quota_rules').delete().eq('id', r.id);
                              setMealQuotaRules((prev) => prev.filter((x) => x.id !== r.id));
                            }
                          }} title="ลบ" />
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          <section className={`${cardClass} min-w-0`}>
            <div className={sectionHeaderClass}>
              <h2 className={sectionTitleClass}>กติกาโควต้าวันหยุด (แบบขั้น)</h2>
              <button
                type="button"
                className={btnCompact}
                onClick={() => {
                  setQuotaTierForm({ max_people: 4, max_leave: 1 });
                  setModalQuotaTier({ open: true, tier: null });
                }}
              >
                เพิ่มเงื่อนไข
              </button>
            </div>
            <div className="bg-premium-darker/50 border border-premium-gold/15 rounded px-2.5 py-2 mb-2">
              <p className="text-gray-300 text-[13px] mb-0.5">
                <strong className="text-premium-gold/90">ขอบเขต:</strong> แผนก+กะ+กลุ่ม{mealSettingsForm.scope_holiday_quota_by_website ? '+เว็บ' : ''} — คน ≤ X → หยุดได้ Y คน/วัน
              </p>
            </div>
            <label className="flex items-center gap-2 text-gray-400 text-[13px] mb-2">
              <input
                type="checkbox"
                checked={mealSettingsForm.scope_holiday_quota_by_website}
                onChange={(e) => setMealSettingsForm((f) => ({ ...f, scope_holiday_quota_by_website: e.target.checked }))}
                className="rounded border-premium-gold/40"
              />
              <span>แยกโควต้าตามเว็บ</span>
            </label>

            <div className={tableWrapClass}>
              <table className={`${tableClass} min-w-[200px]`}>
                <thead>
                  <tr className="bg-premium-gold/10">
                    <th className={thClass}>คน (≤)</th>
                    <th className={thClass}>หยุด/วัน</th>
                    <th className={`${thClass} w-20 text-right`}>ดำเนินการ</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredHolidayQuotaTiers.map((t) => (
                    <tr key={t.id} className="border-b border-premium-gold/10 h-9 min-h-[36px] hover:bg-premium-gold/5 transition-colors">
                      <td className={`${tdClass} tabular-nums`}>{t.max_people}</td>
                      <td className={`${tdClass} tabular-nums`}>{t.max_leave}</td>
                      <td className={`${actionColClass} text-right`}>
                        <span className="inline-flex items-center gap-0.5 justify-end">
                          <BtnEdit className={iconBtnClass} onClick={() => { setQuotaTierForm({ max_people: t.max_people, max_leave: t.max_leave }); setModalQuotaTier({ open: true, tier: t }); }} title="แก้ไข" />
                          <BtnDelete className={iconBtnClass} onClick={() => deleteQuotaTier(t.id)} title="ลบ" />
                        </span>
                      </td>
                    </tr>
                  ))}
                  {filteredHolidayQuotaTiers.length === 0 && (
                    <tr>
                      <td className="px-2 py-4 text-center text-gray-500 text-[13px]" colSpan={3}>
                        ยังไม่มีเงื่อนไข — กด &quot;เพิ่มเงื่อนไข&quot;
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </section>
        </div>

        <div className={colStack}>
          <section className={`${cardClass} min-w-0`}>
            <div className={sectionHeaderClass}>
              <h2 className={sectionTitleClass}>กติกาวันหยุด (กติกากลาง)</h2>
              <button type="button" className={btnCompact} onClick={saveGlobalHolidayDays}>บันทึก</button>
            </div>
            <p className="text-gray-500/90 text-[12px] mb-2">แต่ละคนจองวันหยุดได้สูงสุดกี่วันต่อเดือน — ใช้บังคับทุกแผนก (หัวหน้าไม่สามารถตั้งเกินนี้)</p>
            <div className="flex items-center gap-3">
              <label className="text-gray-400 text-[13px]">แต่ละคนหยุดได้สูงสุด (วัน/เดือน)</label>
              <input type="number" min={1} value={mealSettingsForm.max_holiday_days_per_person_per_month ?? 4} onChange={(e) => setMealSettingsForm((f) => ({ ...f, max_holiday_days_per_person_per_month: parseInt(e.target.value, 10) || 1 }))} className="w-20 h-8 bg-premium-dark border border-premium-gold/30 rounded px-2 text-white text-[13px]" />
            </div>
          </section>

          <section className={`${cardClass} min-w-0`}>
            <div className={sectionHeaderClass}>
              <h2 className={sectionTitleClass}>ตั้งค่าการจองวันหยุด</h2>
              <button type="button" className={btnCompact} onClick={() => { setBookingForm({ target_year_month: format(new Date(), 'yyyy-MM'), open_from: '', open_until: '', max_days_per_person: mealSettingsForm.max_holiday_days_per_person_per_month ?? 4 }); setModalBooking({ open: true, config: null }); }}>เพิ่มการตั้งค่า</button>
            </div>
            <p className="text-gray-500/90 text-[12px] mb-2">เดือนเป้าหมาย · ช่วงเปิดจอง (จาก–ถึง) เท่านั้น — วัน/คน ใช้กติกากลางด้านบน</p>
            <div className={tableWrapClass}>
              <table className={tableClass}>
                <thead>
                  <tr>
                    <th className={thClass}>เดือน</th>
                    <th className={thClass}>จาก</th>
                    <th className={thClass}>ถึง</th>
                    <th className={`${thClass} w-20`}>ดำเนินการ</th>
                  </tr>
                </thead>
                <tbody>
                  {bookingConfigs.map((c) => (
                    <tr key={c.id} className="border-b border-premium-gold/10 h-9 min-h-[36px]">
                      <td className={tdClass}>{c.target_year_month}</td>
                      <td className={`${tdClass} text-gray-400 text-[12px]`}>{c.open_from}</td>
                      <td className={`${tdClass} text-gray-400 text-[12px]`}>{c.open_until}</td>
                      <td className={actionColClass}>
                        <BtnEdit className={iconBtnClass} onClick={() => { setBookingForm({ target_year_month: c.target_year_month, open_from: c.open_from, open_until: c.open_until, max_days_per_person: c.max_days_per_person }); setModalBooking({ open: true, config: c }); }} title="แก้ไข" />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          <section className={`${cardClass} min-w-0`}>
            <div className={sectionHeaderClass}>
              <h2 className={sectionTitleClass}>ประเภทการลา</h2>
              <button type="button" className={btnCompact} onClick={() => { setLeaveTypeForm({ code: '', name: '', color: '#9CA3AF', description: '' }); setModalLeaveType({ open: true, leaveType: null }); }}>เพิ่มประเภท</button>
            </div>
            <p className="text-gray-500/90 text-[12px] mb-2">รหัส · ชื่อ · สี (ใช้ในตารางวันหยุด) — X เป็นรหัสวันหยุด (ค่าเริ่มต้น)</p>
            <div className={tableWrapClass}>
              <table className={tableClass}>
                <thead>
                  <tr>
                    <th className={thClass}>รหัส</th>
                    <th className={thClass}>ชื่อ</th>
                    <th className={thClass}>สี</th>
                    <th className={thClass}>คำอธิบาย</th>
                    <th className={`${thClass} w-20`}>ดำเนินการ</th>
                  </tr>
                </thead>
                <tbody>
                  {leaveTypes.map((lt) => (
                    <tr key={lt.code} className="border-b border-premium-gold/10 h-9 min-h-[36px]">
                      <td className={`${tdClass} font-mono text-premium-gold/90 text-[12px]`}>{lt.code}</td>
                      <td className={tdClass}>{lt.name}</td>
                      <td className={tdClass}>
                        <span className="inline-flex items-center gap-1.5">
                          <input type="color" value={lt.color || '#9CA3AF'} readOnly className="w-5 h-5 rounded border border-premium-gold/30 cursor-default" />
                          <span className="text-gray-400 text-[12px] font-mono">{lt.color || '—'}</span>
                        </span>
                      </td>
                      <td className={`${tdClass} text-gray-400 text-[12px] max-w-[10rem] truncate`}>{lt.description || '—'}</td>
                      <td className={actionColClass}>
                        <span className="inline-flex items-center gap-0.5">
                          <BtnEdit className={iconBtnClass} onClick={() => { setLeaveTypeForm({ code: lt.code, name: lt.name, color: lt.color || '#9CA3AF', description: lt.description || '' }); setModalLeaveType({ open: true, leaveType: lt }); }} title="แก้ไข" />
                          {lt.code !== 'X' && <BtnDelete className={iconBtnClass} onClick={() => deleteLeaveType(lt.code)} title="ลบ" />}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </div>


      {/* กติกาการพักแบบเดิมถูกถอดออก (รวมในระบบจองพักอาหารแล้ว) */}

      <Modal open={modalBranch.open} onClose={() => setModalBranch({ open: false, branch: null })} title={modalBranch.branch ? 'แก้ไขแผนก' : 'เพิ่มแผนก'} footer={
        <>
          <Button variant="ghost" className="h-8 px-3 text-[13px]" onClick={() => setModalBranch({ open: false, branch: null })}>ยกเลิก</Button>
          <Button variant="gold" className="h-8 px-3 text-[13px]" onClick={saveBranch} disabled={!branchForm.name.trim()}>บันทึก</Button>
        </>
      }>
        <div className="space-y-2">
          <div>
            <label className="block text-gray-400 text-[12px] mb-0.5">ชื่อแผนก *</label>
            <input value={branchForm.name} onChange={(e) => setBranchForm((f) => ({ ...f, name: e.target.value }))} className="w-full h-8 bg-premium-dark border border-premium-gold/30 rounded px-2 text-white text-[13px]" placeholder="เช่น แผนกหลัก" />
          </div>
          <div>
            <label className="block text-gray-400 text-[12px] mb-0.5">รหัส (ไม่บังคับ)</label>
            <input value={branchForm.code} onChange={(e) => setBranchForm((f) => ({ ...f, code: e.target.value }))} className="w-full h-8 bg-premium-dark border border-premium-gold/30 rounded px-2 text-white font-mono text-[13px]" placeholder="เช่น MAIN" />
          </div>
          {modalBranch.branch && (
            <label className="flex items-center gap-2 text-gray-400 text-[13px]">
              <input type="checkbox" checked={branchForm.active} onChange={(e) => setBranchForm((f) => ({ ...f, active: e.target.checked }))} className="rounded border-premium-gold/40" />
              <span>เปิดใช้งาน</span>
            </label>
          )}
        </div>
      </Modal>

      <Modal open={modalBooking.open} onClose={() => setModalBooking({ open: false, config: null })} title={modalBooking.config ? 'แก้ไขตั้งค่าจองวันหยุด' : 'เพิ่มตั้งค่าจองวันหยุด'} footer={
        <>
          <Button variant="ghost" className="h-8 px-3 text-[13px]" onClick={() => setModalBooking({ open: false, config: null })}>ยกเลิก</Button>
          <Button variant="gold" className="h-8 px-3 text-[13px]" onClick={saveBookingConfig}>บันทึก</Button>
        </>
      }>
        <div className="space-y-2">
          <div>
            <label className="block text-gray-400 text-[12px] mb-0.5">เดือนเป้าหมาย (yyyy-MM)</label>
            <input value={bookingForm.target_year_month} onChange={(e) => setBookingForm((f) => ({ ...f, target_year_month: e.target.value }))} className="w-full h-8 bg-premium-dark border border-premium-gold/30 rounded px-2 text-white text-[13px]" placeholder="2026-03" disabled={!!modalBooking.config?.id} />
          </div>
          <div>
            <label className="block text-gray-400 text-[12px] mb-0.5">เปิดจองจาก (วันที่)</label>
            <input type="date" value={bookingForm.open_from} onChange={(e) => setBookingForm((f) => ({ ...f, open_from: e.target.value }))} className="w-full h-8 bg-premium-dark border border-premium-gold/30 rounded px-2 text-white text-[13px]" />
          </div>
          <div>
            <label className="block text-gray-400 text-[12px] mb-0.5">เปิดจองถึง (วันที่)</label>
            <input type="date" value={bookingForm.open_until} onChange={(e) => setBookingForm((f) => ({ ...f, open_until: e.target.value }))} className="w-full h-8 bg-premium-dark border border-premium-gold/30 rounded px-2 text-white text-[13px]" />
          </div>
          <p className="text-gray-500 text-[12px]">วันสูงสุดต่อคน ใช้กติกากลาง (แต่ละคนหยุดได้สูงสุด วัน/เดือน) จากด้านบน</p>
        </div>
      </Modal>

      <Modal open={modalQuotaTier.open} onClose={() => setModalQuotaTier({ open: false, tier: null })} title={modalQuotaTier.tier ? 'แก้ไขเงื่อนไขโควต้าวันหยุด' : 'เพิ่มเงื่อนไขโควต้าวันหยุด'} footer={
        <>
          <Button variant="ghost" className="h-8 px-3 text-[13px]" onClick={() => setModalQuotaTier({ open: false, tier: null })}>ยกเลิก</Button>
          <Button variant="gold" className="h-8 px-3 text-[13px]" onClick={saveQuotaTier} disabled={quotaTierForm.max_people < 1 || quotaTierForm.max_leave < 0}>บันทึก</Button>
        </>
      }>
        <div className="space-y-2">
          <div>
            <label className="block text-gray-400 text-[12px] mb-0.5">จำนวนคน (≤)</label>
            <input type="number" min={1} value={quotaTierForm.max_people} onChange={(e) => setQuotaTierForm((f) => ({ ...f, max_people: parseInt(e.target.value, 10) || 1 }))} className="w-full h-8 bg-premium-dark border border-premium-gold/30 rounded px-2 text-white text-[13px]" />
          </div>
          <div>
            <label className="block text-gray-400 text-[12px] mb-0.5">หยุดได้สูงสุด (คน/วัน)</label>
            <input type="number" min={0} value={quotaTierForm.max_leave} onChange={(e) => setQuotaTierForm((f) => ({ ...f, max_leave: parseInt(e.target.value, 10) || 0 }))} className="w-full h-8 bg-premium-dark border border-premium-gold/30 rounded px-2 text-white text-[13px]" />
          </div>
        </div>
      </Modal>

      <Modal open={modalShift.open} onClose={() => setModalShift({ open: false, shift: null })} title={modalShift.shift ? `ตั้งเวลากะ: ${modalShift.shift.name}` : 'ตั้งเวลากะ'} footer={
        <>
          <Button variant="ghost" className="h-8 px-3 text-[13px]" onClick={() => setModalShift({ open: false, shift: null })}>ยกเลิก</Button>
          <Button variant="gold" className="h-8 px-3 text-[13px]" onClick={saveShiftTimes} disabled={!shiftForm.start_time || !shiftForm.end_time}>บันทึก</Button>
        </>
      }>
        <div className="space-y-2">
          <p className="text-gray-400 text-[12px]">กะดึกที่ข้ามเที่ยงคืน: ตั้งเลิกงานเป็นเวลาวันถัดไป (เช่น 08:00) — ระบบนับวันทำงานเป็นวันที่เริ่มกะ</p>
          <div>
            <label className="block text-gray-400 text-[12px] mb-0.5">เวลาเริ่มงาน</label>
            <input type="time" value={shiftForm.start_time} onChange={(e) => setShiftForm((f) => ({ ...f, start_time: e.target.value }))} className="w-full h-8 bg-premium-dark border border-premium-gold/30 rounded px-2 text-white text-[13px]" />
          </div>
          <div>
            <label className="block text-gray-400 text-[12px] mb-0.5">เวลาเลิกงาน</label>
            <input type="time" value={shiftForm.end_time} onChange={(e) => setShiftForm((f) => ({ ...f, end_time: e.target.value }))} className="w-full h-8 bg-premium-dark border border-premium-gold/30 rounded px-2 text-white text-[13px]" />
          </div>
        </div>
      </Modal>

      <Modal open={modalMealQuota.open} onClose={() => setModalMealQuota({ open: false, rule: null })} title={modalMealQuota.rule ? 'แก้ไขโควต้าพักอาหาร' : 'เพิ่มโควต้าพักอาหาร'} footer={
        <>
          <Button variant="ghost" className="h-8 px-3 text-[13px]" onClick={() => setModalMealQuota({ open: false, rule: null })}>ยกเลิก</Button>
          <Button variant="gold" className="h-8 px-3 text-[13px]" onClick={saveMealQuotaRule}>บันทึก</Button>
        </>
      }>
        <div className="space-y-2">
          {!modalMealQuota.rule && (
            <p className="text-gray-400 text-[12px] mb-1">โควต้านี้ใช้กับทุกแผนก/กะ/กลุ่ม — การนับคนอยู่ปฏิบัติแยกตามแผนกเดียวกัน กะเดียวกัน กลุ่มเดียวกัน อยู่แล้ว</p>
          )}
          <div>
            <label className="block text-gray-400 text-[12px] mb-0.5">เมื่อคนอยู่ปฏิบัติ (≤) กี่คน</label>
            <input type="number" min={0} value={mealQuotaForm.on_duty_threshold} onChange={(e) => {
              const v = parseInt(e.target.value, 10) || 0;
              setMealQuotaForm((f) => ({ ...f, on_duty_threshold: v, max_concurrent: v === 0 ? 0 : Math.min(f.max_concurrent, v) }));
            }} className="w-full h-8 bg-premium-dark border border-premium-gold/30 rounded px-2 text-white text-[13px]" />
          </div>
          <div>
            <label className="block text-gray-400 text-[12px] mb-0.5">จองพักพร้อมกันได้ (คน) — ต้องไม่เกินคนอยู่ปฏิบัติ</label>
            <input type="number" min={1} max={mealQuotaForm.on_duty_threshold || undefined} value={mealQuotaForm.max_concurrent} onChange={(e) => setMealQuotaForm((f) => ({ ...f, max_concurrent: parseInt(e.target.value, 10) || 1 }))} className="w-full h-8 bg-premium-dark border border-premium-gold/30 rounded px-2 text-white text-[13px]" />
          </div>
        </div>
      </Modal>

      <Modal open={modalLeaveType.open} onClose={() => setModalLeaveType({ open: false, leaveType: null })} title={modalLeaveType.leaveType ? 'แก้ไขประเภทการลา' : 'เพิ่มประเภทการลา'} footer={
        <>
          <Button variant="ghost" className="h-8 px-3 text-[13px]" onClick={() => setModalLeaveType({ open: false, leaveType: null })}>ยกเลิก</Button>
          <Button variant="gold" className="h-8 px-3 text-[13px]" onClick={saveLeaveType}>บันทึก</Button>
        </>
      }>
        <div className="space-y-2">
          <div className="flex items-center gap-2 flex-wrap">
            <div className="flex-1 min-w-[6rem]">
              <label className="block text-gray-400 text-[12px] mb-0.5">รหัส</label>
              <input type="text" value={leaveTypeForm.code} onChange={(e) => setLeaveTypeForm((f) => ({ ...f, code: e.target.value.toUpperCase() }))} className="w-full h-8 bg-premium-dark border border-premium-gold/30 rounded px-2 text-white text-[13px] font-mono" placeholder="VL" disabled={!!modalLeaveType.leaveType?.code} />
            </div>
            <div className="flex-1 min-w-[8rem]">
              <label className="block text-gray-400 text-[12px] mb-0.5">ชื่อ</label>
              <input type="text" value={leaveTypeForm.name} onChange={(e) => setLeaveTypeForm((f) => ({ ...f, name: e.target.value }))} className="w-full h-8 bg-premium-dark border border-premium-gold/30 rounded px-2 text-white text-[13px]" placeholder="ลาพักร้อน" />
            </div>
          </div>
          <div className="flex items-center gap-2 flex-wrap">
            <div>
              <label className="block text-gray-400 text-[12px] mb-0.5">สี</label>
              <div className="flex items-center gap-2">
                <input type="color" value={leaveTypeForm.color} onChange={(e) => setLeaveTypeForm((f) => ({ ...f, color: e.target.value }))} className="w-7 h-7 rounded border border-premium-gold/30 cursor-pointer" />
                <input type="text" value={leaveTypeForm.color} onChange={(e) => setLeaveTypeForm((f) => ({ ...f, color: e.target.value }))} className="w-24 h-8 bg-premium-dark border border-premium-gold/30 rounded px-2 text-white text-[12px] font-mono" placeholder="#F2C94C" />
              </div>
            </div>
            <div className="flex-1 min-w-[10rem]">
              <label className="block text-gray-400 text-[12px] mb-0.5">คำอธิบาย (ไม่บังคับ)</label>
              <input type="text" value={leaveTypeForm.description} onChange={(e) => setLeaveTypeForm((f) => ({ ...f, description: e.target.value }))} className="w-full h-8 bg-premium-dark border border-premium-gold/30 rounded px-2 text-white text-[13px]" placeholder="ลาพักร้อน" />
            </div>
          </div>
        </div>
      </Modal>
    </div>
  );
}
