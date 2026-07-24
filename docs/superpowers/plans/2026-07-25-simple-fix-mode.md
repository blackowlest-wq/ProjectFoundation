# Simple Fix Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `scripts/check.ps1 -Mode Simple` と標準運用資料を追加し、ユーザーが選択した簡易修正モードでFocused Unit、表示要件時の1ケース、変更対象層のlint / typecheck / buildだけを実行し、全体回帰は既存CIへ委譲できるようにする。

**Architecture:** 既存の `scripts/check.ps1` を単一入口として維持し、Simple専用のチェック定義を追加する。SimpleはScopeとFocused Unit対象を明示入力として受け取り、任意のシェル文字列は実行しない。PR本文または1枚の変更記録を簡易モードの証跡とし、既存hookとPR必須CIの全6チェックは変更しない。

**Tech Stack:** PowerShell 7、npm scripts、Vitest、Playwright、Maven Wrapper、Markdownlint、既存のProjectFoundation標準資料と`.agents/skills`。

## Global Constraints

- 簡易修正モードはユーザーが選択した場合に変更カテゴリ・規模を理由として自動的に品質重視モードへ変更しない。
- 簡易修正モードでも`Full / Windows`、`Full / Linux`、`Backend / Unit`、`Coverage / Frontend`、`E2E`、`Gitleaks / Directory`を必須CIとして維持する。
- Simple Modeは全テスト、coverage、全E2E、Oracle、追加の秘密情報検査をローカル実行しない。ただし既存pre-commit / pre-push Gitleaksは維持する。
- Focused Unit対象またはN/A理由、表示要件時のPlaywright対象または手動確認理由を必須入力にする。
- BackendやDocsでtypecheckまたはbuildに相当する確認がない場合は、記録へ`N/A`と理由を残す。
- 専用仕様書、実装計画、AC/TC/RT台帳、実装後レビュー文書は、簡易モードで個別変更を行う際には生成しない。今回のSimple Mode自体の実装は品質重視の基盤変更として作業記録と本計画を残す。
- 実装開始前にPowerShell、npm/Playwright、Maven Surefireの公式ドキュメントまたは一次情報を確認し、確認結果を作業記録へ記録する。
- 日本語ドキュメントはUTF-8で編集し、`npm.cmd run lint:markdown`を通す。

---

## 変更ファイルの責務

| ファイル | 責務 |
| --- | --- |
| `scripts/simple-mode.tests.ps1` | Simple Modeの入力検証、Scope、Focused Unit、browser、広範囲チェック非実行のPowerShell契約テスト |
| `scripts/check.ps1` | `Simple` Modeの引数、作業ツリー変更ファイル取得、Simpleチェック定義、Runner分岐 |
| `docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md` | Simple Modeの入口、実行範囲、hook・CIとの責務分担 |
| `docs/AI活用開発研究/構想メモ/標準化/開発フロー.md` | 作業開始時のモード確認とSimple / Qualityの工程分岐 |
| `docs/AI活用開発研究/構想メモ/標準化/AI実装依頼テンプレート.md` | 利用者向けモード選択欄と簡易記録の入力項目 |
| `docs/AI活用開発研究/構想メモ/標準化/実装前チェック表.md` | Simple Modeで省略する資料と、維持する確認項目 |
| `docs/AI活用開発研究/構想メモ/標準化/実装後レビュー表.md` | Simple Modeの1回コード差分レビューとCI委譲の確認 |
| `docs/AI活用開発研究/構想メモ/標準化/skills/projectfoundation-preflight-ja/SKILL.md` | 実装前SkillのSimple / Quality分岐の正本 |
| `docs/AI活用開発研究/構想メモ/標準化/skills/projectfoundation-review-ja/SKILL.md` | 実装後SkillのSimple / Quality分岐の正本 |
| `.agents/skills/projectfoundation-preflight-ja/SKILL.md` | Codexが自動検出するpreflight Skillのコピー先 |
| `.agents/skills/projectfoundation-review-ja/SKILL.md` | Codexが自動検出するreview Skillのコピー先 |
| `docs/AI活用開発研究/作業記録/品質ハーネス_簡易修正モード_作業記録.md` | 実装のWhat、採用判断、テスト結果、標準化判定、未実行条件 |

## Task 1: Simple Modeの契約テストを先に作る

**Files:**

- Create: `scripts/simple-mode.tests.ps1`
- Test: `scripts/simple-mode.tests.ps1`

