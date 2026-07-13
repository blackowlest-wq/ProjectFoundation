/**
 * 認証APIのクライアント関数。
 * Cookieセッションを利用するため、実際のcredentialsやCSRF処理はshared/apiClientへ集約する。
 */
import { getJsonOrNullOnUnauthorized, postJson, postNoContentWithCsrf } from '../shared/apiClient';
import type { CurrentUser } from './types';

/**
 * ログインIDとパスワードをログインAPIへ送り、認証済み利用者を返す。
 */
export async function login(loginId: string, password: string): Promise<CurrentUser> {
  return postJson<CurrentUser>('/api/auth/login', { loginId, password });
}

/**
 * 現在のCookieセッションを確認し、未ログインの場合はnullを返す。
 */
export async function fetchMe(): Promise<CurrentUser | null> {
  return getJsonOrNullOnUnauthorized<CurrentUser>('/api/auth/me');
}

/**
 * CSRFヘッダー付きでログアウトAPIを呼び出し、失敗時は例外を伝播する。
 */
export async function logout(): Promise<void> {
  await postNoContentWithCsrf('/api/auth/logout');
}

/**
 * ロールごとの初期画面URLを固定ルールで返す。
 */
export function initialPathForRole(role: CurrentUser['role']): string {
  // Why not: 画面実装の有無から遷移先を推測するとロール追加時にURL契約が揺れるため、ロールごとの初期URLを先に固定する。
  switch (role) {
    case 'MANAGER':
      return '/pending-approvals';
    case 'ADMIN':
      return '/monthly-summaries';
    case 'EMPLOYEE':
    default:
      return '/daily-reports';
  }
}

/**
 * ロール初期URLの公開入口として、既存の初期URL判定へ委譲する。
 */
export function initialPathFor(role: CurrentUser['role']): string {
  return initialPathForRole(role);
}
