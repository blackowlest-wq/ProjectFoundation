// @vitest-environment jsdom

import { act, type ReactNode } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import App from '../src/app/App';
import { fetchMe, login, logout } from '../src/auth/authApi';
import type { CurrentUser } from '../src/auth/types';
import { DailyReportCalendarList } from '../src/dailyReport/DailyReportCalendarList';
import { DailyReportForm } from '../src/dailyReport/DailyReportForm';
import type {
  DailyReportListItem,
  DailyReportResponse,
  HolidayTypeOption,
  ProjectOption,
  WorkCategoryOption,
} from '../src/dailyReport/types';

vi.mock('../src/auth/authApi', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../src/auth/authApi')>();
  return {
    ...actual,
    fetchMe: vi.fn(),
    login: vi.fn(),
    logout: vi.fn(),
  };
});

const currentUser: CurrentUser = {
  userId: 'U001',
  loginId: 'employee001',
  userName: '山田 太郎',
  role: 'EMPLOYEE',
  groupId: 'G001',
  groupName: '第1開発グループ',
  breakTypeId: 'BT001',
  breakTypeName: '標準休憩',
  workTimeTypeId: 'WT001',
  workTimeTypeName: '通常勤務',
};

const managerUser: CurrentUser = {
  ...currentUser,
  role: 'MANAGER',
};

const adminUser: CurrentUser = {
  ...currentUser,
  role: 'ADMIN',
};

const fallbackUser: CurrentUser = {
  ...currentUser,
  groupId: null,
  groupName: null,
  breakTypeId: null,
  breakTypeName: null,
  workTimeTypeId: null,
  workTimeTypeName: null,
};

const holidayTypes: HolidayTypeOption[] = [
  { holidayType: 'WORKDAY', holidayTypeName: '通常勤務', requiresWorkTime: true, allowsWorkItems: true },
  { holidayType: 'HOLIDAY', holidayTypeName: '休日', requiresWorkTime: false, allowsWorkItems: false },
  { holidayType: 'PAID_LEAVE', holidayTypeName: '有給休暇', requiresWorkTime: false, allowsWorkItems: false },
  { holidayType: 'AM_OFF', holidayTypeName: '午前休', requiresWorkTime: true, allowsWorkItems: true },
  { holidayType: 'PM_OFF', holidayTypeName: '午後休', requiresWorkTime: true, allowsWorkItems: true },
];

const projects: ProjectOption[] = [
  { projectId: 'P001', projectName: '案件A' },
  { projectId: 'P002', projectName: '案件B' },
];

const categories: WorkCategoryOption[] = [
  { workCategoryId: 'WC001', workCategoryName: '実装' },
  { workCategoryId: 'WC002', workCategoryName: 'レビュー' },
];

type StubResult =
  | Response
  | { kind: 'json'; body: unknown; init?: ResponseInit }
  | { kind: 'throw'; error: unknown };

type FetchScenario = {
  holidayTypes?: StubResult;
  projects?: StubResult;
  categories?: StubResult;
  search?: StubResult | ((url: URL, callCount: number) => StubResult);
  reportDetails?: Record<string, StubResult>;
  create?: StubResult;
  update?: StubResult;
  submit?: StubResult;
  resubmit?: StubResult;
};

let root: Root | null = null;
let container: HTMLDivElement | null = null;

(globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

function jsonResponse(body: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
    ...init,
  });
}

function respondJson(body: unknown, init: ResponseInit = {}): StubResult {
  return { kind: 'json', body, init };
}

function rejectWith(error: unknown): StubResult {
  return { kind: 'throw', error };
}

function buildReportDetail(reportId: string, overrides: Partial<DailyReportResponse> = {}): DailyReportResponse {
  return {
    reportId,
    employeeId: 'E001',
    employeeName: '山田 太郎',
    groupId: 'G001',
    groupName: '第1開発グループ',
    reportDate: '2026-07-15',
    holidayType: 'WORKDAY',
    startTime: '09:00',
    endTime: '18:00',
    remarks: '定例対応',
    breakTypeId: 'BT001',
    breakTypeName: '標準休憩',
    workTimeTypeId: 'WT001',
    workTimeTypeName: '通常勤務',
    breakMinutes: 60,
    workMinutes: 480,
    regularWorkMinutes: 480,
    overtimeWorkMinutes: 0,
    nightWorkMinutes: 0,
    workTimeDisplay: '09:00-18:00',
    regularWorkTimeDisplay: '8:00',
    overtimeWorkTimeDisplay: '0:00',
    nightWorkTimeDisplay: '0:00',
    totalWorkItemMinutes: 480,
    approvalStatus: 'DRAFT',
    submittedAt: null,
    rejectComment: null,
    workItems: [{
      workItemId: 'WI001',
      projectId: 'P001',
      projectName: '案件A',
      workCategoryId: 'WC001',
      workCategoryName: '実装',
      workMinutes: 480,
    }],
    ...overrides,
  };
}

