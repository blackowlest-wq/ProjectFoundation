# Quality Harness Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** BackendCoverageとOracle診断が、テスト結果・JaCoCo成果物・環境未実行を区別して失敗を正しく伝播するようにする。

**Architecture:** 既存の scripts/check.ps1 を単一入口として維持し、coverage成果物検査に安定した失敗分類を追加する。JaCoCo reportはテスト完了後に生成し、PowerShell契約テストでworkflowと終了コードの契約を固定する。OracleはPR Required CIへ追加せず、main後の専用runnerで診断する。

**Tech Stack:** PowerShell 7、Maven Wrapper、Maven JaCoCo 0.8.12、GitHub Actions、Java 21、Maven 3.9.16。

## Global Constraints

- P0/P1レビュー、Required CI 6 check、各カバレッジ閾値を削除・任意化・引き下げない。
- Required CIは Full / Windows、Full / Linux、Backend / Unit、Coverage / Frontend、E2E、Gitleaks / Directory を維持する。
- OracleをPRのRequired CIへ追加しない。
- Oracle未実行、キャンセル、環境不足を成功扱いにしない。
- 接続URL、ユーザー名、パスワード、設定値をログへ出力しない。
- 日報承認・差戻し本体の機能コードは変更しない。

---

## File Map

- Modify: backend/pom.xml — JaCoCo reportのphaseをテスト完了後へ移す。
- Modify: scripts/check.ps1 — coverage成果物の分類付き検証を追加する。
- Modify: scripts/coverage-gate.tests.ps1 — BackendCoverageの実行定義と成果物契約を検証する。
- Modify: scripts/oracle-preflight.tests.ps1 — Windows/Linuxでwrapper契約を検証する。
- Modify: .github/workflows/oracle.yml — coverage失敗を隠さず、診断artifactを収集する。
- Modify: docs/AI活用開発研究/作業記録/日報承認差戻し_作業記録.md — 実施結果と未実行条件を記録する。

## Task 1: BackendCoverageの契約を先に固定する

**Files:** scripts/coverage-gate.tests.ps1

- [ ] Step 1: 現在の入口を再現する

    pwsh -NoProfile -File scripts/check.ps1 -CiTask BackendCoverage

Expected: Oracle環境がない場合はpreflightで非0終了し、接続値を出力しない。環境がある場合はテスト終了コードと backend/target/site/jacoco の実在を記録する。

- [ ] Step 2: 失敗する契約テストを追加する

    Assert-Condition ($backendArguments -contains '-Pcoverage') 'Backend coverage must use the coverage profile.'
    Assert-Condition ($backendArguments -contains 'verify') 'Backend coverage must run Maven verify.'
    Assert-Condition ($backendNames -contains 'backend-coverage-report') 'Backend coverage must have a report check.'
    Assert-Condition ($coverageGateText -match 'JACOCO_REPORT_MISSING') 'Backend report checks must expose a stable failure code.'
    Assert-Condition ($coverageGateText -match 'backend/target/jacoco\.exec') 'Backend coverage must verify the JaCoCo data file.'

- [ ] Step 3: 追加契約が未実装で失敗することを確認する

    pwsh -NoProfile -File scripts/coverage-gate.tests.ps1

Expected: JACOCO_REPORT_MISSINGまたはjacoco.exec契約の未実装を示してFAILする。

- [ ] Step 4: Commit

    git add scripts/coverage-gate.tests.ps1
    git commit -m "test: define backend coverage failure contract"

## Task 2: JaCoCo成果物生成と失敗分類を修正する

**Files:** backend/pom.xml、scripts/check.ps1、scripts/coverage-gate.tests.ps1

- [ ] Step 1: JaCoCo reportをverifyへ移す

backend/pom.xmlの report execution を次の状態にする。checkもverify phaseにあり、POM上でreportより後に置く。

    <execution>
        <id>report</id>
        <phase>verify</phase>
        <goals>
            <goal>report</goal>
        </goals>
    </execution>

