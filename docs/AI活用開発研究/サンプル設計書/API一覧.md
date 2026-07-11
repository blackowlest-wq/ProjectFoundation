# サンプルアプリ API一覧

## 目的

社内向け日報管理システムのAPI一覧を定義する。

本資料は、React + TypeScript フロントエンドと Java / Spring Boot バックエンドの接続仕様として使用する。
詳細な業務ルール、画面項目、受入条件は以下を参照する。

- スコープ定義: `スコープ定義.md`
- 機能一覧・受入条件: `機能一覧・受入条件.md`
- 画面設計: `画面設計.md`
- DB概念設計: `DB概念設計.md`
- 状態遷移・業務フロー設計: `状態遷移・業務フロー設計.md`
- 入力チェック・業務ルール一覧: `入力チェック・業務ルール一覧.md`
- 非機能要件: `非機能要件.md`
- テスト設計書: `テスト設計書.md`

## API設計方針

- APIのベースパスは `/api` とする
- 通信形式はJSONとする
- CSV出力APIのみ `text/csv` を返す
- 認証APIを除き、すべて認証済み利用者のみ利用できる
- 権限制御はバックエンドAPIで必ず行う
- 日付は `yyyy-MM-dd` 形式で扱う
- 年月は `yyyy-MM` 形式で扱う
- 時刻は `HH:mm` 形式で扱う
- 時間量は分単位の整数で扱う
- 日時はISO 8601形式で扱う
- 一覧APIはページングなしの初回サンプル仕様とする

## 共通レスポンス

### エラーレスポンス

入力エラー、権限エラー、状態遷移エラーなどは、以下の形式で返す。

```json
{
  "code": "VALIDATION_ERROR",
  "message": "入力内容に誤りがあります。",
  "details": [
    {
      "field": "workItems[0].workMinutes",
      "message": "作業時間は1分以上で入力してください。"
    }
  ]
}
```

### 主なHTTPステータス

| ステータス | 用途 |
| --- | --- |
| 200 | 取得、更新、状態変更が成功した |
| 201 | 登録が成功した |
| 204 | ログアウトが成功した |
| 400 | 入力値が不正 |
| 401 | 未認証 |
| 403 | 権限なし |
| 404 | 対象データなし |
| 409 | 状態不整合、重複登録 |

## Enum

### Role

```text
EMPLOYEE
MANAGER
ADMIN
```

### ApprovalStatus

```text
DRAFT
PENDING
REJECTED
APPROVED
```

画面・設計上の状態名との対応:

| API値 | 表示名 |
| --- | --- |
| DRAFT | 未提出 |
| PENDING | 承認待ち |
| REJECTED | 差戻し |
| APPROVED | 承認済み |

### HolidayType

```text
WORKDAY
HOLIDAY
PAID_LEAVE
AM_OFF
PM_OFF
```

画面・設計上の休日区分との対応:

| API値 | 表示名 |
| --- | --- |
| WORKDAY | 通常勤務 |
| HOLIDAY | 休日 |
| PAID_LEAVE | 有給休暇 |
| AM_OFF | 午前休 |
| PM_OFF | 午後休 |

### AggregateType

```text
EMPLOYEE_WORK
PROJECT_WORK
CATEGORY_WORK
HOLIDAY_TYPE_DAYS
```

## API一覧

