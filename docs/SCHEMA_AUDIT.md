# การตรวจสอบ Schema — ทำไมดูเยอะ และอะไรที่อาจไม่ได้ใช้

## 1. ทำไม schema ดูเยอะจัง

ระบบ OKACE ใน repo นี้ออกแบบให้รองรับหลายโมดูลในตัวเดียว:

| กลุ่มฟีเจอร์ | ตารางหลัก | หมายเหตุ |
|-------------|------------|----------|
| ลงเวลา / พัก | work_logs, break_logs, break_rules | ใช้จริง |
| วันหยุด / โควตา | holidays, holiday_quotas, holiday_quota_tiers, holiday_booking_config, leave_types | ใช้จริง |
| สลับกะ / ย้ายกะ | shift_swaps, cross_branch_transfers, shift_swap_rounds, shift_swap_assignments | ใช้จริง |
| ตารางกะรายเดือน | monthly_roster, monthly_roster_status | ใช้จริง |
| จัดหน้าที่ | duty_roles, duty_assignments | ใช้จริง |
| กลุ่มงาน | group_links, group_link_websites, group_link_branches | ใช้จริง |
| ตารางงาน (การ์ด) | schedule_cards | ใช้จริง |
| เว็บที่ดูแล | websites, website_assignments | ใช้จริง |
| พักอาหาร (จองช่วง) | meal_settings, meal_quota_rules, meal_round_templates, meal_slot_templates, meal_concurrency_rules, meal_logs + break_logs (break_type=MEAL) | ใช้ผ่าน RPC |
| คลังรูป | file_vault | ใช้จริง (PhotoVault) |
| ~~คลังรหัสผ่าน~~ | ~~password_vault~~ | **ลบแล้ว (migration 05)** — ไม่มี frontend/RPC/API อ้างอิง |
| งานที่มอบหมาย | tasks | ใช้จริง (MyTasks) |
| ประวัติ | audit_logs, holiday_audit_logs | ใช้จริง (History, และ trigger ฝั่ง DB) |
| อ้างอิง | branches, shifts, profiles | ใช้ทุกที่ |

การเพิ่ม migrations ทีละฟีเจอร์ (001–057 แล้วรวมเป็น 01–04) ทำให้มีทั้งตารางใหม่ คอลัมน์เพิ่ม และ RLS เยอะ จึงดูซับซ้อนใน Schema Visualizer

---

## 2. สิ่งที่อาจไม่ได้ใช้หรือใช้ทางอ้อม (ใน repo นี้)

- **password_vault**  
  - ตรวจสอบแล้ว: ไม่มี frontend (.from), ไม่มี RPC, ไม่มี API ใน repo  
  - **ลบแล้ว** ด้วย migration **05_drop_unused_password_vault.sql** (ตารางจะถูกลบเมื่อรัน 05) “ไม่ได้ใช้จาก UI ปัจจุบัน”

- **holiday_quotas**  
  - ตั้งค่าโควต้าวันหยุดแบบเดิม (ต่อวัน ต่อสาขา/กะ/กลุ่ม)  
  - ฟีเจอร์วันหยุดตอนนี้ใช้ **holiday_quota_tiers** เป็นหลัก  
  - ยังมี RLS และ constraint อยู่ อาจถูกอ้างอิงใน logic ฝั่ง DB หรือ migration อื่น จึงไม่แนะนำให้ลบโดยไม่ตรวจ

- **ตารางที่เห็นใน Schema Visualizer แต่ไม่มีใน schema/migrations ของ repo นี้**  
  - ถ้าใน Supabase จริงมีตารางเช่น `booking_requests`, `shift_swap_categories`, `shift_swap_requests`, `mass_concurrent_roles`, `mass_reassignments`, `departments`, `group_link_departments`, `user_groups`, `meal_quota_values` ฯลฯ แปลว่าถูกเพิ่มจากที่อื่น (Dashboard / โปรเจกต์อื่น / migration นอก repo)  
  - ไม่ถือว่า “ใช้โดยระบบใน repo นี้” จนกว่าจะมีโค้ดหรือ migration ใน repo อ้างอิง

---

## 3. ถ้าปล่อยไว้จะเปลืองไหม

- **พื้นที่ (storage)**  
  - ตารางว่างหรือมีข้อมูลน้อยใช้พื้นที่ไม่มาก  
  - แต่จำนวนตาราง/คอลัมน์/RLS เยอะจะทำให้ backup ใหญ่ขึ้นและ restore ช้าลง

- **ความซับซ้อน**  
  - Schema เยอะ อ่านและไล่ logic ยาก  
  - คนใหม่หรือคนกลับมาแก้บั๊กจะเสียเวลา

- **ความเสี่ยง**  
  - ตาราง/คอลัมน์ที่ “ไม่รู้ว่าใช้ที่ไหน” อาจถูกเปลี่ยนหรือลบโดยไม่รู้ว่าแอปหรือ trigger ยังอ้างอิงอยู่

ดังนั้น **ปล่อยไว้ไม่จำเป็นต้องเปลือง storage มาก แต่เปลือง “ความเข้าใจและเวลา maintain”**  
ถ้าตรวจแล้วยืนยันว่าไม่ใช้ แนะนำให้มีแผนลบหรือ deprecate (เช่น ไม่ใช้ใน UI แล้ว ค่อยพิจารณาลบตารางหลัง backup)

---

## 4. แนวทางตรวจและทำความสะอาด (ไม่ลบให้เองใน doc นี้)

1. **ยืนยันว่าตารางไหนใช้**  
   - อ้างอิงจากรายการในส่วน 1 และการ grep ใน frontend ว่า `.from('...')` / `.rpc(...)` เรียกตาราง/ฟังก์ชันไหน  
   - ฝั่ง DB: ดู trigger, function, RLS ว่าอ้างอิงตารางไหน

2. **แยกระหว่าง “มีใน repo นี้” กับ “มีแค่ใน DB”**  
   - ถ้าใน Schema Visualizer มีตารางที่ไม่มีใน `schema.sql` หรือ migrations 01–04 แปลว่ามาจากที่อื่น  
   - ตัดสินใจว่าจะเก็บไว้ใช้หรือจะลบ (และทำ migration ลบใน repo ถ้าต้องการให้ schema ใน repo กับ DB ตรงกัน)

3. ~~**password_vault**~~ — ลบแล้วด้วย migration 05 (ไม่ใช้ในระบบ)

4. **holiday_quotas**  
   - ตรวจใน DB ว่ามี function/trigger ใดยังอ่านหรือเขียนตารางนี้หรือไม่  
   - ถ้าไม่มีแล้วและยืนยันว่าโควต้าวันหยุดใช้แค่ holiday_quota_tiers ค่อยพิจารณา deprecate/ลบ

สรุป: **schema ดูเยอะเพราะรวมหลายโมดูลและ migrations สะสม** สิ่งที่ “อาจไม่ได้ใช้” ในระบบตอนนี้คือ **password_vault (ไม่มี UI)** และตารางที่ **มีแค่ใน DB แต่ไม่มีใน repo นี้** ถ้าปล่อยไว้จะเปลืองน้อยในแง่ storage แต่เปลืองในแง่ความซับซ้อนและเวลา maintain แนะนำให้ตรวจใช้/ไม่ใช้แล้วค่อยลบหรือ deprecate เป็นขั้นตอน