**Interfaces:**

- Consumes: `Get-SimpleCheckDefinitions`、`Invoke-QualityRunner`、既存の`New-CheckDefinition`
- Produces: Simple Modeの定義名、引数、入力エラー、広範囲チェック非実行を固定する契約

- [ ] **Step 1: 契約テストを作成する**

`scripts/coverage-gate.tests.ps1`と同じdot-source方式で`check.ps1`を読み込み、次の契約を実装する。

```powershell
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/check.ps1')

function Assert-Condition {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Message)
    try {
        & $Action
    }
    catch {
        return
    }
    throw $Message
}

$frontend = @(Get-SimpleCheckDefinitions -RepoRoot $repoRoot -Scope Frontend `
        -FocusedUnitScope Frontend -FocusedUnitTarget 'test/App.test.tsx' `
        -ChangedFiles @('frontend/src/App.tsx', 'frontend/test/App.test.tsx'))
$frontendNames = @($frontend | ForEach-Object Name)

Assert-Condition ($frontendNames -contains 'simple-focused-unit') `
    'Frontend Simple Mode must include one focused unit definition.'
Assert-Condition ($frontendNames -contains 'simple-frontend-lint') `
    'Frontend Simple Mode must include lint.'
Assert-Condition ($frontendNames -contains 'simple-frontend-typecheck') `
    'Frontend Simple Mode must include typecheck.'
Assert-Condition ($frontendNames -contains 'simple-frontend-build') `
    'Frontend Simple Mode must include build.'
Assert-Condition (($frontendNames | Where-Object { $_ -match 'coverage|oracle|secret|full|e2e' }).Count -eq 0) `
    'Frontend Simple Mode must not add broad local checks.'

