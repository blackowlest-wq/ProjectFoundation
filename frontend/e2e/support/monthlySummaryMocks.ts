import type { Page } from '@playwright/test';
import type { CurrentUser } from '../../src/auth/types';
import { admin, mockAuthApis } from './authMocks';

export const normalMonthlySummary = {
  yearMonth: '2026-06',
  employeeWorkSummaries: [
    { employeeId: 'E001', employeeName: '山田 太郎', totalWorkMinutes: 480 },
    { employeeId: 'E002', employeeName: '高橋 次郎', totalWorkMinutes: 360 },
  ],
  projectWorkSummaries: [
    { projectId: 'P001', projectName: 'プロジェクトA', totalWorkMinutes: 420 },
    { projectId: 'P002', projectName: 'プロジェクトB', totalWorkMinutes: 420 },
  ],
  categoryWorkSummaries: [
    { workCategoryId: 'WC001', workCategoryName: '設計', totalWorkMinutes: 540 },
    { workCategoryId: 'WC002', workCategoryName: '実装', totalWorkMinutes: 300 },
  ],
  holidayTypeSummaries: [
    { holidayType: 'WORKDAY', totalDays: 2 },
    { holidayType: 'PAID_LEAVE', totalDays: 1 },
  ],
} as const;

export const emptyMonthlySummary = {
  yearMonth: '2026-06',
  employeeWorkSummaries: [],
  projectWorkSummaries: [],
  categoryWorkSummaries: [],
  holidayTypeSummaries: [],
} as const;

type MonthlySummaryMockOptions = {
  user?: CurrentUser;
  response?: typeof normalMonthlySummary | typeof emptyMonthlySummary;
  status?: number;
  registerAuth?: boolean;
};

export async function mockMonthlySummaryApis(page: Page, options: MonthlySummaryMockOptions = {}) {
  if (options.registerAuth !== false) {
    await mockAuthApis(page, { user: options.user ?? admin });
  }
  const requestedUrls: string[] = [];
  await page.route('**/api/monthly-summaries**', async (route) => {
    requestedUrls.push(route.request().url());
    if (options.status && options.status !== 200) {
      await route.fulfill({ status: options.status, json: { code: 'UNAUTHORIZED', message: 'ログインが必要です。', details: [] } });
      return;
    }
    await route.fulfill({ json: options.response ?? normalMonthlySummary });
  });
  return { requestedUrls };
}
