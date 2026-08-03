import { describe, expect, it } from 'vitest';
import { totalWorkItemMinutes, validateDailyReportInput } from '../src/dailyReport/dailyReportValidation';
import type { DailyReportRequest, HolidayTypeOption } from '../src/dailyReport/types';

const holidayOptions: HolidayTypeOption[] = [
  { holidayType: 'WORKDAY', holidayTypeName: '通常勤務', requiresWorkTime: true, allowsWorkItems: true },
  { holidayType: 'HOLIDAY', holidayTypeName: '休日', requiresWorkTime: false, allowsWorkItems: true },
  { holidayType: 'PAID_LEAVE', holidayTypeName: '有給休暇', requiresWorkTime: false, allowsWorkItems: false },
];

function base(overrides: Partial<DailyReportRequest> = {}): DailyReportRequest {
  return {
    reportDate: '2026-06-01',
    holidayType: 'WORKDAY',
    startTime: '09:00',
    endTime: '18:00',
    remarks: '',
    workItems: [{ projectId: 'P001', workCategoryId: 'WC001', workMinutes: 480 }],
    ...overrides,
  };
}

function validate(request: DailyReportRequest): string | null {
  return validateDailyReportInput(request, holidayOptions.find((option) => option.holidayType === request.holidayType));
}

describe('daily report validation', () => {
  it('accepts a workday report with time and work items', () => {
    expect(validate(base())).toBeNull();
  });

  it('rejects invalid time order', () => {
    expect(validate(base({ endTime: '09:00' }))).toBe('勤務終了時刻は勤務開始時刻より後にしてください。');
  });

  it('rejects missing required fields and invalid time format', () => {
    expect(validate(base({ reportDate: '' }))).toBe('日付を入力してください。');
    expect(validate(base({ holidayType: '' as DailyReportRequest['holidayType'] }))).toBe('休日区分を選択してください。');
    expect(validate(base({ startTime: null }))).toBe('勤務時刻と1件以上の作業明細を入力してください。');
    expect(validate(base({ startTime: '24:00' }))).toBe('時刻はHH:mm形式で入力してください。');
  });

  it('accepts holiday without work items and rejects times on it', () => {
    expect(validate(base({ holidayType: 'HOLIDAY', startTime: null, endTime: null, workItems: [] }))).toBeNull();
    expect(validate(base({ holidayType: 'HOLIDAY', workItems: [] }))).toBe('休日で作業明細がない場合、勤務時刻は入力できません。');
  });

  it('rejects paid leave with work input', () => {
    expect(validate(base({ holidayType: 'PAID_LEAVE' }))).toBe('有給休暇では勤務時刻と作業明細を入力できません。');
    expect(validate(base({ holidayType: 'PAID_LEAVE', startTime: null, endTime: null, workItems: [] }))).toBeNull();
  });

  it('rejects zero or negative work minutes', () => {
    expect(validate(base({
      workItems: [{ projectId: 'P001', workCategoryId: 'WC001', workMinutes: 0 }],
    }))).toBe('作業時間は1分以上で入力してください。');
  });

  it('sums work item minutes', () => {
    expect(totalWorkItemMinutes(base({
      workItems: [
        { projectId: 'P001', workCategoryId: 'WC001', workMinutes: 120 },
        { projectId: 'P002', workCategoryId: 'WC002', workMinutes: 60 },
      ],
    }))).toBe(180);
  });
});
