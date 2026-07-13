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

export function initialPathFor(role: CurrentUser['role']): string {
  return initialPathForRole(role);
}
