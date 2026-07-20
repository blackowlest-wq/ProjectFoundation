/**
 * 承認画面で共有する入力検証と検索条件生成。
 * API呼び出しは持たず、UIが送信可否と当月の検索範囲を決めるための純粋ロジックだけを公開する。
 */
import { currentMonth, monthRange } from './dailyReportSearch';

export type PendingApprovalCriteria = {
  targetMonth: string;
  dateFrom: string;
  dateTo: string;
  groupId: string;
  employeeId: string;
};

/** 差し戻しコメントを画面で検証し、送信可能なら空文字を返す。 */
export function validateRejectComment(rejectComment: string): string {
  const trimmedComment = rejectComment.trim();
  // How: 前後空白を除いた値が空なら、文字数上限の判定より先に必須エラーを返す。
  if (!trimmedComment) {
    return '差し戻しコメントを入力してください。';
  }
  // How: trim後の文字数だけを画面で補助検証し、最終的な受理判定はバックエンドへ委譲する。
  if (trimmedComment.length > 1000) {
    return '差し戻しコメントは1000文字以内で入力してください。';
  }
  return '';
}

/** 現在月の月初・月末を使った未承認一覧の初期条件を生成する。 */
export function pendingApprovalCriteria(): PendingApprovalCriteria {
  const targetMonth = currentMonth();
  return {
    targetMonth,
    ...monthRange(targetMonth),
    groupId: '',
    employeeId: '',
  };
}

/** 未承認一覧の条件をAPIのクエリ文字列へ変換する。 */
export function buildPendingApprovalUrl(criteria: PendingApprovalCriteria): string {
  const params = new URLSearchParams();
  params.set('dateFrom', criteria.dateFrom);
  params.set('dateTo', criteria.dateTo);
  // How: 任意条件は値がある場合だけ追加し、URLSearchParamsにエンコードを委譲する。
  if (criteria.groupId) {
    params.set('groupId', criteria.groupId);
  }
  if (criteria.employeeId) {
    params.set('employeeId', criteria.employeeId);
  }
  return `/api/daily-reports/pending-approvals?${params.toString()}`;
}
