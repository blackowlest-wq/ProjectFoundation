import { describe, expect, it } from 'vitest';
import { formatDateTime } from '../src/dailyReport/dateTimeFormat';

describe('formatDateTime', () => {
  it('formats an ISO datetime without changing the source offset time', () => {
    expect(formatDateTime('2026-07-17T09:00:00+09:00')).toBe('2026-07-17 09:00:00');
  });

  it('removes milliseconds and renders missing values as a dash', () => {
    expect(formatDateTime('2026-07-17T09:00:00.123+09:00')).toBe('2026-07-17 09:00:00');
    expect(formatDateTime(null)).toBe('-');
    expect(formatDateTime('')).toBe('-');
  });

  it('preserves an unexpected non-empty value for diagnosis', () => {
    expect(formatDateTime('not-a-datetime')).toBe('not-a-datetime');
  });
});
