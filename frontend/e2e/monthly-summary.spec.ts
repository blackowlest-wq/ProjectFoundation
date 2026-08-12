import { expect, test } from '@playwright/test';
import { admin, employee, loginAsAdmin, loginAsEmployee, loginAsManager, manager } from './support/authMocks';
import { mockDailyReportApis } from './support/dailyReportMocks';
import { emptyMonthlySummary, mockMonthlySummaryApis, normalMonthlySummary } from './support/monthlySummaryMocks';
import { mockStaticFrontend } from './support/staticFrontend';

test('RT-F011-E2E-001 admin can inspect concrete monthly aggregates and move tabs by keyboard', async ({ page }) => {
  const { requestedUrls } = await mockMonthlySummaryApis(page, { user: admin, response: normalMonthlySummary });
  await mockStaticFrontend(page);
  await loginAsAdmin(page);

  await expect(page).toHaveURL(/\/monthly-summaries$/);
  await page.getByLabel('対象年月').fill('2026-06');
  await page.getByRole('button', { name: '集計表示' }).click();
  await expect(page.getByText('対象社員2名')).toBeVisible();
  await expect(page.getByText('総作業時間840分')).toBeVisible();
  await expect(page.getByRole('cell', { name: 'E001', exact: true })).toBeVisible();
  await expect(page.getByRole('cell', { name: '山田 太郎', exact: true })).toBeVisible();
  await expect(page.getByRole('cell', { name: '480', exact: true })).toBeVisible();
  await expect(page.getByRole('cell', { name: 'E002', exact: true })).toBeVisible();
  await expect(page.getByRole('cell', { name: '高橋 次郎', exact: true })).toBeVisible();
  await expect(page.getByRole('cell', { name: '360', exact: true })).toBeVisible();
  await expect(page.getByRole('row').filter({ hasText: 'E001' })).toContainText('480');
  await expect(page.getByRole('row').filter({ hasText: 'E002' })).toContainText('360');
  await expect(page.locator('[role="tabpanel"]:not([hidden])')).toHaveCount(1);
  await expect(page.locator('[role="tabpanel"][hidden]')).toHaveCount(3);

  const request = requestedUrls.at(-1);
  expect(request).toContain('/api/monthly-summaries?yearMonth=2026-06');
  expect(requestedUrls.filter((url) => url.includes('yearMonth=2026-06'))).toHaveLength(1);

  const employeeTab = page.getByRole('tab', { name: '社員別' });
  await employeeTab.focus();
  await page.keyboard.press('ArrowRight');
  await expect(page.getByRole('tab', { name: '案件別' })).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByRole('cell', { name: 'P001', exact: true })).toBeVisible();
  await expect(page.getByRole('cell', { name: 'プロジェクトA', exact: true })).toBeVisible();
  await expect(page.getByRole('cell', { name: 'P002', exact: true })).toBeVisible();
  await expect(page.getByRole('cell', { name: 'プロジェクトB', exact: true })).toBeVisible();
  await expect(page.getByRole('row').filter({ hasText: 'P001' })).toContainText('420');
  await expect(page.getByRole('row').filter({ hasText: 'P002' })).toContainText('420');
  await expect(page.locator('[role="tabpanel"]:not([hidden])')).toHaveCount(1);
  await expect(page.locator('[role="tabpanel"][hidden]')).toHaveCount(3);
  await page.keyboard.press('ArrowRight');
  await expect(page.getByRole('tab', { name: '作業分類別' })).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByRole('cell', { name: 'WC001', exact: true })).toBeVisible();
  await expect(page.getByRole('cell', { name: '設計', exact: true })).toBeVisible();
  await expect(page.getByRole('cell', { name: 'WC002', exact: true })).toBeVisible();
  await expect(page.getByRole('cell', { name: '実装', exact: true })).toBeVisible();
  await expect(page.getByRole('row').filter({ hasText: 'WC001' })).toContainText('540');
  await expect(page.getByRole('row').filter({ hasText: 'WC002' })).toContainText('300');
  await expect(page.locator('[role="tabpanel"]:not([hidden])')).toHaveCount(1);
  await expect(page.locator('[role="tabpanel"][hidden]')).toHaveCount(3);
  await page.getByRole('tab', { name: '休日区分別' }).click();
  await expect(page.getByRole('cell', { name: 'PAID_LEAVE', exact: true })).toBeVisible();
  await expect(page.getByRole('cell', { name: 'WORKDAY', exact: true })).toBeVisible();
  await expect(page.getByRole('cell', { name: '1', exact: true })).toBeVisible();
  await expect(page.getByRole('row').filter({ hasText: 'WORKDAY' })).toContainText('2');
  await expect(page.getByRole('row').filter({ hasText: 'PAID_LEAVE' })).toContainText('1');
  await expect(page.locator('[role="tabpanel"]:not([hidden])')).toHaveCount(1);
  await expect(page.locator('[role="tabpanel"][hidden]')).toHaveCount(3);
});

test('RT-F011-E2E-003 admin can operate an empty monthly summary in every tab', async ({ page }) => {
  await mockMonthlySummaryApis(page, { user: admin, response: emptyMonthlySummary });
  await mockStaticFrontend(page);
  await loginAsAdmin(page);

  await expect(page.getByText('対象社員0名')).toBeVisible();
  await expect(page.getByText('総作業時間0分')).toBeVisible();
  for (const tabName of ['社員別', '案件別', '作業分類別', '休日区分別']) {
    await page.getByRole('tab', { name: tabName }).click();
    await expect(page.locator('[role="tabpanel"]:not([hidden])').getByText('該当する集計データはありません。'))
      .toBeVisible();
    await expect(page.locator('[role="tabpanel"]:not([hidden])')).toHaveCount(1);
    await expect(page.locator('[role="tabpanel"][hidden]')).toHaveCount(3);
  }
});

test('RT-F011-E2E-002 employee cannot see the monthly page or request its API', async ({ page }) => {
  await mockDailyReportApis(page, { user: employee });
  const { requestedUrls } = await mockMonthlySummaryApis(page, { registerAuth: false });
  await mockStaticFrontend(page);
  await loginAsEmployee(page);

  await expect(page.getByRole('heading', { name: '日報カレンダー・一覧' })).toBeVisible();
  expect(requestedUrls).toHaveLength(0);
  await expect(page.getByRole('heading', { name: '月次集計' })).not.toBeVisible();
});

test('RT-F011-E2E-002 manager cannot see the monthly page or request its API', async ({ page }) => {
  await mockDailyReportApis(page, { user: manager });
  const { requestedUrls } = await mockMonthlySummaryApis(page, { registerAuth: false });
  await mockStaticFrontend(page);
  await loginAsManager(page);
  await expect(page.getByRole('heading', { name: '日報カレンダー・一覧' })).toBeVisible();
  expect(requestedUrls).toHaveLength(0);
  await expect(page.getByRole('heading', { name: '月次集計' })).not.toBeVisible();
});
