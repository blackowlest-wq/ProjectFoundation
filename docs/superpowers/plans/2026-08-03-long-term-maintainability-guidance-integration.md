# Long-Term Maintainability Guidance Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 既存の開発フロー・実装前チェック・実装後レビューへ長期保守可能性の判断を組み込み、重要な設計判断をADRで追跡できるようにする。

**Architecture:** 上位方針は既存の構想メモに置き、重要な設計判断はADRを正本とする。`開発フロー.md`は適用順序、`実装前チェック表.md`は適用判断、`実装後レビュー表.md`は実装と根拠の整合性を担う。テスト方針、テストケースレビュー観点、品質ゲート運用は初回変更では改訂しない。

**Tech Stack:** UTF-8 Markdown、PowerShell、Markdownlint、既存のGit pre-commit hook、Git。

## Global Constraints

- 正しさ、安全性、セキュリティ、法令・契約要件は絶対条件として扱い、長期保守性を理由に緩和しない。
- 長期保守性は、絶対条件、全変更の必須核、変更リスクに応じた適用観点の3層で扱う。
- 全変更の必須核は、変更影響、変更結果の検証、重要な判断・前提の追跡とする。
- AI対話全文と生成コードの行単位の採用範囲は保存しない。重要な判断だけをADRまたは作業記録へ残す。
- ADRは重要な設計判断だけに要求し、局所的で影響範囲が小さい判断には要求しない。
- 初回変更では既存のテスト方針、テストケースレビュー観点、テスト・静的解析チェック表、品質ゲート運用、統合品質記録様式を改訂しない。
- 初回変更では既存の確認項目を削除しない。削減・統合・優先度変更は、複数機能での試行結果を得た後に行う。
- 新しいCI job、品質ゲート段階、runnerを追加しない。
- ドキュメントは既存の正本へ追記し、同じ実行結果や判断を複数資料へ重複転記しない。
- 作業は現在の`main`上で行い、新しいブランチは作成しない。

---

### Task 1: ADRテンプレートと上位資料の導線を追加する

**Files:**
- Create: `docs/AI活用開発研究/設計判断記録/ADRテンプレート.md`
- Modify: `docs/AI活用開発研究/構想メモ/長期保守可能性を重視した品質方針.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/標準化資料一覧.md`

**Interfaces:**
- Consumes: 承認済み設計記録のADR適用条件、最小項目、既存資料との役割分担。
- Produces: 重要な設計判断を1判断1ファイルで記録するためのテンプレートと、構想メモ・標準化資料一覧からの導線。

- [ ] **Step 1: 既存の長期保守方針と資料一覧のリンク構造を確認する**

  `Get-Content -Raw -Encoding UTF8`で対象2ファイルを読み、既存の「既存標準化資料との関係」および「最初に確認する資料」へ追記する位置を確定する。テスト方針、品質ゲート運用、統合品質記録をADRの正本として誤って扱わない。

- [ ] **Step 2: ADRテンプレートを追加する**

  `docs/AI活用開発研究/設計判断記録/ADRテンプレート.md`へ、次の項目と適用説明を記載する。

  ```text
  ID:
  タイトル:
  日付:
  状態: Proposed / Accepted / Superseded / Rejected
  背景・問題:
  決定:
  検討した代替案と不採用理由:
  前提・制約:
  影響・リスク:
  安全性を確認したテスト・レビュー:
  影響する機能・ファイル・外部境界:
  関連資料:
  ```

  重要な設計判断の対象を「複数機能の構造・共通部品」「API・DB・外部契約」「認証認可・セキュリティ・ログ・復旧の制約」「将来の変更を強く制約する方式」「代替案から選択した判断」に限定し、局所変更には要求しないことを明記する。判断変更時は既存ADRを直接書き換えず、新しいADRで置換関係を示す。

- [ ] **Step 3: 構想メモへADRの役割を追記する**

  `長期保守可能性を重視した品質方針.md`の既存資料との関係へ、ADRが重要な設計判断の正本であること、作業記録と統合品質記録は実施結果とリンクを担うこと、AI対話全文や生成範囲を保存しないことを追記する。

- [ ] **Step 4: 標準化資料一覧へADRテンプレートを追加する**

  `標準化資料一覧.md`へ、`../../設計判断記録/ADRテンプレート.md`と保存先の用途を追加する。既存の標準化資料の役割を上書きする説明は追加しない。

- [ ] **Step 5: Markdownと参照先を確認する**

  Run: `npx --no-install markdownlint-cli2 --no-globs docs/AI活用開発研究/設計判断記録/ADRテンプレート.md docs/AI活用開発研究/構想メモ/長期保守可能性を重視した品質方針.md docs/AI活用開発研究/構想メモ/標準化/標準化資料一覧.md`

  Expected: 3ファイルのMarkdownlintが0エラーで終了し、相対リンク先のファイルが存在する。

