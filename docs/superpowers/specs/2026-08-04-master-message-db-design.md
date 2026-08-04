# DBマスタ・メッセージカタログ設計

日付: 2026-08-04
状態: Approved for implementation
開発モード: 品質重視モード

## 目的

業務上変更される区分と画面表示メッセージの正本をDBへ寄せ、ソース変更なしで名称・表示順・有効状態・表示文言を変更できるようにする。状態遷移、権限制御、入力検証、計算ロジック、APIエラーコードはソースを正として保持する。

## 対象範囲

- `groups`マスタの追加と、既存のグループAPI設計に沿った取得。
- 既存の案件、作業分類、休日区分、休憩区分、勤務区分と同じ有効フラグ・表示順の扱い。
- `message_catalog`の追加。
- BackendのAPIエラー、入力エラー、業務エラー、セキュリティエラーのメッセージ解決。
- Frontendの共有メッセージ取得、承認状態ラベル、主要なエラー・操作結果メッセージのDB上書き。
- DB障害・未登録キー時の安全なソースデフォルトへのフォールバック。
- Oracle DDL、開発・テスト用初期データ、API仕様、テストケース、作業記録の更新。

## 対象外

- ロールの追加・削除や動的RBAC。
- `DRAFT`、`PENDING`などの状態遷移のDB設定化。
- 入力桁数・正規表現・勤務時間計算などの業務ロジックのDB設定化。
- マスタメンテナンス画面の追加。初回はDB seedまたはDB管理作業で変更する。
- 過去の日報に表示済みのスナップショット文言の再計算。

## 正本の境界

| 対象 | 正本 | 補足 |
| --- | --- | --- |
| 案件、作業分類、休日区分、休憩区分、勤務区分 | DB | 有効な行をAPI・保存前検証・計算設定の入力とする |
| グループ | DB | 利用者、承認対象、検索条件で参照する。無効化し、物理削除しない |
| 表示メッセージ | DB | `message_key`と`locale`で表示文言を取得する |
| メッセージキー、APIエラーコード | ソース | API契約とテストで固定する |
| ロール、承認状態、状態遷移 | ソース＋DB制約 | DB列の値はEnumとCHECK制約で検証する |
| 入力検証、計算、権限制御 | ソース | DBマスタの属性を入力として使うが、ルールの実行順はコードで管理する |

## データモデル

### groups

既存の概念設計に合わせ、`group_id`、`group_name`、`display_order`、`enabled`を持つ。ユーザーの所属、上長の承認対象、日報の登録時所属は`group_id`を参照する。既存の日報に保持する`group_name`は登録時点のスナップショットとして残す。

### message_catalog

```text
message_key  VARCHAR2(120 CHAR)  primary key component
locale       VARCHAR2(20 CHAR)   primary key component
message_text VARCHAR2(1000 CHAR) not null
enabled      NUMBER(1)           not null
created_at   TIMESTAMP           not null
updated_at   TIMESTAMP           not null
```

主キーは`message_key + locale`とする。同一キーの日本語を一つに限定せず、将来の多言語化に備える。メッセージ本文はHTMLとして解釈せず、パラメータはBackendまたはFrontendで安全に埋め込む。

## メッセージ解決

Backendはエラーを`message_key`とソースデフォルトの組み合わせで生成し、共通例外ハンドラーでDB文言へ解決する。既存のJSON契約の`message`と`details[].message`は維持し、必要な場合だけ`messageKey`を追加する。

Frontendは`/api/master/messages?locale=ja-JP`を起動時に取得し、共有メッセージコンテキストへ保存する。取得失敗または未登録キーの場合はソースデフォルトを表示する。Backend APIが返すエラーメッセージはAPIレスポンスを優先し、Frontendで再解決しない。

メッセージキャッシュはアプリケーション内に保持し、5分経過後の次回参照で再取得する。DB障害時は直前のキャッシュまたはソースデフォルトを使用し、メッセージ取得障害を利用者向けに追加表示しない。

## グループ取得

`GET /api/master/groups`を認証必須で提供する。管理者は有効な全グループ、上長は`manager_group_permissions`に登録された有効グループ、社員は空配列を返す。表示順は`display_order, group_id`とする。クライアントから受け取ったグループIDは既存の権限制御で再検証し、APIの選択肢取得だけを信頼しない。

## セキュリティ・障害時方針

- メッセージAPIは認証済み利用者へ限定する。
- SQLは既存Repositoryと同じパラメータバインドで実行する。
- メッセージ本文をログへ出力せず、エラーコードとリクエストIDだけを観測対象とする。
- DBで自由にエラーコード、ロール、状態を追加できる設計にしない。
- グループは物理削除せず`enabled=0`で無効化する。過去日報はスナップショットで表示する。
- DB取得失敗時に、エラー処理がDB取得を再帰的に呼び出さない。

## 受入条件

