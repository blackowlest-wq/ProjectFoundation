# 日報承認・差し戻し Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 上長が担当グループの日報を未承認一覧・詳細画面から承認またはコメント付きで差し戻しでき、監査情報を保存して社員の既存再提出フローへ接続する。

**Architecture:** 既存の日報更新系とは別に `DailyReportApprovalController` / `DailyReportApprovalService` を追加し、状態変更と認可を承認ユースケースへ閉じ込める。検索系とは別に `DailyReportPendingApprovalController` / `DailyReportPendingApprovalService` を追加し、担当グループかつ `PENDING` の一覧だけを返す。React側は `DailyReportPendingApprovalList` と `DailyReportDetail` を日報機能配下へ追加し、既存のCookieセッション、CSRF、APIエラー変換、AppのURL判定を利用する。

**Tech Stack:** Java 21、Spring Boot、Spring Data JPA、Oracle/H2テストDB、React 19、TypeScript、Vitest、Playwright。

## Global Constraints

- APIの承認・差し戻しは `/api/daily-reports/{reportId}/approve` と `/api/daily-reports/{reportId}/reject` を使用する。
- 承認・差し戻し対象は `PENDING` の日報だけとし、不正状態はHTTP 409と`INVALID_STATUS`で拒否する。
- 上長の担当グループ判定は既存の`manager_group_permissions`と`DailyReportAccessPolicy`を使用する。
- 差し戻しコメントは空白除去後1文字以上、最大1000文字とし、バックエンドを最終判定とする。
- 更新系APIは既存のCookieセッションとCSRFヘッダー契約を使用する。
- 承認者・差し戻し者の名前は操作時点の利用者情報をスナップショットし、コメント履歴・楽観ロックは追加しない。
- テストは`frontend/test`、`frontend/e2e`、`backend/src/test`へ配置し、本番ソース配下へ置かない。
- 外部ライブラリは追加せず、既存のAPIクライアント、認証補助、テスト補助、品質ゲートを利用する。

---

### Task 1: 承認・差し戻しのドメイン、DB、API

**Files:**
- Modify: `backend/src/main/java/com/example/dailyreport/report/entity/DailyReportEntity.java`
- Create: `backend/src/main/java/com/example/dailyreport/report/dto/RejectRequest.java`
- Create: `backend/src/main/java/com/example/dailyreport/report/dto/ApproveResponse.java`
- Create: `backend/src/main/java/com/example/dailyreport/report/dto/RejectResponse.java`
- Create: `backend/src/main/java/com/example/dailyreport/report/DailyReportApprovalService.java`
- Create: `backend/src/main/java/com/example/dailyreport/report/controller/DailyReportApprovalController.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/dto/DailyReportResponse.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/dto/DailyReportListItemResponse.java`
- Modify: `backend/src/main/resources/db/oracle/schema-daily-report.sql`
- Test: `backend/src/test/java/com/example/dailyreport/report/DailyReportApprovalControllerTest.java`
- Modify: `backend/src/test/java/com/example/dailyreport/report/support/DailyReportTestSupport.java`

**Interfaces:**
- Consumes: `AuthenticatedUser`, `DailyReportRepository`, `DailyReportAccessPolicy`, `AppUser`, `ApprovalStatus`。
- Produces: `POST /api/daily-reports/{reportId}/approve`、`POST /api/daily-reports/{reportId}/reject`、Entityの承認監査項目、詳細・一覧DTOの承認監査項目。

- [ ] **Step 1: 承認・差し戻しの失敗テストを先に追加する**

`DailyReportApprovalControllerTest`に、次のテストを追加する。テスト用日報は`seedReport`で`PENDING`を作り、上長の担当グループは既存のseedを利用する。成功ケースではレスポンスとDB列を同時に確認する。

