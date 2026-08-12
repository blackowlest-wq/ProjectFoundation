import { afterEach, describe, expect, it, vi } from 'vitest';
import { getMonthlySummary } from '../src/monthlySummary/monthlySummaryApi';
import type { MonthlySummaryResponse } from '../src/monthlySummary/types';

const response: MonthlySummaryResponse = {
  yearMonth: '2026-06',
  employeeWorkSummaries: [{ employeeId: 'E001', employeeName: '山田 太郎', totalWorkMinutes: 480 }],
  projectWorkSummaries: [{ projectId: 'P001', projectName: 'プロジェクトA', totalWorkMinutes: 480 }],
  categoryWorkSummaries: [{ workCategoryId: 'WC001', workCategoryName: '設計', totalWorkMinutes: 480 }],
  holidayTypeSummaries: [{ holidayType: 'WORKDAY', totalDays: 1 }],
};

describe('monthlySummaryApi', () => {
  afterEach(() => vi.restoreAllMocks());

  it('RT-F011-FE-001 gets a monthly summary with the session cookie and exact year-month query', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response(JSON.stringify(response), { status: 200 }));

    await expect(getMonthlySummary('2026-06')).resolves.toEqual(response);
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/monthly-summaries?yearMonth=2026-06',
      { credentials: 'include' },
    );
  });
});
