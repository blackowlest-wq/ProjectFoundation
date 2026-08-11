# F-002 日報登録画面 完成 Implementation Plan

> **Codexでの実行:** 実装前に`/plan`でこの既存計画と現在のリポジトリ状態を照合する。長時間・多段階の実行では、合意した結果、制約、検証を含む`/goal`を開始する。チェックボックスは進捗記録に使い、未確認の項目を現行要件として扱わない。

**Goal:** F-002のBackend未実行ケースを実行可能な正本テストへ追加し、JaCoCo全指標85%以上とOracle実行証跡を満たした日報登録画面の品質ゲートを完成させる。

**Architecture:** 既存の登録API責務を持つ`DailyReportCommandControllerTest`へF-002ケースを追加し、`TimeRulesTest`は業務ルール分岐の単体責務として維持する。Oracle用seedは`DataInitializer`の既存の不足時投入契約へ追加し、登録所有者は常に`AuthenticatedUser`から設定される既存Service契約をテストで固定する。生成済みカバレッジを根拠にF-002関連の未通過分岐だけを追加確認し、カバレッジ結果と正本資料を同期する。

**Tech Stack:** Java 21, Spring Boot 3.3.6, Spring MockMvc, JUnit 5, Oracle, JaCoCo 0.8.12, Maven Wrapper, PowerShell 7, TypeScript/React, Playwright。

## Global Constraints

- 開発モードは品質重視モードとする。
- Backend CoverageのINSTRUCTION、BRANCH、METHOD、LINEは各85%以上とする。
- Backend/Oracleは`backend/scripts/test-oracle.cmd`を共通入口とし、Oracle識別値と秘密値非出力の契約を維持する。
- 未実行のBackend、Coverage、Oracle、E2Eを成功扱いにしない。
- 本番コード変更は、変更を必要とする失敗テストを先に確認した場合だけ行う。
- F-003、F-006、F-009固有機能とF-008差戻し完全E2Eは変更しない。
- AM_OFF/PM_OFFは半日休暇の短縮時間を推測せず、現行マスタの`requires_work_time`、`allows_work_items`、作業時間合計一致の契約だけを確認する。
- 日本語資料はUTF-8で編集し、Gitフックの空白・Markdown・秘密情報検査を通過させる。

---

### Task 1: 正本ケースとトレーサビリティを先に更新する

