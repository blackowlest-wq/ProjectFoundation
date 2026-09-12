# カスタムLinter 実装前レビュー

## 1. 判定と境界

| 項目 | 記録 |
| --- | --- |
| レビュー日 | 2026-09-02 |
| 判断日 | 2026-09-01 |
| 対象 | カスタムLinter実装計画、正本テストケース、統合品質記録、ADR-PFL-001、Phase 1の6 policy、U1/A/B/D/C、scope matrix |
| 開発モード | 品質重視モード（利用者承認済み） |
| レビューモデル | gpt-5.6-luna / max |
| 判定 | **Stage 0設計レビュー完了（履歴）／実装後の利用可能gate確認済み** |
| 実装状態 | 本番コード、validator、fixture、test、workflow、C接続を実装済み。実測結果と保留項目は§7へ更新 |
| 判定理由 | 実装前の独立レビューでP0/P1を解消した後、U1/A/B/D/Cの契約、Full、FrontendCoverage、Chromium E2E、focused Dを実行した。TC-PFL-085は実在locator・symbol/case・public runner整合、commit/SHA256、exitCodeを検証してroot PASSとし、現行pinは `scripts/fixtures/project-lint/TC-PFL-085-post-review-gate/post-review.json::executionEvidence.sha256` を正本として本文はlocatorだけを参照する。文書更新後のpin再固定も完了し、TC-PFL-074の歴史artifactとOracle系だけを保留として成功したgateと分離する |
| Git承認 | 固定HEAD `905a9676a7d48a86bf9aab6fb34dcbf08c65f402`。2026-09-02の利用者「続けてください」はcurrent `main`（ahead 5、docs dirty）でDoを継続し、fetch、branch、reset、stash、commit、pushを行わない承認。後でbranchを作る場合だけAGENTS.mdのmain clean/fetch/0 0前提を再確認する。 |

品質重視モードのHard Gateにより、Stage 0（contracts/cases/trace固定、独立レビューP0/P1、利用者承認、Git固定点記録）は実装前履歴として完了している。実装後はStage 1〜4と利用可能な最終gateを実行し、未取得artifactや環境依存の確認は保留として記録する。

## 2. 参照契約

| 優先度 / 観点 | 参照資料・節 | 独立担当 / 出力 | 状態 |
| --- | --- | --- | --- |
| P0 設計・受入条件照合 | `docs/AI活用開発研究/構想メモ/標準化/実装前チェック表.md`の実装前確認・アウトプット、実装計画§3 through §7、ADR決定 | 設計担当 / 本記録と実装計画 | 実装後再照合済み。P0指摘は修正済み |
| P0 テスト不足 | `docs/AI活用開発研究/構想メモ/標準化/テストケースレビュー観点.md`基本観点・期待結果、`テスト方針.md`、正本§2 through §4 | テスト担当 / 正本 | B 96/96、Frontend 190 tests、Chromium 21/21。追加subcaseを分離 |
| P0 テスト構成・責務分割 | `テストケースレビュー観点.md`「テスト構成・責務分割観点」、`テスト方針.md`「テスト配置とユースケース分割」、`ディレクトリ構成ルール.md`、正本§5 | 配置担当 / 正本 | B placement contractとFullを確認。責務集中は標準化候補/HOLD |
| P0 期待結果 | `AI専門レビュー用プロンプト定義.md`「06 期待結果レビュー」、正本のexact expected | 期待結果担当 / 正本 | 一原因・exact expected・RED実敗北を確認。TC-PFL-074は保留 |
| P0 トレーサビリティ・統合 | 同「08」、`統合品質記録様式.md`、正本§3・§6・§7 | 統合担当 / 統合品質記録 | TC/RT 001〜105、P1R-001〜013、LUNA追加指摘を追跡。TC-PFL-085 schema v2 root PASS（19 source artifacts、105 locator/symbol coverage、hash/exit整合）。pin正本は `scripts/fixtures/project-lint/TC-PFL-085-post-review-gate/post-review.json::executionEvidence.sha256` とし、本文へ具体hashを複製しない |
| P1 静的解析・CI | `テスト・静的解析チェック表.md`、`品質ゲート運用.md` Local/CI/Quick/PrePush | CI担当 / 品質記録 | FullとC non-content contract成功。Quick/PrePushはbase-onlyで維持 |
| P1 配置・共通化 | `ディレクトリ構成ルール.md`、`共通部品化判断基準.md`、正本§5 | 配置担当 / 正本 | 現行構造は維持。index/registry責務分割を次回機能追加時に再評価 |
| P1 security・observability | `セキュリティ規約.md`ログ/機密情報、実装前チェック表ログ設計、ADR PF-OBS-001 | Security/Observability担当 / ADR・正本 | untrusted diagnostic非漏えい、D live mappingを確認。Oracle系は環境保留 |

