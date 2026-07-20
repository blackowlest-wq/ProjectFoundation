import { expect, test } from '@playwright/test';
import { gotoWithRetry, loginAsEmployee, loginAsManager, manager } from './support/authMocks';
import { mockDailyReportApis } from './support/dailyReportMocks';
import { mockStaticFrontend } from './support/staticFrontend';

test('employee can search daily reports by synchronized target month range', async ({ page }) => {
  const requestedUrls: string[] = [];
  await mockDailyReportApis(page);
  await page.route('**/api/daily-reports?**', async (route) => {
    if (route.request().method() === 'GET') {
      requestedUrls.push(route.request().url());
      await route.fulfill({
        json: [{
          reportId: 'R-LIST-001',
          reportDate: '2026-07-15',
          employeeId: 'E001',
          employeeName: '山田 太郎',
          groupId: 'G001',
          groupName: '第1開発グループ',
          holidayType: 'WORKDAY',
          startTime: '09:00',
          endTime: '18:00',
          breakTypeId: 'BT001',
          breakTypeName: '標準休憩',
          workTimeTypeId: 'WT001',
          workTimeTypeName: '通常勤務',
          breakMinutes: 60,
          workMinutes: 480,
          regularWorkMinutes: 480,
          overtimeWorkMinutes: 0,
          nightWorkMinutes: 0,
          workTimeDisplay: '8:00',
          regularWorkTimeDisplay: '8:00',
          overtimeWorkTimeDisplay: '0:00',
          nightWorkTimeDisplay: '0:00',
          totalWorkItemMinutes: 480,
          approvalStatus: 'PENDING',
          submittedAt: '2026-07-15T18:10:00+09:00',
          approverName: null,
          approvedAt: null,
          rejected: false,
        }],
      });
      return;
    }
    await route.fallback();
  });
  await mockStaticFrontend(page);
  await loginAsEmployee(page);

  await page.getByLabel('対象年月').fill('2026-07');
  await expect(page.getByLabel('検索開始日')).toHaveValue('2026-07-01');
  await expect(page.getByLabel('検索終了日')).toHaveValue('2026-07-31');
  await page.getByRole('button', { name: '検索' }).click();

  await expect(page.getByRole('cell', { name: '2026-07-15', exact: true })).toBeVisible();
  expect(requestedUrls.some((url) => url.includes('dateFrom=2026-07-01') && url.includes('dateTo=2026-07-31'))).toBeTruthy();
});

test('employee sees list columns empty state and status colored calendar cell', async ({ page }) => {
  let searchCount = 0;
  await mockDailyReportApis(page);
  await page.route('**/api/daily-reports?**', async (route) => {
    searchCount += 1;
    if (searchCount === 1) {
      await route.fulfill({
        json: [{
          reportId: 'R-LIST-STATUS',
          reportDate: '2026-07-15',
          employeeId: 'E001',
          employeeName: '山田 太郎',
          groupId: 'G001',
          groupName: '第1開発グループ',
          holidayType: 'WORKDAY',
          startTime: '09:00',
          endTime: '18:00',
          breakTypeId: 'BT001',
          breakTypeName: '標準休憩',
          workTimeTypeId: 'WT001',
          workTimeTypeName: '通常勤務',
          breakMinutes: 60,
          workMinutes: 480,
          regularWorkMinutes: 480,
          overtimeWorkMinutes: 0,
          nightWorkMinutes: 0,
          workTimeDisplay: '8:00',
          regularWorkTimeDisplay: '8:00',
          overtimeWorkTimeDisplay: '0:00',
          nightWorkTimeDisplay: '0:00',
          totalWorkItemMinutes: 480,
          approvalStatus: 'PENDING',
          submittedAt: '2026-07-15T18:10:00+09:00',
          approverName: null,
          approvedAt: null,
          rejected: false,
        }],
      });
      return;
    }
    await route.fulfill({ json: [] });
  });
  await mockStaticFrontend(page);
  await loginAsEmployee(page);

  await expect(page.getByLabel('グループID')).not.toBeVisible();
  await expect(page.getByRole('columnheader', { name: '日付' })).toBeVisible();
  await expect(page.getByRole('cell', { name: '承認待ち' })).toBeVisible();
  await expect(page.getByLabel('2026-07-15 承認待ち')).toHaveClass(/status-pending/);

  await page.getByRole('button', { name: '検索' }).click();

  await expect(page.getByRole('cell', { name: '該当する日報はありません。' })).toBeVisible();
});

