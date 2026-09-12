# カスタムLinter 作業記録

## 1. 作業情報

| 項目 | 記録 |
| --- | --- |
| 作業日 | 2026-09-12（実装後記録更新。初版作業日は2026-09-02） |
| 判断日 | 2026-09-01 |
| 対象 | カスタムLinter Phase 1の実装後検証、指摘対応、標準化記録 |
| 開発モード | 品質重視モード（利用者承認済み） |
| 使用モデル | gpt-5.6-luna / max（利用者承認済み） |
| 状態 | Stage 1〜4実装・契約テスト・C接続完了。Full、FrontendCoverage、Chromium E2E、B/D/C focused gate成功。TC-PFL-085はschema v2の証跡整合を含めroot PASS。現行pinは `scripts/fixtures/project-lint/TC-PFL-085-post-review-gate/post-review.json::executionEvidence.sha256` を唯一正本とし、文書更新後の再固定も完了。TC-PFL-074とOracle系は保留 |
| 変更対象 | 実装計画、正本テストケース、実装前レビュー、統合品質記録、本文書、ADR-PFL-001、指摘一覧 |
| TC/RT trace | TC-PFL-001〜105 ↔ RT-PFL-001〜105を一対一で固定。TC-PFL-093〜101はFIND-PFL-REV-002、TC-PFL-102〜105はFIND-PFL-REV-008へ接続 |

今回の更新では、実装前に固定したcatalog、6 policy、公開seam、scope、baseline、Stage、AC/TC/RT/FINDを、実装後の実測結果・指摘対応・保留条件へ同期する。sourceArtifact pinはcanonical locatorを唯一の正本とし、docsには具体値を複製しない。成功した確認と未実行の確認を分離し、文書の自己申告だけで品質gateを通過させない。

## 2. AI提案の採否と判断

| 提案 | 判定 | 判断・反映 |
| --- | --- | --- |
| 既存native test/configだけで全規約を検査する | 不採用 | 業務回帰には利用できるが、catalog必須field、owner/seam、配置横断、gate connectionを一意に証明しない。ADRの代替案比較へ反映した。 |
| Java static parserでController routeを正本化する | 不採用 | annotation文字列はSpringが実際に登録したmapping、合成route、HandlerMethodを証明しない。 |
| Spring introspectionをruntime mappingの入力にする | 採用 | D seamで実Spring `RequestMappingHandlerMapping`全件を列挙し、中央`EndpointMetadataRegistry`とHTTP method + normalized route、HandlerMethodを比較する。 |
| Controller annotationまたは生成ファイルだけを正本にする | 補助・Phase 2再評価 | runtime mappingの正本にはしない。 |
| ruleごとに設定を分散し、central catalogを置かない | 不採用 | policy ID、severity、owner、例外、gate connectionが分散する。top-level `schemaVersion`と可変`policies[]`を採用した。 |
| baselineをignore storeへ移して初回gateを通す | 不採用 | 新規違反との境界と修正期限を失う。3分類5 logical occurrencesを台帳化し、ignore storeは作らない。 |
| Cを早期接続して常時Fullで検査する | 不採用 | isolated U1/A/B/D、baseline修正、real repository 0件の証跡前に既存gateを不安定化する。Stage 4で接続する。 |

## 3. 正本へ固定した契約

### Catalogとpolicy

catalogのtop-levelは`schemaVersion`と可変`policies[]`である。Phase 1のproduction catalog固定pathは`config/project-lint-policies.json`であり、本記録でもその実装pathを正本とする。policy必須fieldは次の7つだけであり、policy entryへschemaVersionを重複させない。`targets`は`seams`（array）、`scopes`（array）、`include`（array）、`diagnosticTarget`（string）を必須nested keyとし、`exceptions`の各entryは`path`、`reason`、`expiresAt`、`reviewer`を必須とする（例外なしは`[]`）。`policies[]`の件数は可変だが、未登録の第7 policyのように接続定義がないentryは拒否する。schemaVersionは数値1だけを受け入れ、`1.1`、`0.9`、bool、stringを拒否する。`1e0`はJSON parse後の数学的な数値1として許容する。

`policyId`、`engineRuleId`、`adapterOwner`、`phase`、`severity`、`targets`、`exceptions`

