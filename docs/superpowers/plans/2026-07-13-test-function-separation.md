# テストと機能コードの責務分離 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 日報機能の検索・登録更新・提出を Controller、Service、テストクラス単位で分離し、フロントエンドのテスト配置と再発防止チェックを整える。

**Architecture:** 日報 API の既存 URL と DTO 契約を維持したまま、検索・詳細、登録・更新、提出・再提出の3つの Controller / Service 組へ分ける。社員操作や詳細参照可否は `DailyReportAccessPolicy` に集約し、テスト準備処理は `src/test` 配下の共通補助へ移す。フロントの検索ヘルパーテストは `frontend/test` へ移動し、PowerShell のレイアウトチェックをテスト実行前に通す。

**Tech Stack:** Java 21、Spring Boot 3.3.6、Spring MVC、Spring Data JPA、JUnit Jupiter、MockMvc、Maven、TypeScript 5.6.3、React 19、Vite 5.4.11、Vitest 4.1.9、PowerShell。

## Global Constraints

- API URL、HTTP メソッド、DTO、Entity、Repository、レスポンス形式を変更しない。
- 業務ルール、入力チェック、認証認可、CSRF、状態遷移、DB更新順序を変更しない。
- 既存テストのテストケース、期待値、describe/test 名、アサーションは変更しない。
- フロント `frontend/src` に `*.test.*` / `*.spec.*` を置かない。
- バックエンド `backend/src/main` にテストクラスを置かない。
- 既存 `.github/workflows/oracle.yml` の品質ハーネス全体は再設計しない。
- 日本語資料は PowerShell で `-Encoding UTF8` を指定して読む・更新する。
- 実装前に確認した公式資料: Spring MVC Handler Methods、Spring `@Transactional`、Vitest Configuration。

---

## File Map

### Create

- `scripts/check-test-layout.ps1`: フロント本体配下とバックエンド本体配下へのテスト誤配置を検出する品質ゲート。
- `backend/src/test/java/com/example/dailyreport/report/DailyReportSeparationTest.java`: 分割後の Controller / Service Bean と旧混在 Bean の存在を確認する構造保護テスト。
- `backend/src/main/java/com/example/dailyreport/report/DailyReportAccessPolicy.java`: 日報機能で共通する社員限定操作、詳細参照可否、上長担当グループ判定。
- `backend/src/main/java/com/example/dailyreport/report/DailyReportSearchService.java`: 日報一覧検索と詳細取得。
- `backend/src/main/java/com/example/dailyreport/report/DailyReportCommandService.java`: 日報登録と更新。
- `backend/src/main/java/com/example/dailyreport/report/DailyReportSubmissionService.java`: 日報提出と再提出。
- `backend/src/main/java/com/example/dailyreport/report/controller/DailyReportSearchController.java`: 検索・詳細 GET API。
- `backend/src/main/java/com/example/dailyreport/report/controller/DailyReportCommandController.java`: 登録 POST と更新 PUT API。
- `backend/src/main/java/com/example/dailyreport/report/controller/DailyReportSubmissionController.java`: 提出・再提出 POST API。
- `backend/src/test/java/com/example/dailyreport/support/MockMvcTestSupport.java`: ログイン処理の共通テスト補助。
- `backend/src/test/java/com/example/dailyreport/report/support/DailyReportTestSupport.java`: 日報作成、JSON生成、DBシードの共通テスト補助。
- `backend/src/test/java/com/example/dailyreport/report/DailyReportSearchControllerTest.java`: 検索・詳細 API の既存テスト移設先。
- `backend/src/test/java/com/example/dailyreport/report/DailyReportCommandControllerTest.java`: 登録・更新 API の既存テスト移設先。
- `backend/src/test/java/com/example/dailyreport/report/DailyReportSubmissionControllerTest.java`: 提出・再提出 API の既存テスト移設先。
- `backend/src/test/java/com/example/dailyreport/master/MasterControllerTest.java`: マスタ API の既存テスト移設先。
- `frontend/test/dailyReportSearch.test.ts`: `src` 配下から移動する既存テスト。

