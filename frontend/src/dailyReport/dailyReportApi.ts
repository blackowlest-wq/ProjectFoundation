/**
 * 日報登録・編集画面で使うAPIクライアント。
 * マスタ取得、日報の登録/更新/取得、提出/再提出を画面から呼びやすい関数にまとめる。
 */
import { getJson, postJsonWithCsrf, postNoBodyWithCsrf, putJsonWithCsrf } from '../shared/apiClient';
import type {
  DailyReportListItem,
  DailyReportRequest,
  DailyReportResponse,
  DailyReportSummary,
  HolidayTypeOption,
  ProjectOption,
  WorkCategoryOption,
} from './types';
import { buildDailyReportSearchUrl, type DailyReportSearchCriteria } from './dailyReportSearch';

/** 有効な案件マスタを取得する。 */
export async function fetchProjects(): Promise<ProjectOption[]> {
  return getJson<ProjectOption[]>('/api/master/projects');
}

/** 有効な作業分類マスタを取得する。 */
export async function fetchWorkCategories(): Promise<WorkCategoryOption[]> {
  return getJson<WorkCategoryOption[]>('/api/master/work-categories');
}

/** 休日区分と入力ルールのマスタを取得する。 */
export async function fetchHolidayTypes(): Promise<HolidayTypeOption[]> {
  return getJson<HolidayTypeOption[]>('/api/master/holiday-types');
}

/** 指定日報を取得し、編集・詳細表示用レスポンスを返す。 */
export async function fetchDailyReport(reportId: string): Promise<DailyReportResponse> {
  return getJson<DailyReportResponse>(`/api/daily-reports/${encodeURIComponent(reportId)}`);
}

/** 検索条件をURLへ変換して日報一覧を取得する。 */
export async function searchDailyReports(criteria: DailyReportSearchCriteria): Promise<DailyReportListItem[]> {
  return getJson<DailyReportListItem[]>(buildDailyReportSearchUrl(criteria));
}

/** CSRFヘッダー付きで日報を新規登録する。 */
export async function createDailyReport(request: DailyReportRequest): Promise<DailyReportSummary> {
  return postJsonWithCsrf<DailyReportSummary>('/api/daily-reports', request);
}

/** CSRFヘッダー付きで指定日報を更新する。 */
export async function updateDailyReport(reportId: string, request: DailyReportRequest): Promise<DailyReportSummary> {
  return putJsonWithCsrf<DailyReportSummary>(`/api/daily-reports/${encodeURIComponent(reportId)}`, request);
}

/** 下書き日報を提出し、承認待ち状態へ遷移させる。 */
export async function submitDailyReport(reportId: string): Promise<DailyReportSummary> {
  return postNoBodyWithCsrf<DailyReportSummary>(`/api/daily-reports/${encodeURIComponent(reportId)}/submit`);
}

/** 差戻し日報を再提出し、承認待ち状態へ遷移させる。 */
export async function resubmitDailyReport(reportId: string): Promise<DailyReportSummary> {
  return postNoBodyWithCsrf<DailyReportSummary>(`/api/daily-reports/${encodeURIComponent(reportId)}/resubmit`);
}
