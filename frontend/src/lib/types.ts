export type AppRole = 'admin' | 'manager' | 'instructor_head' | 'instructor' | 'staff';

/** กลุ่มสำหรับแยกข้อมูลลงเวลา/พัก/วันหยุด: Instructor vs Staff vs Manager (ไม่รวม admin) */
export type UserGroup = 'INSTRUCTOR' | 'STAFF' | 'MANAGER';
export type WorkLogType = 'IN' | 'OUT';
export type HolidayStatus = 'pending' | 'approved' | 'rejected' | 'cancelled';
export type RosterStatus = 'DRAFT' | 'CONFIRMED';
export type SwapStatus = 'pending' | 'approved' | 'rejected' | 'cancelled';
export type TransferStatus = 'pending' | 'approved' | 'rejected' | 'cancelled';
export type BreakLogStatus = 'active' | 'ended';

export interface Branch {
  id: string;
  name: string;
  code: string | null;
  active: boolean;
  created_at: string;
  updated_at: string;
}

export interface Shift {
  id: string;
  name: string;
  code: string | null;
  start_time: string | null;
  end_time: string | null;
  sort_order: number;
  active: boolean;
  created_at: string;
  updated_at: string;
}

export interface Profile {
  id: string;
  email: string;
  display_name: string | null;
  role: AppRole;
  default_branch_id: string | null;
  default_shift_id: string | null;
  active: boolean;
  created_at: string;
  updated_at: string;
  branch?: Branch;
  shift?: Shift;
  telegram?: string | null;
  lock_code?: string | null;
  email_code?: string | null;
  computer_code?: string | null;
  work_access_code?: string | null;
  two_fa?: string | null;
  avatar_url?: string | null;
  link1_url?: string | null;
  link2_url?: string | null;
  note_title?: string | null;
  note_body?: string | null;
}

export interface WorkLog {
  id: string;
  user_id: string;
  branch_id: string;
  shift_id: string;
  logical_date: string;
  log_type: WorkLogType;
  logged_at: string;
  created_at: string;
  user_group?: UserGroup;
}

export interface BreakRule {
  id: string;
  branch_id: string | null;
  shift_id: string | null;
  min_staff: number;
  max_staff: number;
  concurrent_breaks: number;
  user_group: UserGroup;
}

export type BreakType = 'NORMAL' | 'MEAL';

export interface BreakLog {
  id: string;
  user_id: string;
  branch_id: string;
  shift_id: string;
  break_date: string;
  started_at: string;
  ended_at: string | null;
  status: BreakLogStatus;
  user_group?: UserGroup;
  break_type?: BreakType;
  round_key?: string | null;
  website_id?: string | null;
}

/** ตั้งค่าจองพักอาหาร (rounds_json: { max_per_work_date, rounds: [...] }) */
export interface MealSettings {
  id: string;
  effective_from: string;
  is_enabled: boolean;
  /** true = นับและจองแยกตามเว็บหลักเดียวกัน, false = ไม่แยกเว็บ */
  scope_meal_quota_by_website?: boolean;
  /** true = นับโควต้าวันหยุดแยกตามเว็บหลักเดียวกัน, false = ไม่แยกเว็บ */
  scope_holiday_quota_by_website?: boolean;
  /** กติกากลาง: แต่ละคนจองวันหยุดได้สูงสุดกี่วันต่อเดือน */
  max_holiday_days_per_person_per_month?: number;
  rounds_json: { max_per_work_date?: number; rounds?: Array<{ key: string; name: string; slots: Array<{ start: string; end: string }> }> };
  created_at: string;
  updated_at: string;
}

/** โควต้าพักอาหาร: on_duty <= on_duty_threshold → max_concurrent จองพร้อมกันได้; NULL = ทั้งหมด */
export interface MealQuotaRule {
  id: string;
  branch_id: string | null;
  shift_id: string | null;
  website_id: string | null;
  on_duty_threshold: number;
  max_concurrent: number;
  user_group: UserGroup | null;
  created_at?: string;
}

