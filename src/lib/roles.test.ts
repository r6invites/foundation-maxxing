import { describe, expect, it } from 'vitest';
import { hasRoleAtLeast, homePathForRole, invitableRoles, navItemsFor, ROLES } from './roles';

describe('role hierarchy', () => {
  it('ranks Student < Mentor < Supervisor < Admin', () => {
    expect(hasRoleAtLeast('admin', 'supervisor')).toBe(true);
    expect(hasRoleAtLeast('supervisor', 'mentor')).toBe(true);
    expect(hasRoleAtLeast('mentor', 'student')).toBe(true);
    expect(hasRoleAtLeast('student', 'mentor')).toBe(false);
    expect(hasRoleAtLeast('mentor', 'supervisor')).toBe(false);
    expect(hasRoleAtLeast('supervisor', 'admin')).toBe(false);
  });

  it('every role is at least itself', () => {
    for (const role of ROLES) expect(hasRoleAtLeast(role, role)).toBe(true);
  });
});

describe('routing and navigation', () => {
  it('sends each role to its own home', () => {
    expect(homePathForRole('student')).toBe('/student');
    expect(homePathForRole('admin')).toBe('/admin');
  });

  it('gives every role at least one nav item pointing at its home', () => {
    for (const role of ROLES) {
      expect(navItemsFor(role).some((item) => item.to === homePathForRole(role))).toBe(true);
    }
  });
});

describe('who may invite whom', () => {
  it('lets admins invite every role', () => {
    expect(invitableRoles('admin')).toEqual(['student', 'mentor', 'supervisor', 'admin']);
  });

  it('lets supervisors invite mentors only', () => {
    expect(invitableRoles('supervisor')).toEqual(['mentor']);
  });

  it('lets mentors and students invite nobody', () => {
    expect(invitableRoles('mentor')).toEqual([]);
    expect(invitableRoles('student')).toEqual([]);
  });
});