```java
@Test
void managerCanApprovePendingReport() throws Exception {
    seedReport(jdbcTemplate, "R-APPROVE-001", "U001", "E001", "山田 太郎",
            "G001", "第1開発グループ", LocalDate.of(2026, 6, 2), "PENDING");
    MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

    mockMvc.perform(post("/api/daily-reports/R-APPROVE-001/approve")
                    .with(csrf()).session(session))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.reportId", equalTo("R-APPROVE-001")))
            .andExpect(jsonPath("$.approvalStatus", equalTo("APPROVED")))
            .andExpect(jsonPath("$.approverId", equalTo("U002")))
            .andExpect(jsonPath("$.approverName", equalTo("佐藤 上長")))
            .andExpect(jsonPath("$.approvedAt", notNullValue()));

    Map<String, Object> row = jdbcTemplate.queryForMap(
            "SELECT approval_status, approver_user_id, approver_name, approved_at "
                    + "FROM daily_reports WHERE report_id = 'R-APPROVE-001'");
    assertThat(row.get("APPROVAL_STATUS")).isEqualTo("APPROVED");
    assertThat(row.get("APPROVER_USER_ID")).isEqualTo("U002");
    assertThat(row.get("APPROVER_NAME")).isEqualTo("佐藤 上長");
    assertThat(row.get("APPROVED_AT")).isNotNull();
}

@Test
void managerCanRejectPendingReportWithComment() throws Exception {
    seedReport(jdbcTemplate, "R-REJECT-001", "U001", "E001", "山田 太郎",
            "G001", "第1開発グループ", LocalDate.of(2026, 6, 3), "PENDING");
    MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

    mockMvc.perform(post("/api/daily-reports/R-REJECT-001/reject")
                    .with(csrf()).session(session)
                    .contentType(MediaType.APPLICATION_JSON)
                    .content("{\"rejectComment\":\"作業時間を確認してください。\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.approvalStatus", equalTo("REJECTED")))
            .andExpect(jsonPath("$.rejectorId", equalTo("U002")))
            .andExpect(jsonPath("$.rejectorName", equalTo("佐藤 上長")))
            .andExpect(jsonPath("$.rejectedAt", notNullValue()))
            .andExpect(jsonPath("$.rejectComment", equalTo("作業時間を確認してください。")));
}

@Test
void managerCannotApproveUnauthorizedOrNonPendingReports() throws Exception {
    seedReport(jdbcTemplate, "R-APPROVE-OUTSIDE", "U099", "E099", "他部署 社員",
            "G099", "他部署グループ", LocalDate.of(2026, 6, 4), "PENDING");
    seedReport(jdbcTemplate, "R-APPROVE-DRAFT", "U001", "E001", "山田 太郎",
            "G001", "第1開発グループ", LocalDate.of(2026, 6, 5), "DRAFT");
    MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

    mockMvc.perform(post("/api/daily-reports/R-APPROVE-OUTSIDE/approve").with(csrf()).session(session))
            .andExpect(status().isForbidden());
    mockMvc.perform(post("/api/daily-reports/R-APPROVE-DRAFT/approve").with(csrf()).session(session))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code", equalTo("INVALID_STATUS")));
}

@Test
void managerCannotRejectUnauthorizedOrNonPendingReports() throws Exception {
    seedReport(jdbcTemplate, "R-REJECT-APPROVED", "U001", "E001", "山田 太郎",
            "G001", "第1開発グループ", LocalDate.of(2026, 6, 6), "APPROVED");
    MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

    mockMvc.perform(post("/api/daily-reports/R-REJECT-APPROVED/reject")
                    .with(csrf()).session(session)
                    .contentType(MediaType.APPLICATION_JSON)
                    .content("{\"rejectComment\":\"確認してください。\"}"))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code", equalTo("INVALID_STATUS")));
}

@Test
void rejectCommentMustNotBeBlankOrLongerThan1000Characters() throws Exception {
    seedReport(jdbcTemplate, "R-REJECT-VALIDATION", "U001", "E001", "山田 太郎",
            "G001", "第1開発グループ", LocalDate.of(2026, 6, 7), "PENDING");
    MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

    mockMvc.perform(post("/api/daily-reports/R-REJECT-VALIDATION/reject")
                    .with(csrf()).session(session)
                    .contentType(MediaType.APPLICATION_JSON)
                    .content("{\"rejectComment\":\"   \"}"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
}
```

- [ ] **Step 2: テストが機能未実装で失敗することを確認する**

Run: `backend\mvnw.cmd -q -Dtest=DailyReportApprovalControllerTest test`

