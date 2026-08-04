# 区分・メッセージDB化 正本テストケース

## 受入条件

| ID | 内容 |
| --- | --- |
| AC-MSG-001 | 有効なグループがDBの表示順で取得され、未ログイン401、社員空配列、上長は許可範囲、管理者は全件となる |
| AC-MSG-002 | グループのDB変更がAPIへ反映され、既存日報の登録時点グループ名は変わらない |
| AC-MSG-003 | DBのメッセージ文言がBackendエラーとFrontend共有表示へ反映される |
| AC-MSG-004 | 未登録キーまたはDB障害時にソースデフォルトへフォールバックする |
| AC-MSG-005 | 状態、ロール、状態遷移、入力検証、計算ロジックはDBメッセージ変更で変化しない |

## BDDシナリオ

### S-MSG-001 グループAPIのロール別取得

- Given: DBに有効なG001/G002と無効なG099があり、上長U002の許可グループがG001だけである
- When: 未ログイン、社員、上長、管理者が`GET /api/master/groups`を呼ぶ
- Then: 未ログインは401、社員は空配列、上長はG001のみ、管理者はG001/G002を表示順で取得する
- AC: AC-MSG-001
- 層: Backend API

### S-MSG-002 グループ名変更と日報履歴

- Given: G001の名称が「第1開発グループ」で、日報R001が登録時点名称を保持している
- When: DBのG001名称を変更し、新規日報を登録してR001を再取得する
- Then: 新規日報は変更後名称をスナップショットし、R001は登録時点名称のまま表示する
- AC: AC-MSG-002
- 層: Backend Unit/Oracle

### S-MSG-003 BackendエラーのDB文言

- Given: `validation.invalid`のDB本文を「入力を確認してください。」へ変更する
- When: 入力エラーAPIが同じエラーキーを返す
- Then: HTTPステータスとエラーコードは変わらず、`message`または`details[].message`だけがDB本文になる
- AC: AC-MSG-003
- 層: Backend Unit/API

### S-MSG-004 Frontend共有カタログ

- Given: メッセージAPIが`status.pending`を「確認待ち」と返す
- When: 日報一覧・詳細・登録画面を表示する
- Then: 承認状態ラベルが「確認待ち」と表示される
- AC: AC-MSG-003
- 層: Frontend Unit/Mock E2E

### S-MSG-005 フォールバック

- Given: メッセージキーが未登録、またはメッセージAPI・DB取得が失敗する
- When: BackendエラーまたはFrontend画面を表示する
- Then: 安全なソースデフォルトを表示し、DB例外や内部SQL情報は表示しない
- AC: AC-MSG-004
- 層: Backend Unit/Frontend Unit

### S-MSG-006 業務ロジック境界

- Given: DBの表示文言だけを変更する
- When: ロール判定、承認状態遷移、入力検証、勤務時間計算を実行する
- Then: 判定結果と計算結果は従来と一致する
- AC: AC-MSG-005
- 層: Backend/Frontend regression

## 詳細ケースとトレーサビリティ

| TC ID | 受入条件 | 前提・データ | 操作 | 期待結果 | テスト層 | 実テストID |
| --- | --- | --- | --- | --- | --- | --- |
| TC-MSG-001 | AC-MSG-001 | G001/G002 enabled=1、G099 enabled=0、U002→G001 | 各ロールでGET | 401/空配列/許可範囲/全件、表示順 | API | RT-MSG-001 |
| TC-MSG-002 | AC-MSG-001 | group SQLに順序違いの行 | Repository取得 | enabled=1だけを`display_order, group_id`順で返す | Unit | RT-MSG-002 |
| TC-MSG-003 | AC-MSG-002 | G001名称、R001スナップショット | マスタ更新後に新規/既存日報取得 | 新規だけ変更後名称、既存は保存名称 | Oracle/Unit | RT-MSG-003 |
| TC-MSG-004 | AC-MSG-003 | `validation.invalid`, ja-JP | API入力エラー | `code`/statusは維持、本文はDB値 | Unit/API | RT-MSG-004 |
| TC-MSG-005 | AC-MSG-003 | `status.pending`, ja-JP | Frontendカタログロード後表示 | DB表示文言で状態ラベルを描画 | UI | RT-MSG-005 |
| TC-MSG-006 | AC-MSG-004 | 未登録キー、JdbcTemplate例外、fetch例外 | Backend/Frontend解決 | ソースデフォルト、内部情報非表示 | Unit | RT-MSG-006 |
| TC-MSG-007 | AC-MSG-005 | DB本文だけ変更 | 状態/ロール/検証/計算を実行 | 結果が従来と一致 | Regression | RT-MSG-007 |

## 実行結果

- `MasterControllerTest`、`MasterControllerUnitTest`、`MessageCatalogControllerTest`、`MasterDataRepositoryTest`、`MessageCatalogServiceTest`、`ApiExceptionHandlerTest`、日報ルール: Focused Unit 56件成功。Oracle接続を必要とするSpring統合テスト全体は`ORA-01017`で保留。
- `MessageCatalogServiceTest`: DB本文、未登録キー、DB障害、locale、TTL再取得を成功。
- `MessageCatalogControllerTest`: 空localeの`ja-JP`正規化を成功。
- `ApiExceptionHandlerTest`: API本文・details本文のDBキー解決と既存レスポンス項目維持を成功。
- `messageCatalog.test.tsx`: DB上書きと取得失敗時フォールバックを成功。
- Frontend全体: 16 files / 137 tests、lint、typecheck、build成功。
- Mock E2E: 17 tests成功。Frontend coverageはStatements 95.87%、Branches 92.38%、Functions 97.48%、Lines 95.71%。
- Markdown 103 files、test layout、Quick/secret検査成功。

## 期待結果・テスト不足レビュー

| TC | 期待結果レビュー | テスト不足レビュー | 判定 |
| --- | --- | --- | --- |
| TC-MSG-001〜002 | ロール別空配列・許可範囲・表示順・無効行・スナップショットを確認 | Oracle実FKとDB更新反映は未実行 | 保留条件明記 |
| TC-MSG-003〜006 | status/code、DB本文、未登録/障害時の安全なフォールバックを確認 | locale別Oracle実値は未実行 | 保留条件明記 |
| TC-MSG-007 | DB本文のみ変更して状態・計算ロジックが変わらないことをUnit/E2Eで確認 | Backend Oracle/coverage未実行 | 保留条件明記 |

## テスト構成・責務分割

- `MasterControllerTest`: マスタAPIの認証・ロール別取得のみ。既存マスタAPIテストと責務が一致するため維持する。
- `MasterDataRepositoryTest`: DB行の取得・順序・フォールバックのみ。メッセージ解決テストは混在させず、`MessageCatalogServiceTest`へ分ける。
- `ApiExceptionHandlerTest`: 共通エラーレスポンス変換のみ。DB問い合わせそのものはサービスUnitで確認する。
- `messageCatalog.test.tsx`: FrontendのContext/API/フォールバックのみ。各画面テストへカタログ実装詳細を重複させない。
- 既存画面テストは、状態ラベル・既定文言の期待値を維持し、DBカタログ取得を直接モックする責務を持たせない。

## レビュー結果欄

| TC ID | 期待結果レビュー | テスト不足レビュー | 指摘ID | 保留理由・再確認条件 |
| --- | --- | --- | --- | --- |
| TC-MSG-001〜007 | 未実施 | 未実施 | なし | 実装後にP0レビューで記録 |
