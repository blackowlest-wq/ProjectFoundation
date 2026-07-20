// @vitest-environment jsdom

import { act } from 'react';
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
  flushEffects,
  installFrontendFetch,
  keyDown,
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

  it('TC-APR-008 RT-APR-UI-001 sends current-month and selected pending filters, then clears them back to the current month', async () => {
    const { calls } = installFrontendFetch({
      pendingApprovals: respondJson([buildListItem('R-PENDING-001', { approvalStatus: 'PENDING' })]),
    });

    await renderUi(<DailyReportPendingApprovalList user={managerUser} />);

    expect(document.body.textContent).toContain('山田 太郎');
    const initialRequest = calls.find((call) => call.method === 'GET' && call.url.pathname === '/api/daily-reports/pending-approvals');
    expect(initialRequest?.url.searchParams.get('dateFrom')).toBe('2026-07-01');
    expect(initialRequest?.url.searchParams.get('dateTo')).toBe('2026-07-31');
    const detailLink = Array.from(document.querySelectorAll('a')).find((link) => link.textContent === '詳細');
    expect(detailLink?.getAttribute('href')).toBe('/daily-reports/R-PENDING-001');

    setControlValue(document.querySelector('input[aria-label="検索開始日"]')!, '2026-07-02');
    setControlValue(document.querySelector('input[aria-label="検索終了日"]')!, '2026-07-16');
    setControlValue(document.querySelector('input[aria-label="グループID"]')!, 'G 1&2');
    setControlValue(document.querySelector('input[aria-label="社員ID"]')!, 'E/ 1');
    await click(buttonByText('検索'));

    const selectedRequest = calls.at(-1)?.url;
    expect(selectedRequest?.searchParams.get('dateFrom')).toBe('2026-07-02');
    expect(selectedRequest?.searchParams.get('dateTo')).toBe('2026-07-16');
    expect(selectedRequest?.searchParams.get('groupId')).toBe('G 1&2');
    expect(selectedRequest?.searchParams.get('employeeId')).toBe('E/ 1');
    expect(selectedRequest?.search).toContain('G+1%262');
    expect(selectedRequest?.search).toContain('E%2F+1');

    await click(buttonByText('条件クリア'));
    expect(document.querySelector<HTMLInputElement>('input[aria-label="検索開始日"]')?.value).toBe('2026-07-01');
    expect(document.querySelector<HTMLInputElement>('input[aria-label="検索終了日"]')?.value).toBe('2026-07-31');
    expect(document.querySelector<HTMLInputElement>('input[aria-label="グループID"]')?.value).toBe('');
    expect(document.querySelector<HTMLInputElement>('input[aria-label="社員ID"]')?.value).toBe('');
    expect(calls.at(-1)?.url.search).toBe('?dateFrom=2026-07-01&dateTo=2026-07-31');
  });

  it('TC-APR-008 RT-APR-UI-001 validates dates and separates empty and API-error pending-list states', async () => {
    const { calls } = installFrontendFetch({ pendingApprovals: respondJson([]) });

    await renderUi(<DailyReportPendingApprovalList user={managerUser} />);
    expect(document.body.textContent).toContain('承認待ちの日報はありません。');
    const requestCount = countRequests(calls, 'GET', '/api/daily-reports/pending-approvals');
    setControlValue(document.querySelector('input[aria-label="検索開始日"]')!, '');
    await click(buttonByText('検索'));
    expect(document.querySelector('[role="alert"]')?.textContent).toBe('対象期間を指定してください。');
    expect(countRequests(calls, 'GET', '/api/daily-reports/pending-approvals')).toBe(requestCount);

    cleanupUi();
    installFrontendFetch({ pendingApprovals: rejectWith({}) });
    await renderUi(<DailyReportPendingApprovalList user={managerUser} />);
    expect(document.querySelector('[role="alert"]')?.textContent).toBe('未承認一覧の取得に失敗しました。');
  });

  it.each([currentUser, adminUser])('TC-APR-009 RT-APR-UI-003 hides pending approvals and makes no pending-list request for non-managers', async (user) => {
    const { calls } = installFrontendFetch();

    await renderUi(<DailyReportPendingApprovalList user={user} />);

    expect(document.body.textContent).not.toContain('未承認一覧');
    expect(countRequests(calls, 'GET', '/api/daily-reports/pending-approvals')).toBe(0);
  });

  it('TC-APR-006 RT-APR-UI-002 requires a comment before sending rejection', async () => {
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

  it('TC-APR-010 RT-APR-UI-004 shows approval audit values after approving a pending report', async () => {
    installFrontendFetch({
      reportDetails: {
        'R-PENDING-001': respondJson(buildReportDetail('R-PENDING-001', { approvalStatus: 'PENDING' })),
      },
    });

    await renderUi(<DailyReportDetail user={managerUser} reportId="R-PENDING-001" />);
    await click(buttonByText('承認する'));
    await click(buttonByText('承認を確定'));

    expect(document.body.textContent).toContain('承認済み');
    expect(document.body.textContent).toContain('佐藤 上長');
  });

  it('TC-APR-003 TC-APR-010 RT-APR-UI-004 opens an approval confirmation before sending the request and safely cancels it', async () => {
    const { calls } = installFrontendFetch({
      reportDetails: {
        'R-PENDING-001': respondJson(buildReportDetail('R-PENDING-001', { approvalStatus: 'PENDING' })),
      },
    });

    await renderUi(<DailyReportDetail user={managerUser} reportId="R-PENDING-001" />);
    const approveTrigger = buttonByText('承認する');
    await click(approveTrigger);

    const dialog = document.querySelector('[role="dialog"]')!;
    expect(dialog.textContent).toContain('日報を承認しますか');
    expect(countRequests(calls, 'POST', '/api/daily-reports/R-PENDING-001/approve')).toBe(0);
    expect(buttonByText('差し戻しする').disabled).toBe(true);

    await keyDown(dialog, 'Escape');
    expect(document.querySelector('[role="dialog"]')).toBeNull();
    expect(document.activeElement).toBe(approveTrigger);
    expect(countRequests(calls, 'POST', '/api/daily-reports/R-PENDING-001/approve')).toBe(0);

    await click(approveTrigger);
    await click(buttonByText('キャンセル'));
    expect(document.querySelector('[role="dialog"]')).toBeNull();
    expect(document.activeElement).toBe(approveTrigger);
    expect(countRequests(calls, 'POST', '/api/daily-reports/R-PENDING-001/approve')).toBe(0);

    await click(approveTrigger);
    await click(buttonByText('承認を確定'));
    expect(countRequests(calls, 'POST', '/api/daily-reports/R-PENDING-001/approve')).toBe(1);
  });

  it('TC-APR-010 RT-APR-UI-004 does not show state controls when detail loading fails', async () => {
    installFrontendFetch({ reportDetails: { 'R-OUTSIDE': rejectWith({ code: 'FORBIDDEN', message: '参照できません。' }) } });

    await renderUi(<DailyReportDetail user={managerUser} reportId="R-OUTSIDE" />);

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('参照できません。');
    expect(document.body.textContent).not.toContain('承認する');
    expect(document.body.textContent).not.toContain('差し戻しする');
  });

  it('TC-APR-010 RT-APR-UI-004 notifies the parent and keeps controls hidden after an unauthorized detail request', async () => {
    const onUnauthorized = vi.fn();
    installFrontendFetch({ reportDetails: { 'R-UNAUTHORIZED': rejectWith({ code: 'UNAUTHORIZED', message: 'ログインが必要です。' }) } });

    await renderUi(<DailyReportDetail user={managerUser} reportId="R-UNAUTHORIZED" onUnauthorized={onUnauthorized} />);

    expect(onUnauthorized).toHaveBeenCalledTimes(1);
    expect(document.body.textContent).not.toContain('承認する');
  });

  it('TC-APR-010 RT-APR-UI-004 refreshes stale detail and hides controls after a status conflict', async () => {
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
    await click(buttonByText('承認を確定'));

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('日報はすでに処理されています。');
    expect(document.body.textContent).toContain('承認済み');
    expect(document.body.textContent).not.toContain('差し戻しする');
  });

  it('TC-APR-010 RT-APR-UI-004 submits a nonblank rejection comment and refreshes the detail', async () => {
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

  it.each(['DRAFT', 'REJECTED'] as const)('TC-APR-010 RT-APR-UI-004 provides an encoded employee edit link and list return for %s reports only', async (approvalStatus) => {
    const reportId = 'R /?';
    installFrontendFetch({
      reportDetails: { [reportId]: respondJson(buildReportDetail(reportId, { approvalStatus })) },
    });

    await renderUi(<DailyReportDetail user={currentUser} reportId={reportId} />);

    const editLink = Array.from(document.querySelectorAll('a')).find((link) => link.textContent === '編集する');
    expect(editLink?.getAttribute('href')).toBe('/daily-reports/R%20%2F%3F/edit');
    expect(Array.from(document.querySelectorAll('a')).find((link) => link.textContent === '一覧へ戻る')?.getAttribute('href')).toBe('/daily-reports');
  });

  it.each(['PENDING', 'APPROVED'] as const)('TC-APR-010 RT-APR-UI-004 does not expose employee edit navigation for %s reports', async (approvalStatus) => {
    installFrontendFetch({
      reportDetails: { [`R-${approvalStatus}`]: respondJson(buildReportDetail(`R-${approvalStatus}`, { approvalStatus })) },
    });

    await renderUi(<DailyReportDetail user={currentUser} reportId={`R-${approvalStatus}`} />);

    expect(Array.from(document.querySelectorAll('a')).some((link) => link.textContent === '編集する')).toBe(false);
  });

  it.each([managerUser, adminUser])('TC-APR-010 RT-APR-UI-004 keeps edit navigation hidden for manager and admin detail views', async (user) => {
    installFrontendFetch({
      reportDetails: { 'R-DRAFT': respondJson(buildReportDetail('R-DRAFT', { approvalStatus: 'DRAFT' })) },
    });

    await renderUi(<DailyReportDetail user={user} reportId="R-DRAFT" />);

    expect(Array.from(document.querySelectorAll('a')).some((link) => link.textContent === '編集する')).toBe(false);
    expect(Array.from(document.querySelectorAll('a')).find((link) => link.textContent === '一覧へ戻る')?.getAttribute('href'))
      .toBe(user.role === 'MANAGER' ? '/pending-approvals' : '/daily-reports');
  });

  it.each([
    ['approve', 'UNAUTHORIZED', 'ログインが必要です。'],
    ['approve', 'FORBIDDEN', '操作できません。'],
    ['reject', 'UNAUTHORIZED', 'ログインが必要です。'],
    ['reject', 'FORBIDDEN', '操作できません。'],
    ['approve', 'SERVER_ERROR', '処理に失敗しました。'],
    ['reject', 'SERVER_ERROR', '処理に失敗しました。'],
  ] as const)('TC-APR-010 RT-APR-UI-004 displays safe %s error behavior for %s responses', async (operation, code, message) => {
    const onUnauthorized = vi.fn();
    const { calls } = installFrontendFetch({
      reportDetails: { 'R-PENDING-001': respondJson(buildReportDetail('R-PENDING-001', { approvalStatus: 'PENDING' })) },
      [operation]: rejectWith({ code, message }),
    });

    await renderUi(<DailyReportDetail user={managerUser} reportId="R-PENDING-001" onUnauthorized={onUnauthorized} />);
    if (operation === 'approve') {
      await click(buttonByText('承認する'));
      await click(buttonByText('承認を確定'));
    } else {
      await click(buttonByText('差し戻しする'));
      setControlValue(document.querySelector('textarea')!, '確認してください。');
      await click(buttonByText('差し戻しを確定'));
    }

    expect(document.querySelector('[role="alert"]')?.textContent).toBe(message);
    expect(countRequests(calls, 'POST', `/api/daily-reports/R-PENDING-001/${operation}`)).toBe(1);
    expect(document.body.textContent).not.toContain('承認する');
    expect(onUnauthorized).toHaveBeenCalledTimes(code === 'UNAUTHORIZED' ? 1 : 0);
  });

  it('TC-APR-010 RT-APR-UI-004 refreshes stale detail after a rejection status conflict', async () => {
    installFrontendFetch({
      reject: rejectWith({ code: 'INVALID_STATUS', message: '日報はすでに処理されています。' }),
      reportDetails: {
        'R-PENDING-001': (callCount) => respondJson(buildReportDetail('R-PENDING-001', {
          approvalStatus: callCount === 1 ? 'PENDING' : 'APPROVED',
        })),
      },
    });

    await renderUi(<DailyReportDetail user={managerUser} reportId="R-PENDING-001" />);
    await click(buttonByText('差し戻しする'));
    setControlValue(document.querySelector('textarea')!, '確認してください。');
    await click(buttonByText('差し戻しを確定'));

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('日報はすでに処理されています。');
    expect(document.body.textContent).toContain('承認済み');
    expect(document.body.textContent).not.toContain('差し戻しする');
  });

  it('TC-APR-003 TC-APR-010 RT-APR-UI-004 disables approval actions while the mutation is loading', async () => {
    let resolveApproval!: (response: Response) => void;
    const approval = new Promise<Response>((resolve) => {
      resolveApproval = resolve;
    });
    const { calls } = installFrontendFetch({
      approve: approval,
      reportDetails: { 'R-PENDING-001': respondJson(buildReportDetail('R-PENDING-001', { approvalStatus: 'PENDING' })) },
    });

    await renderUi(<DailyReportDetail user={managerUser} reportId="R-PENDING-001" />);
    await click(buttonByText('承認する'));
    const confirm = buttonByText('承認を確定');
    await act(async () => {
      confirm.dispatchEvent(new MouseEvent('click', { bubbles: true }));
      confirm.dispatchEvent(new MouseEvent('click', { bubbles: true }));
      await Promise.resolve();
    });
    await flushEffects();

    expect(buttonByText('承認する').disabled).toBe(true);
    expect(buttonByText('差し戻しする').disabled).toBe(true);
    expect(countRequests(calls, 'POST', '/api/daily-reports/R-PENDING-001/approve')).toBe(1);
    resolveApproval(new Response(JSON.stringify({
      reportId: 'R-PENDING-001',
      approvalStatus: 'APPROVED',
      approverId: 'M001',
      approverName: '佐藤 上長',
      approvedAt: '2026-07-17T09:00:00+09:00',
    }), { headers: { 'Content-Type': 'application/json' } }));
    await flushEffects();
  });

  it('TC-APR-010 RT-APR-UI-004 disables background actions while a rejection dialog is open and traps keyboard focus', async () => {
    installFrontendFetch({
      reportDetails: { 'R-PENDING-001': respondJson(buildReportDetail('R-PENDING-001', { approvalStatus: 'PENDING' })) },
    });

    await renderUi(<DailyReportDetail user={managerUser} reportId="R-PENDING-001" />);
    const rejectTrigger = buttonByText('差し戻しする');
    await click(rejectTrigger);

    const textarea = document.querySelector('textarea')!;
    const dialog = document.querySelector('[role="dialog"]')!;
    const cancel = buttonByText('キャンセル');
    expect(document.activeElement).toBe(textarea);
    expect(buttonByText('承認する').disabled).toBe(true);

    cancel.focus();
    await keyDown(dialog, 'Tab');
    expect(document.activeElement).toBe(textarea);
    textarea.focus();
    await keyDown(dialog, 'Tab', { shiftKey: true });
    expect(document.activeElement).toBe(cancel);

    await keyDown(dialog, 'Escape');
    expect(document.querySelector('[role="dialog"]')).toBeNull();
    expect(document.activeElement).toBe(rejectTrigger);

    await click(rejectTrigger);
    await click(buttonByText('キャンセル'));
    expect(document.querySelector('[role="dialog"]')).toBeNull();
    expect(document.activeElement).toBe(rejectTrigger);
  });
});
