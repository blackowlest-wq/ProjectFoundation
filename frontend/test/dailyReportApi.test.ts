import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  createDailyReport,
  approveDailyReport,
  fetchPendingApprovals,
  fetchDailyReport,
  fetchHolidayTypes,
  fetchProjects,
  fetchWorkCategories,
  resubmitDailyReport,
  rejectDailyReport,
  submitDailyReport,
  updateDailyReport,
} from '../src/dailyReport/dailyReportApi';
import type { DailyReportListItem, DailyReportRequest, DailyReportResponse } from '../src/dailyReport/types';
import type { PendingApprovalCriteria } from '../src/dailyReport/dailyReportApproval';

const request: DailyReportRequest = {
  reportDate: '2026-06-01',
  holidayType: 'WORKDAY',
  startTime: '09:00',
  endTime: '18:00',
  remarks: 'memo',
  workItems: [{ projectId: 'P001', workCategoryId: 'WC001', workMinutes: 480 }],
};

const nullAuditDetailFields: Pick<DailyReportResponse, 'submittedAt' | 'approverId' | 'approverName' | 'approvedAt' | 'rejectorId' | 'rejectorName' | 'rejectedAt' | 'rejectComment'> = {
  submittedAt: null,
  approverId: null,
  approverName: null,
  approvedAt: null,
  rejectorId: null,
  rejectorName: null,
  rejectedAt: null,
  rejectComment: null,
};

const nullAuditListFields: Pick<DailyReportListItem, 'approverId' | 'approverName' | 'approvedAt'> = {
  approverId: null,
  approverName: null,
  approvedAt: null,
};

