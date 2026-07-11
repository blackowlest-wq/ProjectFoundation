import { describe, expect, it } from 'vitest';
import { initialPathForRole } from '../src/auth/authApi';

describe('initialPathForRole', () => {
  it('maps roles to role-specific first screens', () => {
    expect(initialPathForRole('EMPLOYEE')).toBe('/daily-reports');
    expect(initialPathForRole('MANAGER')).toBe('/pending-approvals');
    expect(initialPathForRole('ADMIN')).toBe('/monthly-summaries');
  });
});