理由: Surefire/Failsafe完了後にreportを生成する。

- [ ] Step 2: report checkに失敗コードを追加する

New-CoverageReportCheckDefinitionへ FailureCode を追加し、欠落時に次の形式でthrowする。

    throw "JACOCO_REPORT_MISSING: Coverage reports are missing: $($missing -join ', ')"

BackendCoverageの必須パスは次の4件とする。

    backend/target/jacoco.exec
    backend/target/site/jacoco/index.html
    backend/target/site/jacoco/jacoco.xml
    backend/target/site/jacoco/jacoco.csv

Maven非0終了はテストまたはthreshold側の失敗として非0を維持する。

- [ ] Step 3: 契約テストとBackendCoverageを実行する

    pwsh -NoProfile -File scripts/coverage-gate.tests.ps1
    pwsh -NoProfile -File scripts/check.ps1 -CiTask BackendCoverage

Expected: テスト失敗時はMaven非0、テスト成功後に成果物がない場合はJACOCO_REPORT_MISSING、全成果物と閾値が揃った場合だけPASSする。

- [ ] Step 4: Commit

    git add backend/pom.xml scripts/check.ps1 scripts/coverage-gate.tests.ps1
    git commit -m "fix: make backend coverage reports deterministic"

## Task 3: Oracle wrapperとworkflowの失敗境界を検証する

**Files:** scripts/oracle-preflight.tests.ps1、.github/workflows/oracle.yml

- [ ] Step 1: Windows/Linux wrapper契約を実行する

    pwsh -NoProfile -File scripts/oracle-preflight.tests.ps1

Expected: 空パスワードはMaven開始前に非0終了し、Windowsのcmd shimとLinux相当のPowerShell wrapperが接続値を出力しない。

- [ ] Step 2: workflowの失敗隠蔽を契約化する

oracle.ymlのcoverage本体に continue-on-error: true を追加しない。summaryとartifact uploadだけを if: always() にする。契約テストは、continue-on-error: true がないことと、if: always() があることを検証する。

- [ ] Step 3: 実行状態を記録する

    gh run list --workflow oracle.yml --limit 5
    $oracleRunId = gh run list --workflow oracle.yml --limit 1 --json databaseId --jq '.[0].databaseId'
    gh run view $oracleRunId --json status,conclusion,jobs,url

Expected: PASSED、FAILED、NOT_RUN_ENVIRONMENT、CANCELLED_OR_TIMEOUTを作業記録で区別する。接続値は記録しない。

- [ ] Step 4: Commit

    git add scripts/oracle-preflight.tests.ps1 .github/workflows/oracle.yml
    git commit -m "test: preserve oracle failure diagnostics"

## Task 4: 最終検証と実施記録

**Files:** docs/AI活用開発研究/作業記録/日報承認差戻し_作業記録.md

- [ ] Step 1: ローカル検証を実行する

    pwsh -NoProfile -File scripts/coverage-gate.tests.ps1
    pwsh -NoProfile -File scripts/oracle-preflight.tests.ps1
    pwsh -NoProfile -File scripts/check.ps1 -Mode Full

Expected: 契約テストとFullが成功する。Oracle資格情報がない場合はOracle未実行として記録する。

- [ ] Step 2: Required CIを実行する

    $qualityBranch = git branch --show-current
    gh workflow run quality.yml --ref $qualityBranch
    gh run list --workflow quality.yml --limit 1

Expected: Required CI 6 checkの結果とログURLを記録し、失敗を推測で成功扱いにしない。

- [ ] Step 3: 作業記録を更新する

実行commit、コマンド、結果、CI/Oracle URL、未実行理由、再確認条件、標準化判定を記録する。秘密値は記録しない。

- [ ] Step 4: 差分を確認してCommitする

    git diff --check
    git status --short
    git add docs/AI活用開発研究/作業記録/日報承認差戻し_作業記録.md
    git commit -m "docs: record quality harness verification"
