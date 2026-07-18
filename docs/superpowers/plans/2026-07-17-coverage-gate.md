# Coverage Threshold and Branch Coverage Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** FrontendとBackendのStatements、Branches、Functions、Linesを85%以上へ判定し、未達時に詳細レポートを残してテスト追加後の同一入口再実行を強制する。

**Architecture:** VitestとJaCoCoの標準threshold/checkを判定の正本にする。`scripts/check.ps1`はcoverage実行、レポート存在確認、失敗集約、再実行案内を担当し、GitHub Actionsは失敗時もcoverage artifactを保存する。テストは未通過分岐をレポートから特定し、既存のユースケース別テストへ追加する。

**Tech Stack:** PowerShell 7、Node.js 24.18.0、npm 11.16.0、Vitest 4.1.9、`@vitest/coverage-v8`、Java 21、Maven Wrapper 3.3.4、Maven core 3.9.16、JaCoCo 0.8.12、JUnit 5、Spring Boot 3.3.6、GitHub Actions。

## Global Constraints

- Frontendのcoverage閾値はStatements / Branches / Functions / Linesを各85%、グローバル単位とする。
- Backendのcoverage閾値はJaCoCo INSTRUCTION / BRANCH / METHOD / LINEを各0.85、BUNDLE単位とする。
- Vitestのcoverage対象は`frontend/src/**/*.{ts,tsx}`とし、業務コードを閾値回避のために除外しない。
- Oracle接続情報は`backend/config/oracle-test.properties`または保護されたprocess環境だけから読み取る。
- `backend`のテストは`backend/scripts/test-oracle.ps1`を共通入口とし、直接`mvn.cmd`を品質ゲートの入口にしない。
- coverage、target、Playwright report、Oracle設定はGitへ追加しない。
- 既存のユーザー変更（README、標準化資料、作業記録、未追跡計画）は上書き・巻き戻ししない。
- 実装前にVitestとJaCoCoの公式ドキュメントを確認し、判断を作業記録へ残す。
- カバレッジを満たすためだけの本番コード変更、業務コードの除外、同一テストの無条件自動リトライは行わない。

---

### Task 1: Coverage configuration and runner contract tests

**Files:**

- Create: `frontend/test/coverageConfig.test.ts`
- Create: `scripts/coverage-gate.tests.ps1`

**Interfaces:**

- Consumes: current `frontend/vite.config.ts` and `scripts/check.ps1` exports after dot-sourcing.
- Produces: failing executable contracts for coverage thresholds, report reporters, and the Backend `verify` command.

- [ ] **Step 1: Write the failing Frontend configuration test**

Create `frontend/test/coverageConfig.test.ts`:

```ts
import { describe, expect, test } from 'vitest';
import config from '../vite.config';

type CoverageConfig = {
  clean?: boolean;
  include?: string[];
  reporter?: string[];
  reportsDirectory?: string;
  reportOnFailure?: boolean;
  thresholds?: { branches?: number; functions?: number; lines?: number; statements?: number };
};

const coverage = (config.test as { coverage?: CoverageConfig } | undefined)?.coverage;

describe('coverage quality gate configuration', () => {
  test('requires global 85 percent coverage and reviewable reports', () => {
    expect(coverage).toMatchObject({
      clean: true,
      include: ['src/**/*.{ts,tsx}'],
      reporter: ['text', 'text-summary', 'html', 'json-summary', 'lcov'],
      reportsDirectory: 'coverage',
      reportOnFailure: true,
      thresholds: { branches: 85, functions: 85, lines: 85, statements: 85 },
    });
  });
});
```

- [ ] **Step 2: Run the new Frontend test and verify the expected failure**

Run `npm.cmd --prefix frontend exec -- vitest run test/coverageConfig.test.ts`.

Expected: FAIL because `vite.config.ts` does not yet define `test.coverage`.

- [ ] **Step 3: Write the failing PowerShell runner contract**