export interface HolidayQuota {
  id: string;
  branch_id: string;
  shift_id: string;
  quota_date: string;
  quota: number;
  user_group: UserGroup;
}

/** กติกาโควต้าวันหยุดแบบชั้น: ถ้าจำนวนคน <= max_people จะหยุดได้สูงสุด max_leave; combined = แผนก+กะ+กลุ่ม(+เว็บถ้าเปิด) */
export type HolidayQuotaDimension = 'branch' | 'shift' | 'website' | 'combined';
export interface HolidayQuotaTier {
  id: string;
  dimension: HolidayQuotaDimension;
  /** NULL = ใช้กับทุกกลุ่ม (แบบขั้น แผนก+กะ+กลุ่ม) */
  user_group: UserGroup | null;
  max_people: number;
  max_leave: number;
  sort_order: number;
  created_at?: string;
  updated_at?: string;
}

/** One row in holiday_audit_logs (create/update/delete by admin/manager/instructor_head) */
export interface HolidayAuditLogEntry {
  id: string;
  action: string;
  actor_id: string;
  actor_role: string;
  target_user_id: string;
  holiday_id: string | null;
  holiday_date: string | null;
  branch_id: string | null;
  leave_type: string | null;
  reason: string | null;
  is_quota_exempt: boolean | null;
  before_payload: Record<string, unknown> | null;
  after_payload: Record<string, unknown> | null;
  created_at: string;
}

/** ตั้งค่าการเปิดจองวันหยุดต่อเดือน (Admin) */
export interface HolidayBookingConfig {
  id: string;
  target_year_month: string;
  open_from: string;
  open_until: string;
  max_days_per_person: number;
  created_at?: string;
  updated_at?: string;
}

/** ประเภทการลา (จาก leave_types) */
export interface LeaveType {
  code: string;
  name: string;
  color: string | null;
  description: string | null;
}

export interface Holiday {
  id: string;
  user_id: string;
  branch_id: string;
  shift_id: string;
  holiday_date: string;
  status: HolidayStatus;
  reason: string | null;
  approved_by: string | null;
  approved_at: string | null;
  reject_reason: string | null;
  created_at: string;
  updated_at: string;
  user_group?: UserGroup;
  leave_type?: string;
  is_quota_exempt?: boolean;
}

export interface MonthlyRoster {
  id: string;
  branch_id: string;
  shift_id: string;
  user_id: string;
  work_date: string;
}

export interface MonthlyRosterStatus {
  id: string;
  branch_id: string;
  month: string;
  status: RosterStatus;
  confirmed_by: string | null;
  confirmed_at: string | null;
  unlock_reason: string | null;
  unlocked_by: string | null;
  unlocked_at: string | null;
}

export interface ShiftSwap {
  id: string;
  user_id: string;
  branch_id: string;
  from_shift_id: string;
  to_shift_id: string;
  start_date: string;
  end_date: string;
  reason: string | null;
  status: SwapStatus;
  approved_by: string | null;
  approved_at: string | null;
  reject_reason: string | null;
  created_at: string;
  skipped_dates?: string[] | null;
}

export interface CrossBranchTransfer {
  id: string;
  user_id: string;
  from_branch_id: string;
  to_branch_id: string;
  from_shift_id: string;
  to_shift_id: string;
  start_date: string;
  end_date: string;
  reason: string | null;
  status: TransferStatus;
  approved_by: string | null;
  approved_at: string | null;
  reject_reason: string | null;
  admin_note?: string | null;
  created_at: string;
  skipped_dates?: string[] | null;
}

export interface DutyRole {
  id: string;
  branch_id: string;
  name: string;
  sort_order: number;
}

export interface DutyAssignment {
  id: string;
  branch_id: string;
  shift_id: string;
  duty_role_id: string;
  user_id: string | null;
  assignment_date: string;
}

