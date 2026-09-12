# カスタムLinter 実装後レビュー

## 1. レビュー概要

対象機能: ProjectFoundation のカスタムLinter（PF-GATE-001、PF-FE-001、PF-FE-002、PF-TEST-001、PF-SUPPRESS-001、PF-OBS-001）を、実装後の公開入口・テスト・品質ゲート・記録まで確認する。

レビュー対象範囲: frontend ESLint custom rules と公開 Frontend CLI、repository validator B、公開 check.ps1 の C、Spring live mapping と EndpointMetadataRegistry の D、catalog、fixture、runner、workflow接続、正本ケース、品質記録。

影響範囲判定（変更機能 / 直接依存 / 推移的依存 / 共通部品 / 認証 / DB / workflow影響）:

- 変更機能はカスタムLinterの policy discovery、診断、終了コード、実行形、baseline検証、endpoint metadata照合である。
- 直接依存は frontend/eslint-rules/index.mjs、frontend/scripts/frontend-lint.mjs、frontend/eslint.config.mjs、scripts/project-lint.ps1、scripts/project-lint.tests.ps1、scripts/check.ps1、scripts/check.contract.tests.ps1、EndpointMetadataRegistry とその契約テストである。
- 推移的依存は frontend の対象matrix・lcov target、Spring component scan と real RequestMappingHandlerMapping、central registry、catalog gate connection、既存check regression scriptsである。
- 共通部品は診断adapter、catalog loader、公開CLI/runnerの境界、EndpointMetadataRegistryである。Frontendの直接AST regex代替は削除済みで、公開AはESLint Node APIに統一した。
- 認証・CSRFはPF-FE-001の検査対象として診断境界を確認したが、アプリの認証状態を変更していない。DB業務データ・DDLは変更していない。Oracle系は固定SQL cleanupが設定済みDBへ作用するため承認なしで実行せず、HOLDに分離した。
- workflow / test runner / quality gate接続は影響範囲に含め、check.ps1の Full、C contract、既存regressionを確認した。無関係な F-001 HTML は範囲外で編集していない。

選択した範囲・除外した範囲・根拠・フォールバック理由:

- 選択範囲はカスタムLinterの全 seam（U1/A/B/C/D）、catalog、fixture、runner、records、関連coverage、E2E、quality gateである。catalog、runner、check接続を含むため影響選択の信頼性が局所化できず、Fullへフォールバックした。
- 通常確認では focused U1/A/B/D/C、FrontendCoverage、E2E、backend focused、全B形式を実行した。夜間・リリース前相当の全体確認では Full を実行した。
- 除外はUIの見た目確認（挙動変更なしのためN/A）、対象DBの承認なしに行うOracle/BackendCoverage/E2EOracleである。除外ではなく理由付きHOLDとし、再確認条件を記録した。

参照した設計書・正本ケース:

- AGENTS.md、docs/AI活用開発研究/構想メモ/標準化/標準化資料一覧.md、開発フロー.md、実装後レビュー表.md、テスト・静的解析チェック表.md、テストケースレビュー観点.md、テスト方針.md、AI専門レビュー用プロンプト定義.md、品質ゲート運用.md。
- カスタムLinter_実装計画.md、カスタムLinter_実装前レビュー.md、カスタムLinter_テストケース.md、カスタムLinter_作業記録.md、カスタムLinter_統合品質記録.md、日報登録編集_指摘一覧.md。
- 公式一次情報として ESLint Node.js API / flat config、Spring ClassPathScanningCandidateComponentProvider / RequestMappingHandlerMapping を確認した。

実装前レビュー結果: 品質重視モードの受入条件、正本TC/RT、責務境界、公開入口、baselineの扱い、Cの終了コード伝播を固定してから実装へ進めた。実装後は、実装前の計画上の判定を実行証跡の代用にせず、下記の実コード・テスト・commandで再照合した。

## 2. 必須資料・ID・レビュー担当

requiredArtifacts:

1. docs/AI活用開発研究/作業記録/カスタムLinter_実装後レビュー.md
2. docs/AI活用開発研究/作業記録/カスタムLinter_テストケース.md
3. docs/AI活用開発研究/作業記録/カスタムLinter_統合品質記録.md
4. docs/AI活用開発研究/作業記録/カスタムLinter_作業記録.md
5. docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md

requiredIdRanges:

| namespace | required range | meaning |
| --- | --- | --- |
| acceptance | AC-PFL-001..009 | 受入条件9件 |
| canonical test | TC-PFL-001..105 | 正本テストケース105件 |
| runtime test | RT-PFL-001..105 | 実テスト105件 |
| baseline finding | FIND-PFL-BASE-001..005 | 5 logical baseline occurrences |
| post-review finding | FIND-PFL-P1R-001..013 | 独立レビューP1 13件（001..009に010..013を追加） |

レビュー範囲（P0/P1/P2）・適用理由・各担当へ渡した参照ファイル/節:

| priority | 適用理由 | 具体的な参照入力 | 判定 / 出力 |
| --- | --- | --- | --- |
| P0 設計・受入条件・状態 | 全機能へ適用 | 実装後レビュー表、実装計画、AC、live mapping境界、終了コード契約 | 実装とACの不整合なし。P0重複指摘は本記録へ統合 |
| P0 テスト不足・coverage | custom rule、runner、coverageを追加・変更 | テストケースレビュー観点、テスト方針、テスト・静的解析チェック表、正本ケース、Full/coverage/E2Eログ | 105行を一件一行で照合。TC-PFL-074だけHOLD |
| P0 テスト構成・責務分割 | U1/A/B/C/Dを追加・変更 | テストケースレビュー観点のテスト構成・責務分割、ディレクトリ構成ルール、実テストファイル | 各層の責務を維持。baselineSuppression.test.tsをTC080/081の実source回帰へ使用 |
| P0 期待結果・アサーション | exit、bytes、channel、redaction、mappingを検証 | テストケースレビュー観点の期待結果、正本ケース、実テスト | 診断exitとtest process exitを分離。TC012/070のREDも実測 |
| P0 トレーサビリティ・統合 | 受入条件、TC、RT、FINDを同期 | AI専門レビュー用プロンプト定義の08、正本ケース、作業記録、指摘一覧 | AC 9件、TC/RT 105件、baseline 5件、P1R-001..013の13件を記録 |
| P1 セキュリティ・入力 | CSRF境界、catalog値、secret、invalid UTF-8、suppression文字列境界 | セキュリティ規約、PF-FE-001、adapter test、TC106..119 | redaction、strict UTF-8、binary除外、block/comment tokenを確認 |
| P1 配置・共通化 | 新規rule、runner、registry、test配置 | ディレクトリ構成ルール、共通部品化判断基準、実コード・実テスト | 既存入口へ接続し、P1R-009のみ標準化候補としてHOLD |
| P1 静的解析・CI・品質ゲート | check.ps1、C、coverage、Oracle接続を変更 | テスト・静的解析チェック表、品質ゲート運用、check scripts | Full、C contracts、TC120/121、regression PASS。Oracle系は理由付きHOLD |
| P1 ログ・観測可能性 | endpoint metadata、diagnostic、channel、非開示 | 実装後レビュー表のロガー観点、セキュリティ規約のログ節、D契約 | central registry、live mapping、secret非開示を確認 |
| P2 非機能・競合・性能・互換性・アクセシビリティ | UI/性能要件に実質変更なし | 品質ゲート運用、変更差分、browser scope | Browser visual はN/A。DB/Oracleの外部条件はP1のHOLDへ分離 |

専門レビュー担当・入力・出力:

- 設計・受入条件担当: 実装計画、AC、実装後レビュー表、EndpointMetadataRegistry境界。出力はP0重複（D manual list、future policy、終了コード）とP1R-003/005/007。
- テスト・構成担当: 正本ケース、実テスト、fixture、テスト方針、テストケースレビュー観点。出力はTC012/070、TC080/081、TC110..119、canonical 105行、B 48x2の照合。
- 静的解析・CI担当: ESLint Node API、flat config、check.ps1、contract scripts、品質ゲート運用。出力はP1R-001/002/006、TC074/075/076/077/083/084/085/092/120/121。
- セキュリティ・観測担当: セキュリティ規約、catalog adapter、D live mapping、ログ・診断境界。出力はP1R-004/008/010/013、P1R-009の責務集中再確認条件、TC130/131。
- 統合担当: 上記の入力と実行ログを、重複・重大度・仕様根拠・保留条件を相互に独立して照合し、本記録・統合品質記録・正本ケースへ統合した。

requiredAdditionalIds（今回のレビューで追跡するLUNA findings）:

- FIND-LUNA-P0-001
- FIND-LUNA-P1-001
- FIND-LUNA-P1-003
- FIND-LUNA-P1-004
- FIND-LUNA-P1-005
- FIND-LUNA-P1-006
- FIND-LUNA-P1-007