function buildListItem(reportId: string, overrides: Partial<DailyReportListItem> = {}): DailyReportListItem {
  const detail = buildReportDetail(reportId);
  return {
    ...detail,
    approverName: null,
    approvedAt: null,
    rejected: false,
    ...overrides,
  } as unknown as DailyReportListItem;
}

function toPromise(result: StubResult): Promise<Response> {
  if (result instanceof Response) {
    return Promise.resolve(result);
  }
  if (result.kind === 'throw') {
    return Promise.reject(result.error);
  }
  return Promise.resolve(jsonResponse(result.body, result.init));
}

function installFrontendFetch(scenario: FetchScenario = {}) {
  const calls: Array<{ method: string; url: URL; body?: string }> = [];
  let searchCallCount = 0;

  vi.spyOn(globalThis, 'fetch').mockImplementation((input, init) => {
    const rawUrl = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    const url = new URL(rawUrl, 'http://localhost');
    const method = init?.method ?? 'GET';
    calls.push({ method, url, body: typeof init?.body === 'string' ? init.body : undefined });

    if (method === 'GET' && url.pathname === '/api/master/holiday-types') {
      return toPromise(scenario.holidayTypes ?? respondJson(holidayTypes));
    }
    if (method === 'GET' && url.pathname === '/api/master/projects') {
      return toPromise(scenario.projects ?? respondJson(projects));
    }
    if (method === 'GET' && url.pathname === '/api/master/work-categories') {
      return toPromise(scenario.categories ?? respondJson(categories));
    }
    if (method === 'GET' && url.pathname === '/api/daily-reports') {
      searchCallCount += 1;
      const searchResult = typeof scenario.search === 'function'
        ? scenario.search(url, searchCallCount)
        : scenario.search ?? respondJson([]);
      return toPromise(searchResult);
    }
    if (method === 'GET' && /^\/api\/daily-reports\/[^/]+$/.test(url.pathname)) {
      const reportId = decodeURIComponent(url.pathname.slice('/api/daily-reports/'.length));
      return toPromise(scenario.reportDetails?.[reportId] ?? respondJson(buildReportDetail(reportId)));
    }
    if (method === 'POST' && url.pathname === '/api/daily-reports') {
      return toPromise(scenario.create ?? respondJson({ reportId: 'RNEW', approvalStatus: 'DRAFT' }, { status: 201 }));
    }
    if (method === 'PUT' && /^\/api\/daily-reports\/[^/]+$/.test(url.pathname)) {
      return toPromise(scenario.update ?? respondJson({ reportId: 'R001', approvalStatus: 'DRAFT' }));
    }
    if (method === 'POST' && /^\/api\/daily-reports\/[^/]+\/submit$/.test(url.pathname)) {
      return toPromise(scenario.submit ?? respondJson({ reportId: 'R001', approvalStatus: 'PENDING' }));
    }
    if (method === 'POST' && /^\/api\/daily-reports\/[^/]+\/resubmit$/.test(url.pathname)) {
      return toPromise(scenario.resubmit ?? respondJson({ reportId: 'R001', approvalStatus: 'PENDING' }));
    }

    return Promise.reject(new Error(`Unhandled fetch: ${method} ${url.pathname}${url.search}`));
  });

  return { calls };
}

async function flushEffects(turns = 6) {
  await act(async () => {
    for (let index = 0; index < turns; index += 1) {
      await Promise.resolve();
    }
  });
}

async function renderUi(ui: ReactNode) {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () => {
    root?.render(<>{ui}</>);
    await Promise.resolve();
  });
  await flushEffects();
}

async function renderApp() {
  await renderUi(<App />);
}

async function renderCalendarList(user: CurrentUser, onUnauthorized?: () => void) {
  await renderUi(<DailyReportCalendarList user={user} onUnauthorized={onUnauthorized} />);
}

async function renderDailyReportForm(user: CurrentUser) {
  await renderUi(<DailyReportForm user={user} />);
}

function labelByText(labelText: string): HTMLLabelElement {
  const label = Array.from(document.querySelectorAll('label'))
    .find((candidate) => candidate.textContent?.includes(labelText));
  if (!label) {
    throw new Error(`Label not found: ${labelText}`);
  }
  return label as HTMLLabelElement;
}

function controlByLabel<T extends HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>(labelText: string): T {
  const control = labelByText(labelText).querySelector('input, select, textarea');
  if (!control) {
    throw new Error(`Control not found: ${labelText}`);
  }
  return control as T;
}

