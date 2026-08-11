# 品質確認表示データのテンプレート化 Implementation Plan

> **Codexでの実行:** 実装前に`/plan`でこの既存計画と現在のリポジトリ状態を照合する。長時間・多段階の実行では、合意した結果、制約、検証を含む`/goal`を開始する。チェックボックスは進捗記録に使い、未確認の項目を現行要件として扱わない。

**Goal:** 品質確認表示データの共通JSON形式と汎用契約テストを追加し、F-001をテンプレート形式へ移行して他機能へ展開できる状態にする。

**Architecture:** 入力JSONは`schemaVersion`と固定トップレベル項目を持つ。生成スクリプトは入力の構造・参照・実行・ゲートを検証し、`automatedFindings`だけを生成物へ追加する。機能固有の回帰確認は機能フォルダのテストに残し、共通契約は`quality-report-contract.tests.ps1`へ分離する。

**Tech Stack:** PowerShell 7、JSON、自己完結HTML、既存の`check-quality-reports.ps1`、既存のDocs Simpleゲート

## Global Constraints

- 対象は`docs/AI活用開発研究/コード品質確認画面`と品質確認用の`scripts`に限定する。
- 既存の未コミット変更を破棄、リセット、上書きしない。
- F-001の既存レビュー内容、実行結果、証跡、機械検証の意味を変更しない。
- `automatedFindings`は入力JSONへ保存せず、生成時に決定的に作成する。
- `reviewStatus`、`caseDesignStatus`、`findings.status=要補足`を自動評価へ使用しない。
- 新しい外部ライブラリを追加しない。

---

### Task 1: テンプレートとスキーマ契約のREDテストを追加する

**Files:**
- Create: `scripts/quality-report-template.tests.ps1`
- Modify: `scripts/quality-report.tests.ps1`
- Test data: `docs/AI活用開発研究/コード品質確認画面/品質確認表示データ.template.json`

**Interfaces:**
- Consumes: テンプレートJSON、既存F-001生成スクリプト
- Produces: `schemaVersion`、トップレベル項目、生成物へ`automatedFindings`を持ち込まない契約

- [ ] **Step 1: テンプレート契約テストを書く**

次の契約をPowerShellで追加する。

```powershell
$requiredRootProperties = @(
    'schemaVersion', 'feature', 'acceptanceCriteria', 'qualityGates',
    'rootCauses', 'testCases', 'viewpoints', 'testImplementations',
    'evidence', 'findings', 'coverage', 'sources'
)
$template = Get-Content -Raw -Encoding UTF8 $templatePath | ConvertFrom-Json
foreach ($property in $requiredRootProperties) {
    if ($null -eq $template.PSObject.Properties[$property]) {
        throw "Template property is missing: $property"
    }
}
if ([string]$template.schemaVersion -ne '1.0') {
    throw 'Template schemaVersion must be 1.0.'
}
if ($null -ne $template.PSObject.Properties['automatedFindings']) {
    throw 'Template must not contain generated automatedFindings.'
}
```

- [ ] **Step 2: F-001データのスキーマ契約テストを追加する**

F-001表示データにも`schemaVersion=1.0`が存在することを確認し、`automatedFindings`が入力JSONに存在しないことを確認する。既存生成スクリプトを`-ValidateOnly`で実行する契約も追加する。

- [ ] **Step 3: テストをREDで実行する**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\quality-report-template.tests.ps1`

Expected: テンプレート未作成またはF-001の`schemaVersion`未追加により失敗する。

### Task 2: テンプレートと生成スクリプトのスキーマ検証を実装する

**Files:**
- Create: `docs/AI活用開発研究/コード品質確認画面/品質確認表示データ.template.json`
- Modify: `docs/AI活用開発研究/コード品質確認画面/F-001_ログイン/F-001_ログイン_表示データ.json`
- Modify: `docs/AI活用開発研究/コード品質確認画面/F-001_ログイン/F-001_ログイン_生成.ps1`

**Interfaces:**
- Consumes: `schemaVersion=1.0`のJSON
- Produces: `Test-QualityData`によるスキーマバージョン検証と、既存の構造・参照検証

- [ ] **Step 1: 最小の有効JSONテンプレートを作成する**

`schemaVersion=1.0`、機能メタデータの入力欄、全固定コレクション、Frontend/Backendの`未生成`カバレッジ欄を持つテンプレートを作成する。空のコレクションは許可し、機能作成時に実データを追加する。テンプレートには`automatedFindings`を入れない。

- [ ] **Step 2: F-001へ`schemaVersion`だけを追加する**

既存の受入条件、ケース、証跡、レビュー状態、カバレッジ値は変更せず、JSONルートへ`"schemaVersion": "1.0"`を追加する。

- [ ] **Step 3: PowerShell検証へスキーマバージョン検証を追加する**

`Test-QualityData`の先頭で`schemaVersion`を必須取得し、`1.0`以外を非0終了にする。

```powershell
$schemaVersion = [string](Get-RequiredProperty -Object $Data -Name 'schemaVersion' -Context 'root data')
if ($schemaVersion -ne '1.0') {
    Throw-ValidationError "root data schemaVersion must be 1.0, got '$schemaVersion'."
}
```

- [ ] **Step 4: REDテストをGREENにする**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\quality-report-template.tests.ps1`

