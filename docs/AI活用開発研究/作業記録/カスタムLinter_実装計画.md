# カスタムLinter 実装計画

## 1. 前提・固定点

- 利用者承認: 2026-09-01に品質重視モード、およびgpt-5.6-luna / maxを承認済み。
- 作業状態: Stage 1〜4の実装・契約テスト・既存gate接続を完了し、Stage 5の標準化記録を更新済み。利用可能な通常gateは成功し、TC-PFL-085は実在locator・symbol/case・public runner整合、commit/SHA256、exitCodeを含む証跡検証でroot PASSとした。現行sourceArtifact pinの正本は `scripts/fixtures/project-lint/TC-PFL-085-post-review-gate/post-review.json::executionEvidence.sha256` とし、本文はlocatorだけを参照する。文書更新後のpin再固定も完了している。TC-PFL-074の歴史baseline証跡とOracle系coverage/E2Eは保留として扱う。
- Git固定: preflight固定点は`905a9676a7d48a86bf9aab6fb34dcbf08c65f402`。2026-09-02の利用者「続けてください」は、current `main`（main ahead 5、docs dirty）でDoを継続し、fetch、branch作成、reset、stash、commit、pushを行わない承認として記録する。後でbranchを作る要求が生じた場合だけAGENTS.mdのmain clean/fetch/0 0前提を再確認する。
- 正本: `カスタムLinter_テストケース.md`をAC/TC/RTのsourceとし、FINDの意味は`日報登録編集_指摘一覧.md`のcanonical rowをsourceとする。他文書はFIND ID、正本、statusだけを記載する。
- TC/RT trace: 正本テストケースはTC-PFL-001〜105とRT-PFL-001〜105を一対一で固定する。TC-PFL-093〜101はFIND-PFL-REV-002、TC-PFL-102〜105はFIND-PFL-REV-008へ紐付ける。

## 2. 目的・In / Out

### 目的

可変catalogを唯一のpolicy定義とし、U1 RuleTester、A Frontend CLI、B repository validator、D Spring contract、C aggregateの責務・診断・終了コードを固定する。Phase 1の新規違反と既知baselineを分離し、C/CI接続前にA/B/Dの実証を終える。

Phase 1のproduction catalog固定pathは`config/project-lint-policies.json`とし、本計画をその実装pathの正本とする。

### In

- PF-GATE-001、PF-FE-001、PF-FE-002、PF-TEST-001、PF-SUPPRESS-001、PF-OBS-001。
- catalog schema、module matrix、test placement/runner separation、抑制、Spring mappingとcentral metadata registry、診断bytes、root安全性、stdout/stderr redaction。
- Scope matrix、U1/A/B/D/Cの公開契約、baseline 3分類5 logical occurrences、Stage 0 through Stage 5、rollback、P0/P1独立レビュー。

### Out

- 業務API、業務DB、DDL、SQL意味論、画面動作のテスト。
- PMD、ArchUnit、自動修正、IDE/PR連携、Phase 2のmaster/seed、trace、DDL、SQL bindの実装。
- 業務API、業務DB、DDL、SQL意味論、画面動作の機能変更は対象外。これらを扱うOracle実機確認は、今回のLinter gateの保留条件として別途記録する。

## 3. 可変catalog契約

トップレベルは`schemaVersion`と可変長`policies[]`だけを正本とする。policy entryの必須fieldは次の7つであり、件数は6件に固定しない。

| 必須field | 契約 |
| --- | --- |
| `policyId` | `PF-`で始まる一意ID。Phase 1の6 IDを含む。 |
| `engineRuleId` | engine上の一意ID。catalog内で重複しない。 |
| `adapterOwner` | `B`、`A`、`D`のいずれか。Cはpolicyを実装せずorchestrateのみ。 |
| `phase` | Phase番号。Phase 1 entryは`1`。 |
| `severity` | 初期値`Error`。catalog外からdowngradeしない。 |
| `targets` | `seams`（array）、`scopes`（array）、`include`（array）、`diagnosticTarget`（string）を必須nested keyとするobject。 |
| `exceptions` | 各entryは`path`、`reason`、`expiresAt`、`reviewer`を必須とする配列。例外なしは`[]`。 |

トップレベルとentryの最小例:

