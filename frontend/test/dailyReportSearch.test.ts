import { afterEach, describe, expect, test, vi } from 'vitest';
import {
  buildDailyReportSearchUrl,
  currentMonth,
  initialSearchCriteria,
  monthRange,
  validateDailyReportSearch,
} from '../src/dailyReport/dailyReportSearch';

describe('daily report search helpers', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

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

  test('validateDailyReportSearch rejects a date with an invalid text format', () => {
    expect(validateDailyReportSearch({ targetMonth: '2026-06', dateFrom: '2026-6-01', dateTo: '2026-06-30' }))
      .toBe('対象期間の日付形式が正しくありません。');
  });

  test('validateDailyReportSearch rejects inverted date range before API call', () => {
    expect(validateDailyReportSearch({ targetMonth: '2026-06', dateFrom: '2026-06-30', dateTo: '2026-06-01' }))
      .toBe('検索終了日は検索開始日以降にしてください。');
  });

  test('validateDailyReportSearch accepts a valid date range', () => {
    expect(validateDailyReportSearch({ targetMonth: '2026-06', dateFrom: '2026-06-01', dateTo: '2026-06-30' }))
      .toBeNull();
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

  test('buildDailyReportSearchUrl omits optional filters when they are empty', () => {
    expect(buildDailyReportSearchUrl({
      targetMonth: '2026-06', dateFrom: '2026-06-01', dateTo: '2026-06-30',
      employeeId: '', groupId: '', status: '', holidayType: '',
    })).toBe('/api/daily-reports?dateFrom=2026-06-01&dateTo=2026-06-30');
  });

  test('buildDailyReportSearchUrl includes the optional group filter', () => {
    expect(buildDailyReportSearchUrl({
      targetMonth: '2026-06', dateFrom: '2026-06-01', dateTo: '2026-06-30', groupId: 'G001',
    })).toBe('/api/daily-reports?dateFrom=2026-06-01&dateTo=2026-06-30&groupId=G001');
  });

  test('initialSearchCriteria uses the current month range', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-17T09:00:00+09:00'));

    expect(currentMonth()).toBe('2026-07');
    expect(initialSearchCriteria()).toEqual({
      targetMonth: '2026-07',
      dateFrom: '2026-07-01',
      dateTo: '2026-07-31',
      status: '',
      holidayType: '',
    });
  });
});
