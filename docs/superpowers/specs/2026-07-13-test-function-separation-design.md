# テストと機能コードの責務分離 設計書

## 1. 背景

日報機能の既存コードでは、フロントエンドのテストが機能実装ディレクトリに配置され、バックエンドの Controller、Service、テストクラスにも複数ユースケースが集約されている。機能追加時に同じファイルへ変更が集中し、責務の把握と並列開発が難しくなるため、機能単位に分離する。

## 2. 対象と対象外

### 対象

- フロントエンドの日報検索ヘルパーテストの配置分離
- バックエンドの日報 API の検索・詳細、登録・更新、提出・再提出の責務分離
- 日報テストクラスのユースケース単位分割
- 日報テストに混在しているマスタ API テストのマスタ機能への移動
- 認可など複数ユースケースで同じ変更理由を持つ処理の最小限の共通化
- テスト配置とユースケース分割の再発防止策
- 作業記録、指摘一覧、標準化資料の更新

### 対象外

- API の URL、HTTP メソッド、DTO、Entity、Repository、レスポンス形式の変更
- 業務ルール、入力チェック、認証認可、状態遷移の仕様変更
- テストの確認内容、期待値、テストケース追加・削除
- 今回の対象外機能の大規模リファクタリング
- 既存 `.github` の Oracle ワークフロー全体の再設計

## 3. 目標構成

### 3.1 バックエンド本体

既存の `DailyReportController` と `DailyReportService` を、次のユースケース単位へ分割する。

| ユースケース | Controller | Service | 主な責務 |
| --- | --- | --- | --- |
| 検索・詳細 | `DailyReportSearchController` | `DailyReportSearchService` | 日付・権限制約付き一覧検索、詳細取得 |
| 登録・更新 | `DailyReportCommandController` | `DailyReportCommandService` | 入力計算、重複確認、登録、編集 |
| 提出・再提出 | `DailyReportSubmissionController` | `DailyReportSubmissionService` | 状態確認、保存済みデータ再検証、提出状態遷移 |

Entity、DTO、Repository、`TimeRules`、承認状態、共通例外処理は現状の責務を維持する。複数 Service にまたがる社員限定操作や詳細参照可否の判定は、重複を避けるため日報機能内の認可共通部品へ切り出す。ただし、共通部品には機能固有の処理だけを置き、汎用化しすぎない。

Controller の URL マッピングは分割前後で同一とする。各 Service の `@Transactional` / `@Transactional(readOnly = true)` の意味も維持し、トランザクション境界を Controller や Entity へ移さない。

### 3.2 バックエンドテスト

既存 `DailyReportControllerTest` のテストメソッドと検証内容を変更せず、主目的に応じて次へ移動する。

| テストクラス | 対象 |
| --- | --- |
| `DailyReportSearchControllerTest` | 検索、詳細、検索条件、ロール別参照範囲、並び順 |
| `DailyReportCommandControllerTest` | 登録、更新、入力検証、重複、CSRF、編集可能状態 |
| `DailyReportSubmissionControllerTest` | 提出、再提出、提出可能状態、保存済みデータ再検証 |
| `MasterControllerTest` | マスタ API のログイン要求とマスタ取得 |

各テストクラスは必要な `@SpringBootTest`、`@AutoConfigureMockMvc`、`@ActiveProfiles("test")`、日報テーブル初期化を維持する。ログイン、JSON生成、日報シードなど複数テストクラスで共通する準備処理は `src/test` 配下のテスト補助へ移し、テスト本体のアサーションは極力そのまま残す。

### 3.3 フロントエンドテスト

`frontend/src/dailyReport/dailyReportSearch.test.ts` を `frontend/test/dailyReportSearch.test.ts` へ移動する。テストケース、期待値、describe/test 名は維持し、実装ファイルへの相対 import のみ移動後の配置に合わせて変更する。

## 4. 依存関係とデータフロー

```text
HTTP request
  -> use-case Controller
  -> use-case Service
  -> shared authorization / TimeRules / master repository
  -> DailyReportRepository / Entity
  -> existing DTO response
```

- 検索 Controller は検索 Service だけを呼び出す。
- 登録・更新 Controller は command Service だけを呼び出す。
- 提出 Controller は submission Service だけを呼び出す。
- 既存の API URL は重複させず、各 Controller が異なる HTTP メソッドまたはパスを担当する。
- 共通処理の抽出によって認証認可、CSRF、入力検証、DB更新順序を変更しない。

## 5. 再発防止

次の二段構えで再発を防ぐ。

1. 標準化資料へ配置と分割ルールを追記する。
   - `frontend/src` に `*.test.*` / `*.spec.*` を置かない。
   - `backend/src/main` にテストクラスを置かない。
   - Controller、Service、テストはユースケース単位で分け、複数機能のテストを一つのクラスへ継続追加しない。
2. 本体配下へテストファイルが戻った場合に失敗するレイアウトチェックを追加し、フロントテストの実行前から検出できるようにする。

実装前確認と実装後レビューにも同じ観点を追加し、構造上の再発とレビュー漏れの両方を防ぐ。

既存 `.github/workflows/oracle.yml` は別の品質ハーネス入口 `scripts/check.ps1` を呼び出す構成であり、その入口は今回の作業開始時点では存在しない。今回のレイアウトチェックは実在する PowerShell スクリプトとフロントテスト前処理へ接続し、Oracle ワークフローの再設計は別作業として扱う。

## 6. 受入条件

- 既存の API URL とレスポンス契約が変わらない。
- 既存テストの検証内容を維持したまま、テストクラスがユースケース単位に分かれている。
- フロントの機能コードとテストコードが別ディレクトリに分かれている。
- 検索・登録更新・提出の本体コードが別 Controller / Service に分かれている。
- 認証認可、CSRF、入力検証、状態遷移、DB更新の既存挙動が回帰しない。
- フロント単体テスト、型チェック、ビルド、バックエンド通常テストを実行する。
- レイアウトチェックが成功し、誤配置を検出できることを確認する。
- 作業記録と `日報登録編集_指摘一覧.md` に変更内容、指摘、対応状況、未実行確認を記録する。

## 7. 外部ドキュメント確認

- [Spring MVC Handler Methods](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-controller/ann-methods.html)
- [Spring Framework Using `@Transactional`](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/annotations.html)
- [Vitest Configuration](https://vitest.dev/config/)

公式資料で確認した Controller のハンドラ分割、Service の公開メソッド単位のトランザクション、Vitest のテスト対象・除外設定を実装判断の前提とする。
