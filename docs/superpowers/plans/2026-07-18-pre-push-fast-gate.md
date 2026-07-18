# Pre-push軽量品質ゲート Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** pre-pushをFull検査から送信commit差分の軽量静的検査へ変更し、PR/mainのFull品質ゲートを維持したままローカルpush待ちを短縮する。

**Architecture:** `scripts/check.ps1`にPrePush Modeを追加し、pre-push stdinのref情報から送信対象ファイルを解決する。差分に応じたgit diff、artifact、Gitleaks、Frontend ESLint、Markdownlint、Backend Spotlessだけを実行し、unit/typecheck/build/SpotBugsはGitHub Actionsへ残す。

**Tech Stack:** PowerShell 7、Lefthook 2.1.10、Git、npm/ESLint/Markdownlint、Maven Wrapper/Spotless、Gitleaks。

## Global Constraints

- `pre-commit`のQuick、PR/mainのFull、required status checkは変更しない。
- Oracle、coverage、E2E、Dependency AuditはPrePushの対象外とする。
- Git管理外の資格情報、coverage、生成物をソースやログへ出力しない。
- Frontendは`frontend` npm project、Backendは`backend/pom.xml` aggregatorを入口にする。
- 日本語文書はUTF-8で編集し、作業記録と指摘一覧を更新する。

---

### Task 1: 送信refとPrePush検査選択の契約テスト

**Files:**

- Create: `scripts/pre-push.tests.ps1`
- Modify: `scripts/check.ps1`（テストから呼ぶ関数の契約だけを先に定義）

**Interfaces:**

- `Get-PushRefRecords -InputText <string>`は、pre-push stdinをref recordへ変換する。
- `Get-PrePushChangedFiles -RepoRoot <string> -PushRefs <object[]>`は、送信commit差分の相対パス一覧を返す。
- `Get-PrePushCheckDefinitions -RepoRoot <string> -ChangedFiles <string[]> ...`は、差分に応じた検査definitionを返す。

- [x] **Step 1: 失敗する契約テストを書く**

  通常push、新規ref、削除ref、不正行、Frontend/Markdown/Backend混在を検証する。さらにPrePushのdefinition名に`frontend-unit-test`、`frontend-typecheck`、`frontend-build`、`backend-test-compile`、`backend-checkstyle`、`backend-spotbugs`が含まれないことを検証する。

- [x] **Step 2: テストが機能不足で失敗することを確認する**

  `pwsh -NoProfile -File scripts/pre-push.tests.ps1`を実行し、未定義関数または期待definition不足で失敗することを確認する。

### Task 2: PrePushのref解析と差分解決

**Files:**

- Modify: `scripts/check.ps1`

**Interfaces:**

- Script parameterのModeへ`PrePush`を追加する。
- `Get-PushRefRecords`は4列以外の非空行を拒否し、40桁shaまたはGitのzero shaだけを受け入れる。
- 既存remote shaがある場合はremote/local間の`git diff --name-only --diff-filter=ACMR`を使う。
- 新規refではremoteに存在しないlocal commitのdiff-treeを集約する。

- [x] **Step 1: 最小実装でref recordとchanged-filesを追加する**

  zero shaの削除refは空一覧にし、複数refは重複を除いて相対パスを返す。Gitコマンド失敗時は例外にしてpushを止める。

- [x] **Step 2: 契約テストを再実行する**

  `pwsh -NoProfile -File scripts/pre-push.tests.ps1`を実行し、全ケースが成功することを確認する。

### Task 3: 差分対象の軽量検査を追加する

**Files:**

- Modify: `scripts/check.ps1`
- Modify: `lefthook.yml`

**Interfaces:**

- PrePushは常に空白、生成物禁止、Gitleaks directory scanを実行する。
- TypeScript変更時は変更ファイルESLint、設定変更時はFrontend lint全体を実行する。
- Markdown変更時は変更ファイルMarkdownlintを実行する。
- Java変更時はMaven aggregator Spotlessを実行する。

- [x] **Step 1: 契約テストが指定するdefinitionを満たす最小実装を追加する**

  既存の`New-CheckDefinition`と`Invoke-QualityChecks`を再利用し、Full definitionを呼び出さない。

- [x] **Step 2: `Invoke-QualityRunner`へPrePush分岐を追加する**

  `-Mode PrePush`ではscript parameterの`PushInput`が指定されていればそれを使い、通常hook実行ではstdinをEOFまで読む。失敗一覧を既存形式で出力する。

- [x] **Step 3: LefthookをPrePush入口へ変更する**

  `pre-push`のrunを`pwsh -NoProfile -File scripts/check.ps1 -Mode PrePush`へ変更し、pre-push stdinをrunnerへ渡す設定を追加する。

- [x] **Step 4: 契約テストと手動のPrePush dry runを実行する**

  `pwsh -NoProfile -File scripts/pre-push.tests.ps1`と、代表stdinを`-PushInput`で渡したPrePush dry runを実行する。Full固有のunit/typecheck/build/SpotBugsが実行されないことをログで確認する。

### Task 4: 標準資料と作業記録を更新する

**Files:**

- Modify: `docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md`
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md`
- Modify: `docs/AI活用開発研究/作業記録/カバレッジ閾値強化_2026-07-17.md`

- [x] **Step 1: Local Modeとhook責務を更新する**

  Quickはpre-commit、PrePushは差分静的検査、FullはPR/main CIという責務分担と、PrePushで未実行の検査を明記する。

- [x] **Step 2: 指摘一覧と作業記録へ判断理由を記録する**

  Fullをpre-pushから外すことで、push前のunit/build検出は失われるが、required CIによりmerge品質は維持されること、pre-push stdinを使う理由、再確認条件を記録する。

### Task 5: 検証と品質ゲート確認

**Files:**

- No additional source files.

- [ ] **Step 1: PrePushとQuickを実行する**

  `pwsh -NoProfile -File scripts/pre-push.tests.ps1`、`pwsh -NoProfile -File scripts/check.ps1 -Mode Quick`を実行する。

- [ ] **Step 2: Fullと既存契約テストを実行する**

  `pwsh -NoProfile -File scripts/check.ps1 -Mode Full`、`pwsh -NoProfile -File scripts/oracle-preflight.tests.ps1`、`pwsh -NoProfile -File scripts/coverage-summary.tests.ps1`、`pwsh -NoProfile -File scripts/coverage-gate.tests.ps1`を実行する。

- [x] **Step 3: 文書 lintと差分検査を実行する**

  対象Markdownへ`npm.cmd run lint:markdown -- --no-globs ...`を実行し、`git diff --check`を実行する。

- [ ] **Step 4: 変更をcommitする**

  pre-commit Quickが成功した後、`git add`と`git commit`を実行する。
