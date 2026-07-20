import { expect, test } from '@playwright/test';
import { admin, employee, loginAsAdmin, loginAsEmployee, loginAsManager, manager } from './support/authMocks';
import { createApprovalMockState, mockApprovalApis } from './support/dailyReportApprovalMocks';
import { mockStaticFrontend } from './support/staticFrontend';

test('TC-APR-003 RT-APR-E2E-001 manager approves a pending report from the detail screen', async ({ page }) => {
  await mockApprovalApis(page, { user: manager });
  await mockStaticFrontend(page);
  const loginResponse = page.waitForResponse((response) => new URL(response.url()).pathname === '/api/auth/login');
  await loginAsManager(page);
  await expect(await (await loginResponse).json()).toEqual({
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
  });

  await expect(page.getByText('佐藤 花子', { exact: true })).toBeVisible();
  await expect(page.getByText('上長', { exact: true })).toBeVisible();
  await page.getByRole('link', { name: '詳細', exact: true }).click();
  await expect(page.getByRole('heading', { name: '日報詳細' })).toBeVisible();
  let approveRequests = 0;
  page.on('request', (request) => {
    if (new URL(request.url()).pathname.endsWith('/approve')) {
      approveRequests += 1;
    }
  });
  const approveTrigger = page.locator('button').filter({ hasText: /^承認する$/ });
  await approveTrigger.click();
  const approvalDialog = page.getByRole('dialog', { name: '日報を承認しますか' });
  await expect(approvalDialog).toBeVisible();
  await expect(approveTrigger).toBeDisabled();
  expect(approveRequests).toBe(0);
  await approvalDialog.getByRole('button', { name: 'キャンセル' }).click();
  await expect(approvalDialog).not.toBeVisible();
  await expect(approveTrigger).toBeFocused();
  expect(approveRequests).toBe(0);

  const approveResponse = page.waitForResponse((response) => new URL(response.url()).pathname.endsWith('/approve'));
  await approveTrigger.click();
  await page.getByRole('dialog', { name: '日報を承認しますか' }).getByRole('button', { name: '承認を確定' }).click();
  await expect(await (await approveResponse).json()).toMatchObject({
    approverId: 'U002',
    approverName: '佐藤 花子',
  });
  expect(approveRequests).toBe(1);

  await expect(page.locator('.status-pill')).toHaveText('承認済み');
  await expect(page.locator('.detail-grid').getByText('佐藤 花子', { exact: true })).toBeVisible();
  await expect(page.getByText('2026-06-28T09:00:00+09:00', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: '承認する' })).not.toBeVisible();
  await expect(page.getByRole('button', { name: '差し戻しする' })).not.toBeVisible();
  await page.getByRole('link', { name: '一覧へ戻る' }).click();
  const pendingPanel = page.locator('section.report-panel').filter({ has: page.getByRole('heading', { name: '未承認一覧' }) });
  await expect(pendingPanel.getByRole('cell', { name: 'R-PENDING-001', exact: true })).toHaveCount(0);
});