test('manager sees group filter on daily report list', async ({ page }) => {
  await mockDailyReportApis(page, { user: manager });
  await page.route('**/api/daily-reports?**', async (route) => {
    await route.fulfill({ json: [] });
  });
  await mockStaticFrontend(page);
  await loginAsManager(page);

  const searchPanel = page.locator('section.report-panel').filter({ has: page.getByRole('heading', { name: '日報検索' }) });
  await expect(searchPanel.getByLabel('グループID')).toBeVisible();
});

test('logout failure keeps authenticated screen and shows error', async ({ page }) => {
  await mockDailyReportApis(page);
  await page.route('**/api/daily-reports?**', async (route) => {
    await route.fulfill({ json: [] });
  });
  await page.route('**/api/auth/logout', async (route) => {
    await route.fulfill({ status: 500, body: '' });
  });
  await mockStaticFrontend(page);
  await loginAsEmployee(page);

  await page.getByRole('button', { name: 'ログアウト' }).click();

  await expect(page.getByRole('heading', { name: '日報カレンダー・一覧' })).toBeVisible();
  await expect(page.getByRole('alert')).toContainText('ログアウトに失敗しました。時間をおいて再度お試しください。');
  await expect(page.getByText('山田 太郎').first()).toBeVisible();
});

test('employee is returned to login when search receives unauthorized', async ({ page }) => {
  let searchCount = 0;
  await mockDailyReportApis(page);
  await page.route('**/api/daily-reports?**', async (route) => {
    searchCount += 1;
    if (searchCount === 1) {
      await route.fulfill({
        json: [{
          reportId: 'R-LIST-401',
          reportDate: '2026-07-15',
          employeeId: 'E001',
          employeeName: '山田 太郎',
          groupId: 'G001',
          groupName: '第1開発グループ',
          holidayType: 'WORKDAY',
          startTime: '09:00',
          endTime: '18:00',
          breakTypeId: 'BT001',
          breakTypeName: '標準休憩',
          workTimeTypeId: 'WT001',
          workTimeTypeName: '通常勤務',
          breakMinutes: 60,
          workMinutes: 480,
          regularWorkMinutes: 480,
          overtimeWorkMinutes: 0,
          nightWorkMinutes: 0,
          workTimeDisplay: '8:00',
          regularWorkTimeDisplay: '8:00',
          overtimeWorkTimeDisplay: '0:00',
          nightWorkTimeDisplay: '0:00',
          totalWorkItemMinutes: 480,
          approvalStatus: 'PENDING',
          submittedAt: '2026-07-15T18:10:00+09:00',
          approverName: null,
          approvedAt: null,
          rejected: false,
        }],
      });
      return;
    }
    await route.fulfill({ status: 401, body: '' });
  });
  await mockStaticFrontend(page);
  await loginAsEmployee(page);

  await expect(page.getByRole('cell', { name: '山田 太郎' })).toBeVisible();
  await page.getByRole('button', { name: '検索' }).click();

  await expect(page.getByRole('heading', { name: 'ログイン' })).toBeVisible();
  await expect(page.getByRole('alert')).toContainText('ログインが必要です。');
  await expect(page.getByText('山田 太郎')).not.toBeVisible();
});