Expected: 新しいControllerまたはエンドポイントがないため、テストクラスがコンパイルできないか、対象POSTが404となって失敗する。既存テストの失敗は別原因として記録し、テストの期待値を変更しない。

- [ ] **Step 3: Entityへ承認監査項目と状態変更メソッドを追加する**

`DailyReportEntity`へ`approverUserId`、`approverName`、`approvedAt`とgetterを追加し、次の責務を持つメソッドを追加する。

```java
public void approve(String approverUserId, String approverName, OffsetDateTime now) {
    this.approvalStatus = ApprovalStatus.APPROVED;
    this.approverUserId = approverUserId;
    this.approverName = approverName;
    this.approvedAt = now;
}

public void reject(String rejectorUserId, String rejectorName, OffsetDateTime now, String comment) {
    this.approvalStatus = ApprovalStatus.REJECTED;
    this.approverUserId = null;
    this.approverName = null;
    this.approvedAt = null;
    this.rejectorUserId = rejectorUserId;
    this.rejectorName = rejectorName;
    this.rejectedAt = now;
    this.rejectComment = comment;
}
```

`RejectRequest`は`record RejectRequest(@NotBlank @Size(max = 1000) String rejectComment)`とし、`DailyReportApprovalService`は`@Transactional`で利用者ロール、担当グループ、現在状態を確認してからEntityメソッドを呼ぶ。空白除去後の値を保存する。

- [ ] **Step 4: DTO、Controller、Oracle DDLを実装する**

承認系Controllerは次のメソッドを持つ。

```java
@PostMapping("/{reportId}/approve")
public ApproveResponse approve(@PathVariable String reportId,
        @AuthenticationPrincipal AuthenticatedUser principal) {
    return service.approve(reportId, principal);
}

@PostMapping("/{reportId}/reject")
public RejectResponse reject(@PathVariable String reportId,
        @Valid @RequestBody RejectRequest request,
        @AuthenticationPrincipal AuthenticatedUser principal) {
    return service.reject(reportId, request, principal);
}
```

ControllerはHTTP入力、認証済みユーザー受け取り、Service呼び出し、業務イベントログだけを担当する。ログには`reportId`、利用者ID、状態、機能、ユースケースを含め、コメント本文や個人情報を出力しない。DDLには`approver_user_id VARCHAR2(20 CHAR)`、`approver_name VARCHAR2(120 CHAR)`、`approved_at TIMESTAMP WITH LOCAL TIME ZONE`を`submitted_at`の後へ追加する。

- [ ] **Step 5: DTO変換と既存回帰を確認する**

`DailyReportResponse`と`DailyReportListItemResponse`へ承認者ID、承認者名、承認日時を追加し、Entityから変換する。既存レスポンスの項目を削除せず、フロントの既存fixtureへnull項目を追加する。

Run: `backend\mvnw.cmd -q -Dtest=DailyReportApprovalControllerTest,DailyReportSearchControllerTest,DailyReportSubmissionControllerTest test`

Expected: 承認・差し戻しの新規ケースと既存の検索・提出・再提出ケースがPASSする。

- [ ] **Step 6: コミットする**

```powershell
git add backend/src/main backend/src/test
git commit -m "feat: add daily report approval and rejection API"
```

### Task 2: 未承認一覧APIと詳細APIの監査情報

**Files:**
- Create: `backend/src/main/java/com/example/dailyreport/report/DailyReportPendingApprovalService.java`
- Create: `backend/src/main/java/com/example/dailyreport/report/controller/DailyReportPendingApprovalController.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/entity/DailyReportRepository.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/DailyReportAccessPolicy.java`
- Test: `backend/src/test/java/com/example/dailyreport/report/DailyReportApprovalControllerTest.java`
- Modify: `backend/src/test/java/com/example/dailyreport/report/support/DailyReportTestSupport.java`

**Interfaces:**
- Consumes: `DailyReportSearchService`と同じ日付範囲検証方針、`DailyReportAccessPolicy.permittedGroupIds`、`DailyReportListItemResponse`。
- Produces: `GET /api/daily-reports/pending-approvals`、担当グループ限定の未承認一覧、詳細APIの監査情報。

