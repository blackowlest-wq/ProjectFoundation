# DB Master and Message Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with review checkpoints.

**Goal:** DBを正とするグループマスタとメッセージカタログを追加し、APIエラーと主要Frontend表示をDB文言へ切り替えつつ、安全なフォールバックを維持する。

**Architecture:** Backendは`MasterDataRepository`でグループを取得し、独立した`MessageCatalogService`がDB文言を5分TTLで解決する。共通例外ハンドラーは安定したメッセージキーをDB文言へ変換し、Frontendは認証済みの共有メッセージAPIをContextへロードする。状態・ロール・検証ロジックはEnum、コード、DB制約に残す。

**Tech Stack:** Spring Boot 3.3 / Java 21 / JdbcTemplate / Oracle SQL / React 19 / TypeScript / Vitest / Playwright / Maven Wrapper.

## Global Constraints

- 品質重視モードのP0設計照合、テスト不足、期待結果、トレーサビリティ・統合レビューを適用する。
- DB変更は`schema-login.sql`と`schema-daily-report.sql`、DataInitializer、Oracle seedの両方へ反映する。
- APIの既存`message`と`details[].message`契約を維持し、追加項目は後方互換にする。
- SQLはパラメータバインドを使い、グループ・メッセージ本文をログへ出力しない。
- 本番コードを書く前に、各追加テストをREDで実行する。
- 既存の日報履歴のグループ名スナップショットを現在のマスタ名で上書きしない。
- 初期マスタ変更は管理画面を追加せず、DB seedまたはDataInitializerで行う。
- Oracle認証が利用できない場合は、Oracle確認を未実行として作業記録へ理由と再確認条件を残す。

---

### Task 1: Design and quality records

