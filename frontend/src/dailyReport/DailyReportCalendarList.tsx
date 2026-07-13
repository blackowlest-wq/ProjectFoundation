import { useEffect, useMemo, useState } from 'react';
import type { CurrentUser } from '../auth/types';
import type { ApiError } from '../shared/apiClient';
import { fetchHolidayTypes, searchDailyReports } from './dailyReportApi';
import {
  initialSearchCriteria,
  monthRange,
  validateDailyReportSearch,
  type DailyReportSearchCriteria,
} from './dailyReportSearch';
import type { ApprovalStatus, DailyReportListItem, HolidayType, HolidayTypeOption } from './types';

const statusLabelByStatus: Record<ApprovalStatus, string> = {
  DRAFT: '未提出',
  PENDING: '承認待ち',
  REJECTED: '差戻し',
  APPROVED: '承認済み',
};

const statusClassByStatus: Record<ApprovalStatus, string> = {
  DRAFT: 'status-draft',
  PENDING: 'status-pending',
  REJECTED: 'status-rejected',
  APPROVED: 'status-approved',
};

function calendarDays(targetMonth: string) {
  const { dateFrom, dateTo } = monthRange(targetMonth);
  const first = new Date(`${dateFrom}T00:00:00`);
  const last = new Date(`${dateTo}T00:00:00`);
  const mondayStartOffset = (first.getDay() + 6) % 7;
  const days: Array<{ date: string; inMonth: boolean }> = [];
  const cursor = new Date(first);
  cursor.setDate(first.getDate() - mondayStartOffset);
  while (days.length < 42) {
    const value = `${cursor.getFullYear()}-${String(cursor.getMonth() + 1).padStart(2, '0')}-${String(cursor.getDate()).padStart(2, '0')}`;
    days.push({ date: value, inMonth: cursor.getMonth() === first.getMonth() });
    cursor.setDate(cursor.getDate() + 1);
  }
  return days.filter((day, index) => index < 35 || new Date(`${day.date}T00:00:00`) <= last);
}

function holidayName(item: DailyReportListItem, holidayTypes: HolidayTypeOption[]) {
  return holidayTypes.find((option) => option.holidayType === item.holidayType)?.holidayTypeName ?? item.holidayType;
}

function readErrorMessage(error: unknown) {
  const apiError = error as Partial<ApiError>;
  return apiError.message ?? '日報一覧の取得に失敗しました。';
}

