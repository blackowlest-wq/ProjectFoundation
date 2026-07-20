# 日報承認・差し戻し 設計書

## 目的

日報の提出後に、上長が担当グループの日報を確認し、承認または差し戻しできるようにする。差し戻し後は、既存の日報編集・再提出機能へ戻れる状態を完成させる。

## 対象範囲

### 実装対象

- F-007 日報承認
- F-008 日報差戻し
- F-010 未承認一覧（承認・差し戻しの操作入口）
- F-005 日報詳細の承認・差し戻し操作および監査情報表示
- A-012 承認API
- A-013 差戻しAPI
- A-015 未承認一覧API
- 承認者・承認日時の永続化とAPI表示
- 上長向けの未承認一覧、日報詳細、差戻し入力UI

### 対象外

- 差し戻しコメントの履歴テーブル・履歴画面
- 承認ルートの多段階化
- 管理者による承認・差し戻し
- 楽観ロック用のversion列や条件付きUPDATEによる原子性改善
- 月次集計、CSV出力
- グループ・ユーザー・承認対象グループの保守画面
- メール通知

楽観ロックは既存設計で別途保留されている。今回の状態変更はトランザクション内で現在状態を確認し、`PENDING` 以外を409で拒否する範囲とする。DB更新の競合を原子性まで保証する変更は別課題として扱う。

## 仕様根拠

- `docs/AI活用開発研究/サンプル設計書/機能一覧・受入条件.md` の F-005、F-007、F-008、F-010
- `docs/AI活用開発研究/サンプル設計書/API一覧.md` の A-009、A-012、A-013、A-015
- `docs/AI活用開発研究/サンプル設計書/画面設計.md` の S-005、S-006、S-007
- `docs/AI活用開発研究/サンプル設計書/DB概念設計.md` の日報監査項目
- `docs/AI活用開発研究/サンプル設計書/入力チェック・業務ルール一覧.md` の V-STAT-005～008、V-AUTH-003～006、V-TRN-003～005、V-TRN-009～010

## 状態遷移

```text
PENDING --上長が承認--> APPROVED
PENDING --上長がコメント付きで差し戻し--> REJECTED
```

- 承認・差し戻しの対象状態は `PENDING` のみとする。
- 承認後は社員の編集・提出・再提出を既存の状態判定で拒否する。
- 差し戻し後は既存の編集・再提出機能で `REJECTED` の日報を修正し、`PENDING` へ戻せる。
- 承認時は承認者ID、承認者名、承認日時を保存する。
- 差し戻し時は差し戻し者ID、差し戻し者名、差し戻し日時、最新コメントを保存する。
- 差し戻し時に既存の承認監査項目があれば、承認済みとは扱わない。今回の通常フローでは承認前の `PENDING` のみを対象にする。

## API設計

### 承認

```http
POST /api/daily-reports/{reportId}/approve
```

認証済みの上長だけが利用できる。担当グループの日報で、現在状態が `PENDING` の場合に、次のレスポンスを返す。

```json
{
  "reportId": "R001",
  "approvalStatus": "APPROVED",
  "approverId": "M001",
  "approverName": "佐藤 上長",
  "approvedAt": "2026-06-02T09:00:00+09:00"
}
```

### 差し戻し

```http
POST /api/daily-reports/{reportId}/reject
Content-Type: application/json
```

```json
{
  "rejectComment": "作業時間を確認してください。"
}
```

コメントは前後空白を除いた文字列が1文字以上で、既存の差し戻しコメント列の上限以内とする。成功時は次のレスポンスを返す。

```json
{
  "reportId": "R001",
  "approvalStatus": "REJECTED",
  "rejectorId": "M001",
  "rejectorName": "佐藤 上長",
  "rejectedAt": "2026-06-02T09:00:00+09:00",
  "rejectComment": "作業時間を確認してください。"
}
```

### 未承認一覧

```http
GET /api/daily-reports/pending-approvals?dateFrom=2026-06-01&dateTo=2026-06-30&groupId=G001&employeeId=E001
```

上長の担当グループに属する `PENDING` の日報だけを返す。日付範囲は既存一覧APIと同じく必須、開始日が終了日を超えない、366日以内のルールを使用する。社員・管理者は403とする。

### APIエラー

