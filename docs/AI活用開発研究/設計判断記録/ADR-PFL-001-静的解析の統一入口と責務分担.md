# ADR-PFL-001 静的解析の統一入口と責務分担

| 項目 | 内容 |
| --- | --- |
| ID | ADR-PFL-001 |
| 状態 | Accepted (Stage 0 complete) |
| 判断日 | 2026-09-01 |
| 決定者 | 利用者（品質重視モード、gpt-5.6-luna / max を承認） |

## Context

ProjectFoundationには、FrontendのAST規約、repository横断のテスト配置、Spring Controllerの公開mappingと共通metadataの整合を一つの検査関数へ集めるには責務の異なる失敗がある。一方で、各runnerが個別の規則・診断・終了コードを持つと、Full、Simple、CIで検査漏れと結果の不一致が再発する。

既知baselineは3分類、5 logical occurrencesである。TC-PFL-074はStage 1後・Stage 2前のcurrent treeで、固定HEAD `905a9676a7d48a86bf9aab6fb34dcbf08c65f402`とのblob一致を先に検証し、不一致をTC failureとする。対象5ファイルは`backend/src/main/java/com/example/dailyreport/observability/RequestContext.java`、`backend/src/main/java/com/example/dailyreport/observability/RequestMetadataInterceptor.java`、`frontend/src/monthlySummary/MonthlySummaryPage.tsx`、`frontend/src/dailyReport/DailyReportPendingApprovalList.tsx`、`frontend/eslint.config.mjs`であり、一致確認後に同じcurrent treeへ公開A/Dを実行する。結果は`FIND-PFL-BASE-001` groups、`FIND-PFL-BASE-002` messages、`FIND-PFL-BASE-003` MonthlySummary、`FIND-PFL-BASE-004` PendingApproval、`FIND-PFL-BASE-005` lcov targetのexact 5 logical occurrences・3 categoriesとする。

| baseline ID | 分類 | logical occurrence | 対象 |
| --- | --- | --- | --- |
| FIND-PFL-BASE-001 | endpoint metadata | 1 | `GET /api/master/groups` |
| FIND-PFL-BASE-002 | endpoint metadata | 1 | `GET /api/master/messages` |
| FIND-PFL-BASE-003 | suppression | 1 | `frontend/src/monthlySummary/MonthlySummaryPage.tsx`の直前`Why not:`不足 |
| FIND-PFL-BASE-004 | suppression | 1 | `frontend/src/dailyReport/DailyReportPendingApprovalList.tsx`の直前`Why not:`不足 |
| FIND-PFL-BASE-005 | Frontend target | 1 | `frontend/scripts/lcov-to-html.mjs`の無宣言lint除外 |

baselineをignore storeへ移すと、新規違反との境界と修正期限が失われるため、ignore storeは作らない。endpoint metadataの既存表の重複は2 occurrenceの移行作業であり、6個目の分類には数えない。

TC/RT traceはTC-PFL-001〜105とRT-PFL-001〜105を一対一で固定する。TC-PFL-093〜101はFIND-PFL-REV-002、TC-PFL-102〜105はFIND-PFL-REV-008へ紐付ける。

### Review FIND canonical references

| FIND ID | 正本 | status |
| --- | --- | --- |
| FIND-PFL-REV-001 | 正本: `日報登録編集_指摘一覧.md` 該当行 | Stage0レビュー解消・Do開始可 |
| FIND-PFL-REV-002 | 正本: `日報登録編集_指摘一覧.md` 該当行 | Stage0レビュー解消・Do開始可 |
| FIND-PFL-REV-003 | 正本: `日報登録編集_指摘一覧.md` 該当行 | Stage0レビュー解消・Do開始可 |
| FIND-PFL-REV-004 | 正本: `日報登録編集_指摘一覧.md` 該当行 | Stage0レビュー解消・Do開始可 |
| FIND-PFL-REV-005 | 正本: `日報登録編集_指摘一覧.md` 該当行 | Stage0レビュー解消・Do開始可 |
| FIND-PFL-REV-006 | 正本: `日報登録編集_指摘一覧.md` 該当行 | Stage0レビュー解消・Do開始可 |
| FIND-PFL-REV-007 | 正本: `日報登録編集_指摘一覧.md` 該当行 | Stage0レビュー解消・Do開始可 |
| FIND-PFL-REV-008 | 正本: `日報登録編集_指摘一覧.md` 該当行 | Stage0レビュー解消・Do開始可 |
| FIND-PFL-REV-009 | 正本: `日報登録編集_指摘一覧.md` 該当行 | Stage0レビュー解消・Do開始可 |
| FIND-PFL-REV-010 | 正本: `日報登録編集_指摘一覧.md` 該当行 | Stage0レビュー解消・Do開始可 |
| FIND-PFL-REV-011 | 正本: `日報登録編集_指摘一覧.md` 該当行 | Stage0レビュー解消・Do開始可 |
| FIND-PFL-REV-012 | 正本: `日報登録編集_指摘一覧.md` 該当行 | Stage0レビュー解消・Do開始可 |
| FIND-PFL-REV-013 | 正本: `日報登録編集_指摘一覧.md` 該当行 | Stage0レビュー解消・Do開始可 |
| FIND-PFL-REV-014 | 正本: `日報登録編集_指摘一覧.md` 該当行 | Stage0レビュー解消・Do開始可 |

