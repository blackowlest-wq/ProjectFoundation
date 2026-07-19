import { act, type ReactNode } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { vi } from 'vitest';
import type { CurrentUser } from '../../src/auth/types';
import type {
  DailyReportListItem,
  DailyReportResponse,
  HolidayTypeOption,
  ProjectOption,
  WorkCategoryOption,
} from '../../src/dailyReport/types';

export const currentUser: CurrentUser = {
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

export const managerUser: CurrentUser = {
  ...currentUser,
  role: 'MANAGER',
};

export const adminUser: CurrentUser = {
  ...currentUser,
  role: 'ADMIN',
};

export const fallbackUser: CurrentUser = {
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
  | Promise<Response>
  | Response
  | { kind: 'json'; body: unknown; init?: ResponseInit }
  | { kind: 'throw'; error: unknown };

export type FetchScenario = {
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

export function jsonResponse(body: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
    ...init,
  });
}

export function respondJson(body: unknown, init: ResponseInit = {}): StubResult {
  return { kind: 'json', body, init };
}

export function rejectWith(error: unknown): StubResult {
  return { kind: 'throw', error };
}

export function buildReportDetail(reportId: string, overrides: Partial<DailyReportResponse> = {}): DailyReportResponse {
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
    approverId: null,
    approverName: null,
    approvedAt: null,
    rejectorId: null,
    rejectorName: null,
    rejectedAt: null,
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

export function buildListItem(reportId: string, overrides: Partial<DailyReportListItem> = {}): DailyReportListItem {
  const detail = buildReportDetail(reportId);
  return {
    ...detail,
    approverId: null,
    approverName: null,
    approvedAt: null,
    rejected: false,
    ...overrides,
  };
}

function toPromise(result: StubResult): Promise<Response> {
  if (result instanceof Promise) {
    return result;
  }
  if (result instanceof Response) {
    return Promise.resolve(result);
  }
  if (result.kind === 'throw') {
    return Promise.reject(result.error);
  }
  return Promise.resolve(jsonResponse(result.body, result.init));
}

export function installFrontendFetch(scenario: FetchScenario = {}) {
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

export async function flushEffects(turns = 6) {
  await act(async () => {
    for (let index = 0; index < turns; index += 1) {
      await Promise.resolve();
    }
  });
}

export async function renderUi(ui: ReactNode) {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () => {
    root?.render(<>{ui}</>);
    await Promise.resolve();
  });
  await flushEffects();
}

export function cleanupUi() {
  act(() => {
    root?.unmount();
  });
  container?.remove();
  root = null;
  container = null;
  vi.restoreAllMocks();
  vi.useRealTimers();
  window.history.replaceState(null, '', '/login');
}

export function labelByText(labelText: string): HTMLLabelElement {
  const label = Array.from(document.querySelectorAll('label'))
    .find((candidate) => candidate.textContent?.includes(labelText));
  if (!label) {
    throw new Error(`Label not found: ${labelText}`);
  }
  return label as HTMLLabelElement;
}

export function controlByLabel<T extends HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>(labelText: string): T {
  const control = labelByText(labelText).querySelector('input, select, textarea');
  if (!control) {
    throw new Error(`Control not found: ${labelText}`);
  }
  return control as T;
}

export function setControlValue(control: HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement, value: string) {
  act(() => {
    const prototype = control instanceof HTMLSelectElement
      ? HTMLSelectElement.prototype
      : control instanceof HTMLTextAreaElement
        ? HTMLTextAreaElement.prototype
        : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;
    setter?.call(control, value);
    control.dispatchEvent(new Event('input', { bubbles: true }));
    control.dispatchEvent(new Event('change', { bubbles: true }));
  });
}

export function inputByLabel(labelText: string): HTMLInputElement {
  return controlByLabel<HTMLInputElement>(labelText);
}

export function buttonByText(labelText: string): HTMLButtonElement {
  const button = Array.from(document.querySelectorAll('button'))
    .find((candidate) => candidate.textContent?.includes(labelText));
  if (!button) {
    throw new Error(`Button not found: ${labelText}`);
  }
  return button as HTMLButtonElement;
}

export async function click(element: Element | null) {
  if (!element) {
    throw new Error('Element not found');
  }
  await act(async () => {
    element.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    await Promise.resolve();
  });
  await flushEffects();
}

export async function submitLogin(loginIdValue: string, passwordValue: string) {
  setControlValue(inputByLabel('ログインID'), loginIdValue);
  setControlValue(inputByLabel('パスワード'), passwordValue);
  await click(buttonByText('ログイン'));
}

export function countRequests(calls: Array<{ method: string; url: URL }>, method: string, path: string) {
  return calls.filter((call) => call.method === method && call.url.pathname === path).length;
}
