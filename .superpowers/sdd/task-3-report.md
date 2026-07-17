# Task 3 Report: Add Backend JaCoCo checks and coverage report-presence checks

## Status

- Completed in the approved isolated worktree on branch `codex/coverage-gate`.

## Implementation details

- `backend/pom.xml`
  - Added `<jacoco-maven-plugin.version>0.8.12</jacoco-maven-plugin.version>` to plugin properties.
  - Switched the coverage-profile JaCoCo plugin version to `${jacoco-maven-plugin.version}`.
  - Added the native JaCoCo `check` execution at `verify` with the required BUNDLE thresholds:
    - `INSTRUCTION` `COVEREDRATIO` `0.85`
    - `BRANCH` `COVEREDRATIO` `0.85`
    - `METHOD` `COVEREDRATIO` `0.85`
    - `LINE` `COVEREDRATIO` `0.85`

- `backend/scripts/test-oracle.ps1`
  - Expanded `$hasTestGoal` so `verify` coverage runs also inject the existing `-Dtest=**/*Test,**/*IT` selector.
  - Kept the Oracle environment loading, credential handling, and DDL safety behavior unchanged.

- `scripts/check.ps1`
  - Added `New-CoverageReportCheckDefinition` exactly for artifact-presence checks.
  - Updated `FrontendCoverage` to run coverage plus follow-up checks for:
    - `frontend/coverage/index.html`
    - `frontend/coverage/coverage-summary.json`
    - `frontend/coverage/lcov.info`
  - Updated `BackendCoverage` to call the Oracle wrapper with `-Pcoverage verify` and follow-up checks for:
    - `backend/target/site/jacoco/index.html`
    - `backend/target/site/jacoco/jacoco.xml`
    - `backend/target/site/jacoco/jacoco.csv`
  - Added a small `New-CheckDefinitionBundle`/expansion path so the tightened Task 1 contract can inspect the primary CI command shape while `Invoke-QualityChecks` still executes both the main coverage command and the follow-up report check in sequence.

## Tests and results

- Contract test (focused TDD contract)
  - Command: `pwsh -NoProfile -File scripts/coverage-gate.tests.ps1`
  - Result: exit `0`
  - Output: `Coverage gate contract tests passed.`

- Syntax checks
  - Command:
    - `Parser::ParseFile('scripts/check.ps1', ...)`
    - `Parser::ParseFile('backend/scripts/test-oracle.ps1', ...)`
  - Result: exit `0`

- Oracle-backed backend coverage task
  - Command: `pwsh -NoProfile -File scripts/check.ps1 -CiTask BackendCoverage`
  - Result: exit `1`
  - Observed behavior:
    - `backend-coverage` failed first.
    - `backend-coverage-report` still ran afterward and reported missing JaCoCo artifacts.
  - Exact blocker:
    - `Oracle test config key is required: DAILY_REPORT_DB_URL`

- Non-Oracle frontend coverage task
  - Command: `pwsh -NoProfile -File scripts/check.ps1 -CiTask FrontendCoverage`
  - Result: exit `1`
  - Observed behavior:
    - `frontend-coverage` failed on existing threshold enforcement.
    - `frontend-coverage-report` still ran afterward and passed, confirming artifact-presence continuation.
  - Threshold output:
    - lines `51.75% < 85%`
    - functions `39.09% < 85%`
    - statements `50% < 85%`
    - branches `47.95% < 85%`

## Oracle availability

- Full backend coverage verification is blocked in this environment because `DAILY_REPORT_DB_URL` is not configured.
- The exact runtime error captured from the shared Oracle entrypoint path was:
  - `Oracle test config key is required: DAILY_REPORT_DB_URL`

## Files changed

- `backend/pom.xml`
- `backend/scripts/test-oracle.ps1`
- `scripts/check.ps1`

## Self-review

- Scope stayed inside the task-owned files plus this required report.
- The common backend entrypoint remains `backend/scripts/test-oracle.ps1`.
- No custom threshold calculator or retry logic was introduced; the native JaCoCo `check` goal and existing `Invoke-QualityChecks` continuation behavior remain the enforcement mechanism.
- Oracle safety and credential-loading logic were not changed.
- The added bundle/expansion logic is localized to `scripts/check.ps1` and exists only to preserve the Task 1 contract’s inspection shape while still executing both checks in CI.

## Concerns

- Backend JaCoCo generation could not be fully exercised end-to-end here because Oracle configuration is unavailable.
- Frontend coverage thresholds are currently below `85%`; this task confirms continuation/report checks, but it does not remediate the existing coverage shortfall.

## Fix wave: remove bundle helper and restore direct CI definition arrays

### Summary

- Removed the custom `New-CheckDefinitionBundle` helper from `scripts/check.ps1`.
- Removed the `Definitions` expansion branch from `Invoke-QualityChecks`.
- Restored `FrontendCoverage` and `BackendCoverage` so each switch arm directly returns the two definitions required by the Task 3 brief.
- Updated `scripts/coverage-gate.tests.ps1` so the contract checks the restored direct-array shape by inspecting the first returned command definition while still asserting the report-presence definition names.

### Commands and outputs

- Focused red shape check before the fix
  - Command: direct `Get-CiTaskDefinitions` inspection for `FrontendCoverage` and `BackendCoverage`
  - Output:
    - `FrontendCoverage should return 2 direct definitions, got 1.`
    - `BackendCoverage should return 2 direct definitions, got 1.`
    - `FrontendCoverage should not return bundle objects.`
    - `BackendCoverage should not return bundle objects.`

- Contract test after the fix
  - Command: `pwsh -NoProfile -File scripts/coverage-gate.tests.ps1`
  - Result: exit `0`
  - Output: `Coverage gate contract tests passed.`

- PowerShell syntax checks after the fix
  - Command:
    - `Parser::ParseFile('scripts/check.ps1', ...)`
    - `Parser::ParseFile('backend/scripts/test-oracle.ps1', ...)`
  - Result: exit `0`
  - Output: `PowerShell syntax checks passed.`

- Focused direct-definition shape check after the fix
  - Command: direct `Get-CiTaskDefinitions` inspection for `FrontendCoverage` and `BackendCoverage`
  - Result: exit `0`
  - Output:
    - `SHAPE FrontendCoverage count=2 names=frontend-coverage, frontend-coverage-report`
    - `SHAPE BackendCoverage count=2 names=backend-coverage, backend-coverage-report`

- Non-Oracle frontend continuation check after the fix
  - Command: `pwsh -NoProfile -File scripts/check.ps1 -CiTask FrontendCoverage`
  - Result: exit `1`
  - Observed behavior:
    - `frontend-coverage` failed on the existing `85%` coverage thresholds.
    - `frontend-coverage-report` still ran afterward and passed.
  - Output excerpt:
    - `PASS frontend-coverage-report`
    - `ERROR: Coverage for lines (51.75%) does not meet global threshold (85%)`
    - `ERROR: Coverage for functions (39.09%) does not meet global threshold (85%)`
    - `ERROR: Coverage for statements (50%) does not meet global threshold (85%)`
    - `ERROR: Coverage for branches (47.95%) does not meet global threshold (85%)`
