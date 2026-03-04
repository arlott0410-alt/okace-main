-- ---------- 12_holiday_global_max_days_per_month.sql ----------
-- กติกากลาง: แต่ละคนหยุดได้สูงสุดกี่วันต่อเดือน (แยกจากการตั้งค่าช่วงเปิดจอง)

ALTER TABLE meal_settings ADD COLUMN IF NOT EXISTS max_holiday_days_per_person_per_month INT DEFAULT 4;
-- ค่าเดิมใน holiday_booking_config ยังใช้ได้; ระบบจะใช้ค่าจาก meal_settings เป็นตัวบังคับ