- [ ] **Step 6: Commit the ADR foundation**

  ```powershell
  git add 'docs/AI活用開発研究/設計判断記録/ADRテンプレート.md' 'docs/AI活用開発研究/構想メモ/長期保守可能性を重視した品質方針.md' 'docs/AI活用開発研究/構想メモ/標準化/標準化資料一覧.md'
  git commit -m "docs: add ADR foundation for maintainability decisions"
  ```

### Task 2: 開発フローと実装前チェックへ3層の適用判断を組み込む

**Files:**
- Modify: `docs/AI活用開発研究/構想メモ/標準化/開発フロー.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/実装前チェック表.md`

**Interfaces:**
- Consumes: Task 1のADRテンプレートと、長期保守性の絶対条件・必須核・リスク適用の定義。
- Produces: 実装前にADR要否、変更影響、検証方法、適用観点、対象外理由を判断できる標準手順。

- [ ] **Step 1: `開発フロー.md`の既存Plan・Design Check・Record位置を確認する**

  `rg -n '^##|^###|Plan|Design Check|Record|AI利用|Why not|P0|P1|P2'`で対象節を確認する。既存のテスト方針・品質ゲート運用への委譲関係と、Simple Modeの専用資料を増やさない契約を維持する。

- [ ] **Step 2: 開発フローへ3層の適用原則を追加する**

  `開発フロー.md`の基本原則または標準フローへ、絶対条件、全変更の必須核、リスク適用観点の順に適用する原則を追加する。全項目を無条件に追加しないこと、重要な設計判断はADRを参照・作成すること、テスト方針と品質ゲート運用は各正本へ委譲することを記載する。

- [ ] **Step 3: Plan / Design CheckへADR要否と必須核を追加する**

  Planの実装前アウトプットへ次を追加する。

  ```text
  長期保守性の必須核:
  変更影響の確認方法:
  変更結果の検証方法:
  ADR: 既存参照 / 新規作成 / 対象外理由:
  リスク適用観点:
  自動検査へ委譲する観点:
  ```

  Design Checkでは、ADRの決定・前提・制約、変更影響、検証方法を確認し、障害調査・復旧・ログなどは変更リスクがある場合だけ適用する。対象外理由を記録するが、既存のテストケースや品質ゲートの結果を再掲しない。

- [ ] **Step 4: 実装前チェック表へ既存項目として統合する**

  新しい大量のチェック行は追加せず、既存の設計書、受入条件、トレーサビリティ、テスト、専門レビュー、記録の行または実装前アウトプットへ、ADR要否、変更影響、検証根拠、リスク観点の適用範囲を組み込む。局所的な変更へADRを強制しない。

- [ ] **Step 5: 既存のSimple Mode契約を確認する**

  Simple Modeで専用仕様書、実装計画、AC/TC/RT台帳、実装後レビュー文書を増やさないことを確認する。重要な設計判断が発生した場合は既存ADR参照またはADR作成を選べるが、ADR不要の局所変更には追加資料を要求しない。

- [ ] **Step 6: Markdownlintと差分を確認する**

  Run: `npx --no-install markdownlint-cli2 --no-globs docs/AI活用開発研究/構想メモ/標準化/開発フロー.md docs/AI活用開発研究/構想メモ/標準化/実装前チェック表.md`

  Expected: 2ファイルのMarkdownlintが0エラーで終了し、`git diff --check`が成功する。

- [ ] **Step 7: Commit the preflight integration**

  ```powershell
  git add 'docs/AI活用開発研究/構想メモ/標準化/開発フロー.md' 'docs/AI活用開発研究/構想メモ/標準化/実装前チェック表.md'
  git commit -m "docs: integrate maintainability checks into preflight"
  ```

### Task 3: 実装後レビューへADR整合性と保守担当者の確認を組み込む

**Files:**
- Modify: `docs/AI活用開発研究/構想メモ/標準化/実装後レビュー表.md`

**Interfaces:**
- Consumes: Task 1のADRテンプレート、Task 2の実装前に決めたADR要否・変更影響・検証方法。
- Produces: 既存レビューへ統合されたADR整合性、保守担当者視点、AI生成物の最終成果物レビュー。

- [ ] **Step 1: 既存の設計照合・AI生成物・記録レビューの節を確認する**

  `rg -n '^##|^###|AI生成物|Why|Why not|トレーサビリティ|記録|ログ|P0|P1|P2'`で対象節を確認し、同じ内容を複数のレビュー項目へ追加しない位置を決める。

- [ ] **Step 2: ADR整合性を既存の設計照合へ追加する**

  次の確認を既存の設計照合またはトレーサビリティへ追加する。

  ```text
  ADR要否が実装前判断と一致しているか
  実装がADRの決定、前提、制約と一致しているか
  ADRで却下した方式を意図せず再導入していないか
  ADRのリスク・影響をテスト、ログ、運用確認で検証できているか
  ADR不要の局所判断はコード構造、コメント、テストで根拠を確認できるか
  ```