function setControlValue(control: HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement, value: string) {
  act(() => {
    const prototype = control instanceof HTMLSelectElement
      ? HTMLSelectElement.prototype
      : control instanceof HTMLTextAreaElement
        ? HTMLTextAreaElement.prototype
        : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;
    setter?.call(control, value);
    control.dispatchEvent(new Event(control instanceof HTMLSelectElement ? 'change' : 'input', { bubbles: true }));
  });
}

function inputByLabel(labelText: string): HTMLInputElement {
  return controlByLabel<HTMLInputElement>(labelText);
}

function buttonByText(labelText: string): HTMLButtonElement {
  const button = Array.from(document.querySelectorAll('button'))
    .find((candidate) => candidate.textContent === labelText);
  if (!button) {
    throw new Error(`Button not found: ${labelText}`);
  }
  return button as HTMLButtonElement;
}

async function click(element: Element | null) {
  if (!element) {
    throw new Error('Clickable element not found.');
  }
  await act(async () => {
    element.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    await Promise.resolve();
  });
  await flushEffects();
}

async function submitLogin(loginIdValue: string, passwordValue: string) {
  setControlValue(inputByLabel('ログインID'), loginIdValue);
  setControlValue(inputByLabel('パスワード'), passwordValue);
  const form = document.querySelector('form');
  if (!form) {
    throw new Error('Login form not found.');
  }
  await act(async () => {
    form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    await Promise.resolve();
  });
  await flushEffects();
}

function countRequests(calls: Array<{ method: string; url: URL }>, method: string, path: string) {
  return calls.filter((call) => call.method === method && call.url.pathname === path).length;
}

describe('App authentication state', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-17T09:00:00+09:00'));
    window.history.replaceState(null, '', '/login');
    vi.clearAllMocks();
  });

  afterEach(() => {
    act(() => {
      root?.unmount();
    });
    container?.remove();
    root = null;
    container = null;
    vi.restoreAllMocks();
    vi.useRealTimers();
    window.history.replaceState(null, '', '/login');
  });

  it('shows the login screen when the initial session is unauthenticated', async () => {
    vi.mocked(fetchMe).mockResolvedValue(null);

    await renderApp();

    expect(document.querySelector('h1')?.textContent).toBe('ログイン');
    expect(document.querySelector('.topbar')).toBeNull();
  });

  it('shows the login fallback error when login fails without a usable message', async () => {
    vi.mocked(fetchMe).mockResolvedValue(null);
    vi.mocked(login).mockRejectedValue({});

    await renderApp();
    await submitLogin('employee001', 'password123');

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('ログインに失敗しました。');
  });

  it.each([
    ['EMPLOYEE', '/daily-reports', currentUser],
    ['MANAGER', '/pending-approvals', managerUser],
    ['ADMIN', '/monthly-summaries', adminUser],
  ] as const)('moves to the %s initial path after login', async (_role, expectedPath, loggedInUser) => {
    installFrontendFetch();
    vi.mocked(fetchMe).mockResolvedValue(null);
    vi.mocked(login).mockResolvedValue(loggedInUser);

    await renderApp();
    await submitLogin('employee001', 'password123');

    expect(window.location.pathname).toBe(expectedPath);
    expect(document.body.textContent).toContain('山田 太郎');
  });

  it('returns to the login screen after logout succeeds', async () => {
    installFrontendFetch();
    vi.mocked(fetchMe).mockResolvedValue(currentUser);
    vi.mocked(logout).mockResolvedValue(undefined);

    await renderApp();
    await click(buttonByText('ログアウト'));

    expect(window.location.pathname).toBe('/login');
    expect(document.querySelector('h1')?.textContent).toBe('ログイン');
  });

  it('shows a fallback dash when the authenticated user has no group name', async () => {
    installFrontendFetch();
    vi.mocked(fetchMe).mockResolvedValue({ ...currentUser, groupName: null });

    await renderApp();

    expect(document.body.textContent).toContain('所属');
    expect(document.body.textContent).toContain('-');
  });

  it('keeps the authenticated screen and shows an error when logout fails', async () => {
    installFrontendFetch();
    vi.mocked(fetchMe).mockResolvedValue(currentUser);
    vi.mocked(logout).mockRejectedValue(new Error('logout failed'));

    await renderApp();
    await click(buttonByText('ログアウト'));

    expect(document.querySelector('.topbar')).not.toBeNull();
    expect(document.querySelector('[role="alert"]')?.textContent)
      .toBe('ログアウトに失敗しました。時間をおいて再度お試しください。');
  });

  it('returns to the login screen when the real report list receives unauthorized', async () => {
    installFrontendFetch({
      search: rejectWith({ code: 'UNAUTHORIZED', message: 'ログインが必要です。' }),
    });
    vi.mocked(fetchMe).mockResolvedValue(currentUser);

    await renderApp();
    await flushEffects();

    expect(window.location.pathname).toBe('/login');
    expect(document.querySelector('[role="alert"]')?.textContent).toBe('ログインが必要です。');
    expect(document.querySelector('h1')?.textContent).toBe('ログイン');
  });
});

