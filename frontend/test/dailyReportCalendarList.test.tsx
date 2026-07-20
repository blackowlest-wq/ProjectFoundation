// @vitest-environment jsdom

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DailyReportCalendarList } from '../src/dailyReport/DailyReportCalendarList';
import {
  buildListItem,
  buttonByText,
  cleanupUi,
  controlByLabel,
  countRequests,
  currentUser,
  installFrontendFetch,
  managerUser,
  rejectWith,
  renderUi,
  respondJson,
  setControlValue,
  click,
} from './support/dailyReportTestSupport';

describe('DailyReportCalendarList behavior from task-owned tests', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-17T09:00:00+09:00'));
    window.history.replaceState(null, '', '/daily-reports');
  });

  afterEach(() => {
    cleanupUi();
  });

  it('keeps calendar-list regression behavior and provides an encoded detail route', async () => {
    installFrontendFetch({
      search: respondJson([
        buildListItem('R /?', {
          holidayType: 'WORKDAY',
          approvalStatus: 'PENDING',
          reportDate: '2026-07-15',
          workTimeDisplay: '09:00-18:00',
          totalWorkItemMinutes: 480,
          submittedAt: null,
          approverName: null,
          approvedAt: null,
        }),
      ]),
    });

    await renderUi(<DailyReportCalendarList user={currentUser} />);

    expect(document.body.textContent).not.toContain('グループID');
    expect(document.querySelector('[aria-label="2026-07-15 承認待ち"]')).not.toBeNull();
    expect(document.body.textContent).toContain('通常勤務');
    expect(document.body.textContent).toContain('8:00');
    expect(document.body.textContent).toContain('-');
    expect(Array.from(document.querySelectorAll('a')).find((link) => link.textContent === '詳細')?.getAttribute('href'))
      .toBe('/daily-reports/R%20%2F%3F');
  });

  it('shows the manager group filter, rejects invalid search input, and clears conditions back to the current month', async () => {
    const { calls } = installFrontendFetch();

    await renderUi(<DailyReportCalendarList user={managerUser} />);

    expect(document.body.textContent).toContain('グループID');
    const initialSearchCalls = countRequests(calls, 'GET', '/api/daily-reports');

    setControlValue(controlByLabel<HTMLInputElement>('検索開始日'), '');
    await click(buttonByText('検索'));

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('対象期間を指定してください。');
    expect(countRequests(calls, 'GET', '/api/daily-reports')).toBe(initialSearchCalls);

    setControlValue(controlByLabel<HTMLInputElement>('対象年月'), '2026-06');
    await click(buttonByText('条件クリア'));

    expect(document.querySelector('[role="alert"]')).toBeNull();
    expect(controlByLabel<HTMLInputElement>('対象年月').value).toBe('2026-07');
    expect(controlByLabel<HTMLInputElement>('検索開始日').value).toBe('2026-07-01');
    expect(controlByLabel<HTMLInputElement>('検索終了日').value).toBe('2026-07-31');
  });

  it('falls back to the holiday type id when holiday master loading fails', async () => {
    installFrontendFetch({
      holidayTypes: rejectWith({}),
      search: respondJson([
        buildListItem('R002', {
          holidayType: 'AM_OFF',
          reportDate: '2026-07-16',
          approvalStatus: 'APPROVED',
        }),
      ]),
    });

    await renderUi(<DailyReportCalendarList user={currentUser} />);

    expect(document.body.textContent).toContain('AM_OFF');
  });

  it('shows the fallback list error when search fails without a usable message', async () => {
    installFrontendFetch({
      search: rejectWith({}),
    });

    await renderUi(<DailyReportCalendarList user={currentUser} />);

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('日報一覧の取得に失敗しました。');
  });

  it('calls onUnauthorized and clears previous reports when a later search becomes unauthorized', async () => {
    const onUnauthorized = vi.fn();
    installFrontendFetch({
      search: (_url, callCount) => (
        callCount === 1
          ? respondJson([
            buildListItem('R003', { reportDate: '2026-07-17', approvalStatus: 'REJECTED', approverName: '佐藤 上長' }),
          ])
          : rejectWith({ code: 'UNAUTHORIZED', message: 'ログインが必要です。' })
      ),
    });

    await renderUi(<DailyReportCalendarList user={currentUser} onUnauthorized={onUnauthorized} />);
    expect(document.body.textContent).toContain('佐藤 上長');

    await click(buttonByText('検索'));

    expect(onUnauthorized).toHaveBeenCalledTimes(1);
    expect(document.body.textContent).toContain('該当する日報はありません。');
  });

  it('tolerates an unauthorized search even when the callback is not provided', async () => {
    installFrontendFetch({
      search: rejectWith({ code: 'UNAUTHORIZED', message: 'ログインが必要です。' }),
    });

    await renderUi(<DailyReportCalendarList user={currentUser} />);

    expect(document.querySelector('[role="alert"]')).toBeNull();
    expect(document.body.textContent).toContain('該当する日報はありません。');
  });
});