Expected: `Template schema contract passed.`

### Task 3: F-001固有判定と汎用契約テストを分離する

**Files:**
- Create: `scripts/quality-report-contract.tests.ps1`
- Modify: `scripts/check-quality-reports.ps1`
- Test: `scripts/quality-report.tests.ps1`

**Interfaces:**
- Consumes: `-FeaturePath`、機能別表示データ、生成スクリプト
- Produces: F-001固有IDを参照しない共通契約テストと、機能別テストを順序付きで実行するバッチ

- [ ] **Step 1: 共通契約テストをREDで定義する**

`quality-report-contract.tests.ps1`は`-FeaturePath`を受け取り、機能フォルダ内の`*_表示データ.json`、`*_生成.ps1`、`*_コード品質確認.html`を解決する。出力先を一時HTMLへして生成し、次を確認する。

```powershell
foreach ($property in $requiredRootProperties) {
    if ($null -eq $data.PSObject.Properties[$property]) {
        throw "Generated data property is missing: $property"
    }
}
foreach ($finding in @($data.automatedFindings)) {
    foreach ($property in @('category', 'id', 'text', 'status')) {
        if ($null -eq $finding.PSObject.Properties[$property]) {
            throw "Automated finding property is missing: $property"
        }
    }
}
if ($data.automatedFindings.category -contains '期待結果・ケース設計不足') { throw 'Semantic category was automated.' }
if ($data.automatedFindings.category -contains '観点判定') { throw 'Viewpoint judgment was automated.' }
if ($data.automatedFindings.category -contains '要補足') { throw '要補足 was automated.' }
```

F-001固有のケースID、受入条件ID、観点IDをこの共通テストへ書かない。

- [ ] **Step 2: REDを確認する**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\quality-report-contract.tests.ps1 -FeaturePath .\docs\AI活用開発研究\コード品質確認画面\F-001_ログイン`

Expected: 共通契約テスト未作成またはバッチ未連携により失敗する。

- [ ] **Step 3: バッチへ共通契約テストを追加する**

各機能について、次の順で実行する。

1. `quality-report-contract.tests.ps1`
2. 機能別`*_表示方針.tests.ps1`
3. 生成スクリプト`-ValidateOnly`
4. `-ValidateOnly`でない場合だけHTMLを最終生成

- [ ] **Step 4: 共通契約テストをGREENにする**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\quality-report.tests.ps1`

Expected: `Quality report batch contract passed.`

### Task 4: 利用手順と検証記録を更新する

**Files:**
- Modify: `docs/AI活用開発研究/コード品質確認画面/F-001_ログイン/README.md`
- Modify: `docs/AI活用開発研究/作業記録/コード品質確認画面_検証記録.md`

**Interfaces:**
- Consumes: テンプレート配置、共通契約テスト、一括実行コマンド
- Produces: 他機能追加時に再利用できる入力手順と検証証跡

- [ ] **Step 1: READMEへテンプレート利用手順を追加する**

テンプレートを機能フォルダへコピーし、機能固有の値を入力し、`-ValidateOnly`と一括実行を行う手順を追加する。`automatedFindings`を入力JSONへ書かないことを明記する。

- [ ] **Step 2: 検証記録へ移行内容を記録する**

F-001へスキーマバージョンを追加したこと、共通契約テストを導入したこと、元のレビュー記録と機械検証結果を維持したこと、ブラウザ・Oracle・Full実行の未実行理由を記録する。

### Task 5: 最終検証

- [ ] **Step 1: テストを実行する**

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\quality-report-template.tests.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\quality-report.tests.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\simple-mode.tests.ps1
```

- [ ] **Step 2: F-001を一括生成する**

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-quality-reports.ps1 -FeaturePath .\docs\AI活用開発研究\コード品質確認画面\F-001_ログイン
```

- [ ] **Step 3: Docs Simpleゲート、構文、Markdown、差分を確認する**

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1 -Mode Simple -Scope Docs -FocusedUnitNotApplicableReason 'Documentation and static quality report template change has no application unit logic.'
git diff --check
```

Expected: 全テスト成功、Docs Simpleゲート成功、PowerShell構文エラーなし、Markdown lintエラーなし、差分空白エラーなし。