Create `scripts/coverage-gate.tests.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/check.ps1')

function Assert-Condition {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

$oracleScript = Join-Path $repoRoot 'backend/scripts/test-oracle.ps1'
$frontend = @(Get-CiTaskDefinitions -CiTask FrontendCoverage -RepoRoot $repoRoot `
        -NpmCommand 'npm.cmd' -MavenCommand 'backend/mvnw.cmd' -OracleScript $oracleScript)
$backend = @(Get-CiTaskDefinitions -CiTask BackendCoverage -RepoRoot $repoRoot `
        -NpmCommand 'npm.cmd' -MavenCommand 'backend/mvnw.cmd' -OracleScript $oracleScript)

$frontendArguments = @($frontend.Arguments)
$backendArguments = @($backend.Arguments)
$frontendNames = @($frontend | ForEach-Object Name)
$backendNames = @($backend | ForEach-Object Name)

Assert-Condition ($frontendArguments -contains 'coverage') 'Frontend coverage must invoke npm coverage.'
Assert-Condition ($frontendNames -contains 'frontend-coverage-report') 'Frontend report check is missing.'
Assert-Condition ($backendArguments -contains '-Pcoverage') 'Backend coverage profile is missing.'
Assert-Condition ($backendArguments -contains 'verify') 'Backend coverage must run Maven verify.'
Assert-Condition ($backendNames -contains 'backend-coverage-report') 'Backend report check is missing.'

Write-Output 'Coverage gate contract tests passed.'
```

- [ ] **Step 4: Run the runner contract and verify the expected failure**

Run `pwsh -NoProfile -File scripts/coverage-gate.tests.ps1`.

Expected: FAIL because the current Backend coverage definition uses `test` and no report-presence checks exist.

### Task 2: Configure Vitest thresholds and report outputs

**Files:**

- Modify: `frontend/vite.config.ts:18-26`

**Interfaces:**

- Consumes: Vitest 4.1.9 and the installed `@vitest/coverage-v8` provider.
- Produces: `npm.cmd --prefix frontend run coverage` that fails below 85% for all four metrics and writes text, HTML, JSON summary, and LCOV reports.

- [ ] **Step 1: Add the minimal Vitest coverage configuration**

Extend the existing `test` object in `frontend/vite.config.ts` with:

```ts
    coverage: {
      provider: 'v8',
      clean: true,
      include: ['src/**/*.{ts,tsx}'],
      reporter: ['text', 'text-summary', 'html', 'json-summary', 'lcov'],
      reportsDirectory: 'coverage',
      reportOnFailure: true,
      thresholds: {
        branches: 85,
        functions: 85,
        lines: 85,
        statements: 85,
      },
    },
```

Keep `test.exclude` unchanged so E2E, generated, and coverage files remain outside unit-test discovery.

- [ ] **Step 2: Verify the configuration contract**

Run `npm.cmd --prefix frontend exec -- vitest run test/coverageConfig.test.ts`.

Expected: PASS.

- [ ] **Step 3: Capture the first threshold report**

Run `pwsh -NoProfile -File scripts/check.ps1 -CiTask FrontendCoverage`.

Expected: the command fails because the existing global Branches value is below 85%, while `frontend/coverage/index.html`, `frontend/coverage/coverage-summary.json`, and `frontend/coverage/lcov.info` are generated.

### Task 3: Add Backend JaCoCo checks and coverage report-presence checks

**Files:**

- Modify: `backend/pom.xml:18-25,137-160`
- Modify: `backend/scripts/test-oracle.ps1:22-27`
- Modify: `scripts/check.ps1:19-23,142-160`

**Interfaces:**

- Consumes: the existing `BackendCoverage` CI task and Oracle safety wrapper.
- Produces: Maven `verify` execution with JaCoCo report plus BUNDLE threshold check; report-presence checks that run after a failed coverage command whenever artifacts exist.

- [ ] **Step 1: Add the JaCoCo version property and BUNDLE checks**

Add `<jacoco-maven-plugin.version>0.8.12</jacoco-maven-plugin.version>` beside the existing plugin version properties, use it for the JaCoCo plugin version, and add this execution inside the coverage profile after the report execution:

```xml
<execution>
    <id>check</id>
    <phase>verify</phase>
    <goals><goal>check</goal></goals>
    <configuration>
        <rules>
            <rule>
                <element>BUNDLE</element>
                <limits>
                    <limit><counter>INSTRUCTION</counter><value>COVEREDRATIO</value><minimum>0.85</minimum></limit>
                    <limit><counter>BRANCH</counter><value>COVEREDRATIO</value><minimum>0.85</minimum></limit>
                    <limit><counter>METHOD</counter><value>COVEREDRATIO</value><minimum>0.85</minimum></limit>
                    <limit><counter>LINE</counter><value>COVEREDRATIO</value><minimum>0.85</minimum></limit>
                </limits>
            </rule>
        </rules>
    </configuration>
</execution>
```

- [ ] **Step 2: Make the Oracle wrapper include `*IT` in `verify` coverage runs**

Change `$hasTestGoal` in `backend/scripts/test-oracle.ps1` to:

```powershell
$hasTestGoal = @($MavenArgs | Where-Object { $_ -in @('test', 'verify') }).Count -gt 0
```

Keep the existing `-Dtest=**/*Test,**/*IT` selector insertion and credential-handling logic unchanged.

- [ ] **Step 3: Add a report-presence helper to `scripts/check.ps1`**

Add this function after `New-CheckDefinition`:

```powershell
function New-CoverageReportCheckDefinition {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string[]]$Paths)

    New-CheckDefinition -Name $Name -Action {
        $missing = @($Paths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
        if ($missing.Count -gt 0) { throw "Coverage reports are missing: $($missing -join ', ')" }
        Write-Host 'Coverage reports:'
        $Paths | ForEach-Object { Write-Host " - $_" }
    }.GetNewClosure()
}
```

- [ ] **Step 4: Replace the Frontend/Backend CI task definitions**

Use these exact cases in `Get-CiTaskDefinitions`:

```powershell
        'FrontendCoverage' {
            @(
                New-CheckDefinition -Name 'frontend-coverage' -Command $NpmCommand -Arguments @('--prefix', 'frontend', 'run', 'coverage')
                New-CoverageReportCheckDefinition -Name 'frontend-coverage-report' -Paths @(
                    (Join-Path $RepoRoot 'frontend/coverage/index.html')
                    (Join-Path $RepoRoot 'frontend/coverage/coverage-summary.json')
                    (Join-Path $RepoRoot 'frontend/coverage/lcov.info')
                )
            )
        }
        'BackendCoverage' {
            $arguments = @('-NoProfile', '-File', $OracleScript)
            if (-not [string]::IsNullOrWhiteSpace($OracleConfigPath)) { $arguments += @('-ConfigPath', $OracleConfigPath) }
            $arguments += @('-Pcoverage', 'verify')
            @(
                New-CheckDefinition -Name 'backend-coverage' -Command 'pwsh' -Arguments $arguments
                New-CoverageReportCheckDefinition -Name 'backend-coverage-report' -Paths @(
                    (Join-Path $RepoRoot 'backend/target/site/jacoco/index.html')
                    (Join-Path $RepoRoot 'backend/target/site/jacoco/jacoco.xml')
                    (Join-Path $RepoRoot 'backend/target/site/jacoco/jacoco.csv')
                )
            )
        }
```

`Invoke-QualityChecks` already continues after a failed definition, so report confirmation runs after threshold failure.

- [ ] **Step 5: Run contract and syntax checks**

Run:

```powershell
pwsh -NoProfile -File scripts/coverage-gate.tests.ps1
pwsh -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('scripts/check.ps1',[ref]`$null,[ref]`$null); [void][System.Management.Automation.Language.Parser]::ParseFile('backend/scripts/test-oracle.ps1',[ref]`$null,[ref]`$null)"
```

Expected: both exit 0 and the contract output is `Coverage gate contract tests passed.`

### Task 4: Add Frontend cases for uncovered branches and rerun coverage

**Files:**

- Modify: `frontend/test/dailyReportSearch.test.ts`
- Modify: `frontend/test/apiClient.test.ts`
- Modify: `frontend/test/loginValidation.test.ts`
- Modify: `frontend/test/App.test.tsx`

**Interfaces:**

- Consumes: current production behavior; no production implementation changes.
- Produces: behavior tests for known uncovered branches while preserving existing assertions.

- [ ] **Step 1: Add search helper branch cases**

Append these tests to `frontend/test/dailyReportSearch.test.ts`:

```ts
  test('validateDailyReportSearch rejects a date with an invalid text format', () => {
    expect(validateDailyReportSearch({ targetMonth: '2026-06', dateFrom: '2026-6-01', dateTo: '2026-06-30' }))
      .toBe('対象期間の日付形式が正しくありません。');
  });

  test('buildDailyReportSearchUrl omits optional filters when they are empty', () => {
    expect(buildDailyReportSearchUrl({
      targetMonth: '2026-06', dateFrom: '2026-06-01', dateTo: '2026-06-30',
      employeeId: '', groupId: '', status: '', holidayType: '',
    })).toBe('/api/daily-reports?dateFrom=2026-06-01&dateTo=2026-06-30');
  });

  test('buildDailyReportSearchUrl includes the optional group filter', () => {
    expect(buildDailyReportSearchUrl({
      targetMonth: '2026-06', dateFrom: '2026-06-01', dateTo: '2026-06-30', groupId: 'G001',
    })).toBe('/api/daily-reports?dateFrom=2026-06-01&dateTo=2026-06-30&groupId=G001');
  });
```

- [ ] **Step 2: Add login validation required and length cases**

Append this parameterized test to `frontend/test/loginValidation.test.ts`:

```ts
  it.each([
    ['', 'password123', 'ログインIDは必須です。'],
    ['a'.repeat(81), 'password123', 'ログインIDは80文字以内で入力してください。'],
    ['employee001', '', 'パスワードは必須です。'],
    ['employee001', 'a'.repeat(101), 'パスワードは100文字以内で入力してください。'],
  ])('rejects required or overlong credentials', (loginId, password, expectedMessage) => {
    expect(validateLoginInput(loginId, password)).toBe(expectedMessage);
  });
```

- [ ] **Step 3: Add API fallback, unauthorized, and CSRF cases**

Extend the import in `frontend/test/apiClient.test.ts` with `csrfHeader`, `getJsonOrNullOnUnauthorized`, `jsonCsrfHeaders`, `readCookie`, and `readJson`. Add these tests and clear the cookie in `afterEach`:

```ts
  afterEach(() => {
    document.cookie = 'XSRF-TOKEN=; Max-Age=0; path=/';
    vi.restoreAllMocks();
  });

  it('uses fallback fields when an unauthorized JSON body omits common error fields', async () => {
    const response = new Response(JSON.stringify({}), {
      status: 401,
      headers: { 'Content-Type': 'application/json', 'X-Request-Id': 'request-auth-001' },
    });
    await expect(readError(response)).resolves.toMatchObject({
      code: 'UNAUTHORIZED', message: 'ログインが必要です。', details: [], requestId: 'request-auth-001',
    });
  });

  it('uses fallback fields and logs when an error body is not JSON', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    await expect(readError(new Response('not-json', { status: 503 }))).resolves.toMatchObject({
      code: 'UNKNOWN_ERROR', message: 'リクエストに失敗しました。', details: [],
    });
    expect(consoleError).toHaveBeenCalledWith('event=api.http_failure', expect.objectContaining({
      status: 503, code: 'UNKNOWN_ERROR',
    }));
  });

  it('returns successful JSON and converts a 401 response to null', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 401 }));
    await expect(readJson<{ value: string }>(new Response(JSON.stringify({ value: 'ok' }), { status: 200 })))
      .resolves.toEqual({ value: 'ok' });
    await expect(getJsonOrNullOnUnauthorized('/api/me')).resolves.toBeNull();
  });

  it('reads and applies the encoded CSRF cookie', () => {
    document.cookie = 'XSRF-TOKEN=token%2B1; path=/';
    expect(readCookie('XSRF-TOKEN')).toBe('token+1');
    expect(csrfHeader()).toEqual({ 'X-XSRF-TOKEN': 'token+1' });
    expect(jsonCsrfHeaders()).toEqual({ 'Content-Type': 'application/json', 'X-XSRF-TOKEN': 'token+1' });
  });

  it('logs an unknown path when a network request has an invalid URL', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new TypeError('network unavailable'));
    await expect(getJson('http://[invalid')).rejects.toThrow('network unavailable');
    expect(consoleError).toHaveBeenCalledWith('event=api.network_failure', { path: '/unknown' });
  });
```

Do not delete the existing business-error, server-error, or network-error assertions.

- [ ] **Step 4: Expose and test the App unauthorized callback**

Change the mocked `DailyReportCalendarList` in `frontend/test/App.test.tsx` to:

```tsx
vi.mock('../src/dailyReport/DailyReportCalendarList', () => ({
  DailyReportCalendarList: ({ onUnauthorized }: { onUnauthorized: () => void }) => (
    <div data-testid="daily-report-list">
      日報一覧
      <button data-testid="unauthorized" onClick={onUnauthorized}>セッション切れ</button>
    </div>
  ),
}));
```

Add this test:

```tsx
  it('returns to the login screen when the report list reports unauthorized', async () => {
    vi.mocked(fetchMe).mockResolvedValue(currentUser);
    await renderApp();
    await act(async () => {
      document.querySelector<HTMLButtonElement>('[data-testid="unauthorized"]')?.click();
      await Promise.resolve();
    });
    expect(window.location.pathname).toBe('/login');
    expect(document.querySelector('[role="alert"]')?.textContent).toBe('ログインが必要です。');
    expect(document.querySelector('h1')?.textContent).toBe('ログイン');
  });
```

- [ ] **Step 5: Run focused tests and Frontend coverage**

Run:

```powershell
npm.cmd --prefix frontend exec -- vitest run test/coverageConfig.test.ts test/dailyReportSearch.test.ts test/apiClient.test.ts test/loginValidation.test.ts test/App.test.tsx
pwsh -NoProfile -File scripts/check.ps1 -CiTask FrontendCoverage
```

Expected: focused tests pass and the report shows Branches at or above 85%. If Branches remains below 85%, use `frontend/coverage/index.html` and `frontend/coverage/lcov.info` to add a named test for each remaining business branch, then rerun the same coverage command.

### Task 5: Add Backend branch cases from the JaCoCo report

**Files:**

- Modify: `backend/src/test/java/com/example/dailyreport/report/TimeRulesTest.java`
- Modify: `backend/src/test/java/com/example/dailyreport/report/DailyReportSearchControllerTest.java`
- Modify: `backend/src/test/java/com/example/dailyreport/report/DailyReportCommandControllerTest.java`
- Modify: `backend/src/test/java/com/example/dailyreport/report/DailyReportSubmissionControllerTest.java`
- Modify or create: the existing `backend/src/test/java/com/example/dailyreport/master/*Test.java` owner of a reported master branch

**Interfaces:**

- Consumes: `backend/target/site/jacoco/index.html`, `jacoco.xml`, and `jacoco.csv` from `BackendCoverage`.
- Produces: behavior tests for each reported uncovered branch, with no production-code changes.

- [ ] **Step 1: Run Backend coverage through the common Oracle entry**

Run in an environment with `DAILY_REPORT_DB_ENV=TEST`, expected identity, and protected credentials:

```powershell
pwsh -NoProfile -File scripts/check.ps1 -CiTask BackendCoverage
```

Expected: JaCoCo writes HTML/XML/CSV and reports all four ratios. If the Oracle safety guard cannot start, record the exact missing prerequisite and recheck condition; do not substitute a non-Oracle result for BackendCoverage.

- [ ] **Step 2: Add the fixed high-value TimeRules cases**

Add these methods to `TimeRulesTest`, using its existing helpers:

```java
    @Test
    void validateAndCalculateReturnsEmptyForPaidLeaveWithoutWorkInput() {
        DailyReportRequest request = new DailyReportRequest(
                LocalDate.of(2026, 7, 5), "PAID_LEAVE", null, null, null, List.of());
        TimeRules.CalculatedWorkTime calculated = TimeRules.validateAndCalculate(
                request, employee("BT001", "WT001"), masterData());
        assertThat(calculated.hasWorkTime()).isFalse();
        assertThat(calculated.workMinutes()).isNull();
    }

    @Test
    void validateAndCalculateReturnsEmptyForHolidayWithoutWorkInput() {
        DailyReportRequest request = new DailyReportRequest(
                LocalDate.of(2026, 7, 6), "HOLIDAY", null, null, null, List.of());
        TimeRules.CalculatedWorkTime calculated = TimeRules.validateAndCalculate(
                request, employee("BT001", "WT001"), masterData());
        assertThat(calculated.hasWorkTime()).isFalse();
        assertThat(calculated.workMinutes()).isNull();
    }

    @Test
    void validateAndCalculateRejectsWorkdayWithEndBeforeStart() {
        DailyReportRequest request = workday(LocalDate.of(2026, 7, 7), "18:00", "09:00", 480);
        assertThatThrownBy(() -> TimeRules.validateAndCalculate(request, employee("BT001", "WT001"), masterData()))
                .isInstanceOf(ApiException.class)
                .hasMessageContaining("入力内容が不正です。");
    }

    @Test
    void formatTimeAndDurationHandleMissingValues() {
        assertThat(TimeRules.formatTime(null)).isNull();
        assertThat(TimeRules.formatDuration(null)).isEqualTo("0:00");
    }
```

- [ ] **Step 3: Add missing search-date validation cases**

Add these tests to `DailyReportSearchControllerTest`:

```java
    @Test
    void searchRejectsMissingStartDate() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
        mockMvc.perform(get("/api/daily-reports").param("dateTo", "2026-06-30").session(session))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.details[0].field", equalTo("dateFrom")));
    }

    @Test
    void searchRejectsMissingEndDate() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
        mockMvc.perform(get("/api/daily-reports").param("dateFrom", "2026-06-01").session(session))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.details[0].field", equalTo("dateTo")));
    }
```

- [ ] **Step 4: Add every remaining JaCoCo-reported business branch**

After each Backend coverage run, inspect the report and add the next test to the existing owning class using this mapping:

| JaCoCo area | Required behavior cases when still missed |
| --- | --- |
| `TimeRules.java` | paid leave with times/items, holiday without items with times, invalid HH:mm, out-of-range time, break duration not less than elapsed, work-item total mismatch, regular/overtime/night boundaries |
| `DailyReportAccessPolicy.java` | employee own/other report, manager permitted/denied group, admin report, non-admin denial, manager requested group allowed/denied |
| `DailyReportSearchService.java` | missing dates, inverted range, over-366-day range, manager with no permitted groups, each role and optional-filter combination |
| `MasterDataRepository.java` | missing holiday/break/work-time master, project/category name fallback, normal/cross-midnight `TimePeriod` containment |
| `ApiExceptionHandler.java` | business exception with details, unexpected exception without secret leakage, malformed JSON |

Each test must assert an API or domain behavior and be named after its condition and expected result. Re-run `pwsh -NoProfile -File scripts/check.ps1 -CiTask BackendCoverage` after each meaningful batch and stop only when all four BUNDLE ratios are at least 0.85.

### Task 6: Update quality-gate workflows and project records

**Files:**

- Modify: `scripts/check.ps1`
- Modify: `.github/workflows/quality.yml`
- Modify: `.github/workflows/oracle.yml`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/テスト方針.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/テスト・静的解析チェック表.md`
- Create: `docs/AI活用開発研究/作業記録/カバレッジ閾値強化_2026-07-17.md`

**Interfaces:**

- Consumes: new coverage commands and generated report paths.
- Produces: one documented local/CI procedure and an evidence-based work record distinguishing pass, fail, and unavailable Oracle checks.

- [ ] **Step 1: Add Full-mode execution of the runner contract**

Add this definition to `Get-FullCheckDefinitions` after the existing Backend static-analysis definitions:

```powershell
        New-CheckDefinition -Name 'coverage-gate-contract-test' -Command 'pwsh' -Arguments @(
            '-NoProfile', '-File', (Join-Path $RepoRoot 'scripts/coverage-gate.tests.ps1')
        )
```

- [ ] **Step 2: Preserve explicit CI artifact paths**

In `.github/workflows/quality.yml`, retain `if: always()` and `path: frontend/coverage`. In `.github/workflows/oracle.yml`, retain `if: always()` and `path: backend/target/site/jacoco`. If the exact entries already exist, make no functional workflow change and record that verification result.

- [ ] **Step 3: Update standard documents without duplicating command ownership**

Add these rules:

- `テスト方針.md`: coverage is a required report review; all four Frontend and Backend-mapped metrics are 85% minimum; Branches is blocking; tests are added from uncovered behavior and the same entry is rerun.
- `品質ゲート運用.md`: Frontend/Backend coverage generate artifacts; coverage failure is nonzero; Backend uses Maven `verify`; report-presence checks run after the test command; CI retains artifacts on failure.
- `テスト・静的解析チェック表.md`: report existence, four threshold values, branch review, artifact review, and Oracle unavailable/recheck recording are required checks.

Keep exact commands in `品質ゲート運用.md` and `scripts/check.ps1`; the other documents describe purpose and acceptance criteria only.

- [ ] **Step 4: Create the work record with actual execution evidence**

Create `docs/AI活用開発研究/作業記録/カバレッジ閾値強化_2026-07-17.md` with these sections:

```markdown
# カバレッジ閾値・分岐充足強化 作業記録

## 対象機能

Frontend/Backend coverage品質ゲート、85%閾値、分岐ケース追加・再実施。

## 変更内容

実際に変更したファイルと責務を列挙する。

## 公式ドキュメント確認

- https://vitest.dev/config/coverage
- https://vitest.dev/guide/coverage
- https://www.jacoco.org/jacoco/trunk/doc/check-mojo.html
- https://www.jacoco.org/jacoco/trunk/doc/maven.html

## Coverage実績

### Frontend

- 実行コマンド: `pwsh -NoProfile -File scripts/check.ps1 -CiTask FrontendCoverage`
- 実測値: 実行ログのStatements / Branches / Functions / Lines
- レポート: `frontend/coverage/index.html`、`coverage-summary.json`、`lcov.info`

### Backend

- 実行コマンド: `pwsh -NoProfile -File scripts/check.ps1 -CiTask BackendCoverage`
- 実測値: JaCoCoのINSTRUCTION / BRANCH / METHOD / LINE
- レポート: `backend/target/site/jacoco/index.html`、`jacoco.xml`、`jacoco.csv`
- 未実行時の理由と再確認条件: Oracle未実行時だけ具体的に記載する。

## 追加したテストケース

テスト名、対象分岐、期待結果、再実施結果を列挙する。

## 未達・保留

85%未達または未実行が残る場合だけ、原因、保留理由、再確認条件を記載する。未達がない場合は「なし」と記載する。
```

Replace instructional sentences with concrete results before completion; do not leave instructions in the final record.

### Task 7: Run the complete verification matrix and prepare handoff

**Files:**

- Verify: all modified files from Tasks 1-6
- Verify: generated `frontend/coverage` and `backend/target/site/jacoco` remain ignored

- [ ] **Step 1: Run Frontend tests, static checks, build, and coverage**

Run:

```powershell
npm.cmd --prefix frontend exec -- vitest run test/coverageConfig.test.ts test/dailyReportSearch.test.ts test/apiClient.test.ts test/loginValidation.test.ts test/App.test.tsx
npm.cmd --prefix frontend run lint
npm.cmd --prefix frontend run typecheck
npm.cmd --prefix frontend run build
pwsh -NoProfile -File scripts/check.ps1 -CiTask FrontendCoverage
```

Expected: all commands exit 0; all four Frontend values are at least 85%; HTML, JSON summary, and LCOV exist.

- [ ] **Step 2: Run runner contract, Full, Markdown lint, and diff checks**

Run:

```powershell
pwsh -NoProfile -File scripts/coverage-gate.tests.ps1
pwsh -NoProfile -File scripts/check.ps1 -Mode Full
npm.cmd run lint:markdown -- --no-globs docs/superpowers/specs/2026-07-17-coverage-gate-design.md docs/superpowers/plans/2026-07-17-coverage-gate.md
git diff --check
```

Expected: contract, Full, Markdown lint, and diff checks exit 0. Full includes the runner contract and existing Frontend/Backend static checks.

- [ ] **Step 3: Run Backend coverage or record the protected-environment block**

Run:

```powershell
pwsh -NoProfile -File scripts/check.ps1 -CiTask BackendCoverage
```

Expected: in the protected Oracle environment all four JaCoCo ratios are at least 0.85 and reports exist. If the environment is unavailable, do not claim BackendCoverage passed; record the exact prerequisite and recheck condition in the work record.

- [ ] **Step 4: Verify generated files and existing user changes**

Run:

```powershell
git status --short --ignored -- frontend/coverage backend/target/site/jacoco
git status --short
```

Expected: coverage and target outputs are ignored; only intended source, test, workflow, standard-document, work-record, and plan/design files are changed; pre-existing README and user work-record changes remain present.

- [ ] **Step 5: Commit implementation changes separately from unrelated user changes**

Stage only intended implementation files, run the repository Quick hook, and commit with:

```powershell
git add -- frontend/vite.config.ts frontend/test/coverageConfig.test.ts frontend/test/dailyReportSearch.test.ts frontend/test/apiClient.test.ts frontend/test/loginValidation.test.ts frontend/test/App.test.tsx backend/pom.xml backend/scripts/test-oracle.ps1 scripts/check.ps1 scripts/coverage-gate.tests.ps1 .github/workflows/quality.yml .github/workflows/oracle.yml docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md docs/AI活用開発研究/構想メモ/標準化/テスト方針.md docs/AI活用開発研究/構想メモ/標準化/テスト・静的解析チェック表.md docs/AI活用開発研究/作業記録/カバレッジ閾値強化_2026-07-17.md
git commit -m "test: enforce coverage and branch thresholds"
```

Expected: the commit contains no README, unrelated work-record, generated coverage, Oracle config, or untracked user plan changes.

## Self-review checklist

- [ ] Every design requirement has a task: four thresholds, branch blocking, reports, rerun flow, CI artifact, Oracle record, and user-change preservation.
- [ ] No production code is added solely to improve coverage.
- [ ] Frontend cases assert behavior, not implementation details.
- [ ] Backend cases are added to existing use-case test boundaries and are driven by JaCoCo uncovered branches.
- [ ] No unresolved placeholder or vague implementation step remains in this plan.
- [ ] Commands use the repository's documented common test入口 and fixed tool versions.