```json
{
  "schemaVersion": 1,
  "policies": [
    {
      "policyId": "PF-FE-001",
      "engineRuleId": "frontend/no-direct-transport-access",
      "adapterOwner": "A",
      "phase": 1,
      "severity": "Error",
      "targets": {
        "seams": ["A"],
        "scopes": ["frontend/src/**/*.ts(x)"],
        "include": ["frontend/src"],
        "diagnosticTarget": "global transport access"
      },
      "exceptions": []
    }
  ]
}
```

PF-GATE-001（B）はschemaVersionの対応可否、7必須field、policyId/engineRuleIdの一意性、Phase 1 required ID、adapterOwner、全gate接続を検査する。schemaVersionは数値として数学的に1である値だけを受け入れ、`1.1`、`0.9`、boolean、stringを拒否する。JSON `1e0`はParse後の数値1であり、字面の表記揺れを契約に含めないため許容する。missing propertyのdiagnosticはプロパティ位置を捏造せず、親objectの固定位置（`line=1,column=1`）をanchorにし、`rule=null`を記録する。未知schema/inputのB直接実行はexit 2とする。`policies[]`の件数は可変だが、未登録の第7 policyなど接続定義のないpolicyは`MISSING_GATE_CONNECTION`として拒否する。severity downgradeまたはpolicy削除には、更新ADR、対応FIND、利用者承認を必須とする。

TC-PFL-093〜096は`targets.seams`、`targets.scopes`、`targets.include`、`targets.diagnosticTarget`の欠落を各一原因で検出する。TC-PFL-097〜100は非空exception entryの`path`、`reason`、`expiresAt`、`reviewer`の欠落を各一原因で検出し、TC-PFL-101は4必須fieldを持つ非空exception entryを1件受け入れる。

## 4. Phase 1 policyと責務

| policyId | engineRuleId | adapterOwner | 検査契約 |
| --- | --- | --- | --- |
| PF-GATE-001 | `gate/catalog-owner-and-connections` | B | catalog schema、required ID、owner、U1/A/B/D/C接続 |
| PF-FE-001 | `frontend/no-direct-transport-access` | A | production `frontend/src`でapiClient以外のglobal fetch、`document.cookie` read/write、ad-hoc CSRF token/headerを拒否。shadowed fetchは許可。 |
| PF-FE-002 | `frontend/module-matrix-and-target-coverage` | A | sharedはfeatureへ依存しない、featureはapp/他featureへ依存しない、appはfeatureを統合する。sharedは`shared/types`のみ、featureは`auth/types`と`shared/types`のtype-only importを許可し、runtime importは拒否。 |
| PF-TEST-001 | `repository/test-placement-runner-separation` | B | Unit/E2E/Oracle/backend Test/ITの配置、runner間cross-import、support内test登録を検査。`traceId`/`requestId`値はtest定義と数えない。fixture manifest/runner command属性は導入しない。 |
| PF-SUPPRESS-001 | `frontend/suppression-reason` | A | raw ESLint directiveを解析し、explicit rule IDと直前物理行の`// Why not: <nonempty>`を必須化。custom report自身を抑制する方式は採用しない。 |
| PF-OBS-001 | `backend/endpoint-metadata-registry` | D | bean型packageが`com.example.dailyreport`で始まりnormalized routeが`/api/`で始まるapplication-owned HandlerMethodのみを対象に、Spring `RequestMappingHandlerMapping`のmappingとcentral `EndpointMetadataRegistry`をHTTP method + normalized route + HandlerMethodで比較。framework/error/actuator/staticは除外し、明示HTTP methodなしのapplication `/api/**` mappingは違反、明示各methodは別keyへ展開する。`feature`/`useCase`は非`UNKNOWN`。RequestContext/interceptorはregistryをconsumeする。 |

PF-OBS-001の正式seamはDである。Dの対象は、bean型のpackageが`com.example.dailyreport`で始まり、normalized routeが`/api/`で始まるapplication-owned `HandlerMethod`のみ。framework/error/actuator/staticは除外する。application `/api/**` mappingで明示HTTP methodがないものは違反とし、明示された各methodを別keyへ展開する。Dは実Spring contextを起動し、`RequestMappingHandlerMapping`から対象mappingを列挙してin-memory registryと比較する。TC-PFL-102〜105でframework mapping除外、non-API application handler除外、methodless application `/api/**`違反、multi-method別key展開を各一原因で検証する。BはSpring snapshotを生成せず、PF-TEST-001とB入力の静的契約だけを検査する。

