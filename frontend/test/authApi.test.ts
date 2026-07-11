import { afterEach, describe, expect, it, vi } from 'vitest';
import { fetchMe, login, logout } from '../src/auth/authApi';
import type { CurrentUser } from '../src/auth/types';

const currentUser: CurrentUser = {
  userId: 'U001',
  loginId: 'employee001',
  userName: '山田 太郎',
  role: 'EMPLOYEE',
  groupId: 'G001',
  groupName: '第1開発グループ',
  breakTypeId: 'BT001',
  breakTypeName: '標準休憩',
  workTimeTypeId: 'WT001',
  workTimeTypeName: '通常勤務',
};

function mockFetch(response: Response) {
  const fetchMock = vi.fn().mockResolvedValue(response);
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

function jsonResponse(body: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
    ...init,
  });
}

describe('authApi', () => {
  afterEach(() => {
    document.cookie = 'XSRF-TOKEN=; Max-Age=0; path=/';
    vi.unstubAllGlobals();
  });

  it('posts login credentials and returns the current user', async () => {
    const fetchMock = mockFetch(jsonResponse(currentUser));

    await expect(login('employee001', 'password')).resolves.toEqual(currentUser);
    expect(fetchMock).toHaveBeenCalledWith('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify({ loginId: 'employee001', password: 'password' }),
    });
  });

  it('returns null when fetchMe receives 401', async () => {
    mockFetch(new Response(null, { status: 401 }));

    await expect(fetchMe()).resolves.toBeNull();
  });

  it('throws API error response when login fails with JSON body', async () => {
    const apiError = { code: 'AUTHENTICATION_FAILED', message: 'Login failed.', details: [] };
    mockFetch(jsonResponse(apiError, { status: 401 }));

    await expect(login('employee001', 'wrong')).rejects.toEqual(apiError);
  });

  it('falls back to unauthorized error when 401 body is not JSON', async () => {
    mockFetch(new Response('not-json', { status: 401 }));

    await expect(login('employee001', 'wrong')).rejects.toEqual({
      code: 'UNAUTHORIZED',
      message: 'ログインが必要です。',
      details: [],
    });
  });

  it('sends CSRF token header on logout when XSRF-TOKEN cookie exists', async () => {
    document.cookie = 'XSRF-TOKEN=csrf-token; path=/';
    const fetchMock = mockFetch(new Response(null, { status: 204 }));

    await logout();
    expect(fetchMock).toHaveBeenCalledWith('/api/auth/logout', {
      method: 'POST',
      credentials: 'include',
      headers: { 'X-XSRF-TOKEN': 'csrf-token' },
    });
  });

  it('does not send CSRF header on logout when XSRF-TOKEN cookie is absent', async () => {
    const fetchMock = mockFetch(new Response(null, { status: 204 }));

    await logout();
    expect(fetchMock).toHaveBeenCalledWith('/api/auth/logout', {
      method: 'POST',
      credentials: 'include',
      headers: undefined,
    });
  });

  it('throws when logout fails', async () => {
    const apiError = { code: 'FORBIDDEN', message: '権限がありません。', details: [] };
    mockFetch(jsonResponse(apiError, { status: 403 }));

    await expect(logout()).rejects.toEqual(apiError);
  });
});
