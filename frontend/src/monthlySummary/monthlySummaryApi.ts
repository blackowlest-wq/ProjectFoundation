/** 月次集計APIのクライアント。 */
import { getJson } from '../shared/apiClient';
import type { MonthlySummaryResponse } from './types';

export async function getMonthlySummary(yearMonth: string): Promise<MonthlySummaryResponse> {
  const query = new URLSearchParams({ yearMonth });
  return getJson<MonthlySummaryResponse>(`/api/monthly-summaries?${query.toString()}`);
}
