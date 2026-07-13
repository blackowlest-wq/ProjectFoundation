/**
 * 日報登録・編集画面のメインコンポーネント。
 * マスタ読み込み、既存日報の編集、下書き保存、提出、作業明細編集を1画面で扱う。
 */
import { useEffect, useState } from 'react';
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
import type { CurrentUser } from '../auth/types';
import type { ApiError } from '../shared/apiClient';
import type {
  ApprovalStatus,
  DailyReportRequest,
  DailyReportWorkItemInput,
  HolidayType,
  HolidayTypeOption,
  ProjectOption,
  WorkCategoryOption,
} from './types';

const statusLabelByStatus: Record<ApprovalStatus, string> = {
  DRAFT: '下書き',
  PENDING: '承認待ち',
  REJECTED: '差戻し',
  APPROVED: '承認済み',
};

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

function emptyReport(): DailyReportRequest {
  return {
    reportDate: today(),
    holidayType: 'WORKDAY',
    startTime: '09:00',
    endTime: '18:00',
    remarks: '',
    workItems: [{ projectId: 'P001', workCategoryId: 'WC001', workMinutes: 480 }],
  };
}

function reportIdFromPath(): string | null {
  const match = window.location.pathname.match(/^\/daily-reports\/([^/]+)\/edit$/);
  return match ? decodeURIComponent(match[1]) : null;
}

function totalMinutes(items: DailyReportWorkItemInput[]): number {
  return items.reduce((total, item) => total + Number(item.workMinutes || 0), 0);
}

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

function useDailyReportEditor() {
  const [reportId, setReportId] = useState<string | null>(() => reportIdFromPath());
  const [status, setStatus] = useState<ApprovalStatus>('DRAFT');
  const [form, setForm] = useState<DailyReportRequest>(() => emptyReport());
  const [projects, setProjects] = useState<ProjectOption[]>([]);
  const [categories, setCategories] = useState<WorkCategoryOption[]>([]);
  const [holidayTypes, setHolidayTypes] = useState<HolidayTypeOption[]>([]);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    // How: 3種類のマスタを並列取得し、完了後に各選択肢を同じフォーム状態へ設定する。
    // Why not: 入力行ごとにマスタを取得すると選択肢と通信回数が不安定になるため、画面表示時に一括取得して共有する。
    Promise.all([fetchProjects(), fetchWorkCategories(), fetchHolidayTypes()])
      .then(([projectOptions, categoryOptions, holidayOptions]) => {
        setProjects(projectOptions);
        setCategories(categoryOptions);
        setHolidayTypes(holidayOptions);
      })
      .catch((e) => setError((e as ApiError).message ?? 'マスタデータの読み込みに失敗しました。'));
  }, []);

  useEffect(() => {
    // How: 編集URLのreportIdがある場合だけ既存日報を取得して入力DTOへ変換し、新規URLは初期値を維持する。
    if (!reportId) {
      return;
    }
    fetchDailyReport(reportId)
      .then((report) => {
        setStatus(report.approvalStatus);
        setForm(toEditableReport(report));
      })
      .catch((e) => setError((e as ApiError).message ?? '日報の読み込みに失敗しました。'));
  }, [reportId]);

  function setField<K extends keyof DailyReportRequest>(key: K, value: DailyReportRequest[K]) {
    setForm((current) => ({ ...current, [key]: value }));
  }

  function changeHolidayType(value: HolidayType) {
    if (value === 'PAID_LEAVE') {
      // Why not: 区分変更前の勤務入力を残すと保存時に有給休暇の業務ルール違反になるため、関連入力を即時クリアする。
      setForm((current) => ({ ...current, holidayType: value, startTime: null, endTime: null, workItems: [] }));
      return;
    }
    setField('holidayType', value);
  }

  async function saveDraft() {
    await save(false);
  }

  async function saveAndSubmit() {
    await save(true);
  }

  async function save(thenSubmit: boolean) {
    // How: 画面入力を検証し、reportIdの有無で登録/更新を選び、提出時は差戻しだけ再提出APIへ分岐する。
    setError('');
    setMessage('');
    const validationError = validateDailyReportInput(form);
    if (validationError) {
      setError(validationError);
      return;
    }
    try {
      const saved = reportId ? await updateDailyReport(reportId, form) : await createDailyReport(form);
      setReportId(saved.reportId);
      setStatus(saved.approvalStatus);
      if (thenSubmit) {
        // Why not: 差戻し日報を通常提出APIへ送ると状態遷移の入口を分けられないため、再提出APIへ限定する。
        const submitted = saved.approvalStatus === 'REJECTED'
          ? await resubmitDailyReport(saved.reportId)
          : await submitDailyReport(saved.reportId);
        setStatus(submitted.approvalStatus);
        setMessage('保存して提出しました。');
      } else {
        setMessage('保存しました。');
      }
      // Why not: 登録後に新規URLを残すと再読込時に新規作成として扱われるため、編集URLへ置き換える。
      window.history.replaceState(null, '', `/daily-reports/${encodeURIComponent(saved.reportId)}/edit`);
    } catch (e) {
      const apiError = e as ApiError;
      // Why not: API全体のメッセージだけを表示すると入力箇所を特定できないため、field別エラーを優先する。
      setError(apiError.details?.[0]?.message ?? apiError.message ?? '保存に失敗しました。');
    }
  }

  function addItem() {
    // How: 現在のマスタ先頭値を選び、未取得時は既定IDを使って明細を末尾へ追加する。
    // Why not: マスタ取得完了まで追加操作を止めると入力を開始できないため、先頭値または既定IDで行を作成する。
    setForm((current) => ({
      ...current,
      workItems: [
        ...current.workItems,
        {
          projectId: projects[0]?.projectId ?? 'P001',
          workCategoryId: categories[0]?.workCategoryId ?? 'WC001',
          workMinutes: 60,
        },
      ],
    }));
  }

  function updateItem(index: number, item: DailyReportWorkItemInput) {
    setForm((current) => ({
      ...current,
      workItems: current.workItems.map((currentItem, itemIndex) => (itemIndex === index ? item : currentItem)),
    }));
  }

  function deleteItem(index: number) {
    // Why not: 明細ごとの差分APIを持つと画面とバックエンドで削除状態がずれるため、保存時に入力配列を全差し替えする。
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
    reportId,
    saveAndSubmit,
    saveDraft,
    setField,
    status,
    updateItem,
  };
}

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
          <select value={item.projectId} onChange={(event) => onUpdate(index, { ...item, projectId: event.target.value })}>
            {projects.map((project) => <option key={project.projectId} value={project.projectId}>{project.projectName}</option>)}
          </select>
          <select value={item.workCategoryId} onChange={(event) => onUpdate(index, { ...item, workCategoryId: event.target.value })}>
            {categories.map((category) => <option key={category.workCategoryId} value={category.workCategoryId}>{category.workCategoryName}</option>)}
          </select>
          <input
            type="number"
            min="1"
            value={item.workMinutes}
            onChange={(event) => onUpdate(index, { ...item, workMinutes: Number(event.target.value) })}
          />
          <button type="button" className="secondary" onClick={() => onDelete(index)}>削除</button>
        </div>
      ))}
      <p className="hint">合計: {totalMinutes(items)} 分</p>
    </div>
  );
}

