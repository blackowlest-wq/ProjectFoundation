import { expect, type Page } from '@playwright/test';
import { LOGIN_FORM_TEXT } from '../../src/auth/LoginForm';
import type { CurrentUser } from '../../src/auth/types';

/** DataInitializerと同じログイン利用者契約。employeeIdはCurrentUser APIに含まれない。 */
export const employee: CurrentUser = {
  userId: 'U001',
  employeeId: 'E001',
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

export const manager: CurrentUser = {
  userId: 'U002',
  loginId: 'manager001',
  userName: '佐藤 花子',
  role: 'MANAGER',
  groupId: 'G900',
  groupName: '管理グループ',
  breakTypeId: null,
  breakTypeName: null,
  workTimeTypeId: null,
  workTimeTypeName: null,
};

export const admin: CurrentUser = {
  userId: 'U003',
  loginId: 'admin001',
  userName: '鈴木 一郎',
  role: 'ADMIN',
  groupId: null,
  groupName: null,
  breakTypeId: null,
  breakTypeName: null,
  workTimeTypeId: null,
  workTimeTypeName: null,
};

export async function mockAuthApis(page: Page, options: { authenticated?: boolean; user?: CurrentUser } = {}) {
  const currentUser = options.user ?? employee;
  await page.route('**/api/auth/me', async (route) => {
    if (options.authenticated) {
      await route.fulfill({ json: currentUser });
      return;
    }
    await route.fulfill({ status: 401, body: '' });
  });
  await page.route('**/api/auth/login', async (route) => {
    await route.fulfill({ json: currentUser });
  });
}

export async function gotoWithRetry(page: Page, path: string) {
  const retryableErrorPattern = /ERR_CONNECTION_REFUSED|ECONNREFUSED/;

  for (let attempt = 1; attempt <= 12; attempt += 1) {
    try {
      await page.goto(path);
      return;
    } catch (error) {
      if (attempt === 12 || !retryableErrorPattern.test(String(error))) {
        throw error;
      }
      await page.waitForTimeout(5_000);
    }
  }
}

export async function loginAsEmployee(page: Page) {
  await loginAs(page, 'employee001', '日報カレンダー・一覧');
}

export async function loginAsManager(page: Page) {
  await loginAs(page, 'manager001', '日報カレンダー・一覧');
}

export async function loginAsAdmin(page: Page) {
  await loginAs(page, 'admin001', '日報カレンダー・一覧');
}

async function loginAs(page: Page, loginId: string, heading: string) {
  await gotoWithRetry(page, '/login');
  await page.getByLabel(LOGIN_FORM_TEXT.loginIdLabel).fill(loginId);
  await page.getByLabel(LOGIN_FORM_TEXT.passwordLabel).fill('password');
  await page.getByRole('button', { name: LOGIN_FORM_TEXT.submit }).click();
  await expect(page.getByRole('heading', { name: heading })).toBeVisible();
}
