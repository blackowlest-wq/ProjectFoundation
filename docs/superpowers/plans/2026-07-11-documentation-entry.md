# ドキュメント入口整備 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** リポジトリ直下のREADMEから、プロジェクトの概要と既存の開発標準・作業記録へ到達できるようにする。

**Architecture:** READMEを唯一の簡潔な入口とし、開発標準の内容は既存の標準化資料一覧を正本として参照する。既存資料は変更・複製せず、READMEには概要とリンクだけを置く。

**Tech Stack:** Markdown、GitHub Markdown

## Global Constraints

- 文書はUTF-8の日本語で記載する。
- `.gitignore`、ソースコード、依存関係、起動設定は変更しない。
- 将来の複数バージョン構成、詳細な起動手順、ライセンスは記載しない。
- 開発標準の正本は `docs/AI活用開発研究/構想メモ/標準化/標準化資料一覧.md` とし、READMEへ規約を複製しない。

---

### Task 1: リポジトリ入口READMEの追加

**Files:**

- Create: `README.md`
- Test: `README.md` のリンク先3件

**Interfaces:**

- Consumes: `AGENTS.md`、`docs/AI活用開発研究/構想メモ/標準化/標準化資料一覧.md`、`docs/AI活用開発研究/作業記録/`
- Produces: GitHub上で最初に表示されるプロジェクト概要と文書導線

- [ ] **Step 1: READMEのリンク先が存在することを確認する**

Run:

```powershell
@(
  'AGENTS.md',
  'docs/AI活用開発研究/構想メモ/標準化/標準化資料一覧.md',
  'docs/AI活用開発研究/作業記録'
) | ForEach-Object { "$_ : $(Test-Path $_)" }
```

Expected: 3行すべてが `True`。

- [ ] **Step 2: 最小の入口READMEを作成する**

`README.md` に次の内容を記載する。

```markdown
# ProjectFoundation

日報の登録・編集・一覧を扱うアプリケーションです。

## 現行構成

- フロントエンド: React / Vite / TypeScript
- バックエンド: Spring Boot / Java 21
- データベース: Oracle Database

## ドキュメント

- [開発標準資料一覧](docs/AI活用開発研究/構想メモ/標準化/標準化資料一覧.md): 開発フロー、実装前確認、レビュー、テスト方針などの正本です。
- [作業記録](docs/AI活用開発研究/作業記録/): 実装・レビュー・検証の記録です。
- [AI作業時の入口](AGENTS.md): AIを利用して作業する際に確認するルールです。

詳細な起動方法や将来の複数バージョン構成は、内容が確定した時点で追加します。
```

- [ ] **Step 3: 形式とリンク先を検証する**

Run:

```powershell
git diff --check
@(
  'README.md',
  'AGENTS.md',
  'docs/AI活用開発研究/構想メモ/標準化/標準化資料一覧.md',
  'docs/AI活用開発研究/作業記録'
) | ForEach-Object { "$_ : $(Test-Path $_)" }
```

Expected: `git diff --check` は出力なしで終了し、4行すべてが `True`。

- [ ] **Step 4: 変更を確認する**

Run:

```powershell
Get-Content -Raw -Encoding UTF8 README.md
git status --short
```

Expected: READMEに概要・技術構成・文書リンクだけが追加され、既存文書は変更されていない。

- [ ] **Step 5: コミットする**

Run:

```powershell
git add README.md
git commit -m "docs: add project documentation entry"
```

Expected: READMEのみを含むコミットが作成される。
