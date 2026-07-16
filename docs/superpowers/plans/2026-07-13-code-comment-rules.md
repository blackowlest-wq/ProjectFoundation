# コード・コメント運用強化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ProjectFoundation全体で、本体コードはHow、テストコードはWhat、コミットログはWhy、コードコメントは必要なHowとWhy not、各メソッド・関数は日本語の責務・契約コメントを担保し、既存コメントを役割に応じて移行する。

**Architecture:** 正本となる標準資料に4分類を定義し、実装前・実装後レビュー・AIプロンプト・作業記録へ同じ判定基準を反映する。本体コードでは、責務・境界・契約の冒頭コメント、誤読防止の`How:`、不採用方式の`Why not:`を選別して残し、逐語的な説明だけを削除する。既存コミット履歴は変更しない。

**Tech Stack:** Markdown、Java 17 / Spring Boot、TypeScript / React、JUnit、Vitest、Playwright、Maven、npm

## Global Constraints

- `AGENTS.md` のUTF-8文書運用、作業記録、指摘一覧、標準資料反映ルールに従う。
- `docs/superpowers/specs/2026-07-13-code-comment-rules-design.md` の対象外（生成物、設定手順コメント、既存コミット履歴、機能仕様）を変更しない。
- 本体コードのコメントは、必要な責務・境界・契約の冒頭コメント、分岐・重要処理の`How:`、代替方式・制約・互換性・セキュリティ上の`Why not:`を残す。逐語的な説明だけのコメントは削除する。
- 各メソッド・関数は、公開API、状態変更、DBアクセス、外部通信、例外・複数分岐を優先して、直前に日本語の責務・入力・出力・副作用・契約コメントを残す。単純なアクセサ・一行委譲は契約が明確なら省略する。
- テストの期待値・アサーション・fixture・SQLデータは変更しない。テスト名または構造の変更が必要な場合も、確認内容を明確にする範囲に限定する。
- 変更したファイルごとのWhyと、不採用方式の判断を作業記録へ残す。
- 既存の未追跡 `.github/` は変更・ステージしない。

---

### Task 1: 標準資料へ4分類ルールを反映する

**Files:**

- Modify: `docs/AI活用開発研究/構想メモ/標準化/開発フロー.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/実装前確認観点.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/実装前チェック表.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/実装後レビュー観点.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/実装後レビュー表.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/テスト方針.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/テスト・静的解析チェック表.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/作業記録テンプレート.md`

**Interfaces:**

- Consumes: `docs/superpowers/specs/2026-07-13-code-comment-rules-design.md`
- Produces: 作り込み・レビュー・記録で参照できる4分類の正本ルール

- [ ] **Step 1: 共通定義を追加する**

`開発フロー.md` の基本原則と標準フローへ、次の定義を追加する。

```text
本体コードはHow（実装方法）を構造・型・命名で示し、誤読しやすい分岐・重要処理はコメントでもHowを示す。
各メソッド・関数は、直前の日本語コメントから責務・契約・重要な副作用が分かるようにする。
テストコードはWhat（検証対象と期待結果）をテスト名・構造で示す。
コミットログはWhy（背景・目的・影響）を本文で示す。
コードコメントは必要なHow（誤読防止）とWhy not（採用しなかった方式と除外理由）を記載する。
```

- [ ] **Step 2: 実装前チェックへ判断項目を追加する**

`実装前確認観点.md` と `実装前チェック表.md` に、コメント候補の判定、本体コードのHow表現、テストのWhat表現、コミットのWhy、採用しない方式の記録先を追加する。

- [ ] **Step 3: 実装後レビューへ判定基準を追加する**

`実装後レビュー観点.md` と `実装後レビュー表.md` のコメント項目を次へ置き換える。

```text
分岐・重要処理のHowがコードだけで誤読されないか。
責務・境界・契約の冒頭コメントが必要な箇所にあるか。
各メソッド・関数の責務・契約コメントが不足していないか。
Why notコメントは対象方式と除外理由を説明できるか。
テスト名・テスト構造からWhatと期待結果が分かるか。
コミット本文にWhy（背景・目的・影響）があるか。
```

- [ ] **Step 4: テスト方針と作業記録へ記録先を追加する**

`テスト方針.md` にテスト名・`describe`/`it`・Arrange/Act/AssertでWhatを表現するルールを追加する。`作業記録テンプレート.md` に、変更ファイルごとのWhy、コメントの削除/Why not化判断、採用しなかった方式、コミットログのWhy、再検討条件の欄を追加する。

