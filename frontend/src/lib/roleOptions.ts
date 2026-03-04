/** ค่า preset สำหรับ "หัวหน้าขึ้นไป" = เห็นได้เฉพาะหัวหน้า/ผู้จัดการ/แอดมิน */
export const HEAD_AND_ABOVE = 'head_and_above';
export const HEAD_AND_ABOVE_ROLES: string[] = ['instructor_head', 'manager', 'admin'];

/** ตัวเลือกบทบาทสำหรับ multi-select สิทธิ์การมองเห็น (ใช้ใน Group Links, File Vault, Schedule Cards) */
export const ROLE_OPTIONS: { value: string; label: string }[] = [
  { value: 'staff', label: 'พนักงานออนไลน์' },
  { value: 'instructor', label: 'พนักงานประจำ' },
  { value: 'instructor_head', label: 'หัวหน้าพนักงานประจำ' },
  { value: 'manager', label: 'ผู้จัดการ' },
  { value: 'admin', label: 'ผู้ดูแลระบบ' },
  { value: HEAD_AND_ABOVE, label: 'หัวหน้าขึ้นไป' },
];

export function getRoleLabel(value: string): string {
  if (value === HEAD_AND_ABOVE) return 'หัวหน้าขึ้นไป';
  return ROLE_OPTIONS.find((r) => r.value === value)?.label ?? value;
}

/** แปลงค่าที่เลือกในฟอร์ม (รวม head_and_above) เป็น array บทบาทจริงสำหรับบันทึก DB */
export function resolveVisibleRoles(selected: string[]): string[] {
  const out: string[] = [];
  for (const v of selected) {
    if (v === HEAD_AND_ABOVE) out.push(...HEAD_AND_ABOVE_ROLES);
    else out.push(v);
  }
  return Array.from(new Set(out));
}

/** แปลง visible_roles จาก DB เป็นค่าสำหรับแสดงในฟอร์ม (รวมกลุ่มหัวหน้าขึ้นไปเป็น preset เดียว) */
export function toCompactVisibleRoles(roles: string[] | null | undefined): string[] {
  const r = roles ?? [];
  if (r.length !== HEAD_AND_ABOVE_ROLES.length) return r;
  const set = new Set(r);
  if (HEAD_AND_ABOVE_ROLES.every((role) => set.has(role))) return [HEAD_AND_ABOVE];
  return r;
}