Phase 1のownerは、PF-GATE-001=B（repository validator）、PF-FE-001=A、PF-FE-002=A、PF-TEST-001=B、PF-SUPPRESS-001=A、PF-OBS-001=Dとした。Cはpolicyを実装せず、公開A/B/Dをorchestrateする。B directのunknown schema/inputはexit 2、C経由のchild exit 2はaggregate exit 1かつ結果に`childExit=2`を残す。公開AのNode API `lintFiles`/`lintText`とinternal adapterは同じESLint設定・custom rule pathを通る同値契約とし、regexによる別実装は置かない。

### 公開seam

| seam | 正本契約 |
| --- | --- |
| U1 | RuleTester/Node API unit。期待diagnosticを検出したtest processはexit 0、RED assertion mismatchはexit 1。 |
| A | `npm --prefix frontend run --silent lint`。0=違反なし、1=規約違反、2=config/runtime/input。success stdoutは空。RuleTesterとCLI black-boxを分離する。 |
| B | `pwsh -NoProfile -File scripts/project-lint.ps1 -RepositoryRoot <abs> [-Format Text\|Json]`。0/1/2を固定し、isolated fixture repositoryで公開Bを子process実行する。 |
| D | `backend\mvnw.cmd ... -Dtest=EndpointMetadataRegistryContractTest test`。対象はbean型packageが`com.example.dailyreport`で始まり、normalized routeが`/api/`で始まるapplication-owned HandlerMethodのみ。framework/error/actuator/staticは除外し、明示HTTP methodなしのapplication `/api/**` mappingは違反、明示各methodは別keyへ展開する。TC-PFL-102〜105でframework mapping除外、non-API application handler除外、methodless違反、multi-method別key展開を各一原因で検証する。BはSpring snapshotを生成しない。 |
| C | `check.contract.tests.ps1`からisolated repo/shimで公開`check.ps1`をblack-box実行する。TC-PFL-025はproduction catalog固定path `config/project-lint-policies.json`のselector fallbackを検証し、`SchemaVersion=1`、`ExecutionScope=Full`、`ChangedFiles` count=1/value=`config/project-lint-policies.json`、`SelectedLayers=9`、`ExcludedLayers=0`、`FallbackUsed=true`、`FallbackReason` exact=`IMPACT_SELECTOR_OR_GATE_CHANGED: config/project-lint-policies.json`、`FullReason` empty、`LayerReasons=9`、C exit 0を固定する。scope unavailableは既存check.ps1回帰へ委譲する。fake runnerを内部dot-sourceせず、C自身は0/1 aggregateとする。 |

診断schemaは`policyId`、`engineRuleId`、`severity`、repository-relative `path`、nullable `line`、nullable `column`、nullable `rule`、`message`、nullable `code`で固定する。catalog由来の値はuntrustedとして扱い、診断identityへ補間せず、stdout/stderrのcanaryを漏えいさせない。null位置はTextで`path:-:-`と表現する。sort、deterministic bytes、stdout/stderr双方のsecret canary不在、root外、path/CRLF、strict UTF-8入力、unknown schemaをテスト契約へ固定した。

### Policyの責務

- PF-FE-001: production `frontend/src`でapiClient以外のglobal `fetch`、`document.cookie` read/write、ad-hoc CSRF cookie/headerを禁止する。shadowed fetchは合法境界とする。
- PF-FE-002: sharedはfeature/appを参照せず、featureはapp/他featureを参照せず、appはfeatureを統合する。sharedは`shared/types`のみ、featureは`auth/types`と`shared/types`をtype-only許可する。RuleTesterはAST、Node APIは`isPathIgnored`/`calculateConfigForFile`/`lintFiles`を受け持ち、actual `frontend/scripts/lcov-to-html.mjs`とNode globalsをtargetにする。
- PF-TEST-001: frontend Unit/E2E/Oracle、backend Test/ITのplacement、runner cross-import、support内test登録を検査する。fixture manifest/runner command属性は導入せず、trace ID文字列は除外する。
- PF-SUPPRESS-001: A raw directive analyzerでexplicit rule IDと直前物理行`// Why not: <nonempty>`を要求する。custom report自身をsuppressionで隠さない。
- PF-OBS-001: Dが対象のSpring mappingをcentral registryと比較し、feature/useCase、method、normalized route、HandlerMethodのUNKNOWN/orphan/duplicateを拒否する。対象はbean型packageが`com.example.dailyreport`で始まり、normalized routeが`/api/`で始まるapplication-owned HandlerMethodのみで、framework/error/actuator/staticを除外する。明示HTTP methodなしのapplication `/api/**` mappingは違反、明示各methodは別keyへ展開する。RequestContext/interceptorはregistryをconsumeする。

