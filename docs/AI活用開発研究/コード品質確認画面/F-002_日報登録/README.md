# F-002 日報登録画面 コード品質確認画面

## 対象

- 機能: `F-002` 日報登録
- 画面: `S-003` 日報登録画面
- API: `POST /api/daily-reports`、案件・作業分類・休日区分マスタAPI
- 関連画面確認: 登録画面からの保存、保存して提出、有給休暇保存、入力エラー表示

F-003日報編集、F-006日報提出、F-009日報再提出の固有判定はこのレポートの対象外です。

## 閲覧

`F-002_日報登録_コード品質確認.html`をブラウザで直接開きます。HTML、CSS、JavaScript、表示データを一つのファイルへ埋め込んでいます。

## 更新

1. F-002の受入条件、正本テストケース、レビュー記録、実行記録を確認する。
2. `F-002_日報登録_表示データ.json`を更新する。`automatedFindings`は入力へ追加しない。
3. 表示方針テストと対象機能の検証を実行する。

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-quality-reports.ps1 `
  -FeaturePath .\docs\AI活用開発研究\コード品質確認画面\F-002_日報登録 `
  -ValidateOnly
```

1. 検証成功後、HTMLを生成する。

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-quality-reports.ps1 `
  -FeaturePath .\docs\AI活用開発研究\コード品質確認画面\F-002_日報登録
```

この画面は品質の総合評価を自動表示せず、受入条件、ケース実行結果、品質ゲート、証跡、カバレッジ、明示された保留を分離して表示します。Backend Coverage runnerの未生成・未再判定を成功として扱いません。
