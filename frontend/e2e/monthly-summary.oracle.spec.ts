import { expect, test, type Page } from '@playwright/test';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

async function login(page: Page, loginId: string, heading: string) {
  await page.goto('/login');
  await page.getByLabel('ログインID').fill(loginId);
  await page.getByLabel('パスワード').fill('password');
  await page.getByRole('button', { name: 'ログイン' }).click();
  await expect(page.getByRole('heading', { name: heading })).toBeVisible();
}

async function logout(page: Page) {
  await page.getByRole('button', { name: 'ログアウト' }).click();
  await expect(page.getByLabel('ログインID')).toBeVisible();
}

test('RT-F011-ORACLE-001 employee submission, manager approval, and admin monthly aggregation', async ({ page }) => {
  const reportDate = '2099-12-02';
  const yearMonth = '2099-12';
  const observedRequestIds: string[] = [];
  const operationRequestIds: Record<string, string> = {};
  page.on('response', (response) => {
    const requestId = response.headers()['x-request-id'];
    if (requestId) {
      observedRequestIds.push(requestId);
      const url = new URL(response.url());
      const method = response.request().method();
      if (method === 'POST' && url.pathname === '/api/daily-reports' && !operationRequestIds.create) {
        operationRequestIds.create = requestId;
      } else if (method === 'POST' && /\/api\/daily-reports\/[^/]+\/submit$/.test(url.pathname)) {
        operationRequestIds.submit = requestId;
      } else if (method === 'POST' && /\/api\/daily-reports\/[^/]+\/approve$/.test(url.pathname)) {
        operationRequestIds.approve = requestId;
      } else if (method === 'GET' && url.pathname === '/api/monthly-summaries'
        && url.searchParams.get('yearMonth') === '2099-12') {
        operationRequestIds.monthlySummary = requestId;
      }
    }
  });

  await login(page, 'employee001', '日報カレンダー・一覧');
  await expect(page.getByRole('heading', { name: '日報登録' })).toBeVisible();
  await page.getByLabel('日付').fill(reportDate);
  await expect(page.locator('input[type="number"]').first()).toHaveValue('480');

  const createResponsePromise = page.waitForResponse((response) =>
    response.url().endsWith('/api/daily-reports') && response.request().method() === 'POST');
  const submitResponsePromise = page.waitForResponse((response) =>
    /\/api\/daily-reports\/[^/]+\/submit$/.test(response.url()) && response.request().method() === 'POST');
  await page.getByRole('button', { name: '保存して提出' }).click();
  const createResponse = await createResponsePromise;
  const submitResponse = await submitResponsePromise;
  expect(createResponse.headers()['x-request-id']).toMatch(UUID_PATTERN);
  expect(submitResponse.headers()['x-request-id']).toMatch(UUID_PATTERN);
  await expect(page.getByText('保存して提出しました。')).toBeVisible();
  await expect(page.locator('.status-pill')).toHaveText('承認待ち');

  const reportId = (await page.url()).match(/\/daily-reports\/([^/]+)\/edit$/)?.[1];
  expect(reportId).toBeTruthy();
  await logout(page);

  await login(page, 'manager001', '日報カレンダー・一覧');
  await page.getByLabel('検索開始日').fill('2099-12-01');
  await page.getByLabel('検索終了日').fill('2099-12-31');
  const pendingResponsePromise = page.waitForResponse((response) =>
    response.url().includes('/api/daily-reports/pending-approvals') && response.request().method() === 'GET');
  await page.getByRole('button', { name: '検索' }).click();
  const pendingResponse = await pendingResponsePromise;
  expect(pendingResponse.headers()['x-request-id']).toMatch(UUID_PATTERN);
  const pendingRow = page.getByRole('row').filter({ hasText: reportId as string });
  await expect(pendingRow).toBeVisible();
  await pendingRow.getByRole('link', { name: '詳細' }).click();
  await expect(page.getByRole('heading', { name: '日報詳細' })).toBeVisible();
  await expect(page.locator('.status-pill')).toHaveText('承認待ち');

  await page.getByRole('button', { name: '承認する' }).click();
  const approveResponsePromise = page.waitForResponse((response) =>
    /\/api\/daily-reports\/[^/]+\/approve$/.test(response.url()) && response.request().method() === 'POST');
  await page.getByRole('button', { name: '承認を確定' }).click();
  const approveResponse = await approveResponsePromise;
  expect(approveResponse.status()).toBe(200);
  expect(approveResponse.headers()['x-request-id']).toMatch(UUID_PATTERN);
  await expect(page.locator('.status-pill')).toHaveText('承認済み');
  await logout(page);

  await login(page, 'admin001', '月次集計');
  await expect(page.getByRole('heading', { name: '月次集計' })).toBeVisible();
  await page.getByLabel('対象年月').fill(yearMonth);
  const monthlyResponsePromise = page.waitForResponse((response) =>
    response.url().includes('/api/monthly-summaries?yearMonth=2099-12') && response.request().method() === 'GET');
  await page.getByRole('button', { name: '集計表示' }).click();
  const monthlyResponse = await monthlyResponsePromise;
  expect(monthlyResponse.status()).toBe(200);
  expect(monthlyResponse.headers()['x-request-id']).toMatch(UUID_PATTERN);
  await expect(page.getByText('対象社員1名')).toBeVisible();
  await expect(page.getByText('総作業時間480分')).toBeVisible();
  await expect(page.getByRole('cell', { name: 'E001', exact: true })).toBeVisible();
  await expect(page.getByRole('cell', { name: '480', exact: true })).toBeVisible();
  await expect(page.getByRole('row').filter({ hasText: 'E001' })).toContainText('480');
  await page.getByRole('tab', { name: '案件別' }).click();
  await expect(page.getByRole('cell', { name: 'P001', exact: true })).toBeVisible();
  await expect(page.getByRole('row').filter({ hasText: 'P001' })).toContainText('480');
  await page.getByRole('tab', { name: '作業分類別' }).click();
  await expect(page.getByRole('cell', { name: 'WC001', exact: true })).toBeVisible();
  await expect(page.getByRole('row').filter({ hasText: 'WC001' })).toContainText('480');
  await page.getByRole('tab', { name: '休日区分別' }).click();
  await expect(page.getByRole('cell', { name: 'WORKDAY', exact: true })).toBeVisible();
  await expect(page.getByRole('cell', { name: '1', exact: true })).toBeVisible();
  await expect(page.getByRole('row').filter({ hasText: 'WORKDAY' })).toContainText('1');

  expect(operationRequestIds.create).toMatch(UUID_PATTERN);
  expect(operationRequestIds.submit).toMatch(UUID_PATTERN);
  expect(operationRequestIds.approve).toMatch(UUID_PATTERN);
  expect(operationRequestIds.monthlySummary).toMatch(UUID_PATTERN);
  console.log(`F011_REQUEST_IDS=${JSON.stringify(operationRequestIds)}`);
  expect(observedRequestIds.length).toBeGreaterThan(0);
  for (const requestId of observedRequestIds) {
    expect(requestId).toMatch(UUID_PATTERN);
  }
});