### Scope、Stage、baseline

Docsは既存markdownのみで新policyを作らない。FrontendはPF-GATE-001、PF-FE-001、PF-FE-002、PF-TEST-001、PF-SUPPRESS-001、BackendはPF-GATE-001、PF-TEST-001、PF-OBS-001、Harness/Mixed/Fullは6 policyすべてを適用する。Simpleは選択scopeのScope×rule matrixに列挙されたpolicyを適用する。catalog/lint script/check変更はImpactでHarnessまたはFull fallbackとする。Quick/PrePushは既存軽量契約を維持する。

Stage 0はcontracts/cases/trace固定、TC/RT 105/105の一対一、独立レビューP0/P1、利用者承認、Git固定点記録を完了した実装前履歴である。Stage 1はisolated U1/A/B/DのRED→GREEN、Stage 2はbaseline 5 occurrence修正とcentral registry migration、Stage 3はreal repository A/B/D zero、Stage 4はC/CI connectionとblack-box、Stage 5はstandards/records/post-reviewとして実施した。A REDはTC-PFL-070のexpected signature mismatchによるtest process `exit 1`、TC-PFL-013はGREEN限定とした。

baseline台帳は3分類5 logical occurrencesである。TC-PFL-074は固定HEAD `905a9676a7d48a86bf9aab6fb34dcbf08c65f402`とのblob一致を確認したが、Stage 1後・Stage 2前の公開A/D実行artifactを取得・不変保存していないため、`evidenceStatus=notCaptured`、`decision=hold`とする。対象5ファイルは`backend/src/main/java/com/example/dailyreport/observability/RequestContext.java`、`backend/src/main/java/com/example/dailyreport/observability/RequestMetadataInterceptor.java`、`frontend/src/monthlySummary/MonthlySummaryPage.tsx`、`frontend/src/dailyReport/DailyReportPendingApprovalList.tsx`、`frontend/eslint.config.mjs`である。修正後の結果はTC-PFL-078〜082へ分離し、`FIND-PFL-BASE-001` groups、`FIND-PFL-BASE-002` messages、`FIND-PFL-BASE-003` MonthlySummary、`FIND-PFL-BASE-004` PendingApproval、`FIND-PFL-BASE-005` lcov targetのexact 5 logical occurrencesを解消済みとして記録する。

| baseline ID | 分類 | occurrence | 対象 | 状態 |
| --- | --- | ---: | --- | --- |
| FIND-PFL-BASE-001 | endpoint metadata | 1 | `GET /api/master/groups` | 解消済み。`EndpointMetadataRegistry.java`、`EndpointMetadataRegistryContractTest::tcPfl078GroupsBaseline`、D focused 24/24・D 18/18。 |
| FIND-PFL-BASE-002 | endpoint metadata | 1 | `GET /api/master/messages` | 解消済み。`EndpointMetadataRegistry.java`、`EndpointMetadataRegistryContractTest::tcPfl079MessagesBaseline`、D focused 24/24・D 18/18。 |
| FIND-PFL-BASE-003 | suppression | 1 | MonthlySummaryの直前`Why not:`不足 | 解消済み。`MonthlySummaryPage.tsx`、`frontend/test/lint/baselineSuppression.test.ts::TC-PFL-080`、A成功。 |
| FIND-PFL-BASE-004 | suppression | 1 | DailyReportPendingApprovalListの直前`Why not:`不足 | 解消済み。`DailyReportPendingApprovalList.tsx`、`frontend/test/lint/baselineSuppression.test.ts::TC-PFL-081`、A成功。 |
| FIND-PFL-BASE-005 | Frontend target | 1 | `frontend/scripts/lcov-to-html.mjs`の無宣言除外 | 解消済み。`frontend/eslint.config.mjs`、`moduleMatrix.config.test.ts::TC-PFL-082`、A成功。 |

### Review FIND canonical references

