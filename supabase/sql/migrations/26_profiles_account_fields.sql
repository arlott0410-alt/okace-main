-- 26: ฟิลด์เพิ่มใน profiles สำหรับหน้า บัญชีของฉัน (telegram, lock_code, email_code, ฯลฯ)

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS telegram TEXT,
  ADD COLUMN IF NOT EXISTS lock_code TEXT,
  ADD COLUMN IF NOT EXISTS email_code TEXT,
  ADD COLUMN IF NOT EXISTS computer_code TEXT,
  ADD COLUMN IF NOT EXISTS work_access_code TEXT,
  ADD COLUMN IF NOT EXISTS two_fa TEXT,
  ADD COLUMN IF NOT EXISTS avatar_url TEXT,
  ADD COLUMN IF NOT EXISTS link1_url TEXT,
  ADD COLUMN IF NOT EXISTS link2_url TEXT,
  ADD COLUMN IF NOT EXISTS note_title TEXT,
  ADD COLUMN IF NOT EXISTS note_body TEXT;
