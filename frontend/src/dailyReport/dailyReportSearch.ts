import type { ApprovalStatus, HolidayType } from './types';

export type DailyReportSearchCriteria = {
  targetMonth: string;
  dateFrom: string;
  dateTo: string;
  employeeId?: string;
  groupId?: string;
  status?: ApprovalStatus | '';
  holidayType?: HolidayType | '';
};

const targetMonthPattern = /^\d{4}-\d{2}$/;
const datePattern = /^\d{4}-\d{2}-\d{2}$/;

function isValidDateText(value: string): boolean {
  if (!datePattern.test(value)) {
    return false;
  }
  const date = new Date(`${value}T00:00:00`);
  return !Number.isNaN(date.getTime()) && value === `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

export function monthRange(targetMonth: string): { dateFrom: string; dateTo: string } {
  if (!targetMonthPattern.test(targetMonth)) {
    return { dateFrom: '', dateTo: '' };
  }
  const [yearText, monthText] = targetMonth.split('-');
  const year = Number(yearText);
  const month = Number(monthText);
  if (month < 1 || month > 12) {
    return { dateFrom: '', dateTo: '' };
  }
  const lastDay = new Date(year, month, 0).getDate();
  return {
    dateFrom: `${targetMonth}-01`,
    dateTo: `${targetMonth}-${String(lastDay).padStart(2, '0')}`,
  };
}

export function currentMonth(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
}

export function initialSearchCriteria(): DailyReportSearchCriteria {
  const targetMonth = currentMonth();
  return { targetMonth, ...monthRange(targetMonth), status: '', holidayType: '' };
}

export function validateDailyReportSearch(criteria: DailyReportSearchCriteria): string | null {
  if (!criteria.dateFrom || !criteria.dateTo) {
    return '対象期間を指定してください。';
  }
  if (!isValidDateText(criteria.dateFrom) || !isValidDateText(criteria.dateTo)) {
    return '対象期間の日付形式が正しくありません。';
  }
  if (criteria.dateFrom > criteria.dateTo) {
    return '検索終了日は検索開始日以降にしてください。';
  }
  return null;
}

export function buildDailyReportSearchUrl(criteria: DailyReportSearchCriteria): string {
  const params = new URLSearchParams();
  params.set('dateFrom', criteria.dateFrom);
  params.set('dateTo', criteria.dateTo);
  if (criteria.groupId) {
    params.set('groupId', criteria.groupId);
  }
  if (criteria.employeeId) {
    params.set('employeeId', criteria.employeeId);
  }
  if (criteria.status) {
    params.set('status', criteria.status);
  }
  if (criteria.holidayType) {
    params.set('holidayType', criteria.holidayType);
  }
  return `/api/daily-reports?${params.toString()}`;
}