export interface Task {
  id: string;
  title: string;
  description: string | null;
  branch_id: string | null;
  assignee_id: string | null;
  created_by: string;
  status: string;
  due_at: string | null;
  completed_at: string | null;
  created_at: string;
}

export interface ScheduleCard {
  id: string;
  title: string;
  url: string | null;
  color_tag: string | null;
  /** URL รูปไอคอนการ์ด (optional) — ใส่ลิงก์ได้เอง ไม่ยึดตามเว็บ */
  icon_url?: string | null;
  scope: string;
  card_type: string;
  branch_id: string | null;
  /** หลายแผนก (หนึ่งการ์ดหนึ่งแถว); null/ว่าง = ใช้ branch_id */
  branch_ids: string[] | null;
  visible_roles: string[];
  website_id: string | null;
  sort_order: number;
  created_by: string | null;
  website?: { id: string; name: string; logo_path?: string | null } | null;
  branch?: { id: string; name: string } | null;
}

export interface GroupLink {
  id: string;
  branch_id: string | null;
  website_id: string | null;
  title: string;
  url: string | null;
  description: string | null;
  sort_order: number;
  created_by: string | null;
  visible_roles?: string[] | null;
}

/** แถวจาก group_links + join group_link_websites, group_link_branches (หลายเว็บ/หลายแผนกต่อ 1 ลิงก์) */
export type GroupLinkRow = GroupLink & {
  group_link_websites?: { website_id: string }[];
  group_link_branches?: { branch_id: string }[];
};

export interface AuditLog {
  id: string;
  actor_id: string | null;
  action: string;
  entity: string;
  entity_id: string | null;
  details_json: Record<string, unknown> | null;
  summary_text?: string | null;
  created_at: string;
}

/** List row for activity log (minimal columns; details loaded on demand) */
export interface AuditLogRow {
  id: string;
  created_at: string;
  actor_id: string | null;
  action: string;
  entity: string;
  entity_id: string | null;
  summary_text: string | null;
  profiles?: { display_name: string | null; email: string | null } | null;
}

/** Detail payload for modal (lazy-loaded) */
export interface AuditLogDetail {
  id: string;
  details_json: Record<string, unknown> | null;
  created_at: string;
}

/** เว็บที่ดูแล (โมดูล Managed Websites) — ไม่บังคับผูกแผนก ผูกกับผู้ใช้ผ่าน assignment */
export interface Website {
  id: string;
  branch_id: string | null;
  name: string;
  alias: string;
  url: string | null;
  description: string | null;
  logo_path: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

/** การมอบหมาย user ดูแล website */
export interface WebsiteAssignment {
  id: string;
  website_id: string;
  user_id: string;
  is_primary: boolean;
  role_on_website: string | null;
  created_at: string;
}

/** รอบสลับกะรายเดือน (หัวหน้าจัดการ) */
export interface ShiftSwapRound {
  id: string;
  branch_id: string;
  website_id: string | null;
  start_date: string;
  end_date: string;
  pairs_per_day: number;
  status: 'draft' | 'published';
  created_by: string;
  created_at: string;
  updated_at: string;
}

/** การมอบหมายสลับกะ ต่อคนต่อวัน */
export interface ShiftSwapAssignment {
  id: string;
  round_id: string;
  swap_date: string;
  user_id: string;
  from_shift_id: string;
  to_shift_id: string;
  partner_id: string | null;
  created_at: string;
}

/** บุคคลที่สาม (3rd Party) — Provider และลิงก์ (ฟิลด์ login/fee/withdraw ถูกลบออกแล้ว) */
export interface ThirdPartyProviderRow {
  id: string;
  provider_name: string;
  provider_code?: string | null;
  logo_url?: string | null;
  merchant_id?: string | null;
  link_url?: string | null;
  branch_id?: string | null;
  website_id?: string | null;
  visible_roles?: string[] | null;
  sort_order?: number | null;
  created_at?: string;
  updated_at?: string;
}