## Decision

### 1. Hybrid deep moduleと可変catalog

可変ルールcatalogを正本としたhybrid deep moduleを採用する。外部へ公開するseamはU1、A、B、D、Cの契約だけとし、個別ruleのparser、fixture形式、process起動、Spring adapterの内部構造は公開しない。利用者が参照するのはcatalogのpolicy ID、diagnostic契約、seam、owner、gate接続である。

catalogは固定件数にしない。Phase 1のproduction catalog固定pathは`config/project-lint-policies.json`とし、このADRで実装予定pathの正本を固定する。トップレベルのschemaは次の2 fieldを持つ。

`@json
{
  "schemaVersion": 1,
  "policies": []
}
`@

`policies[]`の各policy entryは次の7 fieldを必須とする。policy entryへ`schemaVersion`を重複して置かない。`policies[]`の件数は可変であり、Phase 1の6 policyは最低限の必須集合である。

| 必須field | 契約 |
| --- | --- |
| `policyId` | `PF-`で始まる一意の要求ID |
| `engineRuleId` | engine内で一意のrule ID |
| `adapterOwner` | A、B、またはD。catalog validatorはB、orchestratorはCとして役割を固定する |
| `phase` | Phase番号。Phase 1 entryは`1` |
| `severity` | `Error`を初期値とし、catalog外からdowngradeしない |
| `targets` | `seams`（array）、`scopes`（array）、`include`（array）、`diagnosticTarget`（string）を必須nested keyとするobject |
| `exceptions` | 各entryは`path`、`reason`、`expiresAt`、`reviewer`を必須とする配列。例外なしは`[]` |

PF-GATE-001（owner=B repository validator）はschemaVersion、required field、required ID、policyId/engineRuleIdの重複、owner、severity、gate connectionを検査する。Bの直接実行ではunknown schemaまたは不正inputをexit 2とする。Cはpolicyを実装せず、公開B/A/Dの結果をorchestrateするだけである。C経由でchild exit 2が起きた場合はC=1とし、結果に`childExit=2`と原因を残す。

### 2. Phase 1の6 policy

| policyId | engineRuleId | adapterOwner | Phase 1の責務 |
| --- | --- | --- | --- |
| PF-GATE-001 | `gate/catalog-owner-and-connections` | B | catalog schema、required ID、owner、全gate connection |
| PF-FE-001 | `frontend/no-direct-transport-access` | A | production Frontendのglobal fetch、`document.cookie`、ad-hoc CSRFを拒否 |
| PF-FE-002 | `frontend/module-matrix-and-target-coverage` | A | module dependency matrixとlint target coverage |
| PF-TEST-001 | `repository/test-placement-runner-separation` | B | test placement、runner separation、support test禁止 |
| PF-SUPPRESS-001 | `frontend/suppression-reason` | A | raw ESLint suppression directiveのIDと直前理由 |
| PF-OBS-001 | `backend/endpoint-metadata-registry` | D | application-owned `/api/` HandlerMethodのSpring live mappingと中央metadata registryの整合 |

PF-FE-001はproduction `frontend/src/**/*.ts` / `frontend/src/**/*.tsx`を対象とし、`frontend/src/shared/apiClient.ts`だけをtransport/CSRFの例外とする。global `fetch`、`document.cookie`のread/write、ad-hoc CSRF cookie/headerを禁止する。shadowed local `fetch`とtest/E2E scopeは境界ケースとして扱うが、productionの例外にはしない。