## 5. 公開seam・診断・終了コード

| seam | 固定入口 | 成功 | 規約違反 | 入力/実行不能 |
| --- | --- | --- | --- | --- |
| U1 | RuleTester / Node API unit | expected diagnosticを検出したtest processは`exit 0` | RED assertion mismatchはtest process `exit 1` | test runner/config故障はtest process非0。diagnostic signatureは固定する。 |
| A | `npm --prefix frontend run --silent lint` | `exit 0`、stdout空、stderr空 | `exit 1` | config/runtime/parse/inputは`exit 2` |
| B | `pwsh -NoProfile -File scripts/project-lint.ps1 -RepositoryRoot <abs> [-Format Text\|Json]` | `exit 0` | `exit 1` | root、schema、path、input、runtimeは`exit 2` |
| D | `backend\mvnw.cmd -B -Dtest=EndpointMetadataRegistryContractTest test` | JUnit `0 failures` | JUnit failure | Maven/Spring起動不能はtest失敗 |
| C | 公開`check.ps1`をblack-box実行 | aggregate `exit 0` | aggregate `exit 1` | child `exit 2`を結果の`childExit=2`へ保持し、Cは`exit 1` |

U1のRED/GREENはruleのassertionとA CLIの終了コードを混ぜない。Aのblack-box CLI testはU1とは別RTである。A REDはTC-PFL-070のexpected signature mismatchでtest process `exit 1`に固定し、TC-PFL-013はGREEN限定とする。BのText/Jsonは同一diagnostic集合を表し、共通schemaは`policyId`、`engineRuleId`、`severity`、`path`、nullable `line`、nullable `column`、nullable `rule`、`message`、nullable `code`である。Textのnull位置は`path:-:-`で固定する。missing propertyは親anchorと`rule=null`をJSONで確認する。sort keyはpolicyId、path、line、column、messageであり、reverse-order入力でもstdout bytesを完全一致させる。

### 5.1 Cの実行形

| 実行形 | 固定入口 | 必須接続 | 判定 |
| --- | --- | --- | --- |
| Local Full | `pwsh -NoProfile -File scripts/check.ps1 -Mode Full` | U1、A、B、D、既存Full | childが全て0ならC=0。 |
| Simple Scope | `pwsh -NoProfile -File scripts/check.ps1 -Mode Simple -Scope <declared-scope>` | 選択scopeのScope×rule matrixに列挙されたpolicy | 列挙されたpolicyのchild全て0ならC=0。 |
| CiTask FullFrontend | `pwsh -NoProfile -File scripts/check.ps1 -CiTask FullFrontend` | A、Frontend CLI contract、catalog | child全て0ならC=0。 |
| CiTask FullBackend/contract | `pwsh -NoProfile -File scripts/check.ps1 -CiTask FullBackend` | B、D、Backend contract、catalog | child全て0ならC=0。 |
| Impact Plan fallback / Aggregate | `pwsh -NoProfile -File scripts/check.ps1 -Mode Impact -ImpactTask Plan -ChangedFilesPath <abs-changed-files-path> -ImpactPlanPath <abs-plan-path>` または`pwsh -NoProfile -File scripts/check.ps1 -Mode Impact -ImpactTask Aggregate ...` | catalog、lint scripts、check変更はHarness/Fullへfallback | production catalog固定path `config/project-lint-policies.json`のselector変更をTC-PFL-025で検証する。ChangedFilesPathはそのpathの1行だけを持つUTF-8 future fileとし、JSON `SchemaVersion=1`、`ExecutionScope=Full`、`ChangedFiles` count=1/value=`config/project-lint-policies.json`、`SelectedLayers`=9、`ExcludedLayers`=0、`FallbackUsed=true`、`FallbackReason` exact=`IMPACT_SELECTOR_OR_GATE_CHANGED: config/project-lint-policies.json`、`FullReason` empty、`LayerReasons`=9を固定しC=0。scope unavailableは今回のTCへ混在させず既存check.ps1回帰へ委譲する。TC-PFL-092はAggregate JSON `Succeeded=false`、`Jobs`=1、selected row `Selected=true`/`JobResult=success`/`State=missing`/`Valid=false`を固定しC=1。 |

