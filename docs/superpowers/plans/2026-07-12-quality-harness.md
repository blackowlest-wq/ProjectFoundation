# Quality Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 人間、Codex、Lefthook、GitHub Actionsが同じPowerShell入口から、Quick・Full・Oracle・AllおよびCI専用品質チェックを再現可能に実行できる品質ハーネスを構築する。

**Architecture:** `scripts/check.ps1`を検査コマンドの唯一の入口とし、LefthookとCIはモードまたはCI専用タスクを指定して呼び出す。通常品質はGitHub-hosted Windows/Linux、OracleはPRコードを直接実行しない隔離self-hosted runnerへ分離する。rootとfrontendは独立npmプロジェクトとして個別のlockfileを持つ。

**Tech Stack:** PowerShell 7、Git、Lefthook 2.1.10、Gitleaks 8.30.1、Node.js 24.18.0、npm 11.16.0、ESLint 10.6.0、Maven Wrapper 3.3.4、Maven 3.9.16、Java 21、Spotless、Checkstyle、SpotBugs、GitHub Actions

## Global Constraints

- Git hookを品質保証の中心にせず、最終品質ゲートはCIとする。
- 検査処理は`scripts/check.ps1`へ集約し、CIとLefthookに重複定義しない。
- rootと`frontend`は独立npmプロジェクトとし、workspaces化しない。
- Java 21、Maven core 3.9.16、Maven Wrapper 3.3.4を別々に固定する。
- Node.js 24.18.0、npm 11.16.0、Lefthook 2.1.10、Gitleaks 8.30.1、Playwright 1.58.0を固定する。
- Quickは30秒以内を目標にし、全体テスト、build、E2E、coverage、Oracleを実行しない。
- staged lintはGit indexから対象ファイル名を選ぶが、検査内容は作業ツリー上の現在内容とする。
- hookは自動修正、自動stage、`stage_fixed`を行わない。
- CI workflowは`permissions: contents: read`を指定し、第三者Actionを完全SHAで固定する。
- self-hosted runnerは個人環境から隔離し、PRコードを直接実行しない。
- Oracleはテスト接続先、テストユーザー、DB識別情報を照合し、DDLを二重許可制にする。
- directory Gitleaksは依存取得・build前に実行し、生成物を`.gitleaks.toml`でも除外する。
- 静的解析導入前に既存違反数を計測し、大量の無関係な修正を同じ変更へ含めない。
- 既存のユーザー変更と未追跡ファイルを削除・巻き戻ししない。

---

### Task 1: Repository hygiene and root tooling

**Files:**

- Create: `.editorconfig`
- Create: `.gitattributes`
- Create: `.node-version`
- Create: `.markdownlint-cli2.jsonc`
- Create: `.gitleaks.toml`
- Create: `package.json`
- Create: `package-lock.json`
- Modify: `.gitignore`
- Test: Git ignore、改行属性、root npm lockfile

**Interfaces:**

- Consumes: Node.js 24.18.0、npm 11.16.0、既存の生成物配置
- Produces: 後続タスクが使用するroot tooling、Markdown/Gitleaks設定、生成物除外

- [ ] **Step 1: 現在の生成物とローカル状態を記録する**

Run:

```powershell
git status --short --untracked-files=all | Set-Content -Encoding UTF8 "$env:TEMP\projectfoundation-status-before-harness.txt"
git check-ignore -v frontend/node_modules frontend/dist frontend/coverage backend/target logs 2>$null
```

Expected: 現在は`backend/target`などが十分にignoreされていないことを確認し、ユーザー作業を削除しない。

- [ ] **Step 2: 共通編集・Git設定を追加する**

`.editorconfig`:

```editorconfig
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

[*.{bat,cmd}]
end_of_line = crlf

[*.md]
trim_trailing_whitespace = false
```

`.gitattributes`:

```gitattributes
* text=auto eol=lf
*.bat text eol=crlf
*.cmd text eol=crlf
*.png binary
*.jpg binary
*.jpeg binary
*.gif binary
*.pdf binary
*.zip binary
*.jar binary
```

`.node-version`:

```text
24.18.0
```

- [ ] **Step 3: `.gitignore`を生成物・ローカル設定へ拡張する**

`.gitignore`を次の内容へ更新する。

```gitignore
# Node / frontend
node_modules/
frontend/dist/
frontend/coverage/
frontend/playwright-report/
frontend/test-results/
frontend/debug.log

# Maven / Java
backend/target/

# Local database and secret-bearing configuration
backend/config/oracle-test.properties

# Local tools and reports
.tools/
logs/
*.log

# IDE / OS
.idea/
.vscode/
*.iml
.DS_Store
Thumbs.db

```

- [ ] **Step 4: root npm toolingを追加する**

`package.json`:

