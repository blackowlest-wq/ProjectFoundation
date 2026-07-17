# カバレッジ閾値・分岐充足ゲート 設計書

## 目的

テスト実行時にFrontendとBackendのカバレッジ結果をレポートとして確認し、Statements、Branches、Functions、Linesの各指標が85%を下回った場合に品質ゲートを失敗させる。失敗時は未通過箇所を確認できるレポートを保存し、テストケースを追加した後に同じ入口を再実行する運用を、ローカルとCIで再現可能にする。

## 背景

現在の品質ゲートはFrontendのVitest coverageとBackendのJaCoCo reportを生成するが、85%の閾値判定を行っていない。2026-07-17のFrontend実測値はStatements 90.4%、Branches 81.81%、Functions 92.85%、Lines 90.3%であり、分岐が未達である。既存Backend JaCoCoレポートでもBranchが79.71%であり、分岐ケースの追加が必要になる可能性がある。

## 対象範囲

### 実装対象

- VitestのFrontend coverage対象、レポーター、4指標の85%閾値設定
- JaCoCoのBackend coverage profile、BUNDLE単位の4指標相当閾値、`verify`時の判定
- `scripts/check.ps1`のFrontend/Backend coverage実行順、レポート確認、失敗集約、再実行案内
- GitHub Actionsでのcoverageレポートartifact保存
- 現行coverageレポートで確認できる未通過分岐を埋めるFrontend/Backendテストケース
- テスト方針、品質ゲート運用、テスト・静的解析チェック表、作業記録

### 対象外

- カバレッジを満たすためだけの本番コード変更、業務仕様変更、業務コードの除外
- テストコードの自動生成、同一テストの無条件な自動リトライ
- カバレッジ生成物のGit管理
- Oracle runner、GitHub branch protection、外部環境の新規構築

## 設計判断

VitestとJaCoCoが提供する標準閾値判定を正本とし、`scripts/check.ps1`とworkflowは共通入口・実行順・レポート保存を担当する。独自の閾値計算器は導入しない。これにより、テスト実行ツールが表示する達成率と品質ゲートの終了判定が別実装にならず、将来のツール更新時に判定ロジックが二重化しない。

標準レポーターが出力するtext、HTML、LCOV、JSONまたはJaCoCo XML/CSVをレポートの正本とする。`scripts/check.ps1`はレポートが作成された場所、指標別の失敗、未通過分岐を確認するためのパスと再実行コマンドを出力する。詳細な行・分岐位置はHTML/LCOV/JaCoCo HTMLで確認する。

## 指標と閾値

| 対象 | 指標 | 使用ツールのcounter | 最低値 | 判定単位 |
| --- | --- | --- | ---: | --- |
| Frontend | Statements | Vitest statements | 85% | グローバル |
| Frontend | Branches | Vitest branches | 85% | グローバル |
| Frontend | Functions | Vitest functions | 85% | グローバル |
| Frontend | Lines | Vitest lines | 85% | グローバル |
| Backend | Statements相当 | JaCoCo INSTRUCTION | 85% | BUNDLE |
| Backend | Branches | JaCoCo BRANCH | 85% | BUNDLE |
| Backend | Functions相当 | JaCoCo METHOD | 85% | BUNDLE |
| Backend | Lines | JaCoCo LINE | 85% | BUNDLE |

Frontendはファイル単位ではなくグローバル判定とする。個別ファイルの赤字はHTML/LCOVで確認し、業務上意味のある分岐を優先してケースを追加する。BackendはJaCoCoのBUNDLE全体で判定し、生成コードや業務対象外を閾値回避のために除外しない。

## 実行フロー

```text
FrontendCoverage
  -> Vitest test-layout確認
  -> Vitest coverage実行（閾値・レポート生成）
  -> 成功または失敗を記録
  -> coverage生成物の存在と確認パスを表示
  -> CIはcoverageをartifact保存

BackendCoverage
  -> Oracle共通入口で安全設定を確認
  -> JaCoCo付きMaven verify（テスト、report、check）
  -> 成功または失敗を記録
  -> JaCoCo HTML/XML/CSVの確認パスを表示
  -> CIはcoverageをartifact保存
```

`Invoke-QualityChecks`はcoverageテストが失敗しても、独立した後続のレポート確認を可能な限り実行する。レポートが存在しない場合は、テストが早期失敗したことと合わせてcoverage確認失敗として扱う。成功条件は全指標の閾値達成であり、分岐だけを警告扱いにしない。

coverageは毎回新しい結果を使う。Vitestはcoverageディレクトリをcleanしてから実行し、JaCoCoはcoverage profileのexecution dataをテストごとに更新する。前回のHTMLやexecを残したまま判定しない。

## テスト追加・再実施の運用

未達時の作業は次の固定手順とする。

1. コマンド出力で未達した指標とレポートパスを確認する。
2. FrontendはHTML/LCOVで未通過行・分岐を確認し、BackendはJaCoCo HTML/XMLで未通過分岐のクラス・行を確認する。
3. 実装の期待動作に対応するテストを、既存のユースケース別テストへ追加する。テスト名とArrange/Act/Assertで、分岐条件と期待結果を示す。
4. テスト追加後、同じ`check.ps1 -CiTask FrontendCoverage`または`check.ps1 -CiTask BackendCoverage`を再実行する。
5. 85%未達が残る場合は、次の未通過分岐を確認してケース追加と再実施を繰り返す。
6. Oracle環境がない場合は、Backend coverageを成功扱いにせず、未実行理由と再確認条件を作業記録へ残す。

