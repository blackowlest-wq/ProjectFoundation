# 品質ゲート構成のmain取り込み 設計書

## 背景

`main`には`.git/hooks`のLefthook起動スクリプトだけが残り、リポジトリ直下の`lefthook.yml`、品質チェックRunner、GitHub Actionsが含まれていなかった。そのため、コミット・プッシュ時にLefthookが設定なしで終了し、テストや静的解析が実行されなかった。

品質ゲート用worktreeの`feature/quality-harness`には、次の段階的な実装が存在する。

- リポジトリ共通のツールバージョン、依存関係、Gitleaks、Markdown lint設定
- stagedファイル向けQuickチェックと全体Fullチェックを実行するPowerShell Runner
- Node、Maven、Playwright、Lefthook、GitleaksのBootstrap/Doctor
- Oracle接続・DDL安全ガード
- Quality、Security、OracleのGitHub Actions

## 目的

- `main`をcloneした環境でも、品質ゲート設定がリポジトリから復元できるようにする。
- `git commit`でstaged差分の軽量チェックを実行する。
- `git push`でFrontend、Backend、静的解析を含むFullチェックを実行する。
- 設定・ツール不足を成功扱いにせず、品質ゲートをfail closedにする。
- Pull Request、mainへのpush、定期実行でCI品質・セキュリティ・Oracle検査を実行する。

## 対象範囲

### 対象

- `lefthook.yml`
- `scripts/bootstrap.ps1`、`scripts/check.ps1`、`scripts/doctor.ps1`、`scripts/tool-versions.psd1`
- root/FrontendのNode依存、ESLint、Markdown lint、Gitleaks設定
- BackendのMaven Wrapper、Spotless、Checkstyle、SpotBugs設定
- Oracleテスト入口、Oracle安全ガード、Oracle用サンプル設定
- `.github/workflows/quality.yml`、`security.yml`、`oracle.yml`、`CODEOWNERS`
- 品質ゲートの標準資料、README、AGENTS、作業記録、指摘一覧

### 対象外

- 日報機能の業務仕様、API契約、画面動作の変更
- 人手によるコードレビューの自動代替
- GitHub側のBranch Protection設定変更。これはリポジトリ設定として別途必要とする。

## 設計

### ローカル実行

`lefthook.yml`をリポジトリ直下に置き、`pre-commit`から`pwsh -NoProfile -File scripts/check.ps1 -Mode Quick`、`pre-push`から`pwsh -NoProfile -File scripts/check.ps1 -Mode Full`を呼び出す。

Quickはstaged差分の空白、生成物混入、Frontend staged lint、Markdown lint、JavaのSpotless、Gitleaksを確認する。FullはFrontend lint/typecheck/unit/build、Backend compile/Spotless/Checkstyle/SpotBugsを確認する。

Lefthook設定、必要な実行ファイル、PowerShell 7、Node、Java、Maven、Playwright、Gitleaksが不足している場合は、BootstrapまたはDoctorで明示的に失敗させる。Hookの起動スクリプトがLefthookを発見できない場合も、警告だけで成功扱いにしない。

### CI実行

- Quality: Pull RequestとmainへのpushでWindows/LinuxのFull、Frontend coverage、E2E、Directory Gitleaksを実行する。
- Security: 週次と手動実行でGit履歴Gitleaksと依存関係監査を実行する。
- Oracle: mainへのpushと手動実行でOracle integrationとBackend coverageを実行する。

CIは自動検査を担い、人手レビューはPull Requestの承認とBranch Protectionで担う。

### Oracle安全性

Oracleテストは`backend/scripts/test-oracle.ps1`を共通入口とし、接続情報はローカル設定または保護されたプロセス環境から読み取る。DDL実行は明示的な許可がなければ拒否し、Oracle安全ガードテストで危険な設定を検出する。

## 代替案と採用理由

- Hookから各テストコマンドを直接呼ぶ方式: 実行順、CIとの共有、失敗集約が分散するため採用しない。
- CIだけで品質を確認する方式: push前に明らかな不備を検出できず、今回の空振りを再発させるため採用しない。
- `.git/hooks`だけを修正する方式: clone後に再現できず、Hookがバージョン管理されないため採用しない。

## 受入条件

1. `main`の作業ツリーに`lefthook.yml`と品質Runnerが存在し、設定がGit管理される。
2. `scripts/doctor.ps1`が不足ツールやバージョン差異を検出する。
3. `git commit`でQuick、`git push`でFullが呼び出され、チェック失敗時は非0終了する。
4. Quality、Security、OracleのWorkflowがGit管理され、対象イベントで実行される。
5. Oracle接続情報、生成物、秘密情報が通常の差分に混入しない。
6. 既存のBackend/Frontendテストとビルドが品質Runnerから実行可能である。