```json
{
  "name": "projectfoundation-tooling",
  "private": true,
  "packageManager": "npm@11.16.0",
  "engines": {
    "node": "24.18.0",
    "npm": "11.16.0"
  },
  "scripts": {
    "hooks:install": "lefthook install",
    "hooks:validate": "lefthook validate",
    "lint:markdown": "markdownlint-cli2"
  },
  "devDependencies": {
    "lefthook": "2.1.10",
    "markdownlint-cli2": "0.23.0"
  }
}
```

Run:

```powershell
npm.cmd install --package-lock-only --ignore-scripts
npm.cmd ci --ignore-scripts
```

Expected: root `package-lock.json`が作成され、frontend lockfileは変更されない。

- [ ] **Step 5: MarkdownとGitleaksの対象範囲を設定する**

`.markdownlint-cli2.jsonc`:

```jsonc
{
  "config": {
    "MD013": false,
    "MD033": false,
    "MD041": false
  },
  "globs": [
    "**/*.md",
    "#**/node_modules/**",
    "#frontend/coverage/**",
    "#backend/target/**"
  ]
}
```

`.gitleaks.toml`:

```toml
[extend]
useDefault = true

[[allowlists]]
description = "Generated and local-only directories"
paths = [
  '''(^|/)node_modules/''',
  '''(^|/)backend/target/''',
  '''(^|/)frontend/(dist|coverage|playwright-report|test-results)/''',
  '''(^|/)logs/''',
  '''(^|/)\.tools/'''
]
```

- [ ] **Step 6: Repository hygieneを検証する**

Run:

```powershell
git check-ignore -v frontend/node_modules frontend/dist frontend/coverage backend/target logs/frontend-dev.out.log backend/config/oracle-test.properties
git check-attr text eol -- .editorconfig scripts/check.ps1 backend/mvnw.cmd
npm.cmd run lint:markdown -- --no-globs README.md AGENTS.md
git diff --check
```

Expected: 生成物はignoreされ、`.cmd`はCRLF、それ以外のテキストはLF、Markdown検査と`git diff --check`が成功する。

- [ ] **Step 7: Task 1をコミットする**

```powershell
git add .editorconfig .gitattributes .node-version .markdownlint-cli2.jsonc .gitleaks.toml package.json package-lock.json .gitignore
git commit -m "build: add repository quality tooling baseline"
```

---

### Task 2: Frontend ESLint and existing-violation baseline

**Files:**

- Create: `frontend/eslint.config.mjs`
- Modify: `frontend/package.json`
- Modify: `frontend/package-lock.json`
- Create: `docs/AI活用開発研究/作業記録/品質ハーネス_既存違反調査.md`
- Test: frontend ESLint、既存unit test、typecheck

**Interfaces:**

- Consumes: frontend TypeScript/React構成、rootとは独立したfrontend npm project
- Produces: `npm run lint`、Quickでファイル指定できるESLint設定、既存違反記録

- [ ] **Step 1: ESLint依存関係と固定Playwright版を追加する**

Run in `frontend`:

```powershell
npm.cmd install --save-dev --save-exact eslint@10.6.0 @eslint/js@10.0.1 typescript-eslint@8.62.1 eslint-plugin-react-hooks@7.1.1
npm.cmd install --save-dev --save-exact @playwright/test@1.58.0
```

`frontend/package.json`へ次を追加する。

```json
"packageManager": "npm@11.16.0",
"engines": {
  "node": "24.18.0",
  "npm": "11.16.0"
}
```

scriptsへ追加:

```json
"lint": "eslint . --ext .ts,.tsx --max-warnings 0"
```

- [ ] **Step 2: Flat configを追加する**

`frontend/eslint.config.mjs`:

```javascript
import eslint from '@eslint/js';
import reactHooks from 'eslint-plugin-react-hooks';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  {
    ignores: ['dist/**', 'coverage/**', 'playwright-report/**', 'test-results/**'],
  },
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['**/*.{ts,tsx}'],
    plugins: {
      'react-hooks': reactHooks,
    },
    rules: {
      'no-undef': 'off',
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'error',
    },
  },
);
```

- [ ] **Step 3: 品質ゲート化前の既存違反数を計測する**

Run:

```powershell
Push-Location frontend
npm.cmd run lint -- --format json --output-file "$env:TEMP\projectfoundation-eslint-baseline.json"
$lintExit = $LASTEXITCODE
Pop-Location
Write-Host "ESLint baseline exit code: $lintExit"
```

Expected: 出力JSONから違反総数・対象ファイル数・規則別件数を集計し、`品質ハーネス_既存違反調査.md`へ記録する。20件超または10ファイル超の場合はソース一括修正を行わず、段階導入規則として記録する。20件以下かつ10ファイル以下の場合も、ソース修正はこのタスクと別コミットにする。

