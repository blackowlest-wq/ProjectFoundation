# F-001 ログイン コード品質確認画面

## 対象

- 機能: `F-001` ログイン
- 画面: `S-001` ログイン画面
- API: `/api/auth/login`、`/api/auth/logout`、`/api/auth/me`
- 関連: ロール別初期画面、Cookieセッション、CSRF、セッションID再発行、Oracle実機確認

## 閲覧

`F-001_ログイン_コード品質確認.html`をブラウザで直接開く。HTML、CSS、JavaScript、表示データを一つのファイルへ埋め込むため、ローカルの`file://`で閲覧できる。

## 更新

1. 正本資料の受入条件、テストケース、レビュー記録を確認する。
2. `F-001_ログイン_表示データ.json`を更新する。
3. 表示方針の回帰テストと表示用JSONを検証する。

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File .\F-001_ログイン_表示方針.tests.ps1
   pwsh -NoProfile -ExecutionPolicy Bypass -File .\F-001_ログイン_生成.ps1 -ValidateOnly
   ```

4. HTMLを生成する。

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File .\F-001_ログイン_生成.ps1
   ```

5. HTMLを開き、受入条件、観点、機械検証結果、リンクを確認する。

複数手順をまとめて実行する場合は、リポジトリルートから次を実行する。

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-quality-reports.ps1 -FeaturePath .\docs\AI活用開発研究\コード品質確認画面\F-001_ログイン
```

全機能を対象にする場合は`-FeaturePath`を省略する。最終レポート生成を明示的に行わず、テストとJSON検証を中心に確認する場合は`-ValidateOnly`を付ける。品質確認画面配下の変更を含むDocs Simpleゲートでは、この検証が自動実行される。

本画面は簡易修正モードで管理する。アプリ本体のFull、E2E、Oracle、カバレッジ再生成は、この画面の更新だけでは実行しない。

総合評価や段階評価は自動表示しない。実行結果、品質ゲート、証跡、カバレッジを個別の事実として表示する。

`reviewStatus`、`caseDesignStatus`、指摘の`要補足`は入力されたレビュー記録として保持するが、機械検証結果や確認項目の自動生成には使用しない。機械検証は必須項目、ID、紐付け、実行結果、品質ゲート、カバレッジ、明示された保留だけを対象とする。

## テンプレート利用

新しい機能の表示データは、共通テンプレートを機能フォルダへコピーして作成する。

```powershell
Copy-Item .\docs\AI活用開発研究\コード品質確認画面\品質確認表示データ.template.json `
  .\docs\AI活用開発研究\コード品質確認画面\F-002_機能名\F-002_機能名_表示データ.json
```

コピー後に`schemaVersion`、`feature`、各コレクション、`coverage`、`sources`を機能固有の内容へ更新する。`automatedFindings`は入力JSONへ追加せず、生成スクリプトに作成させる。共通契約は`quality-report-contract.tests.ps1`、機能固有の回帰確認は機能フォルダの`*_表示方針.tests.ps1`へ記載する。

検証結果は[コード品質確認画面 検証記録](../../作業記録/コード品質確認画面_検証記録.md)を参照する。

## 正本資料

- `../../../../docs/AI活用開発研究/サンプル設計書/機能一覧・受入条件.md`
- `../../../../docs/AI活用開発研究/サンプル設計書/画面設計.md`
- `../../../../docs/AI活用開発研究/サンプル設計書/入力チェック・業務ルール一覧.md`
- `../../../../docs/AI活用開発研究/作業記録/ログイン機能_テストケース.md`
- `../../../../docs/AI活用開発研究/作業記録/ログイン機能_テストケース品質レビュー_2026-07-15.md`
