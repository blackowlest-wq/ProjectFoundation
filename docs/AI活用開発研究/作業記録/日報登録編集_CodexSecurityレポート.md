# 日報登録編集 Codex Security レポート

## 概要

- 実施日: 2026-07-05
- 対象: ProjectFoundation
- Codex SecurityスキャンID:
  - 初回: `906e860c-56e3-4214-9f99-2ebd7027f96c`
  - 再スキャン: `d31ba863-6607-405e-a5be-0c177b6e3bc1`
- モード: standard
- 重点確認: ログイン画面、日報登録画面、認証、認可、所有者チェック、CSRF、セッション、入力検証、エラー時の情報露出

## Threat Model

本アプリは社内向けの日報管理Webアプリであり、Spring Bootバックエンド、React/TypeScriptフロントエンド、Oracle Databaseを利用する。守るべき主な資産は、認証済みセッション、CSRFトークン、利用者ID/ロール、パスワードハッシュ、日報ヘッダ、日報明細、勤務時間、備考、承認状態、監査項目である。

主な信頼境界は、ブラウザとバックエンドAPIの境界、バックエンドとOracle Databaseの境界、社員・上長・管理者のロール境界である。攻撃者が制御できる入力は、ログインID、パスワード、日報登録JSON、`reportId` パス変数、Cookie付きリクエスト、備考などの自由入力値である。

重要な不変条件は以下である。

- 未認証利用者は業務APIを利用できない。
- 社員は自分の日報のみ登録、編集、提出、再提出、参照できる。
- 上長は承認対象グループの日報のみ参照、承認、差戻しできる。
- 管理者は全社員の日報を参照できるが、社員向け変更操作は行わない。
- Cookieセッションを利用する状態変更APIはCSRF対策を行う。
- フロントエンドの表示制御ではなく、バックエンドで認証認可と入力検証を完結させる。

## 確認結果

### 確認できた防御

- `SecurityConfig` は `/api/auth/login` 以外を認証必須にしている。
- CSRFは `CookieCsrfTokenRepository.withHttpOnlyFalse()` と `X-XSRF-TOKEN` ヘッダー方式で構成され、日報登録、更新、提出、再提出、ログアウトはCSRF対象である。
- `AuthController` はログイン成功時に `request.changeSessionId()` を呼び、セッション固定攻撃を抑止している。
- `PasswordEncoder` は `BCryptPasswordEncoder` である。
- `application.yml` はセッションCookieに `http-only: true`、`same-site: strict`、本番既定で `secure: true` を設定している。
- `CurrentUserResponse` は `passwordHash` を返さない。
- `ApiExceptionHandler` は認証失敗時にログインID存在有無を区別しないメッセージを返す。
- 日報登録、更新、提出、再提出は `requireEmployee()` により社員ロールへ限定されている。
- 日報更新、提出、再提出は `findByReportIdAndEmployeeUserId()` により本人の日報だけを対象にしている。
- 日報登録時はリクエストに社員IDを持たせず、認証済み利用者から社員情報をスナップショットしている。
- 勤務時刻、休日区分、作業明細、作業時間合計、保存済み日報の整合性はバックエンドで検証されている。
- Oracle DDLには同一社員・同一日付の一意制約と承認状態CHECK制約がある。

## 検出事項

### DR-S-003: 上長が承認対象外の日報詳細を参照できる

- 重要度: Medium
- 分類: 認可 / IDOR
- 対象:
  - `backend/src/main/java/com/example/dailyreport/report/controller/DailyReportController.java`
  - `backend/src/main/java/com/example/dailyreport/report/DailyReportService.java`

#### 内容

`GET /api/daily-reports/{reportId}` は認証済み利用者なら到達できる。`DailyReportService#get` は社員の場合だけ `report.employeeUserId == loginUser.userId` を確認しているが、上長については承認対象グループに属する日報かどうかを確認していない。

そのため、ログイン済み上長が承認対象外の日報IDを知っている、または推測・漏えいした場合に、範囲外の日報詳細を取得できる。日報詳細には社員名、所属、勤務時間、作業明細、備考、承認状態などが含まれるため、社内利用想定でも個人・勤務情報の不適切な参照になる。

#### 根拠

- 仕様:
  - `docs/AI活用開発研究/サンプル設計書/非機能要件.md` の `NF-AUTHZ-002` は、上長は承認対象グループの日報のみ参照できるとしている。
  - `docs/AI活用開発研究/サンプル設計書/画面設計.md` の日報詳細画面は、上長が承認対象グループの日報のみ参照できるとしている。
  - `docs/AI活用開発研究/サンプル設計書/機能一覧・受入条件.md` のF-005は、権限外の日報詳細を参照できないとしている。
