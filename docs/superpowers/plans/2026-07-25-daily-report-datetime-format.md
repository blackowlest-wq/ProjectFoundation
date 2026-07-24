# 日報監査日時フォーマット Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 日報画面の提出・承認・差戻し日時を`YYYY-MM-DD HH:mm:ss`形式で表示する。

**Architecture:** `frontend/src/dailyReport/dateTimeFormat.ts`に表示専用の純粋関数を追加し、4つの画面コンポーネントから利用する。APIの`OffsetDateTime`文字列は変更せず、フォーマッタは元のISO文字列の日時部分を使い、ブラウザのタイムゾーン変換を行わない。

**Tech Stack:** React 19、TypeScript、Vitest、Vite。

## Global Constraints

- 表示形式は`YYYY-MM-DD HH:mm:ss`とする。
- `null`または空文字は`-`とする。
- ミリ秒は表示しない。
- API DTOとBackendの日時契約は変更しない。
- テストは`frontend/test`配下へ置き、テストレイアウト規約を維持する。

---

### Task 1: 共通日時フォーマッタの回帰テスト

**Files:**

- Create: `frontend/test/dailyReportDateTimeFormat.test.ts`
- Reference: `frontend/src/dailyReport/dateTimeFormat.ts`

**Interfaces:**

- Consumes: `formatDateTime(value: string | null): string`
- Produces: `YYYY-MM-DD HH:mm:ss`表示、null/空文字の`-`、不正値の安全なフォールバックを検証するテスト。

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from 'vitest';
import { formatDateTime } from '../src/dailyReport/dateTimeFormat';

describe('formatDateTime', () => {
  it('formats an ISO datetime without changing the source offset time', () => {
    expect(formatDateTime('2026-07-17T09:00:00+09:00')).toBe('2026-07-17 09:00:00');
  });

  it('removes milliseconds and renders missing values as a dash', () => {
    expect(formatDateTime('2026-07-17T09:00:00.123+09:00')).toBe('2026-07-17 09:00:00');
    expect(formatDateTime(null)).toBe('-');
    expect(formatDateTime('')).toBe('-');
  });

  it('preserves an unexpected non-empty value for diagnosis', () => {
    expect(formatDateTime('not-a-datetime')).toBe('not-a-datetime');
  });
});
```

- [ ] **Step 2: Run the formatter test and verify it fails**

Run: `npm.cmd test -- --run test/dailyReportDateTimeFormat.test.ts`

Expected: FAIL because `frontend/src/dailyReport/dateTimeFormat.ts` does not exist yet.

### Task 2: 共通日時フォーマッタの実装

**Files:**

- Create: `frontend/src/dailyReport/dateTimeFormat.ts`
- Test: `frontend/test/dailyReportDateTimeFormat.test.ts`

**Interfaces:**

- Consumes: ISO 8601日時文字列または`null`。
- Produces: `formatDateTime(value: string | null): string`。

- [ ] **Step 1: Implement the minimal formatter**

```ts
const isoDateTimePattern = /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;

export function formatDateTime(value: string | null): string {
  if (!value) {
    return '-';
  }
  const match = isoDateTimePattern.exec(value);
  return match ? `${match[1]} ${match[2]}` : value;
}
```

- [ ] **Step 2: Run the formatter test and verify it passes**

Run: `npm.cmd test -- --run test/dailyReportDateTimeFormat.test.ts`

Expected: 3 tests passed.

### Task 3: 各画面への適用と画面回帰テスト

**Files:**

- Modify: `frontend/src/dailyReport/DailyReportDetail.tsx`
- Modify: `frontend/src/dailyReport/DailyReportCalendarList.tsx`
- Modify: `frontend/src/dailyReport/DailyReportPendingApprovalList.tsx`
- Modify: `frontend/src/dailyReport/DailyReportForm.tsx`
- Modify: `frontend/test/dailyReportForm.test.tsx`
- Modify: `frontend/test/DailyReportApprovalPanel.test.tsx`
- Modify: `frontend/test/dailyReportCalendarList.test.tsx`

**Interfaces:**

- Consumes: `formatDateTime` from `./dateTimeFormat`。
- Produces: 4画面の日時表示が`YYYY-MM-DD HH:mm:ss`となり、nullは`-`のままになる。

- [ ] **Step 1: Update component tests to assert formatted output**

Use `2026-07-17T09:00:00+09:00` fixtures and assert `2026-07-17 09:00:00`. Keep existing null assertions for `-`.

- [ ] **Step 2: Run the affected UI tests and verify the regression assertions fail**

Run: `npm.cmd test -- --run test/dailyReportCalendarList.test.tsx test/dailyReportForm.test.tsx test/DailyReportApprovalPanel.test.tsx`

Expected: FAIL because the components still render raw ISO strings.

- [ ] **Step 3: Import and apply `formatDateTime` at every audit datetime render**

Replace direct render expressions as follows:

```tsx
<dd>{formatDateTime(report.submittedAt)}</dd>
<dd>{formatDateTime(report.approvedAt)}</dd>
<dd>{formatDateTime(report.rejectedAt)}</dd>
<dd>{formatDateTime(editor.rejectionDetails?.rejectedAt ?? null)}</dd>
<td>{formatDateTime(report.submittedAt)}</td>
```

- [ ] **Step 4: Run the affected UI tests and verify they pass**

Run: `npm.cmd test -- --run test/dailyReportCalendarList.test.tsx test/dailyReportForm.test.tsx test/DailyReportApprovalPanel.test.tsx test/dailyReportDateTimeFormat.test.ts`

Expected: all affected tests pass with no failures.

### Task 4: 品質ゲートと記録確認

**Files:**

- Verify: `docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md`
- Verify: `docs/AI活用開発研究/作業記録/日報登録編集_作業記録.md`

- [ ] **Step 1: Run test layout and full frontend unit tests**

Run: `npm.cmd test -- --run`

Expected: test layout passes and all frontend Unit tests pass.

- [ ] **Step 2: Run typecheck, lint, and build**

Run: `npm.cmd run typecheck; npm.cmd run lint; npm.cmd run build`

Expected: all three commands exit with code 0.

- [ ] **Step 3: Run diff checks and inspect the final diff**

Run: `git diff --check; git status --short; git diff --stat`

Expected: only the formatter, affected tests/components, and required work records are changed; no whitespace errors are reported.
