import { useCallback, useEffect, useState } from 'react';
import type { CurrentUser } from '../auth/types';
import type { ApiError } from '../shared/apiClient';
import { fetchPendingApprovals } from './dailyReportApi';
import { pendingApprovalCriteria } from './dailyReportApproval';
import { validateDailyReportSearch } from './dailyReportSearch';
import type { DailyReportListItem } from './types';

/** 未承認一覧取得時のAPIエラーを、画面に表示できる文言へ変換する。 */
function readErrorMessage(error: unknown) {
  return (error as Partial<ApiError>).message ?? '未承認一覧の取得に失敗しました。';
}

/** 分数を一覧表示用のH:mm形式へ変換する。 */
function formatMinutes(minutes: number) {
  return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, '0')}`;
}

/** 上長の担当範囲にある当月の承認待ち日報を表示する。 */
export function DailyReportPendingApprovalList({ user, onUnauthorized }: { user: CurrentUser; onUnauthorized?: () => void }) {
  const [criteria, setCriteria] = useState(() => pendingApprovalCriteria());
  const [reports, setReports] = useState<DailyReportListItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  /** 選択済みの期間・グループ・社員で未承認一覧を安全に再取得する。 */
  const runSearch = useCallback(async (currentCriteria = criteria) => {
    const validationError = validateDailyReportSearch(currentCriteria);
    if (validationError) {
      setError(validationError);
      return;
    }

    setLoading(true);
    setError('');
    try {
      setReports(await fetchPendingApprovals(currentCriteria));
    } catch (fetchError) {
      setReports([]);
      if ((fetchError as Partial<ApiError>).code === 'UNAUTHORIZED') {
        onUnauthorized?.();
        return;
      }
      setError(readErrorMessage(fetchError));
    } finally {
      setLoading(false);
    }
  }, [criteria, onUnauthorized]);

  useEffect(() => {
    if (user.role !== 'MANAGER') {
      return;
    }
    void runSearch(criteria);
    // 初期表示だけで取得し、条件入力中の自動通信は避ける。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user.role]);

  /** 指定条件だけを更新し、検索は利用者が明示的に実行する。 */
  function setField<K extends keyof typeof criteria>(key: K, value: (typeof criteria)[K]) {
    setCriteria((current) => ({ ...current, [key]: value }));
  }

  /** 条件を現在月に戻し、同じ初期条件で一覧を再取得する。 */
  function clearConditions() {
    const next = pendingApprovalCriteria();
    setCriteria(next);
    void runSearch(next);
  }

  // How: 社員・管理者には一覧自体をレンダリングせず、誤ってAPIを呼び出さない。
  if (user.role !== 'MANAGER') {
    return null;
  }

  return (
    <section className="report-panel" aria-labelledby="pending-approvals-heading">
      <div className="section-heading">
        <h2 id="pending-approvals-heading">未承認一覧</h2>
        {loading && <span className="hint" role="status">読み込み中...</span>}
      </div>
      <form
        className="form-grid"
        onSubmit={(event) => {
          event.preventDefault();
          void runSearch();
        }}
      >
        <label>
          検索開始日
          <input aria-label="検索開始日" type="date" value={criteria.dateFrom} onChange={(event) => setField('dateFrom', event.target.value)} disabled={loading} />
        </label>
        <label>
          検索終了日
          <input aria-label="検索終了日" type="date" value={criteria.dateTo} onChange={(event) => setField('dateTo', event.target.value)} disabled={loading} />
        </label>
        <label>
          グループID
          <input aria-label="グループID" value={criteria.groupId} onChange={(event) => setField('groupId', event.target.value)} disabled={loading} />
        </label>
        <label>
          社員ID
          <input aria-label="社員ID" value={criteria.employeeId} onChange={(event) => setField('employeeId', event.target.value)} disabled={loading} />
        </label>
        <div className="actions">
          <button type="submit" disabled={loading}>検索</button>
          <button type="button" className="secondary" onClick={clearConditions} disabled={loading}>条件クリア</button>
        </div>
      </form>
      {error && <p className="error" role="alert">{error}</p>}
      {!loading && !error && reports.length === 0 && <p className="hint">承認待ちの日報はありません。</p>}
      {!error && reports.length > 0 && (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>日報ID</th>
                <th>日付</th>
                <th>グループ</th>
                <th>社員名</th>
                <th>休日区分</th>
                <th>勤務時間</th>
                <th>作業時間合計</th>
                <th>提出日時</th>
                <th>操作</th>
              </tr>
            </thead>
            <tbody>
              {reports.map((report) => (
                <tr key={report.reportId}>
                  <td>{report.reportId}</td>
                  <td>{report.reportDate}</td>
                  <td>{report.groupName}</td>
                  <td>{report.employeeName}</td>
                  <td>{report.holidayType}</td>
                  <td>{report.workTimeDisplay}</td>
                  <td>{formatMinutes(report.totalWorkItemMinutes)}</td>
                  <td>{report.submittedAt ?? '-'}</td>
                  <td><a href={`/daily-reports/${encodeURIComponent(report.reportId)}`}>詳細</a></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
