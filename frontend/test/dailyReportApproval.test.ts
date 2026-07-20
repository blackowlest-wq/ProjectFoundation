import { afterEach, describe, expect, it, vi } from 'vitest';
import { pendingApprovalCriteria, validateRejectComment } from '../src/dailyReport/dailyReportApproval';

describe('dailyReportApproval', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it('rejects blank and overlong rejection comments', () => {
    expect(validateRejectComment('   ')).toBe('差し戻しコメントを入力してください。');
    expect(validateRejectComment('a'.repeat(1001))).toBe('差し戻しコメントは1000文字以内で入力してください。');
    expect(validateRejectComment('確認してください。')).toBe('');
  });

  it('creates current-month pending approval criteria', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-17T09:00:00+09:00'));

    expect(pendingApprovalCriteria()).toEqual({
      targetMonth: '2026-07',
      dateFrom: '2026-07-01',
      dateTo: '2026-07-31',
      groupId: '',
      employeeId: '',
    });
  });
});