| 条件 | HTTP | code |
| --- | ---: | --- |
| 未ログイン | 401 | `UNAUTHORIZED` |
| 社員・管理者による操作 | 403 | `FORBIDDEN` |
| 担当グループ外の日報 | 403 | `FORBIDDEN` |
| 日報が存在しない | 404 | `NOT_FOUND` |
| `PENDING` 以外の承認・差し戻し | 409 | `INVALID_STATUS` |
| コメント未入力・空白のみ・上限超過 | 400 | `VALIDATION_ERROR` |
| CSRFトークン不正・未指定 | 403 | Spring Security共通応答 |

## 認可

認可はフロントエンドの表示制御に依存せず、バックエンドで次の順序で確認する。

1. 認証済み利用者が存在することを確認する。
2. 利用者ロールが `MANAGER` であることを確認する。
3. 対象日報を取得する。
4. `manager_group_permissions` による担当グループ判定を行う。
5. 状態変更対象が `PENDING` であることを確認する。
6. 同一トランザクション内で監査項目と状態を更新する。

対象IDを推測しても、担当グループ外の日報の内容・監査情報は返さない。変更系APIは既存のCookieセッションとCSRF契約を使用し、画面のAPIクライアントは既存の `postJsonWithCsrf` を利用する。

## DB・Entity設計

`daily_reports` に次の承認監査項目を追加する。

| 項目 | DB列 | 用途 |
| --- | --- | --- |
| 承認者ID | `approver_user_id` | 承認した上長のユーザーID |
| 承認者名 | `approver_name` | 承認時点の表示名スナップショット |
| 承認日時 | `approved_at` | 承認操作の日時 |

既存の `rejector_user_id`、`rejector_name`、`rejected_at`、`reject_comment` は差し戻し監査項目として利用する。API DTO、Entity、Oracle DDL、テスト用seed/supportの列定義を同じ契約に揃える。履歴テーブルは追加しない。

## 画面設計

### 未承認一覧

- 上長だけに表示する。
- 初期表示は当月の開始日から終了日までを対象とする。
- 日付範囲、グループID、社員IDで検索できる。
- `PENDING` の日報のみ表示し、担当外グループは表示しない。
- 日報ID、日付、グループ、社員名、休日区分、勤務時間、作業時間合計、提出日時を表示する。
- 一覧の「詳細」から日報詳細へ遷移する。

### 日報詳細

- 社員・上長・管理者が認可範囲内の日報を参照できる。
- 日報ヘッダ、作業明細、承認状態、提出日時、承認者・承認日時、差し戻し者・差し戻し日時、最新差し戻しコメントを表示する。
- 上長かつ `PENDING` の場合だけ「承認する」「差し戻しする」を表示する。
- 承認は確認後にAPIを呼び、成功後は状態と監査情報を再表示する。
- 差し戻しはコメント入力ダイアログを開き、空白のみの場合はAPIを呼ばず画面でエラーを表示する。
- 409の場合は状態を再取得し、古い画面からの操作であることを表示する。

## BDDシナリオ

| シナリオID | Given | When | Then | 受入条件 |
| --- | --- | --- | --- | --- |
| BDD-APR-001 | 担当グループの日報が `PENDING` である | 上長が承認する | `APPROVED`、承認者、承認日時がAPI・画面・DBに反映される | F-007-AC-001～004、F-007-AC-009～010 |
| BDD-APR-002 | 担当グループの日報が `PENDING` である | 上長がコメント付きで差し戻す | `REJECTED`、差し戻し者、日時、最新コメントがAPI・画面・DBに反映される | F-008-AC-001～005、F-008-AC-011～012 |
| BDD-APR-003 | 上長に担当グループ外の日報または `PENDING` 以外の日報がある | 承認・差し戻しを要求する | 権限外は403、状態不整合は409、DBは変更されない | F-007-AC-005～008、F-008-AC-006～010 |
| BDD-APR-004 | 上長が差し戻し画面を開いている | コメントなし、空白のみ、上限超過で確定する | 400相当の画面エラーを表示し、API・DB変更を行わない | F-008-AC-002、F-008-AC-007 |
| BDD-APR-005 | 上長がログインしている | 未承認一覧を検索する | 担当グループの `PENDING` のみ表示され、0件時は空表示になる | F-010-AC-001～004、F-010-AC-007～008 |
| BDD-APR-006 | 社員または管理者がログインしている | 承認系画面・APIへアクセスする | UI操作を表示せず、APIは403になる | F-007-AC-007～008、F-008-AC-009～010、F-010-AC-005～006 |
| BDD-APR-007 | 日報が `REJECTED` になっている | 社員が詳細・編集画面を開く | 最新差し戻しコメントを確認でき、既存の修正・再提出へ接続できる | F-008-AC-005、F-009-AC-001～005 |

