# Quality Gate Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the quality gate reproducible on CI, enforceable on public `main`, effective for Oracle-independent Backend tests, stable on the protected Oracle runner, and more observable for coverage results.

**Architecture:** Keep `scripts/check.ps1` as the single command-definition and failure-aggregation entry. Add one Oracle-independent Backend unit-test task, keep Oracle workflows post-merge on the isolated runner, and preserve the existing Frontend/JaCoCo threshold engines as the blocking authorities. Add small, explicitly tested scripts only for runner preflight and coverage presentation.

**Tech Stack:** PowerShell 7, GitHub Actions, Node.js 24.18.0/npm 11.16.0, Java 21, Maven Wrapper 3.3.4/Maven 3.9.16, JUnit 5, Vitest/V8, JaCoCo 0.8.12, GitHub CLI.

## Global Constraints

- Keep the repository public and protect only `main`.
- Keep pull-request workflows on GitHub-hosted runners; never execute untrusted PR code on the Oracle self-hosted runner.
- Keep Oracle credentials in protected environment variables or the existing Git-ignored config; never print values.
- Preserve the global 85% thresholds for Frontend Statements/Branches/Functions/Lines and Backend INSTRUCTION/BRANCH/METHOD/LINE.
- Do not add module-specific paths to workflows; use the Maven aggregator and existing test discovery rules.
- Follow UTF-8 for Japanese documents and record changed files, results, blockers, and retry conditions.

---

### Task 1: Normalize Windows/Linux CI execution

**Files:**

- Modify: `frontend/package.json:8`
- Modify: `scripts/bootstrap.ps1:106,154`
- Modify: `scripts/check.ps1:48-59,317-324`
- Modify mode: `backend/mvnw` from `100644` to `100755`
- Test: `scripts/coverage-gate.tests.ps1`

**Interfaces:**

- `scripts/check.ps1` still aggregates failures and returns one nonzero result.
- Windows uses `backend/mvnw.cmd`; Unix uses executable `backend/mvnw`.
- Maven bootstrap always includes `-f backend/pom.xml`.

- [ ] **Step 1: Add failing portability assertions**

Extend `scripts/coverage-gate.tests.ps1` with assertions that `frontend/package.json` contains `pwsh -NoProfile`, `scripts/bootstrap.ps1` contains `-f backend/pom.xml` and `[System.IO.Path]::GetTempPath()`, and `git ls-files -s backend/mvnw` reports mode `100755`.

- [ ] **Step 2: Verify the new assertions fail**

Run `pwsh -NoProfile -File scripts/coverage-gate.tests.ps1`. Expected: failure for the current `powershell` script, missing Maven POM, `$env:TEMP`, and non-executable wrapper.

- [ ] **Step 3: Implement the minimal fixes**

Change the npm test-layout command to `pwsh`, add `-f backend/pom.xml` to Maven bootstrap, use `[System.IO.Path]::GetTempPath()` for Gitleaks, and run:

```powershell
git update-index --chmod=+x backend/mvnw
```

- [ ] **Step 4: Verify Windows behavior**

Run `pwsh -NoProfile -File scripts/coverage-gate.tests.ps1` and `pwsh -NoProfile -File scripts/check.ps1 -Mode Full`; both must pass.

- [ ] **Step 5: Commit**

```powershell
git add frontend/package.json scripts/bootstrap.ps1 scripts/check.ps1 scripts/coverage-gate.tests.ps1 backend/mvnw
git commit -m "fix: normalize quality checks across operating systems"
```

### Task 2: Restore CI and enforce the public repository

**Files:**

