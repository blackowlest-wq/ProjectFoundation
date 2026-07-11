import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  createDailyReport,
  fetchDailyReport,
  fetchHolidayTypes,
  fetchProjects,
  fetchWorkCategories,
  resubmitDailyReport,
  submitDailyReport,
  updateDailyReport,
} from '../src/dailyReport/dailyReportApi';
import type { DailyReportRequest } from '../src/dailyReport/types';

const request: DailyReportRequest = {
  reportDate: '2026-06-01',
  holidayType: 'WORKDAY',
  startTime: '09:00',
  endTime: '18:00',
  remarks: 'memo',
  workItems: [{ projectId: 'P001', workCategoryId: 'WC001', workMinutes: 480 }],
};

describe('dailyReportApi', () => {
  afterEach(() => {
    vi.restoreAllMocks();
    document.cookie = 'XSRF-TOKEN=; Max-Age=0';
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
