# PMD複雑度ルール適用 設計書

## 目的

Backend Javaコードの複雑度を品質ゲートで検出し、次のPMDルールに違反する実装を受け入れない。

- `CognitiveComplexity`
- `CyclomaticComplexity`
- `NPathComplexity`

既存Backendコードも解析対象とし、既存違反・新規違反を問わずPMD違反があれば品質ゲートを失敗させる。

## 開発モード

簡易修正モード。対象は静的解析設定、Maven品質ゲート、品質ゲート契約テスト、標準資料、作業記録に限定する。

## 対象範囲

### 実装対象

- `backend/pom.xml`へMaven PMD Pluginを追加する。
- `backend/config/pmd.xml`へ3ルールの専用rulesetを追加する。
- `scripts/check.ps1`のBackend品質検査へ`pmd:check`を追加する。
- PMD設定とrunnerの契約テストを追加し、Fullの契約テストから実行する。
- 品質ゲート運用資料、テスト・静的解析チェック表、作業記録を更新する。

### 対象外

- 既存Javaコードの複雑度を下げるリファクタリング。ただし、品質ゲート実行で違反が検出された場合は、品質ゲートを通すために必要な最小修正を別途行う。
- Checkstyle、Spotless、SpotBugsの既存ルール変更。
- Quick / PrePush hookへのPMD追加。
- PMDの3ルール以外のルール追加。
- PMDの警告をベースラインで抑制する仕組み。

## ルールとしきい値

PMD公式のJava Designルールに従い、しきい値は明示的にrulesetへ記載する。

| ルール | プロパティ | 値 | 意味 |
| --- | --- | ---: | --- |
| `CognitiveComplexity` | `reportLevel` | 15 | メソッドの認知的複雑度 |
| `CyclomaticComplexity` | `methodReportLevel` | 10 | メソッドの循環的複雑度 |
| `CyclomaticComplexity` | `classReportLevel` | 80 | クラス全体の循環的複雑度 |
| `NPathComplexity` | `reportLevel` | 200 | メソッドの実行経路数 |

## 実装方針

### PMD設定

`backend/config/pmd.xml`を専用rulesetとし、`category/java/design.xml`から対象3ルールだけを参照する。

Maven PMD Pluginは`3.23.0`を固定し、PMD解析結果でビルドを失敗させる。違反内容をCIログで確認できるよう、失敗詳細を出力する。Backendのmain/test Javaを解析対象とする。

### Maven品質ゲート

`backend/pom.xml`にPMD Pluginを追加し、次の明示ゴールから実行できるようにする。

```text
test-compile spotless:check checkstyle:check spotbugs:check pmd:check
```

`Full` / `FullBackend`では既存のBackend静的解析と同じMaven起動へ含める。`Simple`のBackend対象ではSpotless、Checkstyle、test-compileにPMDを追加する。

Quick / PrePushは既存の軽量検査範囲を維持し、PMDを追加しない。

### 契約テスト

PMDが品質ゲートから抜け落ちないことを、PowerShell契約テストで確認する。

- POMにPMD Pluginと`config/pmd.xml`参照がある。
- POMで失敗時ゲートが有効である。
- rulesetに対象3ルールとしきい値がある。
- `FullBackend`のMavenゴールに`pmd:check`が含まれる。
- `Simple` BackendのMavenゴールに`pmd:check`が含まれる。
- 契約テスト自体がFull Backendの契約テスト集合から実行される。

### 記録・標準化

- `テスト・静的解析チェック表.md`のPMDを適用済みの静的解析として記載する。
- `品質ゲート運用.md`のFull / Simple Backend範囲へPMDを記載する。
- `docs/AI活用開発研究/作業記録/`に今回の変更記録を作成する。
- PMD導入により新しい再発防止観点が発生した場合は、既存資料へ追加する。単なるツール追加で既存観点に収まる場合は、個別対応として記録する。

## 受入条件

- AC-PMD-001: `backend/config/pmd.xml`に対象3ルールが定義され、しきい値が15 / 10・80 / 200である。
- AC-PMD-002: PMD違反がある場合、Backend品質ゲートのMavenコマンドが非0終了する。
- AC-PMD-003: PMD違反がない場合、既存のSpotless、Checkstyle、SpotBugsと同じBackend品質ゲートが成功する。
- AC-PMD-004: `Full`、`FullBackend`、`Simple` Backendの実行経路でPMDが呼び出され、Quick / PrePushには追加されない。
- AC-PMD-005: PMD設定とrunnerの契約テストがFullの契約テスト集合から実行される。
- AC-PMD-006: 運用資料と作業記録に、対象、しきい値、実行モード、未実行条件が記録される。

## 検証方針

### Focused Unit

BackendのPMD設定・runner契約テストをFocused Unit相当として実行する。PMDは設定ファイルとMaven品質ゲートの統合検証で確認する。

### 実行コマンド

```powershell
pwsh -NoProfile -File scripts/pmd.tests.ps1
pwsh -NoProfile -File scripts/check.ps1 -CiTask FullBackend
```

PMD違反が検出された場合は、対象クラス・メソッド、ルール名、複雑度の観測値を記録し、必要な最小修正または保留理由を作業記録へ残す。

### CI委譲

Oracle接続、Frontend、E2E、coverageは今回の変更対象外とし、通常の`main` push後CIへ委譲する。Backend Full品質ゲートはPMDを含めて実行する。

## 公式仕様の確認先

- PMD Maven Plugin: https://pmd.github.io/pmd/pmd_userdocs_tools_maven.html
- PMD Java Design Rules: https://pmd.github.io/pmd/pmd_rules_java_design.html
- PMD Rule Configuration: https://pmd.github.io/pmd/pmd_userdocs_configuring_rules.html

## リスクと対応

- 既存コードに違反がある場合、品質ゲート追加直後からBackend Fullが失敗する。実行結果を確認し、必要最小限の分割・早期return・責務分離を行う。
- PMD Pluginの将来更新でルールの計算結果が変わる可能性があるため、Pluginバージョンを固定し、更新時はrulesetと実行結果を再確認する。
- テストコードも解析対象とするため、テストの複雑度違反が検出される可能性がある。テストの責務分割で対応し、PMD抑制を先行して追加しない。

## 設計承認

2026-08-02、利用者が簡易修正モード、全Backendコード対象、既存・新規違反でゲート失敗、公式デフォルトしきい値（Cyclomatic classReportLevel 80）を承認した。
