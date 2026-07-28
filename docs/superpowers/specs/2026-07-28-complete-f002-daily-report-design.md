# F-002 日報登録画面 完成設計

**作成日:** 2026-07-28

**開発モード:** 品質重視モード
**設計承認:** ユーザー承認済み。手順の追加レビューは省略し、承認済み設計から計画・実装へ進む。

## 目的

F-002 日報登録画面について、未実行のBackend確認を実行し、正本レビューで不足と判定されたケースを追加し、Backend JaCoCoの4指標を85%以上へ到達させる。実行結果は受入条件、正本テストケース、品質確認画面、作業記録、指摘一覧へ追跡可能な形で反映する。

## 対象範囲

- F-002 日報登録の登録API、勤務時間計算、休日区分別入力検証、認証主体による所有者固定。
- F-002の正本ケースで未実行となっている複数明細、作業時間1分、休日作業あり。
- 受入条件レビューで不足と判定されたAPI応答確認、AM_OFF/PM_OFFの入力ルール、別社員seedを用いた認証主体確認。
- Backend Unit、Backend Coverage、Oracle実機確認、必要なBackend/Oracle E2E。
- F-002品質レポートの実行結果、カバレッジ、品質ゲート、証跡の更新。

## 対象外

- F-003日報編集、F-006日報提出、F-009日報再提出の固有機能変更。
- F-008差戻し機能を前提とする提出・差戻し・再提出の完全E2E。
- AM_OFF/PM_OFFの半日休暇による勤務時間短縮値。仕様資料に期待値がないため、現行マスタ契約に基づく入力可否・合計一致だけを確認する。
- Oracle環境、認証情報、CI runnerの構成変更。

## 完了条件

1. F-002の未実行Backendケースが実テストIDと実行証跡へ紐付く。
2. 複数明細、1分、休日作業あり、AM_OFF/PM_OFF、認証主体固定、勤務時間内訳APIの不足ケースが正本ケースへ追加または既存ケースへ明示的に対応付く。
3. Backend Coverageで `INSTRUCTION`、`BRANCH`、`METHOD`、`LINE` が各85%以上となり、JaCoCo XML、HTML、CSV、`jacoco.exec` が生成される。
4. Backend Unit、Backend Coverage、対象E2Eを実行し、未実行項目は成功扱いにしない。
5. F-002品質レポートのBackend品質ゲートが、実行結果とカバレッジに基づく状態へ更新される。
6. 作業記録と指摘一覧に、対応ファイル、実行コマンド、未解決事項、標準化判定が記録される。

## アーキテクチャと責務

### Backend APIテスト

`backend/src/test/java/com/example/dailyreport/report/DailyReportCommandControllerTest.java`を日報登録Command APIの正本テストファイルとして維持する。追加ケースは同じ登録責務に属するため、別ファイルへ分割しない。

### テストデータとJSON生成

`backend/src/test/java/com/example/dailyreport/report/support/DailyReportTestSupport.java`に複数明細を指定できるJSON生成ヘルパーを追加する。テストは固定日付・固定明細・観測可能なAPIレスポンスとDB所有者を使用する。

`backend/src/main/java/com/example/dailyreport/config/DataInitializer.java`には、別勤務設定を持つ2人目の社員を追加する。既存ユーザーを上書きせず、不足時だけseedする既存契約を維持する。

### 業務ルールテスト

JaCoCo XMLで未通過分岐を確認し、F-002の休日区分、作業明細、時刻境界、勤務区分内訳に対応する分岐だけを`TimeRulesTest`へ追加する。別機能の未通過分岐はF-002のケースへ無理に混ぜない。

### 実行フロー

```text
正本ケース更新
  -> 失敗するBackendテスト追加
  -> 最小限のseed/helperまたは本番修正
  -> BackendUnit
  -> BackendCoverage
  -> JaCoCo未通過分岐確認と追加テスト
  -> BackendCoverage再実行
  -> E2EOracle（環境条件が成立する場合）
  -> F-002品質レポート・作業記録更新
```

## 追加・補完ケース

新規ケースIDは既存の`TC-F002-BE-001`～`TC-F002-BE-017`と重複させない。実テストIDは`RT-F002-BE-*`名前空間を使用する。