## 正本テストケースとトレーサビリティ

今回の機能専用ケースは `TC-APR-*`、実テストIDは `RT-APR-*`、指摘IDは `FIND-APR-*` を使用する。既存の日報登録編集ケースを再利用する場合もIDを再利用せず、回帰確認は既存ケースへの参照として記録する。

| 受入条件ID | テストケースID | テスト層 | 期待結果 | 実テストID/コマンド |
| --- | --- | --- | --- | --- |
| F-007-AC-001～004 | TC-APR-001 | API/DB | 担当上長が `PENDING` を承認し、`APPROVED` と承認監査項目が保存される | RT-APR-BE-001 / `DailyReportApprovalControllerTest#managerCanApprovePendingReport` |
| F-007-AC-005～008 | TC-APR-002 | API/DB | 不正状態、担当外、社員、管理者の承認は拒否されDB不変 | RT-APR-BE-002 / `DailyReportApprovalControllerTest#managerCannotApproveUnauthorizedOrNonPendingReports` |
| F-007-AC-009～010 | TC-APR-003 | E2E | 未承認一覧から詳細を開き承認し、表示更新と業務フローを確認 | RT-APR-E2E-001 / `approval-rejection.spec.ts` |
| F-008-AC-001～005 | TC-APR-004 | API/DB | 担当上長がコメント付きで差し戻し、最新コメントと監査項目が保存される | RT-APR-BE-003 / `DailyReportApprovalControllerTest#managerCanRejectPendingReport` |
| F-008-AC-006～010 | TC-APR-005 | API/DB | 不正状態、担当外、社員、管理者の差し戻しは拒否されDB不変 | RT-APR-BE-004 / `DailyReportApprovalControllerTest#managerCannotRejectUnauthorizedOrNonPendingReports` |
| F-008-AC-007 | TC-APR-006 | API/UI | 空文字、空白のみ、上限超過コメントは拒否される | RT-APR-BE-005、RT-APR-UI-002 |
| F-008-AC-011～012 | TC-APR-007 | E2E | 未承認一覧から差し戻し、社員の既存編集・再提出へ接続できる | RT-APR-E2E-002 / `approval-rejection.spec.ts` |
| F-010-AC-001～004、007 | TC-APR-008 | API/UI | 担当グループの `PENDING` のみ表示し、詳細へ遷移できる | RT-APR-BE-006、RT-APR-UI-001 |
| F-010-AC-005～006 | TC-APR-009 | API/UI | 社員・管理者には未承認一覧を表示せず、APIも403になる | RT-APR-BE-007、RT-APR-UI-003 |
| F-005-AC-001～008 | TC-APR-010 | API/UI | 認可範囲の日報詳細と監査情報を表示し、範囲外・不存在を拒否する | RT-APR-BE-008、RT-APR-UI-004 |

## テスト構成・責務対応表

| テストファイル | 責務 | テスト層 | 対象本番モジュール | 分割・維持判断 |
| --- | --- | --- | --- | --- |
| `backend/src/test/java/com/example/dailyreport/report/DailyReportApprovalControllerTest.java` | 承認・差し戻し・未承認一覧API、認証認可、DB副作用 | API/DB結合寄り | `DailyReportApprovalController`、`DailyReportApprovalService`、`DailyReportPendingApprovalService` | 新規作成。既存の提出・検索テストへ混在させない |
| `backend/src/test/java/com/example/dailyreport/report/support/DailyReportTestSupport.java` | 上長・日報・承認対象グループのseed補助 | Test support | 共有fixture | 維持。複数ユースケースから使う既存補助へ最小限の追加 |
| `frontend/test/dailyReportApproval.test.ts` | APIクライアント、コメント入力、状態表示の純粋ロジック | Unit | `dailyReportApproval.ts`、`dailyReportApi.ts` | 新規作成。既存APIテストへ混在させない |
| `frontend/test/DailyReportApprovalPanel.test.tsx` | 未承認一覧・詳細・操作ボタンの表示と通信 | UI Unit | `DailyReportApprovalPanel.tsx`、`DailyReportDetail.tsx` | 新規作成。既存フォーム・一覧テストへ混在させない |
| `frontend/e2e/approval-rejection.spec.ts` | 上長の承認・差し戻し、社員の差し戻し確認・再提出接続 | Mock E2E | Appルーティング、承認画面 | 新規作成。既存日報編集E2Eと責務を分ける |
| `frontend/e2e/support/dailyReportApprovalMocks.ts` | 承認・差し戻し・詳細・未承認一覧の通信モック | E2E support | Playwright fixture | 新規作成。既存日報編集モックへ過剰追加しない |