担当には結論を渡さず、上表の資料・節・対象範囲・出力先だけを配布する。最後に統合担当が重複、矛盾、保留を整理する。

## 3. 正本設計の照合結果

| 照合項目 | 判定 | 根拠 | 再確認 |
| --- | --- | --- | --- |
| catalog | 文書固定済み | production catalog固定path `config/project-lint-policies.json`、top-level `schemaVersion`、可変`policies[]`、policy必須7 field、`targets.seams/scopes/include/diagnosticTarget`、exception entry必須key、PF-GATE-001 owner=B | TC-PFL-086〜091とTC-PFL-093〜100で各欠落を一原因ずつ、TC-PFL-101で非空exception entry正常系をBで実行 |
| PF-FE-001 | 文書固定済み | production `frontend/src`のfetch、document.cookie read/write、ad-hoc CSRFをapiClient以外で禁止。shadowed fetchを許可 | U1とA CLIを別々に実行 |
| PF-FE-002 | 文書固定済み | sharedは`shared/types`のみ、featureは`auth/types`と`shared/types`をtype-only許可。shared/feature/app matrix、Node API target coverage、実`lcov-to-html.mjs` | RuleTesterと`isPathIgnored`/`calculateConfigForFile`/`lintFiles`を実行 |
| PF-TEST-001 | 文書固定済み | Unit/E2E/Oracle/backend Test/IT、cross-runner、support test禁止、trace ID除外。manifest/runner attributeなし | isolated repository B contractを実行 |
| PF-SUPPRESS-001 | 文書固定済み | raw directive analyzer、explicit rule ID、直前物理行の非空Why not、A owner | U1 raw analyzerとA black-boxを実行 |
| PF-OBS-001 | 文書固定済み | Dの対象はbean型packageが`com.example.dailyreport`で始まり、normalized routeが`/api/`で始まるapplication-owned `HandlerMethod`のみ。framework/error/actuator/staticを除外し、明示HTTP methodなしのapplication `/api/**` mappingを違反、明示各methodを別keyへ展開してcentral registryと比較。 | TC-PFL-102〜105でframework mapping/non-API application handler除外、methodless違反、multi-method別keyを各一原因でD live-context contract実行 |
| U1/A/B/D/C | 文書固定済み | 各入口、exit、Text/Json、diagnostic schema（policyId、engineRuleId、severity、path、nullable line/column/rule/code、message）、C childExit=2を分離。A REDはTC-PFL-070のexpected signature mismatchでtest process exit 1、TC-PFL-013はGREEN限定。production catalog固定pathは`config/project-lint-policies.json`。CはTC-PFL-025のcatalog selector fallback（`SchemaVersion=1`、`ExecutionScope=Full`、`ChangedFiles` count=1/value=`config/project-lint-policies.json`、`SelectedLayers=9`、`ExcludedLayers=0`、`FallbackUsed=true`、`FallbackReason` exact=`IMPACT_SELECTOR_OR_GATE_CHANGED: config/project-lint-policies.json`、`FullReason` empty、`LayerReasons=9`）とTC-PFL-092の`Succeeded`/selected row/`State`/件数を固定し、scope unavailableは既存check.ps1回帰へ委譲 | fixed future commandとartifactを記録 |
| TC/RT trace | 文書固定済み | TC-PFL-001〜105 ↔ RT-PFL-001〜105を一対一で固定し、TC-PFL-093〜101はFIND-PFL-REV-002、TC-PFL-102〜105はFIND-PFL-REV-008へ紐付ける | quality recordとの件数・ID・AC一致を再確認 |
| baseline TC-PFL-074 | 文書固定済み | Stage 1後・Stage 2前のcurrent treeで固定HEAD `905a9676a7d48a86bf9aab6fb34dcbf08c65f402`とのblob一致を先に検証し、不一致をTC failureとする。同じcurrent treeへ公開A/Dを実行し、FIND-PFL-BASE-001 groups、FIND-PFL-BASE-002 messages、FIND-PFL-BASE-003 MonthlySummary、FIND-PFL-BASE-004 PendingApproval、FIND-PFL-BASE-005 lcov targetのexact 5 logical occurrences・3 categoriesを記録 | 対象5ファイルは`backend/src/main/java/com/example/dailyreport/observability/RequestContext.java`、`backend/src/main/java/com/example/dailyreport/observability/RequestMetadataInterceptor.java`、`frontend/src/monthlySummary/MonthlySummaryPage.tsx`、`frontend/src/dailyReport/DailyReportPendingApprovalList.tsx`、`frontend/eslint.config.mjs`。blob一致とA/D結果を記録 |
| Scope matrix | 文書固定済み | Docs、Frontend、Backend、Harness/Mixed/Full、Impact fallbackをpolicy別に明記 | scopeごとのmissing policyを一原因TCで実行 |