**Files:**
- Create: `docs/superpowers/specs/2026-08-04-master-message-db-design.md`
- Create: `docs/superpowers/plans/2026-08-04-master-message-db.md`
- Create: `docs/AI活用開発研究/作業記録/区分メッセージDB化_作業記録_2026-08-04.md`
- Create: `docs/AI活用開発研究/作業記録/区分メッセージDB化_テストケース.md`
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md`

**Interfaces:**
- Produces AC-MSG-001..005, TC-MSG-001..007, RT-MSG-001..007 and the quality-mode decision used by later tasks.

- [ ] Record the baseline: Frontend 135 tests, lint/typecheck/build and Markdown lint pass; Backend `mvn test` is blocked by `ORA-01017` in the current environment.
- [ ] Record the existing `groups` API/DB conceptual design and the implementation gap.
- [ ] Record the standardization judgment: this is `標準化候補` for the existing rule that business-selectable values and user-visible copy use stable keys plus a DB-backed catalog; statuses, roles, validation and workflow remain code-owned.
- [ ] Commit only the approved design and preflight records before production implementation.

### Task 2: Backend red tests for groups and message resolution

**Files:**
- Modify: `backend/src/test/java/com/example/dailyreport/master/MasterControllerTest.java`
- Modify: `backend/src/test/java/com/example/dailyreport/master/MasterDataRepositoryTest.java`
- Create: `backend/src/test/java/com/example/dailyreport/master/MessageCatalogServiceTest.java`
- Modify: `backend/src/test/java/com/example/dailyreport/common/ApiExceptionHandlerTest.java`
- Modify: `backend/src/test/java/com/example/dailyreport/common/ApiExceptionTest.java` if required by the constructor contract

**Interfaces:**
- Consumes: AC-MSG-001..004.
- Produces: failing tests for `groups()`, `MessageCatalogService.resolve`, locale catalog retrieval, TTL reuse/refresh, DB fallback, and error message resolution.

- [ ] Add API tests for unauthenticated, employee, manager, and admin group responses.
- [ ] Add repository tests for enabled filtering and `display_order, group_id` ordering.
- [ ] Add message service tests for DB text, default fallback, DB exception fallback, locale, and expiry-driven reload.
- [ ] Add handler tests proving an exception key is rendered as DB text while the response contract remains `message` and `details[].message`.
- [ ] Run the focused tests and confirm RED because the new production APIs do not exist.

### Task 3: Backend schema, group API, and message catalog

**Files:**
- Modify: `backend/src/main/resources/db/oracle/schema-login.sql`
- Modify: `backend/src/main/resources/db/oracle/schema-daily-report.sql`
- Modify: `backend/src/main/resources/db/oracle/seed-master-data.sql`
- Modify: `backend/src/main/java/com/example/dailyreport/config/DataInitializer.java`
- Modify: `backend/src/main/java/com/example/dailyreport/master/MasterDataRepository.java`
- Modify: `backend/src/main/java/com/example/dailyreport/master/MasterController.java`
- Create: `backend/src/main/java/com/example/dailyreport/master/MessageCatalogRepository.java`
- Create: `backend/src/main/java/com/example/dailyreport/master/MessageCatalogService.java`
- Create: `backend/src/main/java/com/example/dailyreport/master/MessageCatalogDefaults.java`
- Create: `backend/src/main/java/com/example/dailyreport/master/MessageCatalogController.java`
- Modify: `backend/src/main/java/com/example/dailyreport/common/ApiException.java`
- Modify: `backend/src/main/java/com/example/dailyreport/common/ApiExceptionHandler.java`
- Modify: `backend/src/main/java/com/example/dailyreport/config/SecurityConfig.java`
- Modify: backend production callers that currently construct user-facing `ApiException` messages

**Interfaces:**
- Consumes: the RED tests from Task 2.
- Produces: `MasterDataRepository.groups()`, `MessageCatalogService.resolve(String key, String fallback)`, `MessageCatalogService.messages(String locale)`, `/api/master/groups`, `/api/master/messages?locale=ja-JP`, and keyed `ApiException`/`ErrorDetail` support.

- [ ] Add `groups` before dependent tables and `message_catalog` to both Oracle schema variants, including keys, `enabled`, timestamps, and required foreign keys.
- [ ] Seed G001/G002/G900 and all migrated message keys in SQL and DataInitializer using merge semantics.
- [ ] Implement group retrieval with role-aware filtering while preserving the existing permission repository boundary.
- [ ] Implement message lookup with a bounded 5-minute cache, locale handling, safe defaults, and `DataAccessException` fallback.
- [ ] Keep error codes and rule execution in source; migrate only display text to stable keys.
- [ ] Ensure SecurityConfig uses the same resolver for 401/403 and does not expose DB exception details.
- [ ] Run focused Backend tests and confirm GREEN.

### Task 4: Backend group snapshot and message regression tests

**Files:**
- Modify: `backend/src/main/java/com/example/dailyreport/report/DailyReportCommandService.java`
- Modify: `backend/src/main/java/com/example/dailyreport/auth/AuthController.java` only if current group display must resolve through the master
- Modify: related Backend tests for daily report creation and auth response
- Modify: `docs/AI活用開発研究/サンプル設計書/API一覧.md`
- Modify: `docs/AI活用開発研究/サンプル設計書/DB概念設計.md`

**Interfaces:**
- Consumes: `MasterDataRepository.groupName` or equivalent current-master lookup and existing report snapshot contract.
- Produces: regression evidence that new daily reports snapshot the DB group name while existing reports keep their stored name.

- [ ] Add a failing regression test for group-name change before report creation.
- [ ] Resolve the current group name from the DB master for new snapshots, with a safe fallback only for legacy rows where the master is unavailable.
- [ ] Preserve stored `daily_reports.group_name` on detail/list conversion.
- [ ] Update API/DB design documents to match the physical `enabled` convention and implemented endpoints.
- [ ] Run affected Backend tests and keep the status/role/workflow assertions unchanged.

### Task 5: Frontend message catalog and main display migration

**Files:**
- Create: `frontend/src/shared/messageCatalog.tsx`
- Create: `frontend/src/shared/messageApi.ts`
- Modify: `frontend/src/main.tsx`
- Modify: `frontend/src/shared/apiClient.ts`
- Modify: `frontend/src/app/App.tsx`
- Modify: `frontend/src/auth/LoginForm.tsx`
- Modify: `frontend/src/auth/loginValidation.ts`
- Modify: `frontend/src/dailyReport/DailyReportCalendarList.tsx`
- Modify: `frontend/src/dailyReport/DailyReportDetail.tsx`
- Modify: `frontend/src/dailyReport/DailyReportForm.tsx`
- Modify: `frontend/src/dailyReport/DailyReportPendingApprovalList.tsx`
- Modify: `frontend/src/dailyReport/dailyReportApproval.ts`
- Modify: `frontend/src/dailyReport/dailyReportSearch.ts`
- Modify: `frontend/src/dailyReport/dailyReportValidation.ts`
- Create: `frontend/test/messageCatalog.test.tsx`
- Modify: affected existing UI tests without changing their expected fallback behavior

**Interfaces:**
- Consumes: `GET /api/master/messages?locale=ja-JP`, `MessageCatalogService.messages`, and source fallback map.
- Produces: `MessageProvider`, `useMessage(key, fallback?)`, and fallback-aware shared display text.

- [ ] Add a typed message API and Context with source fallback defaults and a 5-minute refresh policy.
- [ ] Load the provider from `main.tsx`; keep direct component tests valid through a fallback context default.
- [ ] Replace duplicated approval status labels and principal user-facing API/local validation messages with stable keys.
- [ ] Keep status codes and validation decisions unchanged; only rendered text becomes configurable.
- [ ] Add tests for DB-catalog override, unavailable catalog fallback, and unchanged status/validation behavior.
- [ ] Run Frontend RED/GREEN cycles, then lint, typecheck, build, and full unit tests.

### Task 6: E2E, Oracle, and quality-gate verification

**Files:**
- Modify: `frontend/e2e/daily-report.spec.ts` or its support fixtures only when the message API requires a deterministic mock
- Modify: `frontend/e2e/support/*.ts` only for the new catalog response
- Modify: `docs/AI活用開発研究/作業記録/区分メッセージDB化_テストケース.md`
- Create: `docs/AI活用開発研究/作業記録/区分メッセージDB化_実装後レビュー.md`
- Create: `docs/AI活用開発研究/作業記録/区分メッセージDB化_品質記録.md`

**Interfaces:**
- Consumes: all implemented APIs and test IDs.
- Produces: E2E/Oracle/coverage/static-analysis evidence and explicit unexecuted reasons.

- [ ] Add the message API to deterministic Mock E2E fixtures and verify status/error display remains stable.
- [ ] Run the affected Mock E2E and required BrowserCase.
- [ ] Run Backend Oracle tests through the project Oracle entry point when credentials are available; otherwise retain the `ORA-01017` blocker and CI recheck condition.
- [ ] Run Frontend coverage and Backend JaCoCo/quality checks according to the project gate.
- [ ] Perform P0/P1 self-review and independent reviews for design, test sufficiency, security, placement, CI, expectations, and traceability.
- [ ] Record every finding with `FIND-` ID, standardization judgment, fix or hold reason, and recheck condition.
- [ ] Run the final verification commands before claiming completion.
