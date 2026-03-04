# Migrations — สำหรับเปิดเว็บใหม่ / ระบบใหม่

รันใน **Supabase SQL Editor** ตามลำดับด้านล่างเท่านั้น  
**ต้องรัน `schema.sql` ก่อนครั้งแรก** (จาก `supabase/sql/schema.sql`)

---

## ลำดับการรัน (ระบบปัจจุบัน)

| # | ไฟล์ | สรุป |
|---|------|------|
| 0 | **schema.sql** | ฐาน: enums, branches, shifts, profiles, work_logs, holidays, break_logs, shift_swaps, cross_branch_transfers, duty_roles, monthly_roster, set_updated_at, is_admin ฯลฯ |
| 1 | **01_consolidated_001_to_025.sql** | admin_note, break_rules, Realtime, ล็อกอินชื่อผู้ใช้, websites/assignments, group_links, RLS หลัก, meal_settings, file_vault, audit_logs ฯลฯ |
| 2 | **02_enum_manager_only.sql** | เพิ่ม enum `manager` ใน app_role (ต้องรันแยกก่อน 03 เพราะ PostgreSQL ต้อง commit enum ก่อนใช้ใน 03) |
| 3 | **03_002_to_057.sql** | ตั้งเว็บหลัก, duty หัวหน้า, กลุ่มงาน/วันหยุด, โควต้าวันหยุดแบบชั้น, manager + RLS, หัวหน้าเห็นทุกคน, ระบบพักอาหาร, ย้ายกะ/สลับกะ, หัวหน้า=ผู้จัดการ ฯลฯ |
| 4 | **04_ensure_group_links_ready.sql** | แก้ 500 / infinite recursion หน้ากลุ่มงาน: can_see_group_link, RLS group_links |
| 5 | **05_drop_unused_password_vault.sql** | ลบตาราง password_vault (ไม่ใช้แล้ว) |
| 6 | **06_apply_scheduled_shift_changes_for_date.sql** | RPC อัปเดตกะ/แผนกเมื่อถึงวันย้ายกะ (สำหรับ Cron) |
| 7 | **07_group_links_head_same_as_manager.sql** | RLS group_links: หัวหน้าเพิ่มลิงก์ได้ทุกแผนก |
| 8 | **08_meal_quota_on_duty_holiday_pending.sql** | โควต้าพักอาหาร: นับคนอยู่ปฏิบัติจากวันหยุด (approved+pending) |
| 9 | **09_audit_logs_retention_7_days.sql** | ฟังก์ชันลบ audit_logs เก่ากว่า 7 วัน |
| 10 | **10_meal_quota_use_strictest_tier.sql** | โควต้าพัก: ใช้ tier ที่จำกัดที่สุด (MIN max_concurrent) |
| 11 | **11_schedule_cards_branch_ids.sql** | ตารางงาน: หนึ่งการ์ดหนึ่งแถว เก็บหลายแผนกใน branch_ids |
| 12 | **12_holiday_global_max_days_per_month.sql** | กติกากลางวันหยุด: สูงสุดกี่วัน/คน/เดือน |
| 13 | **13_meal_slots_return_max_per_work_date.sql** | get_meal_slots_unified คืน max_per_work_date |
| 14 | **14_holiday_quota_enforce_trigger.sql** | Trigger บังคับโควต้าวันหยุดที่ DB |
| 15 | **15_meal_quota_smallest_tier_first.sql** | โควต้าพัก: ยึดขั้นที่น้อยที่สุดก่อน |
| 16 | **16_duty_assignments_multi_user_per_role.sql** | duty_assignments: หลายคนต่อ role ต่อวัน |
| 17 | **17_shift_change_permanent_and_guards.sql** | ย้ายกะถาวร + guards สำหรับ apply |
| 18 | **18_dashboard_today_staff_view.sql** | View/ฟังก์ชันแดชบอร์ด "คนอยู่ปฏิบัติวันนี้" |
| 19 | **19_dashboard_today_staff_meal_slots.sql** | แดชบอร์ด: meal_slots ใน today staff |
| 20 | **20_performance_indexes_and_rpcs.sql** | Index + RPC แดชบอร์ด (get_effective_branch_shift_for_date ฯลฯ) |
| 21 | **21_rpc_dutyboard_holiday_grid_only.sql** | RPC สำหรับ DutyBoard / ตารางวันหยุด |
| 22 | **22_duty_assignments_ensure_multi_user.sql** | duty_assignments: ตรวจหลาย user ต่อ role |
| 23 | **23_profiles_select_same_branch_for_holiday_grid.sql** | RLS profiles สำหรับตารางวันหยุด (เห็นคนสาขาเดียวกัน) |
| 24 | **24_app_access_settings.sql** | ตั้งค่าการเข้าถึงแอป (app_access_settings) |
| 25 | **25_dashboard_shortcuts.sql** | เมนูลัดแดชบอร์ด (dashboard_shortcuts) |
| 26 | **26_profiles_account_fields.sql** | คอลัมน์บัญชีใน profiles |
| 27 | **27_allow_apply_shift_changes_trigger.sql** | อนุญาต trigger apply ย้ายกะ |
| 28 | **28_leave_type_holiday_code_x.sql** | leave_types / holiday code 'X' ฯลฯ |
| 29 | **29_third_party_providers.sql** | ตารางบุคคลที่สาม (third_party_providers) |
| 30 | **30_third_party_website_required.sql** | บังคับ website ใน third_party_providers |
| 31 | **31_schedule_cards_icon_url.sql** | schedule_cards: icon_url |
| 32 | **32_third_party_drop_unused_columns.sql** | ลบคอลัมน์ที่ไม่ใช้ใน third_party_providers |
| 33 | **33_meal_break_slot_within_shift.sql** | จองพักอาหาร: slot ต้องอยู่ทั้งกะ (book_meal_break) |
| 34 | **34_shift_change_history_view.sql** | View ประวัติย้ายกะรวม (shift_change_history_view) |