## 4. 独立レビューFIND

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

上記14件は既知baselineの5 logical occurrencesとは別のレビュー指摘である。レビュー指摘の分類は、個別対応、既存観点で対応、標準化候補、対象外、保留のいずれかで一意に記録する。

## 5. 標準化・保留判定

| 対象 | 判定 | 反映先 | 完了条件 |
| --- | --- | --- | --- |
| 6 policy、catalog、診断schema、seam | 標準化候補 | テスト・静的解析チェック表、品質ゲート運用、review Skill | U1/A/B/D/C実行とP0/P1再レビュー |
| module matrix、test placement、support禁止 | 標準化候補 | テスト方針、ディレクトリ構成ルール、レビュー観点 | 新moduleのisolated fixtureで再発なし |
| FIND-PFL-BASE-001、FIND-PFL-BASE-002、FIND-PFL-BASE-003、FIND-PFL-BASE-004、FIND-PFL-BASE-005 | 個別対応 | plan、quality、work、issues | Stage 3で5件0、ignore storeなし |
| expected結果の一原因契約 | 既存観点で対応 | preflight、期待結果レビュー、正本 | P0期待結果レビューで曖昧語0、各TC exact |
| PMD、ArchUnit、DDL、SQL bind | 対象外/Phase 2 | plan backlog | 別ADRとACを承認 |
| U1/A/B/D/C実行、CI、Oracle、coverage | 保留 | quality、work | 固定commit、runner、artifact取得 |

## 6. Do開始条件と最終gate

Do開始条件であるStage 0（contracts/cases/trace固定、TC/RT 105/105、独立レビューP0/P1、利用者承認、Git固定点記録）は実装前履歴として完了した。Stage 1〜4のRED→GREEN、baseline修正、C/CI接続、実測gateは実施済みで、最終記録では成功結果と保留結果を分離する。

Stage 1のRED→GREEN、Stage 2のbaseline修正、Stage 3のA/B/D 0件、Stage 4のC/CI接続は完了済みである。Stage 5の最終gateは、Full、FrontendCoverage、Chromium E2E、B/D/Cの成功と、TC-PFL-074、Oracle系の保留を別判定として記録する。TC-PFL-085は証跡整合を含めroot PASSとし、現行pin再固定も完了した。一般手順として文書更新後はcanonical pinを再固定し、未実行、artifact不足、childExit=2を成功扱いしない。

## 7. 実装後の再確認結果（2026-09-12）

