# 日報編集画面 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** S-004日報編集画面で、差戻し情報表示、状態別操作制御、詳細読込中・失敗後の安全側制御を実現する。

**Architecture:** 既存の`DailyReportForm`、APIクライアント、フォーム入力DTOを維持し、詳細レスポンスの差戻し監査項目を型と画面状態へ追加する。編集可能状態を`DRAFT`/`REJECTED`に限定し、`DRAFT`はsubmit、`REJECTED`はresubmitだけへ分岐する。バックエンドの認可・入力検証・状態整合性を正とし、フロントは利用者補助と誤操作防止を担う。

**Tech Stack:** React 19, TypeScript, Vitest, Playwright, Vite

## Global Constraints

- S-004対象はF-003日報編集、F-006日報提出、F-009日報再提出の編集画面起点とする。
- `DRAFT`の「保存して提出」はPUT後に初回提出APIだけを呼ぶ。
- `REJECTED`の「保存して提出」はPUT後に再提出APIだけを呼び、初回提出APIを呼ばない。
- `PENDING`/`APPROVED`では入力、明細追加・更新・削除、保存、提出をすべて無効化する。
- 詳細取得中または失敗後は既存日報の初期値を保存せず、更新系APIを呼ばない。
- `rejectComment`、`rejectorName`、`rejectedAt`がnullの場合は各項目を`-`で表示する。
- 新規API、DB/DDL、ルーティングライブラリ、承認・差戻し画面は追加しない。
- AC/TC/RT/FINDのIDを再利用せず、実装したテストへ`RT-DRE-*`を割り当てる。
- 各実装タスクは、テストを先に追加して期待された失敗を確認してから本体コードを変更する。

---

### Task 1: 状態別編集・差戻し情報の失敗テスト

**Files:**

- Modify: `frontend/test/App.test.tsx`
- Reference: `docs/AI活用開発研究/作業記録/日報登録編集_テストケース.md`（TC-DRE-001、TC-DRE-003～007、TC-DRE-009～010）

**Interfaces:**

- Consumes: 既存の`installFrontendFetch`、`buildReportDetail`、`renderDailyReportForm`、`countRequests`、`controlByLabel`、`buttonByText`
- Produces: `DailyReportForm`の状態別操作と差戻し情報を検証するUnitテスト

- [x] **Step 1: Write the failing tests**

  `DailyReportForm behavior from task-owned tests`に以下を追加する。

  - `REJECTED`詳細に`rejectorName: '佐藤 上長'`、`rejectedAt: '2026-07-16T17:30:00+09:00'`、`rejectComment: '詳細を追記してください。'`を与え、3項目の表示、保存成功後の`REJECTED`維持、再提出時に`/submit`を呼ばず`/resubmit`だけを呼ぶことを確認する。
  - 差戻し3項目がnullの場合、3項目が`-`になることを確認する。
  - `PENDING`と`APPROVED`をparameterized testで描画し、日付、休日区分、時刻、備考、明細のselect/input/button、保存、提出がdisabledで、PUT/POSTの件数が0であることを確認する。

- [x] **Step 2: Run the focused tests to verify RED**

  Run: `npm.cmd test -- --run test/App.test.tsx`

  Expected: 既存テストは成功し、新規TC-DRE-001、003～005、009～010相当のテストが、差戻し項目未表示または操作が有効なため失敗する。失敗が型エラーの場合は、テストfixture側で詳細レスポンスの追加項目をintersection型として保持し、機能未実装による失敗へ直す。

- [x] **Step 3: Do not modify production code in this task**

  RED確認後、本タスクでは`frontend/src`を変更せず、失敗テストと実テストIDを作業記録へ記録する。

- [x] **Step 4: Record the test IDs**

  `RT-DRE-UNIT-001`～`RT-DRE-UNIT-005`、`RT-DRE-UNIT-009`、`RT-DRE-UNIT-010`をテスト名へ対応付け、ケース表へ実行結果未実施として記録する。

---

### Task 2: E2Eの状態別画面ケース

**Files:**

- Modify: `frontend/e2e/support/dailyReportMocks.ts`
- Modify: `frontend/e2e/daily-report.spec.ts`
- Test reference: TC-DRE-011～014

**Interfaces:**

- Consumes: 既存`DailyReportForm`、`mockDailyReportApis`、`gotoWithRetry`、`mockStaticFrontend`
- Produces: Mock E2EでのDRAFT提出、REJECTED再提出、PENDING/APPROVED編集不可の確認

- [x] **Step 1: Add the failing E2E cases and route state fixtures**

  モック詳細に`rejectorName`、`rejectedAt`、`PENDING`、`APPROVED`の状態を追加し、以下のspecを追加する。

  - `employee can edit a rejected report and resubmit without calling initial submit`: 差戻し3項目、備考変更、再提出成功、初回提出リクエストが0件。
  - `pending report edit screen disables every mutation control`: 全input/select/buttonがdisabled、PUT/POSTが0件。
  - `approved report edit screen disables every mutation control`: 同上。

- [x] **Step 2: Run the focused E2E cases to verify RED**

  Run: `npm.cmd exec playwright test e2e/daily-report.spec.ts -g "rejected report|pending report|approved report"`

  Expected: 既存E2Eの起動は成功し、新規ケースが差戻し項目未表示または操作可能のため失敗する。

