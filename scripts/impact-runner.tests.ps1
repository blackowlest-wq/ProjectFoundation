$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/check.ps1')

function Assert-Condition {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-SetEquals {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Actual,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Expected,
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

$localUiLayers = @('FullFrontend', 'FrontendCoverage', 'E2E', 'DirectorySecrets')
$localUiExcludedLayers = @('FullBackend', 'BackendUnit', 'Oracle', 'BackendCoverage', 'E2EOracle')
$localApiLayers = @(
    'FullFrontend', 'FullBackend', 'BackendUnit', 'E2E', 'DirectorySecrets',
    'Oracle', 'BackendCoverage', 'E2EOracle'
)
$localApiExcludedLayers = @('FrontendCoverage')
$trackedFiles = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
git -C $repoRoot ls-files | ForEach-Object { $null = $trackedFiles.Add($_.Replace('\', '/')) }
Assert-Condition ($LASTEXITCODE -eq 0) 'Impact regression setup must read tracked repository paths.'

$impactCases = @(
    [pscustomobject]@{
        Name = 'bounded local UI'
        Files = @('frontend/src/dailyReport/DailyReportForm.tsx')
        Selected = $localUiLayers
        Excluded = $localUiExcludedLayers
        Scope = 'Impact'
        Fallback = $false
        FallbackReason = '^$'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'bounded API Controller with direct consumers and changed backend coverage'
        Files = @('backend/src/main/java/com/example/dailyreport/report/controller/DailyReportCommandController.java')
        Selected = $localApiLayers
        Excluded = $localApiExcludedLayers
        Scope = 'Impact'
        Fallback = $false
        FallbackReason = '^$'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'ordinary Service business workflow'
        Files = @('backend/src/main/java/com/example/dailyreport/report/DailyReportCommandService.java')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SCOPE_UNBOUNDED_BUSINESS_STATE:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'business rule'
        Files = @('backend/src/main/java/com/example/dailyreport/report/logic/TimeRules.java')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SCOPE_UNBOUNDED_BUSINESS_STATE:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'workflow state transition'
        Files = @('backend/src/main/java/com/example/dailyreport/workflow/ApprovalStatus.java')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SCOPE_UNBOUNDED_BUSINESS_STATE:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'auth CSRF security config'
        Files = @('backend/src/main/java/com/example/dailyreport/config/SecurityConfig.java')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SCOPE_UNBOUNDED_AUTH_SECURITY:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'shared frontend auth and CSRF client'
        Files = @('frontend/src/shared/apiClient.ts')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SCOPE_UNBOUNDED_AUTH_SECURITY:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'common exception contract'
        Files = @('backend/src/main/java/com/example/dailyreport/common/ApiExceptionHandler.java')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SCOPE_UNBOUNDED_COMMON_CONTRACT:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'Repository DB contract'
        Files = @('backend/src/main/java/com/example/dailyreport/report/entity/DailyReportRepository.java')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SCOPE_UNBOUNDED_DATABASE:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'Entity DB mapping'
        Files = @('backend/src/main/java/com/example/dailyreport/report/entity/DailyReportEntity.java')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SCOPE_UNBOUNDED_DATABASE:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'SQL and DDL schema'
        Files = @('backend/src/main/resources/db/oracle/schema-login.sql')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SCOPE_UNBOUNDED_DATABASE:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'shared master data'
        Files = @('backend/src/main/java/com/example/dailyreport/master/MasterController.java')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SCOPE_UNBOUNDED_DATABASE:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'shared test fixture and support'
        Files = @('backend/src/test/java/com/example/dailyreport/report/support/DailyReportTestSupport.java')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SCOPE_UNBOUNDED_COMMON_CONTRACT:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'GitHub workflow config'
        Files = @('.github/workflows/quality.yml')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SELECTOR_OR_GATE_CHANGED:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'quality runner'
        Files = @('scripts/check.ps1')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SELECTOR_OR_GATE_CHANGED:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'qualified Oracle Playwright runner config'
        Files = @('frontend/playwright.oracle.config.ts')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SELECTOR_OR_GATE_CHANGED:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'backend Oracle runner config contract'
        Files = @('backend/config/oracle-test.example.properties')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SELECTOR_OR_GATE_CHANGED:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'backend test discovery config'
        Files = @('backend/src/test/resources/application-test.yml')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SELECTOR_OR_GATE_CHANGED:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'aggregate build and dependency config'
        Files = @('backend/pom.xml')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SELECTOR_OR_GATE_CHANGED:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'dependency lock config'
        Files = @('frontend/package-lock.json')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SELECTOR_OR_GATE_CHANGED:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'coverage gate config contract'
        Files = @('frontend/test/coverageConfig.test.ts')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SELECTOR_OR_GATE_CHANGED:'
        Tracked = $true
    }
    [pscustomobject]@{
        Name = 'unknown repository area'
        Files = @('unknown-area/undocumented.file')
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SCOPE_UNKNOWN:'
        Tracked = $false
    }
    [pscustomobject]@{
        Name = 'unavailable empty scope'
        Files = @()
        Selected = $allLayers
        Excluded = @()
        Scope = 'Full'
        Fallback = $true
        FallbackReason = '^IMPACT_SCOPE_UNAVAILABLE:'
        Tracked = $false
    }
)

foreach ($case in $impactCases) {
    if ($case.Tracked) {
        foreach ($file in $case.Files) {
            Assert-Condition $trackedFiles.Contains($file) "Regression case '$($case.Name)' must use a tracked path: $file"
        }
    }

    $plan = Get-ImpactPlan -ChangedFiles $case.Files
    Assert-SetEquals -Actual $plan.SelectedLayers -Expected $case.Selected `
        -Message "Regression case '$($case.Name)' selected the wrong layers."
    Assert-SetEquals -Actual $plan.ExcludedLayers -Expected $case.Excluded `
        -Message "Regression case '$($case.Name)' excluded the wrong layers."
    Assert-Condition ($plan.ExecutionScope -eq $case.Scope) `
        "Regression case '$($case.Name)' expected scope $($case.Scope), actual $($plan.ExecutionScope)."
    Assert-Condition ($plan.FallbackUsed -eq $case.Fallback) `
        "Regression case '$($case.Name)' expected FallbackUsed=$($case.Fallback)."
    Assert-Condition ([string]$plan.FallbackReason -match $case.FallbackReason) `
        "Regression case '$($case.Name)' fallback reason did not match '$($case.FallbackReason)': $($plan.FallbackReason)"
}

$frontendPlan = Get-ImpactPlan -ChangedFiles @('frontend/src/dailyReport/DailyReportForm.tsx')

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

    $selectedAggregateFailureCases = @(
        [pscustomobject]@{
            Name = 'missing selected job'
            JobResults = @{
                'oracle-integration' = @{ result = 'skipped'; outputs = @{} }
            }
        }
        [pscustomobject]@{
            Name = 'skipped selected job'
            JobResults = @{
                'full-windows-frontend' = @{ result = 'skipped'; outputs = @{} }
                'oracle-integration' = @{ result = 'skipped'; outputs = @{} }
            }
        }
        [pscustomobject]@{
            Name = 'failed selected job'
            JobResults = @{
                'full-windows-frontend' = @{ result = 'failure'; outputs = @{ state = 'failed' } }
                'oracle-integration' = @{ result = 'skipped'; outputs = @{} }
            }
        }
        [pscustomobject]@{
            Name = 'selected job missing recorded state'
            JobResults = @{
                'full-windows-frontend' = @{ result = 'success'; outputs = @{} }
                'oracle-integration' = @{ result = 'skipped'; outputs = @{} }
            }
        }
    )
    foreach ($case in $selectedAggregateFailureCases) {
        $invalidAggregate = Test-ImpactAggregate -Plan $frontendPlan -Layers @('FullFrontend', 'Oracle') `
            -JobMap $jobMap -JobResults $case.JobResults -AllowExcludedJobSkip
        Assert-Condition (-not $invalidAggregate.Succeeded) `
            "Aggregate must reject $($case.Name)."
        $frontendRow = @($invalidAggregate.Jobs | Where-Object { $_.Layer -eq 'FullFrontend' })
        Assert-Condition ($frontendRow.Count -eq 1 -and -not $frontendRow[0].Valid) `
            "Aggregate must mark $($case.Name) invalid for the selected layer."
    }

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
