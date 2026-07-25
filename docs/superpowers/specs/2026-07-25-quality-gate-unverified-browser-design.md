# 品質ゲートのブラウザ未実行を成功扱いしない設計

## 背景

表示要件を含むSimple品質ハーネスで、PlaywrightのBrowserCaseが起動できない場合に`BrowserManualReason`を指定すると、手動フォールバックが終了コード0となり、`All requested checks passed.`と表示されていた。これはFocused Unit、lint、typecheck、buildが成功したこととは区別されるべきであり、表示要件の確認未実施を品質ゲート合格と誤認する余地がある。

## 目的

- BrowserCase未実行を品質ゲートの成功として報告しない。
- 実行済み、未実行、CI委譲をコマンド出力と作業記録で区別する。
- 同じ問題を品質ハーネス、Review Skill、契約テストで再発検知できるようにする。

## 採用方針

### 1. Runnerの機械的な失敗判定

`scripts/check.ps1`の`BrowserManualReason`は、手動確認理由を記録する入力として残す。ただしBrowserCaseが実行されていないため、`simple-browser-manual`を成功チェックにしない。警告と未実行理由を出力し、Simple Modeは非0終了とする。

BrowserCaseが実行され、対象テストが終了コード0の場合だけ`simple-frontend-browser`を成功とする。これにより、コマンド終了コードだけで表示要件の検証完了を判断できる。

### 2. 契約テスト

`scripts/simple-mode.tests.ps1`へ次を追加する。

- BrowserCase定義がFrontend作業ディレクトリを使用すること。
- `BrowserManualReason`を指定したBrowser未実行のSimpleが非0終了になること。
- 非ブラウザのFocused Unit、lint、typecheck、buildの定義は従来どおり維持すること。

### 3. Review Skillと標準資料

編集元である`docs/AI活用開発研究/構想メモ/標準化/skills/projectfoundation-review-ja/SKILL.md`へ、次の判断規約を追加する。

- BrowserCaseが起動できない、または未実行の場合は、表示要件の品質ゲートを合格と報告しない。
- `BrowserManualReason`は未実行理由の記録であり、実ブラウザ確認の証拠ではない。
- Fullローカル成功はE2E成功を意味しない。E2Eを別途実行していない場合は未実行またはCI委譲と記録する。

編集後は`.agents/skills/projectfoundation-review-ja/SKILL.md`へ同期する。品質ゲート運用資料にも同じ実行結果の区別と契約テストを記録する。

## 対象外

- FullにPlaywright全件を追加しない。E2Eは既存の専用CI jobと`-CiTask E2E`の責務を維持する。
- Oracle、coverage、PR必須CI 6チェックの実行範囲は変更しない。
- BrowserCaseそのもののテスト内容や表示仕様は変更しない。

## 受入条件

1. BrowserCaseが未実行の場合、Simple品質ハーネスが成功終了せず、未実行理由を出力する。
2. BrowserCaseが実行され成功した場合、Simple品質ハーネスが成功する。
3. Browser未実行の結果を、作業記録・指摘一覧・Review Skillで合格扱いにしない規約が追跡できる。
4. 既存のSimple契約テスト、対象E2E、Frontend品質ゲートが成功する。

## 残るリスク

PR必須CIのE2E、coverage、OracleはローカルSimpleの範囲外であり、従来どおりCIまたは専用runnerで最終確認する。手動フォールバックを入力した場合は、ローカル品質ゲートを通過できないため、BrowserCaseを実行可能な環境で再確認する必要がある。
