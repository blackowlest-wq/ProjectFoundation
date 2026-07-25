# 個人開発向け品質ゲート変更計画

## 目的

PRを使わない個人開発で、ブランチpushは軽量PrePush、`main`反映後はFullという一回ずつの品質確認に整理する。

## 手順

1. `coverage-gate.tests.ps1`へ、PR起動なしと`main`push起動の契約を追加する。
2. 契約テストを実行し、現行workflowがREDになることを確認する。
3. `quality.yml`の`pull_request`トリガーを削除する。
4. 品質ゲート運用、開発フロー、レビューSkillのPR前提を個人開発運用へ更新する。
5. 作業記録へ受入条件、変更範囲、検証結果、標準化判定を記録する。
6. Markdown lint、契約テスト、Full、差分確認を実行する。
7. 変更をコミットし、現在のブランチへプッシュする。

## 完了条件

- PR workflowが存在しない。
- branch pushはPrePushのみである。
- `main` pushのquality workflow定義が維持されている。
- 契約テストとFullが成功している。
- 作業記録と標準資料の内容が一致している。
