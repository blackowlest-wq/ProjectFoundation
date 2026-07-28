# 品質確認レポートの参照先とコマンド

## 正本・生成物の対応

| 目的 | 正本または実行対象 |
| --- | --- |
| 機能・受入条件 | `docs/AI活用開発研究/サンプル設計書/機能一覧・受入条件.md`、対象機能の設計書 |
| テストケース | `docs/AI活用開発研究/作業記録/<機能>_テストケース.md` |
| テストケース品質レビュー | `docs/AI活用開発研究/作業記録/<機能>_テストケース品質レビュー_*.md` |
| 表示データ形式 | `docs/AI活用開発研究/コード品質確認画面/品質確認表示データ.template.json` |
| 機能別データ・生成 | `docs/AI活用開発研究/コード品質確認画面/<機能フォルダ>/` |
| 共通契約 | `scripts/quality-report-contract.tests.ps1` |
| 一括検証・生成 | `scripts/check-quality-reports.ps1` |
| 検証記録 | `docs/AI活用開発研究/作業記録/コード品質確認画面_検証記録.md` |

## コマンド

リポジトリルートで実行する。

```powershell
# 対象機能だけを検証（HTMLは更新しない）
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-quality-reports.ps1 `
  -FeaturePath .\docs\AI活用開発研究\コード品質確認画面\<機能フォルダ> `
  -ValidateOnly

# 対象機能を検証してHTMLを生成
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-quality-reports.ps1 `
  -FeaturePath .\docs\AI活用開発研究\コード品質確認画面\<機能フォルダ>

# 全機能を検証・生成する場合だけ対象指定を外す
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-quality-reports.ps1
```

`-ValidateOnly`は共通契約テスト、機能固有表示方針テスト、生成スクリプトの検証を実行する。生成モードでは、検証成功後にHTMLを更新し、埋め込み表示データのカテゴリ集計を出力する。

## データの境界

- 入力JSONは正本資料を表示用に整理したスナップショットであり、`schemaVersion`は`1.0`とする。
- `automatedFindings`は入力JSONに置かず、生成スクリプトが機械検証可能な事実から生成する。
- レビュー記録の状態と、スクリプトが検証した事実を同じ項目へ混ぜない。
- `合格`、`評価A`、`総合判定`、`承認可能／承認不可`を自動で付与しない。
- 未実行のテスト、未生成のカバレッジ、未通過の品質ゲート、明示された保留は、成功に読み替えず事実のまま残す。

## 生成前の確認

- 対象機能フォルダに表示データ、生成スクリプト、表示方針テスト、HTMLが各1つある。
- 新機能ではテンプレートをコピーし、別機能の値を事実として流用していない。
- 既存の未コミット変更を`git status --short`で確認している。
- 実行していないBackend、Frontend、Oracle、Full、E2E、ブラウザ目視確認を、実施済みとして記録していない。