### Modify

- `frontend/package.json`: レイアウトチェック、`pretest`、`precoverage` を追加する。
- `docs/AI活用開発研究/構想メモ/標準化/ディレクトリ構成ルール.md`: テスト配置とユースケース単位分割を明文化する。
- `docs/AI活用開発研究/構想メモ/標準化/実装前確認観点.md`: 実装前に本体・テスト配置と分割単位を確認する行を追加する。
- `docs/AI活用開発研究/構想メモ/標準化/実装後レビュー観点.md`: 実装後の責務分離とテスト配置確認を追加する。
- `docs/AI活用開発研究/構想メモ/標準化/テスト方針.md`: テストファイル配置とユースケース別テストクラスの方針を追加する。
- `docs/AI活用開発研究/作業記録/日報登録編集_作業記録.md`: 2026-07-13 の変更内容と検証結果を追記する。
- `docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md`: 今回のファイル配置・責務分離指摘を `DR-F-009` として対応済みに記録する。

### Delete

- `backend/src/main/java/com/example/dailyreport/report/DailyReportService.java`: 3つの新 Service へ責務を移した後に削除する。
- `backend/src/main/java/com/example/dailyreport/report/controller/DailyReportController.java`: 3つの新 Controller へルートを移した後に削除する。
- `backend/src/test/java/com/example/dailyreport/report/DailyReportControllerTest.java`: 4つの機能別テストクラスへ移設した後に削除する。
- `frontend/src/dailyReport/dailyReportSearch.test.ts`: `frontend/test` への移動後に削除する。

---

### Task 1: レイアウトチェックを追加し、現状の違反をREDで確認する

**Files:**

- Create: `scripts/check-test-layout.ps1`
- Modify: `frontend/package.json`

**Interfaces:**

