# 品質確認画面の機械検証化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** AIまたは意味解釈に依存する「不足」「要補足」を自動確認項目から外し、PowerShellがJSONの構造・ID・紐付け・実行結果・基準値から決定的な機械検証結果を生成する。

**Architecture:** 既存JSONを入力正本として保持し、生成スクリプトに`automatedFindings`を追加する。HTML内のJavaScriptは判定ロジックを持たず、PowerShellが生成した検証結果を並べ替えて表示する。`reviewStatus`、`caseDesignStatus`、`要補足`は入力記録として埋め込むが、機械検証結果には含めない。

**Tech Stack:** PowerShell 7、自己完結HTML、埋め込みJSON、既存のPowerShell表示方針テスト

## Global Constraints

- 対象は`docs/AI活用開発研究/コード品質確認画面/F-001_ログイン`に限定する。
- 既存の未コミット変更を破棄、リセット、上書きしない。
- アプリ本体、認証処理、DB、Oracle実行環境は変更しない。
- 新しい外部ライブラリは追加しない。
- 自動検出結果には意味評価を含めず、入力値と機械的に照合できる事実だけを使う。

---

### Task 1: 機械検証結果の表示契約をテストで固定する

**Files:**
- Modify: `docs/AI活用開発研究/コード品質確認画面/F-001_ログイン/F-001_ログイン_表示方針.tests.ps1`
- Test data: `docs/AI活用開発研究/コード品質確認画面/F-001_ログイン/F-001_ログイン_表示データ.json`

**Interfaces:**
- Consumes: `F-001_ログイン_生成.ps1 -DataPath -OutputPath -ValidateOnly`
- Produces: HTML埋め込みデータの`automatedFindings`配列と、決定的な検証失敗メッセージの契約

- [ ] **Step 1: 既存テストへ埋め込みデータ取得ヘルパーを追加する**

既存の生成・HTML読み込み処理を、HTMLから`quality-data` JSONを取得する`Get-GeneratedData`へまとめる。テスト実行時に生成HTMLを直接書き換えず、生成物を正本として検査する。

- [ ] **Step 2: 意味評価が自動検出結果に入らない失敗テストを追加する**

次の契約を追加する。

```powershell
$automatedCategories = @($data.automatedFindings | ForEach-Object { $_.category })
foreach ($forbiddenCategory in @('期待結果・ケース設計不足', '観点判定')) {
    if ($automatedCategories -contains $forbiddenCategory) {
        throw "Semantic review category must not be automated: $forbiddenCategory"
    }
}
if ($automatedCategories -contains '要補足') {
    throw '要補足 must remain an input finding, not an automated finding.'
}
if (-not ($automatedCategories -contains 'ブロッカー')) {
    throw 'Explicit execution blocker must remain visible as an automated fact.'
}
```

実装前は`automatedFindings`が存在しないため、このテストが失敗することを確認する。

- [ ] **Step 3: 紐付け不足を機械検証結果として出す失敗テストを追加する**

一時JSONのケースから`evidenceIds`を空配列にし、生成後の`automatedFindings`に`証跡未紐付け`が対象ケースID付きで存在することを確認する。実装前は配列が存在しないため失敗することを確認する。

- [ ] **Step 4: 未登録IDを検証エラーにする失敗テストを追加する**

一時JSONの`BE-AUTH-001.testImplementationIds[0]`を`MISSING-IMPLEMENTATION`へ変更し、`-ValidateOnly`の終了コードが0以外で、標準エラーまたは標準出力に`unknown`と対象IDが含まれることを確認する。既存検証がこの契約を満たしていない場合だけ実装を補う。

- [ ] **Step 5: テストを実行してREDを確認する**