export function DailyReportForm({ user }: { user: CurrentUser }) {
  const editor = useDailyReportEditor();
  const workDisabled = editor.form.holidayType === 'PAID_LEAVE'
    || (editor.form.holidayType === 'HOLIDAY' && editor.form.workItems.length === 0);
  // Why not: 画面で勤務時刻を入力可能にするとバックエンド検証まで業務ルール違反を保持できるため、対象区分では入力を無効にする。

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
      <div className="form-grid">
        <label>
          日付
          <input type="date" value={editor.form.reportDate} onChange={(event) => editor.setField('reportDate', event.target.value)} />
        </label>
        <label>
          休日区分
          <select value={editor.form.holidayType} onChange={(event) => editor.changeHolidayType(event.target.value as HolidayType)}>
            {editor.holidayTypes.map((option) => (
              <option key={option.holidayType} value={option.holidayType}>{option.holidayTypeName}</option>
            ))}
          </select>
        </label>
        <label>
          勤務開始
          <input type="time" value={editor.form.startTime ?? ''} disabled={workDisabled} onChange={(event) => editor.setField('startTime', event.target.value || null)} />
        </label>
        <label>
          勤務終了
          <input type="time" value={editor.form.endTime ?? ''} disabled={workDisabled} onChange={(event) => editor.setField('endTime', event.target.value || null)} />
        </label>
      </div>
      <WorkItemsEditor
        categories={editor.categories}
        disabled={editor.form.holidayType === 'PAID_LEAVE'}
        items={editor.form.workItems}
        onAdd={editor.addItem}
        onDelete={editor.deleteItem}
        onUpdate={editor.updateItem}
        projects={editor.projects}
      />
      <label>
        備考
        <textarea value={editor.form.remarks ?? ''} onChange={(event) => editor.setField('remarks', event.target.value)} />
      </label>
      {editor.error && <p className="error" role="alert">{editor.error}</p>}
      {editor.message && <p className="success" role="status">{editor.message}</p>}
      <div className="actions">
        <button type="button" onClick={editor.saveDraft}>下書き保存</button>
        <button type="button" onClick={editor.saveAndSubmit}>保存して提出</button>
      </div>
    </section>
  );
}
