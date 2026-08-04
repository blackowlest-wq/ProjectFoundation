/**
 * 日報登録・編集画面のメインコンポーネント。
 * マスタ読み込み、既存日報の編集、下書き保存、提出、作業明細編集を1画面で扱う。
 */
import { useEffect, useRef, useState } from 'react';
import {
  createDailyReport,
  fetchDailyReport,
  fetchHolidayTypes,
  fetchProjects,
  fetchWorkCategories,
  resubmitDailyReport,
  submitDailyReport,
  updateDailyReport,
} from './dailyReportApi';
import { validateDailyReportInput } from './dailyReportValidation';
import { formatDateTime } from './dateTimeFormat';
import type { CurrentUser } from '../auth/types';
import type { ApiError } from '../shared/apiClient';
import { resolveMessage, useMessage } from '../shared/messageCatalog';
import type {
  ApprovalStatus,
  DailyReportRequest,
  DailyReportResponse,
  DailyReportWorkItemInput,
  HolidayType,
  HolidayTypeOption,
  ProjectOption,
  WorkCategoryOption,
} from './types';

type DetailLoadState = 'idle' | 'loading' | 'loaded' | 'failed';
type RejectionDetails = Pick<DailyReportResponse, 'rejectComment' | 'rejectorName' | 'rejectedAt'>;

/** 実行環境の今日を日報入力用のYYYY-MM-DD形式で返す。 */
function today(): string {
  const current = new Date();
  // Why not: toISOString() converts the value to UTC and can return the previous date during the local midnight boundary.
  return `${current.getFullYear()}-${String(current.getMonth() + 1).padStart(2, '0')}-${String(current.getDate()).padStart(2, '0')}`;
}

/** 新規登録画面で使用する初期日報を生成する。 */
function emptyReport(): DailyReportRequest {
  return {
    reportDate: today(),
    holidayType: 'WORKDAY',
    startTime: '09:00',
    endTime: '18:00',
    remarks: '',
    workItems: [],
  };
}

/** 現在URLが編集画面形式なら、URLから日報IDを取り出す。 */
function reportIdFromPath(): string | null {
  const match = window.location.pathname.match(/^\/daily-reports\/([^/]+)\/edit$/);
  return match ? decodeURIComponent(match[1]) : null;
}

/** 編集中の作業明細の合計分数を返す。 */
function totalMinutes(items: DailyReportWorkItemInput[]): number {
  return items.reduce((total, item) => total + Number(item.workMinutes || 0), 0);
}

