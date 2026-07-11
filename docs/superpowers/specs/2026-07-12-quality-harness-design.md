# Quality Harness Design

## Goal

ProjectFoundation の品質確認を、人間、Codex、Git hook、GitHub Actions から同じ入口で再現可能に実行できるようにする。Git hook は補助とし、最終品質ゲートは CI とする。

## Architecture

品質確認の呼び出し関係は次の順序に固定する。

```text
共通チェック用スクリプト -> CI -> Lefthook -> 人間・Codex
```

`scripts/check.ps1` を検査処理の唯一の実行入口とする。CI と Lefthook は個別の lint、test、build コマンドを再定義せず、`check.ps1` のモードまたは CI 用オプションを呼び出す。

チェックは原則として最後まで実行し、終了時に失敗したチェック名を一覧表示する。成功時は終了コード `0`、一つでも失敗した場合は `0` 以外を返す。対話入力と暗黙的なファイル修正・stage は行わない。

## Scope

実装対象:

- Quick、Full、Oracle、All の共通チェック
- セットアップと環境診断
- Lefthook
- GitHub Actions の通常品質、coverage、E2E、Gitleaks、Oracle ジョブ
- frontend、backend、Markdown、secrets の静的解析
- バージョン固定
- 改行、生成物、ローカル設定の Git 管理ルール
- 品質ゲート運用文書

対象外:

- アプリケーション機能の変更
- 本番 Oracle への接続
- GitHub branch protection の API による自動設定
- hook 内での自動修正または自動 stage
- 既存違反を解消するための大規模なソース整形・リファクタ

## File Plan

### New files

| Path | Responsibility |
| --- | --- |
| `.editorconfig` | UTF-8、改行、末尾空白、最終改行のエディタ規約 |
| `.gitattributes` | LFを基本とし、`.bat`と`.cmd`だけCRLFに固定 |
| `.node-version` | Node.jsの固定バージョン |
| `.markdownlint-cli2.jsonc` | Markdown lint対象、除外、既存記法に合わせた規則 |
| `.gitleaks.toml` | secrets検出規則と生成物ディレクトリの除外 |
| `package.json` / `package-lock.json` | リポジトリ共通のNodeツールだけを管理 |
| `lefthook.yml` | pre-commitとpre-pushから共通スクリプトを呼ぶ |
| `scripts/check.ps1` | 全品質チェックの唯一の実行入口 |
| `scripts/bootstrap.ps1` | 依存関係、ブラウザ、Maven依存、Lefthook、Gitleaksの準備 |
| `scripts/doctor.ps1` | 実行環境とOracle環境の診断 |
| `scripts/tool-versions.psd1` | npm外ツールを含む固定バージョンの正本 |
| `.github/workflows/quality.yml` | Full、coverage、E2E、directory Gitleaksを分割実行 |
| `.github/workflows/oracle.yml` | 隔離self-hosted runnerでOracleを実行 |
| `.github/workflows/security.yml` | Git履歴Gitleaksと依存関係監査の定期・手動実行 |
| `.github/CODEOWNERS` | workflowと品質基盤のレビュー所有者 |
| `backend/mvnw` / `backend/mvnw.cmd` | Maven Wrapper起動スクリプト |
| `backend/.mvn/wrapper/maven-wrapper.properties` | Maven本体配布物とWrapper設定 |
| `backend/config/checkstyle.xml` | 段階導入するJavaチェック規則 |
| `docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md` | 実行タイミング、CI、runner、branch protectionの運用 |

### Modified files

- `.gitignore`
- `README.md`
- `AGENTS.md`
- `frontend/package.json`
- `frontend/package-lock.json`
- `backend/pom.xml`
- `backend/local-maven-settings.xml`
- `backend/scripts/test-oracle.ps1`
- `docs/AI活用開発研究/構想メモ/標準化/標準化資料一覧.md`
- `docs/AI活用開発研究/構想メモ/標準化/開発フロー.md`
- `docs/AI活用開発研究/構想メモ/標準化/テスト・静的解析チェック表.md`

## npm Project Boundaries

ルートと `frontend` は独立した npm プロジェクトとして扱い、npm workspaces にはしない。

- ルート `package.json`: Lefthook、Markdownlintなどリポジトリ横断ツールだけを管理する。
- `frontend/package.json`: React、Vite、TypeScript、Vitest、Playwright、ESLintなどfrontend実装とテストだけを管理する。
- `scripts/bootstrap.ps1` はルートと `frontend` で個別に `npm ci` を実行する。
- lockfile、監査結果、依存更新はプロジェクト単位で分離する。

workspaces化は、共通JavaScriptパッケージを複数追加して依存関係を横断管理する必要が生じた場合に再検討する。現状では依存境界を曖昧にするため導入しない。

## Versions