Cはfake runnerを内部dot-sourceしない。C contract testはisolated repositoryとshimを用いて公開Cをchild processとして実行する。Quick/PrePushは既存の軽量gate（空白、生成物、secret、差分lint、Markdown、Java変更時Spotless）を維持し、Cの新規policyをそこへ追加しない。

## 6. Scope × rule matrix

| scope | 適用policy | 境界・フォールバック |
| --- | --- | --- |
| Docs | 既存Markdown checksのみ | 新policyなし。 |
| Frontend | PF-GATE-001、PF-FE-001、PF-FE-002、PF-TEST-001、PF-SUPPRESS-001 | shared、feature、app、test、E2E、scripts、generated/reportをmodule matrixで分類。 |
| Backend | PF-GATE-001、PF-TEST-001、PF-OBS-001 | DのSpring live mappingとbackend Test/IT配置を含む。 |
| Harness | 6 policy | project-lint、check、fixture、runner、catalog変更を含む。 |
| Mixed | 6 policy | Frontend・Backend・Harness境界が混在する場合。 |
| Full | 6 policy | Local FullまたはCI Full。 |
| Impact | 変更scopeから選択 | catalog、lint scripts、check変更はHarness/Full fallback。mandatory policyを除外しない。 |

### 6.1 Frontend module matrix

| module | runtime依存 | type-only例外 | 対象 |
| --- | --- | --- | --- |
| `frontend/src/shared/**` | sharedだけ。feature/appへ依存しない | `shared/types`のみ | PF-FE-001/002/SUPPRESS |
| `frontend/src/<feature>/**` | 同一featureとshared。app/他featureへ依存しない | `auth/types`、`shared/types` | PF-FE-001/002/SUPPRESS |
| `frontend/src/app/**` | shared、auth、featureを統合 | matrixの型import | PF-FE-001/002/SUPPRESS |
| `frontend/src/auth/**` | auth、shared | `shared/types` | PF-FE-001/002/SUPPRESS |
| `frontend/scripts/lcov-to-html.mjs` | Node globals設定を適用し、無宣言ignoreしない | — | PF-FE-002/SUPPRESS |
| `frontend/dist/**`、`frontend/coverage/**`、`frontend/playwright-report/**`、`frontend/test-results/**` | 明示された生成物除外だけ | — | PF-FE-002の除外 |

PF-FE-002のAST境界はRuleTesterで検査し、ignore/config/target coverageはESLint Node APIの`isPathIgnored`、`calculateConfigForFile`、`lintFiles` integrationで検査する。RuleTesterはignoreを検出しないため、ignoreのGREEN/REDはNode API integrationで行う。

## 7. Test placement / runner境界

宣言rootは既存構成に合わせ、`frontend/test/**`（Unit）、`frontend/e2e/**`（E2E）、`frontend/e2e/**/*.oracle.spec.ts`（Oracle E2E）、`backend/src/test/**`（backend Test/IT）、`scripts/*.tests.ps1`と`scripts/fixtures/project-lint/**`（validator contract）とする。runnerはroot間のcross-importを作らない。`frontend/e2e/support/**`、`frontend/test/support/**`、`backend/src/test/**/support/**`へtest登録を置かない。`traceId`、`requestId`、Playwright trace metadataの文字列はtest登録として数えない。fixture manifestやrunner command属性を新設せず、pathと既存runnerの分離をBが検査する。

## 8. Baseline（3分類・5 logical occurrences）

baselineはignore storeへ移さない。TC-PFL-074の固定HEAD `905a9676a7d48a86bf9aab6fb34dcbf08c65f402`との5 blob照合は実施済みだが、Stage 1直後・Stage 2前の公開A/D実行artifactを取得・不変保存していないため、`evidenceStatus=notCaptured`、`decision=hold`とする。この歴史baselineのHOLDは、TC-PFL-085の可変sourceArtifact pinとは別契約である。対象5ファイルは`backend/src/main/java/com/example/dailyreport/observability/RequestContext.java`、`backend/src/main/java/com/example/dailyreport/observability/RequestMetadataInterceptor.java`、`frontend/src/monthlySummary/MonthlySummaryPage.tsx`、`frontend/src/dailyReport/DailyReportPendingApprovalList.tsx`、`frontend/eslint.config.mjs`である。修正後のA/D結果は同じTC-PFL-074の歴史証跡に混ぜず、TC-PFL-078〜082で個別に確認する。結果は`FIND-PFL-BASE-001` groups、`FIND-PFL-BASE-002` messages、`FIND-PFL-BASE-003` MonthlySummary、`FIND-PFL-BASE-004` PendingApproval、`FIND-PFL-BASE-005` lcov targetのexact 5 logical occurrences、3 categoriesとする。endpoint metadataの既存2表（groups/messages）はendpoint metadata分類の2 logical occurrencesであり、6件目ではない。

