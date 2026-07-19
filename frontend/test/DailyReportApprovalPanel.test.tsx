// @vitest-environment jsdom

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DailyReportDetail } from '../src/dailyReport/DailyReportDetail';
import { DailyReportPendingApprovalList } from '../src/dailyReport/DailyReportPendingApprovalList';
import {
  adminUser,
  buildListItem,
  buildReportDetail,
  buttonByText,
  cleanupUi,
  click,
  countRequests,
  currentUser,
  installFrontendFetch,
  managerUser,
  rejectWith,
  renderUi,
  respondJson,
  setControlValue,
} from './support/dailyReportTestSupport';

describe('DailyReport approval panel behavior from task-owned tests', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-17T09:00:00+09:00'));
  });

  afterEach(() => {
    cleanupUi();
  });

  it('shows pending reports and their detail links for managers', async () => {
    installFrontendFetch({
      pendingApprovals: respondJson([buildListItem('R-PENDING-001', { approvalStatus: 'PENDING' })]),
    });

    await renderUi(<DailyReportPendingApprovalList user={managerUser} />);

    expect(document.body.textContent).toContain('山田 太郎');
    const detailLink = Array.from(document.querySelectorAll('a')).find((link) => link.textContent === '詳細');
    expect(detailLink?.getAttribute('href')).toBe('/daily-reports/R-PENDING-001');
  });

  it.each([currentUser, adminUser])('hides pending approvals for non-managers', async (user) => {
    const { calls } = installFrontendFetch();

    await renderUi(<DailyReportPendingApprovalList user={user} />);

    expect(document.body.textContent).not.toContain('未承認一覧');
    expect(countRequests(calls, 'GET', '/api/daily-reports/pending-approvals')).toBe(0);
  });

  it('requires a comment before sending rejection', async () => {
    const { calls } = installFrontendFetch({
      reportDetails: {
        'R-PENDING-001': respondJson(buildReportDetail('R-PENDING-001', { approvalStatus: 'PENDING' })),
      },
    });

    await renderUi(<DailyReportDetail user={managerUser} reportId="R-PENDING-001" />);
    await click(buttonByText('差し戻しする'));
    await click(buttonByText('差し戻しを確定'));

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('差し戻しコメントを入力してください。');
    expect(countRequests(calls, 'POST', '/api/daily-reports/R-PENDING-001/reject')).toBe(0);
  });

  it('shows approval audit values after approving a pending report', async () => {
    installFrontendFetch({
      reportDetails: {
        'R-PENDING-001': respondJson(buildReportDetail('R-PENDING-001', { approvalStatus: 'PENDING' })),
      },
    });

    await renderUi(<DailyReportDetail user={managerUser} reportId="R-PENDING-001" />);
    await click(buttonByText('承認する'));

    expect(document.body.textContent).toContain('承認済み');
    expect(document.body.textContent).toContain('佐藤 上長');
  });

  it('does not show state controls when detail loading fails', async () => {
    installFrontendFetch({ reportDetails: { 'R-OUTSIDE': rejectWith({ code: 'FORBIDDEN', message: '参照できません。' }) } });

    await renderUi(<DailyReportDetail user={managerUser} reportId="R-OUTSIDE" />);

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('参照できません。');
    expect(document.body.textContent).not.toContain('承認する');
    expect(document.body.textContent).not.toContain('差し戻しする');
  });

  it('notifies the parent and keeps controls hidden after an unauthorized detail request', async () => {
    const onUnauthorized = vi.fn();
    installFrontendFetch({ reportDetails: { 'R-UNAUTHORIZED': rejectWith({ code: 'UNAUTHORIZED', message: 'ログインが必要です。' }) } });

    await renderUi(<DailyReportDetail user={managerUser} reportId="R-UNAUTHORIZED" onUnauthorized={onUnauthorized} />);

    expect(onUnauthorized).toHaveBeenCalledTimes(1);
    expect(document.body.textContent).not.toContain('承認する');
  });

  it('refreshes stale detail and hides controls after a status conflict', async () => {
    installFrontendFetch({
      approve: rejectWith({ code: 'INVALID_STATUS', message: '日報はすでに処理されています。' }),
      reportDetails: {
        'R-PENDING-001': (callCount) => respondJson(buildReportDetail('R-PENDING-001', {
          approvalStatus: callCount === 1 ? 'PENDING' : 'APPROVED',
          approverName: callCount === 1 ? null : '佐藤 上長',
          approvedAt: callCount === 1 ? null : '2026-07-17T09:00:00+09:00',
        })),
      },
    });

    await renderUi(<DailyReportDetail user={managerUser} reportId="R-PENDING-001" />);
    await click(buttonByText('承認する'));

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('日報はすでに処理されています。');
    expect(document.body.textContent).toContain('承認済み');
    expect(document.body.textContent).not.toContain('差し戻しする');
  });

  it('submits a nonblank rejection comment and refreshes the detail', async () => {
    const { calls } = installFrontendFetch({
      reportDetails: {
        'R-PENDING-001': (callCount) => respondJson(buildReportDetail('R-PENDING-001', callCount === 1
          ? { approvalStatus: 'PENDING' }
          : { approvalStatus: 'REJECTED', rejectorName: '佐藤 上長', rejectedAt: '2026-07-17T09:00:00+09:00', rejectComment: '作業時間を確認してください。' })),
      },
    });

    await renderUi(<DailyReportDetail user={managerUser} reportId="R-PENDING-001" />);
    await click(buttonByText('差し戻しする'));
    setControlValue(document.querySelector('textarea')!, '作業時間を確認してください。');
    await click(buttonByText('差し戻しを確定'));

    expect(countRequests(calls, 'POST', '/api/daily-reports/R-PENDING-001/reject')).toBe(1);
    expect(document.body.textContent).toContain('差戻し');
    expect(document.body.textContent).toContain('作業時間を確認してください。');
  });
});
