# 品質ハーネス修正と工程圧縮 設計書

## 1. 対象

- 対象リポジトリ: `ProjectFoundation`
- 対象期間: 2026-07-24以降の全機能追加・大きめの修正
- パイロット対象: 日報承認・差戻し機能で検出された品質ハーネスの失敗と工程上の重複
- 承認日: 2026-07-24

## 2. 背景

日報承認・差戻し機能では、認可、CSRF、状態遷移、DDL、監査情報、Frontend、E2Eを含むため、設計・テスト・セキュリティ・実装後レビューを実施した。このレビュー観点とRequired CIは変更リスクに対して妥当だった。

一方、次の問題が確認された。

1. BackendCoverageはテスト自体が成功してもJaCoCo成果物が生成されず、レポート検証で失敗した。テスト失敗、カバレッジ閾値未達、成果物欠落、Oracle環境未実行の違いが作業記録上で追跡しにくい。
2. Oracleの専用runnerが利用できない場合、実DB検証が未実行になる。未実行を成功扱いにはしていないが、Required CIの成功とリリース確信度の差が工程上分かりにくい。
3. AC・TC・RT・指摘・品質ゲート結果が複数の資料へ重複記載され、Taskごとのレビューと再レビューで同じ事実を再確認する作業が発生した。
4. 機能実装、CI基盤修正、作業記録の整備が同じ変更範囲に混在し、レビュー対象と工数の境界が不明確になった。

## 3. 目的

- 品質レビューの観点、独立性、Required CI、閾値を維持する。
- ハーネスが失敗した場合に、失敗箇所と再確認条件を明確に出力する。
- テスト成功と品質ゲート完了を混同しない。
- 記録の正本を整理し、同じ内容の転記と再レビューを減らす。
- 機能変更とCI・開発基盤変更の境界を明確にする。

## 4. 対象外

- セキュリティレビュー、設計レビュー、テストケースレビューの廃止・任意化
- Required status checkの削除、カバレッジ閾値の引き下げ、Gitleaksの省略
- OracleをPRで必須実行する変更
- 日報承認・差戻し本体の競合更新仕様をこの作業で変更すること
- 既存機能のレビュー記録を機械的に全件書き換えること

承認機能の更新競合については、別途「同時実行時の状態遷移・原子性」を確認する課題として残す。今回の対象はハーネスと工程設計であり、機能コードの変更は必要最小限とする。

## 5. 基本方針

### 5.1 維持する品質確認

大きめの変更では、従来どおり次を適用する。

- P0: 設計・受入条件、テスト不足、テスト構成、期待結果、トレーサビリティ・統合
- P1: 認証・認可・CSRF・入力検証、可読性・配置・共通化、静的解析・CI、ログ・観測可能性
- P2: 競合、性能、互換性、アクセシビリティなど、変更リスクに応じて適用
- Required CI: `Full / Windows`、`Full / Linux`、`Backend / Unit`、`Coverage / Frontend`、`E2E`、`Gitleaks / Directory`

レビューの数を減らすのではなく、同じ観点をTaskごとに繰り返す回数を減らす。

### 5.2 レビューの集約単位

機能単位で、次の3チェックポイントへ集約する。

1. Backend / DB / Security: API、認可、CSRF、入力、DDL、状態遷移、DB不変条件、ログ
2. Frontend / UI: API契約、状態表示、エラー、アクセシビリティ、UI単体テスト
3. Integration / Final: E2E、静的解析、カバレッジ、CI、トレーサビリティ、残存リスク

各担当は他担当の結論を前提にせず、指定された一次資料と対象範囲から独立に判定する。最終統合担当だけが重複、矛盾、保留、ゲート結果を集約する。

### 5.3 記録の正本

機能ごとに統合品質記録を1つ置き、次を正本として管理する。

- 対象範囲・対象外・完了条件
- AC、TC、RT、FINDの対応表
- レビュー結果、判定、根拠、保留条件
- コマンド、CI run、Oracle run、成果物へのリンク
- 未実行理由と再確認条件
- 標準化判定

受入条件レビュー、テストケースレビュー、専門レビューは各観点の詳細を保持する。ただし、同じ実行結果や指摘本文を転記せず、統合品質記録へのリンクと差分だけを記録する。

## 6. ハーネス設計

### 6.1 BackendCoverageの失敗分類

`BackendCoverage`は、次の順序で結果を分類する。

1. Oracle接続・安全ガード
2. Maven test/verifyの終了コード
3. JaCoCoのデータファイル生成
4. HTML/XML/CSVレポート生成
5. カバレッジ閾値判定

各段階の失敗は、同じエラー名を使わず、少なくとも次へ分類する。

- `ORACLE_PREFLIGHT_FAILED`
- `BACKEND_TEST_FAILED`
- `JACOCO_DATA_MISSING`
- `JACOCO_REPORT_MISSING`
- `BACKEND_COVERAGE_THRESHOLD_FAILED`

テスト成功後に成果物が欠落した場合も成功扱いにしない。診断メッセージには、確認したパス、実行したMaven goal、profile、再確認条件を含める。ただし、接続URL、ユーザー名、パスワードなどの秘密・接続値は出力しない。

### 6.2 BackendCoverageの根本原因調査

実装前に、Oracle接続の有無とは分離して、次を確認できる再現入口を用意する。

- `scripts/check.ps1 -CiTask BackendCoverage` が実際に渡すPowerShell、Maven profile、goal
- `backend/pom.xml`のJaCoCo `prepare-agent`、`report`、`check`の各phase
- Maven Surefire/FailsafeがforkしたJVMへJaCoCo agentを引き渡しているか
- `backend/target/jacoco.exec`、`backend/target/site/jacoco/*`の生成タイミング
- wrapper終了コードとレポート確認処理の終了コード伝播

