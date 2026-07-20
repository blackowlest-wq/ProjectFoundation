// @vitest-environment jsdom

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DailyReportForm } from '../src/dailyReport/DailyReportForm';
import {
  buildReportDetail,
  buttonByText,
  cleanupUi,
  controlByLabel,
  countRequests,
  currentUser,
  fallbackUser,
  flushEffects,
  installFrontendFetch,
  jsonResponse,
  rejectWith,
  renderUi,
  respondJson,
  setControlValue,
  click,
} from './support/dailyReportTestSupport';

describe('DailyReportForm behavior from task-owned tests', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-17T09:00:00+09:00'));
    window.history.replaceState(null, '', '/daily-reports/new');
  });

  afterEach(() => {
    cleanupUi();
  });

  it('renders defaults, shows fallback user labels, and updates added work items through real controls', async () => {
    installFrontendFetch();

    await renderUi(<DailyReportForm user={fallbackUser} />);

    expect(document.body.textContent).toContain('日報登録');
    expect(controlByLabel<HTMLInputElement>('日付').value).toBe('2026-07-17');
    expect(document.body.textContent).toContain('休憩区分');
    expect(document.body.textContent).toContain('勤務区分');
    expect(document.body.textContent).toContain('-');

    await click(buttonByText('追加'));

    const rowsAfterAdd = document.querySelectorAll('.work-row');
    expect(rowsAfterAdd).toHaveLength(2);
    const addedProject = rowsAfterAdd[1]?.querySelectorAll('select')[0] as HTMLSelectElement;
    const addedCategory = rowsAfterAdd[1]?.querySelectorAll('select')[1] as HTMLSelectElement;
    const addedMinutes = rowsAfterAdd[1]?.querySelector('input[type="number"]') as HTMLInputElement;
    expect(addedProject.value).toBe('P001');
    expect(addedCategory.value).toBe('WC001');

    setControlValue(addedProject, 'P002');
    setControlValue(addedCategory, 'WC002');
    setControlValue(addedMinutes, '0');

    expect(document.body.textContent).toContain('合計: 480 分');

    const deleteButtons = Array.from(document.querySelectorAll('.work-row button'));
    await click(deleteButtons[0] ?? null);

    expect(document.querySelectorAll('.work-row')).toHaveLength(1);
    expect(document.body.textContent).toContain('合計: 0 分');
  });

  it('clears work inputs for paid leave and keeps holiday-without-items time fields disabled', async () => {
    installFrontendFetch();

    await renderUi(<DailyReportForm user={currentUser} />);

    setControlValue(controlByLabel<HTMLSelectElement>('休日区分'), 'PAID_LEAVE');

    expect(controlByLabel<HTMLInputElement>('勤務開始').value).toBe('');
    expect(controlByLabel<HTMLInputElement>('勤務終了').value).toBe('');
    expect(controlByLabel<HTMLInputElement>('勤務開始').disabled).toBe(true);
    expect(controlByLabel<HTMLInputElement>('勤務終了').disabled).toBe(true);
    expect(document.querySelectorAll('.work-row')).toHaveLength(0);
    expect(buttonByText('追加').disabled).toBe(true);

    setControlValue(controlByLabel<HTMLSelectElement>('休日区分'), 'HOLIDAY');

    expect(controlByLabel<HTMLInputElement>('勤務開始').disabled).toBe(true);
    expect(controlByLabel<HTMLInputElement>('勤務終了').disabled).toBe(true);
    expect(buttonByText('追加').disabled).toBe(false);
  });

  it('shows the fallback master-load error when master APIs fail without a message', async () => {
    installFrontendFetch({
      projects: rejectWith({}),
    });

    await renderUi(<DailyReportForm user={currentUser} />);

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('マスタデータの読み込みに失敗しました。');
  });

  it('shows the fallback existing-report error when edit data cannot be loaded', async () => {
    window.history.replaceState(null, '', '/daily-reports/R404/edit');
    const { calls } = installFrontendFetch({
      reportDetails: {
        R404: rejectWith({}),
      },
    });

    await renderUi(<DailyReportForm user={currentUser} />);

    expect(document.body.textContent).toContain('日報編集');
    expect(document.querySelector('[role="alert"]')?.textContent).toBe('日報の読み込みに失敗しました。');
    const controls = Array.from(document.querySelectorAll('.report-panel input, .report-panel select, .report-panel textarea, .report-panel button')) as Array<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement | HTMLButtonElement>;
    expect(controls.length).toBeGreaterThan(0);
    expect(controls.every((control) => control.disabled)).toBe(true);
    await click(buttonByText('下書き保存'));
    await click(buttonByText('保存して提出'));
    expect(countRequests(calls, 'PUT', '/api/daily-reports')).toBe(0);
    expect(countRequests(calls, 'POST', '/api/daily-reports')).toBe(0);
    expect(calls.filter(({ method }) => method === 'PUT' || method === 'POST')).toHaveLength(0);
  });

  it('disables all edit controls while an existing report is loading', async () => {
    let resolveReport!: (response: Response) => void;
    const reportResponse = new Promise<Response>((resolve) => {
      resolveReport = resolve;
    });
    const { calls } = installFrontendFetch({
      reportDetails: { RLOAD: reportResponse },
    });
    window.history.replaceState(null, '', '/daily-reports/RLOAD/edit');

    await renderUi(<DailyReportForm user={currentUser} />);

    const controls = Array.from(document.querySelectorAll('.report-panel input, .report-panel select, .report-panel textarea, .report-panel button')) as Array<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement | HTMLButtonElement>;
    expect(controls.length).toBeGreaterThan(0);
    expect(controls.every((control) => control.disabled)).toBe(true);
    expect(countRequests(calls, 'PUT', '/api/daily-reports')).toBe(0);
    expect(countRequests(calls, 'POST', '/api/daily-reports')).toBe(0);
    expect(calls.filter(({ method }) => method === 'PUT' || method === 'POST')).toHaveLength(0);

    resolveReport(jsonResponse(buildReportDetail('RLOAD')));
    await flushEffects();
    expect(controlByLabel<HTMLInputElement>('備考').disabled).toBe(false);
  });

  it.each(['PENDING', 'APPROVED'] as const)('disables every mutation control for %s reports', async (approvalStatus) => {
    const { calls } = installFrontendFetch({
      reportDetails: {
        [`R-${approvalStatus}`]: respondJson(buildReportDetail(`R-${approvalStatus}`, { approvalStatus })),
      },
    });
    window.history.replaceState(null, '', `/daily-reports/R-${approvalStatus}/edit`);

    await renderUi(<DailyReportForm user={currentUser} />);

    const controls = Array.from(document.querySelectorAll('.report-panel input, .report-panel select, .report-panel textarea, .report-panel button')) as Array<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement | HTMLButtonElement>;
    expect(controls.length).toBeGreaterThan(0);
    expect(controls.every((control) => control.disabled)).toBe(true);
    expect(countRequests(calls, 'PUT', '/api/daily-reports')).toBe(0);
    expect(countRequests(calls, 'POST', '/api/daily-reports')).toBe(0);
    expect(calls.filter(({ method }) => method === 'PUT' || method === 'POST')).toHaveLength(0);
    expect(document.body.textContent).toContain('この状態の日報は編集できません。');
  });

  it('shows rejection audit details and uses resubmit without calling initial submit', async () => {
    const { calls } = installFrontendFetch({
      reportDetails: {
        'R-REJECTED': respondJson(Object.assign(buildReportDetail('R-REJECTED', { approvalStatus: 'REJECTED' }), {
          rejectorName: '佐藤 上長',
          rejectedAt: '2026-07-16T17:30:00+09:00',
          rejectComment: '詳細を追記してください。',
        })),
      },
      update: respondJson({ reportId: 'R-REJECTED', approvalStatus: 'REJECTED' }),
      resubmit: respondJson({ reportId: 'R-REJECTED', approvalStatus: 'PENDING' }),
    });
    window.history.replaceState(null, '', '/daily-reports/R-REJECTED/edit');

    await renderUi(<DailyReportForm user={currentUser} />);

    expect(document.body.textContent).toContain('差戻しコメント');
    expect(document.body.textContent).toContain('詳細を追記してください。');
    expect(document.body.textContent).toContain('佐藤 上長');
    expect(document.body.textContent).toContain('2026-07-16T17:30:00+09:00');

    await click(buttonByText('保存して提出'));

    expect(countRequests(calls, 'POST', '/api/daily-reports/R-REJECTED/submit')).toBe(0);
    expect(countRequests(calls, 'POST', '/api/daily-reports/R-REJECTED/resubmit')).toBe(1);
    const mutations = calls.filter(({ method }) => method === 'PUT' || method === 'POST');
    expect(mutations.map(({ method, url }) => `${method} ${url.pathname}`)).toEqual([
      'PUT /api/daily-reports/R-REJECTED',
      'POST /api/daily-reports/R-REJECTED/resubmit',
    ]);
    expect(document.body.textContent).toContain('承認待ち');
  });

  it('saves an existing rejected report without changing its rejected state', async () => {
    window.history.replaceState(null, '', '/daily-reports/R-REJECTED-SAVE/edit');
    const { calls } = installFrontendFetch({
      reportDetails: {
        'R-REJECTED-SAVE': respondJson(buildReportDetail('R-REJECTED-SAVE', { approvalStatus: 'REJECTED' })),
      },
      update: respondJson({ reportId: 'R-REJECTED-SAVE', approvalStatus: 'REJECTED' }),
    });

    await renderUi(<DailyReportForm user={currentUser} />);
    setControlValue(controlByLabel<HTMLTextAreaElement>('備考'), '差戻し内容を更新');
    await click(buttonByText('下書き保存'));

    expect(document.querySelector('[role="status"]')?.textContent).toBe('保存しました。');
    expect(document.body.textContent).toContain('差戻し');
    expect(calls.filter(({ method }) => method === 'PUT' || method === 'POST').map(({ method, url }) => `${method} ${url.pathname}`)).toEqual([
      'PUT /api/daily-reports/R-REJECTED-SAVE',
    ]);
    const updateCall = calls.find(({ method, url }) => method === 'PUT' && url.pathname === '/api/daily-reports/R-REJECTED-SAVE');
    expect(JSON.parse(updateCall?.body ?? '{}').remarks).toBe('差戻し内容を更新');
  });

  it('shows dashes when rejection audit details are null', async () => {
    installFrontendFetch({
      reportDetails: {
        'R-NULL-REJECTION': respondJson(Object.assign(buildReportDetail('R-NULL-REJECTION', { approvalStatus: 'REJECTED' }), {
          rejectorName: null,
          rejectedAt: null,
          rejectComment: null,
        })),
      },
    });
    window.history.replaceState(null, '', '/daily-reports/R-NULL-REJECTION/edit');

    await renderUi(<DailyReportForm user={currentUser} />);

    const rejectionDetails = document.querySelector('.rejection-details');
    expect(rejectionDetails).not.toBeNull();
    expect(rejectionDetails?.textContent).toContain('差戻しコメント-');
    expect(rejectionDetails?.textContent).toContain('差戻し者-');
    expect(rejectionDetails?.textContent).toContain('差戻し日時-');
  });

  it('blocks save when the real form validation finds missing required input', async () => {
    const { calls } = installFrontendFetch();

    await renderUi(<DailyReportForm user={currentUser} />);

    setControlValue(controlByLabel<HTMLInputElement>('日付'), '');
    await click(buttonByText('下書き保存'));

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('日付を入力してください。');
    expect(countRequests(calls, 'POST', '/api/daily-reports')).toBe(0);
    expect(countRequests(calls, 'PUT', '/api/daily-reports')).toBe(0);
  });

  it('saves a new report as draft and replaces the path with the edit URL', async () => {
    installFrontendFetch({
      create: respondJson({ reportId: 'R900', approvalStatus: 'DRAFT' }, { status: 201 }),
      reportDetails: {
        R900: respondJson(buildReportDetail('R900')),
      },
    });

    await renderUi(<DailyReportForm user={currentUser} />);
    await click(buttonByText('下書き保存'));

    expect(document.querySelector('[role="status"]')?.textContent).toBe('保存しました。');
    expect(window.location.pathname).toBe('/daily-reports/R900/edit');
    expect(document.body.textContent).toContain('日報編集');
  });

  it('creates and submits a new report through the submit path', async () => {
    installFrontendFetch({
      create: respondJson({ reportId: 'R901', approvalStatus: 'DRAFT' }, { status: 201 }),
      submit: respondJson({ reportId: 'R901', approvalStatus: 'PENDING' }),
      reportDetails: {
        R901: respondJson(buildReportDetail('R901', { approvalStatus: 'PENDING' })),
      },
    });

    await renderUi(<DailyReportForm user={currentUser} />);
    await click(buttonByText('保存して提出'));

    expect(document.querySelector('[role="status"]')?.textContent).toBe('保存して提出しました。');
    expect(document.body.textContent).toContain('承認待ち');
    expect(window.location.pathname).toBe('/daily-reports/R901/edit');
  });

  it('updates an existing draft before submitting through the initial submit path', async () => {
    window.history.replaceState(null, '', '/daily-reports/R902/edit');
    const { calls } = installFrontendFetch({
      reportDetails: {
        R902: respondJson(buildReportDetail('R902', { approvalStatus: 'DRAFT' })),
      },
      update: respondJson({ reportId: 'R902', approvalStatus: 'DRAFT' }),
      submit: respondJson({ reportId: 'R902', approvalStatus: 'PENDING' }),
    });

    await renderUi(<DailyReportForm user={currentUser} />);
    await click(buttonByText('保存して提出'));

    const mutations = calls.filter(({ method }) => method === 'PUT' || method === 'POST');
    expect(mutations.map(({ method, url }) => `${method} ${url.pathname}`)).toEqual([
      'PUT /api/daily-reports/R902',
      'POST /api/daily-reports/R902/submit',
    ]);
    expect(document.querySelector('[role="status"]')?.textContent).toBe('保存して提出しました。');
    expect(document.body.textContent).toContain('承認待ち');
  });

  it('updates and resubmits an existing rejected report', async () => {
    window.history.replaceState(null, '', '/daily-reports/R777/edit');
    installFrontendFetch({
      reportDetails: {
        R777: respondJson(buildReportDetail('R777', {
          approvalStatus: 'REJECTED',
          remarks: null,
          startTime: null,
          endTime: null,
          workItems: [],
        })),
      },
      update: respondJson({ reportId: 'R777', approvalStatus: 'REJECTED' }),
      resubmit: respondJson({ reportId: 'R777', approvalStatus: 'PENDING' }),
    });

    await renderUi(<DailyReportForm user={currentUser} />);

    setControlValue(controlByLabel<HTMLInputElement>('勤務開始'), '09:00');
    setControlValue(controlByLabel<HTMLInputElement>('勤務終了'), '18:00');
    await click(buttonByText('追加'));
    await click(buttonByText('保存して提出'));

    expect(document.querySelector('[role="status"]')?.textContent).toBe('保存して提出しました。');
    expect(document.body.textContent).toContain('承認待ち');
    expect(window.location.pathname).toBe('/daily-reports/R777/edit');
  });

  it('prefers a field-level save error over the generic API message', async () => {
    installFrontendFetch({
      create: rejectWith({
        details: [{ field: 'reportDate', message: '日付ごとのエラーです。' }],
        message: 'APIメッセージ',
      }),
    });

    await renderUi(<DailyReportForm user={currentUser} />);
    await click(buttonByText('下書き保存'));

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('日付ごとのエラーです。');
  });

  it('falls back to the API message when save error details are missing', async () => {
    installFrontendFetch({
      create: rejectWith({ message: 'APIメッセージ' }),
    });

    await renderUi(<DailyReportForm user={currentUser} />);
    await click(buttonByText('下書き保存'));

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('APIメッセージ');
  });

  it('falls back to the generic save error when the API gives no usable details or message', async () => {
    installFrontendFetch({
      create: rejectWith({}),
    });

    await renderUi(<DailyReportForm user={currentUser} />);
    await click(buttonByText('下書き保存'));

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('保存に失敗しました。');
  });

  it('uses fallback project and category ids when adding work items before masters are available', async () => {
    const { calls } = installFrontendFetch({
      projects: respondJson([]),
      categories: respondJson([]),
      create: respondJson({ reportId: 'RFALL', approvalStatus: 'DRAFT' }, { status: 201 }),
      reportDetails: {
        RFALL: respondJson(buildReportDetail('RFALL')),
      },
    });

    await renderUi(<DailyReportForm user={currentUser} />);
    await click(buttonByText('追加'));
    await click(buttonByText('下書き保存'));

    const createCall = calls.find((call) => call.method === 'POST' && call.url.pathname === '/api/daily-reports');
    expect(createCall).toBeDefined();
    const body = JSON.parse(createCall?.body ?? '{}') as {
      workItems: Array<{ projectId: string; workCategoryId: string; workMinutes: number }>;
    };
    expect(body.workItems[1]).toEqual({ projectId: 'P001', workCategoryId: 'WC001', workMinutes: 60 });
  });
});