PF-FE-002のmatrixは次を固定する。

| import元 | 許可 | 禁止 | type-only例外 |
| --- | --- | --- | --- |
| shared | shared | feature、app | `shared/types`のみ |
| feature | 同一feature、shared | app、他feature | `auth/types`と`shared/types` |
| app | shared、auth、feature | feature同士の横結合をapp外へ漏らすこと | matrixの型規則 |
| auth | auth、shared | feature | `shared/types` |

AST検査はRuleTesterを使い、ignore/configはESLint Node APIの`isPathIgnored`、`calculateConfigForFile`、`lintFiles`でintegration検査する。実ファイル`frontend/scripts/lcov-to-html.mjs`をtargetに含め、Node globalsを設定する。RuleTester自体でignore判定を代用しない。

PF-TEST-001は`frontend/test` Unit、`frontend/e2e` E2E、Oracle E2E、`backend/src/test`のTest/ITを走査する。Unit/E2E/Oracle/backend runner間のcross-importと`support`配下のtest登録を禁止する。fixtureにmanifestやrunner command属性を導入しない。`traceId`、`requestId`等の文字列だけはtest定義として数えない。

PF-SUPPRESS-001はAのraw directive analyzerをownerとする。`eslint-disable`、`eslint-disable-line`、`eslint-disable-next-line`にはexplicit rule IDを列挙し、直前の物理行を`// Why not: <nonempty>`とする。custom ESLint reportを自身のsuppressionで隠す方式は採用しない。

PF-OBS-001はDをownerとする。Dの対象は、bean型のpackageが`com.example.dailyreport`で始まり、normalized routeが`/api/`で始まるapplication-owned `HandlerMethod`のみ。framework/error/actuator/staticは除外する。application `/api/**` mappingで明示HTTP methodがないものは違反とし、明示された各methodを別keyへ展開する。実Spring `RequestMappingHandlerMapping`が列挙する対象mappingの`RequestMappingInfo`と`HandlerMethod`を中央`EndpointMetadataRegistry`とin-memory比較する。keyはHTTP method + normalized routeであり、feature/useCase、HTTP method、normalized route、HandlerMethodは欠落または`UNKNOWN`を許さない。orphan、duplicate、不一致を失敗にする。TC-PFL-102〜105でframework mapping除外、non-API application handler除外、methodless application `/api/**`違反、multi-method別key展開を各一原因で検証する。`RequestContext`とinterceptorは中央registryをconsumeし、別route表を持たない。BはSpring snapshotを生成しない。

### 3. 公開seamと結果契約

| seam | 公開入口 | owner | 成功・失敗 |
| --- | --- | --- | --- |
| U1 | RuleTester / Node API unit | AまたはDの各rule test | 期待diagnosticを検出したtest processはexit 0。REDのassertion mismatchはexit 1。signatureは固定する |
| A | `npm --prefix frontend run --silent lint` | A | 0=違反なし、1=規約違反、2=config/runtime/input error。package scriptは将来wrapper/custom formatterを使い、success stdoutは空 |
| B | `pwsh -NoProfile -File scripts/project-lint.ps1 -RepositoryRoot <abs> [-Format Text\|Json]` | B | 0=違反なし、1=規約違反、2=root/path/schema/input/runtime error |
| D | `backend\mvnw.cmd ... -Dtest=EndpointMetadataRegistryContractTest test` | D | 実Spring live mapping全件とregistryのcontract result |
| C | 公開`check.ps1`を`check.contract.tests.ps1`からisolated repo/shimでblack-box実行 | C | C自身は0/1のaggregate。child 2はresultに`childExit=2`を残してC=1 |

AのCLI exit契約はRuleTesterの診断assertionと分離したblack-box RTで検証する。A REDはTC-PFL-070のexpected signature mismatchでtest process `exit 1`に固定し、TC-PFL-013はGREEN限定とする。BのText/Jsonは同一diagnostic集合とし、共通schemaは`policyId`、`engineRuleId`、`severity`、repository-relative `path`、nullable `line`、nullable `column`、nullable `rule`、`message`、nullable `code`とする。null位置はTextで`path:-:-`と表現し、0や空文字へ置換しない。sortはpolicyId、path、line（nullは後）、column（nullは後）、messageの順とする。diagnostic bytesは決定的で、stdoutとstderrの双方にsecret、Cookie、token、接続情報、secret canaryを出さない。