根本原因を確認した後、最小変更で修正し、次の契約テストを追加する。

- `verify`がcoverage profileを使用すること
- report確認が実行順序の後段にあること
- レポート欠落時の分類が固定されていること
- 成功したテスト数だけでは成功扱いにならないこと

### 6.3 Oracle環境未実行の扱い

Oracle専用runnerの未配置、キュー滞留、キャンセル、事前診断失敗を、コード不具合と混同しない。ただし、いずれも「実DB検証済み」とは記録しない。

Oracle実行結果は次のいずれかで記録する。

- `PASSED`: 実行し、全チェック成功
- `FAILED`: 実行し、テストまたはゲート失敗
- `NOT_RUN_ENVIRONMENT`: runner・秘密情報・接続環境不足
- `CANCELLED_OR_TIMEOUT`: 実行開始後にキャンセルまたはタイムアウト

`NOT_RUN_ENVIRONMENT`と`CANCELLED_OR_TIMEOUT`は、mainのリリース判定では未完了として扱う。PRのRequired CIへOracleを追加することは、本設計の範囲外とする。

## 7. 実行計画の圧縮

### 7.1 実行層の責務

| 層 | 実行内容 | 重複させない内容 |
| --- | --- | --- |
| Quick | staged空白、生成物、secret、変更対象lint | Full相当のテスト・build |
| PrePush | push対象差分、軽量lint、必要なSpotless | Full、coverage、Oracle |
| PR Required CI | Full、Backend Unit、Frontend Coverage、Mock E2E、Gitleaks | ローカルFullの再実行を完了条件にしない |
| main後Oracle | Oracle安全ガード、実DB統合、BackendCoverage、実Backend E2E | PRでOracleを重複実行しない |

ローカルのFullは任意の事前確認とし、PR Required CIを最終判定とする。失敗時は、ローカル再実行を無制限に繰り返さず、該当する層のログと分類を確認する。

### 7.2 PRの境界

- 機能PR: 本体、機能テスト、機能固有のDDL、必要なテストfixture
- ハーネス・CI PR: check runner、workflow、coverage、Oracle preflight、共通テスト
- 標準資料PR: 開発フロー、品質ゲート運用、記録様式、レビュー運用

緊急の不具合修正を除き、3種類を混在させない。依存関係がある場合は、PR説明に先行PRを明記する。

## 8. 受入条件とテスト対応

| AC ID | 受入条件 | テスト層 | 実テストID・確認方法 |
| --- | --- | --- | --- |
| AC-HRN-001 | BackendCoverageがテスト成功、成果物欠落、閾値未達、Oracle未実行を区別する | PowerShell contract / Maven | RT-HRN-001〜004 |
| AC-HRN-002 | JaCoCo成果物が欠落した場合、ハーネスは非0終了し、確認パスと再確認条件を出力する | PowerShell contract | RT-HRN-005 |
| AC-HRN-003 | 秘密値・接続値を失敗ログへ出力しない | PowerShell security contract / CI | RT-HRN-006 |
| AC-HRN-004 | Oracle未実行を実DB検証済みとして記録しない | workflow contract / 作業記録レビュー | RT-HRN-007 |
| AC-HRN-005 | P0/P1レビュー観点とRequired CIの一覧が変更前後で維持される | 標準資料レビュー / contract | RT-HRN-008 |
| AC-HRN-006 | 統合品質記録を正本とし、詳細資料から重複実行結果を転記しない | 文書レビュー | RT-HRN-009 |
| AC-HRN-007 | 機能PR、ハーネスPR、標準資料PRの責務境界が確認できる | PR template / 文書レビュー | RT-HRN-010 |

P0/P1レビューは、AC-HRN-005〜007の確認対象として維持する。レビューを実行しないことを工程圧縮の成果とはしない。

## 9. 完了条件

- BackendCoverageの根本原因をログと実行経路で特定している
- 成果物欠落を検出する契約テストがあり、失敗分類が安定している
- Oracle未実行・キャンセル・環境不足が成功扱いにならない
- Required CIの6 check名、閾値、レビュー優先度が維持されている
- 標準資料に3チェックポイント、正本記録、実行層、PR境界が反映されている
- 既存の品質レビュー資料に、レビュー削減ではなく重複記録削減であることが反映されている
- Quick/PrePush/Full/Oracleの各入口について、同じ処理を重複実行しない理由が記録されている
- 変更後にQuick、Full、契約テスト、利用可能なOracle診断を実行し、未実行理由を記録している

## 10. リスクと判断

### リスク

- 記録を一本化しすぎると、専門レビューの根拠が失われる
- Oracle環境の未実行状態を厳密に分類すると、main後の未完了が可視化される
- ハーネスの分類修正が、既存workflowの終了コードやartifact収集へ影響する

### 対策

- 専門レビュー資料は残し、統合品質記録から相互リンクする
- 「未実行」と「成功」を分けたまま、Required CIへOracleを追加しない
- 契約テストを先に追加し、runner・workflow変更は最小差分で検証する
- ハーネスPRと標準資料PRを分け、各PRでFullと該当契約テストを実行する

## 11. 次の作業

1. BackendCoverageを実行経路・Maven lifecycle・成果物パスの順に再現調査する
2. 最小の契約テストを先に追加する
3. ハーネスを修正し、Quick/Fullで検証する
4. 標準資料と統合品質記録の様式を更新する
5. 実装後レビューで、レビュー観点が維持され、重複作業だけが圧縮されたことを確認する
