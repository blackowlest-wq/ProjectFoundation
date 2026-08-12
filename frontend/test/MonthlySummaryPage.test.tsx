// @vitest-environment jsdom

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { MonthlySummaryPage } from '../src/monthlySummary/MonthlySummaryPage';
import {
  adminUser,
  buttonByText,
  cleanupUi,
  click,
  flushEffects,
  keyDown,
  renderUi,
  setControlValue,
} from './support/monthlySummaryTestSupport';
import type { MonthlySummaryResponse } from '../src/monthlySummary/types';

const emptySummary: MonthlySummaryResponse = {
  yearMonth: '2026-08',
  employeeWorkSummaries: [],
  projectWorkSummaries: [],
  categoryWorkSummaries: [],
  holidayTypeSummaries: [],
};

const normalSummary: MonthlySummaryResponse = {
  yearMonth: '2026-06',
  employeeWorkSummaries: [
    { employeeId: 'E001', employeeName: '山田 太郎', totalWorkMinutes: 480 },
    { employeeId: 'E002', employeeName: '高橋 次郎', totalWorkMinutes: 360 },
  ],
  projectWorkSummaries: [
    { projectId: 'P001', projectName: 'プロジェクトA', totalWorkMinutes: 420 },
    { projectId: 'P002', projectName: 'プロジェクトB', totalWorkMinutes: 420 },
  ],
  categoryWorkSummaries: [
    { workCategoryId: 'WC001', workCategoryName: '設計', totalWorkMinutes: 540 },
    { workCategoryId: 'WC002', workCategoryName: '実装', totalWorkMinutes: 300 },
  ],
  holidayTypeSummaries: [
    { holidayType: 'WORKDAY', totalDays: 2 },
    { holidayType: 'PAID_LEAVE', totalDays: 1 },
  ],
};

vi.mock('../src/monthlySummary/monthlySummaryApi', () => ({
  getMonthlySummary: vi.fn(),
}));