- [ ] **Step 1: 未承認一覧の失敗テストを追加する**

次のテストを`DailyReportApprovalControllerTest`へ追加する。

```java
@Test
void pendingApprovalsReturnOnlyPermittedPendingReports() throws Exception {
    seedUser(jdbcTemplate, "U099", "E099", "other001", "他部署 社員", "EMPLOYEE", "G099", "他部署グループ");
    seedReport(jdbcTemplate, "R-PENDING-IN", "U001", "E001", "山田 太郎",
            "G001", "第1開発グループ", LocalDate.of(2026, 6, 8), "PENDING");
    seedReport(jdbcTemplate, "R-PENDING-OUT", "U099", "E099", "他部署 社員",
            "G099", "他部署グループ", LocalDate.of(2026, 6, 8), "PENDING");
    seedReport(jdbcTemplate, "R-DRAFT-IN", "U001", "E001", "山田 太郎",
            "G001", "第1開発グループ", LocalDate.of(2026, 6, 9), "DRAFT");
    MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

    mockMvc.perform(get("/api/daily-reports/pending-approvals")
                    .param("dateFrom", "2026-06-01")
                    .param("dateTo", "2026-06-30")
                    .session(session))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$[0].reportId", equalTo("R-PENDING-IN")))
            .andExpect(jsonPath("$.length()", equalTo(1)));
}

@Test
void employeeAndAdminCannotUsePendingApprovals() throws Exception {
    MockHttpSession employeeSession = loginAs(mockMvc, objectMapper, "employee001");
    mockMvc.perform(get("/api/daily-reports/pending-approvals")
                    .param("dateFrom", "2026-06-01")
                    .param("dateTo", "2026-06-30")
                    .session(employeeSession))
            .andExpect(status().isForbidden());

    MockHttpSession adminSession = loginAs(mockMvc, objectMapper, "admin001");
    mockMvc.perform(get("/api/daily-reports/pending-approvals")
                    .param("dateFrom", "2026-06-01")
                    .param("dateTo", "2026-06-30")
                    .session(adminSession))
            .andExpect(status().isForbidden());
}
```

- [ ] **Step 2: 失敗を確認する**

Run: `backend\mvnw.cmd -q -Dtest=DailyReportApprovalControllerTest#pendingApprovalsReturnOnlyPermittedPendingReports,DailyReportApprovalControllerTest#employeeAndAdminCannotUsePendingApprovals test`

Expected: `pending-approvals` endpointが未実装のため404または未解決Controllerで失敗する。

- [ ] **Step 3: 未承認検索を実装する**

`DailyReportPendingApprovalService`で、上長を`requireManager`へ通し、日付範囲を既存の検索ルールで検証する。Specificationへ`approvalStatus = PENDING`と許可グループ条件を必ず追加し、`reportDate`、`employeeId`の昇順で返す。担当グループが0件の場合は空配列を返す。

`DailyReportPendingApprovalController`は`@GetMapping("/pending-approvals")`で専用パスを受け、Serviceへ委譲する。既存の`GET /api/daily-reports/{reportId}`とのPathVariable競合を避けるため、検索系Controllerへ追記しない。

- [ ] **Step 4: 詳細DTOの監査項目を検証する**

承認後・差し戻し後の`GET /api/daily-reports/{reportId}`で`approverId`、`approverName`、`approvedAt`、`rejectorId`、`rejectorName`、`rejectedAt`、`rejectComment`を確認するAPIテストを追加する。社員、担当上長、管理者の参照範囲と、担当外上長・不存在IDの拒否を維持する。

- [ ] **Step 5: コミットする**

```powershell
git add backend/src/main backend/src/test
git commit -m "feat: add pending daily report approvals endpoint"
```

### Task 3: フロントエンドAPIと純粋ロジック

**Files:**
- Modify: `frontend/src/dailyReport/types.ts`
- Modify: `frontend/src/dailyReport/dailyReportApi.ts`
- Create: `frontend/src/dailyReport/dailyReportApproval.ts`
- Create: `frontend/test/dailyReportApproval.test.ts`
- Modify: `frontend/test/dailyReportApi.test.ts`

