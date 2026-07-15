# Logger Observability and Oracle E2E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Backendの各リクエストを相関ID・機能・ユースケース・HTTP結果・処理時間で追跡できるようにし、業務エラーとシステムエラーを安全に記録する。Frontendには相関IDを伝播し、実BackendとOracleを接続したPlaywright E2Eで、ログインから日報の保存・提出・再読込までを実DB上で検証する。

**Architecture:** Spring MVCの最上位`OncePerRequestFilter`がリクエストごとにUUIDを生成し、MDC、リクエスト属性、`X-Request-Id`レスポンスヘッダーへ設定する。HandlerMethod用InterceptorがControllerから機能名・ユースケース名を解決し、Filterの完了ログへ渡す。共通例外ハンドラーとSpring Securityのエラー入口は同じ`ErrorResponse`形式と相関IDを返し、期待される業務エラーはWARN、予期しない例外はERRORへ記録する。通常の本番設定は業務イベントのINFOまで、リクエスト開始・完了の詳細はE2EプロファイルでDEBUGへ上げる。Oracle E2Eは専用PowerShellランナーがOracle設定を検証し、BackendとVite previewを起動し、Playwright実ブラウザを実行し、終了時に安全なテストデータを削除する。

**Tech Stack:** Spring Boot 3.3.6 / Spring MVC / Spring Security / SLF4J + Logback、Java 21、React + TypeScript + Vite、Vitest、Playwright、PowerShell、Oracle SQL*Plus、GitHub Actions self-hosted Oracle runner。

## Global Constraints