| API ID | メソッド | パス | 概要 | 主な利用ロール | 対応機能 |
| --- | --- | --- | --- | --- | --- |
| A-001 | POST | `/api/auth/login` | ログインする | 社員、上長、管理者 | F-001 |
| A-002 | POST | `/api/auth/logout` | ログアウトする | 社員、上長、管理者 | F-001 |
| A-003 | GET | `/api/auth/me` | ログイン中利用者を取得する | 社員、上長、管理者 | F-001 |
| A-004 | GET | `/api/master/employees` | 社員選択肢を取得する | 社員、上長、管理者 | F-004、F-006、F-011 |
| A-005 | GET | `/api/master/projects` | 案件選択肢を取得する | 社員 | F-002、F-003 |
| A-006 | GET | `/api/master/work-categories` | 作業分類選択肢を取得する | 社員 | F-002、F-003 |
| A-007 | GET | `/api/daily-reports` | 日報を検索する | 社員、上長、管理者 | F-004 |
| A-008 | POST | `/api/daily-reports` | 日報を登録する | 社員 | F-002 |
| A-009 | GET | `/api/daily-reports/{reportId}` | 日報詳細を取得する | 社員、上長、管理者 | F-005 |
| A-010 | PUT | `/api/daily-reports/{reportId}` | 日報を編集する | 社員 | F-003 |
| A-011 | POST | `/api/daily-reports/{reportId}/submit` | 日報を提出する | 社員 | F-006 |
| A-012 | POST | `/api/daily-reports/{reportId}/approve` | 日報を承認する | 上長 | F-007 |
| A-013 | POST | `/api/daily-reports/{reportId}/reject` | 日報を差戻す | 上長 | F-008 |
| A-014 | POST | `/api/daily-reports/{reportId}/resubmit` | 日報を再提出する | 社員 | F-009 |
| A-015 | GET | `/api/daily-reports/pending-approvals` | 未承認一覧を取得する | 上長 | F-010 |
| A-016 | GET | `/api/monthly-summaries` | 月次集計を取得する | 管理者 | F-011 |
| A-017 | GET | `/api/exports/monthly-summary` | 月次集計CSVを出力する | 管理者 | F-012 |
| A-018 | GET | `/api/exports/daily-report-details` | 日報明細CSVを出力する | 管理者 | F-012 |
| A-019 | GET | `/api/master/groups` | グループ選択肢を取得する | 上長、管理者 | F-004、F-010、F-011 |
| A-020 | GET | `/api/master/holiday-types` | 休日区分選択肢を取得する | 社員、上長、管理者 | F-002、F-003、F-004 |
| A-021 | GET | `/api/master/break-types` | 休憩区分選択肢を取得する | 社員、上長、管理者 | F-002、F-003、F-005 |
| A-022 | GET | `/api/master/work-time-types` | 勤務区分選択肢を取得する | 社員、上長、管理者 | F-002、F-003、F-005 |

## A-001 ログイン

### リクエスト

```http
POST /api/auth/login
```

```json
{
  "loginId": "employee001",
  "password": "password"
}
```

### レスポンス

```json
{
  "userId": "U001",
  "loginId": "employee001",
  "userName": "山田 太郎",
  "role": "EMPLOYEE",
  "groupId": "G001",
  "groupName": "第一開発グループ",
  "breakTypeId": "BT001",
  "breakTypeName": "標準休憩",
  "workTimeTypeId": "WT001",
  "workTimeTypeName": "勤務区分A"
}
```

### 受入条件

- 有効なログインIDとパスワードでログインできる
- 無効なログインIDまたはパスワードでは `401` を返す

## A-002 ログアウト

### リクエスト

```http
POST /api/auth/logout
```

### レスポンス

```text
204 No Content
```

## A-003 ログイン中利用者取得

### リクエスト

```http
GET /api/auth/me
```

### レスポンス

```json
{
  "userId": "U001",
  "loginId": "employee001",
  "userName": "山田 太郎",
  "role": "EMPLOYEE",
  "groupId": "G001",
  "groupName": "第一開発グループ",
  "breakTypeId": "BT001",
  "breakTypeName": "標準休憩",
  "workTimeTypeId": "WT001",
  "workTimeTypeName": "勤務区分A"
}
```

## A-004 社員選択肢取得

### リクエスト

```http
GET /api/master/employees?scope=VISIBLE
```

### クエリパラメータ

| 名前 | 必須 | 内容 |
| --- | --- | --- |
| scope | 任意 | `VISIBLE` のみ。省略時も `VISIBLE` と同じ |

### レスポンス

```json
[
  {
    "employeeId": "E001",
    "employeeName": "山田 太郎",
    "groupId": "G001",
    "groupName": "第一開発グループ"
  }
]
```

### 権限制御

- 社員は自分のみ取得できる
- 上長は承認対象グループに所属する社員のみ取得できる
- 管理者は全社員を取得できる

## A-005 案件選択肢取得

### リクエスト

```http
GET /api/master/projects
```

### レスポンス

```json
[
  {
    "projectId": "P001",
    "projectName": "案件A"
  }
]
```

## A-006 作業分類選択肢取得

### リクエスト

