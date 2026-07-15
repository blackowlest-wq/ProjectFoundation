# Login Screen Test Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add executable App-level login screen tests and LoginForm API-error coverage for the gaps identified in `D-LOGIN-021`.

**Architecture:** Keep production boundaries unchanged. Test `App` through its real React state transitions while mocking only authentication API calls and unrelated daily-report child components. Extend the existing `LoginForm.test.tsx` with the real `LoginForm` error branch and then synchronize the test-case and defect records.

**Tech Stack:** React 19, TypeScript, Vitest 4, jsdom, React `createRoot`, npm scripts, Markdown/CSV quality checks.

## Global Constraints

- Frontend unit tests remain under `frontend/test`.
- Existing test helpers and `act` usage remain the pattern for React rendering.
- Do not expose passwords, cookies, or API credentials in test output or records.
- Use the repository test gates: test layout check, Vitest, lint, typecheck, and build.
- Record the test IDs, acceptance IDs, review IDs, and defect status in the login documents.

---

### Task 1: Add App authentication-state tests

**Files:**

- Create: `frontend/test/App.test.tsx`
- Read: `frontend/src/app/App.tsx`, `frontend/src/auth/authApi.ts`, `frontend/src/auth/LoginForm.tsx`

**Interfaces:**

- Consumes: `App` default export; mocked `fetchMe`, `login`, and `logout` from `authApi`.
- Produces: executable cases `FE-AUTH-013` through `FE-AUTH-016` covering App state transitions.

- [ ] **Step 1: Write the failing/coverage tests**

Create a jsdom test harness using `createRoot`, `act`, a DOM container, and `window.history.replaceState`. Mock `DailyReportCalendarList` and `DailyReportForm` so the test is limited to authentication state. Add these tests:

```typescript
it('shows the login screen when the initial session is unauthenticated', async () => {
  vi.mocked(fetchMe).mockResolvedValue(null);
  await renderApp();

  expect(document.querySelector('h1')?.textContent).toBe('ログイン');
  expect(document.querySelector('.topbar')).toBeNull();
});

it.each([
  ['EMPLOYEE', '/daily-reports'],
  ['MANAGER', '/pending-approvals'],
  ['ADMIN', '/monthly-summaries'],
] as const)('moves to the %s initial path after login', async (role, expectedPath) => {
  vi.mocked(fetchMe).mockResolvedValue(null);
  vi.mocked(login).mockResolvedValue({ ...currentUser, role });
  await renderApp();
  await submitLogin('employee001', 'password');

  expect(window.location.pathname).toBe(expectedPath);
  expect(document.body.textContent).toContain('山田 太郎');
});

it('returns to the login screen after logout succeeds', async () => {
  vi.mocked(fetchMe).mockResolvedValue(currentUser);
  vi.mocked(logout).mockResolvedValue(undefined);
  await renderApp();
  await clickLogout();

  expect(window.location.pathname).toBe('/login');
  expect(document.querySelector('h1')?.textContent).toBe('ログイン');
});

it('keeps the authenticated screen and shows an error when logout fails', async () => {
  vi.mocked(fetchMe).mockResolvedValue(currentUser);
  vi.mocked(logout).mockRejectedValue(new Error('logout failed'));
  await renderApp();
  await clickLogout();

  expect(document.querySelector('.topbar')).not.toBeNull();
  expect(document.querySelector('[role="alert"]')?.textContent).toBe('ログアウトに失敗しました。時間をおいて再度お試しください。');
});
```

- [ ] **Step 2: Run the App tests and inspect the result**

Run from `frontend`:

```powershell
npm.cmd test -- --run test/App.test.tsx
```

Expected: the new tests execute against the current `App` implementation. Any failure must be classified as test harness error or a genuine behavior gap before changing production code.

- [ ] **Step 3: Keep production changes minimal**

If the tests expose a real behavior gap, change only the relevant authentication state handling in `frontend/src/app/App.tsx`; do not refactor daily-report components. If all specified behavior already exists, make no production change and retain the tests as regression coverage.

- [ ] **Step 4: Run the App tests again**

Run:

```powershell
npm.cmd test -- --run test/App.test.tsx
```

Expected: all App authentication-state cases pass.

### Task 2: Add LoginForm API-error display coverage

**Files:**

