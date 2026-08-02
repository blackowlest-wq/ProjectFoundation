$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-WorkflowJobBlock {
    param([Parameter(Mandatory)][string]$Workflow, [Parameter(Mandatory)][string]$JobId)
    $escaped = [regex]::Escape($JobId)
    $match = [regex]::Match($Workflow, "(?ms)^  ${escaped}:\r?\n(?<body>.*?)(?=^  [a-z0-9][a-z0-9-]*:\r?$|\z)")
    if (-not $match.Success) { throw "Workflow job is missing: $JobId" }
    $match.Groups['body'].Value
}

function Assert-ImpactWorkflow {
    param(
        [Parameter(Mandatory)][string]$Workflow,
        [Parameter(Mandatory)][hashtable]$LayerJobs,
        [Parameter(Mandatory)][string]$AggregateJob,
        [switch]$OracleWorkflow
    )

    $triggerBlock = $Workflow.Substring(0, $Workflow.IndexOf("`npermissions:"))
    Assert-Condition ($triggerBlock -match '(?m)^  schedule:\s*$') 'Workflow must define a scheduled full gate.'
    if (-not $OracleWorkflow) {
        Assert-Condition ($triggerBlock -match '(?m)^    tags:\s*$') 'Quality workflow must define a release-tag full gate.'
    }
    Assert-Condition ($triggerBlock -match '(?m)^  workflow_dispatch:\s*$') 'Workflow must define a release-before manual gate.'

    $plan = Get-WorkflowJobBlock -Workflow $Workflow -JobId 'impact-plan'
    Assert-Condition ($plan -match "Mode\s*=\s*'Impact'" -and $plan -match "ImpactTask\s*=\s*'Plan'") `
        'Plan job must use the explicit Impact runner entry.'
    Assert-Condition ($plan -match '(?m)^    outputs:\s*$' -and $plan -match 'steps\.plan\.outputs\.') `
        'Plan job must publish selected scope for downstream jobs.'
    Assert-Condition ($plan -match 'release-before|nightly') 'Plan job must force full for night/release execution.'
    if ($OracleWorkflow) {
        Assert-Condition ($plan -match "refs/heads/main") 'Manual Oracle full execution must remain restricted to main.'
    }

    foreach ($entry in $LayerJobs.GetEnumerator()) {
        $block = Get-WorkflowJobBlock -Workflow $Workflow -JobId $entry.Key
        Assert-Condition ($block -match [regex]::Escape("-Mode Impact -ImpactTask $($entry.Value)")) `
            "Layer job $($entry.Key) must execute through Impact task $($entry.Value)."
        if (-not $OracleWorkflow) {
            Assert-Condition ($block -notmatch '(?m)^    if:\s*.*outputs\..*==\s*''true''') `
                "Required quality job $($entry.Key) must not become a green job-level conditional skip."
        }
    }

    $aggregate = Get-WorkflowJobBlock -Workflow $Workflow -JobId $AggregateJob
    Assert-Condition ($aggregate -match '(?m)^    if:\s*\$\{\{\s*always\(\)\s*\}\}') `
        'Stable aggregate must run even after failed or skipped dependencies.'
    Assert-Condition ($aggregate -match '-Mode Impact\s+-ImpactTask Aggregate') `
        'Stable aggregate must validate selected, excluded, missing, skipped, and failed jobs through check.ps1.'
    foreach ($jobId in $LayerJobs.Keys) {
        Assert-Condition ($aggregate -match [regex]::Escape($jobId)) "Aggregate must include job $jobId."
    }
}

$quality = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot '.github/workflows/quality.yml')
$oracle = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot '.github/workflows/oracle.yml')
$lefthook = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'lefthook.yml')

Assert-ImpactWorkflow -Workflow $quality -LayerJobs @{
    'full-windows-frontend' = 'FullFrontend'
    'full-windows-backend' = 'FullBackend'
    'backend-unit' = 'BackendUnit'
    'coverage-frontend' = 'FrontendCoverage'
    'e2e' = 'E2E'
    'gitleaks-directory' = 'DirectorySecrets'
} -AggregateJob 'quality-aggregate'

foreach ($jobId in @(
        'impact-plan'
        'full-windows-frontend'
        'full-windows-backend'
        'backend-unit'
        'coverage-frontend'
        'e2e'
        'gitleaks-directory'
        'quality-aggregate'
    )) {
    $qualityJob = Get-WorkflowJobBlock -Workflow $quality -JobId $jobId
    Assert-Condition ($qualityJob -match '(?m)^    timeout-minutes:\s*10\s*$') `
        "Quality workflow job $jobId must have a 10-minute timeout."
}

Assert-ImpactWorkflow -Workflow $oracle -LayerJobs @{
    'oracle-integration' = 'Oracle'
    'oracle-coverage' = 'BackendCoverage'
    'oracle-e2e' = 'E2EOracle'
} -AggregateJob 'oracle-aggregate' -OracleWorkflow

Assert-Condition ($lefthook -match '-Mode Quick') 'Pre-commit must remain the lightweight Quick entry.'
Assert-Condition ($lefthook -match '-Mode PrePush') 'Pre-push must remain the lightweight diff-based PrePush entry.'
Assert-Condition ($lefthook -notmatch '-Mode (Full|Impact)') 'Local hooks must not run Full or Impact CI gates.'

Write-Output 'Impact workflow contract tests passed.'
