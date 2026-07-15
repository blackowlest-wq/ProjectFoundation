# ロガー・実Backend Oracle E2E強化 設計書

## 背景

現在のBackendはSpring Bootの既定コンソールログに依存しており、アプリケーション固有のLogger、リクエスト単位の相関ID、業務エラーとシステムエラーの記録方針がない。
`ApiExceptionHandler`はエラーをAPIレスポンスへ変換するが、どの機能・処理で発生したかをログから追跡できない。想定外例外も共通の500レスポンスと相関IDへ統一されていない。

既存のPlaywright E2EはAPIをモックしているため、画面とFrontendの操作は確認できるが、実BackendとOracleへの接続、トランザクション完了、再読込後の永続化までは確認できない。

Spring Bootの既定ログはコンソール出力が中心で、ログレベル、ファイル出力、ローテーションを設定で制御できる。既存の`spring-boot-starter-web`によりLogging基盤は利用できるため、今回の第一段階では新たな集中ログ製品やOpenTelemetryを追加しない。

## 目的

- どのリクエストが、どの機能・ユースケースで、いつ、何秒で、どの結果になったかを追跡できるようにする。
- 業務エラーは利用者向けレスポンスと調査用ログを分離し、処理が想定どおり拒否されて終了したことを確認できるようにする。
- 想定外例外はスタックトレースをログだけへ残し、利用者へは内部情報を返さない共通500レスポンスへ統一する。
- 本番ではログレベルにより通常リクエストの詳細を抑制し、E2E・検証環境では処理経路を追えるようにする。
- 実Backend＋Oracleを接続したE2Eで、登録・提出・再読込後の永続化を確認する。
- E2E失敗時にPlaywright成果物とBackendログを同じ検証結果として回収できるようにする。

## 対象範囲

### 対象

- Backendの相関ID、リクエスト完了ログ、業務エラー・システムエラーログ
- 共通エラーレスポンスへの`requestId`追加
- 認証失敗、認可拒否、CSRF拒否のログと共通エラー応答
- 本番、通常テスト、Oracle E2Eでのログレベル設定
- 既存のモックE2Eを維持したうえでの実Backend＋Oracle E2E
- Oracle E2Eの起動、ヘルスチェック、テストデータ準備、後始末、ログ成果物回収
- ログ機密情報対策、ログ契約テスト、作業記録・指摘一覧・標準資料の更新

### 対象外

- OpenTelemetry、分散トレーシング基盤、外部ログ収集製品の導入
- 全SQL、リクエスト本文、レスポンス本文の常時ログ出力
- 本番DBや本番相当ユーザーを使うE2E
- ログを業務監査証跡として長期保存するための保管基盤設計
- 既存業務仕様やAPIの成功・失敗ルール自体の変更

## 用語とログレベル

| レベル | 通常の本番出力 | E2E・検証環境 |
| --- | --- | --- |
| `ERROR` | 想定外例外、DB接続障害、処理不能 | 出力する |
| `WARN` | 認可拒否、CSRF拒否、異常に遅い処理 | 出力する |
| `INFO` | ログイン、登録、更新、提出など重要な業務結果 | 重要業務とエラーを出力する |
| `DEBUG` | 全リクエストの開始・完了、検索、マスタ取得、詳細時間 | 出力する |
| `TRACE` | 使用しない | 使用しない |

通常の本番では、全リクエスト完了ログを`DEBUG`へ置く。登録・更新・提出・ログインなど、調査上重要な状態変更の成功結果は`INFO`で残す。業務上想定された4xxはコードと結果を記録し、認証・認可・CSRFに関する拒否は`WARN`とする。

ログレベルは、`logging.level.<logger-name>`、Spring Profile、環境変数のいずれからも変更できる構成にする。E2Eでは専用Profileでリクエスト完了ログを`DEBUG`へ上げ、本番設定へ詳細ログを持ち込まない。

## 設計

### 1. リクエスト相関ID

Backendの最上位Filterで、各HTTPリクエストにUUID形式の`requestId`を生成する。

- MDCへ`requestId`を設定する。
- レスポンスヘッダー`X-Request-Id`へ同じ値を設定する。
- エラーレスポンスのJSONにも`requestId`を含める。
- Filterの`finally`でMDCを必ず削除し、スレッドプール間の値の漏洩を防ぐ。
- クライアントから渡された任意の相関IDは信頼せず、第一段階ではBackend生成値を正とする。

FilterはSpring Securityを含むリクエスト全体を対象にし、認証前の拒否でも相関IDが残るようにする。リクエスト完了ログには、Filterで測定したHTTP処理全体の経過時間を`durationMs`で記録する。MDCの`requestId`は、ログパターンからも確認できるようにする。

### 2. リクエストログ

通常の全リクエストについて、開始と完了を次の構造で記録する。開始ログは`DEBUG`、完了ログは成功時`DEBUG`、遅延・拒否・失敗時はログ方針に従って`WARN`以上へ昇格する。

```text
event=request.started
requestId=<uuid>
method=POST
path=/api/daily-reports/{reportId}/submit
```