**Interfaces:**
- Consumes: `getJson`, `postJsonWithCsrf`, `ApprovalStatus`、既存の日報DTO。
- Produces: `approveDailyReport`、`rejectDailyReport`、`fetchPendingApprovals`、拒否コメント検証、当月検索条件。

- [ ] **Step 1: API関数と純粋ロジックの失敗テストを追加する**

`dailyReportApproval.test.ts`へ次の期待を追加する。

```typescript
it('rejects blank and overlong rejection comments', () => {
  expect(validateRejectComment('   ')).toBe('差し戻しコメントを入力してください。');
  expect(validateRejectComment('a'.repeat(1001))).toBe('差し戻しコメントは1000文字以内で入力してください。');
  expect(validateRejectComment('確認してください。')).toBe('');
});

it('creates current-month pending approval criteria', () => {
  expect(pendingApprovalCriteria('2026-07')).toEqual({
    targetMonth: '2026-07',
    dateFrom: '2026-07-01',
    dateTo: '2026-07-31',
    groupId: '',
    employeeId: '',
  });
});
```

`dailyReportApi.test.ts`へ、approveが本文なしPOST、rejectがJSON本文付きPOST、pending approvalsが指定クエリ付きGETを送ることを追加する。

- [ ] **Step 2: 失敗を確認する**

Run: `npm.cmd --prefix frontend test -- dailyReportApproval.test.ts dailyReportApi.test.ts`

Expected: 新しい関数が未定義のため失敗する。

- [ ] **Step 3: 型とAPIクライアントを追加する**

`types.ts`へ次を追加する。

```typescript
export type ApproveResponse = {
  reportId: string;
  approvalStatus: 'APPROVED';
  approverId: string;
  approverName: string;
  approvedAt: string;
};

export type RejectResponse = {
  reportId: string;
  approvalStatus: 'REJECTED';
  rejectorId: string;
  rejectorName: string;
  rejectedAt: string;
  rejectComment: string;
};
```

`dailyReportApi.ts`へ次を追加する。

```typescript
export async function approveDailyReport(reportId: string): Promise<ApproveResponse> {
  return postNoBodyWithCsrf<ApproveResponse>(`/api/daily-reports/${encodeURIComponent(reportId)}/approve`);
}

export async function rejectDailyReport(reportId: string, rejectComment: string): Promise<RejectResponse> {
  return postJsonWithCsrf<RejectResponse>(`/api/daily-reports/${encodeURIComponent(reportId)}/reject`, { rejectComment });
}

export async function fetchPendingApprovals(criteria: PendingApprovalCriteria): Promise<DailyReportListItem[]> {
  return getJson<DailyReportListItem[]>(buildPendingApprovalUrl(criteria));
}
```

`dailyReportApproval.ts`では1000文字上限、前後空白除去、`monthRange`再利用、URLSearchParamsによるURL生成を実装する。既存のAPIクライアント以外のfetchを追加しない。

- [ ] **Step 4: テストを通す**

Run: `npm.cmd --prefix frontend test -- dailyReportApproval.test.ts dailyReportApi.test.ts`

Expected: 新規API・純粋ロジックテストがPASSし、既存APIテストもPASSする。

- [ ] **Step 5: コミットする**

```powershell
git add frontend/src frontend/test
git commit -m "feat: add approval frontend API client"
```

### Task 4: 未承認一覧・日報詳細・差し戻しUI

**Files:**
- Create: `frontend/src/dailyReport/DailyReportPendingApprovalList.tsx`
- Create: `frontend/src/dailyReport/DailyReportDetail.tsx`
- Modify: `frontend/src/app/App.tsx`
- Modify: `frontend/src/dailyReport/DailyReportCalendarList.tsx`
- Modify: `frontend/src/styles.css`
- Create: `frontend/test/DailyReportApprovalPanel.test.tsx`

**Interfaces:**
- Consumes: Task 1/2のAPI、Task 3の型・API・検証関数、`CurrentUser`、既存の401処理。
- Produces: 上長専用未承認一覧、認可範囲の日報詳細、承認ボタン、差し戻し入力ダイアログ、詳細リンク。

- [ ] **Step 1: 画面の失敗テストを追加する**

`DailyReportApprovalPanel.test.tsx`へ次のケースを追加する。