- Produces: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-test-layout.ps1` が、`frontend/src` 内の `*.test.*` / `*.spec.*` と `backend/src/main` 内の `*Test.java` / `*IT.java` を検出した場合に終了コード1を返す。
- Produces: `npm.cmd test` と `npm.cmd run coverage` の前処理で同じレイアウトチェックを実行する。

- [ ] **Step 1: レイアウトチェックを追加する**

  `scripts/check-test-layout.ps1` は次の判定を実装する。

  ```powershell
  [CmdletBinding()]
  param(
      [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
  )

  $violations = @()
  $frontendSource = Join-Path $ProjectRoot 'frontend\src'
  $backendMain = Join-Path $ProjectRoot 'backend\src\main'

  if (Test-Path -LiteralPath $frontendSource) {
      $violations += Get-ChildItem -LiteralPath $frontendSource -Recurse -File |
          Where-Object { $_.Name -match '\.(test|spec)\.[^.]+$' } |
          ForEach-Object { "frontend/src test file: $($_.FullName)" }
  }

  if (Test-Path -LiteralPath $backendMain) {
      $violations += Get-ChildItem -LiteralPath $backendMain -Recurse -File |
          Where-Object { $_.Name -match '(Test|IT)\.java$' } |
          ForEach-Object { "backend/src/main test file: $($_.FullName)" }
  }

  if ($violations.Count -gt 0) {
      Write-Error ("Test files must be placed under the test source directories:`n" + ($violations -join "`n"))
      exit 1
  }

  Write-Output 'Test layout check passed.'
  ```

- [ ] **Step 2: フロントテスト実行前にチェックを接続する**

  `frontend/package.json` の scripts に次を追加する。

  ```json
  "check:test-layout": "powershell -NoProfile -ExecutionPolicy Bypass -File ../scripts/check-test-layout.ps1",
  "pretest": "npm run check:test-layout",
  "precoverage": "npm run check:test-layout"
  ```

- [ ] **Step 3: REDを確認する**

  Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-test-layout.ps1`

  Expected: `frontend/src/dailyReport/dailyReportSearch.test.ts` が検出され、終了コード1になる。これは既存の誤配置を検知できることを確認するための期待された失敗である。

- [ ] **Step 4: 変更を確認する**

  Run: `git diff --check -- scripts/check-test-layout.ps1 frontend/package.json`

  Expected: 空の出力で終了コード0。

- [ ] **Step 5: Commit**

  ```powershell
  git add -- scripts/check-test-layout.ps1 frontend/package.json
  git commit -m "test: guard source and test file separation"
  ```

### Task 2: フロントエンドの既存テストをテスト専用ディレクトリへ移動する

**Files:**

- Move: `frontend/src/dailyReport/dailyReportSearch.test.ts` -> `frontend/test/dailyReportSearch.test.ts`

**Interfaces:**

- Consumes: Task 1 のレイアウトチェック。
- Produces: 既存の6テストケースを同じ内容で `frontend/test` から実行できる状態。

- [ ] **Step 1: テストファイルを移動し、実装 import だけ更新する**

  テスト本文の describe/test 名、期待値、アサーションは保持し、import を次の形へ変更する。

  ```ts
  import {
    buildDailyReportSearchUrl,
    monthRange,
    validateDailyReportSearch,
  } from '../src/dailyReport/dailyReportSearch';
  ```

- [ ] **Step 2: レイアウトチェックをGREENで確認する**

  Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-test-layout.ps1`

  Expected: `Test layout check passed.`、終了コード0。

- [ ] **Step 3: フロント既存テストを実行する**

  Run: `npm.cmd test -- --run` (workdir: `frontend`)

  Expected: 既存フロントテストが全件成功し、移動前後でテストケース数が減らない。

- [ ] **Step 4: 移動差分を確認する**

  Run: `git diff --find-renames -- frontend/src/dailyReport/dailyReportSearch.test.ts frontend/test/dailyReportSearch.test.ts`

  Expected: ファイル移動と実装 import の相対パス変更以外のテスト内容差分がない。

- [ ] **Step 5: Commit**

  ```powershell
  git add -- frontend/src/dailyReport/dailyReportSearch.test.ts frontend/test/dailyReportSearch.test.ts
  git commit -m "test: move daily report search tests out of source"
  ```

### Task 3: 分割後のバックエンド Bean を検証する保護テストを先に追加する

**Files:**

- Create: `backend/src/test/java/com/example/dailyreport/report/DailyReportSeparationTest.java`

**Interfaces:**

- Produces: 分割後に `dailyReportSearchController`、`dailyReportCommandController`、`dailyReportSubmissionController`、`dailyReportSearchService`、`dailyReportCommandService`、`dailyReportSubmissionService`、`dailyReportAccessPolicy` が存在し、`dailyReportController` と `dailyReportService` が存在しないことを確認するテスト。

- [ ] **Step 1: 失敗する構造テストを書く**

  ```java
  package com.example.dailyreport.report;

  import static org.assertj.core.api.Assertions.assertThat;

  import org.junit.jupiter.api.Test;
  import org.springframework.beans.factory.annotation.Autowired;
  import org.springframework.boot.test.context.SpringBootTest;
  import org.springframework.context.ApplicationContext;
  import org.springframework.test.context.ActiveProfiles;

  @SpringBootTest
  @ActiveProfiles("test")
  class DailyReportSeparationTest {
      @Autowired
      ApplicationContext applicationContext;

      @Test
      void separatedUseCaseBeansReplaceMixedDailyReportBeans() {
          assertThat(applicationContext.containsBean("dailyReportSearchController")).isTrue();
          assertThat(applicationContext.containsBean("dailyReportCommandController")).isTrue();
          assertThat(applicationContext.containsBean("dailyReportSubmissionController")).isTrue();
          assertThat(applicationContext.containsBean("dailyReportSearchService")).isTrue();
          assertThat(applicationContext.containsBean("dailyReportCommandService")).isTrue();
          assertThat(applicationContext.containsBean("dailyReportSubmissionService")).isTrue();
          assertThat(applicationContext.containsBean("dailyReportAccessPolicy")).isTrue();
          assertThat(applicationContext.containsBean("dailyReportController")).isFalse();
          assertThat(applicationContext.containsBean("dailyReportService")).isFalse();
      }
  }
  ```

- [ ] **Step 2: REDを確認する**

  Run: `mvn.cmd -s local-maven-settings.xml -o -Dtest=DailyReportSeparationTest test` (workdir: `backend`)

  Expected: 新しい Bean がまだないため `separatedUseCaseBeansReplaceMixedDailyReportBeans` が失敗する。テストコンパイルエラーではなく、旧 Bean 構成との差分によるアサーション失敗であることを確認する。

- [ ] **Step 3: Commit**

  ```powershell
  git add -- backend/src/test/java/com/example/dailyreport/report/DailyReportSeparationTest.java
  git commit -m "test: protect daily report use case boundaries"
  ```

### Task 4: バックエンド本体を検索・登録更新・提出単位へ分割する

**Files:**

- Create: `backend/src/main/java/com/example/dailyreport/report/DailyReportAccessPolicy.java`
- Create: `backend/src/main/java/com/example/dailyreport/report/DailyReportSearchService.java`
- Create: `backend/src/main/java/com/example/dailyreport/report/DailyReportCommandService.java`
- Create: `backend/src/main/java/com/example/dailyreport/report/DailyReportSubmissionService.java`
- Create: `backend/src/main/java/com/example/dailyreport/report/controller/DailyReportSearchController.java`
- Create: `backend/src/main/java/com/example/dailyreport/report/controller/DailyReportCommandController.java`
- Create: `backend/src/main/java/com/example/dailyreport/report/controller/DailyReportSubmissionController.java`
- Delete: `backend/src/main/java/com/example/dailyreport/report/DailyReportService.java`
- Delete: `backend/src/main/java/com/example/dailyreport/report/controller/DailyReportController.java`

**Interfaces:**

- `DailyReportSearchService.search(LocalDate dateFrom, LocalDate dateTo, String groupId, String employeeId, ApprovalStatus status, String holidayType, AuthenticatedUser principal)` returns `List<DailyReportListItemResponse>`.
- `DailyReportSearchService.get(String reportId, AuthenticatedUser principal)` returns `DailyReportResponse`.
- `DailyReportCommandService.create(DailyReportRequest request, AuthenticatedUser principal)` returns `DailyReportSummaryResponse`.
- `DailyReportCommandService.update(String reportId, DailyReportRequest request, AuthenticatedUser principal)` returns `DailyReportSummaryResponse`.
- `DailyReportSubmissionService.submit(String reportId, AuthenticatedUser principal)` returns `SubmitResponse`.
- `DailyReportSubmissionService.resubmit(String reportId, AuthenticatedUser principal)` returns `SubmitResponse`.
- `DailyReportAccessPolicy.requireEmployee(AuthenticatedUser principal)` returns `AppUser`.
- `DailyReportAccessPolicy.canReadReport(AppUser user, DailyReportEntity report)` returns `boolean`.
- `DailyReportAccessPolicy.permittedGroupIds(AppUser user, String requestedGroupId)` returns `List<String>`.

- [ ] **Step 1: 検索 Service を作成する**

  `DailyReportSearchService` へ旧 `DailyReportService.search`、`get`、`validateSearchDateRange`、`searchSpecification` をそのまま移し、`@Transactional(readOnly = true)` を各公開検索メソッドへ残す。検索条件、社員・上長・管理者の絞り込み、並び順、詳細参照認可は変更しない。

- [ ] **Step 2: 登録更新 Service を作成する**

  `DailyReportCommandService` へ旧 `create`、`update`、`apply` を移す。`TimeRules.validateAndCalculate`、重複チェック、スナップショット、状態チェック、勤務設定の適用順序をそのまま保持し、`@Transactional` を登録・更新メソッドへ残す。

- [ ] **Step 3: 提出 Service を作成する**

  `DailyReportSubmissionService` へ旧 `submit`、`resubmit` を移す。`DRAFT` / `REJECTED` の状態制限、`TimeRules.validateStoredReport`、`report.submit(OffsetDateTime.now())`、`@Transactional` を変更しない。

- [ ] **Step 4: 認可共通部品を作成する**

  `DailyReportAccessPolicy` に旧 Service の `requireEmployee`、`canReadReport`、`permittedGroupIds` を移す。`ManagerGroupPermissionRepository` の参照結果、社員本人・上長担当グループ・管理者の条件をそのまま移植する。

- [ ] **Step 5: Controller を3つ作成する**

  次の HTTP マッピングを保持する。

  ```text
  DailyReportCommandController
    POST /api/daily-reports
    PUT  /api/daily-reports/{reportId}

  DailyReportSearchController
    GET  /api/daily-reports
    GET  /api/daily-reports/{reportId}

  DailyReportSubmissionController
    POST /api/daily-reports/{reportId}/submit
    POST /api/daily-reports/{reportId}/resubmit
  ```

  Controller は認証済み principal と入力を対応する Service へ渡すだけにし、業務ロジックを追加しない。

- [ ] **Step 6: 旧混在クラスを削除する**

  旧 Controller と旧 Service を削除し、同一 URL のハンドラが二重登録されない状態にする。

- [ ] **Step 7: 構造テストをGREENにする**

  Run: `mvn.cmd -s local-maven-settings.xml -o -Dtest=DailyReportSeparationTest test` (workdir: `backend`)

  Expected: 1テスト成功、失敗0、エラー0。

- [ ] **Step 8: 既存の統合テストで挙動を確認する**

  Run: `mvn.cmd -s local-maven-settings.xml -o -Dtest=DailyReportControllerTest test` (workdir: `backend`)

  Expected: テストメソッドをまだ移動していない段階で、既存テスト全件が成功する。失敗した場合はテスト期待値を変えず、本体の分割差分を修正する。

- [ ] **Step 9: Commit**

  ```powershell
  git add -- backend/src/main/java/com/example/dailyreport/report backend/src/main/java/com/example/dailyreport/report/controller
  git commit -m "refactor: split daily report use case services"
  ```

### Task 5: バックエンドテストを機能別クラスへ移設する

**Files:**

- Create: `backend/src/test/java/com/example/dailyreport/support/MockMvcTestSupport.java`
- Create: `backend/src/test/java/com/example/dailyreport/report/support/DailyReportTestSupport.java`
- Create: `backend/src/test/java/com/example/dailyreport/report/DailyReportSearchControllerTest.java`
- Create: `backend/src/test/java/com/example/dailyreport/report/DailyReportCommandControllerTest.java`
- Create: `backend/src/test/java/com/example/dailyreport/report/DailyReportSubmissionControllerTest.java`
- Create: `backend/src/test/java/com/example/dailyreport/master/MasterControllerTest.java`
- Delete: `backend/src/test/java/com/example/dailyreport/report/DailyReportControllerTest.java`

**Interfaces:**

- `MockMvcTestSupport.loginAs(MockMvc mockMvc, ObjectMapper objectMapper, String loginId)` returns `MockHttpSession`。
- `DailyReportTestSupport.createReport(MockMvc mockMvc, ObjectMapper objectMapper, MockHttpSession session, LocalDate date, int workMinutes)` returns `ResultActions`。
- `DailyReportTestSupport.createReportId(MockMvc mockMvc, ObjectMapper objectMapper, MockHttpSession session, LocalDate date, int workMinutes)` returns `String`。
- `DailyReportTestSupport.seedUser(JdbcTemplate jdbcTemplate, String userId, String employeeId, String loginId, String userName, String role, String groupId, String groupName)` returns `void`。
- `DailyReportTestSupport.seedReport(JdbcTemplate jdbcTemplate, String reportId, String employeeUserId, String employeeId, String employeeName, String groupId, String groupName, LocalDate reportDate, String approvalStatus)` returns `void`。
- `DailyReportTestSupport.reportJson(ObjectMapper objectMapper, LocalDate reportDate, String holidayType, String startTime, String endTime, int workMinutes, String remarks)` returns `String`。

- [ ] **Step 1: ログイン補助を移す**

  旧 `loginAs` の MockMvc 呼び出し、ログイン JSON、パスワード、HTTP ステータス、セッション取得を変更せず、`MockMvcTestSupport.loginAs` へ移す。

- [ ] **Step 2: 日報補助を移す**

  旧 `createReport`、`createReportId`、`seedUser`、`seedReport`、`reportJson` の SQL、JSON、期待値を変更せず、`DailyReportTestSupport` へ移す。テスト本体からは static import して呼び出し名を維持する。

- [ ] **Step 3: 検索・詳細テストを移す**

  `DailyReportSearchControllerTest` へ次のメソッドを移す。

  ```text
  searchRequiresDateRange
  searchRequiresLogin
  detailRequiresLogin
  searchRejectsInvalidDateFormat
  searchRejectsInvalidApprovalStatus
  searchRejectsTooWideDateRange
  employeeSearchReturnsOnlyOwnReportsInDateRange
  employeeSearchIgnoresOtherEmployeeIdFilter
  managerSearchReturnsOnlyPermittedGroupReports
  managerSearchWithOutsideGroupFilterReturnsEmpty
  adminSearchReturnsMultipleEmployeesAndCanFilterByGroupAndEmployee
  searchReturnsReportsOrderedByDateAndEmployeeId
  managerCanGetOnlyPermittedGroupReportDetail
  adminSearchCanFilterByStatusAndHolidayType
  getMissingReportReturnsNotFound
  ```

- [ ] **Step 4: 登録・更新テストを移す**

  `DailyReportCommandControllerTest` へ次のメソッドを移す。

  ```text
  createWorkdayReportCalculatesMinutes
  editDraftReportKeepsDraftStatus
  pendingReportCannotBeEdited
  createRejectsDuplicateReportForSameEmployeeAndDate
  createRejectsWorkItemTotalMismatch
  createAllowsHolidayWithoutWorkItemsAndPaidLeave
  managerCannotCreateEmployeeReport
  createRequiresCsrfToken
  updateMissingOwnReportReturnsForbidden
  createRejectsMissingHolidayType
  createRejectsInvalidTimeFormat
  createRejectsPaidLeaveWithWorkInput
  createRejectsHolidayWithoutItemsButWithTimes
  createRejectsWorkdayMissingTimesAndItems
  createRejectsEndTimeBeforeStartTime
  createRejectsBreakLongerThanElapsedTime
  holidayWithoutWorkItemsCanBeReadWithEmptyDurations
  ```

- [ ] **Step 5: 提出・再提出テストを移す**

  `DailyReportSubmissionControllerTest` へ次のメソッドを移す。

  ```text
  submitDraftReportChangesToPending
  submitPendingReportIsRejected
  rejectedReportCanBeResubmitted
  resubmitDraftReportIsRejected
  submitCorruptedStoredReportIsRejected
  ```

- [ ] **Step 6: マスタテストを移す**

  `MasterControllerTest` へ次のメソッドを移す。テスト名は既存内容を優先して変更しない。

  ```text
  protectedDailyReportApiRequiresLogin
  masterOptionsAreAvailableForLoggedInUser
  ```

- [ ] **Step 7: 各テストクラスの Spring 設定を維持する**

  日報3クラスには既存の日報削除 SQL を付け、`@SpringBootTest`、`@AutoConfigureMockMvc`、`@ActiveProfiles("test")`、`MockMvc`、`ObjectMapper`、`JdbcTemplate` の注入を維持する。マスタテストには日報削除 SQLを付けず、必要なログイン補助だけを利用する。

- [ ] **Step 8: 分割後テストを実行する**

  Run: `mvn.cmd -s local-maven-settings.xml -o -Dtest=DailyReportSeparationTest,DailyReportSearchControllerTest,DailyReportCommandControllerTest,DailyReportSubmissionControllerTest,MasterControllerTest test` (workdir: `backend`)

  Expected: 構造テストと移設した全テストが成功し、失敗0、エラー0。旧クラスの削除によってテスト件数が減っていない。

- [ ] **Step 9: 旧テストとのメソッド網羅を確認する**

  Run: `rg -n '^    void ' backend/src/test/java/com/example/dailyreport/report backend/src/test/java/com/example/dailyreport/master`

  Expected: Task 5 の4クラスに、旧 `DailyReportControllerTest` の40メソッドが漏れなく存在する。

- [ ] **Step 10: Commit**

  ```powershell
  git add -- backend/src/test/java
  git commit -m "test: split daily report controller tests by use case"
  ```

### Task 6: 標準資料・指摘一覧・作業記録へ再発防止を反映する

**Files:**

- Modify: `docs/AI活用開発研究/構想メモ/標準化/ディレクトリ構成ルール.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/実装前確認観点.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/実装後レビュー観点.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/テスト方針.md`
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_作業記録.md`
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md`

**Interfaces:**

- Produces: 実装前・実装後に、テスト配置、本体とテストの責務分離、ユースケース別テストクラスを確認できる標準資料。
- Produces: `DR-F-009` に今回の検出内容、対応ファイル、対応済み状態を記録する。

- [ ] **Step 1: ディレクトリ構成ルールを更新する**

  フロント欄に `src` は実装専用、`test` は Vitest 専用であること、バックエンド欄に `src/main` は実装専用、`src/test` はテスト専用であることを追加する。さらに「Controller、Service、テストは検索・登録更新・提出などユースケース単位で分け、同一テストクラスへ複数機能を継続追加しない」を並列開発の分割ルールへ追加する。

- [ ] **Step 2: 実装前確認観点を更新する**

  ファイル配置欄へ「本体配下にテストを置かないか」「テストがユースケース単位に分かれているか」「既存テストを移動するだけで確認内容を維持できるか」を追加する。

- [ ] **Step 3: 実装後レビュー観点を更新する**

  責務分離・並列開発・テスト欄へ、実装コードとテストコードの配置分離、複数ユースケースの同一 Controller / Service / テストクラスへの再集中がないことを追加する。

- [ ] **Step 4: テスト方針を更新する**

  テスト分類の前に、フロント単体テストは `frontend/test`、E2E は `frontend/e2e`、バックエンドテストは `backend/src/test` に配置し、テストクラスはユースケース単位で分ける方針を追加する。レイアウトチェックを品質ゲートの補助確認として記載する。

- [ ] **Step 5: 指摘一覧を更新する**

  `日報登録編集_指摘一覧.md` に次の形式で `DR-F-009` を追加する。

  ```text
  | DR-F-009 | ファイル配置・責務分離 | Medium | フロントの日報検索テストが機能実装配下にあり、バックエンドの日報 Controller、Service、テストクラスにも複数ユースケースが集中していた | 対応済み | フロントテストを frontend/test へ移動し、バックエンドを検索・登録更新・提出・マスタの Controller / Service / テストへ分割。scripts/check-test-layout.ps1、標準化資料、DailyReportSeparationTest を追加。 |
  ```

- [ ] **Step 6: 作業記録を更新する**

  2026-07-13 の節を追加し、対象範囲、変更ファイル、既存テスト確認内容を維持したこと、実行したコマンド、未実行の Oracle 確認がある場合は「DDL・SQL・DB接続設定を変更していないため対象外」と記録する。既存 `.github/workflows/oracle.yml` は確認したが、別作業で導入予定の `scripts/check.ps1` を呼び出す構成のため、今回の分離では変更していないことも記録する。

- [ ] **Step 7: 文書差分を検証する**

  Run: `git diff --check -- docs/AI活用開発研究/構想メモ/標準化 docs/AI活用開発研究/作業記録`

  Expected: 空の出力で終了コード0。日本語が文字化けしていないことを `Get-Content -Encoding UTF8` で確認する。

- [ ] **Step 8: Commit**

  ```powershell
  git add -- docs/AI活用開発研究/構想メモ/標準化/ディレクトリ構成ルール.md docs/AI活用開発研究/構想メモ/標準化/実装前確認観点.md docs/AI活用開発研究/構想メモ/標準化/実装後レビュー観点.md docs/AI活用開発研究/構想メモ/標準化/テスト方針.md docs/AI活用開発研究/作業記録/日報登録編集_作業記録.md docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md
  git commit -m "docs: prevent mixed feature and test sources"
  ```

### Task 7: 全体検証と最終レビューを実行する

**Files:**

- Verify: `scripts/check-test-layout.ps1`
- Verify: `frontend/package.json`
- Verify: `backend/pom.xml`
- Verify: 日報分割後の全 Java / TypeScript ソースとテスト

- [ ] **Step 1: レイアウト検査を実行する**

  Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-test-layout.ps1`

  Expected: `Test layout check passed.`、終了コード0。

- [ ] **Step 2: フロント単体テストを実行する**

  Run: `npm.cmd test -- --run` (workdir: `frontend`)

  Expected: 全テスト成功、失敗0、エラー0。`pretest` によりレイアウトチェックも実行される。

- [ ] **Step 3: フロント型チェックとビルドを実行する**

  Run: `npm.cmd run typecheck` (workdir: `frontend`)

  Expected: 終了コード0。

  Run: `npm.cmd run build` (workdir: `frontend`)

  Expected: TypeScript と Vite の production build が終了コード0。

- [ ] **Step 4: フロントカバレッジを実行する**

  Run: `npm.cmd run coverage` (workdir: `frontend`)

  Expected: 全テスト成功。生成物の coverage ディレクトリはソース差分へ含めない。

- [ ] **Step 5: バックエンド通常テストを実行する**

  Run: `mvn.cmd -s local-maven-settings.xml -o test` (workdir: `backend`)

  Expected: 全バックエンドテスト成功、失敗0、エラー0、スキップ0。

- [ ] **Step 6: バックエンドカバレッジを実行する**

  Run: `mvn.cmd -s local-maven-settings.xml -o -Pcoverage test` (workdir: `backend`)

  Expected: 全バックエンドテスト成功。カバレッジ生成物はソース実装と混同せず、Git差分へ含めない。

- [ ] **Step 7: 主要 E2E を実行する**

  Run: `npm.cmd run e2e` (workdir: `frontend`)

  Expected: 主要ログイン・日報操作 E2E が成功する。環境依存で未実行の場合は理由と再実行条件を作業記録へ書く。

- [ ] **Step 8: 本体配下のテスト混在を再確認する**

  Run: `rg --files frontend/src backend/src/main | Where-Object { $_ -match '(\.test\.|\.spec\.|Test\.java$|IT\.java$)' }`

  Expected: 空の出力。

- [ ] **Step 9: 変更範囲と記録をレビューする**

  Run: `git diff --check; git status --short; git diff --stat HEAD~6..HEAD`

  Expected: 空白エラーなし、未追跡 `.github` 以外の意図しない変更なし、仕様書・実装・テスト・標準資料・記録が揃っている。

- [ ] **Step 10: Commit**

  ```powershell
  git add -- scripts frontend backend docs/AI活用開発研究/構想メモ/標準化 docs/AI活用開発研究/作業記録
  git commit -m "refactor: separate daily report features and tests"
  ```

## Verification Summary

- Functional behavior is protected by the existing MockMvc, Vitest, and E2E assertions.
- Structural behavior is protected by `DailyReportSeparationTest` and `scripts/check-test-layout.ps1`.
- Oracle integration is not required for this change because no DDL, SQL, master data, or DB connection setting is changed. If the standard environment requires it anyway, record the result or the unavailable connection reason in the work record.
- Before claiming completion, run the fresh verification commands in Task 7 and inspect their exit codes and failure counts.
