# Quality Process Compression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 品質レビューとRequired CIを維持したまま、レビュー記録・実行層・PR境界の重複作業を全機能向け標準として圧縮する。

**Architecture:** 専門レビュー資料は観点ごとの根拠として残し、機能単位の統合品質記録をAC・TC・RT・指摘・ゲート結果の正本にする。レビューはBackend/DB/Security、Frontend/UI、Integration/Finalの3チェックポイントで実施し、Quick、PrePush、PR Required CI、main後Oracleの責務を重複させない。

**Tech Stack:** Markdown標準資料、PowerShell quality runner、GitHub Actions、既存のP0/P1/P2レビュー運用。

## Global Constraints

- P0/P1レビューと、変更リスクに応じたP2レビューを削除・任意化しない。
- Required CI 6 checkとカバレッジ閾値を変更しない。
- 統合品質記録はレビュー詳細を隠すためではなく、重複転記をなくすために使用する。
- Oracle実行をPR Required CIへ追加しない。
- 機能PR、ハーネス・CI PR、標準資料PRを原則として分離する。
- 既存資料の過去記録を一括変換せず、新規機能と次回更新から適用する。

---

## File Map

- Create: docs/AI活用開発研究/構想メモ/標準化/統合品質記録様式.md — AC・TC・RT・FIND・レビュー・ゲート結果の正本様式。
- Modify: docs/AI活用開発研究/構想メモ/標準化/標準化資料一覧.md — 新様式を標準資料として登録する。
- Modify: docs/AI活用開発研究/構想メモ/標準化/開発フロー.md — 3チェックポイントとPR境界を追加する。
- Modify: docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md — 実行層と重複実行禁止のルールを整理する。
- Modify: docs/AI活用開発研究/構想メモ/標準化/実装前チェック表.md — 正本記録とレビュー計画を追加する。
- Modify: docs/AI活用開発研究/構想メモ/標準化/実装後レビュー表.md — 3チェックポイントの統合判定を追加する。
- Modify: docs/AI活用開発研究/作業記録/日報承認差戻し_作業記録.md — 今回をパイロットとして分類する。

## Task 1: 統合品質記録の正本様式を作成する

**Files:** Create統合品質記録様式.md、Modify標準化資料一覧.md

- [ ] Step 1: 正本様式の必須項目を確認する

    必須: 対象範囲、対象外、完了条件、AC/TC/RT/FIND対応表、レビュー結果、ゲート結果、未実行条件、標準化判定。
    禁止: 専門レビュー資料の削除、同じ実行結果の重複転記、未実行の成功扱い、秘密値の記録。

- [ ] Step 2: 統合品質記録様式.mdを作成する

次の見出しを固定する。

    # 統合品質記録
    ## 1. 対象範囲・対象外
    ## 2. 完了条件
    ## 3. AC・TC・RT・FIND対応表
    ## 4. レビュー計画と判定
    ## 5. 品質ゲート実行結果
    ## 6. 未実行・保留・再確認条件
    ## 7. 指摘の標準化判定
    ## 8. 証跡リンク

- [ ] Step 3: 標準化資料一覧へ登録する

様式の役割を「専門レビュー詳細を置き換えず、統合担当が正本結果を集約する資料」として登録する。

- [ ] Step 4: Markdown lintを実行する

    npm.cmd run lint:markdown -- --no-globs 'docs/AI活用開発研究/構想メモ/標準化/統合品質記録様式.md' 'docs/AI活用開発研究/構想メモ/標準化/標準化資料一覧.md'

Expected: Markdown lintが成功する。

- [ ] Step 5: Commit

    git add docs/AI活用開発研究/構想メモ/標準化/統合品質記録様式.md docs/AI活用開発研究/構想メモ/標準化/標準化資料一覧.md
    git commit -m "docs: add canonical integrated quality record"

## Task 2: 開発フローと実装前チェックへ3チェックポイントを反映する

**Files:** Modify開発フロー.md、Modify実装前チェック表.md

- [ ] Step 1: 現行の必須レビュー項目を抽出する

    rg -n 'P0|P1|P2|レビュー|統合|品質ゲート|トレーサビリティ' docs/AI活用開発研究/構想メモ/標準化/開発フロー.md docs/AI活用開発研究/構想メモ/標準化/実装前チェック表.md

Expected: 現行項目を削除せず、3チェックポイントのどこで実施するか対応付けられる。

- [ ] Step 2: 3チェックポイントの配置ルールを追加する

  レビューの集約単位: 機能追加・大きめの修正は、Backend/DB/Security、Frontend/UI、Integration/Finalの3チェックポイントで確認する。各チェックポイント内では対象Taskをまとめるが、P0/P1レビュー観点と独立判定は省略しない。

- [ ] Step 3: 正本記録と重複転記の禁止をHard Gateへ追加する

  - 統合品質記録を正本とし、詳細レビュー資料は根拠と指摘だけを保持する。
  - 同じコマンド結果、CI URL、未実行理由を複数資料へ転記しない。
  - レビューを省略するのではなく、チェックポイントへ集約した結果を記録する。

- [ ] Step 4: Markdown lintを実行する

    npm.cmd run lint:markdown -- --no-globs 'docs/AI活用開発研究/構想メモ/標準化/開発フロー.md' 'docs/AI活用開発研究/構想メモ/標準化/実装前チェック表.md'