```http
GET /api/master/work-categories
```

### レスポンス

```json
[
  {
    "workCategoryId": "WC001",
    "workCategoryName": "設計"
  }
]
```

## A-007 日報検索

### リクエスト

```http
GET /api/daily-reports?dateFrom=2026-06-01&dateTo=2026-06-30&groupId=G001&employeeId=E001&status=PENDING&holidayType=WORKDAY
```

### クエリパラメータ

| 名前 | 必須 | 内容 |
| --- | --- | --- |
| dateFrom | 任意 | 検索開始日 |
| dateTo | 任意 | 検索終了日 |
| groupId | 任意 | グループID |
| employeeId | 任意 | 社員ID |
| status | 任意 | 承認状態 |
| holidayType | 任意 | 休日区分 |

### レスポンス

```json
[
  {
    "reportId": "R001",
    "reportDate": "2026-06-01",
    "employeeId": "E001",
    "employeeName": "山田 太郎",
    "groupId": "G001",
    "groupName": "第一開発グループ",
    "holidayType": "WORKDAY",
    "startTime": "09:00",
    "endTime": "18:00",
    "breakTypeId": "BT001",
    "breakTypeName": "標準休憩",
    "workTimeTypeId": "WT001",
    "workTimeTypeName": "勤務区分A",
    "breakMinutes": 60,
    "workMinutes": 480,
    "regularWorkMinutes": 480,
    "overtimeWorkMinutes": 0,
    "nightWorkMinutes": 0,
    "workTimeDisplay": "8:00",
    "regularWorkTimeDisplay": "8:00",
    "overtimeWorkTimeDisplay": "0:00",
    "nightWorkTimeDisplay": "0:00",
    "totalWorkItemMinutes": 480,
    "approvalStatus": "PENDING",
    "submittedAt": "2026-06-01T18:10:00+09:00",
    "approverName": null,
    "approvedAt": null
  }
]
```

### 権限制御

- 社員は自分の日報のみ検索できる
- 上長は承認対象グループの日報のみ検索できる
- 管理者は全社員の日報を検索できる

## A-008 日報登録

### リクエスト

```http
POST /api/daily-reports
```

```json
{
  "reportDate": "2026-06-01",
  "holidayType": "WORKDAY",
  "startTime": "09:00",
  "endTime": "18:00",
  "remarks": "備考",
  "workItems": [
    {
      "projectId": "P001",
      "workCategoryId": "WC001",
      "workMinutes": 480
    }
  ]
}
```

### レスポンス

```text
201 Created
```

```json
{
  "reportId": "R001",
  "approvalStatus": "DRAFT"
}
```

### 受入条件

- 同一社員・同一日の日報は重複登録できない
- 登録後の承認状態は `DRAFT` とする
- 休日区分ごとの入力チェックを適用する
- 休憩時間は社員に紐づく休憩区分から自動算出し、リクエストでは受け取らない
- 通常勤務時間、残業時間、深夜時間は社員に紐づく勤務区分から自動算出し、リクエストでは受け取らない

## A-009 日報詳細取得

### リクエスト

```http
GET /api/daily-reports/{reportId}
```

### レスポンス

```json
{
  "reportId": "R001",
  "reportDate": "2026-06-01",
  "employeeId": "E001",
  "employeeName": "山田 太郎",
  "groupId": "G001",
  "groupName": "第一開発グループ",
  "holidayType": "WORKDAY",
  "startTime": "09:00",
  "endTime": "18:00",
  "breakTypeId": "BT001",
  "breakTypeName": "標準休憩",
  "workTimeTypeId": "WT001",
  "workTimeTypeName": "勤務区分A",
  "breakMinutes": 60,
  "workMinutes": 480,
  "regularWorkMinutes": 480,
  "overtimeWorkMinutes": 0,
  "nightWorkMinutes": 0,
  "workTimeDisplay": "8:00",
  "regularWorkTimeDisplay": "8:00",
  "overtimeWorkTimeDisplay": "0:00",
  "nightWorkTimeDisplay": "0:00",
  "totalWorkItemMinutes": 480,
  "remarks": "備考",
  "approvalStatus": "PENDING",
  "submittedAt": "2026-06-01T18:10:00+09:00",
  "approverId": null,
  "approverName": null,
  "approvedAt": null,
  "rejectorId": null,
  "rejectorName": null,
  "rejectedAt": null,
  "rejectComment": null,
  "workItems": [
    {
      "workItemId": "WI001",
      "projectId": "P001",
      "projectName": "案件A",
      "workCategoryId": "WC001",
      "workCategoryName": "設計",
      "workMinutes": 480
    }
  ]
}
```