describe('MonthlySummaryPage', () => {
  beforeEach(async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-08-12T09:00:00+09:00'));
    const { getMonthlySummary } = await import('../src/monthlySummary/monthlySummaryApi');
    vi.mocked(getMonthlySummary).mockResolvedValue(emptySummary);
  });

  afterEach(() => cleanupUi());

  it('RT-F011-FE-002 loads the local current month and exposes four aggregate tabs', async () => {
    const { getMonthlySummary } = await import('../src/monthlySummary/monthlySummaryApi');

    await renderUi(<MonthlySummaryPage user={adminUser} />);

    expect(document.querySelector('h1')?.textContent).toBe('月次集計');
    expect(document.querySelector<HTMLInputElement>('input[type="month"]')?.value).toBe('2026-08');
    expect(vi.mocked(getMonthlySummary)).toHaveBeenCalledWith('2026-08');
    expect(document.querySelectorAll('[role="tab"]')).toHaveLength(4);
    expect(document.querySelector('[role="tablist"]')).not.toBeNull();
  });

  it('RT-F011-FE-004 displays each aggregate with its independent literal values and overview', async () => {
    const { getMonthlySummary } = await import('../src/monthlySummary/monthlySummaryApi');
    vi.mocked(getMonthlySummary).mockResolvedValue(normalSummary);

    await renderUi(<MonthlySummaryPage user={adminUser} />);

    expect(document.body.textContent).toContain('対象社員2名');
    expect(document.body.textContent).toContain('総作業時間840分');
    expect(document.body.textContent).toContain('E001');
    expect(document.body.textContent).toContain('山田 太郎');
    expect(document.body.textContent).toContain('480');
    expect(document.body.textContent).toContain('E002');
    expect(document.body.textContent).toContain('高橋 次郎');
    expect(document.body.textContent).toContain('360');
    const assertPanelVisibility = (activeKey: string) => {
      const panels = Array.from(document.querySelectorAll<HTMLElement>('[role="tabpanel"]'));
      expect(panels.filter((panel) => !panel.hasAttribute('hidden'))).toHaveLength(1);
      for (const panel of panels) {
        expect(panel.hasAttribute('hidden')).toBe(panel.id !== `monthly-summary-panel-${activeKey}`);
      }
    };
    assertPanelVisibility('employees');
    expect(Array.from(document.querySelectorAll('[role="tabpanel"]:not([hidden]) tbody tr')).map((row) =>
      Array.from(row.querySelectorAll('td')).map((cell) => cell.textContent))).toEqual([
      ['E001', '山田 太郎', '480'],
      ['E002', '高橋 次郎', '360'],
    ]);

    await click(buttonByText('案件別'));
    expect(document.body.textContent).toContain('P001');
    expect(document.body.textContent).toContain('プロジェクトA');
    expect(document.body.textContent).toContain('P002');
    expect(document.body.textContent).toContain('プロジェクトB');
    expect(document.body.textContent).toContain('420');
    assertPanelVisibility('projects');
    expect(Array.from(document.querySelectorAll('[role="tabpanel"]:not([hidden]) tbody tr')).map((row) =>
      Array.from(row.querySelectorAll('td')).map((cell) => cell.textContent))).toEqual([
      ['P001', 'プロジェクトA', '420'],
      ['P002', 'プロジェクトB', '420'],
    ]);
    expect(document.querySelector('[role="tabpanel"]:not([hidden])')?.textContent).toContain('案件別作業時間');

    await click(buttonByText('作業分類別'));
    expect(document.body.textContent).toContain('WC001');
    expect(document.body.textContent).toContain('設計');
    expect(document.body.textContent).toContain('WC002');
    expect(document.body.textContent).toContain('実装');
    expect(document.body.textContent).toContain('540');
    expect(document.body.textContent).toContain('300');
    assertPanelVisibility('categories');
    expect(Array.from(document.querySelectorAll('[role="tabpanel"]:not([hidden]) tbody tr')).map((row) =>
      Array.from(row.querySelectorAll('td')).map((cell) => cell.textContent))).toEqual([
      ['WC001', '設計', '540'],
      ['WC002', '実装', '300'],
    ]);

    await click(buttonByText('休日区分別'));
    expect(document.body.textContent).toContain('PAID_LEAVE');
    expect(document.body.textContent).toContain('WORKDAY');
    expect(document.body.textContent).toContain('1');
    assertPanelVisibility('holidays');
    expect(Array.from(document.querySelectorAll('[role="tabpanel"]:not([hidden]) tbody tr')).map((row) =>
      Array.from(row.querySelectorAll('td')).map((cell) => cell.textContent))).toEqual([
      ['WORKDAY', '2'],
      ['PAID_LEAVE', '1'],
    ]);
    expect(document.querySelectorAll('[role="tabpanel"]')).toHaveLength(4);
    for (const tab of Array.from(document.querySelectorAll<HTMLButtonElement>('[role="tab"]'))) {
      const panel = document.getElementById(tab.getAttribute('aria-controls')!);
      expect(panel).not.toBeNull();
      expect(panel?.getAttribute('aria-labelledby')).toBe(tab.id);
      expect(panel?.hasAttribute('hidden')).toBe(tab.getAttribute('aria-selected') !== 'true');
    }
  });

  it('RT-F011-FE-005 shows zero overview and an empty state in every aggregate tab', async () => {
    const { getMonthlySummary } = await import('../src/monthlySummary/monthlySummaryApi');
    vi.mocked(getMonthlySummary).mockResolvedValue(emptySummary);

    await renderUi(<MonthlySummaryPage user={adminUser} />);

    expect(document.body.textContent).toContain('対象社員0名');
    expect(document.body.textContent).toContain('総作業時間0分');
    for (const tab of ['社員別', '案件別', '作業分類別', '休日区分別']) {
      await click(buttonByText(tab));
      expect(document.body.textContent).toContain('該当する集計データはありません。');
      expect(document.querySelectorAll('tbody tr')).toHaveLength(0);
    }
  });

  it('RT-F011-FE-006 clears the previous summary and shows a retryable business error', async () => {
    const { getMonthlySummary } = await import('../src/monthlySummary/monthlySummaryApi');
    vi.mocked(getMonthlySummary)
      .mockResolvedValueOnce(normalSummary)
      .mockRejectedValueOnce({ code: 'VALIDATION_ERROR', message: '対象年月が不正です。' });

    await renderUi(<MonthlySummaryPage user={adminUser} />);
    expect(document.body.textContent).toContain('E001');
    setControlValue(document.querySelector<HTMLInputElement>('input[type="month"]')!, '2026-07');
    await click(buttonByText('集計表示'));

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('対象年月が不正です。');
    expect(document.body.textContent).not.toContain('E001');
    expect(document.querySelector<HTMLInputElement>('input[type="month"]')?.value).toBe('2026-07');
  });

  it('RT-F011-FE-007 clears the previous summary and notifies the parent once on unauthorized', async () => {
    const { getMonthlySummary } = await import('../src/monthlySummary/monthlySummaryApi');
    const onUnauthorized = vi.fn();
    vi.mocked(getMonthlySummary)
      .mockResolvedValueOnce(normalSummary)
      .mockRejectedValueOnce({ code: 'UNAUTHORIZED', message: 'ログインが必要です。' });

    await renderUi(<MonthlySummaryPage user={adminUser} onUnauthorized={onUnauthorized} />);
    setControlValue(document.querySelector<HTMLInputElement>('input[type="month"]')!, '2026-07');
    await click(buttonByText('集計表示'));

    expect(onUnauthorized).toHaveBeenCalledTimes(1);
    expect(document.body.textContent).not.toContain('E001');
  });

  it('RT-F011-FE-009 uses the local month at a Japan midnight boundary', async () => {
    const { getMonthlySummary } = await import('../src/monthlySummary/monthlySummaryApi');
    vi.setSystemTime(new Date('2027-01-01T00:30:00+09:00'));
    vi.mocked(getMonthlySummary).mockResolvedValue({ ...emptySummary, yearMonth: '2027-01' });

    await renderUi(<MonthlySummaryPage user={adminUser} />);

    expect(document.querySelector<HTMLInputElement>('input[type="month"]')?.value).toBe('2027-01');
    expect(vi.mocked(getMonthlySummary)).toHaveBeenCalledWith('2027-01');
  });

  it('RT-F011-FE-010 keeps the newer month when an older request resolves late', async () => {
    const { getMonthlySummary } = await import('../src/monthlySummary/monthlySummaryApi');
    let resolveAugust!: (value: MonthlySummaryResponse) => void;
    let resolveJune!: (value: MonthlySummaryResponse) => void;
    vi.mocked(getMonthlySummary).mockImplementation((yearMonth) => {
      if (yearMonth === '2026-08') {
        return new Promise((resolve) => { resolveAugust = resolve; });
      }
      return new Promise((resolve) => { resolveJune = resolve; });
    });

    await renderUi(<MonthlySummaryPage user={adminUser} />);
    setControlValue(document.querySelector<HTMLInputElement>('input[type="month"]')!, '2026-06');
    await click(buttonByText('集計表示'));
    await act(async () => {
      resolveJune(normalSummary);
      await Promise.resolve();
    });
    await flushEffects();
    expect(document.body.textContent).toContain('E001');
    await act(async () => {
      resolveAugust({ ...emptySummary, yearMonth: '2026-08' });
      await Promise.resolve();
    });
    await flushEffects();
    expect(document.querySelector<HTMLInputElement>('input[type="month"]')?.value).toBe('2026-06');
    expect(document.body.textContent).toContain('E001');
  });

  it('RT-F011-FE-011 supports automatic tab selection and left/right keyboard movement', async () => {
    const { getMonthlySummary } = await import('../src/monthlySummary/monthlySummaryApi');
    vi.mocked(getMonthlySummary).mockResolvedValue(normalSummary);

    await renderUi(<MonthlySummaryPage user={adminUser} />);
    const employeeTab = buttonByText('社員別');
    expect(employeeTab.getAttribute('aria-selected')).toBe('true');
    expect(employeeTab.getAttribute('aria-controls')).toBe('monthly-summary-panel-employees');

    await keyDown(employeeTab, 'ArrowRight');
    expect(buttonByText('案件別').getAttribute('aria-selected')).toBe('true');
    expect(document.activeElement).toBe(buttonByText('案件別'));
    await keyDown(buttonByText('案件別'), 'ArrowLeft');
    expect(employeeTab.getAttribute('aria-selected')).toBe('true');
    expect(document.activeElement).toBe(employeeTab);
  });
});
