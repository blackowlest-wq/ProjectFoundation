# 影響範囲ベーステスト実行への移行 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 通常の品質確認を変更影響範囲へ限定し、夜間・リリース前に全体テストと全体カバレッジを実行する運用を、標準資料と品質重視モードSkillへ反映する。

**Architecture:** 品質ゲート運用資料を実行層とスケジュールの正本、テスト方針資料を影響範囲・カバレッジ・テスト分割の正本、ProjectFoundation Review Skillを実務手順の正本として役割分担する。共通部品・高リスク・影響範囲不明の変更は全体実行へフォールバックし、未実行や除外を成功扱いにしない。

**Tech Stack:** Markdown、PowerShell契約テスト、ProjectFoundation `.agents` Skill同期、Git hooks。

## Global Constraints

- 変更対象は、品質ゲート運用資料、テスト方針資料、ProjectFoundation Review Skillの編集元・同期先、および移行記録に限定する。
- 全体テスト・全体カバレッジを廃止せず、夜間またはリリース前の実行として維持する。
- 影響範囲を判定できない変更、密結合で分離できない変更、高リスク変更は全体実行へフォールバックする。
- 未実行、除外、影響範囲不明、カバレッジ未取得を成功扱いにしない。
- Skillの編集元は`docs/AI活用開発研究/構想メモ/標準化/skills/`、配置先は`.agents/skills/`とする。
- 日本語資料はUTF-8で編集し、Markdown lint、既存契約テスト、差分確認を実行する。

## File Map

- Modify: `docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md` — 実行層、main push、夜間、リリース前、影響範囲フォールバックの正本。
- Modify: `docs/AI活用開発研究/構想メモ/標準化/テスト方針.md` — テスト選択、カバレッジ、テスト分割、共通依存の方針。
- Modify: `docs/AI活用開発研究/構想メモ/標準化/skills/projectfoundation-review-ja/SKILL.md` — 品質重視モードのレビュー・最終ゲート手順。
- Modify: `.agents/skills/projectfoundation-review-ja/SKILL.md` — 実行時に検出される同期済みSkill。
- Test: `scripts/pre-push.tests.ps1`、`scripts/simple-mode.tests.ps1`、`scripts/coverage-gate.tests.ps1`、`npm run lint:markdown` — 既存の品質ゲート契約とMarkdown契約で影響を確認する。

---

### Task 1: 品質ゲート運用資料を影響範囲ベースへ更新

**Files:**
- Modify: `docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md`
- Test: `scripts/pre-push.tests.ps1`、`scripts/simple-mode.tests.ps1`、`scripts/coverage-gate.tests.ps1`

**Interfaces:**
- Consumes: `docs/superpowers/specs/2026-08-02-impact-based-test-execution-design.md`
- Produces: 通常実行、夜間全体実行、リリース前全体実行、影響範囲不明時のフォールバックを定義する運用規約

- [ ] **Step 1: 実行層の現状記述を確認する**

  `Local Mode`、`実行層の責務と重複禁止`、`PrePushの対象選択`、`CI jobとmain運用`を読み、現行の「main push後に全体実行」記述と、Simple/PrePushの差分実行記述を一覧化する。

- [ ] **Step 2: 影響範囲ベースの実行層を追記する**

  開発中、通常CI、main push後、夜間、リリース前の範囲と目的を表へ反映する。main push後は影響範囲を基本とし、夜間・リリース前は全体実行と明記する。

- [ ] **Step 3: 影響範囲とフォールバック条件を追記する**

  局所変更、共通部品・認証・DB・業務ルール変更、workflow・runner・依存関係変更の扱いを記載し、密結合・影響範囲不明・高リスク変更は全体実行へフォールバックする契約を明記する。

- [ ] **Step 4: 夜間・リリース前の全体実行責務を明記する**

  全テスト、全カバレッジ、全E2E、必要なOracleを実行すること、未実行や失敗を成功扱いにしないこと、CIスケジュールまたはリリース判定で記録することを記載する。

- [ ] **Step 5: 既存契約との矛盾を確認する**

  `rg`で`main push`、`全体`、`影響範囲`、`夜間`、`リリース前`、`coverage`を検索し、SimpleのFocused Unit、PrePushの軽量検査、全体ゲートの役割が矛盾していないことを確認する。

