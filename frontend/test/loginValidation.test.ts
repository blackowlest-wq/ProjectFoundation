import { describe, expect, it } from 'vitest';
import { validateLoginInput } from '../src/auth/loginValidation';

describe('validateLoginInput', () => {
  it('accepts alphanumeric login ID and password', () => {
    expect(validateLoginInput('employee001', 'password123')).toBeNull();
  });

  it('rejects non-alphanumeric login ID', () => {
    expect(validateLoginInput('employee_001', 'password123')).toBe('ログインIDは半角英数字で入力してください。');
  });

  it('rejects non-alphanumeric password', () => {
    expect(validateLoginInput('employee001', 'pass-word')).toBe('パスワードは半角英数字で入力してください。');
  });

  it.each([
    ['', 'password123', 'ログインIDは必須です。'],
    ['a'.repeat(81), 'password123', 'ログインIDは80文字以内で入力してください。'],
    ['employee001', '', 'パスワードは必須です。'],
    ['employee001', 'a'.repeat(101), 'パスワードは100文字以内で入力してください。'],
  ])('rejects required or overlong credentials', (loginId, password, expectedMessage) => {
    expect(validateLoginInput(loginId, password)).toBe(expectedMessage);
  });
});
