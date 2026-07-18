$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/check.ps1')

function Assert-Condition {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$Message
    )

    try {
        & $Action
    }
    catch {
        return
    }

    throw $Message
}

$zeroSha = '0000000000000000000000000000000000000000'
$localSha = '1111111111111111111111111111111111111111'
$remoteSha = '2222222222222222222222222222222222222222'
$inputText = @"
refs/heads/feature $localSha refs/heads/feature $remoteSha
refs/heads/new $localSha refs/heads/new $zeroSha
refs/heads/deleted $zeroSha refs/heads/deleted $remoteSha
"@
$records = @(Get-PushRefRecords -InputText $inputText)

Assert-Condition ($records.Count -eq 3) 'Three push ref records must be parsed.'
Assert-Condition ($records[0].LocalSha -eq $localSha) 'Local sha was not parsed.'
Assert-Condition ($records[0].RemoteSha -eq $remoteSha) 'Remote sha was not parsed.'
Assert-Condition ($records[1].RemoteSha -eq $zeroSha) 'New ref zero sha was not preserved.'
Assert-Condition ($records[2].LocalSha -eq $zeroSha) 'Deleted ref zero sha was not preserved.'
Assert-Throws { Get-PushRefRecords -InputText 'invalid push input' } `
    'Malformed push input must fail.'

$definitions = @(Get-PrePushCheckDefinitions `
        -RepoRoot $repoRoot `
        -ChangedFiles @('frontend/src/App.tsx', 'docs/quality.md', 'backend/src/main/java/App.java') `
        -NpmCommand 'npm.cmd' `
        -MavenCommand 'backend/mvnw.cmd' `
        -GitleaksCommand 'gitleaks')
$names = @($definitions | ForEach-Object Name)

foreach ($requiredName in @(
        'pre-push-diff-check',
        'pre-push-artifact-check',
        'pre-push-secrets',
        'frontend-pre-push-lint',
        'markdown-pre-push-lint',
        'backend-pre-push-spotless')) {
    Assert-Condition ($names -contains $requiredName) "Missing PrePush definition: $requiredName"
}

foreach ($forbiddenName in @(
        'frontend-unit-test',
        'frontend-typecheck',
        'frontend-build',
        'backend-test-compile',
        'backend-checkstyle',
        'backend-spotbugs')) {
    Assert-Condition ($names -notcontains $forbiddenName) "Full definition leaked into PrePush: $forbiddenName"
}

$lefthookText = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'lefthook.yml')
Assert-Condition ($lefthookText -match '-Mode PrePush') 'Lefthook must invoke PrePush mode.'
Assert-Condition ($lefthookText -match 'use_stdin:\s*true') 'Lefthook must pass pre-push stdin to the runner.'

Write-Output 'Pre-push contract tests passed.'