- Modify: `frontend/test/LoginForm.test.tsx`
- Read: `frontend/src/auth/LoginForm.tsx`, `frontend/src/shared/apiClient.ts`

**Interfaces:**

- Consumes: existing `renderLoginForm`, `inputByLabel`, `change`, and `submit` helpers.
- Produces: `FE-AUTH-017` covering the `LoginForm` API-error catch branch.

- [ ] **Step 1: Add the case before any production change**

Add one test that stubs `fetch` with a JSON `401` response, submits valid credentials, and asserts the API message is rendered in `[role="alert"]`.

```typescript
it('shows the API error message when login fails', async () => {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue(jsonResponse({
    code: 'AUTHENTICATION_FAILED',
    message: 'ログインIDまたはパスワードが正しくありません。',
    details: [],
  }, { status: 401 })));
  renderLoginForm();

  change(inputByLabel(LOGIN_FORM_TEXT.loginIdLabel), 'employee001');
  change(inputByLabel(LOGIN_FORM_TEXT.passwordLabel), 'wrong');
  await submit();

  expect(document.querySelector('[role="alert"]')?.textContent).toBe('ログインIDまたはパスワードが正しくありません。');
});
```

- [ ] **Step 2: Run the focused LoginForm test**

Run:

```powershell
npm.cmd test -- --run test/LoginForm.test.tsx
```

Expected: the test either passes against the existing error branch or fails with a concrete rendering mismatch. Do not weaken the assertion.

- [ ] **Step 3: Fix only if required**

If the focused test fails because the implemented contract does not render the API message, update `LoginForm.tsx` to preserve the existing fallback while rendering `ApiError.message`. If it passes, do not alter production behavior.

- [ ] **Step 4: Run the focused LoginForm test again**

Expected: all LoginForm tests pass.

### Task 3: Synchronize quality records

**Files:**

- Modify: `docs/AI活用開発研究/作業記録/ログイン機能_テストケース.md`
- Modify: `docs/AI活用開発研究/作業記録/ログイン機能_テストケース品質レビュー_2026-07-15.md`
- Modify: `docs/AI活用開発研究/作業記録/ログイン機能_作業記録.md`
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md`
- Modify: `docs/AI活用開発研究/構想メモ/検証記録/欠陥記録.csv`

**Interfaces:**

- Consumes: actual test names and execution counts from Tasks 1 and 2.
- Produces: traceability for `FE-AUTH-013`～`FE-AUTH-017`; updated `D-LOGIN-021` status.

- [ ] **Step 1: Update the case table**

Record each new case with its acceptance IDs, `D-LOGIN-021`, actual test name, expected-result review, and specialist review ID. Use `LOGIN-APP-001`～`003` for App cases and `LOGIN-APP-002` for the LoginForm error display candidate only if the test is accepted under that existing candidate.

- [ ] **Step 2: Update defect status**

Set `D-LOGIN-021` to `対応済み` only when all four App transitions and the LoginForm error display test pass. Otherwise retain `保留` and record the exact failing behavior and recheck condition.

- [ ] **Step 3: Update work and findings records**

Add the test files, exact command results, and any production fix to the login work record. Update the findings list so the previous `DR-C-019` status matches the defect record.

### Task 4: Run the complete verification gate

**Files:**

- Verify: `frontend/test/App.test.tsx`, `frontend/test/LoginForm.test.tsx`, all related Markdown and CSV records

- [ ] **Step 1: Run all Frontend tests**

```powershell
cd frontend
npm.cmd test -- --run
```

Expected: all test files and tests pass, including the new App and LoginForm cases.

- [ ] **Step 2: Run static and build checks**

```powershell
npm.cmd run lint
npm.cmd run typecheck
npm.cmd run build
```

Expected: all commands exit 0.

- [ ] **Step 3: Run documentation and CSV checks**

```powershell
cd ..
npx.cmd --no-install markdownlint-cli2 --no-globs docs/AI活用開発研究/作業記録/ログイン機能_テストケース.md docs/AI活用開発研究/作業記録/ログイン機能_テストケース品質レビュー_2026-07-15.md docs/AI活用開発研究/作業記録/ログイン機能_作業記録.md docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md
git diff --check
```

Expected: Markdown has zero errors, CSV remains 30 columns with unique defect IDs, and `git diff --check` has no errors.