| ID | 条件 |
| --- | --- |
| AC-MSG-001 | 有効なグループがDBの表示順で`GET /api/master/groups`へ返り、未ログインは401、社員は空配列、上長は許可グループだけ、管理者は全件を取得できる |
| AC-MSG-002 | グループ名・表示順・有効状態をDBで変更すると、再取得後のAPI結果に反映される。既存日報の登録時点グループ名は変わらない |
| AC-MSG-003 | 登録済み`message_key`の文言変更がBackendのエラー応答とFrontendの共有メッセージへ反映される |
| AC-MSG-004 | メッセージ未登録またはDB取得失敗時も、API契約を壊さず、ソースデフォルトの文言で処理を継続できる |
| AC-MSG-005 | 承認状態、ロール、入力検証、権限制御、計算ロジックの正本はソースに残り、DBメッセージ変更だけでは業務ルールが変わらない |

## 正本テストケースとトレーサビリティ

| 受入条件ID | テストケースID | テスト層 | 期待結果 | 実テストID/コマンド |
| --- | --- | --- | --- | --- |
| AC-MSG-001 | TC-MSG-001 | Backend API | 未認証401、社員空配列、上長の許可範囲、管理者の全件、表示順を確認 | RT-MSG-001 `MasterControllerTest` |
| AC-MSG-001 | TC-MSG-002 | Backend Unit | Repositoryがenabled=1だけを`display_order, group_id`順で取得する | RT-MSG-002 `MasterDataRepositoryTest` |
| AC-MSG-002 | TC-MSG-003 | Oracle/Repository | DBの名称・順序・無効化が再取得へ反映され、無効化後も履歴参照が継続する | RT-MSG-003 `mvnw test` / Oracle runner |
| AC-MSG-003 | TC-MSG-004 | Backend Unit/API | キー解決、locale、DB文言、Backendエラー応答を確認する | RT-MSG-004 `MessageCatalogServiceTest`, `ApiExceptionHandlerTest` |
| AC-MSG-003 | TC-MSG-005 | Frontend Unit | 取得したカタログで状態ラベルとエラー表示が上書きされる | RT-MSG-005 `messageCatalog.test.tsx` |
| AC-MSG-004 | TC-MSG-006 | Backend Unit/Frontend Unit | DB例外・未登録キー時にデフォルトへフォールバックする | RT-MSG-006 `MessageCatalogServiceTest`, `messageCatalog.test.tsx` |
| AC-MSG-005 | TC-MSG-007 | Backend/Frontend regression | 状態遷移、ロール判定、入力検証、計算結果が従来どおりである | RT-MSG-007 `mvnw test`, `npm test`, E2E |

## テスト構成・責務対応表

| テストファイル | 責務 | 層 | 対象本番モジュール | 判定 |
| --- | --- | --- | --- | --- |
| `backend/src/test/java/com/example/dailyreport/master/MasterControllerTest.java` | マスタAPI認証・ロール別グループ取得 | API | `MasterController` | 既存責務へ追加 |
| `backend/src/test/java/com/example/dailyreport/master/MasterDataRepositoryTest.java` | グループSQLの取得とフォールバック | Unit | `MasterDataRepository` | 既存責務へ追加 |
| `backend/src/test/java/com/example/dailyreport/master/MessageCatalogServiceTest.java` | メッセージ解決、TTL、DB障害フォールバック | Unit | `MessageCatalogService` | 新規 |
| `backend/src/test/java/com/example/dailyreport/common/ApiExceptionHandlerTest.java` | 共通APIエラーの解決 | API | `ApiExceptionHandler` | 既存責務へ追加 |
| `frontend/test/messageCatalog.test.tsx` | カタログ取得・フォールバック・共有表示 | Unit/UI | `MessageProvider` | 新規 |
| `frontend/test/App.test.tsx`ほか既存テスト | 既存画面の回帰 | Unit/UI | 各画面 | 維持 |
| `frontend/e2e/daily-report.spec.ts` | 主要画面表示・DBマスタ利用の代表フロー | Mock E2E | Frontend | 既存回帰 |

## 自己レビュー結果

- 対象範囲はグループ、メッセージカタログ、既存API契約、DB初期化、Frontend表示に限定し、動的RBACや業務ルールのDB化を対象外にした。
- `groups`は既存のDB概念設計・API一覧と整合する。物理SQLに不足していた表を追加する変更として扱う。
- メッセージはキーと本文を分離し、APIエラーコード・状態・検証ロジックをDBから変更できないため、設計境界に矛盾はない。
- 未登録・DB障害時のデフォルトを受入条件とテストケースへ対応付けた。
- Backend、Frontend、Oracle、E2Eのテスト層を責務別に分離し、Full成功だけで構成確認を完了扱いにしない。
- 既存APIの`message`本文を維持し、`messageKey`は互換性を壊さない追加項目として扱う。
- 残る運用事項は、初回は管理画面を作らずDB seedまたはDB管理作業で文言を変更することと、キャッシュ反映まで最大5分かかることである。