/** 分単位の勤務時間を画面表示用のH:mmへ変換する。 */
function formatDuration(minutes: number | null | undefined): string {
  if (minutes == null) {
    return '0:00';
  }
  return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, '0')}`;
}

/** 詳細APIレスポンスから、画面編集に必要な入力DTO部分だけを抽出する。 */
function toEditableReport(report: Awaited<ReturnType<typeof fetchDailyReport>>): DailyReportRequest {
  return {
    reportDate: report.reportDate,
    holidayType: report.holidayType,
    startTime: report.startTime,
    endTime: report.endTime,
    remarks: report.remarks,
    workItems: report.workItems.map((item) => ({
      projectId: item.projectId,
      workCategoryId: item.workCategoryId,
      workMinutes: item.workMinutes,
    })),
  };
}

/** 新規・編集日報のフォーム状態、マスタ取得、保存・提出操作を集約するカスタムフック。 */
function useDailyReportEditor() {
  const [reportId, setReportId] = useState<string | null>(() => reportIdFromPath());
  const [status, setStatus] = useState<ApprovalStatus>('DRAFT');
  const [detailLoadState, setDetailLoadState] = useState<DetailLoadState>(() => reportIdFromPath() ? 'loading' : 'idle');
  const [rejectionDetails, setRejectionDetails] = useState<RejectionDetails | null>(null);
  const [form, setForm] = useState<DailyReportRequest>(() => emptyReport());
  const [projects, setProjects] = useState<ProjectOption[]>([]);
  const [categories, setCategories] = useState<WorkCategoryOption[]>([]);
  const [holidayTypes, setHolidayTypes] = useState<HolidayTypeOption[]>([]);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const [calculation, setCalculation] = useState<DailyReportResponse | null>(null);
  const [saving, setSaving] = useState(false);
  const savingRef = useRef(false);
  const initialReportIdRef = useRef(reportId);

  /** 詳細APIの結果をフォーム、状態、計算結果へ反映する。 */
  function applyDetail(report: DailyReportResponse) {
    setStatus(report.approvalStatus);
    setRejectionDetails({
      rejectComment: report.rejectComment,
      rejectorName: report.rejectorName,
      rejectedAt: report.rejectedAt,
    });
    setForm(toEditableReport(report));
    setCalculation(report);
    setDetailLoadState('loaded');
  }

  useEffect(() => {
    // How: 3種類のマスタを並列取得し、完了後に各選択肢を同じフォーム状態へ設定する。
    // Why not: 入力行ごとにマスタを取得すると選択肢と通信回数が不安定になるため、画面表示時に一括取得して共有する。
    Promise.all([fetchProjects(), fetchWorkCategories(), fetchHolidayTypes()])
      .then(([projectOptions, categoryOptions, holidayOptions]) => {
        setProjects(projectOptions);
        setCategories(categoryOptions);
        setHolidayTypes(holidayOptions);
        if (!initialReportIdRef.current) {
          setForm((current) => {
            const holidayOption = holidayOptions.find((option) => option.holidayType === current.holidayType);
            if (current.workItems.length > 0 || !holidayOption?.allowsWorkItems || !projectOptions[0] || !categoryOptions[0]) {
              return current;
            }
            return {
              ...current,
              workItems: [{ projectId: projectOptions[0].projectId, workCategoryId: categoryOptions[0].workCategoryId, workMinutes: 480 }],
            };
          });
        }
      })
      .catch((e) => setError((e as ApiError).message ?? resolveMessage('error.master_load', 'マスタデータの読み込みに失敗しました。')));
  }, []);

  useEffect(() => {
    // How: 編集URLのreportIdがある場合だけ既存日報を取得して入力DTOへ変換し、新規URLは初期値を維持する。
    // How: 新規URLでは既存日報を取得せず、初期入力を維持したまま副作用を終了する。
    if (!reportId) {
      setDetailLoadState('idle');
      return;
    }
    setDetailLoadState('loading');
    fetchDailyReport(reportId)
      .then(applyDetail)
      .catch((e) => {
        setDetailLoadState('failed');
        setError((e as ApiError).message ?? resolveMessage('error.daily_report_load', '日報の読み込みに失敗しました。'));
      });
  }, [reportId]);

  const selectedHolidayType = holidayTypes.find((option) => option.holidayType === form.holidayType);
  const canEnterWorkTime = Boolean(selectedHolidayType)
    && (selectedHolidayType?.requiresWorkTime === true
      || (selectedHolidayType?.allowsWorkItems === true && form.workItems.length > 0));
  const mutationDisabled = saving || Boolean(reportId)
    && (detailLoadState === 'loading' || detailLoadState === 'failed' || status === 'PENDING' || status === 'APPROVED');
  const workItemsDisabled = mutationDisabled
    || !selectedHolidayType?.allowsWorkItems || projects.length === 0 || categories.length === 0;
  const workTimeDisabled = mutationDisabled || !canEnterWorkTime;

  /** 入力フォームの指定フィールドだけを更新する。 */
  function setField<K extends keyof DailyReportRequest>(key: K, value: DailyReportRequest[K]) {
    setCalculation(null);
    setForm((current) => ({ ...current, [key]: value }));
  }

  /** 休日区分マスタに応じて勤務入力と作業明細の状態を整合させる。 */
  function changeHolidayType(value: HolidayType) {
    const holidayOption = holidayTypes.find((option) => option.holidayType === value);
    setCalculation(null);
    setForm((current) => ({
      ...current,
      holidayType: value,
      startTime: holidayOption?.requiresWorkTime || (holidayOption?.allowsWorkItems && current.workItems.length > 0)
        ? current.startTime
        : null,
      endTime: holidayOption?.requiresWorkTime || (holidayOption?.allowsWorkItems && current.workItems.length > 0)
        ? current.endTime
        : null,
      workItems: holidayOption?.allowsWorkItems ? current.workItems : [],
    }));
  }

  /** 現在の入力を保存し、提出は行わない。 */
  async function saveDraft() {
    await save(false);
  }

  /** 現在の入力を保存した後、状態に応じた提出または再提出を行う。 */
  async function saveAndSubmit() {
    await save(true);
  }

  /** 入力検証後に登録・更新を選択し、必要なら提出まで実行する共通保存処理。 */
  async function save(thenSubmit: boolean) {
    // How: 既存詳細の未確定・取得失敗・編集不可状態では検証とAPI呼び出しの前に終了し、画面操作以外からの変更も防ぐ。
    // Why not: disabled属性だけに依存すると、イベント経由の呼び出しで状態不整合な更新要求を送れるため、保存処理でも同じ条件を確認する。
    if (mutationDisabled || savingRef.current) {
      return;
    }
    // How: 画面入力を検証し、reportIdの有無で登録/更新を選び、提出時は差戻しだけ再提出APIへ分岐する。
    setError('');
    setMessage('');
    const validationError = validateDailyReportInput(form, selectedHolidayType);
    // How: 入力エラーがあればAPI保存へ進まず、最初の検証結果を画面へ表示する。
    if (validationError) {
      setError(validationError);
      return;
    }
    savingRef.current = true;
    setSaving(true);
    try {
      const resubmit = status === 'REJECTED';
      const saved = reportId ? await updateDailyReport(reportId, form) : await createDailyReport(form);
      if (reportId) {
        setReportId(saved.reportId);
      }
      setStatus(saved.approvalStatus);
      if (reportId) {
        try {
          applyDetail(await fetchDailyReport(saved.reportId));
        } catch {
          setError(resolveMessage('error.calculation_reload', '保存は完了しましたが、計算結果の再取得に失敗しました。'));
        }
      }
      // How: 提出指定時だけ、保存開始前に判定した状態に応じて差戻しは再提出、それ以外は初回提出へ分岐する。
      if (thenSubmit) {
        // Why not: 差戻し日報を通常提出APIへ送ると状態遷移の入口を分けられないため、再提出APIへ限定する。
        const submitted = resubmit
          ? await resubmitDailyReport(saved.reportId)
          : await submitDailyReport(saved.reportId);
        setStatus(submitted.approvalStatus);
        setMessage(resolveMessage('success.saved_and_submitted', '保存して提出しました。'));
      } else {
        setMessage(resolveMessage('success.saved', '保存しました。'));
      }
      if (!reportId) {
        try {
          // Why not: 登録APIの概要レスポンスだけではBackend計算結果を表示できないため、新規登録でも詳細を再取得する。
          applyDetail(await fetchDailyReport(saved.reportId));
        } catch {
          setError(resolveMessage('error.calculation_reload', '保存は完了しましたが、計算結果の再取得に失敗しました。'));
        }
        setReportId(saved.reportId);
      }
      // Why not: 登録後に新規URLを残すと再読込時に新規作成として扱われるため、編集URLへ置き換える。
      window.history.replaceState(null, '', `/daily-reports/${encodeURIComponent(saved.reportId)}/edit`);
    } catch (e) {
      const apiError = e as ApiError;
      // Why not: API全体のメッセージだけを表示すると入力箇所を特定できないため、field別エラーを優先する。
      setError(apiError.details?.[0]?.message ?? apiError.message ?? resolveMessage('error.save_failed', '保存に失敗しました。'));
    } finally {
      savingRef.current = false;
      setSaving(false);
    }
  }

  /** マスタの先頭値を使って作業明細を末尾へ追加する。 */
  function addItem() {
    const project = projects[0];
    const category = categories[0];
    if (!project || !category) {
      setError(resolveMessage('error.master_not_ready', '案件と作業分類の読み込みが完了していません。'));
      return;
    }
    // How: 取得済みマスタの先頭値を使って明細を末尾へ追加する。
    // Why not: 未取得時に固定IDを作ると、利用者に見えない無効な入力を保存要求へ混入させるため、マスタがない場合は追加しない。
    setCalculation(null);
    setForm((current) => ({
      ...current,
      workItems: [
        ...current.workItems,
        {
          projectId: project.projectId,
          workCategoryId: category.workCategoryId,
          workMinutes: 60,
        },
      ],
    }));
  }

  /** 指定された作業明細だけを新しい入力値へ置き換える。 */
  function updateItem(index: number, item: DailyReportWorkItemInput) {
    setCalculation(null);
    setForm((current) => ({
      ...current,
      workItems: current.workItems.map((currentItem, itemIndex) => (itemIndex === index ? item : currentItem)),
    }));
  }

  /** 指定された作業明細をフォームから削除する。 */
  function deleteItem(index: number) {
    // Why not: 明細ごとの差分APIを持つと画面とバックエンドで削除状態がずれるため、保存時に入力配列を全差し替えする。
    setCalculation(null);
    setForm((current) => ({
      ...current,
      workItems: current.workItems.filter((_, itemIndex) => itemIndex !== index),
    }));
  }

  return {
    addItem,
    categories,
    changeHolidayType,
    deleteItem,
    error,
    form,
    holidayTypes,
    message,
    projects,
    rejectionDetails,
    reportId,
    saveAndSubmit,
    saveDraft,
    setField,
    status,
    mutationDisabled,
    calculation,
    saving,
    workItemsDisabled,
    workTimeDisabled,
    updateItem,
  };
}

/** 作業明細の選択・時間入力・追加・削除を表示する編集部品。 */
function WorkItemsEditor({
  categories,
  disabled,
  items,
  onAdd,
  onDelete,
  onUpdate,
  projects,
}: {
  categories: WorkCategoryOption[];
  disabled: boolean;
  items: DailyReportWorkItemInput[];
  onAdd: () => void;
  onDelete: (index: number) => void;
  onUpdate: (index: number, item: DailyReportWorkItemInput) => void;
  projects: ProjectOption[];
}) {
  return (
    <div className="work-items">
      <div className="section-heading">
        <h2>作業明細</h2>
        <button type="button" className="secondary" disabled={disabled} onClick={onAdd}>追加</button>
      </div>
      {items.map((item, index) => (
        <div className="work-row" key={index}>
          <select disabled={disabled} value={item.projectId} onChange={(event) => onUpdate(index, { ...item, projectId: event.target.value })}>
            {projects.map((project) => <option key={project.projectId} value={project.projectId}>{project.projectName}</option>)}
          </select>
          <select disabled={disabled} value={item.workCategoryId} onChange={(event) => onUpdate(index, { ...item, workCategoryId: event.target.value })}>
            {categories.map((category) => <option key={category.workCategoryId} value={category.workCategoryId}>{category.workCategoryName}</option>)}
          </select>
          <input
            type="number"
            min="1"
            disabled={disabled}
            value={item.workMinutes}
            onChange={(event) => onUpdate(index, { ...item, workMinutes: Number(event.target.value) })}
          />
          <button type="button" className="secondary" disabled={disabled} onClick={() => onDelete(index)}>削除</button>
        </div>
      ))}
      <p className="hint">合計: {totalMinutes(items)} 分</p>
    </div>
  );
}

/** 日報の登録・編集フォームを表示し、社員の入力・保存・提出を受け付ける。 */
export function DailyReportForm({ user }: { user: CurrentUser }) {
  const editor = useDailyReportEditor();
  const statusLabelByStatus: Record<ApprovalStatus, string> = {
    DRAFT: useMessage('status.draft_editor', '下書き'),
    PENDING: useMessage('status.pending', '承認待ち'),
    REJECTED: useMessage('status.rejected', '差戻し'),
    APPROVED: useMessage('status.approved', '承認済み'),
  };

  return (
    <section className="report-panel">
      <div className="section-heading">
        <div>
          <p className="eyebrow">日報</p>
          <h2>{editor.reportId ? '日報編集' : '日報登録'}</h2>
        </div>
        <span className="status-pill">{statusLabelByStatus[editor.status]}</span>
      </div>
      <div className="summary compact">
        <dl>
          <div><dt>利用者</dt><dd>{user.userName}</dd></div>
          <div><dt>所属</dt><dd>{user.groupName ?? '-'}</dd></div>
          <div><dt>休憩区分</dt><dd>{user.breakTypeName ?? '-'}</dd></div>
          <div><dt>勤務区分</dt><dd>{user.workTimeTypeName ?? '-'}</dd></div>
        </dl>
      </div>
      <div className="summary compact" aria-label="自動計算結果">
        <dl>
          <div><dt>自動算出休憩時間</dt><dd>{editor.calculation ? formatDuration(editor.calculation.breakMinutes) : '-'}</dd></div>
          <div><dt>実勤務時間</dt><dd>{editor.calculation ? editor.calculation.workTimeDisplay : '-'}</dd></div>
          <div><dt>通常勤務時間</dt><dd>{editor.calculation ? editor.calculation.regularWorkTimeDisplay : '-'}</dd></div>
          <div><dt>残業時間</dt><dd>{editor.calculation ? editor.calculation.overtimeWorkTimeDisplay : '-'}</dd></div>
          <div><dt>深夜時間</dt><dd>{editor.calculation ? editor.calculation.nightWorkTimeDisplay : '-'}</dd></div>
          <div><dt>作業時間合計</dt><dd>{editor.calculation ? formatDuration(editor.calculation.totalWorkItemMinutes) : '-'}</dd></div>
        </dl>
        {!editor.calculation && <p className="hint">保存後にBackendの計算結果を表示します。</p>}
      </div>
      {(editor.status === 'PENDING' || editor.status === 'APPROVED') && (
        <p className="hint">この状態の日報は編集できません。</p>
      )}
      <div className="form-grid">
        <label>
          日付
          <input type="date" disabled={editor.mutationDisabled} value={editor.form.reportDate} onChange={(event) => editor.setField('reportDate', event.target.value)} />
        </label>
        <label>
          休日区分
          <select disabled={editor.mutationDisabled} value={editor.form.holidayType} onChange={(event) => editor.changeHolidayType(event.target.value as HolidayType)}>
            {editor.holidayTypes.map((option) => (
              <option key={option.holidayType} value={option.holidayType}>{option.holidayTypeName}</option>
            ))}
          </select>
        </label>
        <label>
          勤務開始
          <input type="time" value={editor.form.startTime ?? ''} disabled={editor.workTimeDisabled} onChange={(event) => editor.setField('startTime', event.target.value || null)} />
        </label>
        <label>
          勤務終了
          <input type="time" value={editor.form.endTime ?? ''} disabled={editor.workTimeDisabled} onChange={(event) => editor.setField('endTime', event.target.value || null)} />
        </label>
      </div>
      <WorkItemsEditor
        categories={editor.categories}
        disabled={editor.workItemsDisabled}
        items={editor.form.workItems}
        onAdd={editor.addItem}
        onDelete={editor.deleteItem}
        onUpdate={editor.updateItem}
        projects={editor.projects}
      />
      <label>
        備考
        <textarea disabled={editor.mutationDisabled} value={editor.form.remarks ?? ''} onChange={(event) => editor.setField('remarks', event.target.value)} />
      </label>
      {editor.status === 'REJECTED' && (
        <div className="rejection-details">
          <dl>
            <div><dt>差戻しコメント</dt><dd>{editor.rejectionDetails?.rejectComment ?? '-'}</dd></div>
            <div><dt>差戻し者</dt><dd>{editor.rejectionDetails?.rejectorName ?? '-'}</dd></div>
            <div><dt>差戻し日時</dt><dd>{formatDateTime(editor.rejectionDetails?.rejectedAt ?? null)}</dd></div>
          </dl>
        </div>
      )}
      {editor.error && <p className="error" role="alert">{editor.error}</p>}
      {editor.message && <p className="success" role="status">{editor.message}</p>}
      <div className="actions">
        <button type="button" disabled={editor.mutationDisabled} onClick={editor.saveDraft}>下書き保存</button>
        <button type="button" disabled={editor.mutationDisabled} onClick={editor.saveAndSubmit}>保存して提出</button>
      </div>
      {editor.saving && <p className="hint" role="status">保存中...</p>}
    </section>
  );
}