- [ ] **Step 3: 保守担当者の5つの問いを既存レビューへ統合する**

  「機能の保証」「関係するファイル・データ・外部境界・業務ルール」「現在の方式の理由」「変更後の安全性の確認方法」「障害時の調査・復旧の入口」を、既存の設計、テスト、ログ、記録レビューの確認視点として追加する。独立した新レビュー担当は設けない。

- [ ] **Step 4: AI生成物レビューの記録負荷を下げる**

  AIが生成したコードの行単位の採用範囲を記録する要求は追加しない。最終成果物が仕様、ADR、テスト、セキュリティ要件と一致すること、重要な人間の判断がADRまたは作業記録へ残ること、コード差分とテスト結果が証拠として追跡できることを確認する。

- [ ] **Step 5: 既存レビュー優先度と統合担当を維持する**

  Backend/DB/Security、Frontend/UI、Integration/Finalの3チェックポイント、既存P0/P1/P2、統合品質記録を維持する。ADRだけを理由に独立レビューや新しい記録台帳を追加しない。

- [ ] **Step 6: Markdownlintと差分を確認する**

  Run: `npx --no-install markdownlint-cli2 --no-globs docs/AI活用開発研究/構想メモ/標準化/実装後レビュー表.md`

  Expected: Markdownlintが0エラーで終了し、`git diff --check`が成功する。

- [ ] **Step 7: Commit the review integration**

  ```powershell
  git add 'docs/AI活用開発研究/構想メモ/標準化/実装後レビュー表.md'
  git commit -m "docs: integrate ADR checks into implementation review"
  ```

### Task 4: 初回変更の範囲と試行準備を検証する

**Files:**
- Verify only: `docs/AI活用開発研究/構想メモ/標準化/テストケースレビュー観点.md`
- Verify only: `docs/AI活用開発研究/構想メモ/標準化/テスト方針.md`
- Verify only: `docs/AI活用開発研究/構想メモ/標準化/テスト・静的解析チェック表.md`
- Verify only: `docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md`
- Verify only: `docs/AI活用開発研究/構想メモ/標準化/統合品質記録様式.md`

**Interfaces:**
- Consumes: Task 1〜3の文書変更。
- Produces: 初回変更がテスト・品質ゲート運用を不要に変更していないこと、試行時に観点を棚卸しできることの検証結果。

- [ ] **Step 1: 初回変更の変更ファイルを確認する**

  Run: `git diff --name-only 6b76fe5..HEAD`

  Expected: 計画修正版コミット`6b76fe5`以降では、新しいADRテンプレート、長期保守方針、標準化資料一覧、`開発フロー.md`、`実装前チェック表.md`、`実装後レビュー表.md`のみが対象で、テスト方針・ケースレビュー観点・品質ゲート運用・統合品質記録様式は変更されていない。

- [ ] **Step 2: 参照先とUTF-8を確認する**

  PowerShellで対象Markdownを`Get-Content -Raw -Encoding UTF8`で読み、ADRテンプレート、既存の標準化資料、構想メモのリンク先が存在することを確認する。

  Expected: 文字化けがなく、参照先がすべて存在する。

- [ ] **Step 3: 棚卸し方法が初回変更に誤適用されていないことを確認する**

  `開発フロー.md`と`実装前チェック表.md`を読み、初回変更で既存項目の削除・優先度変更を要求していないことを確認する。削減・統合・廃止候補は、複数機能で試行した後に判断する記述を残す。

- [ ] **Step 4: 対象Markdownを一括検証する**

  Run: `npx --no-install markdownlint-cli2 --no-globs docs/AI活用開発研究/設計判断記録/ADRテンプレート.md docs/AI活用開発研究/構想メモ/長期保守可能性を重視した品質方針.md docs/AI活用開発研究/構想メモ/標準化/標準化資料一覧.md docs/AI活用開発研究/構想メモ/標準化/開発フロー.md docs/AI活用開発研究/構想メモ/標準化/実装前チェック表.md docs/AI活用開発研究/構想メモ/標準化/実装後レビュー表.md`

  Expected: 6ファイルのMarkdownlintが0エラーで終了し、`git diff --check`、作業ツリー確認、秘密情報検査が成功する。

- [ ] **Step 5: Record the verification result**

  検証結果は同じ実行結果を複数資料へ転記せず、今回の作業記録または統合品質記録の対象箇所へリンクする。検証だけのTask 4ではソース資料を追加変更せず、初回変更で新しい品質ゲートjobを追加しない。

## Plan Self-Review

- Spec coverage: ADRの導入と役割分担はTask 1、3層の適用はTask 2、レビューへの統合はTask 3、テスト・品質ゲートを変更しない確認と段階導入準備はTask 4で扱う。
- Scope: 初回変更では文書とADRテンプレートだけを扱い、既存観点の削除・優先度変更、CI変更、テスト方針変更を含めない。
- Evidence: 各タスクでUTF-8、リンク、Markdownlint、差分チェックを行い、最終的に初回変更対象外の資料が変更されていないことを確認する。
- 未確定の作業、空欄、未指定の手順はない。
