/**
 * 認証APIのクライアント関数。
 * Cookieセッションを利用するため、実際のcredentialsやCSRF処理はshared/apiClientへ集約する。
 */
import { getJsonOrNullOnUnauthorized, postJson, postNoContentWithCsrf } from '../shared/apiClient';
import type { CurrentUser } from './types';

export async function login(loginId: string, password: string): Promise<CurrentUser> {
  return postJson<CurrentUser>('/api/auth/login', { loginId, password });
}

export async function fetchMe(): Promise<CurrentUser | null> {
  return getJsonOrNullOnUnauthorized<CurrentUser>('/api/auth/me');
}

export async function logout(): Promise<void> {
  await postNoContentWithCsrf('/api/auth/logout');
}

export function initialPathForRole(role: CurrentUser['role']): string {
  // ログイン成功後の遷移先をロールごとに定義する。未実装画面もURLだけ先に固定しておく。
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

export function initialPathFor(role: CurrentUser['role']): string {
  return initialPathForRole(role);
}
