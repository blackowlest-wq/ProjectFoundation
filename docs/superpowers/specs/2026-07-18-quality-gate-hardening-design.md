# 品質ゲート実効性強化 設計書

## 目的

品質ゲートを「定義されている状態」から「CIで再現性を持って成功し、mainへのマージを実際に抑止できる状態」へ進める。実施順は、CI正常化、branch protection、Backend単体テスト、Oracle安定化、カバレッジ高度化とする。

## 対象

- GitHub ActionsのWindows/Linux実行差異とbootstrap失敗の解消
- publicリポジトリでのmain branch protectionと必須status checkの設定
- Oracle不要のBackend単体テストをPR品質ゲートへ追加
- Oracle workflowのdoctor、bootstrap、runner待機・失敗理由の可視化
- Frontend/Backendカバレッジの出力分離、契約検証、分岐・変更コードの確認強化
- 品質ゲート運用資料、作業記録、指摘一覧の更新

## 対象外

- 業務API、画面、認証認可、CSRF、DBスキーマ、DDLの仕様変更
- Oracle接続資格情報の変更またはログ出力
- self-hosted runner上でのpull requestコード実行
- 85％未満の既存カバレッジを隠すための除外追加

## 設計方針

### 1. CIの実行入口をOS差異から分離する

PowerShellの入口はworkflowでは`pwsh`に統一し、npm script内のWindows専用`powershell`呼び出しを除去する。MavenはWindowsでは`mvnw.cmd`、Unix系では実行権限を持つ`./mvnw`をPOSIX shell経由で実行する。bootstrapのMaven invocationにはBackend POMを明示し、Gitleaksの一時ディレクトリはOSに依存しない一時パスから生成する。

### 2. PR品質ゲートとOracleゲートを分離する

PRではGitHub-hosted runner上でFrontend、DB非依存Backend単体テスト、静的解析、E2E、secret scanを実行する。Oracle統合テスト・Oracle-backed coverage・実接続E2Eは、main反映後の隔離self-hosted runnerで実行する。これにより、PRコードを保護環境へ直接投入せずに、PR時点のBackend回帰を検知する。

### 3. Oracle workflowを自己診断可能にする

Oracle各jobは共通のdoctorと必要なbootstrapを実行する。接続情報不足、runner label不一致、expected identity不一致、Maven/Node/Playwright不足は、テスト失敗と混同せず、明確なpreflight失敗として記録する。Oracle coverageも他のOracle jobと同じ初期化契約を持つ。

### 4. カバレッジはグローバル85％を維持し、段階的に粒度を上げる

既存のStatements/Branches/Functions/LinesおよびINSTRUCTION/BRANCH/METHOD/LINEの85％閾値を維持する。JaCoCo実行データは`backend/target`配下へ分離し、worktreeや並列実行で共有しない。契約テストでは、タスク引数だけでなく閾値、レポートパス、失敗時のレポート確認を検証する。粒度の高い閾値は、まず変更コードまたは重要packageの可視化から始め、既存コードへの一括破壊的適用は避ける。

## BDD受入シナリオ

1. Given publicリポジトリで品質workflowが実行される、When Windows/Linux Full、Frontend coverage、E2E、Gitleaksが完了する、Then各jobが同じ固定入口で成功し、失敗時は原因とartifactが確認できる。
2. Given mainへのPRが作成される、When必須status checkまたはレビューが未完了である、Thenmainへマージできない。
3. Given Oracle不要のBackend単体テストが存在する、When PR品質workflowを実行する、ThenOracle資格情報なしで単体テストと単体カバレッジが実行される。
4. Given main反映後にOracle runnerが利用可能である、When Oracle workflowを実行する、Thendoctor、接続安全確認、テスト、coverageまたはE2E、artifact回収が同じ環境契約で実行される。
5. Given coverage閾値未達またはレポート欠落が発生する、When品質ゲートを実行する、Then成功扱いにならず、レポート確認結果と再実行条件が残る。

## TDD対象

- OS判定に応じたnpm/Maven/Gitleaks実行コマンドの選択
- Maven bootstrapのPOM指定と失敗時の終了判定
- Coverage task契約、レポートパス、閾値、失敗集約の検証
- Oracle coverage jobのdoctor/bootstrap前提
- Oracle不要Backend単体テストのテスト発見とPR実行

## 完了条件

- Windows/LinuxのQuality workflowが成功する。
- Gitleaks、Maven bootstrap、Frontend coverage、E2EがCIで成功する。
- publicリポジトリのmainにPR、Code Ownerレビュー、必須status check、force push禁止、削除禁止が設定される。
- PRでOracle不要Backend単体テストが実行される。
- Oracle coverageを含むOracle workflowがpreflightからartifact回収まで再現可能に実行される。
- Frontend/Backend coverageの4指標が85％以上で、レポートが取得できる。
- 実装後レビュー、指摘一覧、作業記録、品質ゲート運用資料が更新される。

## 確認事項・仮定

- リポジトリをpublic化したため、GitHub Free相当でもpublic repositoryのbranch protectionが利用できる前提で設定する。
- Oracle self-hosted runner、environment secret、test schemaは既存のものを継続利用する。
- Backend単体テスト追加時は既存のテスト命名規約とMaven aggregatorを利用し、workflowへ個別module列挙を追加しない。
- 公式一次情報としてGitHub protected branches、Microsoft PowerShellのUnix差異、Apache Maven Wrapper、JaCoCo Maven pluginの仕様を確認した。