test('employee can save and submit a daily report from the screen', async ({ page }) => {
  await mockDailyReportApis(page);
  await mockStaticFrontend(page);
  await loginAsEmployee(page);

  await page.getByLabel('日付').fill('2026-06-28');
  await page.getByLabel('勤務開始').fill('09:00');
  await page.getByLabel('勤務終了').fill('18:00');
  await page.getByLabel('備考').fill('E2E日報');
  await page.getByRole('button', { name: '保存して提出' }).click();

  await expect(page.getByText('保存して提出しました。')).toBeVisible();
  await expect(page.locator('.status-pill')).toHaveText('承認待ち');
  await expect(page).toHaveURL(/\/daily-reports\/R-E2E-001\/edit$/);
});

test('daily report validation errors are visible on the screen', async ({ page }) => {
  await mockDailyReportApis(page);
  await mockStaticFrontend(page);
  await loginAsEmployee(page);

  await page.getByLabel('勤務開始').fill('18:00');
  await page.getByLabel('勤務終了').fill('09:00');
  await page.getByRole('button', { name: '下書き保存' }).click();

  await expect(page.getByRole('alert')).toContainText('勤務終了時刻は勤務開始時刻より後にしてください。');
});

test('employee can save a paid leave report as draft', async ({ page }) => {
  await mockDailyReportApis(page);
  await mockStaticFrontend(page);
  await loginAsEmployee(page);

  const reportForm = page.locator('.report-panel').filter({ has: page.getByRole('heading', { name: '日報登録' }) });
  await page.getByLabel('日付').fill('2026-06-29');
  await reportForm.getByLabel('休日区分').selectOption('PAID_LEAVE');
  await reportForm.getByRole('button', { name: '下書き保存' }).click();

  await expect(page.getByText('保存しました。')).toBeVisible();
  await expect(page.locator('.status-pill')).toHaveText('下書き');
});

test('employee can edit an existing draft report', async ({ page }) => {
  await mockDailyReportApis(page, { authenticated: true });
  await mockStaticFrontend(page);

  await gotoWithRetry(page, '/daily-reports/R-DRAFT-001/edit');

  await expect(page.getByRole('heading', { name: '日報編集' })).toBeVisible();
  await expect(page.getByLabel('備考')).toHaveValue('既存の下書き');

  await page.getByLabel('備考').fill('E2Eで更新');
  await page.getByRole('button', { name: '下書き保存' }).click();

  await expect(page.getByText('保存しました。')).toBeVisible();
  await expect(page.locator('.status-pill')).toHaveText('下書き');
});

test('employee can update and submit an existing draft report', async ({ page }) => {
  const mutationRequests: string[] = [];
  page.on('request', (request) => {
    if (request.method() === 'POST' || request.method() === 'PUT') {
      mutationRequests.push(`${request.method()} ${new URL(request.url()).pathname}`);
    }
  });
  await mockDailyReportApis(page, { authenticated: true });
  await mockStaticFrontend(page);

  await gotoWithRetry(page, '/daily-reports/R-DRAFT-001/edit');

  await page.getByLabel('備考').fill('E2Eで更新して提出');
  await page.getByRole('button', { name: '保存して提出' }).click();

  await expect(page.getByText('保存して提出しました。')).toBeVisible();
  await expect(page.locator('.status-pill')).toHaveText('承認待ち');
  await page.reload();
  await expect(page.locator('.status-pill')).toHaveText('承認待ち');
  const reportForm = page.locator('.report-panel').filter({ has: page.getByRole('heading', { name: '日報編集' }) });
  await expect(reportForm.getByText('この状態の日報は編集できません。')).toBeVisible();
  const controls = reportForm.locator('input, select, textarea, button');
  expect(await controls.count()).toBeGreaterThan(0);
  expect(await controls.evaluateAll((elements) => elements.every((control) => (control as HTMLInputElement).disabled))).toBe(true);
  expect(mutationRequests).toEqual([
    'PUT /api/daily-reports/R-DRAFT-001',
    'POST /api/daily-reports/R-DRAFT-001/submit',
  ]);
});