- [ ] **Step 6: 資料単位の検証を実行する**

  Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\pre-push.tests.ps1`、`pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\simple-mode.tests.ps1`、`pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\coverage-gate.tests.ps1`

  Expected: 既存の実行層・workflow・Simple契約が成功し、新方針と矛盾する契約がない。

### Task 2: テスト方針資料を影響範囲・カバレッジ基準へ更新

**Files:**
- Modify: `docs/AI活用開発研究/構想メモ/標準化/テスト方針.md`
- Test: Markdown lint、`scripts/coverage-gate.tests.ps1`、既存テスト配置・品質ゲート契約

**Interfaces:**
- Consumes: Task 1の実行層定義、影響範囲ベース設計書
- Produces: 変更種別から実行対象を選択するテスト方針と、通常／全体カバレッジの判定基準

- [ ] **Step 1: テスト分類とユースケース分割の既存記述を確認する**

  `テスト配置とユースケース分割`、`品質ゲート`、`テスト追加の判断`を確認し、変更機能と直接依存先を通常実行対象にできる記述位置を決める。

- [ ] **Step 2: 変更種別ごとの実行選択表を追加する**

  画面/API局所、共通部品、認証・CSRF、業務ルール、DB/SQL、workflow・テスト基盤の変更ごとに、対象Unit/API/E2E/Oracle、影響範囲、全体実行へのフォールバック条件を記載する。

- [ ] **Step 3: カバレッジの二層基準を追加する**

  通常実行では変更行・変更モジュール・影響範囲と分岐未充足を確認し、夜間・リリース前は全体カバレッジを再生成することを記載する。全体カバレッジだけで変更機能の十分性を代替しないことも明記する。

- [ ] **Step 4: 密結合と影響範囲不明を品質上のフォールバックとして記録する**

  分離不能な共通依存は全体実行の理由として扱い、長期改善候補として責務分割、依存グラフ、fixture分離、契約テストを記録する方針を追加する。

- [ ] **Step 5: テスト構成レビューとの関係を確認する**

  Full成功やカバレッジ成功だけではテスト責務分割レビューを代替しない既存記述を維持し、影響範囲の選択根拠をテスト構成・責務対応表へ記録できるようにする。

- [ ] **Step 6: coverageとテスト方針の契約を検証する**

  Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\coverage-gate.tests.ps1`

  Expected: 85%閾値、Frontend/Backendのcoverage artifact、未生成時の失敗扱いなど既存契約が成功する。

### Task 3: 品質重視モードSkillを更新して同期する

**Files:**
- Modify: `docs/AI活用開発研究/構想メモ/標準化/skills/projectfoundation-review-ja/SKILL.md`
- Modify: `.agents/skills/projectfoundation-review-ja/SKILL.md`
- Test: `scripts/skill*.tests.ps1`、Skill内容の編集元・同期先比較

**Interfaces:**
- Consumes: Task 1・Task 2の標準資料、影響範囲ベース設計書
- Produces: 品質重視モードで影響範囲を判定・記録し、必要時だけ全体実行へフォールバックする手順

- [ ] **Step 1: Skill内のFull・最終品質ゲート記述を確認する**

  Hard Gate、実装後の確認契約、手順、完了条件、簡易修正モードを検索し、全体実行を常時前提としている文面を特定する。

- [ ] **Step 2: 品質重視モードの影響範囲判定手順を追加する**

  変更ファイルから変更機能、直接・推移的依存、共通部品、認証・DB・workflow影響を判定し、選択範囲・除外範囲・根拠・フォールバックをレビュー記録へ残す手順を追加する。

- [ ] **Step 3: 通常ゲートと全体ゲートの完了条件を分離する**

  通常は影響範囲の対象テストと静的解析を完了条件とし、夜間・リリース前は全体テスト、全体カバレッジ、全E2E、必要なOracleを完了条件とする。未実行を成功扱いにしない既存契約を維持する。

- [ ] **Step 4: カバレッジ確認を二層化する**

  変更行・変更モジュール・影響範囲のカバレッジ確認と、夜間・リリース前の全体カバレッジ確認を分け、抽出不能時の全体フォールバックを記載する。

- [ ] **Step 5: 編集元を配置先へ同期する**

  UTF-8で編集元を確認した後、編集元の内容を`.agents/skills/projectfoundation-review-ja/SKILL.md`へ同期し、`Get-FileHash`で一致を確認する。

- [ ] **Step 6: Skill契約を検証する**

  Run: `rg -n '影響範囲|夜間|リリース前|フォールバック|全体カバレッジ|未実行' docs/AI活用開発研究/構想メモ/標準化/skills/projectfoundation-review-ja/SKILL.md .agents/skills/projectfoundation-review-ja/SKILL.md`

  Expected: 編集元と配置先に同じ運用条件があり、常時全実行を要求する矛盾した文面が残っていない。

### Task 4: 統合検証と作業記録

**Files:**
- Test: `git diff --check`、Markdown lint、関連PowerShell契約、編集元・同期先ハッシュ比較
- Modify: `docs/AI活用開発研究/作業記録/コード品質確認画面_検証記録.md` — Skill編集元・配置先の同期、方針変更、検証結果、未実装のCI自動化範囲を記録する。

**Interfaces:**
- Consumes: Task 1～3の資料とSkill
- Produces: 検証結果、未実行事項、影響範囲運用への移行記録

- [ ] **Step 1: 変更ファイルと差分整合性を確認する**

  Run: `git status --short`、`git diff --check`、`git diff --stat`

  Expected: 意図した標準資料、Skill、作業記録だけが変更される。

- [ ] **Step 2: MarkdownとPowerShellの検証を実行する**

  Run: リポジトリ既存のMarkdown lint、品質ゲート契約、coverage契約、Skill契約テスト。

  Expected: 変更対象の契約が成功し、未実行のCI全体テストは未実行として記録する。

- [ ] **Step 3: 編集元と配置先のSkillを比較する**

  Run: `Get-FileHash`で両Skillを比較する。

  Expected: SHA256が一致する。

- [ ] **Step 4: 残る制約を記録する**

  影響範囲の自動判定runner、変更行カバレッジ、夜間workflowの実装が今回の文書変更だけでは導入されない場合、その未実装範囲と導入条件を作業記録へ明記する。

- [ ] **Step 5: 変更をコミットする**

  ```powershell
  git add docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md docs/AI活用開発研究/構想メモ/標準化/テスト方針.md docs/AI活用開発研究/構想メモ/標準化/skills/projectfoundation-review-ja/SKILL.md .agents/skills/projectfoundation-review-ja/SKILL.md
  git commit -m "docs: define impact-based quality gates"
  ```