`テスト・静的解析チェック表.md` のバックエンド通常テストとJaCoCoコマンドは、`backend/config/oracle-test.properties`を読み込む共通入口を使う。直接`mvn.cmd`を呼ばない。

- [ ] **Step 5: 文書内の整合性を確認する**

Run: `rg -n "コメント|テスト名|コミット|Why not|How|What|Why" docs/AI活用開発研究/構想メモ/標準化/{開発フロー,実装前確認観点,実装前チェック表,実装後レビュー観点,実装後レビュー表,テスト方針,作業記録テンプレート}.md`

Expected: 4分類の表現が各資料の役割に沿って存在し、旧来の「難しい処理にはコメントを入れる」だけの指示が残っていない。

### Task 2: AIプロンプトとProjectFoundationレビューskillへ反映する

**Files:**

- Modify: `docs/AI活用開発研究/構想メモ/標準化/AI内部プロンプト定義.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/skills/projectfoundation-preflight-ja/SKILL.md`
- Modify: `docs/AI活用開発研究/構想メモ/標準化/skills/projectfoundation-review-ja/SKILL.md`

**Interfaces:**

- Consumes: Task 1の正本ルール
- Produces: AI実装依頼・セルフレビュー・実装後レビューで同じ判断を要求するプロンプト

- [ ] **Step 1: 実装依頼テンプレートを更新する**

本体コード、テストコード、コミットログ、コードコメントの要求を追加する。コードコメントの要求は次の文面を基準にする。

```text
- 本体コードの処理手順は実装・構造・型・命名で表現してください。ただし、分岐の優先順位、アルゴリズム、処理順、重要な不変条件、副作用、外部API契約など、コードだけでは誤読しやすいHowはコメントで残してください。
- ファイル名だけでは分からない責務・境界・公開契約を示す冒頭コメントは残してください。
- 代替方式を採用しなかった理由が必要な箇所は、`Why not:`で対象方式と除外理由を記載してください。
- テスト名・describe/itからWhatと期待結果が分かるようにしてください。
- コミット本文には背景・目的・影響のWhyを記載してください。
```

- [ ] **Step 2: セルフレビュー・実装後レビューの観点を更新する**

コメント、テスト名、コミット本文を独立したレビュー観点として追加し、不採用方式に根拠がない場合は指摘一覧・作業記録へ記録する指示を追加する。

- [ ] **Step 3: ローカルレビューskillを更新する**

手順4の可読性確認と完了条件へ、必要なHow・責務/境界/契約の冒頭コメント・What・Why・Why notの確認、Why notコメントの根拠確認、テスト名のWhat確認を追加する。

`projectfoundation-preflight-ja/SKILL.md` の実装前確認手順と出力へ、4分類の表現方針とコメントとして残す判断を追加する。

- [ ] **Step 4: プロンプトとskillの参照整合性を確認する**

Run: `rg -n "How|What|Why not|コミット.*Why|テスト名.*What|コメント.*Why not" docs/AI活用開発研究/構想メモ/標準化/AI内部プロンプト定義.md docs/AI活用開発研究/構想メモ/標準化/skills/projectfoundation-review-ja/SKILL.md`

Expected: 実装依頼、セルフレビュー、実装後レビューの各テンプレートに4分類の要求がある。

### Task 3: バックエンド本体コメントを移行する

**Files:**

- Modify: `backend/src/main/java/com/example/dailyreport/auth/AppUser.java`
- Modify: `backend/src/main/java/com/example/dailyreport/auth/AppUserDetailsService.java`
- Modify: `backend/src/main/java/com/example/dailyreport/auth/AuthController.java`
- Modify: `backend/src/main/java/com/example/dailyreport/auth/AuthenticatedUser.java`
- Modify: `backend/src/main/java/com/example/dailyreport/auth/CurrentUserResponse.java`
- Modify: `backend/src/main/java/com/example/dailyreport/auth/LoginRequest.java`
- Modify: `backend/src/main/java/com/example/dailyreport/auth/ManagerGroupPermissionRepository.java`
- Modify: `backend/src/main/java/com/example/dailyreport/auth/Role.java`
- Modify: `backend/src/main/java/com/example/dailyreport/auth/UserRepository.java`
- Modify: `backend/src/main/java/com/example/dailyreport/common/ApiException.java`
- Modify: `backend/src/main/java/com/example/dailyreport/common/ApiExceptionHandler.java`
- Modify: `backend/src/main/java/com/example/dailyreport/config/DataInitializer.java`
- Modify: `backend/src/main/java/com/example/dailyreport/config/SecurityConfig.java`
- Modify: `backend/src/main/java/com/example/dailyreport/DailyReportApplication.java`
- Modify: `backend/src/main/java/com/example/dailyreport/master/MasterController.java`
- Modify: `backend/src/main/java/com/example/dailyreport/master/MasterDataRepository.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/controller/DailyReportCommandController.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/controller/DailyReportSearchController.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/controller/DailyReportSubmissionController.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/DailyReportAccessPolicy.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/DailyReportCommandService.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/DailyReportSearchService.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/DailyReportSubmissionService.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/dto/DailyReportListItemResponse.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/dto/DailyReportRequest.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/dto/DailyReportResponse.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/dto/DailyReportSummaryResponse.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/dto/SubmitResponse.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/entity/DailyReportEntity.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/entity/DailyReportRepository.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/entity/DailyReportWorkItemEntity.java`
- Modify: `backend/src/main/java/com/example/dailyreport/report/logic/TimeRules.java`
- Modify: `backend/src/main/java/com/example/dailyreport/workflow/ApprovalStatus.java`