describe('DailyReportCalendarList behavior from task-owned tests', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-17T09:00:00+09:00'));
    window.history.replaceState(null, '', '/daily-reports');
  });

  afterEach(() => {
    act(() => {
      root?.unmount();
    });
    container?.remove();
    root = null;
    container = null;
    vi.restoreAllMocks();
    vi.useRealTimers();
    window.history.replaceState(null, '', '/login');
  });

  it('renders calendar results, master holiday labels, and fallback dashes for missing approval fields', async () => {
    installFrontendFetch({
      search: respondJson([
        buildListItem('R001', {
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

    await renderCalendarList(currentUser);

    expect(document.body.textContent).not.toContain('グループID');
    expect(document.querySelector('[aria-label="2026-07-15 承認待ち"]')).not.toBeNull();
    expect(document.body.textContent).toContain('通常勤務');
    expect(document.body.textContent).toContain('8:00');
    expect(document.body.textContent).toContain('-');
  });

  it('shows the manager group filter, rejects invalid search input, and clears conditions back to the current month', async () => {
    const { calls } = installFrontendFetch();

    await renderCalendarList(managerUser);

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

    await renderCalendarList(currentUser);

    expect(document.body.textContent).toContain('AM_OFF');
  });

  it('shows the fallback list error when search fails without a usable message', async () => {
    installFrontendFetch({
      search: rejectWith({}),
    });

    await renderCalendarList(currentUser);

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

    await renderCalendarList(currentUser, onUnauthorized);
    expect(document.body.textContent).toContain('佐藤 上長');

    await click(buttonByText('検索'));

    expect(onUnauthorized).toHaveBeenCalledTimes(1);
    expect(document.body.textContent).toContain('該当する日報はありません。');
  });

  it('tolerates an unauthorized search even when the callback is not provided', async () => {
    installFrontendFetch({
      search: rejectWith({ code: 'UNAUTHORIZED', message: 'ログインが必要です。' }),
    });

    await renderCalendarList(currentUser);

    expect(document.querySelector('[role="alert"]')).toBeNull();
    expect(document.body.textContent).toContain('該当する日報はありません。');
  });
});

describe('DailyReportForm behavior from task-owned tests', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-17T09:00:00+09:00'));
    window.history.replaceState(null, '', '/daily-reports/new');
  });

  afterEach(() => {
    act(() => {
      root?.unmount();
    });
    container?.remove();
    root = null;
    container = null;
    vi.restoreAllMocks();
    vi.useRealTimers();
    window.history.replaceState(null, '', '/login');
  });

  it('renders defaults, shows fallback user labels, and updates added work items through real controls', async () => {
    installFrontendFetch();

    await renderDailyReportForm(fallbackUser);

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

    await renderDailyReportForm(currentUser);

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

    await renderDailyReportForm(currentUser);

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('マスタデータの読み込みに失敗しました。');
  });

  it('shows the fallback existing-report error when edit data cannot be loaded', async () => {
    window.history.replaceState(null, '', '/daily-reports/R404/edit');
    installFrontendFetch({
      reportDetails: {
        R404: rejectWith({}),
      },
    });

    await renderDailyReportForm(currentUser);

    expect(document.body.textContent).toContain('日報編集');
    expect(document.querySelector('[role="alert"]')?.textContent).toBe('日報の読み込みに失敗しました。');
  });

  it('blocks save when the real form validation finds missing required input', async () => {
    const { calls } = installFrontendFetch();

    await renderDailyReportForm(currentUser);

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

    await renderDailyReportForm(currentUser);
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

    await renderDailyReportForm(currentUser);
    await click(buttonByText('保存して提出'));

    expect(document.querySelector('[role="status"]')?.textContent).toBe('保存して提出しました。');
    expect(document.body.textContent).toContain('承認待ち');
    expect(window.location.pathname).toBe('/daily-reports/R901/edit');
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

    await renderDailyReportForm(currentUser);

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

    await renderDailyReportForm(currentUser);
    await click(buttonByText('下書き保存'));

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('日付ごとのエラーです。');
  });

  it('falls back to the API message when save error details are missing', async () => {
    installFrontendFetch({
      create: rejectWith({ message: 'APIメッセージ' }),
    });

    await renderDailyReportForm(currentUser);
    await click(buttonByText('下書き保存'));

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('APIメッセージ');
  });

  it('falls back to the generic save error when the API gives no usable details or message', async () => {
    installFrontendFetch({
      create: rejectWith({}),
    });

    await renderDailyReportForm(currentUser);
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

    await renderDailyReportForm(currentUser);
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