| Tool | Fixed version | Mechanism |
| --- | --- | --- |
| Java | 21 | Maven Enforcer、CI setup-java |
| Maven core | 3.9.16 | Wrapperの`distributionUrl`とchecksum |
| Maven Wrapper | 3.3.4 | Wrapper生成物とwrapper設定 |
| Node.js | 24.18.0 LTS | `.node-version`、CI setup-node、doctor |
| npm | 11.16.0 | `packageManager`、doctor |
| Lefthook | 2.1.10 | ルートdevDependencyとlockfile |
| Gitleaks | 8.30.1 | `tool-versions.psd1`、bootstrap、CI |
| Playwright | 1.58.0 | frontend devDependencyとlockfile |
| markdownlint-cli2 | 0.23.0 | ルートdevDependencyとlockfile |

Maven本体とMaven Wrapperは別製品として別々に固定する。Wrapper `3.3.4` がMaven本体 `3.9.16` を取得・起動する。

## Check Modes

### Quick

コミット前の目標時間を10から20秒、上限を30秒程度とする。

1. `gitleaks git --pre-commit --staged --redact --verbose`
2. stagedされたfrontend対象ファイル名を取得し、そのファイルだけESLint
3. Java変更がある場合にSpotless check
4. stagedされたMarkdownだけMarkdownlint
5. stagedされたテキストの末尾空白、最終改行、禁止生成物を確認

Quickは`git diff --cached --name-only`で対象ファイル名を選ぶが、lint対象の内容はGit indexのblobではなく、作業ツリー上の現在内容を読む。このため部分stageされたファイルでは、コミット予定内容以外の未stage変更も検査対象になる。この仕様を`品質ゲート運用.md`とコマンド出力に明記する。

Quickではfrontend/backend全体テスト、build、E2E、coverage、Oracleを実行しない。TypeScript typecheckはFullで実行し、Quickの時間上限を優先する。

### Full

1. frontend全体ESLint
2. TypeScript typecheck
3. frontend unit test
4. frontend build
5. backend unit test
6. Spotless check
7. Checkstyle
8. SpotBugs

通常はオンラインでMaven Wrapperを実行する。`-Offline`指定時だけMavenへ`-o`を渡す。Oracle設定は要求しない。

### Oracle

1. Oracle設定と安全ガードの確認
2. 接続先、service、DB名、session userの照合
3. Oracle接続確認
4. 明示許可された場合だけDDL・初期化確認
5. `*OracleIT`の実行

### All

`Full`を実行した後に`Oracle`を実行する。Oracle環境がない端末ではOracleとAllは明示的に失敗するが、QuickとFullには影響しない。

## Failure and Logging Behavior

- 各チェックの開始、成功、失敗、所要時間を表示する。
- 失敗しても独立した後続チェックを可能な限り継続する。
- 最後に失敗名と終了コードをまとめる。
- password、token、cookie、JDBC URL内のcredentialを表示しない。
- 前提ツール不足はコード不良と区別して`PREREQUISITE`として表示する。
- Oracle環境不足は`ORACLE_ENVIRONMENT`として表示する。

## Lefthook

Lefthookには検査ロジックを持たせず、次だけを実行する。

```yaml
pre-commit:
  jobs:
    - name: quick-check
      run: pwsh -NoProfile -File scripts/check.ps1 -Mode Quick

pre-push:
  jobs:
    - name: full-check
      run: pwsh -NoProfile -File scripts/check.ps1 -Mode Full
```

`stage_fixed`、自動修正、自動stageは使用しない。

## CI Design

すべてのworkflowに次を明示する。

```yaml
permissions:
  contents: read
```

第三者Actionは可能な限り完全なcommit SHAで固定し、行末コメントに対応するrelease tagを記載する。

### quality.yml

Pull Request、`main`へのpush、手動実行を対象とし、可能な限り次の別ジョブへ分割する。

| Job | Runner | Command |
| --- | --- | --- |
| `full-windows` | GitHub-hosted Windows | `check.ps1 -Mode Full` |
| `full-linux` | GitHub-hosted Ubuntu | `check.ps1 -Mode Full` |
| `coverage-frontend` | GitHub-hosted Ubuntu | `check.ps1 -Mode Full -CiTask FrontendCoverage` |
| `coverage-backend` | GitHub-hosted Ubuntu | `check.ps1 -Mode Full -CiTask BackendCoverage` |
| `e2e` | GitHub-hosted Ubuntu | `check.ps1 -Mode Full -CiTask E2E` |
| `gitleaks-directory` | GitHub-hosted Ubuntu | `check.ps1 -Mode Full -CiTask DirectorySecrets` |

本番OSは明文化されていないが、Linux配備を想定して`full-linux`を必須ジョブとして追加する。CI用タスクはFull全体を再実行せず、同じ`check.ps1`内の該当チェックだけを呼ぶ。