```tsx
it('shows pending reports and opens their detail link for managers', async () => {
  render(<DailyReportPendingApprovalList user={manager} />);
  expect(await screen.findByText('山田 太郎')).toBeVisible();
  expect(screen.getByRole('link', { name: '詳細' })).toHaveAttribute('href', '/daily-reports/R-PENDING-001');
  expect(screen.getByRole('button', { name: '承認' })).toBeVisible();
  expect(screen.getByRole('button', { name: '差し戻し' })).toBeVisible();
});

it('requires a comment before sending rejection', async () => {
  const user = userEvent.setup();
  render(<DailyReportDetail user={manager} reportId="R-PENDING-001" />);
  await screen.findByText('山田 太郎');
  await user.click(screen.getByRole('button', { name: '差し戻しする' }));
  await user.click(screen.getByRole('button', { name: '差し戻しを確定' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('差し戻しコメントを入力してください。');
  expect(rejectDailyReportMock).not.toHaveBeenCalled();
});

it('shows approval audit values after approving a pending report', async () => {
  const user = userEvent.setup();
  render(<DailyReportDetail user={manager} reportId="R-PENDING-001" />);
  await screen.findByText('山田 太郎');
  await user.click(screen.getByRole('button', { name: '承認する' }));
  expect(await screen.findByText('承認済み')).toBeVisible();
  expect(screen.getByText('佐藤 上長')).toBeVisible();
});
```

社員・管理者には未承認一覧を表示しないこと、詳細画面では担当範囲外・ロード失敗時に操作ボタンを表示しないことも追加する。

- [ ] **Step 2: 失敗を確認する**

Run: `npm.cmd --prefix frontend test -- DailyReportApprovalPanel.test.tsx`

Expected: コンポーネントが未作成またはAppから接続されていないため失敗する。

- [ ] **Step 3: 未承認一覧を実装する**

`DailyReportPendingApprovalList`は、当月初期条件で`fetchPendingApprovals`を呼ぶ。検索中、エラー、0件、一覧表示、詳細リンクを分けて表示する。承認・差し戻しボタンは一覧の直接操作ではなく詳細画面への入口として配置し、状態変更の主処理を詳細画面へ集約する。

- [ ] **Step 4: 詳細画面とダイアログを実装する**

`DailyReportDetail`は`fetchDailyReport`で詳細を取得し、ヘッダ、作業明細、状態、提出日時、承認監査情報、差し戻し監査情報を読み取り専用で表示する。`MANAGER`かつ`PENDING`の場合だけ状態変更ボタンを表示する。承認成功時はレスポンスで状態・監査項目を更新し、差し戻し成功時は詳細を再取得する。入力中、失敗、401、409では安全側にボタンを無効化・非表示にする。

`App.tsx`へ次のURL判定を追加する。

```typescript
function detailReportIdFromPath(): string | null {
  const match = window.location.pathname.match(/^\/daily-reports\/([^/]+)$/);
  return match ? decodeURIComponent(match[1]) : null;
}
```

詳細URLでは`DailyReportDetail`、社員の`/edit`では既存`DailyReportForm`、通常のロール別初期URLでは既存一覧を表示する。上長の初期画面には`DailyReportPendingApprovalList`を追加する。

- [ ] **Step 5: 一覧から詳細へ遷移できるようにする**

`DailyReportCalendarList`の一覧行へ`<a href={`/daily-reports/${encodeURIComponent(report.reportId)}`}>詳細</a>`を追加する。カレンダーの状態色、検索条件、既存の社員向け画面挙動は変更しない。

- [ ] **Step 6: 画面テストを通す**

Run: `npm.cmd --prefix frontend test -- DailyReportApprovalPanel.test.tsx dailyReportCalendarList.test.tsx App.test.tsx`

Expected: 承認・差し戻し画面と既存の一覧・App回帰がPASSする。

- [ ] **Step 7: コミットする**

```powershell
git add frontend/src frontend/test
git commit -m "feat: add daily report approval screens"
```

### Task 5: 承認・差し戻しのMock E2E

**Files:**
- Create: `frontend/e2e/approval-rejection.spec.ts`
- Create: `frontend/e2e/support/dailyReportApprovalMocks.ts`
- Modify: `frontend/e2e/support/dailyReportMocks.ts`