Cの実行形は次のとおりである。Cのfake runnerを内部dot-sourceせず、isolated repositoryとshimから公開Cを呼ぶ。

| 実行形 | 入口 | 完了判定 |
| --- | --- | --- |
| Local Full | `pwsh -NoProfile -File scripts/check.ps1 -Mode Full` | catalog、A、B、D、既存Full checksが全て0ならC=0 |
| Simple Scope | `pwsh -NoProfile -File scripts/check.ps1 -Mode Simple -Scope <declared-scope>` | 選択scopeのScope×rule matrixに列挙されたpolicyだけを実行し、列挙policyの欠落はC=1 |
| CiTask FullFrontend | `pwsh -NoProfile -File scripts/check.ps1 -CiTask FullFrontend` | A、Frontend contract、catalogが全て0 |
| CiTask FullBackend/contract | `pwsh -NoProfile -File scripts/check.ps1 -CiTask FullBackend` | B、D、Backend/contract、catalogが全て0 |
| Impact Plan fallback / Aggregate | `pwsh -NoProfile -File scripts/check.ps1 -Mode Impact -ImpactTask Plan -ChangedFilesPath <abs-changed-files-path> -ImpactPlanPath <abs-plan-path>`または`pwsh -NoProfile -File scripts/check.ps1 -Mode Impact -ImpactTask Aggregate -ImpactPlanPath <abs-plan> -ImpactResultPath <abs-result> -ImpactJobResultsJson <json> -ImpactJobMap <map>` | production catalog固定path `config/project-lint-policies.json`のselector変更をTC-PFL-025で検証する。ChangedFilesPathはそのpathの1行だけを持つUTF-8 future fileとし、JSON `SchemaVersion=1`、`ExecutionScope=Full`、`ChangedFiles` count=1/value=`config/project-lint-policies.json`、`SelectedLayers`=9、`ExcludedLayers`=0、`FallbackUsed=true`、`FallbackReason` exact=`IMPACT_SELECTOR_OR_GATE_CHANGED: config/project-lint-policies.json`、`FullReason` empty、`LayerReasons`=9を固定しC=0。scope unavailableは今回のTCへ混在させず既存check.ps1回帰へ委譲する。TC-PFL-092はAggregate JSON `Succeeded=false`、`Jobs`=1、selected row `Selected=true`/`JobResult=success`/`State=missing`/`Valid=false`を固定しC=1 |

Quick/PrePushは既存の軽量契約を維持し、カスタムLinterの全policyをそこへ追加しない。C/CI接続はStage 4で行う。

### 4. Scope matrix

| scope | 必須policy |
| --- | --- |
| Docs | 既存markdownのみ。新policyは作らない |
| Frontend | PF-GATE-001、PF-FE-001、PF-FE-002、PF-TEST-001、PF-SUPPRESS-001 |
| Backend | PF-GATE-001、PF-TEST-001、PF-OBS-001 |
| Harness / Mixed / Full | 6 policyすべて |

catalog、lint script、`check.ps1`の変更はImpactでHarnessまたはFull fallbackとする。scopeごとのmandatory欠落はpolicy別TCで1原因ずつ失敗させる。

### 5. Stage、Do条件、rollback

Stageは0から5の順序で進める。Stage 0はcontracts/cases/trace固定、TC/RT 105/105の一対一、独立レビューP0=0/P1=0、利用者承認、Git固定点記録を完了済みとした状態であり、Stage 1はREDから開始する。A REDはTC-PFL-070のexpected signature mismatchによるtest process `exit 1`、TC-PFL-013はGREEN限定とする。RED/GREENはDo内のmilestoneである。

| Stage | 内容 | 完了証跡 |
| --- | --- | --- |
| 0 | contracts/cases/traceを固定し、TC/RT 105/105を一対一で確認し、独立レビューをP0=0で完了して利用者承認を得る。2026-09-02の利用者「続けてください」はcurrent `main`（ahead 5、docs dirty）でDoを継続し、fetch/branch/reset/stash/commit/pushを行わない承認であり、後でbranchを作る場合だけAGENTS.md前提を再確認する | AC/TC/RT、exact command、fixture、P0=0、承認、Git context |
| 1 | isolated U1/A/B/DをREDから開始してGREENまで実行。A REDはTC-PFL-070、TC-PFL-013はGREEN限定。DはTC-PFL-102〜105の境界を各一原因で実行 | exit、diagnostic bytes、nullable position、Spring registry比較 |
| 2 | baselineの5 logical occurrencesを修正し、central registryへ移行 | 5件のdiff、FIND再判定、metadata migration |
| 3 | real repositoryでA/B/Dを実行し0件 | root固定のreport |
| 4 | C/CI接続とblack-box contract、child error伝播 | C contract、CI job結果 |
| 5 | standards、records、post-review、利用者承認を更新 | 標準化判定、再レビュー、最終gate |