Run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\docs\AI活用開発研究\コード品質確認画面\F-001_ログイン\F-001_ログイン_表示方針.tests.ps1
```

Expected: `automatedFindings`未生成により、意味評価を除外する契約テストが失敗する。

### Task 2: PowerShellで決定的な自動検出結果を生成する

**Files:**
- Modify: `docs/AI活用開発研究/コード品質確認画面/F-001_ログイン/F-001_ログイン_生成.ps1`

**Interfaces:**
- Consumes: `Read-QualityData`後のJSONオブジェクト
- Produces: `$data.automatedFindings`。各要素は`category`、`id`、`text`、`status`を必須とし、必要に応じて`priority`を持つ

- [ ] **Step 1: 自動検出項目を作る関数を追加する**

`Get-AutomatedFindings`を追加し、次のカテゴリだけを生成する。

```text
受入条件未対応
実テスト未紐付け
証跡未紐付け
ブロッカー
失敗
未実行
品質ゲート
カバレッジ
未通過分岐
指摘・保留（statusが明示的に保留の場合のみ）
```

`reviewStatus`、`caseDesignStatus`、`viewpoints.reviewStatus`、`findings.status=要補足`は参照しない。

- [ ] **Step 2: 生成時に自動検出結果をデータへ追加する**

`Test-QualityData`成功後、HTML埋め込み前に次を実行する。

```powershell
$data | Add-Member -NotePropertyName automatedFindings -NotePropertyValue @(Get-AutomatedFindings -Data $data) -Force
```

`-ValidateOnly`ではHTMLを生成しないが、必須項目、参照ID、実行状態、ゲート、カバレッジの既存検証は継続する。

- [ ] **Step 3: 実行状態・ゲート・カバレッジの事実を既存ルールから移植する**

既存HTMLの`rootCauseGroups`、`qualityGates`、ケース未成功、カバレッジ、未通過分岐、明示的な保留の抽出条件をPowerShell側で同じ条件にする。`reviewStatus`系の分岐は移植しない。根本原因は`rootCauses.match`のlayerとexecutionNoteContainsの文字列照合だけを使い、意味評価は行わない。

- [ ] **Step 4: PowerShellの構文と正常生成を確認する**

Run:

```powershell
pwsh -NoProfile -Command "[System.Management.Automation.Language.Parser]::ParseFile('docs/AI活用開発研究/コード品質確認画面/F-001_ログイン/F-001_ログイン_生成.ps1',[ref]$null,[ref]$null) | Out-Null"
pwsh -NoProfile -ExecutionPolicy Bypass -File .\docs\AI活用開発研究\コード品質確認画面\F-001_ログイン\F-001_ログイン_生成.ps1 -ValidateOnly
```

Expected: 構文エラーなし、既存JSONの検証成功。

### Task 3: HTMLを判定ロジックなしの表示へ変更する

**Files:**
- Modify: `docs/AI活用開発研究/コード品質確認画面/F-001_ログイン/F-001_ログイン_生成.ps1`
- Generated: `docs/AI活用開発研究/コード品質確認画面/F-001_ログイン/F-001_ログイン_コード品質確認.html`

**Interfaces:**
- Consumes: `data.automatedFindings`
- Produces: 自動検出結果を表示する`機械検証結果`パネル

- [ ] **Step 1: HTMLの`gaps`導出を`automatedFindings`参照へ置き換える**

ブラウザ側でケース、観点、指摘の意味状態から`gaps`を追加しない。`const orderedGaps = ...`は`data.automatedFindings`を優先し、表示順だけを決める。

- [ ] **Step 2: 受入条件の確認状況から設計不足分岐を削除する**

`deriveAcceptance`から`designStatus`と`designGaps`の参照を削除し、確認状況はケースの失敗・未実行・ブロッカーだけで決める。受入条件の入力JSONにある`caseDesignStatus`は保持するが、表示は自動判定として扱わない。

- [ ] **Step 3: 概要カードとパネル名を事実ベースに変更する**

`観点不足`を`観点一覧`へ変更し、件数は観点総数とする。「不足・保留」パネルは「機械検証結果」へ変更し、説明文から設計不足を削除する。

- [ ] **Step 4: 表示方針テストをGREENにする**

生成HTMLに`機械検証結果`、`automatedFindings`由来の`ブロッカー`、`品質ゲート`、`未実行`が表示され、`期待結果・ケース設計不足`と`観点判定`が機械検証結果に表示されないことを確認する。指摘一覧には入力記録として`要補足`を残す。

### Task 4: 生成物と作業記録を検証する

**Files:**
- Modify: `docs/AI活用開発研究/作業記録/コード品質確認画面_検証記録.md`
- Review: `docs/AI活用開発研究/コード品質確認画面/F-001_ログイン/README.md`

- [ ] **Step 1: 表示方針テストを実行する**

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\docs\AI活用開発研究\コード品質確認画面\F-001_ログイン\F-001_ログイン_表示方針.tests.ps1
```

- [ ] **Step 2: 生成物を再生成する**

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\docs\AI活用開発研究\コード品質確認画面\F-001_ログイン\F-001_ログイン_生成.ps1
```

- [ ] **Step 3: 埋め込みJSONとHTML文字列を検査する**

`quality-data`を`ConvertFrom-Json`で読み、`automatedFindings`のカテゴリに意味評価がないこと、証跡表示から前回削除した5項目が復活していないこと、外部依存がないことを確認する。

- [ ] **Step 4: 検証記録へ機械検証化の結果を追記する**

変更対象、テスト結果、未実行のブラウザ確認、元データを変更しなかった理由、今回の追加指摘の標準化判定を記録する。今回の指摘は「標準化候補」とし、品質確認画面の共通生成方針へ反映要否を記載する。

### Task 5: 最終確認

- [ ] **Step 1: 差分が対象範囲内であることを確認する**

```powershell
git status --short
git diff --check
```

既存のユーザー変更を含め、意図しないファイルの変更がないことを確認する。

- [ ] **Step 2: 計画と仕様の自己レビューを行う**

仕様書の全項目が、PowerShell検証、HTML表示、テスト、記録のいずれかでカバーされていることを確認する。`reviewStatus`系を自動検出へ戻す分岐、`要補足`を確認項目へ戻す分岐、総合評価を生成する分岐が残っていないことを確認する。