**Files:**
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_テストケース.md`
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_受入条件レビュー.md`
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md`
- Modify: `docs/AI活用開発研究/コード品質確認画面/F-002_日報登録/F-002_日報登録_表示データ.json`

**Interfaces:**
- Consumes: 設計書`docs/superpowers/specs/2026-07-28-complete-f002-daily-report-design.md`、既存F-002 AC/TC/RT/FIND、現在のJaCoCo XMLの未通過分岐。
- Produces: `TC-F002-BE-018`～`TC-F002-BE-024`、`RT-F002-BE-011`～`RT-F002-BE-017`、各ケースのAC・期待結果・実行コマンド・実行結果欄。

- [ ] **Step 1: 正本テストケースへ追加ケースを書く**

  `日報登録編集_テストケース.md`の実装後判定表へ次を追加する。

  - `TC-F002-BE-018` / `RT-F002-BE-011`: `createAllowsMultipleWorkItemsAndPreservesOrder`
  - `TC-F002-BE-019` / `RT-F002-BE-012`: `createAllowsOneMinuteWorkItem`
  - `TC-F002-BE-020` / `RT-F002-BE-013`: `createAllowsHolidayWithWorkItems`
  - `TC-F002-BE-021` / `RT-F002-BE-014`: `createAllowsAmOffWorkdayInput`
  - `TC-F002-BE-022` / `RT-F002-BE-015`: `createAllowsPmOffWorkdayInput`
  - `TC-F002-BE-023` / `RT-F002-BE-016`: `createUsesAuthenticatedSecondaryEmployeeSnapshot`
  - `TC-F002-BE-024` / `RT-F002-BE-017`: `createCannotChangeOwnerWithClientEmployeeFields`

  各行には、前提、入力、操作、HTTP結果、詳細APIまたはDBで観測する所有者・合計・内訳、AC ID、テスト層、保留条件を記載する。

- [ ] **Step 2: 受入条件レビューと指摘一覧を同期する**

  `DR-T-001`、`DR-T-002`、`DR-T-003`の対応欄を追加ケースと実装予定へ更新する。AM_OFF/PM_OFFの短縮勤務値は仕様根拠がないため対象外・確認事項として残し、今回のケースが確認する期待値を「現行マスタ契約による入力可否と合計一致」と明記する。各指摘を`既存観点で対応`または`個別対応`へ判定し、判定理由を残す。

- [ ] **Step 3: F-002表示データへ未実行ケースを追加する**

  JSONの`testCases`、`testImplementations`、`evidence`、`findings`、`qualityGates`へ新しいIDを重複なく追加する。実装前は新規Backendケースの`executionStatus`を`未実行`、`executionNote`を「追加テスト未実行」とし、先行して成功扱いにしない。

- [ ] **Step 4: 正本資料の差分を確認する**

  Run: `git diff --check`

  Expected: 終了コード0。ケースID、実テストID、FIND IDが既存IDと重複しない。

### Task 2: Backend登録テストを追加する

**Files:**
- Test: `backend/src/test/java/com/example/dailyreport/report/DailyReportCommandControllerTest.java`
- Modify: `backend/src/test/java/com/example/dailyreport/report/support/DailyReportTestSupport.java`

**Interfaces:**
- Consumes: `DailyReportCommandController`のPOST `/api/daily-reports`、GET `/api/daily-reports/{reportId}`、`MockMvcTestSupport.loginAs`、F-002の追加ケース。
- Produces: `RT-F002-BE-011`～`RT-F002-BE-017`に対応する実行可能なController/APIテスト。

- [ ] **Step 1: 失敗するsecondary employeeログイン確認を追加する**

  `DailyReportCommandControllerTest`へ、まだseedしていない`employee002`でログインするテストの骨格を追加し、次の実行で失敗することを確認する。

  ```java
  @Test
  void createUsesAuthenticatedSecondaryEmployeeSnapshot() throws Exception {
      MockHttpSession session = loginAs(mockMvc, objectMapper, "employee002");

      String responseBody = mockMvc.perform(post("/api/daily-reports")
                      .with(csrf())
                      .session(session)
                      .contentType(MediaType.APPLICATION_JSON)
                      .content(reportJson(objectMapper, LocalDate.of(2026, 7, 10),
                              "WORKDAY", "09:00", "23:00", 765, "secondary")))
              .andExpect(status().isCreated())
              .andExpect(jsonPath("$.approvalStatus", equalTo("DRAFT")))
              .andReturn().getResponse().getContentAsString();

      String reportId = objectMapper.readTree(responseBody).get("reportId").asText();
      mockMvc.perform(get("/api/daily-reports/" + reportId).session(session))
              .andExpect(status().isOk())
              .andExpect(jsonPath("$.employeeUserId", equalTo("U004")))
              .andExpect(jsonPath("$.employeeId", equalTo("E002")))
              .andExpect(jsonPath("$.regularWorkMinutes", equalTo(450)))
              .andExpect(jsonPath("$.overtimeWorkMinutes", equalTo(255)))
              .andExpect(jsonPath("$.nightWorkMinutes", equalTo(60)));
  }
  ```

  Run: `backend\mvnw.cmd -s backend\local-maven-settings.xml -B -Dtest=DailyReportCommandControllerTest#createUsesAuthenticatedSecondaryEmployeeSnapshot test`

  Expected before seed implementation: FAIL during login because `employee002` is absent. This is the intentional RED result for the new test fixture contract.

