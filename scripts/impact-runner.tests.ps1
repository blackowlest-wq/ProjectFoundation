$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/check.ps1')

function Assert-Condition {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-SetEquals {
    param(
        [Parameter(Mandatory)][string[]]$Actual,
        [Parameter(Mandatory)][string[]]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    $actualValue = @($Actual | Sort-Object -Unique) -join ','
    $expectedValue = @($Expected | Sort-Object -Unique) -join ','
    Assert-Condition ($actualValue -eq $expectedValue) "$Message Expected=[$expectedValue] Actual=[$actualValue]"
}

$allLayers = @(
    'FullFrontend',
    'FullBackend',
    'BackendUnit',
    'FrontendCoverage',
    'E2E',
    'DirectorySecrets',
    'Oracle',
    'BackendCoverage',
    'E2EOracle'
)

$frontendPlan = Get-ImpactPlan -ChangedFiles @('frontend/src/dailyReport/DailyReportForm.tsx')
Assert-SetEquals -Actual $frontendPlan.SelectedLayers -Expected @(
    'FullFrontend', 'FrontendCoverage', 'E2E', 'DirectorySecrets'
) -Message 'A local frontend UI change must select its layer, coverage, direct E2E consumer, and directory secrets.'
Assert-Condition (-not $frontendPlan.FallbackUsed) 'A known local frontend change must not use full fallback.'
Assert-Condition ($frontendPlan.ExcludedLayers -contains 'Oracle') 'Unrelated Oracle integration must be explicitly excluded.'

$frontendAssetPlan = Get-ImpactPlan -ChangedFiles @('frontend/public/brand.svg')
Assert-SetEquals -Actual $frontendAssetPlan.SelectedLayers -Expected @(
    'FullFrontend', 'FrontendCoverage', 'E2E', 'DirectorySecrets'
) -Message 'A local frontend asset change must select the frontend layer and direct consumers.'
Assert-Condition (-not $frontendAssetPlan.FallbackUsed) 'A known local frontend asset must not use unknown-scope fallback.'

$backendPlan = Get-ImpactPlan -ChangedFiles @(
    'backend/src/main/java/com/example/dailyreport/report/DailyReportSearchController.java'
)
Assert-SetEquals -Actual $backendPlan.SelectedLayers -Expected @(
    'FullBackend', 'BackendUnit', 'E2E', 'DirectorySecrets'
) -Message 'A local backend API change must select backend quality/tests and its E2E contract consumer.'

$authPlan = Get-ImpactPlan -ChangedFiles @('frontend/src/shared/apiClient.ts')
foreach ($layer in @('FullFrontend', 'FrontendCoverage', 'E2E', 'Oracle', 'BackendCoverage', 'E2EOracle')) {
    Assert-Condition ($authPlan.SelectedLayers -contains $layer) "Shared CSRF/auth code must expand to $layer."
}
Assert-Condition (-not $authPlan.FallbackUsed) 'A recognized cross-cutting auth change is an expanded impact plan, not an unknown fallback.'

$databasePlan = Get-ImpactPlan -ChangedFiles @('backend/src/main/resources/db/oracle/schema-login.sql')
foreach ($layer in @('FullBackend', 'BackendUnit', 'E2E', 'Oracle', 'BackendCoverage', 'E2EOracle')) {
    Assert-Condition ($databasePlan.SelectedLayers -contains $layer) "Database/SQL changes must expand to $layer."
}

foreach ($fallbackCase in @(
        @('scripts/check.ps1'),
        @('.github/workflows/quality.yml'),
        @('frontend/package-lock.json'),
        @('unknown-area/undocumented.file'),
        @()
    )) {
    $fallbackPlan = Get-ImpactPlan -ChangedFiles $fallbackCase
    Assert-Condition $fallbackPlan.FallbackUsed 'Runner/workflow/dependency/unknown/empty scope must use full fallback.'
    Assert-SetEquals -Actual $fallbackPlan.SelectedLayers -Expected $allLayers `
        -Message 'Full fallback must select every quality and Oracle layer.'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($fallbackPlan.FallbackReason)) `
        'Full fallback must record a non-empty reason.'
}

$forcedPlan = Get-ImpactPlan -ChangedFiles @('docs/quality.md') -ForceFullReason 'release-before'
Assert-Condition (-not $forcedPlan.FallbackUsed) 'An intentional night/release full execution is not an analysis fallback.'
Assert-Condition ($forcedPlan.FullReason -match 'release-before') 'Forced full reason must be recorded.'
Assert-SetEquals -Actual $forcedPlan.SelectedLayers -Expected $allLayers `
    -Message 'Forced full execution must select every layer.'

$changedFileList = Join-Path ([System.IO.Path]::GetTempPath()) "projectfoundation-impact-files-$PID.txt"
$resultDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "projectfoundation-impact-results-$PID"
try {
    @('frontend/src/auth/authApi.ts', 'frontend/test/authApi.test.ts') |
        Set-Content -LiteralPath $changedFileList -Encoding utf8NoBOM
    $fromFile = @(Get-ImpactChangedFiles -RepoRoot $repoRoot -ChangedFilesPath $changedFileList)
    Assert-SetEquals -Actual $fromFile -Expected @(
        'frontend/src/auth/authApi.ts', 'frontend/test/authApi.test.ts'
    ) -Message 'CI changed-file input must preserve normalized repository-relative paths.'

    $fromPushDiff = @(Get-ImpactChangedFiles -RepoRoot $repoRoot -BaseRef 'HEAD~1' -HeadRef 'HEAD')
    Assert-Condition ($fromPushDiff.Count -gt 0) 'Impact runner must derive changed files from an available push diff.'

    $forcedCliPlanPath = Join-Path $resultDirectory 'forced-plan.json'
    & pwsh -NoProfile -File (Join-Path $repoRoot 'scripts/check.ps1') -Mode Impact -ImpactTask Plan `
        -ForceFullReason 'release-before' -ImpactPlanPath $forcedCliPlanPath | Out-Host
    Assert-Condition ($LASTEXITCODE -eq 0) 'Intentional full CLI planning must not require a changed-file input.'
    $forcedCliPlan = Get-Content -Raw -Encoding UTF8 $forcedCliPlanPath | ConvertFrom-Json
    Assert-Condition ($forcedCliPlan.ExecutionScope -eq 'Full') 'Intentional full CLI planning must select Full scope.'
    Assert-Condition (-not $forcedCliPlan.FallbackUsed) 'Intentional full CLI planning must not be mislabeled as fallback.'
    Assert-Condition ($forcedCliPlan.FullReason -eq 'release-before') 'Intentional full CLI reason must survive serialization.'

    $fallbackCliPlanPath = Join-Path $resultDirectory 'fallback-plan.json'
    & pwsh -NoProfile -File (Join-Path $repoRoot 'scripts/check.ps1') -Mode Impact -ImpactTask Plan `
        -BaseRef ('0' * 40) -HeadRef 'HEAD' -ImpactPlanPath $fallbackCliPlanPath | Out-Host
    Assert-Condition ($LASTEXITCODE -eq 0) 'Unavailable push scope must conservatively plan Full instead of skipping the gate.'
    $fallbackCliPlan = Get-Content -Raw -Encoding UTF8 $fallbackCliPlanPath | ConvertFrom-Json
    Assert-Condition $fallbackCliPlan.FallbackUsed 'Unavailable push scope must set the fallback flag.'
    Assert-Condition ($fallbackCliPlan.FallbackReason -match 'zero SHA') 'Unavailable push scope must record its fallback reason.'

    New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null
    $excludedResultPath = Join-Path $resultDirectory 'oracle.json'
    $excludedInvocationCount = 0
    $excludedExit = Invoke-ImpactLayer -Plan $frontendPlan -Layer Oracle -RepoRoot $repoRoot `
        -ResultPath $excludedResultPath -CommandInvoker {
            $script:excludedInvocationCount++
            return 0
        }
    $excludedResult = Get-Content -Raw -Encoding UTF8 $excludedResultPath | ConvertFrom-Json
    Assert-Condition ($excludedExit -eq 0) 'An explicitly excluded layer may complete only after writing an exclusion result.'
    Assert-Condition ($excludedResult.State -eq 'Excluded') 'Excluded layer result must be explicit.'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($excludedResult.Reason)) 'Excluded layer result must include a reason.'
    Assert-Condition ($excludedInvocationCount -eq 0) 'Excluded layers must not execute hidden checks.'

    $passedResultPath = Join-Path $resultDirectory 'frontend-passed.json'
    $passedExit = Invoke-ImpactLayer -Plan $frontendPlan -Layer FullFrontend -RepoRoot $repoRoot `
        -ResultPath $passedResultPath -NpmCommand 'npm' -MavenCommand 'mvnw' -GitleaksCommand 'gitleaks' `
        -CommandInvoker { return 0 }
    $passedResult = Get-Content -Raw -Encoding UTF8 $passedResultPath | ConvertFrom-Json
    Assert-Condition ($passedExit -eq 0) 'Selected layer with passing checks must return zero.'
    Assert-Condition ($passedResult.State -eq 'Passed') 'Selected passing layer must record Passed.'
    Assert-Condition (@($passedResult.Checks).Count -gt 0) 'Selected layer must record individual job results.'

    $failedResultPath = Join-Path $resultDirectory 'frontend-failed.json'
    $failedExit = Invoke-ImpactLayer -Plan $frontendPlan -Layer FullFrontend -RepoRoot $repoRoot `
        -ResultPath $failedResultPath -NpmCommand 'npm' -MavenCommand 'mvnw' -GitleaksCommand 'gitleaks' `
        -CommandInvoker { return 9 }
    $failedResult = Get-Content -Raw -Encoding UTF8 $failedResultPath | ConvertFrom-Json
    Assert-Condition ($failedExit -ne 0) 'A selected layer with failed checks must return nonzero.'
    Assert-Condition ($failedResult.State -eq 'Failed') 'Selected failed layer must record Failed.'

    $jobMap = @{
        FullFrontend = 'full-windows-frontend'
        Oracle = 'oracle-integration'
    }
    $validJobResults = @{
        'full-windows-frontend' = @{ result = 'success'; outputs = @{ state = 'passed' } }
        'oracle-integration' = @{ result = 'skipped'; outputs = @{} }
    }
    $aggregateResult = Test-ImpactAggregate -Plan $frontendPlan -Layers @('FullFrontend', 'Oracle') `
        -JobMap $jobMap -JobResults $validJobResults -AllowExcludedJobSkip
    Assert-Condition $aggregateResult.Succeeded `
        'Aggregate must accept a passed selected job and an explicitly planned excluded Oracle skip.'

    $invalidJobResults = @{
        'full-windows-frontend' = @{ result = 'skipped'; outputs = @{} }
        'oracle-integration' = @{ result = 'skipped'; outputs = @{} }
    }
    $invalidAggregate = Test-ImpactAggregate -Plan $frontendPlan -Layers @('FullFrontend', 'Oracle') `
        -JobMap $jobMap -JobResults $invalidJobResults -AllowExcludedJobSkip
    Assert-Condition (-not $invalidAggregate.Succeeded) `
        'Aggregate must fail when a selected job is skipped or has no passing result.'

    $aggregatePlanPath = Join-Path $resultDirectory 'aggregate-plan.json'
    $aggregateResultPath = Join-Path $resultDirectory 'aggregate-result.json'
    Write-ImpactJson -Value $frontendPlan -Path $aggregatePlanPath
    $jobResultsJson = $validJobResults | ConvertTo-Json -Depth 5 -Compress
    & pwsh -NoProfile -File (Join-Path $repoRoot 'scripts/check.ps1') -Mode Impact -ImpactTask Aggregate `
        -ImpactPlanPath $aggregatePlanPath -ImpactResultPath $aggregateResultPath `
        -ImpactJobResultsJson $jobResultsJson `
        -ImpactJobMap 'FullFrontend=full-windows-frontend,Oracle=oracle-integration' `
        -AllowExcludedJobSkip | Out-Host
    Assert-Condition ($LASTEXITCODE -eq 0) 'Aggregate CLI must preserve multiline/JSON job results as one argument.'
    $aggregateCliResult = Get-Content -Raw -Encoding UTF8 $aggregateResultPath | ConvertFrom-Json
    Assert-Condition $aggregateCliResult.Succeeded 'Aggregate CLI must serialize a passing stable result.'
}
finally {
    if (Test-Path -LiteralPath $changedFileList) { Remove-Item -LiteralPath $changedFileList -Force }
    if (Test-Path -LiteralPath $resultDirectory) { Remove-Item -LiteralPath $resultDirectory -Recurse -Force }
}

Write-Output 'Impact runner contract tests passed.'