```text
event=request.completed
requestId=<uuid>
feature=DAILY_REPORT
useCase=SUBMIT
method=POST
path=/api/daily-reports/{reportId}/submit
status=200
durationMs=84
```

`feature`と`useCase`は、HandlerMethodを参照するInterceptorでControllerの公開メソッドから解決し、クラス単位の機能マッピングを固定する。Filterだけで判定できない拒否リクエストは、利用可能な範囲でパスとセキュリティイベントを記録する。

### 3. 業務イベントログ

内部メソッドをすべてログ出力せず、状態変更を伴う公開ユースケースの完了結果だけを明示する。

| feature | useCase | 成功ログ | 主な失敗ログ |
| --- | --- | --- | --- |
| `AUTH` | `LOGIN` / `LOGOUT` | 認証状態の変更結果 | 認証失敗、CSRF拒否 |
| `DAILY_REPORT` | `CREATE` / `UPDATE` | 日報ID、状態、経過時間 | 入力、重複、状態、認可 |
| `DAILY_REPORT` | `SUBMIT` / `RESUBMIT` | 日報ID、遷移後状態、経過時間 | 状態、認可、再検証 |
| `DAILY_REPORT` | `SEARCH` / `GET` | 必要に応じて`DEBUG` | 入力、認可、DB障害 |
| `MASTER` | マスタ取得 | 原則`DEBUG` | DB障害 |

成功ログはサービス処理が正常に戻り、Controllerが成功レスポンスを組み立てられる位置で出力する。`@Transactional`サービスの呼び出し元へ戻った後に記録し、トランザクション境界を越えた後のHTTP完了ログを最終判定とする。DBコミット失敗時に成功ログだけが残る構成にしない。成功ログの対象は状態変更を伴うControllerへ限定し、検索・マスタ取得はリクエスト完了ログへ委ねる。

業務エラーのログには、`code`、HTTPステータス、`feature`、`useCase`、`requestId`、必要最小限の利用者識別子を含める。入力値、パスワード、Cookie、CSRFトークン、個人情報、JDBC URLは含めない。

### 4. 想定外例外とセキュリティ拒否

`ApiExceptionHandler`へ想定外例外の共通処理を追加する。

- ログは`ERROR`で、例外型とメッセージを含まないスタック位置を残す。例外オブジェクト自体は渡さない。
- レスポンスコードは`INTERNAL_SERVER_ERROR`とする。
- 利用者向けメッセージは固定文言とし、SQL、クラス名、スタックトレースを返さない。
- レスポンスの`requestId`でログ検索できるようにする。

Spring Securityの認証EntryPoint、AccessDeniedHandler、CSRF拒否も、可能な範囲で同じ共通エラー形式と`requestId`を返し、拒否理由の分類だけをログへ残す。ログインIDやCookieの値は出力しない。

### 5. Frontendの扱い

FrontendはBackendの`requestId`を`ApiError`へ保持する。エラー本文が読めない場合は`X-Request-Id`ヘッダーから補完する。

通常の成功リクエストをFrontendコンソールへ出力しない。APIエラー時に必要な場合だけ、`code`、HTTPステータス、requestId、APIパスなどの安全な診断情報を出力し、リクエスト本文・認証情報は出力しない。

画面の業務メッセージは現行のAPIエラーコードに従い、ログ追加のために利用者向け文言を変更しない。

### 6. 実Backend＋Oracle E2E

既存のモックE2EはFrontendの画面・表示・API呼び出し契約の確認として維持する。別のOracle E2Eタスクを追加し、隔離されたOracle runnerでのみ実行する。

実行順は次のとおりとする。

1. Oracle環境変数、接続先、DB名、service、session userを既存安全ガードで検証する。
2. E2E専用のテストデータを準備し、対象日報の残存データを除去する。
3. Oracle ProfileでBackendを起動し、`/api/auth/me`等の安全なHTTP確認で起動完了を待つ。
4. Frontendをproduction buildし、Vite previewをBackendへのAPI proxy付きで起動する。
5. Playwrightから実ユーザーでログインする。
6. 日報を実際に登録し、下書き保存、提出、画面再読込、詳細再取得を確認する。
7. 画面上の状態だけでなく、再取得したAPIレスポンスとOracle上の状態が一致することを確認する。
8. 重複登録または不正状態操作を実行し、業務エラーのHTTPコード、画面表示、Backendログを確認する。
9. Backendログ、Oracle保存確認、Playwright HTMLレポートを成果物として回収する。実ログインを含むためtrace/video/screenshotは保存しない。
10. Backend、Frontend、Browserを確実に終了し、テストデータを後始末する。

DB停止などの破壊的なシステム障害を実Oracle E2Eで発生させない。想定外例外の500応答とスタックトレース記録は、テスト専用Controllerを本番へ追加せず、MockMvcのテスト用Controllerと共通Adviceで検証する。

Oracle E2Eは秘密情報を扱うため、PRでself-hosted runner上の任意コードを実行しない。既存Oracle workflowと同じく、mainへの反映後または手動実行を基本とする。

### 7. ログ成果物と運用

