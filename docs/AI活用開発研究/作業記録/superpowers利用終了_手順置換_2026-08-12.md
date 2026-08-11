# superpowers利用終了・Codex標準手順への置換

## 変更概要

- 日付: 2026-08-12
- 開発モード: 簡易修正モード
- 対象: ProjectFoundationの開発フロー、実装前・実装後Skill、既存実装計画の実行案内、現在利用可能なSkillとの役割分担
- 目的: 現行手順からsuperpowersの実行依存を除き、Codex標準機能、適用条件に合う既存Skill、ProjectFoundation既存方針へ置き換える

## 対象範囲

- 現行の正本手順とCodex自動検出Skillにあるsuperpowersの必須・推奨呼び出し
- 既存実装計画の先頭にあるsuperpowers実行指示
- Codex標準機能と現在利用可能なSkillの用途、開始主体、品質ゲートとの境界
- 正本Skillと`.agents/skills`配布コピーの同期

## 対象外

- 過去の作業記録に残るsuperpowers利用実績、旧成果物パス、当時のレビュー証跡
- `.superpowers/`と`docs/superpowers/`の既存ファイル削除・移動
- `.gitignore`の旧成果物除外と`scripts/check.ps1`の文書判定互換の動作変更
- 品質ゲート、hook、workflow、テスト、アプリケーションコードの変更

対象外の旧パスと互換設定はsuperpowersの実行を要求せず、既存証跡の保持または誤追跡防止にだけ使われているため維持する。今後の新規計画・レビューでは正本の標準化資料とCodex標準機能を使う。

## 受入条件

1. 現行のpreflight/review Skillとその配布コピーが、superpowersのSkill呼び出しを要求しない。
2. 仕様整理・タスク分解はPlan mode、長時間作業は必要時のGoal mode、独立レビューはCodexサブエージェント、コードレビューは`/review`、TDDは`$tdd`、難しい不具合調査は`$diagnosing-bugs`へ対応付く。各SkillはProjectFoundationの正本手順を置き換えず、利用できない場合も品質ゲートを継続できる。
3. 既存実装計画の実行案内がsuperpowers必須ではなく、`/plan`と必要時の`/goal`から開始する案内になる。
4. 過去の利用実績と旧成果物は履歴として保持し、品質ゲートコードとCI契約に動作差分を生じさせず、変更MarkdownのlintとSkill同期確認が成功する。

## 簡易修正モードの確認計画

- Focused Unit: N/A。MarkdownとSkill手順だけの変更で、実行可能な業務ロジックを変更しないため。
- 表示要件: なし。画面、CSS、ブラウザ表示を変更しないため。
- 変更対象層の確認: 変更Markdownに対するMarkdown lint、Skill frontmatter検証、正本と配布コピーの一致確認を行う。
- typecheck / build: N/A。TypeScript、Java、build設定を変更しないため。
- 独立レビュー: コード差分レビューを1回実施し、置換漏れ、履歴改変、Codex機能の誤用、正本・配布コピー不一致を確認する。
- CI委譲: 全テスト、全coverage、全E2E、Oracle、追加secret scanは既存の`main` push後CIへ委譲する。既存pre-commit / pre-push hookと6品質jobは変更しない。

## 調査結果

| 分類 | 検出内容 | 判定 |
| --- | --- | --- |
| 現行Skill | preflightにbrainstorming、writing-plans、test-driven-development、dispatching-parallel-agentsの呼び出しが4か所ある | 置換対象 |
| 現行Skill | reviewにdispatching/receiving/requesting/systematic-debuggingの呼び出しが5か所ある | 置換対象 |
| 既存実装計画 | `docs/superpowers/plans`の6計画とコード品質確認画面の1計画に実行用superpowersヘッダーがある | 実行案内だけ置換対象 |
| 品質ゲート正本 | `品質ゲート運用.md`、`テスト方針.md`、`テスト・静的解析チェック表.md`にsuperpowers呼び出しはない | 変更不要 |
| 品質ゲート実装 | `scripts/check.ps1`は`.superpowers/`を文書変更として分類するが、superpowersを実行しない | 旧証跡互換として維持 |
| 旧成果物・記録 | 過去の作業記録、`.superpowers/sdd`、`docs/superpowers/specs`に利用実績と旧パスがある | 履歴として維持 |
| ignore | `.gitignore`が旧ローカル状態と中間計画を除外する | 既存未追跡物の誤追跡防止として維持 |

## 現在のSkill構成と採用判断

Skill一覧そのものは環境の`/skills`を正とし、永続する開発フローへ全件を転記しない。2026-08-12時点のローカル配置を、今回の置換判断に必要な範囲で次のように整理した。

