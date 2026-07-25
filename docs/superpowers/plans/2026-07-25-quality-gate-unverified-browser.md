# 品質ゲートのブラウザ未実行を成功扱いしない Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with checkpoints.

**Goal:** BrowserCaseが未実行の場合にSimple品質ハーネスが成功扱いにならず、Review Skillと標準資料も同じ判定を行う状態にする。

**Architecture:** `scripts/check.ps1`のBrowserManualReasonフォールバックを明示的な失敗定義へ変更し、`scripts/simple-mode.tests.ps1`で終了コードと失敗名を契約化する。Review Skillは実行済み・未実行・CI委譲の報告ルールを補強し、編集元Skillから`.agents/skills`へ同期する。

**Tech Stack:** PowerShell 7、Playwright 1.58.0、Markdownlint、Lefthook、ProjectFoundation Review Skill。

## Global Constraints

- BrowserCaseが起動できない、または未実行の場合は、表示要件の品質ゲートを合格と報告しない。
- `BrowserManualReason`は未実行理由の記録であり、実ブラウザ確認の証拠ではない。
- Fullローカル成功はE2E成功を意味しない。E2Eを別途実行していない場合は未実行またはCI委譲と記録する。
- FullにPlaywright全件を追加せず、E2Eは既存の専用CI jobと`-CiTask E2E`の責務を維持する。
- Oracle、coverage、PR必須CI 6チェックの実行範囲は変更しない。
- 既存の未コミット変更を破棄せず、今回の変更対象以外を編集しない。

---

### Task 1: Manual fallbackの失敗契約を追加する

**Files:**

- Modify: `scripts/simple-mode.tests.ps1:37-47` — BrowserCase定義に関する契約の直後

**Interfaces:**

- Consumes: `Get-SimpleCheckDefinitions`, `Invoke-QualityChecks`
- Produces: `BrowserManualReason`を使うSimple定義が`simple-browser-manual`を失敗として報告する契約

- [ ] **Step 1: Write the failing test**

`$browser`定義から`simple-browser-manual`を取得し、`Invoke-QualityChecks`へ単独で渡して、失敗一覧に含まれることを確認する。既存のBrowserCase作業ディレクトリ契約は維持する。

```powershell
$manual = @(Get-SimpleCheckDefinitions -RepoRoot $repoRoot -Scope Frontend `
        -FocusedUnitScope Frontend -FocusedUnitTarget 'test/App.test.tsx' `
        -DisplayRequirement -BrowserManualReason 'BrowserCase was not executed.' `
        -ChangedFiles @('frontend/src/App.tsx', 'frontend/test/App.test.tsx'))
$manualBrowser = $manual | Where-Object Name -eq 'simple-browser-manual'
$manualFailures = [System.Collections.Generic.List[string]]::new()
Invoke-QualityChecks -Definitions @($manualBrowser) -Failures $manualFailures
Assert-Condition ($manualFailures -contains 'simple-browser-manual') `
    'BrowserManualReason must not produce a passing quality check.'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -File scripts/simple-mode.tests.ps1`

Expected: FAIL because the current manual action only writes a message and returns exit code 0.

- [ ] **Step 3: Commit**

```powershell
git add scripts/simple-mode.tests.ps1
git commit -m "test: reject unexecuted simple browser checks"
```

### Task 2: Make BrowserManualReason non-passing

**Files:**

- Modify: `scripts/check.ps1:260-262` — `New-SimpleBrowserCheckDefinition` manual fallback action

**Interfaces:**

- Consumes: `BrowserManualReason` text from Simple Mode
- Produces: `simple-browser-manual` failure with a stable `BROWSER_UNVERIFIED` marker and nonzero runner exit

- [ ] **Step 1: Write the minimal implementation**

Replace the manual action body so it throws instead of returning normally:

```powershell
New-CheckDefinition -Name 'simple-browser-manual' -Action {
    throw "BROWSER_UNVERIFIED: $BrowserManualReason"
}.GetNewClosure()
```

- [ ] **Step 2: Run the contract test to verify it passes**

Run: `pwsh -NoProfile -File scripts/simple-mode.tests.ps1`

Expected: PASS with `Simple mode contract tests passed.`

- [ ] **Step 3: Verify the public runner exit code**

Run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/check.ps1 -Mode Simple -Scope Frontend `
  -FocusedUnitScope Frontend -FocusedUnitTarget test/dailyReportDateTimeFormat.test.ts `
  -DisplayRequirement -BrowserManualReason 'BrowserCase was not executed.'