| 区分 | 実測・判定 | 証跡 / 保留条件 |
| --- | --- | --- |
| Full | 成功 | `scripts/check.ps1 -Mode Full`。Frontend lint/typecheck/unit 190件/build、Backend Spotless/Checkstyle/SpotBugs/PMD、全contract、project-lint、endpoint contract、connectionsを完走。 |
| Frontend coverage | 成功 | 190/190、Statements 96.08%、Branches 92.38%、Functions 97.77%、Lines 95.94%。 |
| Chromium E2E | 成功 | 21/21 PASS。UI visualは挙動変更なしのためN/A。 |
| B validator | 成功 | 48 cases × Text/Json = 96/96 PASS。TC-PFL-106〜109およびTC-PFL-110〜121/130〜131はレビュー追加回帰subcaseでありcanonical TC-PFL-001〜105とは別集計。 |
| C contract | 成功 | TC-PFL-020/021/022/023/024/025/074/075/076/077/083/084/092のcontract実行はPASS（TC-PFL-074の歴史baseline判定はHOLD）。childExit=2の優先、Quick/PrePush base-only、catalog-derived connectionを確認。 |
| D / interceptor | 成功 | focused D+interceptor 24/24、D 18/18 PASS。実Spring `RequestMappingHandlerMapping`とcentral registryを比較し、TC-PFL-102〜105の境界を確認。 |
| 既存回帰 | 成功 | 既存回帰10 scripts PASS。 |
| Historical baseline TC-PFL-074 | **保留** | 固定HEAD `905a9676a7d48a86bf9aab6fb34dcbf08c65f402`の5 blobは照合済みだが、Stage 1直後・Stage 2前の公開A/D実行artifactが未取得（`evidenceStatus=notCaptured`、`decision=hold`）。これは歴史baseline固有のHOLDであり、TC-PFL-085の可変sourceArtifact pinとは別契約である。次回変更でStage 1後かつStage 2前に公開A/Dを実行し、不変artifactを保存してからbaseline修正を行う。post-fix TC-PFL-078〜082は別判定。 |
| BackendCoverage / Oracle / E2EOracle | **保留** | 固定SQL cleanupが設定済みDBを書き換えるため、対象DBの明示承認なしでは未実行。以前のfull backend testはOracle認証`ORA-01017`で93 errors。専用test DB、runner、expected identity、cleanup承認が揃ったmain pushまたは手動実行で再確認する。 |
| TC-PFL-085 | **成功** | schema v2の19 source artifacts、105明示coverage、104 PASS＋TC-PFL-074限定HOLDを検証。各`path::symbol/selector`の実在・case整合、public command/exit/result/stdout-stderr hash、source hash/artifact pin、commit/SHA256を突合する。現行pinは `scripts/fixtures/project-lint/TC-PFL-085-post-review-gate/post-review.json::executionEvidence.sha256` から解決し、具体hashは本文へ複製しない。旧schema/default/all-HOLD/未許可HOLD、coverage欠落/重複、reason/recheck欠落、架空/空symbolのnegativeを拒否する。文書更新後はpin再固定を行い、最終状態を同期する。 |

### 指摘対応と標準化判定

P1R-001〜008およびP1R-010〜013は修正済みで、修正ファイルと確認テストを指摘一覧へ記録した。FIND-LUNA-P0-001、P1-001、P1-003、P1-004〜007も修正済み・標準化候補とした。P1-005は旧schema v1/5 artifacts/default PASSを正本schema v2へ統合し、P1-006は全105行の`path::symbol/selector`実在検証へ統合した。P1-007はsourceArtifact pinをcanonical locatorへ一元化し、文書へ具体hashを複製しない運用へ修正した。文書更新後はpinを再固定して最終状態を同期する。P1R-009（index.mjs/registryの責務集中）はregex代替を削除済みだが、現行の責務境界を直ちに分割せず、次回のpolicy追加・owner追加時に分割要否を再評価する標準化候補/HOLDとした。P1R-013の非リテラルdynamic importと再代入aliasは静的判定対象外として理由・再確認条件を付した。P0重複（public A bypass、CLI internal seam、意図的RED、TC-PFL-080/081欠落、TC-PFL-074 false historical evidence、TC-PFL-085 self-declared/stale、future seventh policy、D manual list/TC-PFL-104/105 mismatch）は対応または保留条件を指摘一覧の専用行へ同期する。

### 7.1 最終レビュー追加結果（2026-09-12）