Stage0レビュー解消・Do開始可。Do開始条件であるStage 0（contracts/cases/trace固定、独立レビューP0=0/P1=0、利用者承認、Git固定点記録）は完了済みである。Stage 1のRED開始、baseline修正、C/CI接続、Final gateはDo内のmilestoneである。rollbackはcatalog entry、A/U1 rule、B adapter、D registry、C接続を独立単位で戻し、baselineをignoreへ変換しない。severity downgradeまたはpolicy削除はADR更新、対応FIND、利用者承認の全てを必須とする。

### 6. 代替案比較

| 方式 | 判断 | 理由 |
| --- | --- | --- |
| native existing tests/config | 不採用 | 業務回帰には使えるがcatalog field、owner/seam、配置横断、gate connectionを一意に証明しない |
| Java static parser | 不採用 | annotation文字列はSpringが実際に登録したmapping、合成route、HandlerMethodを証明しない |
| Spring introspection | 採用 | live `RequestMappingHandlerMapping`と`HandlerMethod`を取得してcentral registryと比較できる |
| controller annotations/generation | 補助・Phase 2再評価 | 入力補助には使えるがruntime mappingの正本にしない |
| no central catalog | 不採用 | policy ID、severity、owner、例外、gate接続が分散し、検査漏れが再発する |

### 7. Phase 2 backlog

| ID | 対象 | 再開条件 |
| --- | --- | --- |
| TRACE | AC→TC→RT→実test→command→artifact | 全TCを一行ずつ突合し、未実行を成功扱いしない |
| MASTER/seed | master data、seed、fixture | ID、seed、cleanupを独立fixtureとして承認 |
| ARCH | module/adapter/owner構造 | 依存方向と共通化境界をADRで決定 |
| DATE | route/date/CRLF/timezone境界 | timezone、line ending、境界fixtureを固定 |
| INPUT | path/schema/format/secret入力 | malformed分類と失敗diagnosticを承認 |
| DDL | Oracle DDL、制約、test schema | Oracle runnerとDDL変更を別計画で承認 |
| SQL bind | bind変数、parameter、query logging | bind、ログ非開示、Oracle実機ケースを固定 |

## Decision log・公式資料

2026-09-01に次の公式一次資料を確認した。

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

固定Git点は`905a9676a7d48a86bf9aab6fb34dcbf08c65f402`。受入実行コンテキストはcurrent `main`（main ahead 5、docs dirty）であり、2026-09-02の利用者「続けてください」の承認に基づき、fetch、branch、reset、stash、commit、pushは行わない。後でbranchを作る場合だけAGENTS.mdのmain clean/fetch/0 0前提を再確認する。実装コード、テストコード、fixture、workflow、`check.ps1`接続は本ADRの修復では変更しない。

## Related records and exit

- [カスタムLinter 実装計画](../作業記録/カスタムLinter_実装計画.md)
- [カスタムLinter テストケース](../作業記録/カスタムLinter_テストケース.md)
- [カスタムLinter 実装前レビュー](../作業記録/カスタムLinter_実装前レビュー.md)
- [カスタムLinter 統合品質記録](../作業記録/カスタムLinter_統合品質記録.md)
- [カスタムLinter 作業記録](../作業記録/カスタムLinter_作業記録.md)
- [日報登録編集 指摘一覧](../作業記録/日報登録編集_指摘一覧.md)

本ADRは`Accepted (Stage 0 complete)`である。独立再レビューP0=0/P1=0、TC/RT 105/105、利用者承認、Git固定点を確認済みであり、Do開始を許可する。実装、U1/A/B/D/C、CI、Stage 1以降の実行結果は未実施であり、成功扱いしない。FIND-PFL-BASE-001〜005は未解消・Stage 2待ちのままとする。Stage 1以降の実行証跡と最終gateはDoのmilestoneとして記録し、ADRの受入判定と混同しない。
