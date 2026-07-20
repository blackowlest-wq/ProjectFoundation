import { useEffect, useRef, useState } from 'react';
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
  const [approvalDialogOpen, setApprovalDialogOpen] = useState(false);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [rejectComment, setRejectComment] = useState('');
  const [dialogError, setDialogError] = useState('');
  const approveTriggerRef = useRef<HTMLButtonElement | null>(null);
  const rejectTriggerRef = useRef<HTMLButtonElement | null>(null);
  const approveConfirmButtonRef = useRef<HTMLButtonElement | null>(null);
  const rejectTextareaRef = useRef<HTMLTextAreaElement | null>(null);
  const dialogRef = useRef<HTMLElement | null>(null);
  const approvalRequestInFlightRef = useRef(false);
  const restoreApprovalTriggerFocusRef = useRef(false);
  const restoreRejectTriggerFocusRef = useRef(false);

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

  useEffect(() => {
    if (approvalDialogOpen) {
      approveConfirmButtonRef.current?.focus();
      return;
    }
    if (dialogOpen) {
      rejectTextareaRef.current?.focus();
      return;
    }
    if (restoreApprovalTriggerFocusRef.current) {
      approveTriggerRef.current?.focus();
      restoreApprovalTriggerFocusRef.current = false;
    }
    if (restoreRejectTriggerFocusRef.current) {
      rejectTriggerRef.current?.focus();
      restoreRejectTriggerFocusRef.current = false;
    }
  }, [approvalDialogOpen, dialogOpen]);

  /** 承認確認ダイアログを閉じ、起動元の操作へキーボードフォーカスを戻す。 */
  function closeApprovalDialog() {
    restoreApprovalTriggerFocusRef.current = true;
    setApprovalDialogOpen(false);
  }

  /** 差し戻しダイアログを閉じ、起動元の操作へキーボードフォーカスを戻す。 */
  function closeRejectDialog() {
    restoreRejectTriggerFocusRef.current = true;
    setDialogError('');
    setDialogOpen(false);
  }

  /** モーダル内のフォーカスを循環させ、Escapeでは安全にキャンセルする。 */
  function handleDialogKeyDown(event: React.KeyboardEvent<HTMLElement>, closeDialog: () => void) {
    if (event.key === 'Escape' && !operating) {
      event.preventDefault();
      closeDialog();
      return;
    }
    if (event.key !== 'Tab') {
      return;
    }
    const focusable = Array.from(dialogRef.current?.querySelectorAll<HTMLElement>('textarea:not(:disabled), button:not(:disabled)') ?? []);
    if (focusable.length === 0) {
      event.preventDefault();
      return;
    }
    const first = focusable[0];
    const last = focusable.at(-1)!;
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

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

  /** 承認確認後にだけ承認APIを呼び、完了時は確認ダイアログを閉じる。 */
  async function confirmApprove() {
    if (approvalRequestInFlightRef.current) {
      return;
    }
    approvalRequestInFlightRef.current = true;
    try {
      await approve();
    } finally {
      approvalRequestInFlightRef.current = false;
      closeApprovalDialog();
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
      closeRejectDialog();
      setRejectComment('');
      await refreshReport();
    } catch (rejectError) {
      setActionsAvailable(false);
      closeRejectDialog();
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
  const modalOpen = approvalDialogOpen || dialogOpen;
  const canEdit = user.role === 'EMPLOYEE'
    && (report?.approvalStatus === 'DRAFT' || report?.approvalStatus === 'REJECTED');
  const returnPath = user.role === 'MANAGER' ? '/pending-approvals' : '/daily-reports';

  return (
    <section className="report-panel" aria-labelledby="daily-report-detail-heading">
      <div className="section-heading">
        <h2 id="daily-report-detail-heading">日報詳細</h2>
        {loading && <span className="hint" role="status">読み込み中...</span>}
      </div>
      {error && <p className="error" role="alert">{error}</p>}
      {!loading && report && (
        <div aria-hidden={modalOpen || undefined} inert={modalOpen}>
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
              <button
                type="button"
                onClick={(event) => {
                  approveTriggerRef.current = event.currentTarget;
                  setApprovalDialogOpen(true);
                }}
                disabled={operating || modalOpen}
              >承認する</button>
              <button
                type="button"
                className="secondary"
                onClick={(event) => {
                  rejectTriggerRef.current = event.currentTarget;
                  setDialogError('');
                  setDialogOpen(true);
                }}
                disabled={operating || modalOpen}
              >差し戻しする</button>
            </div>
          )}
          <div className="actions" aria-label="詳細画面の遷移">
            {canEdit && <a className="button-link" href={`/daily-reports/${encodeURIComponent(report.reportId)}/edit`}>編集する</a>}
            <a className="button-link secondary-link" href={returnPath}>一覧へ戻る</a>
          </div>
        </div>
      )}
      {approvalDialogOpen && (
        <div className="dialog-backdrop">
          <section ref={dialogRef} className="dialog" role="dialog" aria-modal="true" aria-labelledby="approve-dialog-heading" onKeyDown={(event) => handleDialogKeyDown(event, closeApprovalDialog)}>
            <h3 id="approve-dialog-heading">日報を承認しますか</h3>
            <p>承認すると、この日報は承認済みになり未承認一覧から外れます。</p>
            <div className="actions">
              <button ref={approveConfirmButtonRef} type="button" onClick={() => void confirmApprove()} disabled={operating}>承認を確定</button>
              <button type="button" className="secondary" onClick={closeApprovalDialog} disabled={operating}>キャンセル</button>
            </div>
          </section>
        </div>
      )}
      {dialogOpen && (
        <div className="dialog-backdrop">
          <section ref={dialogRef} className="dialog" role="dialog" aria-modal="true" aria-labelledby="reject-dialog-heading" onKeyDown={(event) => handleDialogKeyDown(event, closeRejectDialog)}>
            <h3 id="reject-dialog-heading">日報を差し戻す</h3>
            <label>
              差し戻しコメント
              <textarea ref={rejectTextareaRef} value={rejectComment} onChange={(event) => setRejectComment(event.target.value)} disabled={operating} required />
            </label>
            {dialogError && <p className="error" role="alert">{dialogError}</p>}
            <div className="actions">
              <button type="button" onClick={() => void reject()} disabled={operating}>差し戻しを確定</button>
              <button type="button" className="secondary" onClick={closeRejectDialog} disabled={operating}>キャンセル</button>
            </div>
          </section>
        </div>
      )}
    </section>
  );
}