- `C:\Users\user\Desktop\個人\個別作業\ツール等\ProjectFoundation\AGENTS.md`と標準資料を正本とし、既存の作業ツリー変更をリセット・上書きしない。
- 変更前に公式一次情報を確認する。確認済みの前提は、[Spring Boot logging](https://docs.spring.io/spring-boot/reference/features/logging.html)、[Spring MVC Filter](https://docs.spring.io/spring-framework/reference/web/webmvc/filters.html)、[Playwright webServer](https://playwright.dev/docs/test-webserver)、[Playwright trace](https://playwright.dev/docs/api/class-testoptions)、[Vite preview proxy](https://vite.dev/config/preview-options.html)である。
- 実装はテスト先行にし、各機能について最初に失敗するテストを追加してから本実装を行う。Oracleへ接続できない環境では、Oracle E2Eを成功扱いにせず、スクリプト構文・静的検査・非Oracleテストまでを検証し、未実行理由を作業記録へ残す。
- ログへリクエスト本文、パスワード、Cookie、CSRFトークン、Authorization値、Oracle JDBC URL、SQL、ユーザー入力の詳細本文を出さない。ユーザーIDやreportIdは業務イベントの追跡に必要な最小限だけを記録する。
- 本番の通常ログ量を増やしすぎない。`ERROR`はシステム失敗、`WARN`は業務エラー・認証拒否・異常な遅延、`INFO`はログイン成功と日報の状態変更、`DEBUG`はリクエスト開始・完了の詳細とし、E2EプロファイルだけでDEBUGを有効化する。
- 新規ファイルはUTF-8で作成する。PowerShellの確認では`Get-Content -Encoding UTF8`を使う。
- 各タスク終了時、対象ファイルだけを確認し、既存のユーザー変更を含めて`git diff`と`git status`を確認する。既存のステージ済み変更を巻き戻さない。

---

## Task 1: Add request context, correlation ID, and feature/use-case metadata

**Files:**

- Add `backend/src/main/java/com/example/dailyreport/observability/RequestContext.java`
- Add `backend/src/main/java/com/example/dailyreport/observability/RequestIdFilter.java`
- Add `backend/src/main/java/com/example/dailyreport/observability/RequestMetadataInterceptor.java`
- Add `backend/src/main/java/com/example/dailyreport/observability/ObservabilityWebConfig.java`
- Add `backend/src/test/java/com/example/dailyreport/observability/RequestIdFilterTest.java`
- Add `backend/src/test/java/com/example/dailyreport/observability/RequestMetadataInterceptorTest.java`

- [ ] Write the failing filter test first.

  - Build a standalone `MockMvc` chain around a test controller or a small `FilterChain`.
  - Assert that a request receives a UUID-shaped `X-Request-Id` response header.
  - Assert that the same ID is available as a request attribute during the chain and is removed from MDC after the request finishes.
  - Capture the logger output with Spring Boot’s `OutputCaptureExtension` or a test appender and assert only stable markers such as `event=request.completed`, HTTP method, status, and `durationMs`; do not assert timestamps or the complete Logback line.
  - Run `mvnw.cmd -s local-maven-settings.xml -B -Dtest=RequestIdFilterTest test` and confirm the test fails because the production classes do not exist.

- [ ] Write the failing metadata test.

  - Exercise a `HandlerMethod` for `DailyReportCommandController` and assert request attributes `feature=DAILY_REPORT` and `useCase=CREATE`.
  - Exercise `AuthController` and `MasterController` methods and assert `AUTH` and `MASTER` feature values with the method name converted to the stable use-case name.
  - Assert an unmapped handler is labeled `UNKNOWN` rather than causing an exception.
  - Run the targeted test and confirm it fails before implementation.

- [ ] Implement `RequestContext`.

  - Define constants for `X-Request-Id`, MDC key `requestId`, request ID attribute, feature attribute, and use-case attribute.
  - Provide null-safe accessors that return `UNKNOWN` for missing feature/use-case values and never generate a second request ID inside exception handling.

- [ ] Implement `RequestIdFilter`.

  - Extend `OncePerRequestFilter`, register as a Spring component with highest precedence, generate a fresh UUID for every request, set the response header before the chain, set the request attribute, and put the value in MDC.
  - Record `System.nanoTime()` at entry and log `event=request.started` and `event=request.completed` at DEBUG with method, path without query string, status, feature, use case, and integer `durationMs`.
  - If an exception escapes the MVC chain, log one `event=request.failed` at ERROR with the exception object and rethrow it; do not log request body, query parameters, cookies, or headers.
  - In `finally`, remove the MDC key even when the chain fails. The completion log must use the response status available at that point.

- [ ] Implement `RequestMetadataInterceptor` and `ObservabilityWebConfig`.

  - Register the interceptor using `WebMvcConfigurer#addInterceptors`.
  - Resolve features by explicit controller class mapping: `AuthController -> AUTH`, `DailyReportCommandController` and `DailyReportSubmissionController` and `DailyReportSearchController -> DAILY_REPORT`, `MasterController -> MASTER`, and all other controllers -> `UNKNOWN`.
  - Resolve use cases from the Java handler method name in uppercase, with stable explicit mappings for `login`, `logout`, `me`, `create`, `update`, `submit`, `resubmit`, `search`, `detail`, `projects`, `workCategories`, and `holidayTypes`.
  - Store the resolved values in request attributes so the exception handlers, business logs, and request completion log use the same values.

- [ ] Run the two targeted backend tests, then run `mvnw.cmd -s local-maven-settings.xml -B -DskipTests test-compile`.

- [ ] Inspect the diff for MDC cleanup, no sensitive fields, and preservation of all existing staged files.

## Task 2: Make business and system errors traceable with a common response

**Files:**

- Modify `backend/src/main/java/com/example/dailyreport/common/ApiExceptionHandler.java`
- Modify `backend/src/main/java/com/example/dailyreport/common/ApiException.java` only if required by compilation; preserve its public error-code/status contract
- Modify `backend/src/main/java/com/example/dailyreport/config/SecurityConfig.java`
- Add `backend/src/test/java/com/example/dailyreport/common/ApiExceptionHandlerTest.java`
- Add `backend/src/test/java/com/example/dailyreport/config/SecurityErrorResponseTest.java` if existing security tests cannot cover the unauthenticated and access-denied paths

- [ ] Write failing handler tests before production changes.

  - Use standalone `MockMvc` with a controller throwing `ApiException` and assert the JSON contains the existing `code`, `message`, `details`, plus a nonblank `requestId` matching the `X-Request-Id` header.
  - Add a controller that throws an unexpected `IllegalStateException`; assert HTTP 500, generic code/message, empty details, and a requestId. Assert the response does not include the exception message or stack trace.
  - Use captured logs to assert business errors record `event=business.error`, status/code, feature, and use case, while unexpected exceptions record `event=system.unhandled_exception` with the exception stack.
  - Run `mvnw.cmd -s local-maven-settings.xml -B -Dtest=ApiExceptionHandlerTest test` and confirm failure before implementation.

- [ ] Write or extend failing security tests.

  - Exercise an unauthenticated protected endpoint and assert HTTP 401 with the common JSON error shape and requestId/header correlation.
  - Exercise an authenticated user without required access and assert HTTP 403 with the common JSON shape and requestId/header correlation.
  - Assert security logs do not contain credentials or session values.

- [ ] Extend `ApiExceptionHandler`.

  - Add `requestId` as the final `ErrorResponse` record field so existing JSON fields and frontend behavior remain compatible.
  - Centralize requestId extraction from `RequestContext`, including a safe fallback only for tests that bypass the filter.
  - Add `@ExceptionHandler(Exception.class)` returning a generic `INTERNAL_SERVER_ERROR` response and logging the exception at ERROR with `event=system.unhandled_exception`, feature, use case, HTTP status, and requestId from MDC/attributes.
  - Log `ApiException`, validation, type mismatch, and bad credentials as expected errors at WARN using codes and counts only; do not log validation values or exception messages that may contain user input.
  - Keep the existing status/code/message contract for known errors unless the new requestId field is required.

- [ ] Replace `HttpStatusEntryPoint` and the ad hoc access-denied map in `SecurityConfig`.

  - Add private or package-level JSON writers for 401 and 403 that use the same `ErrorResponse` JSON field names, requestId header, and request attributes.
  - Keep CSRF behavior and authorization rules unchanged. Use `UNAUTHORIZED` for unauthenticated requests and `FORBIDDEN` for access-denied/CSRF responses.
  - Log authentication/authorization failures at WARN with event, code, feature/use case when available, and HTTP status only.

- [ ] Run the focused handler/security tests, then the existing backend test-compile and relevant unit tests. Update any JSON-path assertions only for the additive `requestId` field.

## Task 3: Add business success logs and profile-controlled logging configuration

**Files:**

- Modify `backend/src/main/java/com/example/dailyreport/auth/AuthController.java`
- Modify `backend/src/main/java/com/example/dailyreport/report/controller/DailyReportCommandController.java`
- Modify `backend/src/main/java/com/example/dailyreport/report/controller/DailyReportSubmissionController.java`
- Modify `backend/src/main/resources/application.yml`
- Modify `backend/src/main/resources/application-test.yml` only if test log capture needs a profile override
- Modify `backend/src/main/resources/application-oracle-test.yml` only if Oracle test settings need an explicit non-production log level
- Add `backend/src/main/resources/application-e2e.yml`
- Add `backend/src/test/java/com/example/dailyreport/observability/LoggingConfigurationTest.java` if configuration behavior cannot be checked through existing tests

- [ ] Add failing success-log assertions before adding logs.

  - Extend controller/service tests with a successful create/update/submit path or a small mocked controller test that asserts stable `event=daily_report.saved` and `event=daily_report.submitted` markers, feature/use case, reportId, and resulting status.
  - Add login success and logout success assertions for `event=auth.login_succeeded` and `event=auth.logout_succeeded`; assert the password is absent from captured output.
  - Run the targeted tests and confirm the new assertions fail before production log statements are added.

- [ ] Add structured success logs at the state-change boundary.

  - Log create/update only after the service returns successfully, using `INFO`, `event=daily_report.saved`, `feature=DAILY_REPORT`, use case `CREATE` or `UPDATE`, reportId, and approval status.
  - Log submit/resubmit only after the service returns successfully, using `INFO`, `event=daily_report.submitted`, the corresponding use case, reportId, and approval status.
  - Log login success after session establishment with `INFO`, `event=auth.login_succeeded`, and the non-secret userId; log logout success after session invalidation with `INFO`, `event=auth.logout_succeeded`.
  - Do not log successful GET/search/master requests at INFO; their request completion details remain DEBUG-only.

- [ ] Configure levels and MDC visibility.

  - In `application.yml`, set root to `WARN`, the application package to `INFO`, and `logging.pattern.level` to include `[requestId:%X{requestId:-}]`.
  - In `application-e2e.yml`, set the application package to `DEBUG`, keep root at `INFO`, and write to `target/e2e/backend.log` with bounded history suitable for a test artifact.
  - Keep production defaults free of per-request DEBUG logs; document that a temporary operational diagnosis can raise the package or observability logger level through environment/profile configuration.
  - Keep SQL/Hibernate bind logging disabled in all profiles.

- [ ] Run focused log tests and start the backend in a non-Oracle profile if available to inspect one INFO success line and one DEBUG request-completion line. If startup is unavailable, validate YAML syntax and record the limitation.

## Task 4: Propagate requestId and record only actionable frontend failures

**Files:**

- Modify `frontend/src/shared/apiClient.ts`
- Modify `frontend/test/dailyReportApi.test.ts`
- Add `frontend/test/apiClient.test.ts` if the existing API test file becomes too broad

- [ ] Write failing frontend tests first.

  - Mock a 400 JSON response with a body requestId and assert `readError` returns it without writing to `console.error`.
  - Mock a 500 JSON response with an `X-Request-Id` header and no body requestId; assert the header value is returned and a safe diagnostic is emitted with only path/status/code/requestId.
  - Mock a network rejection and assert the wrapper logs `event=api.network_failure` with a path only, then rethrows the original error.
  - Assert request bodies and CSRF cookies are absent from diagnostics.
  - Run `npm --prefix frontend test -- --run frontend/test/apiClient.test.ts` or the equivalent Vitest path and confirm failure before implementation.

- [ ] Extend `ApiError` with optional `requestId`.

  - Parse the backend JSON defensively, merge `requestId` from the JSON body and then `X-Request-Id` header, and preserve the existing fallback for empty 401/other error bodies.
  - Introduce a private `fetchWithDiagnostics` wrapper used by all shared GET/POST/PUT helpers. It catches network errors, logs a safe path-only diagnostic, and rethrows without changing existing caller behavior.
  - Log HTTP diagnostics only for 5xx responses or `UNKNOWN_ERROR`; expected business/validation errors remain UI-visible but do not generate browser-console noise.
  - Strip query strings from any diagnostic URL and never serialize request init/body/headers.

- [ ] Run frontend unit tests, typecheck, lint, and build. Run the existing mock Playwright suite to confirm the additive response field does not alter current UI behavior.

## Task 5: Implement a real Backend + Oracle Playwright E2E runner

**Files:**

- Add `backend/scripts/oracle-test-helpers.ps1`
- Modify `backend/scripts/test-oracle.ps1` to consume the shared safe configuration helpers without changing its existing Maven/DDL command contract
- Add `backend/scripts/test-e2e-oracle.ps1`
- Add `backend/src/test/resources/db/oracle/e2e-cleanup.sql`
- Add `backend/src/main/resources/application-e2e.yml`
- Add `frontend/playwright.oracle.config.ts`
- Modify `frontend/package.json` to add `e2e:oracle`
- Add `frontend/e2e/oracle-daily-report.oracle.spec.ts`

- [ ] Write the real E2E test and runner contract first.

  - Add `oracle-daily-report.oracle.spec.ts` using the actual built frontend and no `page.route`, `mockStaticFrontend`, or API mocks.
  - Log in as the existing Oracle test user `employee901` with the repository test password contract, wait for the real daily-report screen, choose `2099-12-01`, choose `PAID_LEAVE` so no master-dependent work item is required, and execute `保存して提出`.
  - Capture the real create response and assert it has an UUID-shaped `X-Request-Id`; assert the UI reaches `保存して提出しました。` and `承認待ち`, reload the edit URL, and assert the date/status persisted from Oracle.
  - Use a dedicated `outputDir` under `frontend/test-results-oracle` and a dedicated HTML report directory so failure artifacts are separable from mocked E2E artifacts. Disable trace/video/screenshot for the real-login suite because the artifacts may contain credentials.
  - Add the runner script contract test or static assertions that the runner refuses missing Oracle config, starts both services, waits for their HTTP endpoints, runs the dedicated Playwright config, cleans the fixed test row in `finally`, and returns the Playwright/backend exit code.

- [ ] Refactor Oracle configuration validation into `oracle-test-helpers.ps1`.

  - Preserve all current required keys, TEST environment checks, expected host/service/name/user checks, administrative/production-like user rejection, JDBC URL shape validation, and DDL approval checks.
  - Expose functions for reading properties, resolving process environment overrides, validating values, setting process environment variables without printing secrets, and invoking SQL*Plus with `-L /nolog` while suppressing credential-bearing output.
  - Keep `test-oracle.ps1` behavior unchanged for integration and coverage tasks; run its existing configuration guard checks after refactoring.

- [ ] Implement `e2e-cleanup.sql` with a fixed, reviewable scope.

  - Delete child rows from `daily_report_work_items` for reports owned by `U901` on `DATE '2099-12-01'`, then delete matching `daily_reports`, and commit.
  - Do not use dynamic SQL, `DROP`, `TRUNCATE`, or a user-provided date/table name.
  - Validate the SQL file path in the runner under `backend/src/test/resources/db/oracle` before invoking SQL*Plus.

- [ ] Implement `test-e2e-oracle.ps1`.

  - Accept `ConfigPath`, fixed local ports (Backend 8080 and frontend preview 4173), and an optional artifact retention switch; use the existing Oracle config contract and force `DAILY_REPORT_DDL_CLI_APPROVED=false`.
  - Create `backend/target/e2e`, redirect Maven/Spring Boot stdout and stderr to separate log files, start `mvnw.cmd -s local-maven-settings.xml -B spring-boot:run` with `oracle-test,e2e` profiles and port 8080, and poll `/api/auth/me` until it returns 200 or 401.
  - Run `npm --prefix frontend run build` before starting Vite preview. Start `npm --prefix frontend run preview -- --host 127.0.0.1 --port 4173 --strictPort`, redirect its log, and poll `/` until HTTP 200.
  - Run `npm --prefix frontend run e2e:oracle` with the dedicated config. Stop only the captured Backend/frontend process trees in `finally`, run cleanup before and after the test, preserve logs and Playwright artifacts on failure, and return a nonzero exit code on any startup, cleanup, or test failure.
  - Do not echo environment variables or command arguments containing the Oracle password. Use hidden process windows for background services.

- [ ] Run the dedicated Playwright test list and PowerShell parser checks locally. If Oracle configuration or sqlplus is unavailable, run the runner far enough to verify the guarded failure and record the exact unavailable prerequisite; do not replace the real test with mocks.

## Task 6: Register the Oracle E2E quality gate and CI artifacts

**Files:**

- Modify `scripts/check.ps1`
- Modify `.github/workflows/oracle.yml`
- Modify `docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md`

- [ ] Add a dedicated `E2EOracle` `CiTask` to `scripts/check.ps1`.

  - Extend every relevant `ValidateSet` and `Get-CiTaskDefinitions` signature with `E2EOracle`.
  - Create one check definition invoking `pwsh -NoProfile -File backend/scripts/test-e2e-oracle.ps1`, forwarding `-OracleConfigPath` when supplied.
  - Keep `E2E` as the existing mocked/static frontend suite; do not silently make PR checks depend on Oracle.
  - Ensure `-Mode Quick`, `-Mode Full`, `-Mode Oracle`, and existing CI task names retain their current behavior.

- [ ] Add an `oracle-e2e` job to `.github/workflows/oracle.yml`.

  - Run on the existing isolated Oracle self-hosted label and `oracle-test` environment, with the same database secrets/variables as integration and coverage.
  - Checkout, run the runner diagnosis/bootstrap required for Node/Playwright/Maven, then call `scripts/check.ps1 -CiTask E2EOracle`.
  - Upload `backend/target/e2e`, `frontend/playwright-report-oracle`, and `frontend/test-results-oracle` with `if: always()` and `if-no-files-found: ignore`.
  - Keep the job on push-to-main/manual Oracle workflow rather than ordinary pull-request CI because it mutates only the isolated TEST schema and requires Oracle credentials.

- [ ] Add a script-level regression test or static quality check proving `E2EOracle` is accepted and resolves to the new runner. Run `scripts/check.ps1 -CiTask E2EOracle` only when a safe Oracle config is available; otherwise use PowerShell parse/static checks.

## Task 7: Update standards, work records, and findings

**Files:**

- Modify `docs/AI活用開発研究/構想メモ/標準化/セキュリティ規約.md`
- Modify `docs/AI活用開発研究/構想メモ/標準化/テスト方針.md`
- Modify `docs/AI活用開発研究/構想メモ/標準化/実装後レビュー観点.md` if the existing logging row does not cover correlation/level/secret requirements
- Modify `docs/AI活用開発研究/構想メモ/標準化/テスト・静的解析チェック表.md` if the existing E2E gate does not distinguish mocked and Oracle-backed E2E
- Modify `docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md`
- Add `docs/AI活用開発研究/作業記録/ロガー強化_作業記録.md`

- [ ] Add the reusable logging rules to the security standard: correlation ID, no secret/request-body logging, level policy, error response requestId, and redaction expectations.

- [ ] Add the testing rules: mock E2E proves UI behavior under controlled responses; Oracle-backed E2E proves Backend + Oracle persistence and preserves backend/log/Oracle verification/report artifacts without trace/video/screenshot; the two suites are complementary.

- [ ] Record findings in `日報登録編集_指摘一覧.md` with unique IDs for at least:

  - missing Backend request correlation/feature/timing logs;
  - missing common logging for business/system/security errors;
  - missing requestId propagation in frontend errors;
  - lack of a real Backend + Oracle E2E path;
  - log-volume risk without production level control.

  For each, record the evidence, changed files, verification result, and any Oracle-only execution still pending with the prerequisite and recheck timing.

- [ ] Write the work record with scope, design decision, official documentation checked, files changed, commands run, test results, artifact paths, and the exact reason for any unavailable Oracle execution. Do not record generated coverage or Playwright output as source implementation.

## Task 8: Verification and review gate

- [ ] Run backend targeted tests, all available backend tests/compile, Spotless, Checkstyle, and SpotBugs through the existing quality scripts.

- [ ] Run frontend unit tests, coverage if required by the existing gate, typecheck, lint, build, and the existing mocked E2E suite.

- [ ] Run PowerShell parser/static checks for `scripts/check.ps1`, `backend/scripts/test-oracle.ps1`, `backend/scripts/oracle-test-helpers.ps1`, and `backend/scripts/test-e2e-oracle.ps1`.

- [ ] Run markdown lint and the repository quick quality gate. Confirm no generated artifacts, secrets, or log files are staged.

- [ ] When Oracle runner prerequisites are available, run `scripts/check.ps1 -CiTask E2EOracle`, inspect the Backend log for requestId/feature/useCase/status/durationMs, and confirm the Playwright test captured the response header and persistence after reload. When unavailable, report the blocked external prerequisite without claiming the Oracle E2E passed.

- [ ] Review the final diff against the design document and this plan, check the existing staged user changes remain intact, and use the requesting-code-review workflow before declaring the implementation complete.

- [ ] Create focused commits only for this implementation’s files if commits are needed; do not include unrelated pre-existing staged changes.
