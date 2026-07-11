import { describe, expect, test } from 'vitest';
import {
  buildDailyReportSearchUrl,
  monthRange,
  validateDailyReportSearch,
} from './dailyReportSearch';

describe('daily report search helpers', () => {
  test('monthRange returns first and last day of selected month', () => {
    expect(monthRange('2026-02')).toEqual({ dateFrom: '2026-02-01', dateTo: '2026-02-28' });
    expect(monthRange('2024-02')).toEqual({ dateFrom: '2024-02-01', dateTo: '2024-02-29' });
  });

  test('monthRange returns empty range when selected month is invalid', () => {
    expect(monthRange('')).toEqual({ dateFrom: '', dateTo: '' });
    expect(monthRange('2026-13')).toEqual({ dateFrom: '', dateTo: '' });
  });

  test('validateDailyReportSearch rejects missing date range before API call', () => {
    expect(validateDailyReportSearch({ targetMonth: '2026-06', dateFrom: '', dateTo: '' }))
      .toBe('対象期間を指定してください。');
  });

  test('validateDailyReportSearch rejects invalid date text before API call', () => {
    expect(validateDailyReportSearch({ targetMonth: '2026-06', dateFrom: '2026-02-30', dateTo: '2026-06-01' }))
      .toBe('対象期間の日付形式が正しくありません。');
  });

  test('validateDailyReportSearch rejects inverted date range before API call', () => {
    expect(validateDailyReportSearch({ targetMonth: '2026-06', dateFrom: '2026-06-30', dateTo: '2026-06-01' }))
      .toBe('検索終了日は検索開始日以降にしてください。');
  });

  test('buildDailyReportSearchUrl includes required date range and optional filters', () => {
    expect(buildDailyReportSearchUrl({
      targetMonth: '2026-06',
      dateFrom: '2026-06-01',
      dateTo: '2026-06-30',
      employeeId: 'E001',
      status: 'PENDING',
      holidayType: 'WORKDAY',
    })).toBe('/api/daily-reports?dateFrom=2026-06-01&dateTo=2026-06-30&employeeId=E001&status=PENDING&holidayType=WORKDAY');
  });
});