- [ ] **Step 4: frontendゲートを検証する**

Run:

```powershell
Push-Location frontend
npm.cmd run lint
npm.cmd run typecheck
npm.cmd test
Pop-Location
```

Expected: lint、typecheck、既存unit testが成功する。既存違反が基準を超えた場合は、調査記録に明示した限定ルールでlintを成功させる。

- [ ] **Step 5: Task 2をコミットする**

```powershell
git add frontend/package.json frontend/package-lock.json frontend/eslint.config.mjs 'docs/AI活用開発研究/作業記録/品質ハーネス_既存違反調査.md'
git commit -m "build: add frontend static analysis baseline"
```

---

### Task 3: Maven Wrapper and backend static-analysis baseline

**Files:**

- Create: `backend/mvnw`
- Create: `backend/mvnw.cmd`
- Create: `backend/.mvn/wrapper/maven-wrapper.properties`
- Create: `backend/config/checkstyle.xml`
- Modify: `backend/pom.xml`
- Modify: `backend/local-maven-settings.xml`
- Modify: `docs/AI活用開発研究/作業記録/品質ハーネス_既存違反調査.md`
- Test: Wrapper version、unit test、Spotless、Checkstyle、SpotBugs

**Interfaces:**

- Consumes: Java 21、Maven core 3.9.16、既存Spring Boot pom
- Produces: `backend/mvnw(.cmd)`とFullが呼ぶ静的解析goal

- [ ] **Step 1: Maven Wrapper 3.3.4でMaven 3.9.16を固定する**

Run in `backend`:

```powershell
mvn.cmd org.apache.maven.plugins:maven-wrapper-plugin:3.3.4:wrapper -Dmaven=3.9.16 -Dtype=only-script
```

Expected: `mvnw`、`mvnw.cmd`、`.mvn/wrapper/maven-wrapper.properties`が作成され、`distributionUrl`はMaven 3.9.16を指す。`distributionSha256Sum`もApache配布物のSHA-256で設定する。

- [ ] **Step 2: ユーザー固有Maven repository pathを除去する**

`backend/local-maven-settings.xml`の`localRepository`を次へ変更する。

```xml
<localRepository>${user.home}/.m2/repository</localRepository>
```

- [ ] **Step 3: 最小のCheckstyle規則を追加する**

`backend/config/checkstyle.xml`:

```xml
<?xml version="1.0"?>
<!DOCTYPE module PUBLIC
    "-//Checkstyle//DTD Checkstyle Configuration 1.3//EN"
    "https://checkstyle.org/dtds/configuration_1_3.dtd">
<module name="Checker">
    <module name="NewlineAtEndOfFile"/>
    <module name="FileTabCharacter"/>
    <module name="TreeWalker">
        <module name="AvoidStarImport"/>
        <module name="UnusedImports"/>
    </module>
</module>
```

- [ ] **Step 4: pomへ固定プラグインを追加する**

`properties`へ追加:

```xml
<maven.version>3.9.16</maven.version>
<maven-enforcer-plugin.version>3.6.2</maven-enforcer-plugin.version>
<spotless-maven-plugin.version>3.6.0</spotless-maven-plugin.version>
<maven-checkstyle-plugin.version>3.6.0</maven-checkstyle-plugin.version>
<spotbugs-maven-plugin.version>4.10.2.0</spotbugs-maven-plugin.version>
```

`build/plugins`へ以下の役割で追加する。

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-enforcer-plugin</artifactId>
    <version>${maven-enforcer-plugin.version}</version>
    <executions>
        <execution>
            <id>enforce-toolchain</id>
            <goals><goal>enforce</goal></goals>
            <configuration>
                <rules>
                    <requireJavaVersion><version>[21,22)</version></requireJavaVersion>
                    <requireMavenVersion><version>[3.9.16,3.9.17)</version></requireMavenVersion>
                </rules>
            </configuration>
        </execution>
    </executions>
</plugin>
<plugin>
    <groupId>com.diffplug.spotless</groupId>
    <artifactId>spotless-maven-plugin</artifactId>
    <version>${spotless-maven-plugin.version}</version>
    <configuration>
        <formats>
            <format>
                <includes><include>src/**/*.java</include></includes>
                <trimTrailingWhitespace/>
                <endWithNewline/>
            </format>
        </formats>
    </configuration>
</plugin>
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-checkstyle-plugin</artifactId>
    <version>${maven-checkstyle-plugin.version}</version>
    <configuration>
        <configLocation>config/checkstyle.xml</configLocation>
        <failOnViolation>true</failOnViolation>
    </configuration>