アプリケーション本体は環境依存のログファイルパスを固定せず、標準出力を基本とする。E2EランナーがBackendの標準出力・標準エラーを安全な作業用ログへリダイレクトし、失敗時も成果物として回収する。

本番でファイル出力を採用する場合は、デプロイ環境側でファイル名、最大サイズ、保持世代、集約先を設定する。アプリケーションのログレベル設定とログの長期保管・監査要件を混同しない。

## テスト設計

### Backend

- Filterがレスポンスへ`X-Request-Id`を付与する。
- 同一リクエストのレスポンスJSONとログでrequestIdが一致する。
- 業務エラーがコード、ステータス、feature、useCase、requestId付きで記録される。
- 想定外例外が共通500レスポンスになり、ログには例外型と安全なスタック位置、レスポンスには内部情報がない。
- 認証失敗、認可拒否、CSRF拒否で機密値がログへ出ない。
- 成功した登録・更新・提出では、結果状態と経過時間がログへ残る。
- ログレベル設定により、通常本番ではリクエスト詳細が抑制され、E2E Profileでは出力される。

ログ出力契約の確認には、Spring Boot testの`OutputCaptureExtension`またはテスト用Appenderを使用する。ログ文字列全体を過度に固定せず、イベント名、requestId、状態、機密情報非出力などの契約を確認する。

### Frontend

- 空本文、非JSON本文、401、4xx、5xxで`ApiError.requestId`が安全に補完される。
- 画面エラー表示が既存の業務エラーコードを維持する。
- API失敗時の診断ログにパスワード、Cookie、CSRF値、リクエスト本文が含まれない。

### E2E

- 既存モックE2Eが回帰しない。
- 実Oracle E2Eでログインから日報提出、再取得まで成功する。
- 実Oracle E2Eで業務エラーが想定されたHTTPコード・画面表示になる。
- E2EのAPI通信に付いたrequestIdをBackendログから検索できる。
- Backend停止、Oracle設定不足、起動タイムアウトを、通常のテスト失敗と区別して報告する。

## 品質ゲートと成果物

- `Full`: Frontend lint、型チェック、単体テスト、build、Backend静的解析を実行する。
- `FrontendCoverage`: 既存Frontendカバレッジを実行する。
- `E2E`: 既存モックE2Eを実行する。
- `E2EOracle`: 隔離Oracle runnerで実Backend＋Oracle E2Eを実行する。
- `Oracle`: 既存Backend Oracle統合テストを実行する。

`E2EOracle`はOracle接続情報とテストデータを扱うため、既存のOracle workflowへ追加し、Backendログ、Oracle検証結果、Playwrightレポートを`always()`条件でアップロードする。生成ログ、coverage、Playwright成果物、Oracle設定はGitへ追加しない。

## 代替案と採用理由

- 全リクエストを本番`INFO`で出す方式: 数百人規模では検索・マスタ取得のログが過剰になるため採用しない。
- リクエスト本文とSQLを常時出す方式: 機密情報とログ量のリスクが高いため採用しない。
- ログだけで機能動作を判定する方式: ログ欠落や出力先障害でもテストが成功するため、APIレスポンス、DB状態、画面結果を主判定とし、ログは追跡補助にする。
- OpenTelemetryを第一段階で導入する方式: 現在の単一BackendとOracle E2Eの目的に対して依存・運用範囲が大きいため、将来の分散構成で再評価する。
- 既存モックE2Eを実Backend E2Eへ置換する方式: Frontendの高速回帰確認とOracle依存の統合確認を分離できなくなるため採用しない。

## 受入条件

1. Backendの成功・業務エラー・想定外エラーを、requestId、feature、useCase、status、durationMsで追跡できる。
2. 本番設定では通常リクエストの詳細ログを抑制し、重要な業務結果と障害情報を残せる。
3. E2E Profileでは、既存のモックE2Eと実Backend＋Oracle E2Eの双方で必要なログを確認できる。
4. 想定外例外は内部情報をレスポンスへ返さず、Backendログに例外型と安全なスタック位置を残す。
5. パスワード、Cookie、CSRFトークン、個人情報、接続文字列、SQL本文がログ成果物に出ない。
6. 実Oracle E2Eで、ログイン、日報登録、提出、再取得、業務エラーを確認できる。
7. E2E失敗時にBackendログ、Oracle検証結果、Playwrightレポートが回収される。認証情報を含み得るtrace/video/screenshotは保存されない。
8. Backend、Frontend、Oracle、品質ゲートのテスト結果と未実行理由が作業記録へ残る。
9. 指摘一覧へロガー観点の指摘、対応内容、保留事項を記録する。

## 記録方針

- 作業記録に、公式Spring資料を確認したこと、採用したログレベル方針、変更ファイル、テスト結果を記載する。
- `日報登録編集_指摘一覧.md`へ、ロガー不足、想定外例外の追跡不足、実Backend E2E不足を指摘として追加する。
- ログ成果物はテスト結果として記録し、ソース実装や永続的な監査証跡と混同しない。
- Oracle環境がない場合は、通常テストと実Oracle E2Eを分け、未実行理由と再確認条件を記録する。
