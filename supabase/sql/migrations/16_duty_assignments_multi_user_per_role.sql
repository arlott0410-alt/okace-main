-- Allow multiple users per duty role per day (one role can have many people).
-- Keep: one user can only be assigned once per role per day (unique on ..., user_id).

-- Drop old unique: one row per (branch, shift, role, date)
ALTER TABLE public.duty_assignments
  DROP CONSTRAINT IF EXISTS duty_assignments_branch_id_shift_id_duty_role_id_assignment_date_key;

-- Same user cannot be on same role twice the same day; multiple users per role allowed
CREATE UNIQUE INDEX IF NOT EXISTS duty_assignments_one_user_per_role_per_day
  ON public.duty_assignments (branch_id, shift_id, duty_role_id, assignment_date, user_id)
  WHERE user_id IS NOT NULL;