**Interfaces:**

- Consumes: 既存の認証、CSRF、Oracle、日報状態遷移、時刻計算の実装とテスト
- Produces: 必要な責務・境界・契約の冒頭コメント、各メソッド・関数の日本語責務コメント、分岐・重要処理の`How:`、不採用方式の`Why not:`で判断を説明するJava本体

- [ ] **Step 1: 冒頭コメントを責務・境界・契約で選別する**

クラス名やフィールドの単純な言い換えだけのコメントは削除する。ファイル名だけでは分からない責務、境界、公開契約を示すコメントは残す。

- [ ] **Step 2: 認証・セキュリティのコメントをHow/Why notへ整理する**

`AuthController.java`、`AppUserDetailsService.java`、`SecurityConfig.java` のコメントは、セッションID再発行、未ログイン時の扱い、CSRF方式、共通エラー形式など、分岐・処理順・外部API契約の誤読を防ぐ`How:`と、別方式を採用しなかった理由を示す`Why not:`へ整理する。

```java
// Why not: 認証前のセッションIDを継続利用するとセッション固定攻撃を許すため、ログイン成功時に再発行する。
```

コードから明らかな逐語的説明だけを削除する。

- [ ] **Step 3: Oracle初期化・マスタコメントをHow/Why notへ整理する**

`DataInitializer.java` と `MasterDataRepository.java` では、初期化の処理順、既存オブジェクトを無視する条件、MERGE、既存明細の削除、無効マスタの表示フォールバックなど、誤読しやすい処理の`How:`と、互換性・再実行性・保存データ保全に関する`Why not:`を残す。ORAコードの単なる説明は、コードから意味が読める場合は削除する。

- [ ] **Step 4: 日報業務ルール・状態遷移・時刻計算のコメントをHow/Why notへ整理する**

`DailyReportCommandService.java`、`DailyReportSubmissionService.java`、`DailyReportAccessPolicy.java`、`DailyReportEntity.java`、`DailyReportResponse.java`、`DailyReportRequest.java`、`TimeRules.java` のコメントを、状態遷移の処理順、集計アルゴリズム、保存時点スナップショット、明細全差し替え、時刻表現の互換性など、誤読しやすい`How:`と判断理由を示す`Why not:`へ整理する。単に「先に検証する」「合計を返す」などコードから明らかな説明だけを削除する。

- [ ] **Step 5: Javaコメント規約違反が残っていないことを確認する**

Run: `rg -n "//|/\*|\*/" backend/src/main/java`

Expected: 残るコメントは、責務・境界・契約の冒頭コメント、`How:`、`Why not:`、またはツール指示として根拠がある。

### Task 4: フロントエンド本体コメントを移行する

**Files:**

- Modify: `frontend/src/app/App.tsx`
- Modify: `frontend/src/auth/authApi.ts`
- Modify: `frontend/src/auth/LoginForm.tsx`
- Modify: `frontend/src/auth/loginValidation.ts`
- Modify: `frontend/src/auth/types.ts`
- Modify: `frontend/src/dailyReport/dailyReportApi.ts`
- Modify: `frontend/src/dailyReport/DailyReportCalendarList.tsx`
- Modify: `frontend/src/dailyReport/DailyReportForm.tsx`
- Modify: `frontend/src/dailyReport/dailyReportValidation.ts`
- Modify: `frontend/src/dailyReport/types.ts`
- Modify: `frontend/src/main.tsx`
- Modify: `frontend/src/shared/apiClient.ts`
- Modify: `frontend/src/styles.css`

