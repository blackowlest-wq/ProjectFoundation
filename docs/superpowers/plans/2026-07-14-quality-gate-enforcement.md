# 品質ゲート構成のmain取り込み Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `main`でコミット・プッシュ時の品質チェックとCI品質ゲートが実際に実行され、設定不足を成功扱いにしない構成へ修正する。

**Architecture:** 品質設定をリポジトリ直下でGit管理し、LefthookからPowerShell共通Runnerを呼び出す。Quickはstaged差分、FullはFrontend/Backend全体、CIはQuality/Security/Oracleに責務分割する。

**Tech Stack:** PowerShell 7、Lefthook 2.1.10、Node 24.18.0、npm 11.16.0、Java 21、Maven 3.9.16、Gitleaks 8.30.1、Vitest、Playwright、GitHub Actions、Oracle。

## Global Constraints

- 業務コードの仕様・API・画面動作を変更しない。
- Oracle接続情報と生成物をGitへ追加しない。
- 品質ゲート設定、ツールバージョン、実行コマンドはGit管理する。
- HookまたはRunnerが設定・ツール不足を検出した場合は非0終了にする。
- 日本語を含む記録はUTF-8で更新する。
- コミットメッセージは日本語で記載する。

---

### Task 1: 品質ツールと静的解析の基盤を取り込む

**Files:**
- Create/Modify: `.editorconfig`, `.gitattributes`, `.gitignore`, `.gitleaks.toml`, `.markdownlint-cli2.jsonc`, `.node-version`
- Create: `package.json`, `package-lock.json`, `frontend/eslint.config.mjs`
- Modify: `frontend/package.json`, `frontend/package-lock.json`
- Create: `backend/config/checkstyle.xml`, `backend/config/spotbugs-exclude.xml`, `backend/.mvn/wrapper/maven-wrapper.properties`, `backend/mvnw`, `backend/mvnw.cmd`
- Modify: `backend/pom.xml`

- [ ] 品質ツールの依存関係とバージョンを固定する。
- [ ] Frontend lint、Markdown lint、Backend Spotless/Checkstyle/SpotBugsが単独で呼び出せるようにする。
- [ ] 生成物、Oracle設定、ログ、ツールキャッシュをGitleaksとGit差分から除外する。

### Task 2: 共通Runner、Bootstrap、Doctor、Hookを取り込む

**Files:**
- Create: `lefthook.yml`
- Create: `scripts/bootstrap.ps1`, `scripts/check.ps1`, `scripts/doctor.ps1`, `scripts/tool-versions.psd1`

- [ ] `scripts/check.ps1 -Mode Quick`がstaged差分の空白、生成物、lint、Spotless、秘密情報を確認する。
- [ ] `scripts/check.ps1 -Mode Full`がFrontendとBackendの品質検査を順番に実行し、全失敗を集約して非0終了する。
- [ ] `scripts/doctor.ps1`がPowerShell、Node/npm、Java、Maven、Lefthook、Gitleaks、Playwrightを確認する。
- [ ] `lefthook.yml`がpre-commitをQuick、pre-pushをFullへ接続する。
- [ ] Lefthook設定または実行ツールがない場合に成功扱いにならないことを確認する。

### Task 3: Oracle安全ガードと共通接続入口を取り込む

**Files:**
- Modify: `backend/scripts/test-oracle.cmd`, `backend/scripts/test-oracle.ps1`
- Create: `backend/config/oracle-test.example.properties`, `backend/src/test/java/com/example/dailyreport/config/OracleSafetyGuardIT.java`
- Modify: `backend/src/main/java/com/example/dailyreport/config/DataInitializer.java`

- [ ] Oracle接続情報をローカル設定または保護された環境変数から読み取る。
- [ ] DDL実行を明示許可なしで拒否する。
- [ ] Oracle安全ガードテストで危険な設定を検出する。

### Task 4: GitHub Actionsと所有者設定を取り込む

**Files:**
- Create: `.github/CODEOWNERS`, `.github/workflows/quality.yml`, `.github/workflows/security.yml`, `.github/workflows/oracle.yml`

- [ ] Pull Requestとmain pushでQuality Workflowを実行する。
- [ ] 週次・手動でSecurity Workflowを実行する。
- [ ] main push・手動でOracle Workflowを実行する。
- [ ] Workflow内のNode/Java/PowerShell/ツールバージョンとローカルRunnerの設定を一致させる。

### Task 5: 標準資料と作業記録を更新する

**Files:**
- Modify: `AGENTS.md`, `README.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/テスト方針.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/テスト・静的解析チェック表.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md`
- Modify: `docs/AI活用開発研究/作業記録/コードコメント運用強化_2026-07-13.md`
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md`

- [ ] 標準実行入口、Quick/Full/CIの役割、Oracle安全条件を記録する。
- [ ] 今回の空振り原因と対応を指摘一覧へ記録する。

### Task 6: 品質ゲートを実行して確認する

- [ ] `pwsh -NoProfile -File scripts/doctor.ps1`を実行し、環境差異を確認する。
- [ ] `pwsh -NoProfile -File scripts/check.ps1 -Mode Quick`を実行する。
- [ ] `pwsh -NoProfile -File scripts/check.ps1 -Mode Full`を実行する。
- [ ] `pwsh -NoProfile -File scripts/check.ps1 -CiTask E2E`を実行する。
- [ ] `pwsh -NoProfile -File scripts/check.ps1 -CiTask BackendCoverage`をOracle共通入口で実行する。
- [ ] `git diff --check`、テスト配置チェック、Hook設定確認を実行する。
- [ ] 失敗があれば原因を修正し、結果を作業記録へ記載する。