## A-010 日報編集

### リクエスト

```http
PUT /api/daily-reports/{reportId}
```

リクエストボディは A-008 日報登録と同じ形式とする。

### レスポンス

```json
{
  "reportId": "R001",
  "approvalStatus": "DRAFT"
}
```

### 受入条件

- `DRAFT` または `REJECTED` の日報のみ編集できる
- 社員は自分の日報のみ編集できる
- 編集しても、承認状態は変更しない

## A-011 日報提出

### リクエスト

```http
POST /api/daily-reports/{reportId}/submit
```

### レスポンス

```json
{
  "reportId": "R001",
  "approvalStatus": "PENDING",
  "submittedAt": "2026-06-01T18:10:00+09:00"
}
```

### 受入条件

- `DRAFT` の日報のみ提出できる
- 提出後、承認状態は `PENDING` になる
- 提出日時を記録する

## A-012 日報承認

### リクエスト

```http
POST /api/daily-reports/{reportId}/approve
```

### レスポンス

```json
{
  "reportId": "R001",
  "approvalStatus": "APPROVED",
  "approverId": "M001",
  "approvedAt": "2026-06-02T09:00:00+09:00"
}
```

### 受入条件

- 上長は承認対象グループの `PENDING` の日報のみ承認できる
- 承認後、承認状態は `APPROVED` になる
- 承認者と承認日時を記録する

## A-013 日報差戻し

### リクエスト

```http
POST /api/daily-reports/{reportId}/reject
```

```json
{
  "rejectComment": "作業時間を確認してください。"
}
```

### レスポンス

```json
{
  "reportId": "R001",
  "approvalStatus": "REJECTED",
  "rejectorId": "M001",
  "rejectedAt": "2026-06-02T09:00:00+09:00",
  "rejectComment": "作業時間を確認してください。"
}
```

### 受入条件

- 上長は承認対象グループの `PENDING` の日報のみ差戻しできる
- 差戻しコメントは必須とする
- 差戻し後、承認状態は `REJECTED` になる
- 差戻し者、差戻し日時、最新差戻しコメントを記録する

## A-014 日報再提出

### リクエスト

```http
POST /api/daily-reports/{reportId}/resubmit
```

### レスポンス

```json
{
  "reportId": "R001",
  "approvalStatus": "PENDING",
  "submittedAt": "2026-06-03T18:10:00+09:00"
}
```

### 受入条件

- `REJECTED` の日報のみ再提出できる
- 再提出後、承認状態は `PENDING` になる
- 提出日時を更新する
- 最新差戻しコメントは保持する

## A-015 未承認一覧取得

### リクエスト

```http
GET /api/daily-reports/pending-approvals?dateFrom=2026-06-01&dateTo=2026-06-30&groupId=G001&employeeId=E001
```

### クエリパラメータ

| 名前 | 必須 | 内容 |
| --- | --- | --- |
| dateFrom | 任意 | 検索開始日 |
| dateTo | 任意 | 検索終了日 |
| groupId | 任意 | グループID |
| employeeId | 任意 | 社員ID |

### レスポンス

A-007 日報検索と同じ一覧形式とする。

### 受入条件

- 上長は承認対象グループの `PENDING` の日報のみ取得できる
- 承認対象グループ以外の日報は取得できない

## A-016 月次集計取得

### リクエスト

```http
GET /api/monthly-summaries?yearMonth=2026-06
```

### クエリパラメータ

| 名前 | 必須 | 内容 |
| --- | --- | --- |
| yearMonth | 必須 | 対象年月 |

### レスポンス