- [ ] **Step 2: Add the multiple-item JSON helper and write the remaining failing tests**

  Add the helper signature below to `DailyReportTestSupport` before using it in the test class:

  ```java
  public static String reportJsonWithItems(ObjectMapper objectMapper, LocalDate reportDate,
          String holidayType, String startTime, String endTime,
          List<Map<String, Object>> workItems, String remarks) throws Exception {
      Map<String, Object> request = new LinkedHashMap<>();
      request.put("reportDate", reportDate.toString());
      request.put("holidayType", holidayType);
      request.put("startTime", startTime);
      request.put("endTime", endTime);
      request.put("remarks", remarks);
      request.put("workItems", workItems);
      return objectMapper.writeValueAsString(request);
  }
  ```

  Add these test methods and assertions:

  - `createAllowsMultipleWorkItemsAndPreservesOrder`: POST WORKDAY 09:00–18:00 with P001/WC001/300 followed by P002/WC002/180; assert 201/DRAFT and GET `workItems[0]`, `workItems[1]`, `totalWorkItemMinutes=480`.
  - `createAllowsOneMinuteWorkItem`: POST WORKDAY 09:00–09:01 with one item of 1; assert 201 and GET `workMinutes=1`, `totalWorkItemMinutes=1`.
  - `createAllowsHolidayWithWorkItems`: POST HOLIDAY 09:00–10:00 with one item of 60; assert 201 and GET `holidayType=HOLIDAY`, `workMinutes=60`, `totalWorkItemMinutes=60`.
  - `createAllowsAmOffWorkdayInput`: POST AM_OFF 09:00–18:00 with one item of 480; assert 201/DRAFT and GET `holidayType=AM_OFF`, `totalWorkItemMinutes=480`.
  - `createAllowsPmOffWorkdayInput`: POST PM_OFF 09:00–18:00 with one item of 480; assert 201/DRAFT and GET `holidayType=PM_OFF`, `totalWorkItemMinutes=480`.

  Run: `backend\mvnw.cmd -s backend\local-maven-settings.xml -B -Dtest=DailyReportCommandControllerTest test`

  Expected: the new cases compile; the secondary employee case remains red until Task 3 adds the seed. If a confirmed case passes immediately, record it as evidence that the existing implementation already satisfies the newly added acceptance case and do not alter production behavior only to force a failure.

- [ ] **Step 3: Add the ownership-injection test**

  Add `createCannotChangeOwnerWithClientEmployeeFields`. Build a `LinkedHashMap` from the valid request and add `employeeUserId=U001`, `employeeId=E001`, and `employeeName=山田 太郎` before serialization. Login as `employee002`, POST the request, then GET the created report and assert `employeeUserId=U004`, `employeeId=E002`, and `employeeName=高橋 次郎`. This verifies the authenticated principal, not client-supplied identity, controls the snapshot.

- [ ] **Step 4: Run the focused Backend Unit tests**

  Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1 -CiTask BackendUnit`

  Expected: Backend unit tests pass after Task 3 seed work; record exact test count and commit in the work record.

### Task 3: Add the minimal secondary employee seed and verify the green tests

**Files:**
- Modify: `backend/src/main/java/com/example/dailyreport/config/DataInitializer.java`
- Test: `backend/src/test/java/com/example/dailyreport/report/DailyReportCommandControllerTest.java`

**Interfaces:**
- Consumes: `saveIfAbsent(UserRepository, AppUser)`, existing P001/P002/WC001/WC002/BT002/WT002 master data.
- Produces: `employee002` login fixture with `U004`, `E002`, `高橋 次郎`, `G002`, `第2開発グループ`, `BT002`, `WT002`.

- [ ] **Step 1: Write the seed-specific failing test first**

  The test from Task 2 must fail at login before the seed is added. Preserve that RED output in the execution notes; do not skip directly to production seed changes.

- [ ] **Step 2: Add the secondary employee factory and seed call**

  Add `saveIfAbsent(userRepository, secondaryEmployee(passwordEncoder));` immediately after the existing employee seed call and implement:

  ```java
  private AppUser secondaryEmployee(PasswordEncoder passwordEncoder) {
      return new AppUser("U004", "E002", "employee002", passwordEncoder.encode("password"),
              "高橋 次郎", Role.EMPLOYEE, "G002", "第2開発グループ",
              "BT002", "分割休憩", "WT002", "短時間勤務");
  }
  ```

  Do not change existing users or seed existing rows unconditionally.

- [ ] **Step 3: Run the focused green test**

  Run: `backend\mvnw.cmd -s backend\local-maven-settings.xml -B -Dtest=DailyReportCommandControllerTest#createUsesAuthenticatedSecondaryEmployeeSnapshot test`

  Expected: PASS with the secondary employee snapshot and 450/255/60 work split.

