# 区分・メッセージDB化 実装後レビュー

日付: 2026-08-04
ブランチ: `codex/master-message-db`
作業場所: 隔離worktree
モード: 品質重視

## レビュー対象

- 受入条件: `AC-MSG-001`〜`AC-MSG-005`
- 正本テストケース: `区分メッセージDB化_テストケース.md`
- 設計: `docs/superpowers/specs/2026-08-04-master-message-db-design.md`
- API/DB: `サンプル設計書/API一覧.md`、`サンプル設計書/DB概念設計.md`
- 実装: `backend/src/main/java/com/example/dailyreport/master`、`config`、日報サービス、`frontend/src/shared`、日報画面、Oracle DDL/seed

## 3チェックポイント判定

### Backend / DB / Security

- `groups` は有効行を表示順で取得し、社員空配列、上長の許可グループ、管理者全件をサーバー側で判定する。
- 上長権限Repository未注入時は全件を返さず空配列とするfail-closedを確認した。
- `message_catalog` は`message_key + locale`複合主キー、`enabled`、本文長制約、作成・更新日時を持つ。
- APIエラーは安定キーと表示本文を分離し、既存のHTTP status/code/detailsを維持する。本文・SQL・資格情報はログへ出さない。
- DB問い合わせはJdbcTemplateのバインド変数を使用し、DB障害時は直前キャッシュまたはソースデフォルトへフォールバックする。
- グループ名は新規日報登録時のスナップショットへ反映し、既存履歴の保存本文を変更しない。
- CSRF、ログイン認証、日報の状態遷移・計算ロジックはDB本文変更の対象外として維持する。

判定: 合格。Oracle実機によるDDL/FK/seed/DB変更反映だけは未実行として保留。

### Frontend / UI

- `MessageProvider` と共有APIでカタログを取得し、5分TTL、DB障害時の既定値・前回値継続を確認した。
- 状態コードはソースの固定値を維持し、一覧の`status.draft=未提出`と編集画面の既存表示`status.draft_editor=下書き`を別キーで保持した。
- APIエラー本文はBackendの解決値を優先し、Frontendの固定値は最終フォールバックとした。
- 既存E2Eの対象月依存と休日マスタ属性不足を修正し、Mock E2E 17件を通過させた。

判定: 合格。

### Integration / Final

- AC/TC/RT/FINDの対応を下表へ整理した。
- 初回FullでSpotBugs指摘を検出し、修正後にBackend静的解析を再実行した。
- Frontend単体137件、coverage、E2E17件、Markdown、配置、secret検査を確認した。
- Oracle接続は`ORA-01017`で実行環境ブロッカー。成功扱いにせず、品質記録へ再確認条件を残す。

判定: Oracleを除くローカル品質ゲート合格。Oracle実行後に最終リリース判定を再確認する。

## トレーサビリティ

| AC | TC | RT/実行結果 | 判定 |
| --- | --- | --- | --- |
| AC-MSG-001 | TC-MSG-001〜002 | `MasterControllerTest`、`MasterDataRepositoryTest`、`MasterControllerUnitTest`、E2Eロール確認 | 合格。Oracle APIは保留 |
| AC-MSG-002 | TC-MSG-003 | `DailyReportCommandControllerTest`、`MasterDataRepositoryTest` | Oracle DB反映は保留 |
| AC-MSG-003 | TC-MSG-004〜005 | `ApiExceptionHandlerTest`、`MessageCatalogServiceTest`、`messageCatalog.test.tsx`、E2E17件 | 合格 |
| AC-MSG-004 | TC-MSG-006 | `MessageCatalogServiceTest`、Frontendカタログテスト、静的解析 | 合格 |
| AC-MSG-005 | TC-MSG-007 | Backend変更関連Unit、Frontend137件、E2E17件 | 合格 |

## 指摘・標準化判定

| 指摘ID | 対応 | 標準化判定 |
| --- | --- | --- |
| FIND-DBMSG-001 | groups/message_catalogと共有キー解決を実装 | 標準化候補: 安定キーとDB表示本文の分離 |
| FIND-DBMSG-002 | 上長権限をfail-closedへ修正、Unit追加 | 既存観点で対応 |
| FIND-DBMSG-003 | seed漏れ2キーを追加、87キー一致を確認 | 標準化候補: source/DataInitializer/seed同期確認 |
| FIND-DBMSG-004 | E2E日付とfixture属性を固定 | 既存観点で対応 |
| FIND-DBMSG-005 | SpotBugs指摘を修正・除外理由を記録 | 既存観点で対応 |

## 保留事項

- Oracle実機: `backend/config/oracle-test.properties`の有効な資格情報、`DAILY_REPORT_DB_ENV=TEST`、期待DB識別環境が設定された隔離runnerで`check.ps1 -Mode Oracle`を再実行する。
- Backend coverage: Oracle接続成功後にJaCoCoとOracle連携テストを実行し、85%以上と未通過分岐のレビューを記録する。
- マスタメンテナンス画面: 今回対象外。DB変更の監査・承認運用は別機能で設計する。