- 実装:
  - `DailyReportController#get` は `reportId` と `AuthenticatedUser` を `DailyReportService#get` に渡す。
  - `DailyReportService#get` は社員だけ所有者チェックを行い、上長と管理者は追加条件なしで `DailyReportResponse.from(report, ...)` に進む。
  - コメントでも「上長・管理者向けの範囲制御は承認機能側で拡張する想定」となっており、現時点の実装では未完了である。
- テスト:
  - `DailyReportControllerTest` には上長が日報を作成できないテストや社員の正常参照テストはあるが、上長が承認対象外の日報詳細を参照できないことを確認するテストは見当たらない。

#### Attack Path

1. 上長ロールの利用者が通常ログインする。
2. 攻撃者が承認対象外の日報IDを入手する。例: URL共有、ログ、画面遷移、推測、別経路の一覧漏えいなど。
3. `GET /api/daily-reports/{reportId}` を送信する。
4. Spring Securityは認証済みのためリクエストを通す。
5. `DailyReportService#get` は上長に対して承認対象グループ制限を行わず、対象日報詳細を返す。

#### Severity

上長としてログイン済みであること、日報IDを知る必要があることからCritical/Highではない。一方で、ロール境界を越えて勤務実績・備考・作業明細などを参照できるため、単なる表示不備ではなく認可不備としてMedium相当である。

#### 修正案

- `DailyReportService#get` でロール別に参照可否を判定する。
- 社員は従来通り本人日報のみ許可する。
- 上長は承認対象グループの日報のみ許可する。承認対象グループの管理データが未実装なら、実装されるまで上長の日報詳細参照を403にするか、仕様上許可する範囲を明示した暫定チェックを置く。
- 管理者は全社員の日報参照を許可する。
- `DailyReportControllerTest` に以下を追加する。
  - 上長が承認対象外の日報詳細を取得すると403。
  - 上長が承認対象内の日報詳細を取得できる。
  - 管理者は日報詳細を取得できる。

## 抑止または低リスクと判断した項目

- ログインAPIのCSRF除外は、ログイン前にCSRFトークンを取得できない設計上の例外であり、ログイン成功後の変更系APIはCSRF対象のため、今回の範囲では単独の指摘にしない。
- ログアウトCSRFはテストで確認されており、ログアウト自体も高影響操作ではないため追加指摘なし。
- SQLインジェクションは、確認範囲ではJPA Repositoryまたは `JdbcTemplate` のプレースホルダを利用しており、文字列連結によるクエリ組み立ては見当たらない。
- XSSは、Reactの通常レンダリングを前提にHTMLとして直接挿入する箇所は確認範囲で見当たらない。
- Cookieの `Secure` は本番既定で `true`、テストプロファイルでは `false` であり、環境依存確認事項として既存の `DR-S-004` に残す。

## 検証

- Codex Security preflight: ready
- 実行コマンド:
  - `python ...\\config_preflight.py --profile security_scan ...`
  - `mvn.cmd -s local-maven-settings.xml -o '-Dtest=AuthControllerTest,DailyReportControllerTest' test`
- Codex Security完了処理:
  - 初回スキャンは、レポート作成によりスキャン開始後のディレクトリ内容が変わったため完了不可。
  - 再スキャンは `scan-manifest.json` がscanDirに存在せず完了不可。
  - scanDirはいずれもサンドボックス外の一時領域であり、当該artifact bundleをこの作業環境から生成できなかった。
  - 再スキャンscanDirの一覧取得も `Access denied` になり、現在のサンドボックスからはCodex Securityの期待するartifactを配置できない。
- バックエンド対象テスト結果:
  - `ORA-01017` によりSpringコンテキスト起動前に失敗。
  - DB認証情報が現在の実行環境で無効なため、動的再現テストは未完了。
  - ただし、検出事項は仕様、ルーティング、サービス層分岐、既存テスト範囲から静的に確認できる。

## 記録

- 指摘一覧: `docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md` の `DR-S-003`
- 作業記録: `docs/AI活用開発研究/作業記録/日報登録編集_作業記録.md`

## 残課題

- `DR-S-003` の修正。
- DB認証情報を再設定したうえで、`AuthControllerTest` と `DailyReportControllerTest` を再実行する。
- Codex SecurityのscanDirがサンドボックス外の一時領域であったため、Codex Securityアプリ側のartifact seal/completeは未完了。アプリ側の完了状態が必要な場合は、scanDirへartifactを書ける実行環境で再スキャンする。
