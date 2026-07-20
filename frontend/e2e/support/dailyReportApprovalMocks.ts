import type { Page } from '@playwright/test';
import type { CurrentUser } from '../../src/auth/types';
import { employee } from './authMocks';

const pendingReport = {
  reportId: 'R-PENDING-001',
  employeeId: employee.employeeId,
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
  remarks: '承認待ちの日報',
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
  submittedAt: '2026-06-27T18:10:00+09:00',
  approverId: null,
  approverName: null,
  approvedAt: null,
  rejectorId: null,
  rejectorName: null,
  rejectedAt: null,
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

type ApprovalMockOptions = {
  user?: CurrentUser;
  state?: ApprovalMockState;
};

export type ApprovalMockState = {
  report: typeof pendingReport;
};

/** 別Browser Contextの利用者間でも、同じ日報の状態遷移だけを共有する。認証状態は共有しない。 */
export function createApprovalMockState(): ApprovalMockState {
  return {
    report: { ...pendingReport, workItems: [...pendingReport.workItems] },
  };
}

/** 承認画面だけに必要な認証・一覧・詳細・状態変更APIを状態付きでモックする。 */
export async function mockApprovalApis(page: Page, options: ApprovalMockOptions = {}) {
  const currentUser = options.user ?? employee;
  let authenticated = false;
  const state = options.state ?? createApprovalMockState();

  await page.route('**/api/auth/me', async (route) => {
    if (!authenticated) {
      await route.fulfill({ status: 401, body: '' });
      return;
    }
    await route.fulfill({ json: currentUser });
  });
  await page.route('**/api/auth/login', async (route) => {
    authenticated = true;
    await route.fulfill({ json: currentUser });
  });
  await page.route('**/api/master/projects', async (route) => {
    await route.fulfill({ json: [{ projectId: 'P001', projectName: 'プロジェクトA' }] });
  });
  await page.route('**/api/master/work-categories', async (route) => {
    await route.fulfill({ json: [{ workCategoryId: 'WC001', workCategoryName: '実装' }] });
  });
  await page.route('**/api/master/holiday-types', async (route) => {
    await route.fulfill({ json: [{ holidayType: 'WORKDAY', holidayTypeName: '通常勤務' }] });
  });
  await page.route('**/api/daily-reports/pending-approvals?**', async (route) => {
    await route.fulfill({
      json: state.report.approvalStatus === 'PENDING' ? [{
        ...state.report,
        rejected: false,
      }] : [],
    });
  });
  await page.route('**/api/daily-reports/R-PENDING-001/approve', async (route) => {
    if (route.request().method() !== 'POST') {
      await route.fallback();
      return;
    }
    state.report = {
      ...state.report,
      approvalStatus: 'APPROVED',
      approverId: 'U002',
      approverName: '佐藤 花子',
      approvedAt: '2026-06-28T09:00:00+09:00',
    };
    await route.fulfill({
      json: {
        reportId: state.report.reportId,
        approvalStatus: state.report.approvalStatus,
        approverId: state.report.approverId,
        approverName: state.report.approverName,
        approvedAt: state.report.approvedAt,
      },
    });
  });
  await page.route('**/api/daily-reports/R-PENDING-001/reject', async (route) => {
    if (route.request().method() !== 'POST') {
      await route.fallback();
      return;
    }
    const { rejectComment } = route.request().postDataJSON() as { rejectComment: string };
    state.report = {
      ...state.report,
      approvalStatus: 'REJECTED',
      rejectorId: 'U002',
      rejectorName: '佐藤 花子',
      rejectedAt: '2026-06-28T09:05:00+09:00',
      rejectComment,
    };
    await route.fulfill({
      json: {
        reportId: state.report.reportId,
        approvalStatus: state.report.approvalStatus,
        rejectorId: state.report.rejectorId,
        rejectorName: state.report.rejectorName,
        rejectedAt: state.report.rejectedAt,
        rejectComment: state.report.rejectComment,
      },
    });
  });
  await page.route('**/api/daily-reports/R-PENDING-001', async (route) => {
    if (route.request().method() === 'GET') {
      await route.fulfill({ json: state.report });
      return;
    }
    if (route.request().method() === 'PUT') {
      const request = route.request().postDataJSON() as { remarks: string | null };
      state.report = { ...state.report, remarks: request.remarks };
      await route.fulfill({ json: { reportId: state.report.reportId, approvalStatus: state.report.approvalStatus } });
      return;
    }
    await route.fallback();
  });
  await page.route('**/api/daily-reports/R-PENDING-001/resubmit', async (route) => {
    if (route.request().method() !== 'POST') {
      await route.fallback();
      return;
    }
    state.report = {
      ...state.report,
      approvalStatus: 'PENDING',
      submittedAt: '2026-06-28T10:00:00+09:00',
    };
    await route.fulfill({
      json: {
        reportId: state.report.reportId,
        approvalStatus: state.report.approvalStatus,
        submittedAt: state.report.submittedAt,
      },
    });
  });
}
