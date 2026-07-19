import { useEffect, useState } from 'react';
import type { CurrentUser } from '../auth/types';
import type { ApiError } from '../shared/apiClient';
import { approveDailyReport, fetchDailyReport, rejectDailyReport } from './dailyReportApi';
import { validateRejectComment } from './dailyReportApproval';
import type { ApprovalStatus, DailyReportResponse } from './types';

const statusLabelByStatus: Record<ApprovalStatus, string> = {
  DRAFT: '下書き',
  PENDING: '承認待ち',
  REJECTED: '差戻し',
  APPROVED: '承認済み',
};

/** APIエラーから詳細画面向けの表示文言を返す。 */
function readErrorMessage(error: unknown) {
  return (error as Partial<ApiError>).message ?? '日報の読み込みに失敗しました。';
}

/** 分数を作業明細向けのH:mm形式へ変換する。 */
function formatMinutes(minutes: number) {
  return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, '0')}`;
}

/** 日報の内容と監査情報を表示し、担当上長だけに状態変更操作を提供する。 */
export function DailyReportDetail({
  user,
  reportId,
  onUnauthorized,
}: {
  user: CurrentUser;
  reportId: string;
  onUnauthorized?: () => void;
}) {
  const [report, setReport] = useState<DailyReportResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [operating, setOperating] = useState(false);
  const [actionsAvailable, setActionsAvailable] = useState(true);
  const [error, setError] = useState('');
  const [dialogOpen, setDialogOpen] = useState(false);
  const [rejectComment, setRejectComment] = useState('');
  const [dialogError, setDialogError] = useState('');

  useEffect(() => {
    let active = true;
    setReport(null);
    setLoading(true);
    setError('');
    setActionsAvailable(true);
    fetchDailyReport(reportId)
      .then((result) => {
        if (active) {
          setReport(result);
        }
      })
      .catch((fetchError) => {
        if (!active) {
          return;
        }
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
  }, [onUnauthorized, reportId]);

  /** 状態変更後または競合時に、サーバーの最新詳細を再取得する。 */
  async function refreshReport() {
    setLoading(true);
    try {
      setReport(await fetchDailyReport(reportId));
    } catch (fetchError) {
      setActionsAvailable(false);
      if ((fetchError as Partial<ApiError>).code === 'UNAUTHORIZED') {
        onUnauthorized?.();
        return;
      }
      setError(readErrorMessage(fetchError));
    } finally {
      setLoading(false);
    }
  }

  /** 承認APIを呼び、成功レスポンスの監査情報を現在の詳細へ反映する。 */
  async function approve() {
    setOperating(true);
    setError('');
    try {
      const result = await approveDailyReport(reportId);
      setReport((current) => current && {
        ...current,
        approvalStatus: result.approvalStatus,
        approverId: result.approverId,
        approverName: result.approverName,
        approvedAt: result.approvedAt,
      });
    } catch (approveError) {
      setActionsAvailable(false);
      setError(readErrorMessage(approveError));
      if ((approveError as Partial<ApiError>).code === 'UNAUTHORIZED') {
        onUnauthorized?.();
      }
      if ((approveError as Partial<ApiError>).code === 'INVALID_STATUS') {
        await refreshReport();
      }
    } finally {
      setOperating(false);
    }
  }

  /** 差し戻しコメントを検証してからAPIを呼び、成功時は最新詳細を再取得する。 */
  async function reject() {
    const validationError = validateRejectComment(rejectComment);
    if (validationError) {
      setDialogError(validationError);
      return;
    }

    setOperating(true);
    setDialogError('');
    setError('');
    try {
      await rejectDailyReport(reportId, rejectComment);
      setDialogOpen(false);
      setRejectComment('');
      await refreshReport();
    } catch (rejectError) {
      setActionsAvailable(false);
      setDialogOpen(false);
      setError(readErrorMessage(rejectError));
      if ((rejectError as Partial<ApiError>).code === 'UNAUTHORIZED') {
        onUnauthorized?.();
      }
      if ((rejectError as Partial<ApiError>).code === 'INVALID_STATUS') {
        await refreshReport();
      }
    } finally {
      setOperating(false);
    }
  }

  const canChangeStatus = user.role === 'MANAGER'
    && report?.approvalStatus === 'PENDING'
    && actionsAvailable;

  return (
    <section className="report-panel" aria-labelledby="daily-report-detail-heading">
      <div className="section-heading">
        <h2 id="daily-report-detail-heading">日報詳細</h2>
        {loading && <span className="hint" role="status">読み込み中...</span>}
      </div>
      {error && <p className="error" role="alert">{error}</p>}
      {!loading && report && (
        <>
          <div className="detail-heading">
            <div>
              <p className="eyebrow">{report.reportId}</p>
              <h3>{report.employeeName}の日報</h3>
            </div>
            <span className={`status-pill status-${report.approvalStatus.toLowerCase()}`}>{statusLabelByStatus[report.approvalStatus]}</span>
          </div>
          <dl className="detail-grid">
            <div><dt>日付</dt><dd>{report.reportDate}</dd></div>
            <div><dt>グループ</dt><dd>{report.groupName}</dd></div>
            <div><dt>休日区分</dt><dd>{report.holidayType}</dd></div>
            <div><dt>勤務時間</dt><dd>{report.workTimeDisplay}</dd></div>
            <div><dt>提出日時</dt><dd>{report.submittedAt ?? '-'}</dd></div>
            <div><dt>備考</dt><dd>{report.remarks ?? '-'}</dd></div>
            <div><dt>承認者</dt><dd>{report.approverName ?? '-'}</dd></div>
            <div><dt>承認日時</dt><dd>{report.approvedAt ?? '-'}</dd></div>
            <div><dt>差戻し者</dt><dd>{report.rejectorName ?? '-'}</dd></div>
            <div><dt>差戻し日時</dt><dd>{report.rejectedAt ?? '-'}</dd></div>
            <div><dt>差戻しコメント</dt><dd>{report.rejectComment ?? '-'}</dd></div>
          </dl>
          <section className="work-item-panel" aria-labelledby="work-items-heading">
            <h3 id="work-items-heading">作業明細</h3>
            <div className="table-wrap">
              <table>
                <thead><tr><th>案件</th><th>作業分類</th><th>作業時間</th></tr></thead>
                <tbody>
                  {report.workItems.map((item) => (
                    <tr key={item.workItemId}><td>{item.projectName}</td><td>{item.workCategoryName}</td><td>{formatMinutes(item.workMinutes)}</td></tr>
                  ))}
                  {report.workItems.length === 0 && <tr><td colSpan={3}>作業明細はありません。</td></tr>}
                </tbody>
              </table>
            </div>
          </section>
          {canChangeStatus && (
            <div className="actions" aria-label="承認操作">
              <button type="button" onClick={() => void approve()} disabled={operating}>承認する</button>
              <button type="button" className="secondary" onClick={() => { setDialogError(''); setDialogOpen(true); }} disabled={operating}>差し戻しする</button>
            </div>
          )}
        </>
      )}
      {dialogOpen && (
        <div className="dialog-backdrop">
          <section className="dialog" role="dialog" aria-modal="true" aria-labelledby="reject-dialog-heading">
            <h3 id="reject-dialog-heading">日報を差し戻す</h3>
            <label>
              差し戻しコメント
              <textarea value={rejectComment} onChange={(event) => setRejectComment(event.target.value)} disabled={operating} />
            </label>
            {dialogError && <p className="error" role="alert">{dialogError}</p>}
            <div className="actions">
              <button type="button" onClick={() => void reject()} disabled={operating}>差し戻しを確定</button>
              <button type="button" className="secondary" onClick={() => setDialogOpen(false)} disabled={operating}>キャンセル</button>
            </div>
          </section>
        </div>
      )}
    </section>
  );
}
