# 簡易修正モード設計

## 1. 文書情報

- 作成日: 2026-07-25
- 状態: ユーザー承認済み。実装前設計。
- 対象: ProjectFoundation の開発ハーネスと変更記録運用
- 関連入口: `scripts/check.ps1`、`品質ゲート運用.md`、既存のPR必須CI

## 2. 背景と目的

日報承認・差戻し機能の開発で、品質確認自体は必要だった一方、専用仕様書、実装計画、AC/TC/RT台帳、観点別レビュー文書、実行結果の重複転記が作業時間を押し上げた。

変更の規模や技術領域を理由に自動的に簡易モードを拒否するのではなく、作業開始時にユーザーが作業強度を選択できるようにする。簡易修正モードでは、ローカルの確認と記録を最小限にし、全体的な回帰確認は既存CIへ委譲する。

目的は、品質ゲートを弱めることではなく、ローカル確認・文書・レビューの重複を減らし、個別の修正に過剰な工程を適用しないことである。

## 3. 決定事項

### 3.1 モード選択

作業開始時にAIがユーザーへ次の2択を確認する。

1. 簡易修正モード
2. 品質重視モード

選択結果は、PR本文または1枚の変更記録へ必ず記録する。作業途中で変更する場合は、同じ記録へ変更理由を追記する。

### 3.2 適用範囲

ユーザーが簡易修正モードを選択した場合、変更カテゴリや規模による自動昇格は行わない。次の領域も簡易修正モードの対象にできる。

- API契約
- DB、DDL、SQL
- 業務ルール、状態遷移、入力検証
- CI、workflow、品質ゲート

この決定により、簡易修正モードはリスク分類ではなく、作業手順を圧縮するモードとなる。高リスク領域を含む変更でも、CI必須チェックを通過しない限りマージできないことを安全上の前提とする。

### 3.3 品質重視モード

品質重視モードでは、既存のProjectFoundation標準フローを適用する。

- 実装前の設計・受入条件確認
- 正本テストケースとトレーサビリティ
- 必要なP0/P1/P2独立レビュー
- 実装後レビューと統合品質記録
- Full、E2E、coverage、Oracleの対象確認

## 4. 簡易修正モードのフロー

```text
作業開始
  ↓
ユーザーがモード選択
  ├─ 品質重視 → 既存ProjectFoundation標準フロー
  └─ 簡易修正
       ↓
    PR本文または1枚の変更記録を作成
       ↓
    受入条件を3～5項目に整理
       ↓
    Focused Unitを1つの対象範囲で実行
       ↓
    変更対象層のlint / typecheck / buildを実行
       ↓
    表示要件があればbuild後にブラウザ確認を1ケース実行
       ↓
    コード差分を1回独立レビュー
       ↓
    既存CIの全必須チェックで最終判定
```

簡易修正モードでは、専用仕様書、実装計画、AC/TC/RT台帳、実装後レビュー文書を作成しない。受入条件と確認結果は、PR本文または1枚の変更記録へ集約する。

## 5. `check.ps1 -Mode Simple`

### 5.1 役割

既存の `scripts/check.ps1` に `Simple` Modeを追加する。Simple Modeはローカル確認の実行入口だけを担当し、記録文書やレビュー文書を自動生成しない。

既存の `Quick`、`PrePush`、`Full`、`Oracle`、`All` の責務は変更しない。

### 5.2 入力

実装時に次の入力を追加する。名称は実装時にPowerShellの既存命名規約と整合させる。

- `-Scope`: `Docs` / `Frontend` / `Backend` / `Harness` / `Mixed`
- `-FocusedUnitTarget`: Frontendのテストファイル、またはBackendのテストクラス・メソッド
- `-FocusedUnitNotApplicableReason`: Unitテスト対象がない場合の理由
- `-DisplayRequirement`: 表示要件がある場合に指定するスイッチ
- `-BrowserCase`: 既存Playwrightテストのタイトルまたは対象
- `-BrowserManualReason`: 既存Playwrightケースがなく手動確認へ切り替える理由

`Scope`は変更対象をAIまたはユーザーが明示する。ハーネスが変更内容の意味を推測して、テスト範囲を自動決定しない。

### 5.3 入力検証

- `-Mode Simple` と `-CiTask` の同時指定はエラーにする。
- Focused Unitの対象またはN/A理由のどちらかを必須にする。
- `-DisplayRequirement`を指定した場合、`-BrowserCase`または`-BrowserManualReason`を必須にする。
- 失敗した確認は成功扱いにせず、非0終了とする。
- N/Aは、理由がある場合だけ成功扱いにできる。

### 5.4 実行マッピング

| Scope | 実行する確認 |
| --- | --- |
| `Docs` | 変更Markdownのlint、Focused UnitはN/A理由を記録 |
| `Frontend` | Frontend lint、typecheck、build、Focused Unit、必要時のPlaywright 1ケース |
| `Backend` | Spotless / Checkstyle、test-compile、Focused Unit |
| `Harness` | 対象のPowerShell契約テスト、Markdown lint、必要なFocused UnitまたはN/A確認 |
| `Mixed` | 変更対象となる複数Scopeの確認を実行 |

FrontendのFocused Unitは既存の `npm --prefix frontend test` 入口へ対象を渡す。BackendのFocused Unitは既存のMaven Wrapperへ `-Dtest` の対象を渡す。任意のシェル文字列をそのまま実行する入力は追加しない。