| baseline FIND | 分類 | 対象 | logical occurrence | 解消条件 |
| --- | --- | --- | ---: | --- |
| FIND-PFL-BASE-001 | endpoint metadata | `GET /api/master/groups` | 1 | 解消済み。`EndpointMetadataRegistry.java`のcentral registry、`EndpointMetadataRegistryContractTest::tcPfl078GroupsBaseline`、D focused 24/24およびD 18/18でlive mappingとの一致を確認。 |
| FIND-PFL-BASE-002 | endpoint metadata | `GET /api/master/messages` | 1 | 解消済み。`EndpointMetadataRegistry.java`のcentral registry、`EndpointMetadataRegistryContractTest::tcPfl079MessagesBaseline`、D focused 24/24およびD 18/18でlive mappingとの一致を確認。 |
| FIND-PFL-BASE-003 | suppression | `frontend/src/monthlySummary/MonthlySummaryPage.tsx` | 1 | 解消済み。explicit rule IDと直前非空`Why not:`へ修正し、`frontend/test/lint/baselineSuppression.test.ts::TC-PFL-080`とAで確認。 |
| FIND-PFL-BASE-004 | suppression | `frontend/src/dailyReport/DailyReportPendingApprovalList.tsx` | 1 | 解消済み。explicit rule IDと直前非空`Why not:`へ修正し、`frontend/test/lint/baselineSuppression.test.ts::TC-PFL-081`とAで確認。 |
| FIND-PFL-BASE-005 | Frontend target | `frontend/eslint.config.mjs`のscripts除外 | 1 | 解消済み。`frontend/scripts/lcov-to-html.mjs`を対象化し、`frontend/test/lint/moduleMatrix.config.test.ts::TC-PFL-082`のNode API検査とAで確認。 |

### 8.1 FINDレビュー正本参照

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

## 9. Stage 0 through Stage 5

| Stage | 内容 | 完了証跡 | C接続 |
| --- | --- | --- | --- |
| 0 | contracts、cases、traceを固定し、独立レビューと利用者承認を完了した実装前履歴。 | AC/TC/RT/FIND、担当、承認、固定path、P0/P1=0、Git context | 接続しない。 |
| 1 | isolated U1/A/B/DをRED→GREENで実行。Aの意図的REDはTC-PFL-070のexpected signature mismatchでtest process `exit 1`、TC-PFL-013はGREEN限定。Bはisolated fixture、Dは実Spring live mappingでTC-PFL-102〜105を各一原因で確認。 | U1/A/B/Dのexit、diagnostic bytes、JUnit artifact。成功済み。 | 接続しない。 |
| 2 | current baseline 3分類5 logical occurrencesを修正し、Dでcentral registryへmetadataを移行。 | FIND-PFL-BASE-001〜005の修正diffとTC-PFL-078〜082再実行。5件解消済み。 | 接続しない。 |
| 3 | real repositoryでA/B/Dを実行し、新規違反0、修正後baseline 0を確認。 | `TC-PFL-083`相当のA/B/D結果、A/B stdout/stderr空、D 0 failures/0 errors。成功済み。 | 接続しない。 |
| 4 | CをLocal Full、Simple Scope、CiTask FullFrontend、FullBackend/contract、Impact fallbackへ接続し、childExit=2をErrorへ伝播。 | C non-content contractのTC-PFL-020/021/022/023/024/025/074/075/076/077/083/084/092はPASS（TC-PFL-074の歴史baseline判定はHOLD）。 | 接続済み。 |
| 5 | standards、records、post-reviewを更新し、各FINDの判定・証跡・保留条件を同期。 | 本更新、P1R-001〜013、FIND-LUNA-P0-001/P1-001/P1-003/P1-004〜007、標準化資料差分。TC-PFL-085はschema v2の証跡整合を含めroot PASSとし、現行pinは `scripts/fixtures/project-lint/TC-PFL-085-post-review-gate/post-review.json::executionEvidence.sha256` を参照する。文書更新後はpin再固定を行う。 | Quick/PrePushはbase-onlyで維持。 |