| FIND ID | 正本 | status |
| --- | --- | --- |
| FIND-PFL-REV-001 | 正本: `日報登録編集_指摘一覧.md` 該当行 | 個別対応・post-reviewで証跡確認済み |
| FIND-PFL-REV-002 | 正本: `日報登録編集_指摘一覧.md` 該当行 | 標準化候補・B 48 cases × Text/Json 96/96で確認済み |
| FIND-PFL-REV-003 | 正本: `日報登録編集_指摘一覧.md` 該当行 | 標準化候補・C/B/D接続を契約テストで確認済み |
| FIND-PFL-REV-004 | 正本: `日報登録編集_指摘一覧.md` 該当行 | 標準化候補・A/Frontend 190 testsで確認済み |
| FIND-PFL-REV-005 | 正本: `日報登録編集_指摘一覧.md` 該当行 | 標準化候補・Frontend 190 testsで確認済み |
| FIND-PFL-REV-006 | 正本: `日報登録編集_指摘一覧.md` 該当行 | 標準化候補・B placement contractで確認済み |
| FIND-PFL-REV-007 | 正本: `日報登録編集_指摘一覧.md` 該当行 | 標準化候補・suppression unit/Aで確認済み |
| FIND-PFL-REV-008 | 正本: `日報登録編集_指摘一覧.md` 該当行 | 標準化候補・D live mapping 24/24で確認済み |
| FIND-PFL-REV-009 | 正本: `日報登録編集_指摘一覧.md` 該当行 | 標準化候補・C black-box契約で確認済み |
| FIND-PFL-REV-010 | 正本: `日報登録編集_指摘一覧.md` 該当行 | 個別対応・baseline 5件の修正後回帰を確認済み |
| FIND-PFL-REV-011 | 正本: `日報登録編集_指摘一覧.md` 該当行 | 既存観点で対応・一原因/exact expectedを確認済み |
| FIND-PFL-REV-012 | 正本: `日報登録編集_指摘一覧.md` 該当行 | 標準化候補・TC/RT traceとRED/GREEN証跡を確認済み |
| FIND-PFL-REV-013 | 正本: `日報登録編集_指摘一覧.md` 該当行 | 標準化候補・B IO/diagnostic contractで確認済み |
| FIND-PFL-REV-014 | 正本: `日報登録編集_指摘一覧.md` 該当行 | 既存観点で対応・資料リンクと承認履歴を確認済み |

severity downgradeまたはpolicy削除は、ADR更新、対応FIND、利用者承認の三点が揃うまで実施しない。

## 4. 公式資料と記録

2026-09-01に公式一次資料を確認した。