```

Expected: nonzero exit, `FAIL simple-browser-manual`, `BROWSER_UNVERIFIED`, and no `All requested checks passed.` message.

- [ ] **Step 4: Commit**

```powershell
git add scripts/check.ps1
git commit -m "fix: fail simple mode when browser is unverified"
```

### Task 3: Synchronize Review Skill and quality-gate guidance

**Files:**

- Modify: `docs/AI活用開発研究/構想メモ/標準化/skills/projectfoundation-review-ja/SKILL.md` — Simple Mode and completion rules
- Copy: `docs/AI活用開発研究/構想メモ/標準化/skills/projectfoundation-review-ja/SKILL.md` to `.agents/skills/projectfoundation-review-ja/SKILL.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md` — Simple Mode BrowserCase/manual fallback rules
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_作業記録.md` — prevention result
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md` — `FIND-QH-002` follow-up

**Interfaces:**

- Consumes: `scripts/check.ps1` failure marker and `scripts/simple-mode.tests.ps1` contract
- Produces: synchronized process rule that separates PASS, UNVERIFIED, and CI DELEGATED

- [ ] **Step 1: Update the source Skill**

Add the following rule in the Simple Mode and completion sections:

```text
BrowserCaseが起動できない、または未実行の場合は、表示要件の品質ゲートを合格と報告しない。BrowserManualReasonは未実行理由の記録であり、実ブラウザ確認の証拠ではない。Fullローカル成功はE2E成功を意味しないため、E2Eを別途実行していない場合は未実行またはCI委譲と記録する。
```

- [ ] **Step 2: Synchronize the runtime Skill**

Run: `Copy-Item -LiteralPath docs/AI活用開発研究/構想メモ/標準化/skills/projectfoundation-review-ja/SKILL.md -Destination .agents/skills/projectfoundation-review-ja/SKILL.md -Force`

Expected: source and runtime Skill contents are byte-for-byte equal.

- [ ] **Step 3: Update standard records**

Add `FIND-QH-002` as対応済み, cite the `BROWSER_UNVERIFIED` contract test, and record that the earlier manual fallback was not a valid display gate. Keep `FIND-QH-001` as the separate BrowserCase working-directory finding. Update `品質ゲート運用.md` to say the manual fallback returns nonzero and is not a pass.

- [ ] **Step 4: Run documentation checks**

Run:

```powershell
npm.cmd run lint:markdown -- --no-globs `
  docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md `
  docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md `
  docs/AI活用開発研究/作業記録/日報登録編集_作業記録.md
git diff --check
```

Expected: zero Markdown errors and zero whitespace errors.

- [ ] **Step 5: Commit**

```powershell
git add docs/AI活用開発研究/構想メモ/標準化/skills/projectfoundation-review-ja/SKILL.md `
  .agents/skills/projectfoundation-review-ja/SKILL.md `
  docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md `
  docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md `
  docs/AI活用開発研究/作業記録/日報登録編集_作業記録.md
git commit -m "docs: clarify unverified browser gate reporting"
```

### Task 4: Run final prevention and regression checks

**Files:**

- Test: `scripts/simple-mode.tests.ps1`
- Test: `frontend/e2e/approval-rejection.spec.ts`
- Test: `frontend/e2e/daily-report.spec.ts`
- Verify: `scripts/check.ps1`, synchronized Review Skill, quality records

**Interfaces:**

- Consumes: completed Tasks 1–3
- Produces: evidence that unverified BrowserCase fails and executed BrowserCase passes

- [ ] **Step 1: Run the harness contract test**

Run: `pwsh -NoProfile -File scripts/simple-mode.tests.ps1`

Expected: PASS, including the manual fallback non-pass assertion and the frontend working-directory assertion.

- [ ] **Step 2: Run the actual display BrowserCase**

Run from the repository root:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/check.ps1 -Mode Simple -Scope Frontend `
  -FocusedUnitScope Frontend -FocusedUnitTarget test/dailyReportDateTimeFormat.test.ts `
  -DisplayRequirement -BrowserCase 'TC-APR-003'
```

Expected: all Simple checks pass, including one Playwright test executed from `frontend`.

- [ ] **Step 3: Run affected E2E and E2E typecheck**

Run from `frontend`:

```powershell
npm.cmd run typecheck:e2e
npm.cmd exec -- playwright test e2e/approval-rejection.spec.ts e2e/daily-report.spec.ts `
  --grep "TC-APR-003|TC-APR-007|employee can resubmit a rejected report"
```

Expected: E2E typecheck passes and 3 affected tests pass.

- [ ] **Step 4: Run Full local gate**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/check.ps1 -Mode Full`

Expected: all existing Full checks pass; do not interpret this as a replacement for full E2E or CI.

- [ ] **Step 5: Verify the manual fallback is rejected**

Run the Task 2 public runner command and verify its exit code is nonzero and output contains `BROWSER_UNVERIFIED` without `All requested checks passed.`.

- [ ] **Step 6: Commit final verification records**

```powershell
git status --short
git diff --check
```

Expected: only intended files are changed; the final report states local checks, unexecuted CI checks, and residual risk separately.
