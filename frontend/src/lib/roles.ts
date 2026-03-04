/**
 * Role hierarchy for user management.
 * Head (manager / instructor_head) can only create/edit users with a role LOWER than their own.
 */

export const ROLE_LEVEL: Record<string, number> = {
  admin: 4,
  manager: 3,
  instructor_head: 2,
  instructor: 1,
  staff: 0,
};

/**
 * Returns true if myRole can manage (create/edit) a user with targetRole.
 * Admin can manage all; manager cannot manage admin; instructor_head cannot manage manager/admin.
 */
export function canManageRole(myRole: string, targetRole: string): boolean {
  const myLevel = ROLE_LEVEL[myRole] ?? -1;
  const targetLevel = ROLE_LEVEL[targetRole] ?? 0;
  return myLevel > targetLevel;
}

/**
 * Roles that the current user can assign in the UI.
 * Admin can assign all roles; others only roles strictly lower than their own.
 */
export function getAllowedRoleValues(myRole: string): string[] {
  const myLevel = ROLE_LEVEL[myRole] ?? -1;
  if (myLevel >= 4) return Object.keys(ROLE_LEVEL) as string[];
  return (Object.keys(ROLE_LEVEL) as string[]).filter((r) => ROLE_LEVEL[r] < myLevel);
}
