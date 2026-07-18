# Pre-push軽量品質ゲート設計

## 目的

`pre-push`で毎回実行しているFull検査を、送信対象commitの差分に対する軽量な静的検査へ置き換える。PRとmainのGitHub Actions Full/required checksは変更せず、push前の待ち時間を短縮しながら、明らかな空白・生成物・secret・変更対象のlint/format不備をpush前に検出する。

## 対象

- `scripts/check.ps1`へ`PrePush` Modeを追加する。
- pre-pushのstdinに渡される`local ref / local sha / remote ref / remote sha`を解析する。
- remote shaが存在する通常pushは、remote shaからlocal shaまでの変更ファイルを検査する。
- 新規ref pushは、既存remoteに含まれないlocal commitの変更ファイルを検査する。
- 削除refは検査対象から除外する。
- 変更対象に応じて、git diff check、生成物禁止、Gitleaks directory scan、Frontend ESLint、Markdownlint、Backend Spotlessを実行する。

## 対象外

- Frontend unit test、typecheck、build。
- Backend test-compile、Checkstyle、SpotBugs。
- Oracle接続、coverage、E2E、Dependency Audit。
- GitHub ActionsのFull/required status check、branch protection。

## 判定ルール

1. `git diff --check`で送信対象commitの空白エラーを検査する。
2. 送信対象に生成物・ローカル専用ファイルが含まれる場合は失敗する。
3. 現在の作業ツリーをGitleaks directory scanし、secret混入を検査する。
4. `frontend/`のTypeScript変更がある場合は、変更された`.ts`/`.tsx`だけをESLintへ渡す。設定・package・tsconfig変更時はFrontend lint全体を実行する。
5. Markdown変更がある場合は、変更されたMarkdownだけをMarkdownlintへ渡す。
6. `backend/`のJava変更がある場合は、Maven aggregatorのSpotless checkを実行する。
7. 各検査の失敗を集約し、1件でも失敗したらpre-pushを非0終了する。

## 失敗時の扱い

- pre-pushが非0終了し、Git pushを中止する。
- Fullの未実行は失敗扱いにしない。FullはPRのrequired status checkで必ず実行する。
- push後のPRでは、従来どおりFull、Backend Unit、Coverage、E2E、Gitleaks Directoryを実行する。

## セキュリティ・互換性

- push stdinのsha値はGit objectとして検証し、無効値や解析不能行は失敗にする。
- secret値や完全な接続情報を出力しない。
- PowerShell 7、Windows/Linux、既存のMaven/npm入口を使用する。
- Lefthookのpre-push stdinを利用するため、hook設定でstdinをrunnerへ渡す。

## 受入条件

- `PrePush`のref解析が通常push、新規ref、削除ref、複数ref、不正行を扱える。
- changed-filesから検査対象が正しく選択され、Frontend/Markdown/Backendの不要な検査を実行しない。
- PrePushがFullのtest/build/SpotBugsを呼ばない。
- pre-commitのQuickとGitHub ActionsのFull/required checkは従来どおり維持する。
- 既存のFull、契約テスト、Markdown lint、PowerShellテストが成功する。