| 区分 | 配置・例 | 今回の扱い |
| --- | --- | --- |
| Codex組み込みSkill | `C:/Users/user/.codex/skills/.system/`の`openai-docs`、`skill-creator`など | 対象作業の起動条件に合う場合だけ使う |
| ユーザー共通・自動起動可能 | `C:/Users/user/.agents/skills/`の`tdd`、`diagnosing-bugs`、`codebase-design`、`code-review`など | ProjectFoundation固有手順を補助する。`$skill-name`形式で明示できる |
| ユーザー共通・明示起動専用 | 同配置の`implement`など、`disable-model-invocation: true`のSkill | 利用者が明示した場合だけ使う。リポジトリの必須入口にしない |
| ProjectFoundation固有 | 編集元`docs/AI活用開発研究/構想メモ/標準化/skills/`、配布先`.agents/skills/` | 品質ゲート、記録、レビュー契約の正本とする |
| Plugin Skill | セッションに表示される文書、セキュリティ、ブラウザ等のSkill | 必要な作業でだけ使い、Plugin未導入環境でも現行手順を完了できるようにする |

| 候補Skill | 採用判断 | 理由 |
| --- | --- | --- |
| `$tdd` | 採用 | test-first、red-green、合意済みテスト境界の手順が今回のTDD用途に一致する。承認済みケースと`テスト方針.md`をProjectFoundation側の入力とする |
| `$diagnosing-bugs` | 条件付き採用 | 再現が難しい不具合・性能劣化で、再現可能なフィードバックループを先に作る用途に一致する。単純で再現済みの失敗には過剰なため最小手順を維持する |
| `$codebase-design` | 条件付き採用 | モジュールのインターフェースやテスト境界の配置自体が設計課題の場合に使う。通常の仕様整理や受入条件確定の代替にはしない |
| `$code-review` | 標準入口には不採用 | 固定点に対する規約・仕様の二軸レビューには有効だが、現状存在しない`docs/agents/issue-tracker.md`と並列サブエージェントを前提とする。通常は`/review`またはProjectFoundationレビューを使う |
| `$implement` | 不採用 | 明示起動専用で、本文に現行と異なる`/tdd`・`/code-review`表記と自動コミットが含まれる。現在のProjectFoundation実行入口として固定しない |
| `$writing-for-agents` / `$skill-creator` | Skill文書変更時に採用 | Skillと`AGENTS.md`の起動条件、責務境界、簡潔さ、検証を確認する用途に一致する |

同名の`projectfoundation-preflight-ja`と`projectfoundation-review-ja`がユーザー共通の`C:/Users/user/.codex/skills/`にも存在し、リポジトリ正本とはSHA-256が一致しなかった。ProjectFoundation内ではリポジトリの`.agents/skills/`を使用対象とし、ユーザー領域の自動同期・削除は他プロジェクトへ影響し得るため行わない。

## 置換方針

| 旧superpowers用途 | 現行手順 |
| --- | --- |
| brainstorming / writing-plans | 利用者が`/plan`でPlan modeを開始し、対象・制約・完了条件・保留・実装順を確定する |
| executing-plans / subagent-driven-development | 合意した計画を通常のCodexタスクで実行する。長時間・多段階作業だけ、利用者が結果・制約・検証を含む`/goal`を開始する |
| dispatching-parallel-agents | Skillまたは利用者の明示指示により、Codexサブエージェントへ独立した読み取り・レビュー観点を委譲し、主担当が統合する |
| test-driven-development | 利用可能な`$tdd`を使い、`テスト方針.md`と承認済みケースで合意したテスト境界を入力として、失敗するFocused Unit、最小実装、成功確認、リファクタ、回帰確認の順で進める |
| requesting-code-review | `/review`またはProjectFoundationの観点別独立レビューを使う |
| receiving-code-review | 指摘ごとに仕様根拠、コード、再現テストを検証して採否・保留を決める |
| systematic-debugging | 再現が難しい不具合・性能劣化は利用可能な`$diagnosing-bugs`を使う。単純で再現済みの失敗は再現条件固定、証拠収集、最小検証、原因修正、回帰テストの最小手順で進める |

Plan modeとGoal modeは品質ゲートそのものではない。Goal modeを開始しても権限・sandbox・承認範囲は広がらず、テスト、レビュー、CI、Oracleの完了条件を代替しない。

## 外部ドキュメント確認