**Interfaces:**

- Consumes: 既存のReact画面、認証、CSRF、日報入力・検索の挙動
- Produces: 各関数の日本語責務コメント、画面初期化・分岐・重要な処理順の`How:`と、入力制約・API互換性などの除外理由を説明する`Why not:`を持つTypeScript/CSS

- [ ] **Step 1: 冒頭コメントを責務・境界・契約で選別する**

`types.ts`、`main.tsx`など名前だけで役割が分かる説明は削除し、`App.tsx`、`LoginForm.tsx`、`DailyReportForm.tsx`、`apiClient.ts`、`styles.css`など責務・境界が重要なファイルの冒頭コメントは残す。

- [ ] **Step 2: API・認証・CSRFのコメントをHow/Why notへ整理する**

`shared/apiClient.ts`、`authApi.ts`、`LoginForm.tsx`、`App.tsx` のコメントは、共通エラー形式、未ログインのnull扱い、CSRFトークンの受け渡し、ロール別URL、バックエンドを正とする入力検証などの外部API契約・処理順を示す`How:`と、別の方式を採用しない理由を示す`Why not:`へ整理する。fetchやstate更新の逐語的説明だけを削除する。

- [ ] **Step 3: 日報フォーム・検索・入力検証のHow/Why notを移行する**

`dailyReportValidation.ts`、`DailyReportForm.tsx`、`DailyReportCalendarList.tsx` のコメントは、有給・休日の入力制約、再提出API、編集URL、初期検索、初期選択値、全差し替えなどの分岐・処理順を`How:`で、業務・UX・API互換性上の除外理由を`Why not:`で残す。

- [ ] **Step 4: ESLint抑制の理由を明示する**

`DailyReportCalendarList.tsx` の初回検索用 `eslint-disable-next-line react-hooks/exhaustive-deps` の直前に、依存配列を増やして自動再検索させない理由を`Why not:`で記載する。抑制ディレクティブ自体は削除しない。

- [ ] **Step 5: TypeScript/CSSコメント規約違反が残っていないことを確認する**

Run: `rg -n "//|/\*|\*/" frontend/src`

Expected: 残る説明コメントは、責務・境界の冒頭コメント、`How:`、`Why not:`、またはツール抑制に必要なコメントである。

### Task 5: テストコードのWhat表現を監査する

**Files:**

- Review: `backend/src/test/java/com/example/dailyreport/auth/AuthControllerOracleIT.java`
- Review: `backend/src/test/java/com/example/dailyreport/auth/AuthControllerTest.java`
- Review: `backend/src/test/java/com/example/dailyreport/master/MasterControllerTest.java`
- Review: `backend/src/test/java/com/example/dailyreport/report/DailyReportCommandControllerTest.java`
- Review: `backend/src/test/java/com/example/dailyreport/report/DailyReportSearchControllerTest.java`
- Review: `backend/src/test/java/com/example/dailyreport/report/DailyReportSeparationTest.java`
- Review: `backend/src/test/java/com/example/dailyreport/report/DailyReportSubmissionControllerTest.java`
- Review: `backend/src/test/java/com/example/dailyreport/report/support/DailyReportTestSupport.java`
- Review: `backend/src/test/java/com/example/dailyreport/report/TimeRulesTest.java`
- Review: `backend/src/test/java/com/example/dailyreport/support/MockMvcTestSupport.java`
- Review: `frontend/test/authApi.test.ts`
- Review: `frontend/test/dailyReportApi.test.ts`
- Review: `frontend/test/dailyReportSearch.test.ts`
- Review: `frontend/test/dailyReportValidation.test.ts`
- Review: `frontend/test/LoginForm.test.tsx`
- Review: `frontend/test/loginValidation.test.ts`
- Review: `frontend/test/routePolicy.test.ts`
- Review: `frontend/e2e/daily-report.spec.ts`
- Review: `frontend/e2e/support/authMocks.ts`
- Review: `frontend/e2e/support/dailyReportMocks.ts`
- Review: `frontend/e2e/support/staticFrontend.ts`

**Interfaces:**

- Consumes: 既存のテスト名、describe/it構造、期待値、アサーション、fixture
- Produces: Whatが名前または構造から読めるテスト。テストの振る舞いは変更しない。

- [ ] **Step 1: JavaテストのWhatを確認する**

`@Test`メソッド名から、対象操作、条件、期待結果が読めることを確認する。既存の`loginSucceeds...`、`createRejects...`、`searchReturns...`などは維持し、曖昧な名前だけを変更する。

