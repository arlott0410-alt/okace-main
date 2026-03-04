-- Migration 31: schedule_cards — เพิ่ม icon_url สำหรับใส่ลิงก์รูปไอคอนได้เอง (ไม่ยึดตามเว็บ)
ALTER TABLE schedule_cards ADD COLUMN IF NOT EXISTS icon_url TEXT;
COMMENT ON COLUMN schedule_cards.icon_url IS 'URL รูปไอคอนการ์ด (optional) — ไม่ยึดตามเว็บ';
