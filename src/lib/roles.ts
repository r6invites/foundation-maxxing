import type { Role } from '../types';

export const ROLES: readonly Role[] = ['student', 'mentor', 'supervisor', 'admin'];

const RANK: Record<Role, number> = { student: 1, mentor: 2, supervisor: 3, admin: 4 };

/** Student < Mentor < Supervisor < Admin. */
export function hasRoleAtLeast(role: Role, minimum: Role): boolean {
  return RANK[role] >= RANK[minimum];
}

export function homePathForRole(role: Role): string {
  return `/${role}`;
}

export interface NavItem {
  to: string;
  label: string;
}

/** Navigation shown for each role. Later stages add entries here. */
export function navItemsFor(role: Role): NavItem[] {
  switch (role) {
    case 'student':    return [{ to: '/student', label: 'Home' }];
    case 'mentor':     return [{ to: '/mentor', label: 'My students' }];
    case 'supervisor': return [{ to: '/supervisor', label: 'Overview' }];
    case 'admin':      return [{ to: '/admin', label: 'Overview' }];
  }
}

/**
 * Roles the given role may create by invitation.
 * Admins: every role. Supervisors: mentors only. Mirrors the check in the invite-user function,
 * which is the real enforcement; this only decides what the form offers.
 */
export function invitableRoles(role: Role): Role[] {
  if (role === 'admin') return [...ROLES];
  if (role === 'supervisor') return ['mentor'];
  return [];
}

export function roleLabel(role: Role): string {
  return role.charAt(0).toUpperCase() + role.slice(1);
}
