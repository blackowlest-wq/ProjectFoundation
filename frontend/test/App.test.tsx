// @vitest-environment jsdom

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import App from '../src/app/App';
import { fetchMe, login, logout } from '../src/auth/authApi';
import {
  adminUser,
  buttonByText,
  buildReportDetail,
  cleanupUi,
  click,
  currentUser,
  flushEffects,
  installFrontendFetch,
  managerUser,
  rejectWith,
  renderUi,
  respondJson,
  submitLogin,
} from './support/dailyReportTestSupport';

vi.mock('../src/auth/authApi', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../src/auth/authApi')>();
  return {
    ...actual,
    fetchMe: vi.fn(),
    login: vi.fn(),
    logout: vi.fn(),
  };
});

describe('App authentication state', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-17T09:00:00+09:00'));
    window.history.replaceState(null, '', '/login');
    vi.clearAllMocks();
  });

  afterEach(() => {
    cleanupUi();
  });

  it('shows the login screen when the initial session is unauthenticated', async () => {
    vi.mocked(fetchMe).mockResolvedValue(null);

    await renderUi(<App />);

    expect(document.querySelector('h1')?.textContent).toBe('ログイン');
    expect(document.querySelector('.topbar')).toBeNull();
  });

  it('shows the login fallback error when login fails without a usable message', async () => {
    vi.mocked(fetchMe).mockResolvedValue(null);
    vi.mocked(login).mockRejectedValue({});

    await renderUi(<App />);
    await submitLogin('employee001', 'password123');

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('ログインに失敗しました。');
  });

  it.each([
    ['EMPLOYEE', '/daily-reports', currentUser],
    ['MANAGER', '/pending-approvals', managerUser],
    ['ADMIN', '/monthly-summaries', adminUser],
  ] as const)('moves to the %s initial path after login', async (_role, expectedPath, loggedInUser) => {
    installFrontendFetch();
    vi.mocked(fetchMe).mockResolvedValue(null);
    vi.mocked(login).mockResolvedValue(loggedInUser);

    await renderUi(<App />);
    await submitLogin('employee001', 'password123');

    expect(window.location.pathname).toBe(expectedPath);
    expect(document.body.textContent).toContain('山田 太郎');
  });

  it('returns to the login screen after logout succeeds', async () => {
    installFrontendFetch();
    vi.mocked(fetchMe).mockResolvedValue(currentUser);
    vi.mocked(logout).mockResolvedValue(undefined);

    await renderUi(<App />);
    await click(buttonByText('ログアウト'));

    expect(window.location.pathname).toBe('/login');
    expect(document.querySelector('h1')?.textContent).toBe('ログイン');
  });

  it('shows a fallback dash when the authenticated user has no group name', async () => {
    installFrontendFetch();
    vi.mocked(fetchMe).mockResolvedValue({ ...currentUser, groupName: null });

    await renderUi(<App />);

    expect(document.body.textContent).toContain('所属');
    expect(document.body.textContent).toContain('-');
  });

  it('keeps the authenticated screen and shows an error when logout fails', async () => {
    installFrontendFetch();
    vi.mocked(fetchMe).mockResolvedValue(currentUser);
    vi.mocked(logout).mockRejectedValue(new Error('logout failed'));

    await renderUi(<App />);
    await click(buttonByText('ログアウト'));

    expect(document.querySelector('.topbar')).not.toBeNull();
    expect(document.querySelector('[role="alert"]')?.textContent)
      .toBe('ログアウトに失敗しました。時間をおいて再度お試しください。');
  });

  it('returns to the login screen when the real report list receives unauthorized', async () => {
    installFrontendFetch({
      search: rejectWith({ code: 'UNAUTHORIZED', message: 'ログインが必要です。' }),
    });
    vi.mocked(fetchMe).mockResolvedValue(currentUser);

    await renderUi(<App />);
    await flushEffects();

    expect(window.location.pathname).toBe('/login');
    expect(document.querySelector('[role="alert"]')?.textContent).toBe('ログインが必要です。');
    expect(document.querySelector('h1')?.textContent).toBe('ログイン');
  });

  it('RT-APR-UI-004 routes an encoded detail ID and preserves the employee edit route', async () => {
    const detailId = 'R /?';
    installFrontendFetch({
      reportDetails: {
        [detailId]: respondJson(buildReportDetail(detailId, { approvalStatus: 'DRAFT' })),
        'R-EDIT': respondJson(buildReportDetail('R-EDIT', { approvalStatus: 'DRAFT' })),
      },
    });
    vi.mocked(fetchMe).mockResolvedValue(currentUser);
    window.history.replaceState(null, '', '/daily-reports/R%20%2F%3F');

    await renderUi(<App />);

    expect(document.body.textContent).toContain('日報詳細');
    expect(Array.from(document.querySelectorAll('a')).find((link) => link.textContent === '編集する')?.getAttribute('href'))
      .toBe('/daily-reports/R%20%2F%3F/edit');

    cleanupUi();
    window.history.replaceState(null, '', '/daily-reports/R-EDIT/edit');
    await renderUi(<App />);
    expect(document.body.textContent).toContain('日報編集');
  });
});