- Modify: `.github/workflows/quality.yml:1-12`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md:90-115`
- Modify: `docs/AI活用開発研究/作業記録/カバレッジ閾値強化_2026-07-17.md`

**Interfaces:**

- Initial required check-run names are `Full / Windows`, `Full / Linux`, `Coverage / Frontend`, `E2E`, and `Gitleaks / Directory`; `Backend / Unit` is added to protection after Task 3.
- Oracle jobs remain post-merge and are not required PR checks.

- [ ] **Step 1: Add stale-run cancellation**

Add this workflow-level block while preserving SHA-pinned actions and read-only permissions:

```yaml
concurrency:
  group: quality-${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true
```

- [ ] **Step 2: Push and dispatch the Quality workflow**

Run `git push -u origin codex/coverage-gate` and `gh workflow run Quality --ref codex/coverage-gate`.

- [ ] **Step 3: Verify all non-Oracle jobs**

Run `gh run list --workflow quality.yml --branch codex/coverage-gate --limit 5` and `gh run watch <run-id> --exit-status`. Expected: Windows, Linux, Frontend coverage, E2E, and Gitleaks all pass.

- [ ] **Step 4: Configure branch protection after checks are green**

Read `gh api repos/blackowlest-wq/ProjectFoundation --jq '.visibility'`, then apply `main` protection with pull request required, one Code Owner approval, stale approval dismissal, the five existing check-run names above, administrator enforcement, force-push prohibition, and deletion prohibition.

- [ ] **Step 5: Read back and record protection**

Run `gh api repos/blackowlest-wq/ProjectFoundation/branches/main/protection` and record the returned contexts and flags. Do not claim activation until readback succeeds.

### Task 3: Add the Oracle-independent Backend unit gate

**Files:**

- Modify: `scripts/check.ps1:6,144,159-206,309`
- Modify: `scripts/coverage-gate.tests.ps1`
- Modify: `.github/workflows/quality.yml`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md:32-45,90-115`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/テスト方針.md`

**Interfaces:**

- New command: `pwsh -NoProfile -File scripts/check.ps1 -CiTask BackendUnit`.
- The task never loads Oracle configuration.
- Selected classes: `ApiExceptionHandlerTest`, `BusinessEventLoggingTest`, `MasterDataRepositoryTest`, `RequestIdFilterTest`, `RequestMetadataInterceptorTest`, `TimeRulesTest`.

- [ ] **Step 1: Add a failing contract assertion**

Assert that `Get-CiTaskDefinitions -CiTask BackendUnit` returns one `backend-unit-test` definition whose Maven arguments contain `test` and the exact comma-separated `-Dtest=` selector for the six classes.

- [ ] **Step 2: Verify the contract fails**

Run `pwsh -NoProfile -File scripts/coverage-gate.tests.ps1`; expected failure is that `BackendUnit` is not yet a valid task.

- [ ] **Step 3: Implement the task and CI job**

Add `BackendUnit` to the validation sets and definitions. Use Maven `-f backend/pom.xml -s backend/local-maven-settings.xml -B -Dtest=ApiExceptionHandlerTest,BusinessEventLoggingTest,MasterDataRepositoryTest,RequestIdFilterTest,RequestMetadataInterceptorTest,TimeRulesTest test`. Add a GitHub-hosted Ubuntu job with Java setup, Maven bootstrap, and the new task.

- [ ] **Step 4: Verify the task without Oracle**

Run the contract test and `pwsh -NoProfile -File scripts/check.ps1 -CiTask BackendUnit` with no `DAILY_REPORT_DB_*` variables. Both must pass.

- [ ] **Step 5: Add `Backend / Unit` to branch protection**

After the new job has produced a successful check-run, update `required_status_checks.contexts` to include `Backend / Unit` and read the protection back.

- [ ] **Step 6: Commit**

```powershell
git add scripts/check.ps1 scripts/coverage-gate.tests.ps1 .github/workflows/quality.yml docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md docs/AI活用開発研究/構想メモ/標準化/テスト方針.md
git commit -m "ci: gate oracle-independent backend unit tests"
```

### Task 4: Stabilize Oracle initialization

**Files:**

- Create: `scripts/doctor-backend-oracle.ps1`
- Test: `scripts/oracle-preflight.tests.ps1`
- Modify: `.github/workflows/oracle.yml:46-78`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md:76-88,120-127`
- Modify: `docs/AI活用開発研究/作業記録/カバレッジ閾値強化_2026-07-17.md`

**Interfaces:**

- The preflight checks Java 21, Maven Wrapper 3.9.16, required protected environment variable presence, `DAILY_REPORT_DB_ENV=TEST`, and the example config file without printing secrets.
- All three Oracle jobs call the preflight; `oracle-coverage` also sets up Java and Maven dependencies.

- [ ] **Step 1: Write a non-network preflight test**

Create a test that runs the preflight with an incomplete temporary process environment and proves it fails for missing `DAILY_REPORT_DB_PASSWORD` before invoking Maven or contacting Oracle.

- [ ] **Step 2: Verify the test fails before implementation**

Run `pwsh -NoProfile -File scripts/oracle-preflight.tests.ps1`; expected failure is the missing preflight script.

- [ ] **Step 3: Implement the secret-safe preflight**

Use `Get-Command`, wrapper `--version`, and process environment lookups. Print only tool names and missing variable names, never values. Exit 0 only when all checks pass.

- [ ] **Step 4: Wire and validate Oracle jobs**

Add the preflight to integration, coverage, and E2E; add Java setup and Maven bootstrap to coverage; add a 30-minute job timeout; validate YAML through the existing lint path.

- [ ] **Step 5: Commit**

```powershell
git add scripts/doctor-backend-oracle.ps1 scripts/oracle-preflight.tests.ps1 .github/workflows/oracle.yml docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md docs/AI活用開発研究/作業記録/カバレッジ閾値強化_2026-07-17.md
git commit -m "ci: stabilize oracle workflow preflight"
```

### Task 5: Harden and present coverage results

**Files:**

- Modify: `backend/pom.xml:134-193`
- Modify: `scripts/coverage-gate.tests.ps1`
- Create: `scripts/write-coverage-summary.ps1`
- Test: `scripts/coverage-summary.tests.ps1`
- Modify: `.github/workflows/quality.yml:65-89`
- Modify: `.github/workflows/oracle.yml:68-78`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/テスト方針.md`

**Interfaces:**

- JaCoCo data is `backend/target/jacoco.exec`; reports remain under `backend/target/site/jacoco`.
- The summary script accepts Frontend JSON and Backend XML paths and writes a concise table to `$env:GITHUB_STEP_SUMMARY` or standard output.
- Existing threshold engines remain the only blocking percentage calculators.

- [ ] **Step 1: Add failing coverage-contract assertions**

Assert that `backend/pom.xml` uses `${project.build.directory}/jacoco.exec`, retains all four 0.85 counters, and that the task definition retains HTML, XML, and CSV report paths.

- [ ] **Step 2: Verify the contract fails**

Run `pwsh -NoProfile -File scripts/coverage-gate.tests.ps1`; expected failure is the current `${env.TEMP}` JaCoCo path and incomplete contract coverage.

- [ ] **Step 3: Change JaCoCo output isolation**

Set both JaCoCo `destFile` and `dataFile` to `${project.build.directory}/jacoco.exec` without changing the blocking thresholds.

- [ ] **Step 4: Write the summary test before the script**

Use temporary Frontend JSON, Backend JaCoCo XML, and `GITHUB_STEP_SUMMARY` paths. Assert that all four metric names and percentages are written and missing input fails.

- [ ] **Step 5: Implement and wire the summary**

Run the summary after each coverage command with `if: always()`, while keeping the existing report-presence check as the failure authority.

- [ ] **Step 6: Verify coverage**

Run the coverage contract test, summary test, and `npm.cmd --prefix frontend run coverage`. Confirm all four Frontend metrics remain at least 85% and all reports exist.

- [ ] **Step 7: Commit**

```powershell
git add backend/pom.xml scripts/coverage-gate.tests.ps1 scripts/write-coverage-summary.ps1 scripts/coverage-summary.tests.ps1 .github/workflows/quality.yml .github/workflows/oracle.yml docs/AI活用開発研究/構想メモ/標準化/テスト方針.md
git commit -m "ci: harden and summarize coverage reports"
```

### Task 6: Verify and update records

**Files:**

- Modify: `docs/AI活用開発研究/作業記録/カバレッジ閾値強化_2026-07-17.md`
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md`
- Review: `docs/AI活用開発研究/構想メモ/標準化/実装後レビュー表.md`
- Review: `docs/AI活用開発研究/構想メモ/標準化/テスト・静的解析チェック表.md`

- [ ] **Step 1: Run local checks in order**

Run `doctor.ps1`, Quick, Full, BackendUnit, Frontend coverage, and E2E. Run Oracle modes only when the protected environment is available; record the exact blocker and retry condition otherwise.

- [ ] **Step 2: Re-run GitHub-hosted Quality**

Confirm the required non-Oracle checks pass on the current commit and capture the run URL.

- [ ] **Step 3: Verify branch protection readback**

Confirm required contexts, review requirement, stale approval dismissal, administrator enforcement, force-push prohibition, and deletion prohibition.

- [ ] **Step 4: Run Oracle manually**

Confirm preflight, integration, Backend coverage, and real E2E. If the runner is unavailable, leave the result unclaimed and record the recheck condition.

- [ ] **Step 5: Review and record**

Use the implementation-after-review and test/static-analysis checklists. Classify findings, record fixed file paths, and record every held item with its reason and recheck condition.

- [ ] **Step 6: Final evidence**

Run `git diff --check` and `git status --short`; report changed commits, local results, CI URLs, branch-protection readback, and Oracle-only unexecuted checks.