Stage 0の完了条件（contracts/cases/trace固定、TC/RT 105/105の一対一、独立レビューP0=0/P1=0、利用者承認、Git固定点の記録）は実装前の履歴として完了している。Stage 1のRED→GREEN、Stage 2のbaseline修正、Stage 3のreal repository検証、Stage 4のC接続までを実施し、Stage 5で実測結果と標準化判定を記録する。RED/GREENの成否と最終gateの成否は別々に保持する。

## 10. 固定future test path/nameとRED/GREEN

| seam / policy | 固定test path | RED command | GREEN command |
| --- | --- | --- | --- |
| U1 PF-FE-001 | `frontend/test/lint/noDirectTransport.rule.test.ts` | `npm --prefix frontend run test -- test/lint/noDirectTransport.rule.test.ts -t TC-PFL-026`（assertion mismatchでprocess exit 1） | 同じcommand（expected diagnostic検出でprocess exit 0） |
| U1 PF-FE-002 | `frontend/test/lint/moduleMatrix.config.test.ts` | `npm --prefix frontend run test -- test/lint/moduleMatrix.config.test.ts -t TC-PFL-038` | 同じcommand |
| U1 PF-SUPPRESS-001 | `frontend/test/lint/suppressionPolicy.test.ts` | `npm --prefix frontend run test -- test/lint/suppressionPolicy.test.ts -t TC-PFL-052` | 同じcommand |
| A black-box GREEN | `frontend/test/lint/frontendLint.cli.test.ts` | — | `npm --prefix frontend run test -- test/lint/frontendLint.cli.test.ts -t TC-PFL-013`（TC-PFL-013はGREEN限定、process exit 0） |
| A black-box RED | `frontend/test/lint/frontendLint.cli.test.ts` | `npm --prefix frontend run test -- test/lint/frontendLint.cli.test.ts -t TC-PFL-070`（expected signature mismatchでtest process exit 1） | 同じcommand（実装後exact signature一致でprocess exit 0） |
| B PF-GATE/TEST | `scripts/project-lint.tests.ps1` | `pwsh -NoProfile -File scripts/project-lint.tests.ps1 -Phase Red -Case TC-PFL-001` | `pwsh -NoProfile -File scripts/project-lint.tests.ps1 -Phase Green -Case TC-PFL-001` |
| C aggregate | `scripts/check.contract.tests.ps1` | `pwsh -NoProfile -File scripts/check.contract.tests.ps1 -Phase Red -Case TC-PFL-020` | `pwsh -NoProfile -File scripts/check.contract.tests.ps1 -Phase Green -Case TC-PFL-020` |
| D PF-OBS-001 | `backend/src/test/java/com/example/dailyreport/observability/EndpointMetadataRegistryContractTest.java` | `backend\mvnw.cmd -B -Dtest=EndpointMetadataRegistryContractTest test`（RED JUnit failure） | 同じcommand（GREEN 0 failures） |

実装後のRT欄は、計画上のRED/GREEN placeholderではなく実test名、実行結果、終了コード、stdout/stderr、artifactへ更新する。TC-PFL-106〜109およびTC-PFL-110〜121/130〜131はレビュー追加回帰subcaseとして実装・実行するが、canonical TC-PFL-001〜105の件数には加えない。

### 10.1 実装後実測（2026-09-12）

