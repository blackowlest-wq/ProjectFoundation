/**
 * ログイン画面の利用者補助用バリデーション。
 * セキュリティ上の最終判定はバックエンドで行い、ここでは送信前に分かる不備だけを返す。
 */
export const LOGIN_ID_MAX_LENGTH = 80;
export const PASSWORD_MAX_LENGTH = 100;

const alphanumericPattern = /^[A-Za-z0-9]+$/;

/**
 * ログインIDとパスワードの必須・長さ・半角英数字条件を順番に検証する。
 */
export function validateLoginInput(loginId: string, password: string): string | null {
  // How: ログインIDの未入力を最初に検出し、後続の長さ・文字種検証を行わず終了する。
  if (!loginId.trim()) {
    return 'ログインIDは必須です。';
  }
  // How: ログインIDが上限を超えた場合は文字種検証より先に長さエラーを返す。
  if (loginId.length > LOGIN_ID_MAX_LENGTH) {
    return 'ログインIDは80文字以内で入力してください。';
  }
  // How: ログインIDの文字種が不正な場合は認証APIを呼び出さず終了する。
  if (!alphanumericPattern.test(loginId)) {
    return 'ログインIDは半角英数字で入力してください。';
  }
  // How: パスワードの未入力を検出し、後続の長さ・文字種検証を行わず終了する。
  if (!password.trim()) {
    return 'パスワードは必須です。';
  }
  // How: パスワードが上限を超えた場合は文字種検証より先に長さエラーを返す。
  if (password.length > PASSWORD_MAX_LENGTH) {
    return 'パスワードは100文字以内で入力してください。';
  }
  // How: パスワードの文字種が不正な場合は認証APIを呼び出さず終了する。
  if (!alphanumericPattern.test(password)) {
    return 'パスワードは半角英数字で入力してください。';
  }
  return null;
}