describe('dailyReportApi', () => {
  afterEach(() => {
    vi.restoreAllMocks();
    document.cookie = 'XSRF-TOKEN=; Max-Age=0';
  });

  it('accepts null-valued audit fields in detail and list response fixtures', () => {
    expect(nullAuditDetailFields).toMatchObject({
      submittedAt: null,
      approverId: null,
      approverName: null,
      approvedAt: null,
      rejectorId: null,
      rejectorName: null,
      rejectedAt: null,
      rejectComment: null,
    });
    expect(nullAuditListFields).toEqual({ approverId: null, approverName: null, approvedAt: null });
  });

  it('creates daily reports with csrf header and credentials', async () => {
    document.cookie = 'XSRF-TOKEN=token-1';
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({
      reportId: 'R001',
      approvalStatus: 'DRAFT',
    }), { status: 201 }));

    await expect(createDailyReport(request)).resolves.toEqual({ reportId: 'R001', approvalStatus: 'DRAFT' });
    expect(fetchMock).toHaveBeenCalledWith('/api/daily-reports', expect.objectContaining({
      method: 'POST',
      credentials: 'include',
      headers: expect.objectContaining({ 'X-XSRF-TOKEN': 'token-1' }),
      body: JSON.stringify(request),
    }));
  });

  it('updates and submits by report id', async () => {
    document.cookie = 'XSRF-TOKEN=token-2';
    const fetchMock = vi.spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(new Response(JSON.stringify({ reportId: 'R001', approvalStatus: 'DRAFT' }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ reportId: 'R001', approvalStatus: 'PENDING' }), { status: 200 }));

    await updateDailyReport('R001', request);
    await submitDailyReport('R001');

    expect(fetchMock).toHaveBeenNthCalledWith(1, '/api/daily-reports/R001', expect.objectContaining({ method: 'PUT' }));
    expect(fetchMock).toHaveBeenNthCalledWith(2, '/api/daily-reports/R001/submit', expect.objectContaining({
      method: 'POST',
      headers: { 'X-XSRF-TOKEN': 'token-2' },
    }));
  });

  it('resubmits rejected reports by report id', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response(JSON.stringify({ reportId: 'R001', approvalStatus: 'PENDING' }), { status: 200 }));

    await expect(resubmitDailyReport('R001')).resolves.toEqual({ reportId: 'R001', approvalStatus: 'PENDING' });

    expect(fetchMock).toHaveBeenCalledWith('/api/daily-reports/R001/resubmit', expect.objectContaining({
      method: 'POST',
      credentials: 'include',
    }));
  });

  it('approves a report with a bodyless csrf POST', async () => {
    document.cookie = 'XSRF-TOKEN=approval-token';
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({
      reportId: 'R/001',
      approvalStatus: 'APPROVED',
      approverId: 'U002',
      approverName: '佐藤 上長',
      approvedAt: '2026-07-02T09:00:00+09:00',
    }), { status: 200 }));

    await expect(approveDailyReport('R/001')).resolves.toMatchObject({ approvalStatus: 'APPROVED' });
    expect(fetchMock).toHaveBeenCalledWith('/api/daily-reports/R%2F001/approve', expect.objectContaining({
      method: 'POST',
      credentials: 'include',
      headers: { 'X-XSRF-TOKEN': 'approval-token' },
    }));
  });

  it('rejects a report with a csrf JSON POST', async () => {
    document.cookie = 'XSRF-TOKEN=reject-token';
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({
      reportId: 'R001',
      approvalStatus: 'REJECTED',
      rejectorId: 'U002',
      rejectorName: '佐藤 上長',
      rejectedAt: '2026-07-02T09:00:00+09:00',
      rejectComment: '確認してください。',
    }), { status: 200 }));
    const rejectComment = '  確認してください。  ';

    await expect(rejectDailyReport('R001', rejectComment)).resolves.toMatchObject({ approvalStatus: 'REJECTED' });
    expect(fetchMock).toHaveBeenCalledWith('/api/daily-reports/R001/reject', expect.objectContaining({
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json', 'X-XSRF-TOKEN': 'reject-token' },
      body: JSON.stringify({ rejectComment }),
    }));
  });

  it('fetches pending approvals with date, group, and employee query parameters', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('[]', { status: 200 }));
    const criteria: PendingApprovalCriteria = {
      targetMonth: '2026-07',
      dateFrom: '2026-07-01',
      dateTo: '2026-07-31',
      groupId: 'G/001',
      employeeId: 'E 001',
    };

    await expect(fetchPendingApprovals(criteria)).resolves.toEqual([]);
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/daily-reports/pending-approvals?dateFrom=2026-07-01&dateTo=2026-07-31&groupId=G%2F001&employeeId=E+001',
      { credentials: 'include' },
    );
  });

  it('propagates approve invalid-status ApiError without transforming it', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({
      code: 'INVALID_STATUS',
      message: '承認待ちの日報だけを承認できます。',
      details: [],
      requestId: 'req-approve-409',
    }), { status: 409 }));

    await expect(approveDailyReport('R001')).rejects.toEqual({
      code: 'INVALID_STATUS',
      message: '承認待ちの日報だけを承認できます。',
      details: [],
      requestId: 'req-approve-409',
    });
  });

  it('propagates reject validation ApiError without transforming it', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({
      code: 'VALIDATION_ERROR',
      message: '差し戻しコメントを入力してください。',
      details: [{ field: 'rejectComment', message: 'must not be blank' }],
      requestId: 'req-reject-400',
    }), { status: 400 }));

    await expect(rejectDailyReport('R001', '   ')).rejects.toEqual({
      code: 'VALIDATION_ERROR',
      message: '差し戻しコメントを入力してください。',
      details: [{ field: 'rejectComment', message: 'must not be blank' }],
      requestId: 'req-reject-400',
    });
  });

  it('propagates pending-approval forbidden ApiError without transforming it', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({
      code: 'FORBIDDEN',
      message: '未承認一覧を参照する権限がありません。',
      details: [],
      requestId: 'req-pending-403',
    }), { status: 403 }));
    const criteria: PendingApprovalCriteria = {
      targetMonth: '2026-07',
      dateFrom: '2026-07-01',
      dateTo: '2026-07-31',
      groupId: '',
      employeeId: '',
    };

    await expect(fetchPendingApprovals(criteria)).rejects.toEqual({
      code: 'FORBIDDEN',
      message: '未承認一覧を参照する権限がありません。',
      details: [],
      requestId: 'req-pending-403',
    });
  });

  it('fetches master data with credentials', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(new Response(JSON.stringify([{ projectId: 'P001', projectName: 'プロジェクトA' }]), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify([{ workCategoryId: 'WC001', workCategoryName: '実装' }]), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify([{ holidayType: 'WORKDAY', holidayTypeName: '通常勤務' }]), { status: 200 }));

    await expect(fetchProjects()).resolves.toHaveLength(1);
    await expect(fetchWorkCategories()).resolves.toHaveLength(1);
    await expect(fetchHolidayTypes()).resolves.toHaveLength(1);

    expect(fetchMock).toHaveBeenNthCalledWith(1, '/api/master/projects', { credentials: 'include' });
    expect(fetchMock).toHaveBeenNthCalledWith(2, '/api/master/work-categories', { credentials: 'include' });
    expect(fetchMock).toHaveBeenNthCalledWith(3, '/api/master/holiday-types', { credentials: 'include' });
  });

  it('throws api errors', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({
      code: 'VALIDATION_ERROR',
      message: '入力内容が不正です。',
      details: [],
    }), { status: 400 }));

    await expect(fetchDailyReport('missing')).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });
  });
});