- [ESLint Custom Rules](https://eslint.org/docs/latest/extend/custom-rules)
- [ESLint Node.js API / RuleTester](https://eslint.org/docs/latest/integrate/nodejs-api#ruletester)
- [ESLint Node.js API](https://eslint.org/docs/latest/integrate/nodejs-api)
- [ESLint Formatters](https://eslint.org/docs/latest/use/formatters/)
- [ESLint Configuration Files](https://eslint.org/docs/latest/use/configure/configuration-files)
- [ESLint Disabling Rules](https://eslint.org/docs/latest/use/configure/rules#disabling-rules)
- [Spring Framework `RequestMapping`](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-controller/ann-requestmapping.html)
- [Spring Framework Handler Mappings](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-servlet/handlermapping.html)
- [PowerShell about_Scripts](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scripts)
- [PowerShell Resolve-Path](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/resolve-path)

公式資料の確認日は2026-09-01であり、実装結果とは分離して記録する。Spring実行、A/B/C契約、Full、FrontendCoverage、Chromium E2Eの実測は2026-09-12の§7へ記録する。

固定baseline点は`905a9676a7d48a86bf9aab6fb34dcbf08c65f402`。受入実行コンテキストはcurrent `main`（main ahead 5、docs dirty）であり、2026-09-02の利用者「続けてください」の承認に基づき、fetch、branch、reset、stash、変更破棄、commit、pushは行わない。後でbranchを作る場合だけAGENTS.mdのmain clean/fetch/0 0前提を再確認する。本作業記録更新では、実装コード、validator、ESLint設定、fixture、test、workflow、`scripts/check.ps1`接続の実装済み差分を証跡として参照し、追加変更は本記録と指定標準資料に限定する。

## 5. 指摘・利用者承認・次のDo

`日報登録編集_指摘一覧.md`へ、baseline rows、FIND-PFL-REV-001〜014、FIND-PFL-P1R-001〜013、FIND-LUNA-P0-001、FIND-LUNA-P1-001/003/004〜007、P0重複行を追加・更新する。各rowの意味・重要度・分類・修正ファイル・証跡・影響範囲・保留条件は指摘一覧を正本とし、本記録では実測結果と判断根拠を要約する。

Stage 0の設計・ケース固定は履歴上完了し、Stage 1〜4の実装・実測とStage 5の記録更新を実施した。2026-09-02の利用者承認によりcurrent `main`で継続し、fetch/branch/reset/stash/commit/pushは行わない。実装後のTC/RT実行結果は正本ケースと統合品質記録へ同期する。

Phase 2 backlogはTRACE、MASTER/seed、ARCH、DATE、INPUT、DDL、SQL bindである。Oracle接続・coverage・E2Eの環境保留はPhase 2へ繰り越すのではなく、専用test DB/runnerと対象DB変更承認が揃った時点の再確認条件として管理する。

## 6. 検証と残存P0

文書更新後の読み取り確認は次のとおりである。

`@powershell
git diff --check
rg -n "PF-GATE-001|PF-FE-001|PF-FE-002|PF-TEST-001|PF-SUPPRESS-001|PF-OBS-001" docs/AI活用開発研究/作業記録 docs/AI活用開発研究/設計判断記録
rg -n "FIND-PFL-REV-" docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md
`@

Stage 1のRED→GREEN、Stage 2のbaseline 5件修正、Stage 3のreal repository 0件、Stage 4のC/CI Error伝播、Stage 5標準化は実施済みである。TC-PFL-085は実在locator・symbol/case・public runner整合、commit/SHA256、exitCodeを含む証跡検証でroot PASSとし、pin再固定も完了した。今後もdocs更新後はcanonical locatorのpinを再固定する。TC-PFL-074、BackendCoverage/Oracle/E2EOracleは根拠付き保留であり、成功したgateへ混在させない。

## 7. 実測結果・指摘対応の詳細（2026-09-12）

### 7.1 実行証跡

| 確認 | 結果 | 記録 |
| --- | --- | --- |
| Full | PASS | `scripts/check.ps1 -Mode Full`でFrontend lint/typecheck/unit 190件/build、Backend Spotless/Checkstyle/SpotBugs/PMD、全contract、project-lint、endpoint contract、connectionsを完走。 |
| FrontendCoverage | PASS | 190/190。Statements 96.08%、Branches 92.38%、Functions 97.77%、Lines 95.94%。 |
| Chromium E2E | PASS | 21/21。UI visualは挙動変更なしのためN/A。 |
| B repository validator | PASS | 48 casesをText/Json各1回、96/96 PASS。strict UTF-8、binary除外、catalog schema、untrusted diagnostic値非漏えいを含む。TC-PFL-106〜109はcanonical TC-PFL-001〜105外のレビュー追加回帰subcase。 |
| C aggregate contract | PASS | TC-PFL-020/021/022/023/024/025/074/075/076/077/083/084/092のcontract実行。TC-PFL-074の歴史baseline判定はHOLD。Cは公開`check.ps1`をblack-box実行し、childExit=2を優先してaggregate exit 1へ伝播。 |
| D / interceptor | PASS | focused D+interceptor 24/24、D 18/18。実Spring `RequestMappingHandlerMapping`とcentral registryを比較し、framework/non-API除外、methodless拒否、multi-method展開を確認。 |
| 既存回帰 | PASS | 10 scripts。Quick/PrePushはbase lintのみでcustom ruleを無効化し、設定変更時はbase `eslint .`を維持。 |

### 7.2 保留

- TC-PFL-074: 固定HEADの5 blobは照合済みだが、Stage 1直後・Stage 2前の公開A/D artifactを取得・不変保存していない。これは歴史baseline固有のHOLDであり、TC-PFL-085のsourceArtifact pinとは別契約である。fixtureの`evidenceStatus=notCaptured`、`decision=hold`、理由・再確認条件に合わせ、post-fix TC-PFL-078〜082を別判定とする。次回変更でStage 1後かつStage 2前に公開A/Dを実行し、artifact保存後にbaseline修正する。
- BackendCoverage/Oracle/E2EOracle: 固定SQL cleanupが設定済みDBを書き換えるため、対象DBの明示承認なしでは実行しない。以前のfull backend testはOracle認証`ORA-01017`で93 errors。専用test DB・runner・expected identity・cleanup承認が揃ったmain pushまたは手動実行で再確認する。
- TC-PFL-085: schema v2の19 source artifacts、105明示coverage、104 PASS＋TC-PFL-074限定HOLDを対象に、各`path::symbol/selector`の実在・case整合、public command/exit/result/stdout-stderr hash、source hash/artifact pin、commit/SHA256を検証しroot PASS。現行pinは `scripts/fixtures/project-lint/TC-PFL-085-post-review-gate/post-review.json::executionEvidence.sha256` から解決し、docsへ具体hashを複製しない。旧schema/default/all-HOLD/未許可HOLD、coverage欠落/重複、reason/recheck欠落、架空/空symbol、PASSと非0exitのnegativeも拒否する。自己申告のcompletion flagは不足・stale artifact検査を迂回できない。docs更新後は一般手順としてpinを再固定し、最終状態へ同期する。

### 7.3 指摘と標準化

P1R-001〜008（public Aのregex bypass、Quick/PrePush wrapper、D manual controller list、catalog diagnostic secret leak、childExit集約、stale docs、schemaVersion fractional、invalid UTF-8 skip）とP1R-010〜013（suppression comment token、完全module edge、re-export/dynamic import、qualified/global transport迂回）は修正済み。FIND-LUNA-P0-001（TC085証跡整合）、P1-001（Impact expected completeness）、P1-003（Stage marker chain）、P1-004（live metadata fail-closed）、P1-005（schema v2との双方向整合）、P1-006（全105 locator symbol/selector実在）、P1-007（canonical pin一元化）も修正済みで、いずれも標準化候補として指摘一覧へ記録した。P1R-009（責務集中）はregex代替を削除済みだが、`frontend/eslint-rules/index.mjs`とregistry周辺の責務分割は次回policy/owner追加時に再評価する標準化候補/HOLDとする。P1R-013の非リテラルdynamic importと再代入aliasは静的判定対象外であり、flow解析を追加する時の再確認条件を残す。

P0重複（public A bypass、CLI internal seam、fake REDのTC-PFL-012/070、TC-PFL-080/081欠落、TC-PFL-074 false historical evidence、TC-PFL-085 self-declared/stale、future seventh policy、D manual listとTC-PFL-104/105の不一致）は、対応済みまたは根拠付き保留として指摘一覧へ同期する。未登録第7 policyは可変件数の例外ではなく、gate接続なしとして拒否する。

## 8. 最終レビュー追加指摘と実測（2026-09-12）

追加findingはcanonical TC-PFL-001〜105へ新規ケースを混在させず、TC-PFL-110〜121/130〜131をreview regression subcaseとして記録した。各判定は`個別対応`、`既存観点で対応`、`標準化候補`、`対象外`、`保留`のいずれかで一意に扱う。

| 指摘ID | 問題 | 対応・証跡 | 標準化判定 | 影響範囲 | 再確認条件 |
| --- | --- | --- | --- | --- | --- |
| FIND-LUNA-P0-001 | TC-PFL-085が架空locatorや未実行PASSを通せた。 | `scripts/check.contract.tests.ps1`とTC-PFL-085 fixtureで実在path、symbol/case、public runner-case、commit/SHA256、exitCodeを検証。架空path/symbol、case不一致、PASS非0exitのnegativeを含みroot PASS。 | 標準化候補 | content gate／証跡 | evidence schemaまたはrunner形式変更時に正負のtrace/evidence整合を再実行する。 |
| FIND-LUNA-P1-001 | Impact aggregateがselected layer欠落を見逃した。 | `scripts/check.ps1`のexpected集合とQuality/Oracle許可除外、TC-PFL-121のmissing selected layerで修正。root PASS。 | 標準化候補 | C Impact | 層追加・名称変更・許可除外変更時に集合完全性とnegativeを再確認する。 |
| FIND-LUNA-P1-003 | Stage 1〜5をStage 0だけで飛ばせた。 | `scripts/check.ps1`の前段marker連鎖とTC-PFL-120で欠落前提をexit 1拒否。root PASS。 | 標準化候補 | Stage／CI | Stageまたはmarker追加時に全前段欠落順序を再確認する。 |
| FIND-LUNA-P1-004 | backend live metadata mismatchを起動時に強制していなかった。 | `EndpointMetadataRegistry.afterSingletonsInstantiated`と固定非開示例外、TC-PFL-130/131で不一致fail-closed／整合successを確認。backend contract20/20、observability32/quality PASS。 | 標準化候補 | Backend D／runtime | controller・mapping・registry lifecycle変更時に起動失敗と起動成功を再実行する。 |
| FIND-LUNA-P1-005 | content gateの実装後レビューが旧schema v1、5 artifacts、default PASSを主張し、実fixture v2と矛盾した。 | v2 fixtureと`execution-evidence.json`をschema v2、19 source artifacts、105明示coverage、104 PASS＋TC-PFL-074限定HOLDへ更新し、public command/exit/result/stdout-stderr hash、source hash/artifact pin、旧schema等のnegativeを検証。 | 標準化候補 | content gate／トレーサビリティ | schema・required artifacts・coverage/status判定変更時に文書とmachine-readable fixtureを双方向突合し、旧schema/default/all-HOLD/未許可HOLD等を再実行する。 |
| FIND-LUNA-P1-006 | locator pathだけでsymbol検証をskipでき、架空または空symbolのTCが成立し得た。 | 全105ケースを`path::symbol/selector`必須化し、PowerShell関数、Java method、TS/JS selectorの実在・case整合を検証。path-only、空、架空symbolをTC-PFL-085 negativeでreject。 | 標準化候補 | content gate／ケース実在性 | locator構文・言語・selector・case範囲変更時に全105行の実在/一致とpath-only/空/架空symbol negativeを再実行する。 |
| FIND-LUNA-P1-007 | sourceArtifact対象docsへ具体的pin値を複製すると、文書更新のたびに旧pinや一時HOLDが残る循環が生じる。 | 修正済み。現行pinは `scripts/fixtures/project-lint/TC-PFL-085-post-review-gate/post-review.json::executionEvidence.sha256` を単一正本とし、docsはlocatorだけを参照して具体hashを複製しない。文書更新後のpin再固定も完了しroot TC-PFL-084/085/121・Full PASSを確認済み。 | 標準化候補 | content gate／証跡pin運用 | sourceArtifact追加・文書更新・schema変更時に、docsへ具体hashが複製されていないこと、locatorの双方向整合、再固定後TC-PFL-085を確認する。 |
| FIND-PFL-P1R-010 | block suppressionを見逃し、文字列を誤検出した。 | `SourceCode.getAllComments()`でAST comment tokenのみ解析。`suppressionPolicy.test.ts` TC-PFL-110/111/112、focused39、全24 files 200/200。 | 標準化候補 | Frontend A／suppression | parser/ESLint更新時にline/block、string/template、Why notの正負を再確認する。 |
| FIND-PFL-P1R-011 | shared→auth、auth→appのmodule edgeが欠落した。 | `moduleMatrix.config.test.ts` TC-PFL-113/114と完全edge matrixで修正。 | 標準化候補 | Frontend A／module boundary | module層やtype-only許可の変更時に全edgeを再確認する。 |
| FIND-PFL-P1R-012 | re-export/static dynamic importを依存解析から落とした。 | AST visitorsでnamed/export-all/import expressionを追加し、TC-PFL-115/116/117で修正。 | 標準化候補 | Frontend A／依存グラフ | parser/visitor変更時にimport、type-only、named/all re-export、static dynamic importを再確認する。 |
| FIND-PFL-P1R-013 | qualified/global fetch・cookieとconst aliasでtransport禁止を迂回できた。 | global/member参照と単純const aliasを検出し、shadowingと`apiClient`例外を維持。TC-PFL-118/119、frontend 200/200。非リテラルdynamic importと再代入aliasは静的判定対象外として記録。 | 標準化候補 | Frontend A／transport・CSRF | flow解析を追加する機能変更時に対象範囲、性能、専用case、責務分割を再評価する。 |

実測はFrontend focused 39、全24 filesのlint/typecheck/build 200/200、TC-PFL-085/120/121 root PASS、backend contract20/20、observability32/quality PASSである。TC-PFL-085はschema v2、19 source artifacts、105明示coverage、104 PASS＋TC-PFL-074限定HOLDを根拠とし、現行pinは `scripts/fixtures/project-lint/TC-PFL-085-post-review-gate/post-review.json::executionEvidence.sha256` から解決する。文書更新後のpin再固定も完了している。既知HOLDはTC-PFL-074（Stage間不変artifact未取得）、BackendCoverage/Oracle/E2EOracle（対象DB変更の明示承認未取得）、P1R-009（次回policy/owner追加時の責務再評価）に限定する。
