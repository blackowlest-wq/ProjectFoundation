import { expect, test } from '@playwright/test';
import { admin, employee, loginAsAdmin, loginAsEmployee, loginAsManager, manager } from './support/authMocks';
import { mockApprovalApis } from './support/dailyReportApprovalMocks';
import { mockStaticFrontend } from './support/staticFrontend';

test('RT-APR-E2E-001 manager approves a pending report from the detail screen', async ({ page }) => {
  await mockApprovalApis(page, { user: manager });
  await mockStaticFrontend(page);
  await loginAsManager(page);

  await expect(page.getByText('佐藤 花子', { exact: true })).toBeVisible();
  await expect(page.getByText('上長', { exact: true })).toBeVisible();
  await page.getByRole('link', { name: '詳細', exact: true }).click();
  await expect(page.getByRole('heading', { name: '日報詳細' })).toBeVisible();
  await page.getByRole('button', { name: '承認する' }).click();

  await expect(page.locator('.status-pill')).toHaveText('承認済み');
  await expect(page.getByText('佐藤 上長', { exact: true })).toBeVisible();
  await expect(page.getByText('2026-06-28T09:00:00+09:00', { exact: true })).toBeVisible();
});

test('RT-APR-E2E-002 manager rejects a pending report and sees the latest audit comment', async ({ page }) => {
  await mockApprovalApis(page, { user: manager });
  await mockStaticFrontend(page);
  await loginAsManager(page);

  await page.getByRole('link', { name: '詳細', exact: true }).click();
  await expect(page.getByRole('heading', { name: '日報詳細' })).toBeVisible();
  await page.getByRole('button', { name: '差し戻しする' }).click();
  await page.getByLabel('差し戻しコメント').fill('作業内容を補足してください。');
  await page.getByRole('button', { name: '差し戻しを確定' }).click();

  await expect(page.locator('.status-pill')).toHaveText('差戻し');
  await expect(page.getByText('佐藤 上長', { exact: true })).toBeVisible();
  await expect(page.getByText('作業内容を補足してください。', { exact: true })).toBeVisible();
  await expect(page.getByText('2026-06-28T09:05:00+09:00', { exact: true })).toBeVisible();
});

test('RT-APR-E2E-003 employee and admin do not see approval controls', async ({ page }) => {
  await mockApprovalApis(page, { user: employee });
  await mockStaticFrontend(page);
  await loginAsEmployee(page);
  await page.goto('/daily-reports/R-PENDING-001');

  await expect(page.getByRole('heading', { name: '日報詳細' })).toBeVisible();
  await expect(page.getByText('山田 太郎', { exact: true })).toBeVisible();
  await expect(page.getByText('社員', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: '承認する' })).not.toBeVisible();
  await expect(page.getByRole('button', { name: '差し戻しする' })).not.toBeVisible();

  const adminPage = await page.context().newPage();
  await mockApprovalApis(adminPage, { user: admin });
  await mockStaticFrontend(adminPage);
  await loginAsAdmin(adminPage);
  await adminPage.goto('/daily-reports/R-PENDING-001');

  await expect(adminPage.getByRole('heading', { name: '日報詳細' })).toBeVisible();
  await expect(adminPage.getByText('鈴木 管理者', { exact: true })).toBeVisible();
  await expect(adminPage.getByText('管理者', { exact: true })).toBeVisible();
  await expect(adminPage.getByRole('button', { name: '承認する' })).not.toBeVisible();
  await expect(adminPage.getByRole('button', { name: '差し戻しする' })).not.toBeVisible();
  await adminPage.close();
});