**Interfaces:**
- Consumes: 実装済みのログインモック、静的Frontend配信、承認API、差し戻しAPI、詳細API、未承認一覧API。
- Produces: `RT-APR-E2E-001`、`RT-APR-E2E-002`、`RT-APR-E2E-003`のPlaywright証跡。

- [ ] **Step 1: Mock E2Eを先に追加する**

`approval-rejection.spec.ts`へ次の3シナリオを追加する。

```typescript
test('manager approves a pending report from the detail screen', async ({ page }) => {
  await mockApprovalApis(page, { user: manager });
  await mockStaticFrontend(page);
  await loginAsManager(page);
  await page.getByRole('link', { name: '詳細' }).click();
  await expect(page.getByRole('heading', { name: '日報詳細' })).toBeVisible();
  await page.getByRole('button', { name: '承認する' }).click();
  await expect(page.getByText('承認済み')).toBeVisible();
  await expect(page.getByText('佐藤 上長')).toBeVisible();
});

test('manager rejects a pending report and employee can see the comment', async ({ page }) => {
  await mockApprovalApis(page, { user: manager });
  await mockStaticFrontend(page);
  await loginAsManager(page);
  await page.getByRole('link', { name: '詳細' }).click();
  await page.getByRole('button', { name: '差し戻しする' }).click();
  await page.getByLabel('差し戻しコメント').fill('作業内容を補足してください。');
  await page.getByRole('button', { name: '差し戻しを確定' }).click();
  await expect(page.getByText('差戻し')).toBeVisible();
  await expect(page.getByText('作業内容を補足してください。')).toBeVisible();
});

test('employee and admin do not see approval controls', async ({ page }) => {
  await mockApprovalApis(page);
  await mockStaticFrontend(page);
  await loginAsEmployee(page);
  await page.goto('/daily-reports/R-PENDING-001');
  await expect(page.getByRole('button', { name: '承認する' })).not.toBeVisible();
  await expect(page.getByRole('button', { name: '差し戻しする' })).not.toBeVisible();
});
```

- [ ] **Step 2: E2EがUI未実装で失敗することを確認する**

Run: `npm.cmd --prefix frontend run e2e -- approval-rejection.spec.ts`

Expected: 承認・差し戻し画面または操作要素がないため失敗する。

- [ ] **Step 3: 通信モックを追加する**

`dailyReportApprovalMocks.ts`に、社員・上長・管理者の認証応答、`pending-approvals`の一覧、詳細GET、approve/reject POSTの状態変更応答を追加する。既存の編集用モックの報告状態を壊さないため、承認系モックを別ファイルへ分離する。

- [ ] **Step 4: E2Eを通す**

Run: `npm.cmd --prefix frontend run e2e -- approval-rejection.spec.ts`

Expected: 3シナリオがPASSし、承認者・差し戻しコメント・ロール別操作可否を画面で確認できる。

- [ ] **Step 5: コミットする**

```powershell
git add frontend/e2e
git commit -m "test: cover daily report approval and rejection flow"
```

### Task 6: 実装前後の記録、レビュー、品質ゲート

