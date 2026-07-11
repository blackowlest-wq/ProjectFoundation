import type { Page } from '@playwright/test';
import { employee, mockAuthApis } from './authMocks';

export const baseDailyReport = {
  reportId: 'R-DRAFT-001',
  employeeId: 'E001',
  employeeName: employee.userName,
  groupId: 'G001',
  groupName: '第1開発グループ',
  breakTypeId: 'BT001',
  breakTypeName: '標準休憩',
  workTimeTypeId: 'WT001',
  workTimeTypeName: '通常勤務',
  reportDate: '2026-06-27',
  holidayType: 'WORKDAY',
  startTime: '09:00',
  endTime: '18:00',
  remarks: '既存の下書き',
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
  approvalStatus: 'DRAFT',
  submittedAt: null,
  rejectComment: null,
  workItems: [{
    workItemId: 'WI001',
    projectId: 'P001',
    projectName: 'プロジェクトA',
    workCategoryId: 'WC001',
    workCategoryName: '実装',
    workMinutes: 480,
  }],
};

export async function mockDailyReportApis(page: Page, options: Parameters<typeof mockAuthApis>[1] = {}) {
  await mockAuthApis(page, options);
  await page.route('**/api/master/projects', async (route) => {
    await route.fulfill({ json: [{ projectId: 'P001', projectName: 'プロジェクトA' }] });
  });
  await page.route('**/api/master/work-categories', async (route) => {
    await route.fulfill({ json: [{ workCategoryId: 'WC001', workCategoryName: '実装' }] });
  });
  await page.route('**/api/master/holiday-types', async (route) => {
    await route.fulfill({
      json: [
        { holidayType: 'WORKDAY', holidayTypeName: '通常勤務' },
        { holidayType: 'HOLIDAY', holidayTypeName: '休日' },
        { holidayType: 'PAID_LEAVE', holidayTypeName: '有給休暇' },
      ],
    });
  });
  await page.route('**/api/daily-reports', async (route) => {
    if (route.request().method() !== 'POST') {
      await route.fallback();
      return;
    }
    await route.fulfill({
      status: 201,
      json: { reportId: 'R-E2E-001', approvalStatus: 'DRAFT' },
    });
  });
  await page.route('**/api/daily-reports/R-DRAFT-001', async (route) => {
    if (route.request().method() === 'GET') {
      await route.fulfill({ json: baseDailyReport });
      return;
    }
    if (route.request().method() === 'PUT') {
      await route.fulfill({ json: { reportId: 'R-DRAFT-001', approvalStatus: 'DRAFT' } });
      return;
    }
    await route.fallback();
  });
  await page.route('**/api/daily-reports/R-REJECTED-001', async (route) => {
    if (route.request().method() === 'GET') {
      await route.fulfill({
        json: {
          ...baseDailyReport,
          reportId: 'R-REJECTED-001',
          approvalStatus: 'REJECTED',
          remarks: '差戻しされた下書き',
          rejectComment: '詳細を追記してください。',
        },
      });
      return;
    }
    if (route.request().method() === 'PUT') {
      await route.fulfill({ json: { reportId: 'R-REJECTED-001', approvalStatus: 'REJECTED' } });
      return;
    }
    await route.fallback();
  });
  await page.route('**/api/daily-reports/R-E2E-001/submit', async (route) => {
    await route.fulfill({
      json: {
        reportId: 'R-E2E-001',
        approvalStatus: 'PENDING',
        submittedAt: '2026-06-28T10:00:00+09:00',
      },
    });
  });
  await page.route('**/api/daily-reports/R-REJECTED-001/resubmit', async (route) => {
    await route.fulfill({
      json: {
        reportId: 'R-REJECTED-001',
        approvalStatus: 'PENDING',
        submittedAt: '2026-06-28T10:00:00+09:00',
      },
    });
  });
}