</plugin>
<plugin>
    <groupId>com.github.spotbugs</groupId>
    <artifactId>spotbugs-maven-plugin</artifactId>
    <version>${spotbugs-maven-plugin.version}</version>
    <configuration>
        <effort>Max</effort>
        <threshold>Medium</threshold>
        <failOnError>true</failOnError>
    </configuration>
</plugin>
```

- [ ] **Step 5: 品質ゲート化前のbackend違反数を計測する**

Run in `backend`:

```powershell
.\mvnw.cmd -s local-maven-settings.xml -B spotless:check
.\mvnw.cmd -s local-maven-settings.xml -B checkstyle:check
.\mvnw.cmd -s local-maven-settings.xml -B test-compile spotbugs:check
```

Expected: 各違反数と対象ファイルを既存違反調査へ記録する。20件超または10ファイル超の場合は全ソースを同一変更で修正せず、規則を段階導入する。

- [ ] **Step 6: Wrapperとbackendゲートを検証する**

```powershell
Push-Location backend
.\mvnw.cmd --version
.\mvnw.cmd -s local-maven-settings.xml -B test
.\mvnw.cmd -s local-maven-settings.xml -B spotless:check checkstyle:check test-compile spotbugs:check
Pop-Location
```

Expected: Wrapper 3.3.4がMaven 3.9.16を起動し、Java 21で全コマンドが成功する。

- [ ] **Step 7: Task 3をコミットする**

```powershell
git add backend/mvnw backend/mvnw.cmd backend/.mvn/wrapper/maven-wrapper.properties backend/config/checkstyle.xml backend/pom.xml backend/local-maven-settings.xml 'docs/AI活用開発研究/作業記録/品質ハーネス_既存違反調査.md'
git commit -m "build: add backend quality tooling baseline"
```

---

### Task 4: Shared Quick, Full, and CI task runner

**Files:**

- Create: `scripts/check.ps1`
- Test: Quick対象選択、Full、CI専用タスク、失敗集約

**Interfaces:**

- Consumes: root/frontend npm scripts、backend Wrapper、Gitleaks
- Produces: `check.ps1 -Mode Quick|Full|Oracle|All [-Offline] [-CiTask ...]`

- [ ] **Step 1: 公開パラメータと終了規約を実装する**

先頭を次で固定する。

```powershell
[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet('Quick', 'Full', 'Oracle', 'All')]
    [string]$Mode = 'Quick',
    [switch]$Offline,
    [ValidateSet('None', 'FrontendCoverage', 'BackendCoverage', 'E2E', 'DirectorySecrets', 'DependencyAudit')]
    [string]$CiTask = 'None',
    [switch]$AllowDdl
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$failures = [System.Collections.Generic.List[string]]::new()
```

`Invoke-QualityCheck`は名前、script blockを受け、開始時刻、成功、失敗、所要時間を表示し、例外または非0終了を`$failures`へ追加して後続チェックを継続する。最後に失敗一覧を表示し、失敗なしは`exit 0`、失敗ありは`exit 1`とする。

- [ ] **Step 2: Quickの対象選択を実装する**

対象名は次で取得する。

```powershell
$stagedFiles = @(
    git -C $repoRoot diff --cached --name-only --diff-filter=ACMR
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

$frontendFiles = @($stagedFiles | Where-Object { $_ -match '^frontend/.+\.(ts|tsx)$' })
$markdownFiles = @($stagedFiles | Where-Object { $_ -match '\.md$' })
$hasJavaChanges = @($stagedFiles | Where-Object { $_ -match '^backend/.+\.java$' }).Count -gt 0
```

ESLintとMarkdownlintには上記ファイル名を渡すが、コマンドは作業ツリー上のファイルを読む。Gitleaksは次を実行する。

```powershell
gitleaks git --pre-commit --staged --redact --verbose --config (Join-Path $repoRoot '.gitleaks.toml')
```

基本空白確認は`git -C $repoRoot diff --cached --check`とし、禁止生成物がstagedされていないことも確認する。

- [ ] **Step 3: Fullのコマンドマップを実装する**

順序を次へ固定する。

```text
frontend-lint
frontend-typecheck
frontend-unit-test
frontend-build
backend-test-compile
backend-spotless
backend-checkstyle
backend-spotbugs
```

frontendはWindowsで`npm.cmd`、Linuxで`npm`を選択し、`--prefix frontend run <script>`を渡す。backendはWindowsで`backend/mvnw.cmd`、Linuxで`backend/mvnw`を使う。Maven引数は常に`-s backend/local-maven-settings.xml -B`を含め、`-Offline`時だけ`-o`を加える。

OS別コマンドは次の変数で一度だけ決定する。

```powershell
$npmCommand = if ($IsWindows) { 'npm.cmd' } else { 'npm' }
$mavenCommand = if ($IsWindows) {
    Join-Path $repoRoot 'backend/mvnw.cmd'
}
else {
    Join-Path $repoRoot 'backend/mvnw'
}
```

- [ ] **Step 4: CI専用タスクを単独実行にする**

`CiTask`が`None`以外の場合はMode全体を実行せず、次だけを実行する。

| CiTask | Command |
| --- | --- |
| FrontendCoverage | `npm --prefix frontend run coverage` |
| BackendCoverage | Wrapperで`-Pcoverage test` |
| E2E | `npm --prefix frontend run e2e` |
| DirectorySecrets | `gitleaks dir --redact --config .gitleaks.toml .` |
| DependencyAudit | root/frontendの`npm audit --audit-level=high`と`org.owasp:dependency-check-maven:12.2.2:check` |

- [ ] **Step 5: QuickとFullを検証する**

Run:

```powershell
pwsh -NoProfile -File scripts/check.ps1 -Mode Quick
pwsh -NoProfile -File scripts/check.ps1 -Mode Full
pwsh -NoProfile -File scripts/check.ps1 -Mode Full -CiTask FrontendCoverage
```

Expected: Quickはstaged対象だけ、FullはOracleなしでfrontendの通常テストとbackendの
`test-compile`・静的解析、CI taskは指定チェックだけを実行する。backendの既存テストは
Oracle接続前提のため、実行とcoverageはOracle用ジョブが担当する。いずれも成功時0、
意図的に失敗コマンドを与える試験では最後に失敗名を表示して1を返す。

- [ ] **Step 6: Task 4をコミットする**

```powershell
git add scripts/check.ps1
git commit -m "build: add shared quality check runner"
```

---

### Task 5: Oracle safety guard and Oracle modes

**Files:**

- Modify: `backend/config/oracle-test.example.properties`
- Modify: `backend/scripts/test-oracle.ps1`
- Modify: `backend/scripts/test-oracle.cmd`
- Modify: `backend/src/main/java/com/example/dailyreport/config/DataInitializer.java`
- Create: `backend/src/test/java/com/example/dailyreport/config/OracleSafetyGuardIT.java`
- Modify: `scripts/check.ps1`
- Test: 不正environment、user、host/service、DB識別情報、DDL許可、Oracle integration

**Interfaces:**

- Consumes: `DAILY_REPORT_DB_*`、expected Oracle識別値、Maven Wrapper
- Produces: 安全ガード通過後だけ動くOracle、All、任意DDL処理

- [ ] **Step 1: Oracle設定サンプルへ安全識別値を追加する**

追加キー:

```properties
DAILY_REPORT_DB_ENV=TEST
DAILY_REPORT_DB_EXPECTED_HOST=localhost
DAILY_REPORT_DB_EXPECTED_SERVICE=ORCL
DAILY_REPORT_DB_EXPECTED_NAME=ORCL
DAILY_REPORT_DB_EXPECTED_USER=DAILY_REPORT_TEST
DAILY_REPORT_ALLOW_DDL=false
```

- [ ] **Step 2: PowerShell前段ガードを実装する**

`test-oracle.ps1`へ`[switch]$AllowDdl`と`[string]$DdlScript`を追加する。`oracle-test.properties`が存在する場合はその値をprocess environmentへ読み込み、存在しない場合はself-hosted runnerで設定済みのprocess environmentを使用する。どちらの場合も同じ必須キーと安全条件を接続前に検証する。

```powershell
if ($values.DAILY_REPORT_DB_ENV -cne 'TEST') { throw 'Oracle environment must be TEST.' }
if ($values.DAILY_REPORT_DB_USER -cne $values.DAILY_REPORT_DB_EXPECTED_USER) { throw 'Oracle user does not match the expected test user.' }
if ($values.DAILY_REPORT_DB_USER -match '^(SYS|SYSTEM)$|PROD') { throw 'Administrative or production-like Oracle users are forbidden.' }
```

JDBC URLは`jdbc:oracle:thin:@//<host>:<port>/<service>`として解析し、host/serviceをexpected値と大文字小文字を区別せず完全一致させる。passwordと完全URLは出力しない。

DDLは次の両方がない限り拒否する。

```powershell
if ($DdlScript -and (-not $AllowDdl -or $values.DAILY_REPORT_ALLOW_DDL -cne 'true')) {
    throw 'DDL requires both -AllowDdl and DAILY_REPORT_ALLOW_DDL=true.'
}
```

`DdlScript`は`backend/src/main/resources/db/oracle`配下の実在`.sql`だけ許可する。

- [ ] **Step 3: 接続後DB識別ガードテストを追加する**

`OracleSafetyGuardIT.java`は`@SpringBootTest`、`@ActiveProfiles("oracle-test")`、`JdbcTemplate`を使用し、次を問い合わせる。

```sql
SELECT
  SYS_CONTEXT('USERENV', 'DB_NAME'),
  SYS_CONTEXT('USERENV', 'SERVICE_NAME'),
  SYS_CONTEXT('USERENV', 'SESSION_USER')
FROM dual
```

結果を`DAILY_REPORT_DB_EXPECTED_NAME`、`DAILY_REPORT_DB_EXPECTED_SERVICE`、`DAILY_REPORT_DB_EXPECTED_USER`と完全一致させる。expected値不足時はskipせず失敗させる。

- [ ] **Step 4: OracleとAllをcheck runnerへ接続する**

Oracleは次を実行する。

```text
oracle-safety-guard
oracle-integration-tests
oracle-ddl（DdlScript指定時のみ）
```

AllはFull完了後にOracleを実行し、両方の失敗を最後に集約する。

- [ ] **Step 5: 失敗系を先に検証する**

Run with temporary process environment values:

```powershell
$env:DAILY_REPORT_DB_ENV = 'PROD'
pwsh -NoProfile -File backend/scripts/test-oracle.ps1
```

Expected: DB接続前に失敗し、passwordと完全URLを表示しない。同様に不正user、host、service、単独`-AllowDdl`、単独`DAILY_REPORT_ALLOW_DDL=true`が失敗する。

- [ ] **Step 6: 正常OracleとAllを検証する**

```powershell
pwsh -NoProfile -File scripts/check.ps1 -Mode Oracle
pwsh -NoProfile -File scripts/check.ps1 -Mode All
```

Expected: 自宅テストOracleで安全ガード、接続、全Oracle ITが成功する。DDLは指定しないため実行されない。

- [ ] **Step 7: Task 5をコミットする**

```powershell
git add backend/config/oracle-test.example.properties backend/scripts/test-oracle.ps1 backend/src/test/java/com/example/dailyreport/config/OracleSafetyGuardIT.java scripts/check.ps1
git commit -m "test: guard Oracle integration checks"
```

---

### Task 6: Bootstrap, doctor, and Lefthook

**Files:**

- Create: `scripts/tool-versions.psd1`
- Create: `scripts/bootstrap.ps1`
- Create: `scripts/doctor.ps1`
- Create: `lefthook.yml`
- Test: clean bootstrap、doctor、Lefthook validation、hook calls

**Interfaces:**

- Consumes: 固定版一覧、root/frontend npm projects、Maven Wrapper
- Produces: 非対話セットアップ、環境診断、pre-commit Quick、pre-push Full

- [ ] **Step 1: 固定版の正本を追加する**

`scripts/tool-versions.psd1`:

```powershell
@{
    Java = '21'
    Maven = '3.9.16'
    MavenWrapper = '3.3.4'
    Node = '24.18.0'
    Npm = '11.16.0'
    Lefthook = '2.1.10'
    Gitleaks = '8.30.1'
    Playwright = '1.58.0'
}
```

- [ ] **Step 2: bootstrapを実装する**

公開パラメータ:

```powershell
param(
    [ValidateSet('All', 'Node', 'Maven', 'Playwright', 'Lefthook', 'Gitleaks')]
    [string]$Component = 'All',
    [switch]$Offline
)
```

Allはroot `npm ci`、frontend `npm ci`、`npm --prefix frontend run e2e:install`、Wrapper `dependency:go-offline`、固定版Gitleaks導入、`npm exec lefthook install`、設定サンプル確認を順に実行する。Gitleaksは8.30.1以外が存在する場合に成功扱いにしない。Windowsでは公式release zip、Linuxでは公式release tar.gzを`.tools/gitleaks/8.30.1`へ取得し、公式checksumsファイルのSHA-256と照合する。対話入力は要求しない。

- [ ] **Step 3: doctorを実装する**

次を`PASS`、`WARN`、`FAIL`で表示し、秘密値は出さない。

```text
PowerShell >= 7
Java major = 21
Maven Wrapper = 3.3.4 / Maven core = 3.9.16
Node = 24.18.0 / npm = 11.16.0
Lefthook = 2.1.10
Gitleaks = 8.30.1
Playwright = 1.58.0 and Chromium installed
Oracle client/config/required keys
ports 5173 and 8080 availability
```

Oracle不足は`WARN`、Quick/Full必須ツール不足は`FAIL`とする。

- [ ] **Step 4: Lefthook設定を追加する**

`lefthook.yml`:

```yaml
min_version: 2.1.10
no_tty: true

pre-commit:
  jobs:
    - name: quick-check
      run: pwsh -NoProfile -File scripts/check.ps1 -Mode Quick

pre-push:
  jobs:
    - name: full-check
      run: pwsh -NoProfile -File scripts/check.ps1 -Mode Full
```

- [ ] **Step 5: セットアップとhookを検証する**

```powershell
pwsh -NoProfile -File scripts/bootstrap.ps1 -Component All
pwsh -NoProfile -File scripts/doctor.ps1
npm.cmd run hooks:validate
npm.cmd run hooks:install
npm.cmd exec -- lefthook run pre-commit
npm.cmd exec -- lefthook run pre-push
```

Expected: bootstrapは非対話、doctorはOracle以外PASS、Lefthookは共通スクリプトだけを呼ぶ。

- [ ] **Step 6: Task 6をコミットする**

```powershell
git add scripts/tool-versions.psd1 scripts/bootstrap.ps1 scripts/doctor.ps1 lefthook.yml
git commit -m "build: add environment bootstrap and hooks"
```

---

### Task 7: Split GitHub Actions quality gates

**Files:**

- Create: `.github/workflows/quality.yml`
- Create: `.github/workflows/security.yml`
- Create: `.github/workflows/oracle.yml`
- Create: `.github/CODEOWNERS`
- Test: workflow syntax、SHA pins、permissions、local-equivalent commands

**Interfaces:**

- Consumes: `bootstrap.ps1`、`check.ps1`、GitHub-hosted runner、隔離self-hosted Oracle runner
- Produces: 分割CI status checks、定期security scan、Oracle post-merge/manual gate

- [ ] **Step 1: Action SHAを固定する**

使用するSHA:

```text
actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4
actions/setup-java@c1e323688fd81a25caa38c78aa6df2d33d3e20d9 # v4
actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4
actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830 # v4
```

- [ ] **Step 2: quality workflowを分割する**

`quality.yml`は`pull_request`、`main` push、`workflow_dispatch`を対象にし、top-levelへ次を置く。

```yaml
permissions:
  contents: read
```

jobsを`full-windows`、`full-linux`、`coverage-frontend`、`coverage-backend`、`e2e`、`gitleaks-directory`へ分ける。各jobは必要最小限のbootstrap componentだけを実行し、次のコマンドへ到達させる。

```powershell
pwsh -NoProfile -File scripts/check.ps1 -Mode Full
pwsh -NoProfile -File scripts/check.ps1 -Mode Full -CiTask FrontendCoverage
pwsh -NoProfile -File scripts/check.ps1 -Mode Full -CiTask BackendCoverage
pwsh -NoProfile -File scripts/check.ps1 -Mode Full -CiTask E2E
pwsh -NoProfile -File scripts/check.ps1 -Mode Full -CiTask DirectorySecrets
```

`gitleaks-directory`はcheckout直後、依存取得・build前にGitleaksだけを導入して実行する。

- [ ] **Step 3: security workflowを追加する**

週次cronと`workflow_dispatch`を設定し、`history-gitleaks`と`dependency-audit`を別jobにする。両jobとも`permissions: contents: read`と完全SHA固定Actionを使用する。

- [ ] **Step 4: Oracle workflowを追加する**

triggerは次だけにする。

```yaml
on:
  workflow_dispatch:
  push:
    branches: [main]
```

jobは次を使用する。

```yaml
runs-on: [self-hosted, Windows, X64, projectfoundation-oracle]
permissions:
  contents: read
```

PR eventを設定しない。runnerは個人環境と別の専用VM/端末、非管理者サービスアカウント、専用Oracle test schemaを前提とする。Oracle secretsをコマンドラインへ展開せず、runner側の保護された環境または利用可能な場合はGitHub Environmentからprocess environmentへ渡す。

- [ ] **Step 5: CODEOWNERSを追加する**

`.github/CODEOWNERS`:

```text
/.github/workflows/ @blackowlest-wq
/.github/CODEOWNERS @blackowlest-wq
/scripts/ @blackowlest-wq
/lefthook.yml @blackowlest-wq
/.gitleaks.toml @blackowlest-wq
/backend/pom.xml @blackowlest-wq
```

- [ ] **Step 6: workflowを静的・ローカル同等確認する**

```powershell
rg -n "permissions:|contents: read|uses:" .github/workflows
rg -n "pull_request" .github/workflows/oracle.yml
pwsh -NoProfile -File scripts/check.ps1 -Mode Full
pwsh -NoProfile -File scripts/check.ps1 -Mode Full -CiTask FrontendCoverage
pwsh -NoProfile -File scripts/check.ps1 -Mode Full -CiTask BackendCoverage
pwsh -NoProfile -File scripts/check.ps1 -Mode Full -CiTask E2E
pwsh -NoProfile -File scripts/check.ps1 -Mode Full -CiTask DirectorySecrets
```

Expected: 全workflowにread-only permission、全`uses`に40桁SHA、Oracle workflowにPR triggerなし、各ローカル同等コマンド成功。

- [ ] **Step 7: Task 7をコミットする**

```powershell
git add .github/workflows/quality.yml .github/workflows/security.yml .github/workflows/oracle.yml .github/CODEOWNERS
git commit -m "ci: add split quality and Oracle workflows"
```

---

### Task 8: Documentation, records, and end-to-end verification

**Files:**

- Create: `docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md`
- Create: `docs/AI活用開発研究/作業記録/品質ハーネス構築_2026-07-12.md`
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/標準化資料一覧.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/開発フロー.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/テスト・静的解析チェック表.md`
- Test: 文書リンク、全モード、全CI相当ジョブ、Git状態

**Interfaces:**

- Consumes: 実装済みハーネスと実行結果
- Produces: 重複しない運用正本、branch protection手順、最終証跡

- [ ] **Step 1: 品質ゲート運用の正本を追加する**

次の役割を明記する。

```text
テスト方針.md: 何を、なぜテストするか
テスト・静的解析チェック表.md: どの観点にどのツールを使うか
品質ゲート運用.md: いつ、どのMode/CI jobを使うか
scripts/check.ps1: 実コマンドと終了判定
```

Quickのstaged lintが作業ツリー内容を読むこと、Oracle runner隔離、PRコード非実行、Gitleaks順序、未実行時の再確認条件を記載する。

- [ ] **Step 2: branch protection前提を文書化する**

`main`へ次をGitHub Settingsで設定する手順を記載する。

```text
Require a pull request before merging
Require review from Code Owners
Dismiss stale pull request approvals when new commits are pushed
Require status checks: full-windows, full-linux, coverage-frontend, coverage-backend, e2e, gitleaks-directory
Block force pushes
Block branch deletion
```

CODEOWNERSだけでは強制されないことも明記する。

- [ ] **Step 3: 既存文書の重複コマンドを整理する**

`テスト・静的解析チェック表.md`の`mvn -o`などを削除し、Modeと`品質ゲート運用.md`へリンクする。READMEとAGENTSから品質ゲート運用へ導線を追加し、具体コマンドは重複させない。

- [ ] **Step 4: 全ローカルモードを新鮮な状態で実行する**

```powershell
pwsh -NoProfile -File scripts/doctor.ps1
pwsh -NoProfile -File scripts/check.ps1 -Mode Quick
pwsh -NoProfile -File scripts/check.ps1 -Mode Full
pwsh -NoProfile -File scripts/check.ps1 -Mode Oracle
pwsh -NoProfile -File scripts/check.ps1 -Mode All
```

Expected: Quick、Full、Oracle、Allが成功する。実行時間と各チェック結果を作業記録へ記載する。

- [ ] **Step 5: 各CI job相当を個別実行する**

```powershell
pwsh -NoProfile -File scripts/check.ps1 -Mode Full -CiTask FrontendCoverage
pwsh -NoProfile -File scripts/check.ps1 -Mode Full -CiTask BackendCoverage
pwsh -NoProfile -File scripts/check.ps1 -Mode Full -CiTask E2E
pwsh -NoProfile -File scripts/check.ps1 -Mode Full -CiTask DirectorySecrets
pwsh -NoProfile -File scripts/check.ps1 -Mode Full -CiTask DependencyAudit
```

Expected: 各job相当が独立して成功する。GitHub-hosted Linuxとself-hosted runner上の実ジョブがまだ起動できない場合は、ローカル同等結果、未実行理由、push後の再確認条件を記録する。

- [ ] **Step 6: LefthookとGit差分を確認する**

```powershell
npm.cmd run hooks:validate
npm.cmd exec -- lefthook run pre-commit
npm.cmd exec -- lefthook run pre-push
git diff --check
git status --short
```

Expected: hook経由でもQuick/Fullが成功し、生成物・secret-bearing configが追跡候補にない。

- [ ] **Step 7: 実装後レビューを実施する**

`superpowers:requesting-code-review`と`projectfoundation-review-ja`を使用し、仕様、セキュリティ、CI、Oracle guard、既存違反の扱い、文書重複、未実行テストをレビューする。問題検出時は作業記録だけでなく指摘一覧へ記録する。

- [ ] **Step 8: Task 8をコミットする**

```powershell
git add README.md AGENTS.md 'docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md' 'docs/AI活用開発研究/構想メモ/標準化/標準化資料一覧.md' 'docs/AI活用開発研究/構想メモ/標準化/開発フロー.md' 'docs/AI活用開発研究/構想メモ/標準化/テスト・静的解析チェック表.md' 'docs/AI活用開発研究/作業記録/品質ハーネス構築_2026-07-12.md'
git commit -m "docs: document quality gate operations"
```

- [ ] **Step 9: 最終結果を報告する**

追加・変更ファイル一覧、Quick/Full/Oracle/All、quality/security/oracle各CI job、Lefthook、bootstrap、doctorの結果を、成功・失敗・未実行理由付きで提示する。secret値は提示しない。