test('TC-APR-007 RT-APR-E2E-002 manager rejects a pending report and the employee updates then resubmits it', async ({ page, browser }) => {
  const state = createApprovalMockState();
  await mockApprovalApis(page, { user: manager, state });
  await mockStaticFrontend(page);
  await loginAsManager(page);

  await page.getByRole('link', { name: '詳細', exact: true }).click();
  await expect(page.getByRole('heading', { name: '日報詳細' })).toBeVisible();
  await page.getByRole('button', { name: '差し戻しする' }).click();
  await page.getByLabel('差し戻しコメント').fill('作業内容を補足してください。');
  const rejectResponse = page.waitForResponse((response) => new URL(response.url()).pathname.endsWith('/reject'));
  await page.getByRole('button', { name: '差し戻しを確定' }).click();
  await expect(await (await rejectResponse).json()).toMatchObject({
    rejectorId: 'U002',
    rejectorName: '佐藤 花子',
  });

  await expect(page.locator('.status-pill')).toHaveText('差戻し');
  await expect(page.locator('.detail-grid').getByText('佐藤 花子', { exact: true })).toBeVisible();
  await expect(page.getByText('作業内容を補足してください。', { exact: true })).toBeVisible();
  await expect(page.getByText('2026-06-28T09:05:00+09:00', { exact: true })).toBeVisible();

  const employeeContext = await browser.newContext();
  const employeePage = await employeeContext.newPage();
  const mutationRequests: string[] = [];
  employeePage.on('request', (request) => {
    const path = new URL(request.url()).pathname;
    if ((request.method() === 'POST' || request.method() === 'PUT') && path.startsWith('/api/daily-reports/')) {
      mutationRequests.push(`${request.method()} ${path}`);
    }
  });
  await mockApprovalApis(employeePage, { user: employee, state });
  await mockStaticFrontend(employeePage);
  const employeeLoginResponse = employeePage.waitForResponse((response) => new URL(response.url()).pathname === '/api/auth/login');
  await loginAsEmployee(employeePage);
  await expect(await (await employeeLoginResponse).json()).toEqual({
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
  });
  await employeePage.goto('/daily-reports/R-PENDING-001');

  await expect(employeePage.locator('.status-pill')).toHaveText('差戻し');
  await expect(employeePage.getByText('佐藤 花子', { exact: true })).toBeVisible();
  await expect(employeePage.getByText('作業内容を補足してください。', { exact: true })).toBeVisible();
  await employeePage.getByRole('link', { name: '編集する' }).click();
  await expect(employeePage.getByRole('heading', { name: '日報編集' })).toBeVisible();
  await employeePage.getByLabel('備考').fill('作業内容を補足して再提出します。');
  await employeePage.getByRole('button', { name: '保存して提出' }).click();

  await expect(employeePage.locator('.status-pill')).toHaveText('承認待ち');
  expect(mutationRequests).toEqual([
    'PUT /api/daily-reports/R-PENDING-001',
    'POST /api/daily-reports/R-PENDING-001/resubmit',
  ]);
  await employeePage.goto('/daily-reports/R-PENDING-001');
  await expect(employeePage.locator('.status-pill')).toHaveText('承認待ち');
  await expect(employeePage.getByText('2026-06-28T10:00:00+09:00', { exact: true })).toBeVisible();
  await expect(employeePage.getByText('佐藤 花子', { exact: true })).toBeVisible();
  await expect(employeePage.getByText('作業内容を補足してください。', { exact: true })).toBeVisible();
  await expect(employeePage.getByRole('link', { name: '編集する' })).not.toBeVisible();
  await employeeContext.close();
});

test('TC-APR-009 RT-APR-E2E-003 employee and admin do not see approval controls', async ({ page }) => {
  await mockApprovalApis(page, { user: employee });
  await mockStaticFrontend(page);
  const employeeLoginResponse = page.waitForResponse((response) => new URL(response.url()).pathname === '/api/auth/login');
  await loginAsEmployee(page);
  await expect(await (await employeeLoginResponse).json()).toEqual({
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
  });
  await page.goto('/daily-reports/R-PENDING-001');

  await expect(page.getByRole('heading', { name: '日報詳細' })).toBeVisible();
  await expect(page.getByText('山田 太郎', { exact: true })).toBeVisible();
  await expect(page.getByText('社員', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: '承認する' })).not.toBeVisible();
  await expect(page.getByRole('button', { name: '差し戻しする' })).not.toBeVisible();

  const adminPage = await page.context().newPage();
  await mockApprovalApis(adminPage, { user: admin });
  await mockStaticFrontend(adminPage);
  const adminLoginResponse = adminPage.waitForResponse((response) => new URL(response.url()).pathname === '/api/auth/login');
  await loginAsAdmin(adminPage);
  await expect(await (await adminLoginResponse).json()).toEqual({
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
  });
  await adminPage.goto('/daily-reports/R-PENDING-001');

  await expect(adminPage.getByRole('heading', { name: '日報詳細' })).toBeVisible();
  await expect(adminPage.getByText('鈴木 一郎', { exact: true })).toBeVisible();
  await expect(adminPage.getByText('管理者', { exact: true })).toBeVisible();
  await expect(adminPage.getByRole('button', { name: '承認する' })).not.toBeVisible();
  await expect(adminPage.getByRole('button', { name: '差し戻しする' })).not.toBeVisible();
  await adminPage.close();
});