- [ ] **Step 4: Run all Backend Unit tests**

  Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1 -CiTask BackendUnit`

  Expected: PASS with no unrelated regression.

### Task 4: Close the Backend coverage gate using evidence-driven cases

**Files:**
- Test: `backend/src/test/java/com/example/dailyreport/report/TimeRulesTest.java`
- Test: `backend/src/test/java/com/example/dailyreport/report/DailyReportCommandControllerTest.java`
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_テストケース.md`

**Interfaces:**
- Consumes: `backend/target/site/jacoco/jacoco.xml`, `TimeRules.validateAndCalculate`, F-002 boundary cases.
- Produces: JaCoCo `jacoco.exec`, `jacoco.xml`, `jacoco.csv`, HTML and all four metrics at or above 85%.

- [ ] **Step 1: Run the coverage gate before adding coverage-only tests**

  Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1 -CiTask BackendCoverage`

  Expected before completion: if the gate fails, capture the primary failure and the JaCoCo counter values; do not record success. If Oracle configuration is unavailable, stop and record the exact missing prerequisite rather than changing the runner.

- [ ] **Step 2: Inspect only F-002-related uncovered branches**

  Run:

  ```powershell
  $xml = [xml](Get-Content -Raw -Encoding UTF8 .\backend\target\site\jacoco\jacoco.xml)
  $xml.report.package.class | ForEach-Object {
      $branch = $_.counter | Where-Object type -eq 'BRANCH'
      if ($branch -and [int]$branch.missed -gt 0) {
          [pscustomobject]@{ class=$_.name; missed=$branch.missed; covered=$branch.covered }
      }
  } | Sort-Object class
  ```

  Map remaining `TimeRules`, `DailyReportCommandService`, `DailyReportAccessPolicy`, or `DataInitializer` branches to an F-002 case before adding a test. Do not add unrelated search, approval, or authentication feature tests to inflate the global number.

- [ ] **Step 3: Add focused業務ルール tests for remaining F-002 branches**

  Add tests in `TimeRulesTest` only for mapped F-002 branches. The first candidates are a valid AM_OFF/PM_OFF pair, the one-minute work interval, holiday with items, and the secondary WT002 evening/night split. Each test must assert a business result or `ApiException` message, not only method execution.

- [ ] **Step 4: Re-run Backend Coverage until the gate is green**

  Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1 -CiTask BackendCoverage`

  Expected: PASS, `backend/target/jacoco.exec` exists, `backend/target/site/jacoco/index.html`, `jacoco.xml`, and `jacoco.csv` exist, and JaCoCo reports INSTRUCTION/BRANCH/METHOD/LINE >= 85%.

- [ ] **Step 5: Record coverage evidence**

  Copy the exact four percentages, command, execution date, commit, and report paths into the F-002 quality data and `日報登録編集_テストケース.md`. Do not copy passwords or connection values.

### Task 5: Run the real Backend/Oracle screen flow when prerequisites are available