$browser = @(Get-SimpleCheckDefinitions -RepoRoot $repoRoot -Scope Frontend `
        -FocusedUnitScope Frontend -FocusedUnitTarget 'test/App.test.tsx' `
        -DisplayRequirement -BrowserCase 'verifies the daily report detail presentation in a browser' `
        -ChangedFiles @('frontend/src/App.tsx', 'frontend/test/App.test.tsx'))
$browserNames = @($browser | ForEach-Object Name)
Assert-Condition ($browserNames -contains 'simple-frontend-browser') `
    'Display requirement must add exactly one focused browser definition.'

$backend = @(Get-SimpleCheckDefinitions -RepoRoot $repoRoot -Scope Backend `
        -FocusedUnitScope Backend -FocusedUnitTarget 'TimeRulesTest' `
        -ChangedFiles @('backend/src/main/java/com/example/TimeRules.java'))
$backendNames = @($backend | ForEach-Object Name)
Assert-Condition ($backendNames -contains 'simple-backend-spotless') `
    'Backend Simple Mode must include Spotless.'
Assert-Condition ($backendNames -contains 'simple-backend-checkstyle') `
    'Backend Simple Mode must include Checkstyle.'
Assert-Condition ($backendNames -contains 'simple-backend-test-compile') `
    'Backend Simple Mode must include test compile.'

$notApplicable = @(Get-SimpleCheckDefinitions -RepoRoot $repoRoot -Scope Docs `
        -FocusedUnitNotApplicableReason 'Markdown-only change has no executable unit logic.' `
        -ChangedFiles @('docs/example.md'))
Assert-Condition ((@($notApplicable | ForEach-Object Name) -contains 'simple-focused-unit-na')) `
    'N/A reason must produce an explicit non-applicable check.'

Assert-Throws {
    Get-SimpleCheckDefinitions -RepoRoot $repoRoot -Scope Frontend `
        -FocusedUnitScope Frontend -ChangedFiles @('frontend/src/App.tsx')
} 'Simple Mode must reject a missing focused unit target and N/A reason.'

Assert-Throws {
    Get-SimpleCheckDefinitions -RepoRoot $repoRoot -Scope Frontend `
        -FocusedUnitScope Frontend -FocusedUnitTarget 'test/App.test.tsx' `
        -DisplayRequirement -ChangedFiles @('frontend/src/App.tsx')
} 'Simple Mode must reject a display requirement without browser case or manual reason.'

$ciProcess = Start-Process pwsh -ArgumentList @(
    '-NoProfile', '-File', (Join-Path $repoRoot 'scripts/check.ps1'),
    '-Mode', 'Simple', '-CiTask', 'BackendUnit'
) -Wait -PassThru -RedirectStandardOutput ([IO.Path]::GetTempFileName())
Assert-Condition ($ciProcess.ExitCode -ne 0) 'Simple Mode must reject CiTask.'

Write-Output 'Simple mode contract tests passed.'
```

- [ ] **Step 2: 失敗を確認する**

Run: `pwsh -NoProfile -File scripts/simple-mode.tests.ps1`

Expected: `Get-SimpleCheckDefinitions` が未定義で失敗する。

- [ ] **Step 3: 契約テストをコミットする**

```powershell
git add scripts/simple-mode.tests.ps1
git commit -m "test: define simple mode contracts"
```

## Task 2: `check.ps1` にSimple Modeの定義と実行入口を実装する

**Files:**

- Modify: `scripts/check.ps1:1-15,107-183,541-641`
- Test: `scripts/simple-mode.tests.ps1`

**Interfaces:**

- Consumes: Task 1のSimple Mode契約、既存の`New-CheckDefinition`、既存npm/Maven入口
- Produces: `Simple`、`Docs` / `Frontend` / `Backend` / `Harness` / `Mixed`、Focused Unit、browser case、N/A理由の実行定義

- [ ] **Step 1: Simple Modeの引数を追加する**

トップレベル`param`と`Invoke-QualityRunner`の`Mode`へ`Simple`を追加し、次の引数を同じ形で追加する。

```powershell
[ValidateSet('Docs', 'Frontend', 'Backend', 'Harness', 'Mixed')]
[string]$Scope,
[ValidateSet('Frontend', 'Backend', 'Harness')]
[string]$FocusedUnitScope,
[string]$FocusedUnitTarget,
[string]$FocusedUnitNotApplicableReason,
[switch]$DisplayRequirement,
[string]$BrowserCase,
[string]$BrowserManualReason
```

`Invoke-QualityRunner`からSimpleへ渡し、既存Modeの引数へ影響させない。

- [ ] **Step 2: 作業ツリーの変更ファイル取得を追加する**

`Get-WorkingTreeChangedFiles`を追加し、次の2つのGit結果を正規化して重複排除する。

```powershell
$tracked = @(git -c core.quotePath=false -C $RepoRoot diff --name-only HEAD)
$untracked = @(git -c core.quotePath=false -C $RepoRoot ls-files --others --exclude-standard)
@($tracked + $untracked | ForEach-Object { $_.Replace('\', '/') } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
```

Git取得が非0終了の場合は、変更範囲を推測せず例外にする。

- [ ] **Step 3: Focused Unit定義を追加する**

`New-SimpleFocusedUnitCheckDefinition`を追加する。

- Frontend: `npm.cmd --prefix frontend test -- <FocusedUnitTarget>`
- Backend: Maven Wrapperへ`-Dtest=<FocusedUnitTarget> test`
- Harness: `pwsh -NoProfile -File <repoRoot>/<FocusedUnitTarget>`。対象は`repoRoot/scripts`配下の`.tests.ps1`だけに限定する。
- N/A: `simple-focused-unit-na`というAction定義で理由を表示し、成功扱いにする。
- TargetとN/A理由が両方ない、または両方ある場合は例外にする。
- Frontend / Backend / Harness以外のFocused Unit Scopeは拒否する。

任意のシェル文字列を`Invoke-Expression`や`cmd /c`へ渡さず、既存コマンドと配列引数だけで実行する。

- [ ] **Step 4: Scope別の静的チェック定義を追加する**

`Get-SimpleCheckDefinitions`を追加し、次の順序で定義を返す。

1. `simple-focused-unit`または`simple-focused-unit-na`
2. Frontendの場合は`simple-frontend-lint`、`simple-frontend-typecheck`、`simple-frontend-build`
3. Backendの場合は`simple-backend-spotless`、`simple-backend-checkstyle`、`simple-backend-test-compile`
4. Harnessの場合はFocused Unit定義で対象契約テストを実行し、変更Markdownがあれば`simple-harness-markdown-lint`
5. Docsの場合は変更されたMarkdownだけへ`npm.cmd run lint:markdown -- --no-globs <files>`を渡す
6. `-DisplayRequirement`が指定された場合はbuild成功後にbrowser定義を追加する

`Scope Mixed`はFrontendとBackendの静的チェックを追加し、`FocusedUnitScope`でFocused Unitの層を明示させる。MixedでDisplayRequirementを指定した場合はFrontend buildとbrowser定義を追加する。

BackendとDocsで存在しないtypecheck/buildの欄は、チェック定義を捏造せず、実行結果の記録でN/A理由を残す。

- [ ] **Step 5: browser定義と手動フォールバックを追加する**

BrowserCaseが指定された場合、Frontend build定義の後に次の配列引数でPlaywrightを1ケースだけ実行する。

```powershell
@('--prefix', 'frontend', 'exec', '--', 'playwright', 'test', '--grep', $BrowserCase)
```

BrowserManualReasonが指定された場合は`simple-browser-manual` Actionで理由を表示し、Playwrightを起動しない。DisplayRequirementに対してどちらもない場合は例外にする。

- [ ] **Step 6: Runner分岐とCiTask拒否を追加する**

`Invoke-QualityRunner`で`$Mode -eq 'Simple'`を`$CiTask`分岐より前に処理し、`$CiTask -ne 'None'`なら次のエラーを返す。

```text
Simple Mode cannot be combined with -CiTask.
```

Simple Modeでは`Get-FullCheckDefinitions`、`Get-OracleCheckDefinitions`、`Get-CiTaskDefinitions`、Gitleaks定義を呼び出さない。作業ツリー変更ファイルを取得し、`Get-SimpleCheckDefinitions`を`Invoke-QualityChecks`へ渡す。

- [ ] **Step 7: 契約テストを通す**

Run: `pwsh -NoProfile -File scripts/simple-mode.tests.ps1`

Expected: `Simple mode contract tests passed.`

- [ ] **Step 8: 実行定義の変更をコミットする**

```powershell
git add scripts/check.ps1 scripts/simple-mode.tests.ps1
git commit -m "feat: add simple quality check mode"
```

## Task 3: 標準資料とSkillへSimple / Quality分岐を反映する

**Files:**

- Modify: `docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/開発フロー.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/AI実装依頼テンプレート.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/実装前チェック表.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/実装後レビュー表.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/skills/projectfoundation-preflight-ja/SKILL.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/skills/projectfoundation-review-ja/SKILL.md`
- Modify: `.agents/skills/projectfoundation-preflight-ja/SKILL.md`
- Modify: `.agents/skills/projectfoundation-review-ja/SKILL.md`
- Create: `docs/AI活用開発研究/作業記録/品質ハーネス_簡易修正モード_作業記録.md`
- Test: `scripts/simple-mode.tests.ps1`

**Interfaces:**

- Consumes: Task 2の`Simple`入口と設計書の1枚記録様式
- Produces: AIが作業開始時にモードを確認し、Simpleでは簡易記録と1回コードレビューへ分岐する標準運用

- [ ] **Step 1: 品質ゲート運用へSimpleを追加する**

`Local Mode`表へ次を追加する。

```markdown
| `Simple` | Scope別のFocused Unit、対象層lint / typecheck / build、表示要件時のPlaywright 1ケース | なし。既存hookとCIは別途実行 |
```

あわせて、SimpleはFull / coverage / 全E2E / Oracle / 追加secret scanをローカル実行せず、既存pre-commit / pre-push GitleaksとPR必須6チェックを維持することを追記する。

- [ ] **Step 2: 開発フローへモード選択を追加する**

Intakeの直後に次の分岐を追加する。

```text
作業開始時にSimple / Qualityをユーザーへ確認する。
Simple: PR本文または1枚の変更記録へAC 3～5項目、確認結果、1回コードレビュー、CI委譲を記録する。
Quality: 既存のPlan、Design Check、BDD/Test Design、専門レビュー、Recordを適用する。
```

SimpleでもCI必須チェックはマージ条件として残し、自動昇格は行わないことを明記する。

- [ ] **Step 3: AI実装依頼テンプレートへ選択欄と簡易記録を追加する**

利用者向け依頼文へ次を追加する。

```text
開発モード:
{簡易修正モード / 品質重視モード}

簡易修正モードを選択した場合:
- 受入条件は3～5項目
- Focused UnitまたはN/A理由
- 表示要件時はPlaywright 1ケース、なければ手動確認理由
- 変更対象層のlint / typecheck / build
- コード差分の独立レビュー1回
- 全体回帰は既存CIへ委譲
```

- [ ] **Step 4: 実装前・実装後チェック表へSimple分岐を追加する**

実装前チェック表には、Simple選択、1枚記録、AC 3～5項目、Focused Unit、表示確認、対象層チェック、CI委譲を確認する行を追加する。Simpleでは専用仕様書、実装計画、AC/TC/RT台帳を作成しないことを明記する。

実装後レビュー表には、Simpleではコード差分の独立レビュー1回だけを行い、記録へ結果を残すこと、既存CI必須チェックを確認することを追加する。品質重視モードのP0/P1/P2チェックは変更しない。

- [ ] **Step 5: ProjectFoundation Skillへ分岐を反映する**

編集元の2 Skillへ、実装開始前にモード確認を行う手順を追加する。

- Quality: 既存Hard GateとDo開始条件を適用する。
- Simple: 1枚記録、AC 3～5項目、Focused UnitまたはN/A、表示確認、対象層チェック、1回コードレビュー、CI委譲を適用する。
- Simpleでも未実行を成功扱いせず、CI必須チェックを省略しない。
- Simple変更で専用仕様書、計画、台帳、実装後レビュー文書を生成しない。

編集後に、編集元を次のコピー先へUTF-8のままコピーする。

```powershell
Copy-Item -LiteralPath 'docs/AI活用開発研究/構想メモ/標準化/skills/projectfoundation-preflight-ja/SKILL.md' `
    -Destination '.agents/skills/projectfoundation-preflight-ja/SKILL.md' -Force
Copy-Item -LiteralPath 'docs/AI活用開発研究/構想メモ/標準化/skills/projectfoundation-review-ja/SKILL.md' `
    -Destination '.agents/skills/projectfoundation-review-ja/SKILL.md' -Force
```

- [ ] **Step 6: 実装作業記録を作成する**

`品質ハーネス_簡易修正モード_作業記録.md`へ、次を記録する。

- 実装目的と対象ファイル
- 公式ドキュメント確認結果
- AC-SFM-001～008と実テストID
- Simple Modeをユーザー選択制・自動昇格なしとした理由
- CI必須6チェックと既存hookを維持した理由
- Focused Unit、browser、N/A入力の検証結果
- Markdown lint、Quick、Full、契約テストの実行結果
- 未実行のOracleや環境依存確認と再確認条件
- 指摘ごとの標準化判定

- [ ] **Step 7: ドキュメントを検証してコミットする**

Run: `npm.cmd run lint:markdown`

Expected: `Summary: 0 error(s)`。

```powershell
git add docs/AI活用開発研究/構想メモ/標準化 .agents/skills/projectfoundation-preflight-ja/SKILL.md .agents/skills/projectfoundation-review-ja/SKILL.md docs/AI活用開発研究/作業記録/品質ハーネス_簡易修正モード_作業記録.md
git commit -m "docs: standardize simple fix mode"
```

PowerShellではバックスラッシュを行継続に使わず、上記の1行コマンドを使用する。

## Task 4: 統合検証と最終レビューを行う

**Files:**

- Test: `scripts/simple-mode.tests.ps1`
- Test: `scripts/coverage-gate.tests.ps1`
- Test: `scripts/oracle-preflight.tests.ps1`
- Verify: `scripts/check.ps1`
- Verify: `docs/superpowers/specs/2026-07-25-simple-fix-mode-design.md`
- Verify: `docs/superpowers/plans/2026-07-25-simple-fix-mode.md`

**Interfaces:**

- Consumes: Task 2のSimple runner、Task 3の運用資料とSkillコピー
- Produces: 変更後の契約テスト、Full、Markdown lint、Quickの証跡と保留条件

- [ ] **Step 1: Simple Mode契約テストを再実行する**

Run: `pwsh -NoProfile -File scripts/simple-mode.tests.ps1`

Expected: `Simple mode contract tests passed.`

- [ ] **Step 2: 既存契約テストを再実行する**

Run: `pwsh -NoProfile -File scripts/coverage-gate.tests.ps1`

Expected: `Coverage gate contract tests passed.`

Run: `pwsh -NoProfile -File scripts/oracle-preflight.tests.ps1`

Expected: `Oracle preflight contract tests passed.`

- [ ] **Step 3: 実行定義を確認する**

Run: `pwsh -NoProfile -File scripts/check.ps1 -Mode Simple -Scope Docs -FocusedUnitNotApplicableReason 'Markdown-only contract check.'`

Expected: Docs lintとN/A表示だけが実行され、Full、coverage、E2E、Oracle、追加Gitleaksが実行されない。

Run: `pwsh -NoProfile -File scripts/check.ps1 -Mode Simple -CiTask BackendUnit`

Expected: 非0終了し、`Simple Mode cannot be combined with -CiTask.`を表示する。

- [ ] **Step 4: Fullを実行する**

Run: `pwsh -NoProfile -File scripts/check.ps1 -Mode Full`

Expected: Frontend lint / typecheck / unit / build、Backend compile / Spotless / Checkstyle / SpotBugs、既存契約テストが成功する。

Oracle実環境、BackendCoverage、Oracle E2Eは既存環境条件がなければ未実行とし、作業記録へ理由と再確認条件を残す。

- [ ] **Step 5: Markdown lintと差分を確認する**

Run: `npm.cmd run lint:markdown`

Expected: `Summary: 0 error(s)`。

Run: `git diff --check`

Expected: 出力なし、終了コード0。

- [ ] **Step 6: 最終レビューを記録する**

コード差分、Simple Modeの広範囲チェック非実行、既存hook、CI必須6チェック、記録様式、Skillの編集元・コピー先を1回の統合レビューで確認する。指摘があれば`docs/AI活用開発研究/作業記録/品質ハーネス_簡易修正モード_作業記録.md`へ指摘ID、対応、標準化判定、再確認条件を記録する。

- [ ] **Step 7: 検証結果をコミットする**

```powershell
git add scripts/simple-mode.tests.ps1 scripts/check.ps1 `
    docs/AI活用開発研究/構想メモ/標準化 `
    .agents/skills/projectfoundation-preflight-ja/SKILL.md `
    .agents/skills/projectfoundation-review-ja/SKILL.md `
    docs/AI活用開発研究/作業記録/品質ハーネス_簡易修正モード_作業記録.md
git commit -m "test: verify simple fix mode integration"
```

## 受入条件と実テスト対応

| AC ID | 実装対象 | 実テストID / コマンド | 期待結果 |
| --- | --- | --- | --- |
| AC-SFM-001 | モード選択と1か所記録 | RT-SFM-001 / 文書レビュー | Simple / Qualityを確認し、PR本文または1枚の記録へ残せる |
| AC-SFM-002 | Scope別チェック定義 | RT-SFM-002 / `simple-mode.tests.ps1` | 対象層の定義だけが生成される |
| AC-SFM-003 | Focused Unit入力検証 | RT-SFM-003 / `simple-mode.tests.ps1` | TargetまたはN/A理由がない場合に非0終了する |
| AC-SFM-004 | Browser入力検証 | RT-SFM-004 / `simple-mode.tests.ps1` | DisplayRequirement時にBrowserCaseまたは手動理由を要求する |
| AC-SFM-005 | 広範囲チェック非実行 | RT-SFM-005 / `simple-mode.tests.ps1`、Simple実行 | Full、coverage、全E2E、Oracle、追加secret scanをSimpleから呼ばない |
| AC-SFM-006 | hook / CI維持 | RT-SFM-006 / `coverage-gate.tests.ps1`、`oracle-preflight.tests.ps1` | 既存hookとPR必須6チェックの契約が維持される |
| AC-SFM-007 | 文書省略 | RT-SFM-007 / AI template・Skillレビュー | Simple変更で専用仕様書等を生成しない |
| AC-SFM-008 | 失敗伝播 | RT-SFM-008 / Simple実行 | Focused Unit、lint、typecheck、build、browserの失敗が非0になる |

## Plan Self-Review

- Spec sections 3～8はTask 2とTask 3で実装範囲・記録・CI責務へ対応付けた。
- Spec section 9のAC-SFM-001～008は、受入条件表とTask 1 / Task 2 / Task 4の実テストへ対応付けた。
- Spec section 10の外部ドキュメント確認、引数名、Playwright選択、任意シェル禁止はGlobal ConstraintsとTask 2へ反映した。
- Spec section 11の対象外はTask 2のCiTask拒否、Task 3のCI資料、Task 4の実行確認へ反映した。
- 未完了を示すプレースホルダーや曖昧な実装指示は使用していない。
- `FocusedUnitScope`はMixed時の曖昧さを解消し、Frontend / Backend / Harnessの実行入口と一致させた。
- Browser確認はFrontend build後に実行する順序へ統一した。
- Simpleのカテゴリ無制限選択とCI必須維持が矛盾しないよう、Simpleはリスク判定ではなく作業強度と定義した。