```json
{
  "yearMonth": "2026-06",
  "employeeWorkSummaries": [
    {
      "employeeId": "E001",
      "employeeName": "山田 太郎",
      "totalWorkMinutes": 9600
    }
  ],
  "projectWorkSummaries": [
    {
      "projectId": "P001",
      "projectName": "案件A",
      "totalWorkMinutes": 6000
    }
  ],
  "categoryWorkSummaries": [
    {
      "workCategoryId": "WC001",
      "workCategoryName": "設計",
      "totalWorkMinutes": 3000
    }
  ],
  "holidayTypeSummaries": [
    {
      "holidayType": "PAID_LEAVE",
      "totalDays": 1
    }
  ]
}
```

### 受入条件

- 管理者のみ利用できる
- `APPROVED` の日報のみ集計対象とする
- 作業時間は分単位で合計する

## A-017 月次集計CSV出力

### リクエスト

```http
GET /api/exports/monthly-summary?yearMonth=2026-06
```

### レスポンス

- Content-Type: `text/csv; charset=UTF-8`
- Content-Disposition: `attachment; filename="monthly-summary-202606.csv"`
- 本文は `スコープ定義.md` のCSV出力仕様に従い、UTF-8 BOM付きで出力する

### 受入条件

- 管理者のみ利用できる
- `APPROVED` の日報のみ出力対象とする
- 出力対象がない場合でもヘッダー行のみ出力する

## A-018 日報明細CSV出力

### リクエスト

```http
GET /api/exports/daily-report-details?yearMonth=2026-06
```

### レスポンス

- Content-Type: `text/csv; charset=UTF-8`
- Content-Disposition: `attachment; filename="daily-report-details-202606.csv"`
- 本文は `スコープ定義.md` のCSV出力仕様に従い、UTF-8 BOM付きで出力する

### 受入条件

- 管理者のみ利用できる
- `APPROVED` の日報のみ出力対象とする
- 作業明細がない休日・有給休暇の日報は1日1行で出力する
- 出力対象がない場合でもヘッダー行のみ出力する

## A-019 グループ選択肢取得

### リクエスト

```http
GET /api/master/groups?scope=VISIBLE
```

### クエリパラメータ

| 名前 | 必須 | 内容 |
| --- | --- | --- |
| scope | 任意 | `VISIBLE` のみ。省略時も `VISIBLE` と同じ |

### レスポンス

```json
[
  {
    "groupId": "G001",
    "groupName": "第一開発グループ"
  }
]
```

### 権限制御

- 上長は承認対象グループのみ取得できる
- 管理者は全グループを取得できる
- 社員は初回サンプルではグループ選択肢取得を利用しない

## A-020 休日区分選択肢取得

### リクエスト

```http
GET /api/master/holiday-types
```

### レスポンス

```json
[
  {
    "holidayType": "WORKDAY",
    "holidayTypeName": "通常勤務",
    "requiresWorkTime": true,
    "allowsWorkItems": true
  }
]
```

## A-021 休憩区分選択肢取得

### リクエスト

```http
GET /api/master/break-types
```

### レスポンス

```json
[
  {
    "breakTypeId": "BT001",
    "breakTypeName": "標準休憩",
    "breakPeriods": [
      {
        "startTime": "12:00",
        "endTime": "13:00"
      }
    ]
  }
]
```

## A-022 勤務区分選択肢取得

### リクエスト

```http
GET /api/master/work-time-types
```

### レスポンス

```json
[
  {
    "workTimeTypeId": "WT001",
    "workTimeTypeName": "勤務区分A",
    "regularStartTime": "09:00",
    "regularEndTime": "18:00",
    "nightStartTime": "22:00",
    "nightEndTime": "05:00"
  }
]
```

## API設計上の補足

- 日報登録、編集、提出、再提出では、休日区分ごとの入力チェックをバックエンドで実施する
- 日報登録、編集では、同一社員・同一日の日報重複をバックエンドで防止する
- 日報登録、編集では、休憩時間を休憩区分から自動算出し、リクエストの自由入力値として受け取らない
- 日報登録、編集では、通常勤務時間、残業時間、深夜時間を勤務区分から自動算出し、リクエストの自由入力値として受け取らない
- 状態変更APIでは、現在の承認状態、利用者ロール、承認対象グループをバックエンドで検証する
- CSVの詳細形式は `スコープ定義.md` のCSV出力仕様を正とする
- リクエスト・レスポンスの項目名と値形式は、本資料のサンプルJSONに合わせる