**Files:**
- Test: `frontend/e2e/oracle-daily-report.oracle.spec.ts`
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_E2Eテスト導入.md`
- Modify: `docs/AI活用開発研究/作業記録/コード品質確認画面_検証記録.md`

**Interfaces:**
- Consumes: Backend Coverage green state, Oracle test identity, real Frontend build, existing registration E2E.
- Produces: Real Backend/Oracle registration and reload evidence, or a recorded prerequisite blocker.

- [ ] **Step 1: Run the E2E Oracle gate**

  Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1 -CiTask E2EOracle`

  Expected: real authentication, POST registration, report ID navigation, DB persistence, and reload verification pass. If the preflight reports missing protected configuration, preserve the failure and record the required environment variable names only.

- [ ] **Step 2: Update the E2E and quality records**

  Record whether the real flow ran, the number of passed cases, the report/artifact paths, and any exact retry condition. Keep Mock E2E evidence separate from real Backend/Oracle evidence.

### Task 6: Regenerate the F-002 quality report and synchronize records

**Files:**
- Modify: `docs/AI活用開発研究/コード品質確認画面/F-002_日報登録/F-002_日報登録_表示データ.json`
- Generate: `docs/AI活用開発研究/コード品質確認画面/F-002_日報登録/F-002_日報登録_コード品質確認.html`
- Modify: `docs/AI活用開発研究/作業記録/コード品質確認画面_検証記録.md`
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md`

**Interfaces:**
- Consumes: Task 2–5 test IDs, command outputs, JaCoCo files, Oracle/E2E evidence.
- Produces: deterministic F-002 quality report with no unexecuted Backend cases falsely marked successful.

- [ ] **Step 1: Update F-002 data after actual execution**

  For every new case, set `executionStatus`, `testImplementationIds`, `evidenceIds`, `findingIds`, `executionNote`, and `reviewStatus` from actual results. Set `QG-F002-API` and `QG-F002-BACKEND-COVERAGE` to `通過` only when their blocking conditions are actually met.

- [ ] **Step 2: Validate the report input**

  Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-quality-reports.ps1 -FeaturePath .\docs\AI活用開発研究\コード品質確認画面\F-002_日報登録 -ValidateOnly`

  Expected: validation succeeds and reports no unbound test, evidence, or blocking gate inconsistency.

- [ ] **Step 3: Generate the report**

  Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-quality-reports.ps1 -FeaturePath .\docs\AI活用開発研究\コード品質確認画面\F-002_日報登録`

  Expected: HTML contains the current commit, updated gate status, four coverage metrics, execution statuses, and linked evidence.

- [ ] **Step 4: Update review and work records**

  Add the changed files, exact commands, results, standardization classification, and remaining conditions to the records. A remaining Oracle or visual blocker must remain visible as `保留` with a recheck condition.

### Task 7: Final quality gate and handoff

**Files:**
- Verify: all changed files in Tasks 1–6

- [ ] **Step 1: Run the full project gate**

  Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1 -Mode Full`

  Expected: Frontend lint/typecheck/unit/build, Backend quality, and contract tests pass.

- [ ] **Step 2: Run diff and status checks**

  Run: `git diff --check`

  Expected: exit code0.

  Run: `git status --short`

  Expected: only intended changes are present before commit.

- [ ] **Step 3: Perform the implementation review**

  Review against `docs/AI活用開発研究/構想メモ/標準化/実装後レビュー表.md` and `docs/AI活用開発研究/構想メモ/標準化/テスト・静的解析チェック表.md`. Confirm test responsibility remains separated, all findings have classifications, and no unexecuted gate is reported as passed.

- [ ] **Step 4: Commit and report**

  ```powershell
  git add -- backend/src/main/java/com/example/dailyreport/config/DataInitializer.java backend/src/test/java/com/example/dailyreport/report/DailyReportCommandControllerTest.java backend/src/test/java/com/example/dailyreport/report/TimeRulesTest.java backend/src/test/java/com/example/dailyreport/report/support/DailyReportTestSupport.java docs/AI活用開発研究/作業記録 docs/AI活用開発研究/コード品質確認画面/F-002_日報登録
  git commit -m "test: complete F-002 backend coverage cases"
  ```

  Report the commit, branch, exact test results, coverage metrics, Oracle/E2E status, and any remaining recheck condition.