Expected: Markdown lintが成功する。

- [ ] Step 5: Commit

    git add docs/AI活用開発研究/構想メモ/標準化/開発フロー.md docs/AI活用開発研究/構想メモ/標準化/実装前チェック表.md
    git commit -m "docs: consolidate preflight review checkpoints"

## Task 3: 品質ゲート運用と実装後統合判定を整理する

**Files:** Modify品質ゲート運用.md、Modify実装後レビュー表.md

- [ ] Step 1: 実行層の重複を照合する

    rg -n 'Quick|PrePush|Full|Oracle|Required|重複|coverage|E2E|Gitleaks' docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md docs/AI活用開発研究/構想メモ/標準化/実装後レビュー表.md

Expected: Quick/PrePush/PR Required CI/main後Oracleの責務がそれぞれ一度ずつ定義される。

- [ ] Step 2: 実行責務表を品質ゲート運用へ追加する

    | 層 | 完了判定 | 同じ層で再実行する条件 |
    | --- | --- | --- |
    | Quick | staged差分の軽量検査 | staged対象が変わった場合のみ |
    | PrePush | push差分の軽量検査 | push対象commitが変わった場合のみ |
    | PR Required CI | 6 checkの最終判定 | CI失敗の原因修正後のみ |
    | main後Oracle | 実DB・実Backendのリリース確認 | Oracle環境またはコードが変わった場合 |

- [ ] Step 3: 実装後レビュー表に統合判定を追加する

  - レビュー観点が実施されたか。
  - Required CI 6 checkの結果が揃っているか。
  - Oracle、fresh schema、real Backend E2Eの未実行が明記されているか。
  - 残存リスクと再確認条件が統合品質記録へ集約されているか。

- [ ] Step 4: Markdown lintを実行する

    npm.cmd run lint:markdown -- --no-globs 'docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md' 'docs/AI活用開発研究/構想メモ/標準化/実装後レビュー表.md'

Expected: Markdown lintが成功する。

- [ ] Step 5: Commit

    git add docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md docs/AI活用開発研究/構想メモ/標準化/実装後レビュー表.md
    git commit -m "docs: clarify quality gate execution layers"

## Task 4: 日報承認・差戻しをパイロットとして記録する

**Files:** Modify docs/AI活用開発研究/作業記録/日報承認差戻し_作業記録.md

- [ ] Step 1: 既存記録の重複箇所を確認する

    rg -n 'AC-|TC-|RT-|FIND-|Full|E2E|coverage|Oracle|標準化|保留' docs/AI活用開発研究/作業記録/日報承認差戻し_作業記録.md docs/AI活用開発研究/作業記録/日報承認差戻し_実装後レビュー.md

Expected: 過去記録を削除せず、今後の正本記録へ移す候補だけを列挙する。

- [ ] Step 2: パイロット判定を追記する

    品質レビュー観点: 既存観点で対応。承認・差戻しでP0/P1レビューが有効だった。
    AC/TC/RTの重複転記: 標準化候補。統合品質記録へ集約できる。
    BackendCoverage失敗分類: 標準化候補。テスト成功と成果物欠落を分ける必要がある。
    Oracle未実行の記録: 標準化候補。リリース未完了を明示する必要がある。
    承認・差戻しの更新競合: 保留。本計画の対象外で、機能仕様の確認が別途必要。

- [ ] Step 3: Markdown lintを実行する

    npm.cmd run lint:markdown -- --no-globs 'docs/AI活用開発研究/作業記録/日報承認差戻し_作業記録.md'

Expected: Markdown lintが成功する。

- [ ] Step 4: Commit

    git add docs/AI活用開発研究/作業記録/日報承認差戻し_作業記録.md
    git commit -m "docs: record process compression pilot"

## Task 5: 標準資料の最終確認を行う

**Files:** 標準化資料全体、パイロット作業記録

- [ ] Step 1: 必須レビューとRequired CIが残っていることを確認する

    rg -n 'P0|P1|P2|Full / Windows|Full / Linux|Backend / Unit|Coverage / Frontend|E2E|Gitleaks / Directory' docs/AI活用開発研究/構想メモ/標準化

Expected: P0/P1/P2とRequired CI 6 checkの記述が残っている。

- [ ] Step 2: 重複転記禁止と3チェックポイントを確認する

    rg -n '3チェックポイント|Backend/DB/Security|Frontend/UI|Integration/Final|正本|重複|転記|Quick|PrePush|main後Oracle' docs/AI活用開発研究/構想メモ/標準化

Expected: 新しい運用ルールが標準資料内で参照可能になっている。

- [ ] Step 3: 全文Markdown lintを実行する

    npm.cmd run lint:markdown

Expected: 対象Markdownがすべて成功する。

- [ ] Step 4: 差分と生成物を確認する

    git diff --check
    git status --short

Expected: 生成物・secret・Oracle実設定が含まれず、標準資料と作業記録だけが変更対象になる。

- [ ] Step 5: Commit

    git add docs/AI活用開発研究/構想メモ/標準化 docs/AI活用開発研究/作業記録/日報承認差戻し_作業記録.md
    git commit -m "docs: standardize quality process compression"
