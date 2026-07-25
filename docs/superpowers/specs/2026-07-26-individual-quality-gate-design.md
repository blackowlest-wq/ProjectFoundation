# 個人開発向け品質ゲート運用設計

## 背景

チーム開発ではPull Requestを品質ゲートの入口にできるが、本リポジトリは個人開発として運用するため、PR作成・レビュー・マージの手順を採用しない。ブランチpush時にFullを実行すると、`main`反映後のFullと同じコミットを重複検査する可能性がある。

## 方針

- ブランチpushは、既存のLefthook `PrePush`だけを実行する。
- GitHub Actionsの品質workflowは`pull_request`では起動しない。
- `main`へのpushをFull品質ゲートの正式な実行契機とする。
- `main`へのfast-forwardマージ、マージコミット、直接pushのいずれも、反映されたコミットに対して一度Fullを実行する。
- Oracle workflowは既存どおり`main`へのpushまたは手動実行とする。
- PR向けの手順、PR必須チェック、PR本文への記録を個人開発の完了条件から外し、変更記録へ集約する。

## 変更対象

- `.github/workflows/quality.yml`
- `scripts/coverage-gate.tests.ps1`
- `lefthook.yml`と`PrePush`定義は変更しない
- 品質ゲート運用、開発フロー、レビューSkill、READMEの現行記述
- 個人開発向けの作業記録

## 受入条件

| ID | 条件 | 確認方法 |
| --- | --- | --- |
| AC-QG-001 | 品質workflowがPull Requestで起動しない | `coverage-gate.tests.ps1`のworkflow契約テスト |
| AC-QG-002 | 品質workflowが`main`へのpushで起動する | `coverage-gate.tests.ps1`のworkflow契約テスト |
| AC-QG-003 | ブランチpushのLefthookが`PrePush`のままで、Fullを実行しない | `pre-push.tests.ps1`と`lefthook.yml`の確認 |
| AC-QG-004 | `main`反映時のFull、coverage、E2E、secret scanのjob定義が維持される | `coverage-gate.tests.ps1`とFull品質ゲート |
| AC-QG-005 | 現行運用資料がPRなしの個人開発フローと一致する | Markdown lintとレビュー |

## テスト方針

workflow起動条件は実際のGitHub Actionsを毎回起動せず、既存の品質ゲート契約テストで正規表現による契約を確認する。PrePushの差分限定契約とFullの各job定義は既存テストで維持し、最終確認ではMarkdown lint、契約テスト、Fullを実行する。

## 対象外

- `scripts/check.ps1`の`Quick`、`PrePush`、`Full`のチェック内容
- Oracle接続条件、DDL、coverage threshold、E2Eシナリオ
- 過去のPR前提のspec/planなど履歴資料
- GitHub Settingsのbranch protectionをAPIから変更する作業
