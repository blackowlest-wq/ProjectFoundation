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

/** 日付文字列の形式と実在日付を検証する。 */
function isValidDateText(value: string): boolean {
  // How: 日付書式が不正ならDate生成を行わず、日付不正として返す。
  if (!datePattern.test(value)) {
    return false;
  }
  const date = new Date(`${value}T00:00:00`);
  return !Number.isNaN(date.getTime()) && value === `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

/** 対象年月から月初・月末の日付範囲を生成し、不正値は空範囲で返す。 */
export function monthRange(targetMonth: string): { dateFrom: string; dateTo: string } {
  // How: 年月書式が不正なら範囲計算を行わず空範囲を返す。
  if (!targetMonthPattern.test(targetMonth)) {
    return { dateFrom: '', dateTo: '' };
  }
  const [yearText, monthText] = targetMonth.split('-');
  const year = Number(yearText);
  const month = Number(monthText);
  // How: 月が1から12の範囲外なら存在しない月として空範囲を返す。
  if (month < 1 || month > 12) {
    return { dateFrom: '', dateTo: '' };
  }
  const lastDay = new Date(year, month, 0).getDate();
  return {
    dateFrom: `${targetMonth}-01`,
    dateTo: `${targetMonth}-${String(lastDay).padStart(2, '0')}`,
  };
}

/** 実行環境の現在年月をYYYY-MM形式で返す。 */
export function currentMonth(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
}

/** 現在月を対象に、一覧画面の初期検索条件を生成する。 */
export function initialSearchCriteria(): DailyReportSearchCriteria {
  const targetMonth = currentMonth();
  return { targetMonth, ...monthRange(targetMonth), status: '', holidayType: '' };
}

/** 日報検索に必要な日付範囲と開始・終了順を検証する。 */
export function validateDailyReportSearch(criteria: DailyReportSearchCriteria): string | null {
  // How: 開始日または終了日がない場合は日付形式や順序を検証せず、必須エラーを返す。
  if (!criteria.dateFrom || !criteria.dateTo) {
    return '対象期間を指定してください。';
  }
  // How: 両日付の形式または実在性が不正なら、日付順の比較へ進めない。
  if (!isValidDateText(criteria.dateFrom) || !isValidDateText(criteria.dateTo)) {
    return '対象期間の日付形式が正しくありません。';
  }
  // How: 両日付が正しい場合だけ開始日と終了日を比較し、逆順をエラーにする。
  if (criteria.dateFrom > criteria.dateTo) {
    return '検索終了日は検索開始日以降にしてください。';
  }
  return null;
}

/** 検索条件を空条件を除外したAPIクエリ文字列へ変換する。 */
export function buildDailyReportSearchUrl(criteria: DailyReportSearchCriteria): string {
  const params = new URLSearchParams();
  params.set('dateFrom', criteria.dateFrom);
  params.set('dateTo', criteria.dateTo);
  // How: 任意条件は値がある場合だけクエリへ追加し、未指定条件をAPIへ送らない。
  if (criteria.groupId) {
    params.set('groupId', criteria.groupId);
  }
  // How: 社員IDがある場合だけ社員絞り込み条件を追加する。
  if (criteria.employeeId) {
    params.set('employeeId', criteria.employeeId);
  }
  // How: 承認状態が選択されている場合だけ状態条件を追加する。
  if (criteria.status) {
    params.set('status', criteria.status);
  }
  // How: 休日区分が選択されている場合だけ区分条件を追加する。
  if (criteria.holidayType) {
    params.set('holidayType', criteria.holidayType);
  }
  return `/api/daily-reports?${params.toString()}`;
}