### security.yml

定期・手動でGit履歴Gitleaksとroot/frontend npm監査、Maven依存関係検査を分割実行する。PRの高速な通常ゲートとは分離する。

### oracle.yml

- `workflow_dispatch`と、レビュー済みコードが`main`へ反映された後だけを対象にする。
- `pull_request`では起動せず、PRコードをself-hosted runnerで直接実行しない。
- runner labelは`[self-hosted, Windows, X64, projectfoundation-oracle]`とする。
- 個人環境から隔離された専用VMまたは専用端末、専用非管理者アカウントを使用する。
- 個人ファイル、個人credential、管理者tokenをrunnerから参照できないようにする。
- Oracleは専用テストschemaだけへ到達可能にする。

## Oracle Safety Guards

Oracleモードは次の条件をすべて満たすまで接続テストを開始しない。

- `DAILY_REPORT_DB_ENV=TEST`
- 接続ユーザーが設定済みのexpected test userと完全一致
- JDBC URLのhostとserviceがexpected host/serviceと完全一致
- 接続後の`DB_NAME`、`SERVICE_NAME`、`SESSION_USER`がexpected値と一致
- test userが本番用ユーザー名・管理ユーザー名の拒否リストに一致しない

DDLは既定で禁止する。DDLを実行するには、コマンド引数`-AllowDdl`とローカル設定`DAILY_REPORT_ALLOW_DDL=true`の両方を要求する。DDL対象schemaはsession user自身に限定し、`SYS`、`SYSTEM`、本番名を含むschemaを拒否する。接続先の値はログへ出さず、照合結果だけを表示する。

## Gitleaks Scope

- Quick: staged差分を`gitleaks git --pre-commit --staged --redact --verbose`で確認する。
- Directory CI: checkout直後、Node/Maven依存取得やbuildより前に実行する。
- History CI: 定期・手動workflowで`gitleaks git --redact .`を実行する。

`.gitleaks.toml`で少なくとも`node_modules`、`target`、`dist`、`coverage`、Playwright report、test-results、logs、ローカルtool cacheを除外する。directory scanを依存取得前に実行することで、除外設定の不備があっても生成物の走査を避ける。

## Existing Violation Baseline

静的解析設定を品質ゲートへ組み込む前に、ESLint、Markdownlint、Spotless、Checkstyle、SpotBugsをレポート目的で実行し、既存違反数と対象ファイルを作業記録へ残す。

- 設定ミスと実コード違反を分ける。
- 大量の違反がある規則は、同じ変更で全ソースを修正せず、規則の段階導入または別変更を選ぶ。
- ハーネス導入に不可欠な小数の修正だけを行う場合も、ハーネス変更と区別して記録する。
- formatterによる全体自動修正は実行しない。

## Bootstrap and Doctor

`bootstrap.ps1`はルートとfrontendの`npm ci`、Playwright Chromium、Maven依存事前取得、固定版Gitleaks、Lefthook install、設定サンプルと必須ディレクトリ確認を行う。対話入力を要求しない。

`doctor.ps1`はPowerShell、Java、Maven本体、Maven Wrapper、Node、npm、Lefthook、Gitleaks、Playwright、Oracle client/接続設定、必須環境変数、ローカル設定、使用予定portを診断する。Oracle未構築は通常開発を妨げない警告とする。

## Documentation Ownership

- `テスト方針.md`: 何を、なぜテストするか。
- `テスト・静的解析チェック表.md`: 品質観点と使用ツール。
- `品質ゲート運用.md`: いつ、どのMode・CIジョブを実行するか。
- `scripts/check.ps1`: 実際のコマンド、順序、終了判定の正本。

同じコマンドを複数Markdownへ複製しない。

## Repository Protection Assumptions

`.github/CODEOWNERS`で`.github/workflows/**`、`scripts/**`、`lefthook.yml`、品質設定を`@blackowlest-wq`の所有対象にする。これだけでは強制されないため、GitHubの`main` branch protectionで次を必須化する前提を`品質ゲート運用.md`へ記載する。

- Pull Request経由の変更
- Code Owner review
- 必須CI status checks
- approval後に新しいcommitが追加された場合の再承認
- force pushとbranch deletionの禁止

## Verification

実装後に次を実行し、成功・失敗・未実行理由を報告する。

1. `Quick`
2. `Full`
3. `Oracle`
4. `All`
5. quality workflow相当の各分割ジョブ
6. security workflow相当の各ジョブ
7. oracle workflow相当のself-hosted runnerジョブ
8. Lefthook設定検証とhook経由のQuick/Full
9. `bootstrap.ps1`と`doctor.ps1`

CI/self-hosted runnerを実際に起動できない場合は、workflow構文とローカル同等コマンドを確認し、未実行理由とGitHub上での再確認条件を明記する。
