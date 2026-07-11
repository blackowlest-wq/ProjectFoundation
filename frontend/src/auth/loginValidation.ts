/**
 * ログイン画面の利用者補助用バリデーション。
 * セキュリティ上の最終判定はバックエンドで行い、ここでは送信前に分かる不備だけを返す。
 */
export const LOGIN_ID_MAX_LENGTH = 80;
export const PASSWORD_MAX_LENGTH = 100;

const alphanumericPattern = /^[A-Za-z0-9]+$/;

export function validateLoginInput(loginId: string, password: string): string | null {
  if (!loginId.trim()) {
    return 'ログインIDは必須です。';
  }
  if (loginId.length > LOGIN_ID_MAX_LENGTH) {
    return 'ログインIDは80文字以内で入力してください。';
  }
  if (!alphanumericPattern.test(loginId)) {
    return 'ログインIDは半角英数字で入力してください。';
  }
  if (!password.trim()) {
    return 'パスワードは必須です。';
  }
  if (password.length > PASSWORD_MAX_LENGTH) {
    return 'パスワードは100文字以内で入力してください。';
  }
  if (!alphanumericPattern.test(password)) {
    return 'パスワードは半角英数字で入力してください。';
  }
  return null;
}
