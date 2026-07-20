# Frontend Test Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 日報一覧・日報編集フォームのUIテストを責務別ファイルへ分割し、テスト同士の変更衝突を減らす。

**Architecture:** `frontend/test/App.test.tsx`には認証・画面遷移のテストだけを残す。日報一覧と編集フォームのUIテストはそれぞれ専用specへ移し、共通fixture・fetch stub・DOM helperは`frontend/test/support/dailyReportTestSupport.tsx`へ集約する。実装コードとE2Eの挙動は変更しない。

**Tech Stack:** React 19、TypeScript、Vitest、jsdom、既存のFrontend test layout check

**Test responsibility matrix:**

| File | Responsibility | Layer | Decision |
| --- | --- | --- | --- |
| `frontend/test/App.test.tsx` | Authentication and route transitions | Frontend UI/Unit | Keep authentication tests only |
| `frontend/test/dailyReportCalendarList.test.tsx` | Daily report calendar-list behavior | Frontend UI/Unit | Split from `App.test.tsx` |
| `frontend/test/dailyReportForm.test.tsx` | Daily report create/edit behavior | Frontend UI/Unit | Split from `App.test.tsx` |
| `frontend/test/support/dailyReportTestSupport.tsx` | Shared fixtures, fetch stubs, and DOM helpers | Test support | Centralize shared setup |

## Global Constraints

- テストは`frontend/test`、E2Eは`frontend/e2e`に配置する。
- テスト名、期待値、アサーション、fixture、mock応答は分割前後で維持する。
- 本番ソース、API契約、E2E specは変更しない。
- 移動後もテストは既存のVitestコマンドとtest layout checkで実行できること。

---

### Task 1: Baseline and test support boundary

**Files:**

- Read: `frontend/test/App.test.tsx`
- Read: `frontend/package.json`
- Read: `docs/AI活用開発研究/構想メモ/標準化/テスト方針.md`

- [ ] **Step 1: Run the current focused UI test baseline**

Run: `npm.cmd test -- --run test/App.test.tsx`

Expected: existing UI tests pass before files are moved.

- [ ] **Step 2: Define shared support responsibility**

Keep only reusable daily-report fixtures, fetch stubs, rendering/cleanup helpers, and DOM query helpers in `frontend/test/support/dailyReportTestSupport.tsx`.

### Task 2: Split the UI test files

**Files:**

- Create: `frontend/test/support/dailyReportTestSupport.tsx`
- Create: `frontend/test/dailyReportCalendarList.test.tsx`
- Create: `frontend/test/dailyReportForm.test.tsx`
- Modify: `frontend/test/App.test.tsx`

- [ ] **Step 1: Move calendar-list tests**

Move the `DailyReportCalendarList behavior from task-owned tests` suite without changing test names, assertions, or fetch scenarios.

- [ ] **Step 2: Move form tests**

Move the `DailyReportForm behavior from task-owned tests` suite without changing test names, assertions, or fetch scenarios.

- [ ] **Step 3: Keep App authentication tests isolated**

Leave the `App authentication state` suite in `App.test.tsx` and update only its imports/helper calls to use the shared support module.

### Task 3: Verify the split

**Files:**

- Test: `frontend/test/App.test.tsx`
- Test: `frontend/test/dailyReportCalendarList.test.tsx`
- Test: `frontend/test/dailyReportForm.test.tsx`
- Test: `frontend/test/support/dailyReportTestSupport.tsx`

- [ ] **Step 1: Run the split UI tests**

Run: `npm.cmd test -- --run test/App.test.tsx test/dailyReportCalendarList.test.tsx test/dailyReportForm.test.tsx`

Expected: all moved tests pass.

- [ ] **Step 2: Run all Frontend unit tests and layout check**

Run: `npm.cmd test -- --run`

Expected: all Frontend unit tests and `check:test-layout` pass.

- [ ] **Step 3: Run typecheck and lint**

Run: `npm.cmd run typecheck` and `npm.cmd run lint`

Expected: both commands pass with no new warnings.