`post-review.json::requiredAdditionalIds.lunaFindings` がfixture側のID pinの唯一の正本であり、docsへ現在値を複製しない。本レビューはP1-005/006/007を修正済みfindingとして記録し、TC-PFL-085がfixtureのID pinと実文書を照合する。

## 3. 実装・ケース単位の統合結果

canonical TC-PFL-001..105 と RT-PFL-001..105 は正本テストケースと統合品質記録へ各一件で記録した。locator は scripts/project-lint.tests.ps1、scripts/check.contract.tests.ps1、frontend/test/lint/*.test.ts、frontend/eslint-rules/index.mjs、frontend/scripts/frontend-lint.mjs、EndpointMetadataRegistryContractTest.java の実在対象に限定した。統合品質記録にはcommand列を設け、各行のstatusをPASSまたはHOLDで明示した。

- Bは scripts/project-lint.tests.ps1 の Test-CatalogCases、Test-DirectBCases、Test-PlacementCases、Test-AdapterCases、Test-MissingFieldCases、Test-ValidExceptionCase に対応し、canonical 48ケースを Text/Json 両形式で96/96 PASS。TC-PFL-106..109は回帰subcaseとして別記し、canonical件数へ足していない。
- U1/Aは frontend/eslint-rules/index.mjs の noDirectTransportAccess、moduleMatrix、analyzeSuppressionDirectives、runFrontendLint を実行。Frontend公開入口は lintFiles/lintTextへ統一し、regex代替は残していない。TC-PFL-110..119はfocused 39/39で、block/line comment、string/template、export-from/dynamic import、qualified global、const aliasを確認した。
- Cは scripts/check.contract.tests.ps1 の Test-CChildExit2、Test-CLocalFull、Test-CSimpleMandatory、Test-CFullFrontend、Test-CFullBackendContract、Test-ImpactPlanFallback、Test-BaselineStageOrder、Test-IgnoreStoreForbidden、Test-StageOrder、Test-StageCompletionMarkers、Test-QuickPrePushUnchanged、Test-RealRepositoryZero、Test-StandardsRecord、Test-PostReviewGate、Test-ImpactAggregateUnresolvedSelectedJob、Test-ImpactAggregatePlanMapMismatch を公開black-boxで確認した。
- Dは EndpointMetadataRegistryContractTest の live Spring RequestMappingHandlerMapping、ClassPathScanningCandidateComponentProvider相当のcomponent scan、application-owned /api/HandlerMethod、central registry比較を実行。TC-PFL-102..105に加え、TC-PFL-130/131でlifecycle mismatchの固定非開示startup failと一致時startup正常を確認した。

## 4. 独立レビュー P1 指摘と対応

| 指摘ID | 内容 / 対象 | 仕様・実装根拠と確認 | 対応状況 / 標準化判定 |
| --- | --- | --- | --- |
| FIND-PFL-P1R-001 | frontend public A bypass。公開CLIと内部regex seamが別経路になる懸念 | frontend/eslint-rules/index.mjs::runFrontendLint、frontend/scripts/frontend-lint.mjsを ESLint Node API lintFiles/lintTextへ統一。frontendLint.cli.test.ts のTC-PFL-013..015、070とFullで確認 | 修正済み。既存観点で対応。公開入口を直接実行する契約を維持 |
| FIND-PFL-P1R-002 | Quick/PrePushがcustom ruleを意図せず実行する懸念 | frontend/eslint.config.mjs のbase lintで2 custom rulesをoff。config-changeもbase eslint .を実行し、scripts/check.contract.tests.ps1::Test-QuickPrePushUnchanged（TC-PFL-077）でcustom invocation count 0 | 修正済み。既存観点で対応。Quick/PrePushの変更検出を継続 |
| FIND-PFL-P1R-003 | Dのcontroller手動列挙 | EndpointMetadataRegistryContractTest と registry実装を real RequestMappingHandlerMapping + component scanへ変更。TC-PFL-019、073、102..105、backend focused 24/24で確認 | 修正済み。個別対応。Spring mapping APIの変更時に再確認 |
| FIND-PFL-P1R-004 | catalog由来secretがdiagnosticへ漏れる懸念 | scripts/project-lint.ps1 の未信頼値をdiagnosticへ補間せず、canaryでstdout/stderr非開示を確認。TC-PFL-066、TC-PFL-106、TC-PFL-109、B 96/96 | 修正済み。既存観点で対応。security規約の非開示アサーションを継続 |
| FIND-PFL-P1R-005 | childExit 1が2を隠す | scripts/check.ps1 の集約優先順位を2優先へ固定し、scripts/check.contract.tests.ps1::Test-CChildExit2（TC-PFL-020）でchildの順序を両方向確認 | 修正済み。既存観点で対応。C契約の終了コード伝播を維持 |
| FIND-PFL-P1R-006 | 作業記録・正本・品質表のstale内容 | 本更新でテストケース、統合品質記録、実装後レビューの実測状態、locator、command、HOLD理由を揃えた。TC-PFL-085のcontent gateでrequired artifacts/IDs、105行、stale marker不存在をblack-box検証 | 修正済み。既存観点で対応。毎回のcontent gateで再確認 |
| FIND-PFL-P1R-007 | schemaVersionの小数・bool・string許容 | scripts/project-lint.ps1 のschema境界を検証し、1.1/0.9/bool/stringはreject、JSON 1e0はnumeric 1としてacceptする理由をTC-PFL-107とTC-PFL-069で明記 | 修正済み。既存観点で対応。入力型境界をadapterケースへ維持 |
| FIND-PFL-P1R-008 | invalid UTF-8をskipする懸念 | relevant textのroot/extensionはstrict invalid UTF-8を deterministic redacted exit2、binaryは対象外。TC-PFL-108およびB adapterで確認 | 修正済み。標準化候補。入力encoding境界を共通adapter/テスト観点へ反映検討 |
| FIND-PFL-P1R-009 | index.mjs / registryへのresponsibility concentration | frontend regex代替は削除済み。ただし index.mjs と registryの責務集中は現実装の動作を壊さずに分割する判断が必要 | 標準化候補 / HOLD。次回モジュール分割時に共通部品化判断基準と責務分割観点で再確認。分割対象・境界・focused regressionを先に設計する |

### 4.1 最終追加のfrontend overlap findings

| 指摘ID | 内容 / 対象 | 仕様・実装根拠と確認 | 対応状況 / 標準化判定 |
| --- | --- | --- | --- |
| FIND-PFL-P1R-010 | block/line ESLint suppressionの解析漏れとliteral誤検出 | frontend/eslint-rules/index.mjs::sourceComments が SourceCode.getAllComments を使い、suppressionPolicy.test.ts のTC-PFL-110 block、TC-PFL-111 string/template、TC-PFL-112 valid blockを公開Aで検証 | 修正済み。既存観点で対応。comment token解析とWhy not直前条件を継続 |
| FIND-PFL-P1R-011 | module matrixのshared→auth / auth→app境界 | frontend/eslint-rules/index.mjs::moduleViolation と moduleMatrix.config.test.ts のTC-PFL-113/114でtype-only shared→authも禁止、auth→appも禁止 | 修正済み。標準化候補。依存辺の網羅表へexport形態ごとの観点を追加検討 |
| FIND-PFL-P1R-012 | export-from / dynamic importの見落とし | frontend/eslint-rules/index.mjs::moduleMatrix visitorのExportNamedDeclaration、ExportAllDeclaration、ImportExpressionとTC-PFL-115..117で確認。非リテラルdynamic importは静的判定外 | 修正済み。既存観点で対応。AST visitor追加時のexport形態回帰を維持 |
| FIND-PFL-P1R-013 | qualified fetch/document.cookie/global aliasとshadowing | frontend/eslint-rules/index.mjs::isGlobalNamespaceIdentifier、isDocumentCookie、isFetchReference、noDirectTransport.rule.test.tsのTC-PFL-118/119でwindow/globalThis/self、qualified cookie、const alias、shadowed/apiClient例外を確認。P0 qualified cookie/fetch指摘を統合 | 修正済み。標準化候補。global objectと静的aliasの安全側判定をPF-FE-001観点へ反映検討 |

## 5. P0重複指摘の統合

| 重複指摘 | 統合した対応と証跡 | 判定 |
| --- | --- | --- |
| public A bypass | P1R-001へ統合。公開CLIをESLint Node API lintFiles/lintTextへ統一し、frontendLint.cli.test.ts とFullを実行 | 修正済み |
| CLI内部seam偏重 | Aの受入を内部関数の直接呼出しだけにせず、frontend/scripts/frontend-lint.mjsの公開CLIをchild processで検証。TC-PFL-013..015、070 | 修正済み |
| fake RED TC12/70 | TC-PFL-012は noDirectTransport.rule.test.ts の child RED assertion mismatch、TC-PFL-070は frontendLint.cli.test.ts の child signature mismatch。診断exitとtest process exit 1を分離 | 修正済み |
| TC80/81欠落 | frontend/test/lint/baselineSuppression.test.ts の実source専用itでMonthlySummaryとPendingApprovalを確認。TC-PFL-080/081 | 修正済み |
| TC74 false evidence | 固定HEAD、5 blobs、evidenceStatus=notCaptured、decision=hold、reason/recheckConditionを保持。post-fix TC-PFL-078..082は別判定 | HOLD（historical evidence） |
| TC85 self-declared / stale | content gateはrequired artifacts、ID ranges、schemaVersion=2のimmutable evidence、canonical trace、実在locator、command、PASS/HOLD、禁制stale markerを読む。postReviewStatus=completeだけでは結果を変えない | 修正済み / TC-PFL-085で検証 |
| future seventh policy | catalogの件数可変を維持し、gate未登録の第7 policyは UNSUPPORTED_POLICY でreject。B 96/96、TC-PFL-002 | 修正済み |
| D manual list / TC104-105 mismatch | Dをlive Spring mapping + component scanへ変更し、TC-PFL-104のmethodless違反、TC-PFL-105のexplicit method展開を実 mappingで確認 | 修正済み |

### 5.1 最終レビュー findings

| 指摘ID | 内容 | 修正・証跡 | 判定 |
| --- | --- | --- | --- |
| FIND-LUNA-P0-001 | TC085が表形式だけを見て、locator実在・symbol/case・public runner整合、実行証跡整合を保証しない懸念 | scripts/check.contract.tests.ps1 のTC-PFL-085がschemaVersion=2、19 sourceArtifacts、105 coveredCases、locator path/symbol/selector、public command、commit/SHA256、stdout/stderr hash、PASSとexitCode不整合のnegativeを検証。immutable evidenceは104 PASS + TC-PFL-074限定HOLD。2026-09-12最終rootのTC-PFL-085はPASSである | 修正済み |
| FIND-LUNA-P1-001 | Impact aggregateでselected layerがJobMapから欠落すると成功扱いになる懸念 | scripts/check.ps1::Get-ImpactAggregateContractViolations / Invoke-ImpactAggregateがmissing selected layerを違反行へ保持。TC-PFL-121はQualityのFullBackend欠落をC exit 1、Oracle系の許可除外を確認 | 修正済み。既存観点で対応 |
| FIND-LUNA-P1-003 | Stage 1..5を飛ばしても後段だけで進める懸念 | scripts/check.ps1::Get-StageOrderContractErrorが前段COMPLETE markerを連鎖要求。TC-PFL-120はstage0..5の正常11 scenarioと飛ばしnegativeを確認 | 修正済み。既存観点で対応 |
| FIND-LUNA-P1-004 | Dのlive mappingとregistry mismatchが検出されてもSpring startupを止めない懸念 | EndpointMetadataRegistry::afterSingletonsInstantiated がvalidation mismatchで固定非開示 EndpointMetadataValidationExceptionをthrow。EndpointMetadataRegistryContractTestのTC-PFL-130/131、contract 20/20、observability 32件、root独立20/20で確認 | 修正済み。既存観点で対応 |
| FIND-LUNA-P1-005 | TC085の文書説明が旧schema v1 / 旧証跡構造のままで、実fixtureのv2契約と不整合になる懸念 | 本更新でカスタムLinter_テストケース.md、カスタムLinter_統合品質記録.md、カスタムLinter_実装後レビュー.mdのTC085説明をschemaVersion=2、19 sourceArtifacts、105 coveredCases、104 PASS + TC-PFL-074限定HOLD、public command/exit/result/stdout/stderr hash、source hash、artifact pinへ更新。2026-09-12最終rootのTC-PFL-084/085はPASS | 修正済み。schema変更時はTC-PFL-085を再確認 |
| FIND-LUNA-P1-006 | locatorをpathだけで受理しsymbol/selectorの実在性を検証しない懸念 | scripts/check.contract.tests.ps1 のTC-PFL-085が `path::symbol` / `path::selector` を必須化し、path-only、空symbol、架空path、架空symbol、case mismatchのnegativeを検証。3正本のcanonical 105行は実在locatorへ揃えた。2026-09-12最終rootのTC-PFL-085はPASS | 修正済み。locatorまたはpublic runner変更時にTC-PFL-085を再確認 |
| FIND-LUNA-P1-007 | docsが可変なartifact pinの具体hashを複製し、docs自身のsource hash更新と循環する懸念 | 3正本から現在pinの具体値を削除し、`scripts/fixtures/project-lint/TC-PFL-085-post-review-gate/post-review.json::executionEvidence.sha256` を唯一のpin正本として記載。TC-PFL-085がlocatorのpinとexecution-evidence.json実体hash一致を検証する。2026-09-12最終rootのTC-PFL-084/085/121とFullはPASS | 修正済み。fixture locatorまたはevidence schema変更時にTC-PFL-085を再確認 |

## 6. 標準化判定と残課題

| 対象 | 判定 | 反映先・理由 |
| --- | --- | --- |
| public seamをblack-boxで検証 | 既存観点で対応 | テスト方針と実装後レビュー表の実装経路・実行証跡へ適用済み。A/Cの公開入口を一行の証跡へ残す |
| TC/RT一件一行、実在locator/command/status | 標準化候補 | 次回の正本ケース様式とcontent gateへ反映する。今回の両記録は105行で実証 |
| secret redaction / canary、strict UTF-8 | 標準化候補 | セキュリティ規約とadapterテスト観点へ追加検討。今回のTC066、106、108、109で回帰可能 |
| D live mappingと境界除外 | 既存観点で対応 | 観測可能性の契約としてTC019、073、102..105を維持 |
| index.mjs / registry責務集中 | 標準化候補 / 保留 | 次回モジュール分割を開始する時点で共通部品化判断基準、ディレクトリ構成ルール、テスト責務分割を再適用。現時点は機能変更を広げない |
| historical baseline artifact | 保留 | TC-PFL-074の再確認条件に従い、次回変更でStage 1直後・baseline修正前の公開A/D stdout、stderr、commit、5 blobsをimmutable保存 |
| block/line suppression、string/template除外 | 標準化候補 | P1R-010。SourceCode.getAllCommentsとWhy not直前条件をテストケースレビュー観点へ反映検討 |
| export-from / dynamic import、shared/auth/app依存辺 | 標準化候補 | P1R-011/012。module matrixの依存辺表へexport形態・静的specifierを追加検討 |
| qualified global、静的const alias、shadowing | 標準化候補 | P1R-013。PF-FE-001の安全側判定とapiClient例外を共通観点へ反映検討 |
| Impact selected layer必須性 | 既存観点で対応 | FIND-LUNA-P1-001 / TC-PFL-121。aggregateはselected layer欠落を失敗行として保持し、許可除外だけを認める |
| Stage 1..5前段marker連鎖 | 既存観点で対応 | FIND-LUNA-P1-003 / TC-PFL-120。stage skipをSTAGE_ORDER_INVALIDで検出 |
| Spring lifecycle mismatchの固定非開示startup fail | 既存観点で対応 | FIND-LUNA-P1-004 / TC-PFL-130/131。live mappingとregistry一致を起動時に強制 |

各P1およびP0の指摘は、修正ファイル・確認テスト・判定・保留条件を日報登録編集_指摘一覧.mdとカスタムLinter_作業記録.mdへ同期する。今回の担当範囲では記録文書3ファイルだけを編集し、一覧と作業記録の既存内容は親担当の同期対象として残した。

## 7. 通常ゲート結果

| 確認項目 | command / artifact | status |
| --- | --- | --- |
| Frontend focused | TC-PFL-012 12/12、TC-PFL-110..119を含む focused 39/39、frontend all 200/200、lint/typecheck/build | PASS |
| Frontend coverage | statements 96.08%、branches 92.38%、functions 97.77%、lines 95.94% | PASS |
| E2E | Chromium 21/21 | PASS |
| Backend focused | EndpointMetadataRegistryContractTest 20/20、observability 32件、root独立20/20 | PASS |
| B direct | canonical 48 cases x Text/Json = 96/96 | PASS |
| C contract | TC-PFL-020、021、022、023、024、025、075、076、077、083、084、092、120、121 | PASS |
| Existing regression | check regression scripts 10/10 | PASS |
| Baseline inventory | TC-PFL-074: fixed HEAD + 5 blobs照合、historical public A/D artifactなし | HOLD |
| Browser visual | UI behavior変更なし | N/A |

## 8. 夜間・リリース前 / 全体ゲート結果

| 確認項目 | command / artifact | status |
| --- | --- | --- |
| Full | pwsh -NoProfile -File scripts/check.ps1 -Mode Full。frontend lint/typecheck/unit 24 files 200 tests/build、backend Spotless/Checkstyle/SpotBugs/PMD、contract、project-lint、endpoint registry 18 tests、custom-policy-connections | PASS |
| Content gate | pwsh -NoProfile -File scripts/check.contract.tests.ps1 -Case TC-PFL-085。schemaVersion=2、19 sourceArtifacts、canonical 105 coveredCases、実在locator/command/status、execution hashを検証 | PASS（2026-09-12最終root） |
| Oracle / BackendCoverage / E2EOracle | 固定SQL cleanupがDBを書き換えるため、対象DBの明示承認なしに未実行。以前のフルbackend testは外部Oracle認証 ORA-01017 93 errors | HOLD |

TC-PFL-085の判定は、実ファイルの内容とblack-box gateの結果で行い、自己申告の postReviewStatus=complete 等を完了根拠にしない。Oracle系の再確認は、対象DB、cleanup範囲、復元手順、認証を明示承認した実行環境で行い、BackendCoverage/Oracle/E2EOracleそれぞれのartifactを保存する。

## 9. 未実行項目と再確認条件

| 項目 | 理由 | 再確認条件 | 判定 |
| --- | --- | --- | --- |
| TC-PFL-074 historical baseline evidence | Stage 1後・Stage 2前の公開A/D immutable artifactが当時取得されていない。fixed HEADと5 blobsのmanifestは保持 | 次回変更時、Stage 1直後かつbaseline修正前に公開A/Dを同一current treeへ実行し、stdout/stderr、対象commit、5 blob照合結果をimmutable保存 | HOLD |
| BackendCoverage | 固定SQL cleanupが設定DBを変更する | 対象DBとcleanup/復元の明示承認、read-only検証、coverage report保存 | HOLD |
| Oracle | 認証済み対象DBとcleanup承認がない | DB、credentials、cleanup範囲、復元計画を承認し、Oracle spec単独実行とDB verifyを保存 | HOLD |
| E2EOracle | Oracle依存のE2E前提が未承認 | Oracleと同じ対象DB承認、失敗時cleanup、E2E report保存 | HOLD |

## 10. 最終レビュー追補: 実測結果・immutable evidence・残留リスク

| 追加確認 | command / 実装locator | 実測結果 |
| --- | --- | --- |
| frontend suppression / module / transport overlap | npm --prefix frontend run test -- test/lint/suppressionPolicy.test.ts test/lint/moduleMatrix.config.test.ts test/lint/noDirectTransport.rule.test.ts | TC-PFL-110..119を含む focused 39/39、全24 files 200/200、lint/typecheck/build PASS |
| Stage completion chain | pwsh -NoProfile -File scripts/check.contract.tests.ps1 -Case TC-PFL-120、scripts/check.ps1::Get-StageOrderContractError | 前段COMPLETE marker連鎖と飛ばしnegative 11 scenario PASS |
| Impact aggregate selected layer | pwsh -NoProfile -File scripts/check.contract.tests.ps1 -Case TC-PFL-121、scripts/check.ps1::Get-ImpactAggregateContractViolations | selected FullBackend欠落をQuality failureへ保持、Oracle系許可除外を維持してPASS |
| Spring lifecycle mismatch / match | backend\\mvnw.cmd -B -Dtest=EndpointMetadataRegistryContractTest test、EndpointMetadataRegistry::afterSingletonsInstantiated | TC-PFL-130/131、contract 20/20、observability 32件、root独立20/20 PASS |
| final root C contracts | pwsh -NoProfile -File scripts/check.contract.tests.ps1 -Case TC-PFL-084 / TC-PFL-085 / TC-PFL-121 | 2026-09-12最終root 3ケース PASS |
| full gate | pwsh -NoProfile -File scripts/check.ps1 -Mode Full | frontend 200 tests/build、backend静的解析、contracts、project-lint、endpoint registry、custom-policy-connections PASS |

TC-PFL-085のfixture実体は、`scripts/fixtures/project-lint/TC-PFL-085-post-review-gate/post-review.json::executionEvidence.path` と `::executionEvidence.sha256` がexecution-evidence.jsonのartifact path/pinの唯一の正本であり、docsへ現在値を複製しない。TC-PFL-085はこのlocatorのpinと実体のSHA-256一致を検証する。実体は `schemaVersion=2`、固定commit `905a9676a7d48a86bf9aab6fb34dcbf08c65f402`、19 source artifacts、105 executionsを保持する構造である。requiredArtifactsの5文書とは別に、19 source artifactsの各path + SHA-256をpinする。各executionは `id`、`coveredCases`、公開command、`exitCode`、`result`、`stdoutSha256`、`stderrSha256`、利用source artifactのpath + sha256を持つ。

`coveredCases` はcanonical TC-PFL-001..105を一件ずつ明示し、execution idは `exec-TC-PFL-001`..`exec-TC-PFL-105`、結果は104 PASS + TC-PFL-074限定HOLDである。locatorは `path::symbol` または `path::selector` を必須とし、path、symbol/selector、case ID、public runner commandを実在対象へ照合する。negativeとして、旧 `caseResults.default` / implicit override形式、全105件HOLD、TC-PFL-074以外のHOLD、coverage欠落・重複、HOLDのreason/recheck欠落、path-only・空symbol・架空path・架空symbol、case mismatch、source/artifact hash mismatch、PASSと非0 exitCodeの不整合をfail-closedで検証する。`postReviewStatus=complete`の自己申告だけでは結果を変えない。

このevidence artifactはcanonical TC-PFL-001..105のゲート結果を固定する資料であり、追加TC-PFL-106..131の全commandごとに別のimmutable artifactを作成したという意味ではない。追加ケースは実測結果と実在locatorで記録し、未取得の証跡を実行済みとして主張しない。2026-09-12最終rootのTC-PFL-084/085/121とFullはPASSである。この3正本更新後にTC-PFL-085を再実行した場合、docs自身がsourceArtifactsであるためsource hash mismatchが出るのはpin再計算差分として正常であり、`missing source artifact` はその従属メッセージに限る。locator/status/coverage等の独立したfailureがないことを確認し、上記104 PASS + TC-PFL-074限定HOLDと混同しない。現在pinの具体hashはfixture locatorだけを参照する。

### 10.1 最終レビュー findings の残留リスク

| リスク | 状態 | 再確認条件 |
| --- | --- | --- |
| FIND-LUNA-P0-001 / TC085形式だけの検証 | 修正済み | TC085でlocator path/symbol/case、public runner、commit/SHA256、exitCode整合のnegativeを継続 |
| FIND-LUNA-P1-001 Impact selected layer欠落 | 修正済み | Quality/Oracle aggregateのexpected layer contractを変更する時にTC-PFL-121を再実行 |
| FIND-LUNA-P1-003 Stage順序 | 修正済み | stage marker名・環境変数を変更する時にTC-PFL-120の飛ばしnegativeを再実行 |
| FIND-LUNA-P1-004 backend live mismatch非強制 | 修正済み | controller追加・registry変更時にTC-PFL-130/131とstartup smokeを再実行 |
| FIND-LUNA-P1-005 docs schema v1不整合 | 修正済み | 3正本のTC085説明またはfixture schemaを変更する時、TC-PFL-085でschemaVersion=2・19 sourceArtifacts・105 coverageを再確認 |
| FIND-LUNA-P1-006 locator symbol skip | 修正済み | canonical locatorまたはpublic runnerの形式を変更する時、path::symbol/selector実在性とnegativeをTC-PFL-085で再確認 |
| FIND-LUNA-P1-007 可変artifact pinの文書複製 | 修正済み | `post-review.json::executionEvidence.sha256` 以外へ現在pinを複製せず、TC-PFL-085でartifact実体hashとの一致を再確認 |
| FIND-PFL-P1R-009 responsibility concentration | 標準化候補 / HOLD | 次回index.mjsまたはregistryをモジュール分割する時、責務境界・共通化・focused regressionを先に設計 |
| FIND-PFL-BASE-001..005 historical evidence | HOLD。TC-PFL-074 | 次回変更のStage 1直後・baseline修正前に公開A/D、commit、5 blobs、stdout/stderrをimmutable保存 |
| BackendCoverage / Oracle / E2EOracle | HOLD | 対象DB、cleanup、復元、認証を明示承認した環境で各artifactを保存。ORA-01017の過去結果を品質PASSと混同しない |
| 非リテラルdynamic import / 再代入alias | 静的判定外。今回の追加修正でHOLDにはしない | 動的解析または別の実行時検証を導入する時に対象範囲とfalse positiveを設計 |

## 11. 確認者・編集範囲

- 確認者: ProjectFoundationレビュー担当。固定baseline HEADと実コード・実テスト・実行結果を照合した。
- 編集範囲: docs/AI活用開発研究/作業記録/カスタムLinter_テストケース.md、docs/AI活用開発研究/作業記録/カスタムLinter_統合品質記録.md、docs/AI活用開発研究/作業記録/カスタムLinter_実装後レビュー.md の3ファイルのみ。
- commit、push、branch作成は行わない。