function formatMinutes(minutes: number) {
  return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, '0')}`;
}

export function DailyReportCalendarList({ user, onUnauthorized }: { user: CurrentUser; onUnauthorized?: () => void }) {
  const [criteria, setCriteria] = useState<DailyReportSearchCriteria>(() => initialSearchCriteria());
  const [reports, setReports] = useState<DailyReportListItem[]>([]);
  const [holidayTypes, setHolidayTypes] = useState<HolidayTypeOption[]>([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const reportsByDate = useMemo(() => {
    const map = new Map<string, DailyReportListItem[]>();
    for (const report of reports) {
      map.set(report.reportDate, [...(map.get(report.reportDate) ?? []), report]);
    }
    return map;
  }, [reports]);

  useEffect(() => {
    fetchHolidayTypes().then(setHolidayTypes).catch(() => setHolidayTypes([]));
  }, []);

  useEffect(() => {
    // How: マウント時は初期条件で一度だけ検索し、以後は同じrunSearchを検索ボタンから呼ぶ。
    void runSearch(criteria);
    // Why not: 条件変更のたびに自動検索すると入力途中の条件で通信するため、初期表示だけ自動検索し以後はボタン操作に限定する。
    // Why not: 依存配列へrunSearchを加えると条件変更ごとに自動検索されるため、初期表示限定の副作用として抑制する。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function setField<K extends keyof DailyReportSearchCriteria>(key: K, value: DailyReportSearchCriteria[K]) {
    setCriteria((current) => ({ ...current, [key]: value }));
  }

  function changeTargetMonth(value: string) {
    setCriteria((current) => ({ ...current, targetMonth: value, ...monthRange(value) }));
  }

  function clearConditions() {
    const next = initialSearchCriteria();
    setCriteria(next);
    setError('');
  }

  async function runSearch(current: DailyReportSearchCriteria = criteria) {
    const validationError = validateDailyReportSearch(current);
    if (validationError) {
      setError(validationError);
      return;
    }
    setLoading(true);
    setError('');
    try {
      setReports(await searchDailyReports(current));
    } catch (searchError) {
      if ((searchError as Partial<ApiError>).code === 'UNAUTHORIZED') {
        setReports([]);
        onUnauthorized?.();
        return;
      }
      setError(readErrorMessage(searchError));
    } finally {
      setLoading(false);
    }
  }

  return (
    <section className="report-panel">
      <div className="section-heading">
        <h2>日報検索</h2>
        {loading && <span className="hint">検索中...</span>}
      </div>

      <div className="form-grid">
        <label>
          対象年月
          <input type="month" value={criteria.targetMonth} onChange={(event) => changeTargetMonth(event.target.value)} />
        </label>
        <label>
          検索開始日
          <input type="date" value={criteria.dateFrom} onChange={(event) => setField('dateFrom', event.target.value)} />
        </label>
        <label>
          検索終了日
          <input type="date" value={criteria.dateTo} onChange={(event) => setField('dateTo', event.target.value)} />
        </label>
        {user.role !== 'EMPLOYEE' && (
          <label>
            グループID
            <input value={criteria.groupId ?? ''} onChange={(event) => setField('groupId', event.target.value)} />
          </label>
        )}
        <label>
          社員ID
          <input value={criteria.employeeId ?? ''} onChange={(event) => setField('employeeId', event.target.value)} />
        </label>
        <label>
          検索承認状態
          <select value={criteria.status ?? ''} onChange={(event) => setField('status', event.target.value as ApprovalStatus | '')}>
            <option value="">すべて</option>
            {Object.entries(statusLabelByStatus).map(([status, label]) => (
              <option key={status} value={status}>{label}</option>
            ))}
          </select>
        </label>
        <label>
          検索休日区分
          <select value={criteria.holidayType ?? ''} onChange={(event) => setField('holidayType', event.target.value as HolidayType | '')}>
            <option value="">すべて</option>
            {holidayTypes.map((option) => (
              <option key={option.holidayType} value={option.holidayType}>{option.holidayTypeName}</option>
            ))}
          </select>
        </label>
      </div>

      {error && <p className="error" role="alert">{error}</p>}

      <div className="actions">
        <button type="button" onClick={() => void runSearch()}>検索</button>
        <button type="button" className="secondary" onClick={clearConditions}>条件クリア</button>
      </div>

      <div className="calendar-grid">
        {['月', '火', '水', '木', '金', '土', '日'].map((day) => (
          <div className="calendar-weekday" key={day}>{day}</div>
        ))}
        {calendarDays(criteria.targetMonth).map((day) => {
          const dayReports = reportsByDate.get(day.date) ?? [];
          const firstReport = dayReports[0];
          const statusLabel = firstReport ? statusLabelByStatus[firstReport.approvalStatus] : '';
          return (
            <div
              className={`calendar-cell ${day.inMonth ? '' : 'muted'} ${firstReport ? statusClassByStatus[firstReport.approvalStatus] : ''}`}
              aria-label={statusLabel ? `${day.date} ${statusLabel}` : day.date}
              key={day.date}
            >
              <span className="calendar-date">{Number(day.date.slice(-2))}</span>
              {firstReport && (
                <>
                  <span>{holidayName(firstReport, holidayTypes)}</span>
                  <strong>{firstReport.workTimeDisplay}</strong>
                </>
              )}
            </div>
          );
        })}
      </div>

      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>日付</th>
              <th>グループ</th>
              <th>社員名</th>
              <th>休日区分</th>
              <th>勤務時間</th>
              <th>作業時間合計</th>
              <th>承認状態</th>
              <th>提出日時</th>
              <th>承認者</th>
              <th>承認日時</th>
            </tr>
          </thead>
          <tbody>
            {reports.map((report) => (
              <tr key={report.reportId}>
                <td>{report.reportDate}</td>
                <td>{report.groupName}</td>
                <td>{report.employeeName}</td>
                <td>{holidayName(report, holidayTypes)}</td>
                <td>{report.workTimeDisplay}</td>
                <td>{formatMinutes(report.totalWorkItemMinutes)}</td>
                <td>{statusLabelByStatus[report.approvalStatus]}</td>
                <td>{report.submittedAt ?? '-'}</td>
                <td>{report.approverName ?? '-'}</td>
                <td>{report.approvedAt ?? '-'}</td>
              </tr>
            ))}
            {reports.length === 0 && (
              <tr>
                <td colSpan={10}>該当する日報はありません。</td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </section>
  );
}