| 指摘ID | 問題 | 対応・証跡 | 標準化判定 | 影響範囲 | 再確認条件 |
| --- | --- | --- | --- | --- | --- |
| FIND-LUNA-P0-001 | TC-PFL-085が架空locatorや未実行PASSを通せた。 | `scripts/check.contract.tests.ps1`とfixtureで実在path、symbol/case、public runner、commit/SHA256、exitCodeを検証。negativeを含めroot PASS。 | 標準化候補 | content gate | evidence schemaまたはrunner形式変更時に正負の整合を再実行する。 |
| FIND-LUNA-P1-001 | Impact selected layer欠落を見逃した。 | `scripts/check.ps1` expected集合、Quality/Oracle許可除外、TC-PFL-121でmissing layerを拒否。root PASS。 | 標準化候補 | C Impact | 層・除外変更時に集合完全性を再確認する。 |
| FIND-LUNA-P1-003 | Stage 1〜5をStage 0だけで飛ばせた。 | 前段marker連鎖とTC-PFL-120で欠落をexit 1拒否。root PASS。 | 標準化候補 | Stage／CI | Stage追加・marker変更時に全順序を再確認する。 |
| FIND-LUNA-P1-004 | live metadata mismatchをbackend起動時に強制していなかった。 | `EndpointMetadataRegistry` lifecycle fail-closed、固定非開示例外、TC-PFL-130/131。backend20/20、observability32/quality PASS。 | 標準化候補 | Backend D／runtime | controller・mapping・lifecycle変更時に不一致/整合の両方を再実行する。 |
| FIND-LUNA-P1-005 | content gateの実装後レビューが旧schema v1、5 artifacts、default PASSを主張し、実fixture v2と矛盾した。 | `scripts/check.contract.tests.ps1`とv2 fixtureで19 source artifacts、105明示coverage、104 PASS＋TC-PFL-074限定HOLD、public command/exit/result/stdout-stderr hash、source hash/artifact pinを双方向検証。旧schema/default/all-HOLD/未許可HOLD、coverage欠落/重複、reason/recheck欠落をreject。 | 標準化候補 | content gate／トレーサビリティ | schema、required artifacts、coverage/status判定変更時に文書とmachine-readable fixtureの双方向整合、旧schema marker negativeを再実行する。 |
| FIND-LUNA-P1-006 | locator pathだけでsymbol検証をskipでき、架空または空symbolのTCが成立し得た。 | 全105ケースを`path::symbol/selector`必須化し、PowerShell関数、Java method、TS/JS selectorの実在・case整合を検証。path-only、空、架空symbolをTC-PFL-085 negativeでreject。 | 標準化候補 | content gate／ケース実在性 | locator構文・言語・selector・case範囲変更時に全105行の実在/一致とpath-only/空/架空symbol negativeを再実行する。 |
| FIND-LUNA-P1-007 | sourceArtifact対象docsへ具体的pin値を複製すると、文書更新のたびに旧pinや一時HOLDが残る循環が生じる。 | 修正済み。現行pinは `scripts/fixtures/project-lint/TC-PFL-085-post-review-gate/post-review.json::executionEvidence.sha256` を単一正本とし、docsはlocatorだけを参照して具体hashを複製しない。文書更新後はpinを再固定し、最終状態へ同期する。 | 標準化候補 | content gate／証跡pin運用 | 指定資料、canonical locator、TC-PFL-084/085/121 root PASS、最終Full PASSを確認済み。sourceArtifact追加・文書更新後は一般手順としてpinを再固定する。 |
| FIND-PFL-P1R-010 | block suppression見逃しと文字列誤検出。 | `SourceCode.getAllComments()`、TC-PFL-110/111/112、focused39・全24 files 200/200。 | 標準化候補 | Frontend A | parser/ESLint更新時にcomment tokenとstring/template境界を再確認する。 |
| FIND-PFL-P1R-011 | shared→auth、auth→app edge欠落。 | 完全edge matrix、TC-PFL-113/114。 | 標準化候補 | Frontend A | module/type-only許可変更時に全edgeを再確認する。 |
| FIND-PFL-P1R-012 | re-export/static dynamic import欠落。 | AST visitors、TC-PFL-115/116/117。 | 標準化候補 | Frontend A | parser/visitor変更時に各import/export形を再確認する。 |
| FIND-PFL-P1R-013 | qualified/global transportとconst alias迂回。 | global/member・単純const aliasを検出しshadowing/apiClient例外を維持。TC-PFL-118/119。非リテラルdynamic import・再代入aliasは静的対象外。 | 標準化候補 | Frontend A／transport・CSRF | flow解析追加時に専用caseと責務境界を再評価する。 |

実測はFrontend focused39、全24 files 200/200、TC-PFL-085/120/121 root PASS、backend contract20/20、observability32/quality PASS。TC-PFL-085はschema v2、19 source artifacts、105明示coverage、104 PASS＋TC-PFL-074限定HOLDを根拠とする。canonicalは105のまま、新規110〜121/130〜131はreview regression subcaseである。既知HOLDはTC-PFL-074、Oracle系、P1R-009のみである。

## 8. 関連資料

- [カスタムLinter 実装計画](カスタムLinter_実装計画.md)
- [カスタムLinter 正本テストケース](カスタムLinter_テストケース.md)
- [カスタムLinter 統合品質記録](カスタムLinter_統合品質記録.md)
- [カスタムLinter 作業記録](カスタムLinter_作業記録.md)
- [ADR-PFL-001](../設計判断記録/ADR-PFL-001-静的解析の統一入口と責務分担.md)
