# ログイン機能 Oracle 接続手順

## 前提

- Oracle 接続先: `jdbc:oracle:thin:@//localhost:1521/ORCL`
- ユーザー: `DAILY_REPORT_TEST`
- パスワード: 環境変数 `DAILY_REPORT_DB_PASSWORD` に設定する
- Spring プロファイル: 通常テストは `test`、Oracle 個別確認は `oracle-test`

## テーブル作成

先に、管理者ユーザーで `DAILY_REPORT_TEST` にログインとテーブル作成権限を付与する。
`ORA-01045: ユーザーDAILY_REPORT_TESTにはCREATE SESSION権限がありません` が出る場合は、この権限付与が不足している。

```sql
GRANT CREATE SESSION TO DAILY_REPORT_TEST;
GRANT CREATE TABLE TO DAILY_REPORT_TEST;
GRANT CREATE SEQUENCE TO DAILY_REPORT_TEST;
ALTER USER DAILY_REPORT_TEST QUOTA UNLIMITED ON USERS;
```

SQL*Plus などで `DAILY_REPORT_TEST` として接続する。

```powershell
sqlplus DAILY_REPORT_TEST/"<password>"@//localhost:1521/ORCL
```

ログイン機能と日報登録・編集機能に必要なテーブルを作成する。

```sql
@backend/src/main/resources/db/oracle/schema-login.sql
```

既に `users` テーブルだけ作成済みの環境へ日報テーブルを追加する場合は、以下の差分DDLを実行する。

```sql
@backend/src/main/resources/db/oracle/schema-daily-report.sql
```

作り直す場合は、先に以下を実行する。

```sql
@backend/src/main/resources/db/oracle/drop-login.sql
```

## アプリケーション接続

Oracle テスト用プロファイルを指定して起動またはテストする。

```powershell
cd backend
$env:DAILY_REPORT_DB_USER='DAILY_REPORT_TEST'
$env:DAILY_REPORT_DB_PASSWORD='<password>'
$env:SESSION_COOKIE_SECURE='false'
mvn test
```

通常のバックエンド自動テストは `test` プロファイルで Oracle 実機を利用する。
Oracle 接続情報は `DAILY_REPORT_DB_URL`、`DAILY_REPORT_DB_USER`、`DAILY_REPORT_DB_PASSWORD` で指定する。

この環境では、権限付与後に `schema-login.sql` の実行と `AuthControllerOracleIT` によるログイン確認が成功した。

## 初期データ

`oracle-test` プロファイルでは、アプリ起動時に以下のログインユーザーを `users` テーブルへ投入する。
既に `users` テーブルに1件以上存在する場合は投入しない。

| ログインID | パスワード | ロール |
| --- | --- | --- |
| `employee001` | `password` | `EMPLOYEE` |
| `manager001` | `password` | `MANAGER` |
| `admin001` | `password` | `ADMIN` |

## ユーザテスト用データ

ユーザテスト用の確認ユーザーを追加する場合は、以下を実行する。

```powershell
sqlplus DAILY_REPORT_TEST/"<password>"@ORCL @backend/src/main/resources/db/oracle/seed-user-test.sql
```

| ログインID | パスワード | ロール | 備考 |
| --- | --- | --- | --- |
| `employee901` | `password` | `EMPLOYEE` | 日報登録・編集画面のユーザテスト用 |