- [x] **Step 3: Record the E2E test IDs before implementation**

  `RT-DRE-E2E-007`～`RT-DRE-E2E-009`をspec名へ対応付け、ケース表へ実装前RED結果を記録する。

---

### Task 3: 詳細読込状態と状態別操作制御の最小実装

**Files:**

- Modify: `frontend/src/dailyReport/types.ts`
- Modify: `frontend/src/dailyReport/DailyReportForm.tsx`
- Test: `frontend/test/App.test.tsx`

**Interfaces:**

- Consumes: Task 1の失敗テスト、既存`DailyReportResponse`、`fetchDailyReport`、`updateDailyReport`、`submitDailyReport`、`resubmitDailyReport`
- Produces: `rejectorName`/`rejectedAt`を含む詳細型、詳細取得状態、状態別disabled制御、差戻し表示

- [x] **Step 1: Add only the type fields needed by the failing tests**

  `DailyReportResponse`へ次を追加する。

  ```ts
  rejectorName: string | null;
  rejectedAt: string | null;
  ```

- [x] **Step 2: Add loading/error state and verify the new tests remain RED**

  `useDailyReportEditor`へ`reportLoading`と`reportLoadFailed`を追加し、編集URLで詳細取得を開始した時点で`reportLoading=true`、成功時にfalse、失敗時にfalseかつ`reportLoadFailed=true`とする。まだUIのdisabled制御は追加しない。

  Run: `npm.cmd test -- --run test/App.test.tsx`

  Expected: 型エラーは解消し、新規テストは操作可能または差戻し情報未表示のためREDのまま。

- [x] **Step 3: Implement the minimal editability predicate**

  `DailyReportForm.tsx`へ次の契約を追加する。

  ```ts
  const canEdit = !editor.reportId || (!editor.reportLoading && !editor.reportLoadFailed
    && (editor.status === 'DRAFT' || editor.status === 'REJECTED'));
  const controlsDisabled = Boolean(editor.reportId) && !canEdit;
  ```

  `controlsDisabled`を日付、休日区分、時刻、備考、`WorkItemsEditor`、保存、提出へ渡す。`WorkItemsEditor`のselect、明細時間input、削除button、追加buttonを同じdisabled契約で無効化する。

- [x] **Step 4: Implement rejection display and submission routing**

  `REJECTED`の時だけ差戻し情報を表示し、null値を`-`へ変換する。`saveAndSubmit`は保存結果の`approvalStatus`で既存どおり分岐し、`REJECTED`の場合は`resubmitDailyReport`だけを呼ぶ。`DRAFT`の場合は`submitDailyReport`だけを呼ぶ。

- [x] **Step 5: Run focused tests to verify GREEN**

  Run: `npm.cmd test -- --run test/App.test.tsx`

  Expected: Task 1の新規テストを含むAppテストが全件成功する。失敗時は本体コードを修正し、テスト期待値を緩めない。

- [x] **Step 6: Run typecheck and lint**

  Run: `npm.cmd run typecheck` and `npm.cmd run lint`

  Expected: TypeScriptエラー、ESLint warningともに0件。

- [x] **Step 7: Run the E2E cases written in Task 2**

  Run: `npm.cmd exec playwright test e2e/daily-report.spec.ts -g "rejected report|pending report|approved report"`

  Expected: `RT-DRE-E2E-007`～`RT-DRE-E2E-009`が成功し、差戻し画面の再提出は初回提出APIを呼ばない。

---

### Task 4: 実装後の自己確認と記録更新

**Files:**

- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_作業記録.md`
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_テストケース.md`
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md`
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_テストケース品質レビュー_2026-07-18.md`

- [x] **Step 1: Run the focused regression set**

  Run: `npm.cmd test -- --run`, `npm.cmd run typecheck`, `npm.cmd run lint`, `npm.cmd run build`, and the focused E2E command from Task 2.

  Expected: 既存テストを含む全Frontend検証が成功する。

- [x] **Step 2: Record actual test IDs and evidence**

  `RT-DRE-UNIT-*`/`RT-DRE-E2E-*`へ実際のテスト名、コマンド、日時、結果を追記し、TCの判定を実装後結果へ更新する。未実行のAPI/Oracleケースは理由と再確認条件を残す。

- [x] **Step 3: Record findings and standardization decisions**

  追加指摘ごとに`FIND-DRE-*`、AC/TC/RT、対応状況、修正ファイル、標準化判定、反映先、保留理由、再確認条件を記録する。

---

## Pre-Review Verification

実装後レビューの前に、以下を実行する。ここでのFullはレビュー前のベースラインとして記録し、最終Fullとは区別する。

1. `scripts/check.ps1 -Mode Doctor`
2. `scripts/check.ps1 -Mode Full`
3. `frontend` coverage
4. Mock E2E
5. Oracle/Backend coverage/E2Eは接続条件を確認し、実行できない場合は理由と再確認条件を記録

## Post-Review Final Gate

観点別専門レビュー（設計、テスト不足、期待結果、トレーサビリティ、必要時のセキュリティ・配置・CI）を独立実行し、統合レビューで全指摘を判定する。指摘修正後に、対象テスト、typecheck、lint、build、Mock E2E、coverage、必要なOracle確認、Markdownlint、`git diff --check`を再実行し、作業記録・指摘一覧・レビュー記録・正本ケース・受入条件レビューを揃える。