- [OpenAI Codex Best practices](https://learn.chatgpt.com/guides/best-practices): 複雑・曖昧な作業は`/plan`でPlan modeを使い、実装前に文脈収集と計画を行う。
- [OpenAI Codex Long-running work](https://learn.chatgpt.com/docs/long-running-work): `/goal`には結果、制約、検証可能な完了条件を含め、同じタスクで進捗を追跡する。
- [OpenAI Codex Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents): 独立作業をサブエージェントへ委譲し、主タスクで結果を統合する。並列の書き込み競合には注意する。
- [OpenAI Skills & Plugins](https://learn.chatgpt.com/docs/skills-and-plugins): Skillは繰り返し利用するワークフローを保持し、利用可能なSkillから作業に合うものを選ぶ。
- [OpenAI Codex Slash commands](https://learn.chatgpt.com/docs/codex/cli/slash-commands): `/skills`、`/plan`、`/goal`、`/review`などのスラッシュコマンドとSkill名の役割を区別する。

## 実施結果

### 変更内容

- `開発フロー.md`へ「Codex標準機能とSkillの利用」を追加し、Plan mode、Goal mode、サブエージェント、`/review`、`$tdd`、`$diagnosing-bugs`の役割と品質ゲートとの境界を正本化した。
- preflight/reviewの編集元Skillからsuperpowersの呼び出しを除き、Codex標準機能、適用条件に合う既存Skill、ProjectFoundation既存手順へ置換した。
- 編集元Skillと`.agents/skills`の配布コピーを同じ内容へ更新した。
- `AGENTS.md`へ、ProjectFoundation内の同名Skillの正本と、Skill文書変更時の`$writing-for-agents`・`$skill-creator`利用を追加した。
- Git管理中の`docs/superpowers/plans` 6件と`コード品質確認画面_実装計画.md`の実行案内を、`/plan`と必要時の`/goal`へ置換した。
- 過去の作業記録、旧成果物パス、`.gitignore`、`scripts/check.ps1`は履歴・互換目的のため変更しなかった。

### 検証結果

| 確認 | 結果 |
| --- | --- |
| 現行実行名検索 | `.agents`、標準化資料、Git管理中の旧計画、コード品質確認画面計画を対象に、`superpowers:`、`REQUIRED SUB-SKILL`、旧Skill名を検索し0件 |
| Skill同期 | preflight/reviewとも編集元と`.agents/skills`配布コピーのSHA-256が一致 |
| Skill validator | `quick_validate.py`を4Skillへ実行し全件成功。初回はWindows既定CP932でUTF-8日本語を読めず失敗したため、`python -X utf8`で再実行した |
| Markdown lint | 現行標準資料、Skill、作業記録は既存設定で0 errors。既存設定が除外する旧計画6件は変更した先頭案内だけを同じルールで個別確認し、各0 errors |
| 差分空白 | `git diff --check`成功。対象外の既存変更`機能一覧・受入条件.md`に改行コード変換警告はあるが、空白エラーはない |
| 独立レビュー | 初回レビューで`コード品質確認画面_実装計画.md`末尾の`executing-plans`残存を1件検出し、「合意済みPlanに従って」へ修正。再レビューCLEAN |
| Skill構成反映後の差分レビュー | `開発フロー.md`の節名変更後、preflight/review正本・配布コピーの参照名4か所が旧名称のまま残った問題を検出し、新名称「Codex標準機能とSkillの利用」へ修正 |

旧計画6件をignore設定から外して全文lintした場合、今回の変更行とは無関係な既存のMD032違反58件を検出した。既存設定では対象外であり、旧成果物の全体整形は履歴差分を増やすため今回の対象外とする。これらを現行の保守対象へ戻す場合は、現在の保存先へ移行するか、全文lintを行う条件で再確認する。

### 簡易修正モードの最終判定

- 受入条件1～4: 対応済み。
- Focused Unit: N/A。実行可能な業務ロジック変更なし。
- 表示確認: N/A。画面・CSS変更なし。
- typecheck / build: N/A。TypeScript、Java、build設定変更なし。
- 全テスト、全coverage、全E2E、Oracle、追加secret scan: ローカル未実行。既存の`main` push後CIへ委譲する。
- 既存hook / 6品質job: ファイル変更なし。従来の判定を維持する。
- 残るリスク: ignore済みの旧ローカル成果物と過去の作業記録にはsuperpowers名称が残る。現行手順ではなく履歴・証跡であり、実行入力へ使う場合は`/plan`で現在状態と再照合する。
- 残るリスク: ユーザー領域の同名ProjectFoundation Skillはリポジトリ正本と不一致である。ProjectFoundation内では`.agents/skills/`を正とし、ユーザー領域の整理は他プロジェクトへの影響を確認してから別作業で行う。

### 標準化判定

- 現行手順が任意の外部Skillを必須依存にする問題は**標準化候補**とし、`開発フロー.md`の「Codex標準機能とSkillの利用」とpreflight/review Skillへ反映した。汎用Skillは適用条件に合う場合の補助とし、利用不能でもProjectFoundationの正本手順を継続できる構成にした。
- 同名Skillの複数配置は**保留**とした。リポジトリ側の正本を明示し、ユーザー領域の同期・削除は他プロジェクトへの影響確認後に再判断する。
- 過去の記録・成果物から製品名を一括削除する対応は**対象外**とした。履歴の意味を変えず、現行手順との境界を本記録へ残す方が追跡性を保てるためである。
