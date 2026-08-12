import { useEffect, useRef, useState } from 'react';
import type { CurrentUser } from '../auth/types';
import type { ApiError } from '../shared/apiClient';
import { getMonthlySummary } from './monthlySummaryApi';
import type { MonthlySummaryResponse } from './types';
import './monthlySummary.css';

type MonthlySummaryPageProps = {
  user: CurrentUser;
  onUnauthorized?: () => void;
};

type TabKey = 'employees' | 'projects' | 'categories' | 'holidays';

const tabs: Array<{ key: TabKey; label: string }> = [
  { key: 'employees', label: '社員別' },
  { key: 'projects', label: '案件別' },
  { key: 'categories', label: '作業分類別' },
  { key: 'holidays', label: '休日区分別' },
];

function localYearMonth(date = new Date()): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
}

function errorMessage(error: unknown): string {
  const apiError = error as Partial<ApiError>;
  return typeof apiError.message === 'string' && apiError.message.length > 0
    ? apiError.message
    : '月次集計の取得に失敗しました。';
}

function totalWorkMinutes(summary: MonthlySummaryResponse): number {
  return summary.employeeWorkSummaries.reduce((total, employee) => total + employee.totalWorkMinutes, 0);
}

export function MonthlySummaryPage({ onUnauthorized }: MonthlySummaryPageProps) {
  const [inputYearMonth, setInputYearMonth] = useState(() => localYearMonth());
  const [summary, setSummary] = useState<MonthlySummaryResponse | null>(null);
  const [activeTab, setActiveTab] = useState<TabKey>('employees');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const requestGeneration = useRef(0);
  const tabRefs = useRef<Array<HTMLButtonElement | null>>([]);

  useEffect(() => {
    void load(localYearMonth());
    // 初期表示だけを自動取得し、年月入力中は通信しない。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function load(yearMonth: string) {
    const generation = requestGeneration.current + 1;
    requestGeneration.current = generation;
    setLoading(true);
    setError('');
    try {
      const nextSummary = await getMonthlySummary(yearMonth);
      if (generation !== requestGeneration.current) {
        return;
      }
      setSummary(nextSummary);
    } catch (loadError) {
      if (generation !== requestGeneration.current) {
        return;
      }
      setSummary(null);
      if ((loadError as Partial<ApiError>).code === 'UNAUTHORIZED') {
        onUnauthorized?.();
        return;
      }
      setError(errorMessage(loadError));
    } finally {
      if (generation === requestGeneration.current) {
        setLoading(false);
      }
    }
  }

  function moveTab(currentIndex: number, offset: number) {
    const nextIndex = (currentIndex + offset + tabs.length) % tabs.length;
    const nextKey = tabs[nextIndex].key;
    setActiveTab(nextKey);
    tabRefs.current[nextIndex]?.focus();
  }

  return (
    <section className="monthly-summary-page" aria-labelledby="monthly-summary-title">
      <div className="section-heading">
        <div>
          <p className="eyebrow">日報管理</p>
          <h1 id="monthly-summary-title">月次集計</h1>
        </div>
        {loading && <span className="hint">集計中...</span>}
      </div>

      <div className="monthly-summary-controls">
        <label htmlFor="monthly-summary-year-month">対象年月</label>
        <input
          id="monthly-summary-year-month"
          aria-label="対象年月"
          type="month"
          value={inputYearMonth}
          onChange={(event) => setInputYearMonth(event.target.value)}
        />
        <button type="button" onClick={() => void load(inputYearMonth)}>
          集計表示
        </button>
      </div>

      {error && <p className="error" role="alert">{error}</p>}

      {summary && (
        <>
          <section className="monthly-summary-overview" aria-label="集計概要">
            <dl>
              <div>
                <dt>対象社員</dt>
                <dd>{summary.employeeWorkSummaries.length}名</dd>
              </div>
              <div>
                <dt>総作業時間</dt>
                <dd>{totalWorkMinutes(summary)}分</dd>
              </div>
            </dl>
          </section>

          <div className="monthly-summary-tabs" role="tablist" aria-label="月次集計の表示切替">
            {tabs.map((tab, index) => (
              <button
                key={tab.key}
                ref={(element) => { tabRefs.current[index] = element; }}
                id={`monthly-summary-tab-${tab.key}`}
                role="tab"
                type="button"
                aria-selected={activeTab === tab.key}
                aria-controls={`monthly-summary-panel-${tab.key}`}
                tabIndex={activeTab === tab.key ? 0 : -1}
                onClick={() => setActiveTab(tab.key)}
                onKeyDown={(event) => {
                  if (event.key === 'ArrowRight') {
                    event.preventDefault();
                    moveTab(index, 1);
                  } else if (event.key === 'ArrowLeft') {
                    event.preventDefault();
                    moveTab(index, -1);
                  }
                }}
              >
                {tab.label}
              </button>
            ))}
          </div>

          <EmployeePanel summary={summary} hidden={activeTab !== 'employees'} />
          <ProjectPanel summary={summary} hidden={activeTab !== 'projects'} />
          <CategoryPanel summary={summary} hidden={activeTab !== 'categories'} />
          <HolidayPanel summary={summary} hidden={activeTab !== 'holidays'} />
        </>
      )}
    </section>
  );
}

function Panel({ tab, hidden, children }: { tab: TabKey; hidden: boolean; children: React.ReactNode }) {
  return (
    <section
      id={`monthly-summary-panel-${tab}`}
      className="monthly-summary-panel"
      role="tabpanel"
      aria-labelledby={`monthly-summary-tab-${tab}`}
      tabIndex={0}
      hidden={hidden}
    >
      {children}
    </section>
  );
}

function EmptyState() {
  return <p className="monthly-summary-empty">該当する集計データはありません。</p>;
}

function EmployeePanel({ summary, hidden }: { summary: MonthlySummaryResponse; hidden: boolean }) {
  return (
    <Panel tab="employees" hidden={hidden}>
      <h2>社員別作業時間</h2>
      {summary.employeeWorkSummaries.length === 0 ? <EmptyState /> : (
        <div className="table-wrap">
          <table>
            <caption className="visually-hidden">社員別作業時間</caption>
            <thead><tr><th>社員ID</th><th>社員名</th><th>合計作業時間（分）</th></tr></thead>
            <tbody>{summary.employeeWorkSummaries.map((item) => (
              <tr key={item.employeeId}><td>{item.employeeId}</td><td>{item.employeeName}</td><td>{item.totalWorkMinutes}</td></tr>
            ))}</tbody>
          </table>
        </div>
      )}
    </Panel>
  );
}

function ProjectPanel({ summary, hidden }: { summary: MonthlySummaryResponse; hidden: boolean }) {
  return (
    <Panel tab="projects" hidden={hidden}>
      <h2>案件別作業時間</h2>
      {summary.projectWorkSummaries.length === 0 ? <EmptyState /> : (
        <div className="table-wrap">
          <table>
            <caption className="visually-hidden">案件別作業時間</caption>
            <thead><tr><th>案件ID</th><th>案件名</th><th>合計作業時間（分）</th></tr></thead>
            <tbody>{summary.projectWorkSummaries.map((item) => (
              <tr key={item.projectId}><td>{item.projectId}</td><td>{item.projectName}</td><td>{item.totalWorkMinutes}</td></tr>
            ))}</tbody>
          </table>
        </div>
      )}
    </Panel>
  );
}

function CategoryPanel({ summary, hidden }: { summary: MonthlySummaryResponse; hidden: boolean }) {
  return (
    <Panel tab="categories" hidden={hidden}>
      <h2>作業分類別作業時間</h2>
      {summary.categoryWorkSummaries.length === 0 ? <EmptyState /> : (
        <div className="table-wrap">
          <table>
            <caption className="visually-hidden">作業分類別作業時間</caption>
            <thead><tr><th>作業分類ID</th><th>作業分類名</th><th>合計作業時間（分）</th></tr></thead>
            <tbody>{summary.categoryWorkSummaries.map((item) => (
              <tr key={item.workCategoryId}><td>{item.workCategoryId}</td><td>{item.workCategoryName}</td><td>{item.totalWorkMinutes}</td></tr>
            ))}</tbody>
          </table>
        </div>
      )}
    </Panel>
  );
}

function HolidayPanel({ summary, hidden }: { summary: MonthlySummaryResponse; hidden: boolean }) {
  return (
    <Panel tab="holidays" hidden={hidden}>
      <h2>休日区分別日数</h2>
      {summary.holidayTypeSummaries.length === 0 ? <EmptyState /> : (
        <div className="table-wrap">
          <table>
            <caption className="visually-hidden">休日区分別日数</caption>
            <thead><tr><th>休日区分</th><th>日数</th></tr></thead>
            <tbody>{summary.holidayTypeSummaries.map((item) => (
              <tr key={item.holidayType}><td>{item.holidayType}</td><td>{item.totalDays}</td></tr>
            ))}</tbody>
          </table>
        </div>
      )}
    </Panel>
  );
}