- [ ] **Step 2: Vitest/PlaywrightテストのWhatを確認する**

`describe`、`it`、`test`の文言から、利用者操作または検証対象と期待結果が読めることを確認する。setupの手順を説明するコメントは追加しない。

- [ ] **Step 3: テスト変更時の回帰を確認する**

テスト名だけを変更した場合も、期待値・アサーション・fixture・モック応答が変わっていないことを`git diff`で確認する。変更が不要なファイルは作業記録へ「既存のWhat表現で充足」と記録する。

### Task 6: 作業記録と指摘一覧を更新する

**Files:**

- Create: `docs/AI活用開発研究/作業記録/コードコメント運用強化_2026-07-13.md`
- Modify: `docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md`

**Interfaces:**

- Consumes: Task 1〜5の変更結果と検証結果
- Produces: 変更理由、コメント移行判断、指摘対応、未実行確認を追跡できる記録

- [ ] **Step 1: 作業記録をテンプレートに沿って作成する**

次を必ず記載する。

```text
依頼内容:
実装対象と対象外:
確認した標準資料:
変更した標準資料・本体コード:
How/What/Why/Why notの判断:
削除したコメントとWhy notへ残したコメントの分類:
テストコードのWhat監査結果:
コミットログのWhy運用:
実行したテスト・静的解析:
未実行・保留理由と再確認条件:
```

- [ ] **Step 2: 指摘一覧へ既存コメントの問題を記録する**

Howコメントの重複、Why not不足、またはテストWhat不足を指摘として追加し、対応ファイルと対応内容を記録する。該当しない分類は「該当なし」と明記する。

- [ ] **Step 3: 作業記録と指摘一覧の整合を確認する**

指摘ID、対応ファイル、保留理由、再確認条件が両資料で矛盾しないことを確認する。

### Task 7: 検証と最終レビューを行う

**Files:**

- Review: 変更差分全体
- Review: `docs/superpowers/specs/2026-07-13-code-comment-rules-design.md`
- Review: `docs/superpowers/plans/2026-07-13-code-comment-rules.md`

**Interfaces:**

- Consumes: Task 1〜6の変更
- Produces: 検証済みの標準資料・本体コード・テスト・記録

- [ ] **Step 1: 差分の機械的な整合を確認する**

Run: `git diff --check`

Expected: 出力なし。

Run: `rg -n --glob '*.java' --glob '*.ts' --glob '*.tsx' --glob '*.css' --glob '!frontend/playwright-report/**' '(?://|/\*|\*/)' backend/src/main frontend/src`

Expected: コメント一覧を確認し、コードから明らかな逐語的説明はなく、必要なHow・責務/境界/契約コメント・Why notまたはツール指示の根拠がある。

- [ ] **Step 2: バックエンド検証を実行する**

Run from the repository root: `Push-Location backend; scripts/test-oracle.cmd -q test; Pop-Location`

Expected: Oracle接続確立後、全テスト成功。実行不能な場合は、原因と再確認条件を作業記録へ記載する。直接`mvn.cmd`を呼ぶと、ローカル設定ファイルが環境変数へ注入されず、`ORA-01017`になるため使用しない。

- [ ] **Step 3: フロントエンド検証を実行する**

Run from the repository root: `Push-Location frontend; npm.cmd test -- --run; Pop-Location`

Expected: Vitestが成功。

Run from the repository root: `Push-Location frontend; npm.cmd run typecheck; Pop-Location`

Expected: TypeScriptエラーなし。

Run from the repository root: `Push-Location frontend; npm.cmd run build; Pop-Location`

Expected: production build成功。

- [ ] **Step 4: E2Eと配置品質ゲートを実行する**

Run from the repository root: `Push-Location frontend; npm.cmd run e2e; Pop-Location`

Expected: Playwrightの対象シナリオが成功。

Run: `powershell -ExecutionPolicy Bypass -File scripts/check-test-layout.ps1`

Expected: テスト配置違反なし。

- [ ] **Step 5: 最終レビューとWhy付きコミットを行う**

Run: `git status --short`

Expected: 変更対象以外では、既存の未追跡`.github/`だけが残る。

コミットする場合は、件名だけでなく本文に次を記載する。

```text
Why: Howコメントの重複を減らし、設計判断をWhy notとして追跡できるようにする。
Scope: 標準資料、既存コメント、テスト表現、作業記録を更新する。実行時の振る舞いは変更しない。
```
