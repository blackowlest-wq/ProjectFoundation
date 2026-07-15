import { expect, test } from '@playwright/test';

test('employee saves, submits, and reloads a daily report through Backend and Oracle', async ({ page }) => {
  const reportDate = '2099-12-01';
  await page.goto('/login');
  await page.getByLabel('ログインID').fill('employee001');
  await page.getByLabel('パスワード').fill('password');
  await page.getByRole('button', { name: 'ログイン' }).click();
  await expect(page.getByRole('heading', { name: '日報カレンダー・一覧' })).toBeVisible();

  await page.getByLabel('日付').fill(reportDate);
  await page.getByLabel('休日区分').last().selectOption('PAID_LEAVE');
  const createResponsePromise = page.waitForResponse((response) =>
    response.url().endsWith('/api/daily-reports') && response.request().method() === 'POST');

  await page.getByRole('button', { name: '保存して提出' }).click();
  const createResponse = await createResponsePromise;
  expect(createResponse.headers()['x-request-id']).toMatch(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );
  await expect(page.getByText('保存して提出しました。')).toBeVisible();
  await expect(page.locator('.status-pill')).toHaveText('承認待ち');
  await expect(page).toHaveURL(/\/daily-reports\/[^/]+\/edit$/);

  await page.reload();
  await expect(page.getByLabel('日付')).toHaveValue(reportDate);
  await expect(page.locator('.status-pill')).toHaveText('承認待ち');

  const duplicateResult = await page.evaluate(async ({ date }) => {
    const csrfCookie = document.cookie.split(';')
      .map((cookie) => cookie.trim())
      .find((cookie) => cookie.startsWith('XSRF-TOKEN='));
    const csrfToken = csrfCookie ? decodeURIComponent(csrfCookie.slice('XSRF-TOKEN='.length)) : '';
    const response = await fetch('/api/daily-reports', {
      method: 'POST',
      credentials: 'include',
      headers: {
        'Content-Type': 'application/json',
        'X-XSRF-TOKEN': csrfToken,
      },
      body: JSON.stringify({
        reportDate: date,
        holidayType: 'PAID_LEAVE',
        startTime: null,
        endTime: null,
        remarks: '',
        workItems: [],
      }),
    });
    const body = await response.json() as { code?: string };
    return {
      code: body.code,
      requestId: response.headers.get('X-Request-Id'),
      status: response.status,
    };
  }, { date: reportDate });
  expect(duplicateResult.status).toBe(409);
  expect(duplicateResult.code).toBe('DUPLICATE_REPORT');
  expect(duplicateResult.requestId).toMatch(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );
});