test('employee can resubmit a rejected report from the edit screen', async ({ page }) => {
  const mutationRequests: string[] = [];
  page.on('request', (request) => {
    if (request.method() === 'POST' || request.method() === 'PUT') {
      mutationRequests.push(`${request.method()} ${new URL(request.url()).pathname}`);
    }
  });
  await mockDailyReportApis(page, { authenticated: true });
  await mockStaticFrontend(page);

  await gotoWithRetry(page, '/daily-reports/R-REJECTED-001/edit');

  await expect(page.locator('.status-pill')).toHaveText('差戻し');
  await expect(page.getByText('差戻しコメント')).toBeVisible();
  await expect(page.getByText('詳細を追記してください。')).toBeVisible();
  await expect(page.getByText('佐藤 上長')).toBeVisible();
  await expect(page.getByText('2026-06-27T17:30:00+09:00')).toBeVisible();
  await page.getByLabel('備考').fill('E2Eで再提出');
  await page.getByRole('button', { name: '保存して提出' }).click();

  await expect(page.getByText('保存して提出しました。')).toBeVisible();
  await expect(page.locator('.status-pill')).toHaveText('承認待ち');
  expect(mutationRequests).toEqual([
    'PUT /api/daily-reports/R-REJECTED-001',
    'POST /api/daily-reports/R-REJECTED-001/resubmit',
  ]);
});

test('pending report edit screen disables every mutation control', async ({ page }) => {
  const mutationRequests: string[] = [];
  page.on('request', (request) => {
    if (request.method() === 'POST' || request.method() === 'PUT') {
      mutationRequests.push(`${request.method()} ${new URL(request.url()).pathname}`);
    }
  });
  await mockDailyReportApis(page, { authenticated: true });
  await mockStaticFrontend(page);

  await gotoWithRetry(page, '/daily-reports/R-PENDING-001/edit');

  await expect(page.locator('.status-pill')).toHaveText('承認待ち');
  const reportForm = page.locator('.report-panel').filter({ has: page.getByRole('heading', { name: '日報編集' }) });
  await expect(reportForm.getByText('この状態の日報は編集できません。')).toBeVisible();
  const controls = reportForm.locator('input, select, textarea, button');
  expect(await controls.count()).toBeGreaterThan(0);
  const allDisabled = await controls.evaluateAll((elements) => elements.every((control) => (control as HTMLInputElement).disabled));
  expect(allDisabled).toBe(true);
  expect(mutationRequests.filter((request) => request.includes('/api/daily-reports/'))).toHaveLength(0);
});

test('approved report edit screen disables every mutation control', async ({ page }) => {
  const mutationRequests: string[] = [];
  page.on('request', (request) => {
    if (request.method() === 'POST' || request.method() === 'PUT') {
      mutationRequests.push(`${request.method()} ${new URL(request.url()).pathname}`);
    }
  });
  await mockDailyReportApis(page, { authenticated: true });
  await mockStaticFrontend(page);

  await gotoWithRetry(page, '/daily-reports/R-APPROVED-001/edit');

  await expect(page.locator('.status-pill')).toHaveText('承認済み');
  const reportForm = page.locator('.report-panel').filter({ has: page.getByRole('heading', { name: '日報編集' }) });
  await expect(reportForm.getByText('この状態の日報は編集できません。')).toBeVisible();
  const controls = reportForm.locator('input, select, textarea, button');
  expect(await controls.count()).toBeGreaterThan(0);
  const allDisabled = await controls.evaluateAll((elements) => elements.every((control) => (control as HTMLInputElement).disabled));
  expect(allDisabled).toBe(true);
  expect(mutationRequests.filter((request) => request.includes('/api/daily-reports/'))).toHaveLength(0);
});