今回の既存Frontendでは、`dailyReportSearch.test.ts`の任意条件・日付形式、`apiClient.test.ts`の正常応答・401・CSRF・fallback、`loginValidation.test.ts`の必須・上限超過、`App.test.tsx`の401復帰を優先する。Backendは実行したJaCoCoレポートに現れた未通過分岐を根拠に、`TimeRules`、検索サービス、認可ポリシーなど対応する既存`*Test`へケースを追加する。

同一テストを無条件に再実行して数値だけを確認する自動リトライは行わない。テスト追加というソース変更が再実施の条件であり、同じ入力に対する再実行は不足を隠すためである。

## レポートとCI artifact

Frontendは次のレポートを`frontend/coverage`へ出力する。

- textまたはtext-summary: 実行ログ上の指標別達成率
- HTML: ファイル、行、分岐の詳細確認
- JSON summary: 機械可読な集計
- LCOV: 未通過行・分岐の位置確認とCI連携

BackendはJaCoCoの次のレポートを`backend/target/site/jacoco`へ出力する。

- HTML: クラス、メソッド、行、分岐の詳細確認
- XML: CI・機械処理向け集計
- CSV: 指標別の集計

Quality workflowはFrontend coverageを、Oracle workflowはBackend coverageを、成功・失敗にかかわらずartifact保存する。coverage、target、Playwright reportなどの生成物は既存のGit除外ルールを維持し、ソース実装・テストコードと混同しない。

## 変更予定ファイル

| ファイル | 責務 |
| --- | --- |
| `frontend/vite.config.ts` | coverage対象、レポーター、4指標の閾値 |
| `frontend/package.json` | coverage実行入口と必要なレポートscriptの整理 |
| `backend/pom.xml` | JaCoCoのreport/check設定と閾値 |
| `backend/scripts/test-oracle.ps1` | `verify` coverage実行時のテスト発見境界 |
| `scripts/check.ps1` | coverage実行定義、レポート確認、失敗集約、再実行案内 |
| `.github/workflows/quality.yml` | Frontend coverage artifact |
| `.github/workflows/oracle.yml` | Backend coverage artifact |
| `frontend/test/*.test.*` | Frontendの未通過分岐ケース |
| `backend/src/test/**/*.java` | Backendの未通過分岐ケース |
| `docs/AI活用開発研究/構想メモ/標準化/品質ゲート運用.md` | coverage ModeとCI運用 |
| `docs/AI活用開発研究/構想メモ/標準化/テスト方針.md` | 閾値、分岐、追加・再実施方針 |
| `docs/AI活用開発研究/構想メモ/標準化/テスト・静的解析チェック表.md` | レポート確認項目と合格条件 |
| `docs/AI活用開発研究/作業記録/カバレッジ閾値強化_2026-07-17.md` | 作業、実測、実行結果、未実行理由 |

既存のユーザー変更ファイル、既存の作業記録、生成されたcoverage/target配下は、変更対象と重ならない限り変更しない。

## 公式ドキュメント確認

- [Vitest Coverage Config](https://vitest.dev/config/coverage): `coverage.reporter`、`coverage.reportsDirectory`、`coverage.reportOnFailure`、coverage thresholdの設定根拠。
- [Vitest Coverage Guide](https://vitest.dev/guide/coverage): V8 providerと`coverage.include`で未import sourceをレポート対象へ含める方法の根拠。
- [JaCoCo check goal](https://www.jacoco.org/jacoco/trunk/doc/check-mojo.html): `verify`にbindされる`check`、BUNDLE単位、INSTRUCTION / LINE / BRANCH / METHOD counterと`COVEREDRATIO` minimumの根拠。
- [JaCoCo Maven plug-in](https://www.jacoco.org/jacoco/trunk/doc/maven.html): `prepare-agent`、`report`、`check`をMaven lifecycleで組み合わせる根拠。

## 受入条件

1. Frontendの4指標がすべて85%以上のとき、`pwsh -NoProfile -File scripts/check.ps1 -CiTask FrontendCoverage`が終了コード0になる。
2. Frontendのいずれか、特にBranchesが85%未満のとき、同コマンドが非0終了し、text出力とHTML/LCOVで未通過箇所を確認できる。
3. Backendの4指標相当がすべて85%以上のとき、Oracle共通入口を使った`BackendCoverage`が終了コード0になる。
4. Backendのいずれか、特にBRANCHが85%未満のとき、`BackendCoverage`が非0終了し、JaCoCo HTML/XML/CSVが残る。
5. 追加したテストを同じcoverage入口で再実施でき、古いレポートを混ぜない。
6. CIがcoverageレポートを成功・失敗にかかわらずartifact保存する。
7. Oracle環境など未実行の確認は、理由と再確認条件が作業記録に残る。
8. coverage生成物はGitへ追加されず、既存ユーザー変更は保持される。

## リスクと対応

| リスク | 対応 |
| --- | --- |
| Oracle runnerが利用できずBackend実測ができない | Backend coverageは未実行として記録し、Oracle設定・runner条件が揃った時点を再確認条件にする |
| Vitest/JaCoCoの閾値と表示形式が更新で変わる | ツール標準機能を使用し、固定バージョンと公式ドキュメントURLを記録する |
| カバレッジを上げるため意味のないテストが増える | 未通過分岐の業務条件・期待結果を持つケースだけを追加し、レポートとテスト名で根拠を残す |
| 既存ユーザー変更と記録ファイルが衝突する | 変更前にgit statusを確認し、対象ファイルを限定して編集・stageする |