表示要件がある場合は、Frontend build成功後に既存のPlaywright設定で対象ケースを1つだけ実行する。既存ケースがない場合はPlaywrightを新規追加せず、手動確認へフォールバックし、理由を変更記録へ残す。

BackendやDocsでtypecheckまたはbuildに相当する確認がない場合は、変更記録の該当欄へ`N/A`と理由を記録する。該当確認を黙って省略しない。

### 5.5 実行しない確認

Simple Modeは、次をローカルで追加実行しない。

- 全テスト
- coverage
- 全E2E
- Oracle
- Simple Modeからの追加の秘密情報検査

ただし、既存のpre-commitのstaged Gitleaksとpre-pushのdirectory Gitleaksは維持する。CIのGitleaksも維持する。

## 6. 既存CIとの関係

簡易修正モードでも、既存のPR必須チェックを変更しない。

- `Full / Windows`
- `Full / Linux`
- `Backend / Unit`
- `Coverage / Frontend`
- `E2E`
- `Gitleaks / Directory`

これらのCIが成功しない限り、簡易修正モードを理由にマージを許可しない。CI、workflow、品質ゲート自体を変更する場合も、必須チェックを弱める例外は追加しない。

## 7. 記録様式

PR本文または1枚の変更記録へ、次の内容だけを記録する。

```markdown
## 開発モード

- [ ] 簡易修正モード
- [ ] 品質重視モード

## 変更概要

- 目的:
- 対象:

## 受入条件

- [ ] 条件1
- [ ] 条件2
- [ ] 条件3

## 確認結果

### Focused Unit

- コマンド:
- 結果:
- 対象なしの場合の理由:

### ブラウザ確認

- 対象:
- 結果:
- 手動確認へ切り替えた場合の理由:

### 変更対象層の確認

- lint:
- typecheck:
- build:

## 独立レビュー

- コード差分レビュー:
- レビュー結果:
- 指摘対応:

## CI委譲

- Full / Windows:
- Full / Linux:
- Backend / Unit:
- Coverage / Frontend:
- E2E:
- Gitleaks / Directory:

> ローカルでは全テスト、coverage、全E2E、追加の秘密情報検査を実行せず、既存CIへ委譲した。
```

受入条件は3～5項目とし、簡易修正モードでは別のAC/TC/RT台帳を作成しない。CI URLや実行結果を別資料へ重複転記しない。

## 8. 独立レビュー

簡易修正モードでは、独立レビューをコード差分について1回だけ実施する。レビュー結果はPR本文または1枚の変更記録へ記録し、観点別の専用レビュー文書は作成しない。

レビューの最低限の確認内容は次のとおりである。

- 変更がPR本文または記録の目的と一致する。
- 受入条件に対して実装が過不足なく対応する。
- Focused Unit、build、必要時のブラウザ確認の結果が記録されている。
- 失敗、N/A、未実行が成功扱いになっていない。
- CI必須チェックを弱める変更が含まれていない。

## 9. 受入条件と将来実装時のテスト観点

| AC ID | 受入条件 | 確認方法 |
| --- | --- | --- |
| AC-SFM-001 | 作業開始時にSimple / Qualityを選択でき、選択結果を1か所へ記録できる | PowerShell契約テスト、記録レビュー |
| AC-SFM-002 | Simple ModeがScopeごとに対象層の確認だけを実行する | PowerShell契約テスト |
| AC-SFM-003 | Focused Unit対象またはN/A理由がない場合に失敗する | PowerShell契約テスト |
| AC-SFM-004 | 表示要件のPlaywrightケースまたは手動フォールバック理由がない場合に失敗する | PowerShell契約テスト |
| AC-SFM-005 | Simple Modeが全テスト、coverage、全E2E、Oracle、追加secret scanを実行しない | 実行定義レビュー、契約テスト |
| AC-SFM-006 | 既存hookのGitleaksとCI必須6チェックを維持する | workflow・hook契約テスト |
| AC-SFM-007 | Simple Modeが専用仕様書、計画、台帳、実装後レビュー文書を生成しない | 文書・runnerレビュー |
| AC-SFM-008 | Focused Unit、lint、typecheck、build、Playwright 1ケースの失敗を非0終了で返す | PowerShell契約テスト、実行確認 |

## 10. 未決事項と実装時の確認

- PowerShellパラメータの最終名称と複数対象の表現は、既存の `check.ps1` 命名・引数構造に合わせて確定する。
- PlaywrightのFocused実行は、既存の `playwright test --grep` 入口で1ケースを選択できることを確認する。
- Frontendのテスト対象指定とBackendの `-Dtest` 指定を、任意シェル実行にならない形で実装する。
- 実装開始前に、PowerShell、Playwright、Maven Wrapperの公式ドキュメントまたは一次情報を確認し、判断根拠を作業記録へ残す。
- CI workflowはSimple専用jobを追加せず、既存必須6チェックの契約テストを更新する。

## 11. 対象外

- Simple ModeでCIをスキップまたは任意化すること
- Simple ModeからOracle、coverage、全E2Eをローカルで自動実行すること
- 簡易修正ごとの専用仕様書・計画書・台帳・実装後レビュー文書の生成
- 変更カテゴリを理由にユーザー選択を自動的に品質重視へ変更すること
