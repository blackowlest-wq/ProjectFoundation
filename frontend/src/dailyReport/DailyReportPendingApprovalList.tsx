import { useEffect, useState } from 'react';
import type { CurrentUser } from '../auth/types';
import type { ApiError } from '../shared/apiClient';
import { fetchPendingApprovals } from './dailyReportApi';
import { pendingApprovalCriteria } from './dailyReportApproval';
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
  const [reports, setReports] = useState<DailyReportListItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    if (user.role !== 'MANAGER') {
      return;
    }

    let active = true;
    setLoading(true);
    setError('');
    fetchPendingApprovals(pendingApprovalCriteria())
      .then((result) => {
        if (active) {
          setReports(result);
        }
      })
      .catch((fetchError) => {
        if (!active) {
          return;
        }
        setReports([]);
        if ((fetchError as Partial<ApiError>).code === 'UNAUTHORIZED') {
          onUnauthorized?.();
          return;
        }
        setError(readErrorMessage(fetchError));
      })
      .finally(() => {
        if (active) {
          setLoading(false);
        }
      });

    return () => {
      active = false;
    };
  }, [onUnauthorized, user.role]);

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