- `pwsh -NoProfile -File scripts/check.ps1 -Mode Full`: frontend lint/typecheck、190 frontend tests、build、backend Spotless/Checkstyle/SpotBugs/PMD、全contract、project-lint、endpoint contract、connectionsを含めて全成功。
- FrontendCoverage: 190/190 tests、Statements 96.08%、Branches 92.38%、Functions 97.77%、Lines 95.94%。Chromium E2Eは21/21 PASS。
- B: `scripts/project-lint.tests.ps1`の48 casesをText/Json各1回、計96/96 PASS。C non-content contractはTC-PFL-020/021/022/023/024/025/074/075/076/077/083/084/092がPASS（TC-PFL-074の歴史baseline判定はHOLD）。TC-PFL-106〜109はP1レビュー追加subcaseでcanonical TC-PFL-001〜105とは別集計。
- D focused interceptor/registryは24/24、D本体は18/18 PASS。既存回帰10 scriptsもPASS。
- Oracle-dependent BackendCoverage/Oracle/E2EOracleは、固定SQL cleanupが設定済みDBを書き換えるため対象DBの明示承認なしでは未実行。以前のfull backend testはOracle認証`ORA-01017`で93 errorsだった。専用test DB・runner・接続identity・cleanup承認が揃ったmain pushまたは手動実行で再確認する。
- TC-PFL-074は固定HEADの5 blob照合、`evidenceStatus=notCaptured`、`decision=hold`、理由・再確認条件を確認済み。これは歴史baseline固有のHOLDであり、TC-PFL-085のsourceArtifact pinとは混同しない。Stage 1直後・Stage 2前の公開A/D不変artifactがないため、post-fix TC-PFL-078〜082とは分離して保留する。
- TC-PFL-085は実装後レビュー、正本ケース、統合品質記録、作業記録、指摘一覧を対象に、schema v2の19 source artifactsと105明示coverageを検証する。各行の実在locator・symbol/case・public runner-case整合、commit/SHA256、status/exitCode、public command、stdout/stderr hashを突合し、104 PASS＋TC-PFL-074限定HOLDを許可する。現行pinは `scripts/fixtures/project-lint/TC-PFL-085-post-review-gate/post-review.json::executionEvidence.sha256` から解決し、具体hashを本文へ複製しない。架空path/symbol、case不一致、旧schema、default/all-HOLD、未許可HOLD、coverage欠落/重複、reason/recheck欠落、PASS非0exitのnegativeを拒否し、自己申告の`postReviewStatus=complete`だけでは合格にしない。一般手順として文書更新後はsource pinを再固定し、最終状態へ同期する。

### 10.2 最終レビュー追加実測（2026-09-12）

| 対象 | 結果 | 追加確認 |
| --- | --- | --- |
| Frontend focused | 39 tests PASS | suppressionのAST comment token、module完全edge、qualified/global transport・aliasのTC-PFL-110〜119。 |
| Frontend全体 | 24 files、lint/typecheck/build 200/200 PASS | custom ruleとbase規約を同時に確認。 |
| C gate | TC-PFL-085/120/121 root PASS（canonical pin再固定済み） | schema v2のpath/symbol/case/public command/exit/result/stdout-stderr/source hash/artifact pin整合、pin正本 `scripts/fixtures/project-lint/TC-PFL-085-post-review-gate/post-review.json::executionEvidence.sha256`、Stage marker chain、Impact expected completeness。文書更新後にpinを再固定する運用を標準とする。 |
| Backend / observability | backend contract20/20、observability32/quality PASS | TC-PFL-130/131のlive metadata lifecycle fail-closed。 |
| 範囲 | canonical TC-PFL-001〜105を維持 | TC-PFL-110〜121/130〜131はreview regression subcase。 |

FIND-LUNA-P0-001、FIND-LUNA-P1-001、FIND-LUNA-P1-003、FIND-LUNA-P1-004〜007、FIND-PFL-P1R-010〜013は修正済み・標準化候補として記録する。P1R-005の旧schema v1/5 artifacts/default PASS、P1R-006のpath-only locatorは、TC-PFL-085 schema v2の双方向整合とsymbol/selector実在検証へ統合した。P1-007ではsourceArtifact pinをcanonical locatorへ一元化し、docsへ具体hashを複製しない。文書更新後にpinを再固定して最終状態へ同期する一般手順も標準化した。P1R-013の非リテラルdynamic importと再代入aliasは静的判定対象外であり、flow解析を導入する機能変更時に再確認する。既知HOLDはTC-PFL-074、Oracle系、P1R-009である。

## 11. Phase 2 backlog

| ID | 対象 | 保留理由 | 再開条件 |
| --- | --- | --- | --- |
| TRACE | AC→TC→RT→実test→command→artifactの完全追跡 | 実装前は実artifactなし | 全行のresultと証跡を固定する。 |
| MASTER/seed | master data、seed、cleanup | Phase 1の静的契約外 | 固定ID、seed、cleanup、Oracle runnerを別ACで承認する。 |
| ARCH | module/adapter責務と依存グラフ | Phase 1のmatrixを越える | ADRと独立architecture reviewを承認する。 |
| DATE | date、timezone、line ending境界 | Phase 1のpath/CRLF以外は未確定 | 入力境界と再現環境を固定する。 |
| INPUT | malformed catalog/path/format全分類 | Phase 1はschema/rootの最小契約 | 入力分類とdiagnostic schemaを拡張する。 |
| DDL | Oracle DDL、制約、test schema | Linterの責務外 | Oracle品質ゲートを別計画で承認する。 |
| SQL bind | bind、parameter、query logging | static validatorはSQL意味論を扱わない | bind・ログ非開示・Oracleケースを別ACで承認する。 |

