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

export async function fetchProjects(): Promise<ProjectOption[]> {
  return getJson<ProjectOption[]>('/api/master/projects');
}

export async function fetchWorkCategories(): Promise<WorkCategoryOption[]> {
  return getJson<WorkCategoryOption[]>('/api/master/work-categories');
}

export async function fetchHolidayTypes(): Promise<HolidayTypeOption[]> {
  return getJson<HolidayTypeOption[]>('/api/master/holiday-types');
}

export async function fetchDailyReport(reportId: string): Promise<DailyReportResponse> {
  return getJson<DailyReportResponse>(`/api/daily-reports/${encodeURIComponent(reportId)}`);
}

export async function searchDailyReports(criteria: DailyReportSearchCriteria): Promise<DailyReportListItem[]> {
  return getJson<DailyReportListItem[]>(buildDailyReportSearchUrl(criteria));
}

export async function createDailyReport(request: DailyReportRequest): Promise<DailyReportSummary> {
  return postJsonWithCsrf<DailyReportSummary>('/api/daily-reports', request);
}

export async function updateDailyReport(reportId: string, request: DailyReportRequest): Promise<DailyReportSummary> {
  return putJsonWithCsrf<DailyReportSummary>(`/api/daily-reports/${encodeURIComponent(reportId)}`, request);
}

export async function submitDailyReport(reportId: string): Promise<DailyReportSummary> {
  return postNoBodyWithCsrf<DailyReportSummary>(`/api/daily-reports/${encodeURIComponent(reportId)}/submit`);
}

export async function resubmitDailyReport(reportId: string): Promise<DailyReportSummary> {
  return postNoBodyWithCsrf<DailyReportSummary>(`/api/daily-reports/${encodeURIComponent(reportId)}/resubmit`);
}