---

## วิธีรัน (เปิดเว็บใหม่ / ระบบใหม่)

**ตัวเลือก A — รันไฟล์เดียว (แนะนำสำหรับระบบใหม่)**  
1. เปิด **Supabase Dashboard** → **SQL Editor**  
2. เปิดไฟล์ **migrations/full_install.sql** (รวม schema + 01 ถึง 34 ลำดับเดียว, ตัดคอมเมนต์ออกแล้ว)  
3. Run ครั้งเดียว  

**ตัวเลือก B — รันแยกไฟล์**  
1. รัน **schema.sql** (จาก `supabase/sql/schema.sql`) ก่อน  
2. รัน **01** → **02** → **03** → … → **34** ตามลำดับ  

ถ้า 01 ขึ้น error เรื่อง `ALTER TYPE ... ADD VALUE` ให้รันเฉพาะบรรทัดนั้นแยกครั้งเดียว แล้วรันส่วนที่เหลือของ 01 ต่อ

---

## สิ่งที่ลบออกแล้ว (ไม่ใช้ในระบบปัจจุบัน)

- ฟีเจอร์ **โปรโมชัน Scatter** และ **คลังโค้ดโปรโมชัน** ถูกลบออกจากแอปแล้ว
- Migration ที่เกี่ยวกับโปรโมชัน (เดิม 33–41, 43) ถูกลบออกจากโฟลเดอร์แล้ว เพื่อให้ชุด migration ปัจจุบันรันแล้วได้เฉพาะระบบที่ใช้งานอยู่ (ไม่มีตาราง promotions, promo_requests, promo_code_vault, promo_games)

---

## โครงสร้างใน 03

ไฟล์ **03_002_to_057.sql** มีหัวข้อ `-- ---------- 002_... ----------` ถึง `-- ---------- 057_... ----------`  
ใช้ค้นหา (Ctrl+F) ชื่อเช่น `054_` หรือ `057_` เพื่อไปจุดที่ต้องการ
