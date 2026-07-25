# ブランチ作成前main確認手順 設計

## 背景

作業開始時に`main`へコミットが残ったまま自動的に作業ブランチへ切り替わると、変更の所属が不明確になり、mainへ意図しないコミットを残す可能性がある。

## 方針

- ブランチ作成前に`main`を作業起点へ戻し、作業ツリーとリモートとの差分を確認する。
- `git status --short`が空であることを確認する。
- `git rev-list --left-right --count main...origin/main`が`0 0`であることを確認する。
- 条件不一致時は自動stash、reset、破棄、強制pushをせず、原因確認で停止する。
- 条件一致後だけ`git switch -c codex/<topic>`を実行する。

## 対象外

- ブランチ作成を自動化する新しいCLIの追加
- mainの差分を自動的にmerge、rebase、resetする処理
- 既存のpre-commit / pre-push品質ゲートの変更