既存の`DailyReportSearchControllerTest`、`DailyReportSubmissionControllerTest`、`DailyReportCalendarList.test.tsx`、日報編集E2Eは、既存機能の回帰確認として維持する。承認専用ケースを既存テストファイルへ追加しない。

## レビュー範囲

| 優先度 | 観点 | 参照資料・節 | 対象範囲 | 出力先 |
| --- | --- | --- | --- | --- |
| P0 | 設計・受入条件照合 | `実装前チェック表.md`、機能一覧F-005/F-007/F-008/F-010、API一覧A-009/A-012/A-013/A-015、画面設計S-005/S-006/S-007 | API、DB、画面、状態遷移、対象外 | `日報承認差戻し_受入条件レビュー.md` |
| P0 | テスト不足・構成 | `テストケースレビュー観点.md`、`テスト方針.md`、`テスト設計書.md` | `TC-APR-*`、責務分割、E2E、Oracle | `日報承認差戻し_テストケースレビュー.md` |
| P0 | 期待結果 | `テストケースレビュー観点.md` の期待結果レビュー観点、専用ケース | API本文、DB、画面、ログ | `日報承認差戻し_テストケースレビュー.md` |
| P0 | トレーサビリティ・統合 | `AI専門レビュー用プロンプト定義.md` の08、作業記録テンプレート | AC/TC/RT/FINDとレビュー結果 | `日報承認差戻し_実装後レビュー.md` |
| P1 | セキュリティ | `セキュリティ規約.md`、同03 | ロール、担当グループ、IDOR、CSRF、エラー | `日報承認差戻し_セキュリティレビュー.md` |
| P1 | 配置・共通化 | `ディレクトリ構成ルール.md`、`共通部品化判断基準.md`、同04 | Controller/Service/DTO、React部品、test support | `日報承認差戻し_可読性レビュー.md` |
| P1 | 静的解析・品質ゲート | `テスト・静的解析チェック表.md`、`品質ゲート運用.md`、同05 | lint、typecheck、build、coverage、Oracle入口 | `日報承認差戻し_実装後レビュー.md` |

## 完了条件

- API、画面、DBの受入条件を満たす。
- 承認、差し戻し、未承認一覧、詳細画面のAPI・Unit/UI・E2Eケースが成功する。
- 既存の提出・再提出・日報一覧・編集の回帰テストが成功する。
- P0/P1レビューと指摘の標準化判定が完了する。
- Frontendのlint、typecheck、unit、build、E2E、coverageを実行する。
- Backendのtest-compile、通常テスト、静的解析、coverage可否を確認する。
- Oracle DDL変更をOracle runnerで実行できない場合は、未実行理由と再確認条件を作業記録へ残す。
- 作業記録、受入条件レビュー、テストケース、指摘一覧、実装後レビューを更新する。

## 確認事項・仮定・保留

- 承認対象グループは既存の`manager_group_permissions`を利用する。
- 承認者名・差し戻し者名は操作時点の`users.user_name`をスナップショットする。
- 未承認一覧の初期日付範囲はクライアントの現在月とする。サーバー側の検索契約は既存一覧APIと同じ日付範囲検証を使う。
- 詳細画面は既存の`GET /api/daily-reports/{reportId}`を拡張し、承認監査項目を含める。新しい詳細APIは追加しない。
- 競合の原子性改善、コメント履歴、通知、集計・CSVは今回保留する。再確認条件は対応する後続機能の設計開始時とする。
- 外部ライブラリは追加しない。既存のSpring Boot/JPA、React/TypeScript、Vitest、Playwright、Oracle DDLを使用する。