## 12. レビュー計画・Do開始条件

| 優先度 | 観点 | 入力資料・節 | 担当 / 出力 | 状態 |
| --- | --- | --- | --- | --- |
| P0 | 設計・受入条件照合 | `標準化/実装前チェック表.md`、本計画§3 through §7 | 独立設計担当 / 実装前レビュー | 実装後再照合済み。P0指摘は修正・証跡化済み |
| P0 | テスト不足・構成 | `標準化/テストケースレビュー観点.md`基本観点・責務分割、`標準化/テスト方針.md`配置節、本正本 | 独立テスト担当 / 正本・レビュー | 190 frontend、B 96/96、D 24/24+18/18。追加subcaseを分離記録 |
| P0 | 期待結果 | `AI専門レビュー用プロンプト定義.md`「06」、本正本のexact expected | 独立期待結果担当 / 正本 | 一原因・exact expectedを確認。TC-PFL-074は保留 |
| P0 | トレーサビリティ・統合 | 同「08」、統合品質記録様式、本正本 | 統合担当 / 統合品質記録 | TC/RT 001〜105、FIND/証跡を更新。TC-PFL-085 schema v2 root PASS（19 source artifacts、105 locator/symbol coverage、hash/exit整合）。pinはcanonical locatorのみ参照し、文書更新後に再固定する。 |
| P1 | 静的解析・CI | `テスト・静的解析チェック表.md`、`品質ゲート運用.md` | 独立CI担当 / 品質記録 | Full、C non-content contract、Quick/PrePush契約を確認済み |
| P1 | 配置・共通化 | `ディレクトリ構成ルール.md`、`共通部品化判断基準.md` | 独立配置担当 / 正本§7 | 現行は機能分割せず、index/registry責務集中を次回再評価候補として保留 |
| P1 | security・observability | `セキュリティ規約.md`ログ/機密情報、実装前チェック表ログ設計 | 独立security担当 / ADR・正本 | catalog untrusted値非漏えい、D live mapping、Oracle未実行条件を確認 |

Stage 0の設計・ケース固定は履歴上完了し、Stage 1〜4の実装・契約実行も完了した。最終gateは、成功したFull/C/E2Eと、TC-PFL-074、Oracle系の保留を分離して判定する。TC-PFL-085は証跡整合を含めroot PASSとし、sourceArtifact pinは `scripts/fixtures/project-lint/TC-PFL-085-post-review-gate/post-review.json::executionEvidence.sha256` を単一正本として再固定済みである。今後も文書更新後はpinを再固定して最終状態へ同期する。保留は理由と再確認条件が揃うまで成功扱いにしない。

## 13. 関連資料と公式一次資料

- [ESLint Custom Rules](https://eslint.org/docs/latest/extend/custom-rules)
- [ESLint RuleTester / Node API](https://eslint.org/docs/latest/integrate/nodejs-api#ruletester)
- [ESLint Node.js API](https://eslint.org/docs/latest/integrate/nodejs-api)
- [ESLint Formatters](https://eslint.org/docs/latest/use/formatters/)
- [ESLint Configuration Files](https://eslint.org/docs/latest/use/configure/configuration-files)
- [ESLint Disabling Rules](https://eslint.org/docs/latest/use/configure/rules#disabling-rules)
- [Spring Mapping Requests](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-controller/ann-requestmapping.html)
- [Spring Handler Mappings](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-servlet/handlermapping.html)
- [PowerShell about_Scripts](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scripts)
- [PowerShell Resolve-Path](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/resolve-path)

関連資料: `AGENTS.md`、`.agents/skills/projectfoundation-preflight-ja/SKILL.md`、`カスタムLinter_テストケース.md`、`カスタムLinter_実装前レビュー.md`、`カスタムLinter_統合品質記録.md`、`カスタムLinter_作業記録.md`、`ADR-PFL-001`。