**Files:**
- Create: `docs/AI活用開発研究/作業記録/日報承認差戻し_作業記録.md`
- Create: `docs/AI活用開発研究/作業記録/日報承認差戻し_受入条件レビュー.md`
- Create: `docs/AI活用開発研究/作業記録/日報承認差戻し_テストケース.md`
- Create: `docs/AI活用開発研究/作業記録/日報承認差戻し_テストケースレビュー.md`
- Create: `docs/AI活用開発研究/作業記録/日報承認差戻し_セキュリティレビュー.md`
- Create: `docs/AI活用開発研究/作業記録/日報承認差戻し_可読性レビュー.md`
- Create: `docs/AI活用開発研究/作業記録/日報承認差戻し_実装後レビュー.md`
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md`

**Interfaces:**
- Consumes: 設計書の`TC-APR-*`、実装差分、各テスト結果、P0/P1レビュー結果。
- Produces: 作業記録、レビュー記録、指摘の標準化判定、最終品質ゲート結果。

- [ ] **Step 1: 正本ケースと実装前記録を作成する**

設計書のトレーサビリティ表を`日報承認差戻し_テストケース.md`へ転記し、各ケースへ期待結果、観測対象、テスト層、実テストID欄、対象外・保留理由を記載する。`日報承認差戻し_受入条件レビュー.md`へF-005/F-007/F-008/F-010とAPI/画面設計の照合結果、採用した仮定、保留事項を記録する。

- [ ] **Step 2: P0/P1レビューを独立に実施する**

次の具体的な資料と節をレビュー入力へ渡し、結果を別々に作成する。

1. 設計照合: `実装前チェック表.md`、機能一覧F-005/F-007/F-008/F-010、API一覧A-009/A-012/A-013/A-015、画面設計S-005/S-006/S-007、DB概念設計の日報監査項目。
2. テスト不足・構成: `テストケースレビュー観点.md`の基本観点と「テスト構成・責務分割観点」、`テスト方針.md`の「テスト配置とユースケース分割」、専用ケースと全追加テスト。
3. 期待結果: `テストケースレビュー観点.md`の「期待結果レビュー観点」、API本文・DB監査列・画面・ログのアサーション。
4. セキュリティ: `セキュリティ規約.md`、`AI専門レビュー用プロンプト定義.md`の03、承認・差し戻し・未承認一覧・詳細APIとCSRF/IDOR/ロール制御。
5. 配置・共通化: `ディレクトリ構成ルール.md`、`共通部品化判断基準.md`、新規Controller/Service/DTO/React部品/test support。
6. 静的解析・品質ゲート: `テスト・静的解析チェック表.md`、`品質ゲート運用.md`、`scripts/check.ps1`の実行対象。

2観点以上の独立レビューを行う場合は、`superpowers:dispatching-parallel-agents`を使用し、担当へ他担当の結論を渡さない。最後に統合担当が重複・矛盾・保留を整理する。

- [ ] **Step 3: 指摘を修正し標準化判定を記録する**

各指摘へ`FIND-APR-*`を付与し、対応/保留、修正ファイル、確認テスト、標準化判定（個別対応、既存観点で対応、標準化候補、対象外、保留）、反映先、保留理由、再確認条件を記録する。レビューで検出した問題は作業記録だけでなく`日報登録編集_指摘一覧.md`へ追加または更新する。

- [ ] **Step 4: 最終品質ゲートを実行する**

Run:

```powershell
pwsh -NoProfile -File scripts/check.ps1 -Mode Quick
pwsh -NoProfile -File scripts/check.ps1 -Mode Full
pwsh -NoProfile -File scripts/check.ps1 -CiTask FrontendCoverage
pwsh -NoProfile -File scripts/check.ps1 -CiTask E2E
pwsh -NoProfile -File scripts/check.ps1 -Mode Oracle
pwsh -NoProfile -File scripts/check.ps1 -CiTask BackendCoverage
```

Expected: 変更対象のlint、Markdown lint、型チェック、Frontend unit/build/E2E、Backend test-compile/test/static analysis、coverageが成功する。Oracle資格情報・runnerがない場合はOracle系を成功扱いにせず、未実行理由と再確認条件を作業記録へ残す。

- [ ] **Step 5: 最終レビューを記録する**

`日報承認差戻し_実装後レビュー.md`へ、P0/P1レビュー結果、テスト構成判定、最終品質ゲート、未実行項目、指摘の統合結果を記録する。`git status`でworktreeの意図しない生成物がないことを確認し、最終コミットを作成する。

## Plan Self-Review

- F-005/F-007/F-008/F-010、A-009/A-012/A-013/A-015、S-005/S-006/S-007をTask 1～5でカバーした。
- 承認監査列、差し戻し監査列、状態遷移、権限、CSRF、コメント検証、未承認一覧、詳細画面、E2EをTask 1～5へ割り当てた。
- 計画中の未確定メソッド名や曖昧な「適切に実装する」記述を含めない。
- 既存の提出・再提出・検索テストは維持し、承認ユースケース専用テストを新規ファイルへ分離した。
- Oracle実行不能時は成功扱いにせず、Task 6で理由と再確認条件を記録する。