| ケースID | 実テストID | 確認内容 | 期待結果 | テスト層 |
| --- | --- | --- | --- | --- |
| TC-F002-BE-018 | RT-F002-BE-011 | 複数作業明細を登録する | 明細の順序、各明細、合計480分、DRAFTを確認 | Backend Unit/Oracle |
| TC-F002-BE-019 | RT-F002-BE-012 | 作業時間1分を登録する | 09:00～09:01、作業1分が201で登録され、詳細の合計も1分 | Backend Unit/Oracle |
| TC-F002-BE-020 | RT-F002-BE-013 | 休日かつ作業明細ありを登録する | 休日、勤務時刻、作業合計60分が201で登録される | Backend Unit/Oracle |
| TC-F002-BE-021 | RT-F002-BE-014 | AM_OFFを登録する | 現行マスタ契約に従い、勤務時刻・明細あり・合計一致で201 | Backend Unit/Oracle |
| TC-F002-BE-022 | RT-F002-BE-015 | PM_OFFを登録する | 現行マスタ契約に従い、勤務時刻・明細あり・合計一致で201 | Backend Unit/Oracle |
| TC-F002-BE-023 | RT-F002-BE-016 | 別勤務設定社員の登録応答を確認する | 認証主体の社員スナップショット、通常・残業・深夜内訳を詳細APIで確認 | Backend Unit/Oracle |
| TC-F002-BE-024 | RT-F002-BE-017 | クライアントが別社員識別子を送っても所有者を変更できない | 保存された所有者は認証主体のままである | Backend Unit/Oracle |

`TC-F002-BE-024`は、現在のAPI DTOに社員識別子を正式な入力項目として追加するものではない。追加フィールドを含む要求を受けても、Serviceが`AuthenticatedUser`から所有者を設定する既存契約を確認する。

## トレーサビリティ

| 受入条件 | ケース | 実テスト | 記録 |
| --- | --- | --- | --- |
| F-002-AC-003 | TC-F002-BE-023 | RT-F002-BE-016 | F-002品質レポート、Backend JaCoCo、Oracle結果 |
| F-002-AC-005 | TC-F002-BE-018 | RT-F002-BE-011 | F-002品質レポート、API/DB応答 |
| F-002-AC-006 | TC-F002-BE-019 | RT-F002-BE-012 | F-002品質レポート、API/DB応答 |
| F-002-AC-008 | TC-F002-BE-020 | RT-F002-BE-013 | F-002品質レポート、API/DB応答 |
| F-002-AC-017 | TC-F002-BE-023～024 | RT-F002-BE-016～017 | F-002品質レポート、所有者確認 |
| F-002-AC-019 | TC-F002-E2E-001～003 | 既存RT-F002-E2E-001～003 | Mock E2Eおよび対象E2E記録 |

AM_OFF/PM_OFFは現行F-002受入条件に独立IDがないため、実装前レビュー指摘`DR-T-001`と品質観点`VP-F002-BOUNDARY`へ対応付け、期待値を新しい受入条件として推測追加しない。

## セキュリティとデータ整合性

- 登録対象社員はリクエストから取得せず、`AuthenticatedUser`から固定する。
- CSRF、社員ロール、マスタ存在、時刻、作業明細、合計一致の既存検証を維持する。
- テストではDB上の`employee_user_id`、`employee_id`、`employee_name`を観測し、画面入力値だけで所有者判定を完了しない。
- Oracle実行は`backend/scripts/test-oracle.cmd`を共通入口とし、期待DB名・サービス名・セッションユーザー検証を維持する。
- 秘密値、接続情報、Oracleパスワードを作業記録や生成レポートへ出力しない。

## 品質ゲートと実行可否

| ゲート | コマンド | 完了条件 | 未実行時の扱い |
| --- | --- | --- | --- |
| Backend Unit | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1 -CiTask BackendUnit` | Oracle不要のBackend単体テスト成功 | 未実行理由と再確認条件を記録 |
| Backend Coverage | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1 -CiTask BackendCoverage` | Oracle実行、JaCoCo成果物、4指標85%以上 | 成功扱いにせず保留 |
| E2E Oracle | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1 -CiTask E2EOracle` | 実Backend、Oracle、Frontendの登録・再読込確認 | Oracle環境条件と再確認条件を記録 |
| Full | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check.ps1 -Mode Full` | Frontend/Backend/契約テスト成功 | 失敗を修正前提で扱う |

## 記録更新

- 正本ケース: `docs/AI活用開発研究/作業記録/日報登録編集_テストケース.md`
- 受入条件レビュー: `docs/AI活用開発研究/作業記録/日報登録編集_受入条件レビュー.md`
- 指摘一覧: `docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md`
- 品質確認画面の検証記録: `docs/AI活用開発研究/作業記録/コード品質確認画面_検証記録.md`
- F-002品質データ・HTML: `docs/AI活用開発研究/コード品質確認画面/F-002_日報登録/`
- 作業記録: 必要に応じてF-002完成作業の実行結果を追記する。

指摘ごとに、`個別対応`、`既存観点で対応`、`標準化候補`、`対象外`、`保留`のいずれかを判定する。今回の追加ケースは、既存の境界値・業務ルール・認証主体固定観点で横展開可能かを確認する。
