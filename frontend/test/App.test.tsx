import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import App from '../src/app/App';
import { fetchMe, login, logout } from '../src/auth/authApi';
import type { CurrentUser } from '../src/auth/types';

vi.mock('../src/auth/authApi', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../src/auth/authApi')>();
  return {
    ...actual,
    fetchMe: vi.fn(),
    login: vi.fn(),
    logout: vi.fn(),
  };
});

vi.mock('../src/dailyReport/DailyReportCalendarList', () => ({
  DailyReportCalendarList: () => <div data-testid="daily-report-list">日報一覧</div>,
}));

vi.mock('../src/dailyReport/DailyReportForm', () => ({
  DailyReportForm: () => <div data-testid="daily-report-form">日報登録</div>,
}));

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

let root: Root | null = null;
let container: HTMLDivElement | null = null;

(globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

function renderApp() {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  return act(async () => {
    root?.render(<App />);
    await Promise.resolve();
  });
}

function inputByLabel(labelText: string): HTMLInputElement {
  const label = Array.from(document.querySelectorAll('label'))
    .find((candidate) => candidate.textContent?.includes(labelText));
  if (!label) {
    throw new Error(`Label not found: ${labelText}`);
  }
  const input = label.querySelector('input');
  if (!input) {
    throw new Error(`Input not found: ${labelText}`);
  }
  return input;
}

function change(input: HTMLInputElement, value: string) {
  act(() => {
    const valueSetter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
    valueSetter?.call(input, value);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

async function submitLogin(loginId: string, password: string) {
  change(inputByLabel('ログインID'), loginId);
  change(inputByLabel('パスワード'), password);
  const form = document.querySelector('form');
  if (!form) {
    throw new Error('Login form not found.');
  }
  await act(async () => {
    form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    await Promise.resolve();
  });
}

async function clickLogout() {
  const button = Array.from(document.querySelectorAll('button'))
    .find((candidate) => candidate.textContent === 'ログアウト');
  if (!button) {
    throw new Error('Logout button not found.');
  }
  await act(async () => {
    button.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    await Promise.resolve();
  });
}

describe('App authentication state', () => {
  beforeEach(() => {
    window.history.replaceState(null, '', '/login');
    vi.clearAllMocks();
  });

  afterEach(() => {
    act(() => {
      root?.unmount();
    });
    container?.remove();
    root = null;
    container = null;
    window.history.replaceState(null, '', '/login');
  });

  it('shows the login screen when the initial session is unauthenticated', async () => {
    vi.mocked(fetchMe).mockResolvedValue(null);

    await renderApp();

    expect(document.querySelector('h1')?.textContent).toBe('ログイン');
    expect(document.querySelector('.topbar')).toBeNull();
  });

  it.each([
    ['EMPLOYEE', '/daily-reports'],
    ['MANAGER', '/pending-approvals'],
    ['ADMIN', '/monthly-summaries'],
  ] as const)('moves to the %s initial path after login', async (role, expectedPath) => {
    vi.mocked(fetchMe).mockResolvedValue(null);
    vi.mocked(login).mockResolvedValue({ ...currentUser, role });

    await renderApp();
    await submitLogin('employee001', 'password');

    expect(window.location.pathname).toBe(expectedPath);
    expect(document.body.textContent).toContain('山田 太郎');
  });

  it('returns to the login screen after logout succeeds', async () => {
    vi.mocked(fetchMe).mockResolvedValue(currentUser);
    vi.mocked(logout).mockResolvedValue(undefined);

    await renderApp();
    await clickLogout();

    expect(window.location.pathname).toBe('/login');
    expect(document.querySelector('h1')?.textContent).toBe('ログイン');
  });

  it('keeps the authenticated screen and shows an error when logout fails', async () => {
    vi.mocked(fetchMe).mockResolvedValue(currentUser);
    vi.mocked(logout).mockRejectedValue(new Error('logout failed'));

    await renderApp();
    await clickLogout();

    expect(document.querySelector('.topbar')).not.toBeNull();
    expect(document.querySelector('[role="alert"]')?.textContent)
      .toBe('ログアウトに失敗しました。時間をおいて再度お試しください。');
  });
});
