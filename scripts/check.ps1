[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet('Quick', 'PrePush', 'Full', 'Simple', 'Oracle', 'All', 'Impact')]
    [string]$Mode = 'Quick',
    [string]$PushInput,
    [switch]$Offline,
    [ValidateSet('None', 'FullFrontend', 'FullBackend', 'FrontendCoverage', 'BackendCoverage', 'BackendUnit', 'E2E', 'E2EOracle', 'DirectorySecrets', 'DependencyAudit')]
    [string]$CiTask = 'None',
    [switch]$AllowDdl,
    [string]$DdlScript,
    [string]$OracleConfigPath,
    [ValidateSet('Docs', 'Frontend', 'Backend', 'Harness', 'Mixed')]
    [string]$Scope,
    [ValidateSet('Frontend', 'Backend', 'Harness')]
    [string]$FocusedUnitScope,
    [string]$FocusedUnitTarget,
    [string]$FocusedUnitNotApplicableReason,
    [switch]$DisplayRequirement,
    [string]$BrowserCase,
    [string]$BrowserManualReason,
    [ValidateSet('Plan', 'FullFrontend', 'FullBackend', 'BackendUnit', 'FrontendCoverage', 'E2E', 'DirectorySecrets', 'Oracle', 'BackendCoverage', 'E2EOracle', 'Aggregate')]
    [string]$ImpactTask = 'Plan',
    [string]$ChangedFilesPath,
    [string]$BaseRef,
    [string]$HeadRef,
    [string]$ImpactPlanPath,
    [string]$ImpactResultPath,
    [string]$ImpactJobResultsJson,
    [string]$ImpactJobMap,
    [string]$ForceFullReason,
    [switch]$AllowExcludedJobSkip
)

$ErrorActionPreference = 'Stop'
$isWindowsHost = if ($null -ne (Get-Variable IsWindows -ErrorAction SilentlyContinue)) { [bool]$IsWindows } else { $env:OS -eq 'Windows_NT' }

function New-CheckDefinition {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$Command,
        [object[]]$Arguments = @(),
        [scriptblock]$Action,
        [string[]]$DependsOn = @(),
        [string]$WorkingDirectory
    )

    $definition = [ordered]@{
        Name = $Name
        Action = $Action
        DependsOn = @($DependsOn)
    }
    if ($PSBoundParameters.ContainsKey('Command')) {
        $definition.Command = $Command
        $definition.Arguments = @($Arguments)
    }
    if ($PSBoundParameters.ContainsKey('WorkingDirectory')) {
        $definition.WorkingDirectory = $WorkingDirectory
    }

    [pscustomobject]$definition
}

function New-CoverageReportCheckDefinition {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Paths,
        [string]$FailureCode = 'COVERAGE_REPORT_MISSING',
        [string[]]$DependsOn = @()
    )

    New-CheckDefinition -Name $Name -DependsOn $DependsOn -Action {
        $missing = @($Paths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
        if ($missing.Count -gt 0) {
            throw "${FailureCode}: Coverage reports are missing: $($missing -join ', ')"
        }
        Write-Host 'Coverage reports:'
        $Paths | ForEach-Object { Write-Host " - $_" }
    }.GetNewClosure()
}

function Get-MavenArguments {
    param(
        [switch]$Offline,
        [Parameter(Mandatory)]
        [string[]]$Goals
    )

    $arguments = @('-f', 'backend/pom.xml', '-s', 'backend/local-maven-settings.xml', '-B')
    if ($Offline) {
        $arguments += '-o'
    }
    $arguments + $Goals
}

function Get-ImpactLayerNames {
    @(
        'FullFrontend'
        'FullBackend'
        'BackendUnit'
        'FrontendCoverage'
        'E2E'
        'DirectorySecrets'
        'Oracle'
        'BackendCoverage'
        'E2EOracle'
    )
}

function Get-ImpactOutputName {
    param([Parameter(Mandatory)][string]$Layer)

    switch ($Layer) {
        'FullFrontend' { 'full_frontend' }
        'FullBackend' { 'full_backend' }
        'BackendUnit' { 'backend_unit' }
        'FrontendCoverage' { 'frontend_coverage' }
        'E2E' { 'e2e' }
        'DirectorySecrets' { 'directory_secrets' }
        'Oracle' { 'oracle' }
        'BackendCoverage' { 'backend_coverage' }
        'E2EOracle' { 'e2e_oracle' }
        default { throw "Unknown impact layer: $Layer" }
    }
}

function Get-QualityTimeoutBudgetSeconds {
    param(
        [ValidateSet('Quick', 'PrePush', 'Full', 'Simple', 'Oracle', 'All', 'Impact')]
        [string]$Mode = 'Quick',
        [ValidateSet('None', 'FullFrontend', 'FullBackend', 'FrontendCoverage', 'BackendCoverage', 'BackendUnit', 'E2E', 'E2EOracle', 'DirectorySecrets', 'DependencyAudit')]
        [string]$CiTask = 'None',
        [ValidateSet('Plan', 'FullFrontend', 'FullBackend', 'BackendUnit', 'FrontendCoverage', 'E2E', 'DirectorySecrets', 'Oracle', 'BackendCoverage', 'E2EOracle', 'Aggregate')]
        [string]$ImpactTask = 'Plan'
    )

    $executionType = if ($CiTask -ne 'None') {
        $CiTask
    }
    elseif ($Mode -eq 'Impact') {
        $ImpactTask
    }
    else {
        $Mode
    }

    switch ($executionType) {
        'Quick' { return 180 }
        'PrePush' { return 180 }
        'DirectorySecrets' { return 180 }
        'Plan' { return 180 }
        'Aggregate' { return 180 }
        'Oracle' { return 1800 }
        'BackendCoverage' { return 1800 }
        'E2EOracle' { return 1800 }
        'All' { return 1800 }
        'DependencyAudit' { return 1800 }
        default { return 600 }
    }
}

function Get-QualityTimeoutGuidance {
    param(
        [ValidateSet('Quick', 'PrePush', 'Full', 'Simple', 'Oracle', 'All', 'Impact')]
        [string]$Mode = 'Quick',
        [ValidateSet('None', 'FullFrontend', 'FullBackend', 'FrontendCoverage', 'BackendCoverage', 'BackendUnit', 'E2E', 'E2EOracle', 'DirectorySecrets', 'DependencyAudit')]
        [string]$CiTask = 'None',
        [ValidateSet('Plan', 'FullFrontend', 'FullBackend', 'BackendUnit', 'FrontendCoverage', 'E2E', 'DirectorySecrets', 'Oracle', 'BackendCoverage', 'E2EOracle', 'Aggregate')]
        [string]$ImpactTask = 'Plan'
    )

    $seconds = Get-QualityTimeoutBudgetSeconds -Mode $Mode -CiTask $CiTask -ImpactTask $ImpactTask
    $minutes = [math]::Ceiling($seconds / 60)
    "Quality gate outer timeout guidance: at least ${seconds}s (${minutes}min) for Mode=$Mode, CiTask=$CiTask, ImpactTask=$ImpactTask."
}

function ConvertTo-NormalizedImpactFiles {
    param([AllowEmptyCollection()][string[]]$ChangedFiles = @())

    $normalized = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $ChangedFiles) {
        if ([string]::IsNullOrWhiteSpace($file)) { continue }
        $path = $file.Trim().Replace('\', '/')
        while ($path.StartsWith('./', [System.StringComparison]::Ordinal)) {
            $path = $path.Substring(2)
        }
        if ($path -match '[\r\n]' -or $path -match '(^|/)\.\.(/|$)' -or [System.IO.Path]::IsPathRooted($path)) {
            throw "Changed file is not a safe repository-relative path: $file"
        }
        $null = $normalized.Add($path)
    }
    @($normalized | Sort-Object)
}

function New-FullImpactPlan {
    param(
        [AllowEmptyCollection()][string[]]$ChangedFiles = @(),
        [string]$FallbackReason,
        [string]$FullReason
    )

    $layers = @(Get-ImpactLayerNames)
    $isFallback = -not [string]::IsNullOrWhiteSpace($FallbackReason)
    $reason = if ($isFallback) { $FallbackReason } else { $FullReason }
    $layerReasons = [ordered]@{}
    foreach ($layer in $layers) {
        $layerReasons[$layer] = "Full execution selected: $reason"
    }
    [pscustomobject][ordered]@{
        SchemaVersion = 1
        ExecutionScope = 'Full'
        ChangedFiles = @($ChangedFiles)
        SelectedLayers = $layers
        ExcludedLayers = @()
        FallbackUsed = $isFallback
        FallbackReason = if ($isFallback) { $FallbackReason } else { '' }
        FullReason = if ($isFallback) { '' } else { $FullReason }
        LayerReasons = [pscustomobject]$layerReasons
    }
}

function Get-ImpactPlan {
    param(
        [AllowEmptyCollection()][string[]]$ChangedFiles = @(),
        [string]$ForceFullReason
    )

    try {
        $files = @(ConvertTo-NormalizedImpactFiles -ChangedFiles $ChangedFiles)
    }
    catch {
        return New-FullImpactPlan -FallbackReason "IMPACT_SCOPE_INVALID: $($_.Exception.Message)"
    }

    if (-not [string]::IsNullOrWhiteSpace($ForceFullReason)) {
        return New-FullImpactPlan -ChangedFiles $files -FullReason $ForceFullReason
    }
    if ($files.Count -eq 0) {
        return New-FullImpactPlan -ChangedFiles $files -FallbackReason 'IMPACT_SCOPE_UNAVAILABLE: no changed files were resolved.'
    }

    $fullTriggerPattern = @(
        '^\.github/(workflows|actions)/'
        '^scripts/.*\.ps1$'
        '^lefthook\.yml$'
        '^\.gitleaks\.toml$'
        '^(package(-lock)?\.json|npm-shrinkwrap\.json|pnpm-lock\.yaml|yarn\.lock)$'
        '^frontend/(package(-lock)?\.json|npm-shrinkwrap\.json|pnpm-lock\.yaml|yarn\.lock)$'
        '^backend/(?:[^/]+/)*pom\.xml$'
        '^backend/(?:[^/]+/)*(?:settings(?:[.-][^/]*)?|[^/]*maven[^/]*settings[^/]*)\.xml$'
        '^backend/(mvnw(\.cmd)?|\.mvn/)'
        '^frontend/(?:[^/]+/)*(vite|vitest|playwright|eslint)(?:[.-][^/]*)?\.(?:[cm]?[jt]s|json)$'
        '^frontend/(?:[^/]+/)*tsconfig(?:[.-][^/]*)?\.json$'
        '^backend/scripts/'
        '^backend/config/'
        '^backend/src/(main|test)/resources/application(?:[.-][^/]*)?\.(yml|yaml|properties)$'
        '(^|/)[^/]*(coverage|jacoco)[^/]*\.(?:[cm]?[jt]s|ps1|xml|ya?ml|json|properties)$'
    ) -join '|'
    $documentationPattern = '^(docs/|\.agents/|\.superpowers/|AGENTS\.md$|README(?:\.[^/]+)?$)|\.md$'
    $frontendPattern = '^frontend/'
    $backendPattern = '^backend/'
    $apiControllerPattern = '^backend/src/main/(java|kotlin)/.+Controller\.(java|kt)$'
    $authSecurityPattern = @(
        '(^|/)(auth|security|csrf)(/|\.|$)'
        '(^|/)[^/]*(Security|Authentication|Authorization|Csrf)[^/]*\.(java|kt|ts|tsx)$'
        '(^|/)apiClient\.(ts|tsx)$'
    ) -join '|'
    $businessStatePattern = @(
        '(^|/)(logic|rules?|workflow|state|transition)(/|\.|$)'
        '(^|/)[^/]*(Service|Rules?|Policy|Workflow|State|Status|Transition)\.(java|kt)$'
    ) -join '|'
    $databasePattern = @(
        '(^|/)(db|sql|ddl|migration|migrations|schema|master)(/|\.|-|$)'
        '\.(sql|ddl)$'
        '(^|/)[^/]*(Repository|Entity)\.(java|kt)$'
        '(^|/)[^/]*(DataInitializer|Seeder)\.(java|kt)$'
    ) -join '|'
    $commonContractPattern = @(
        '(^|/)(shared|common|exception|error|support|fixtures?)(/|\.|$)'
        '(^|/)[^/]*(Exception|Error|Handler)\.(java|kt|ts|tsx)$'
    ) -join '|'

    foreach ($file in $files) {
        if ($file -match $fullTriggerPattern) {
            return New-FullImpactPlan -ChangedFiles $files `
                -FallbackReason "IMPACT_SELECTOR_OR_GATE_CHANGED: $file"
        }
        if ($file -match $authSecurityPattern) {
            return New-FullImpactPlan -ChangedFiles $files `
                -FallbackReason "IMPACT_SCOPE_UNBOUNDED_AUTH_SECURITY: $file"
        }
        if ($file -match $businessStatePattern) {
            return New-FullImpactPlan -ChangedFiles $files `
                -FallbackReason "IMPACT_SCOPE_UNBOUNDED_BUSINESS_STATE: $file"
        }
        if ($file -match $databasePattern) {
            return New-FullImpactPlan -ChangedFiles $files `
                -FallbackReason "IMPACT_SCOPE_UNBOUNDED_DATABASE: $file"
        }
        if ($file -match $commonContractPattern) {
            return New-FullImpactPlan -ChangedFiles $files `
                -FallbackReason "IMPACT_SCOPE_UNBOUNDED_COMMON_CONTRACT: $file"
        }
    }

    $selected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $layerReasons = [ordered]@{}
    $null = $selected.Add('DirectorySecrets')
    $layerReasons.DirectorySecrets = 'Repository directory secret scanning is mandatory for every impact plan.'

    foreach ($file in $files) {
        if ($file -match $documentationPattern) { continue }

        if ($file -match $frontendPattern) {
            foreach ($layer in @('FullFrontend', 'FrontendCoverage', 'E2E')) {
                $null = $selected.Add($layer)
                $layerReasons[$layer] = "Frontend change and direct consumers: $file"
            }
            continue
        }

        if ($file -match $backendPattern) {
            $backendLayers = if ($file -match $apiControllerPattern) {
                @('FullFrontend', 'FullBackend', 'BackendUnit', 'E2E', 'Oracle', 'BackendCoverage', 'E2EOracle')
            }
            else {
                @('FullBackend', 'BackendUnit', 'E2E', 'BackendCoverage')
            }
            foreach ($layer in $backendLayers) {
                $null = $selected.Add($layer)
                $layerReasons[$layer] = if ($file -match $apiControllerPattern) {
                    "Bounded API Controller change selects backend, frontend consumers, changed coverage, E2E, and Oracle contracts: $file"
                }
                else {
                    "Bounded backend change selects backend checks, changed coverage, and direct E2E consumers: $file"
                }
            }
            continue
        }

        return New-FullImpactPlan -ChangedFiles $files -FallbackReason "IMPACT_SCOPE_UNKNOWN: $file"
    }

    $allLayers = @(Get-ImpactLayerNames)
    $selectedLayers = @($allLayers | Where-Object { $selected.Contains($_) })
    $excludedLayers = @($allLayers | Where-Object { -not $selected.Contains($_) })
    foreach ($layer in $excludedLayers) {
        $layerReasons[$layer] = 'Excluded because no changed file or direct consumer requires this layer.'
    }
    [pscustomobject][ordered]@{
        SchemaVersion = 1
        ExecutionScope = 'Impact'
        ChangedFiles = $files
        SelectedLayers = $selectedLayers
        ExcludedLayers = $excludedLayers
        FallbackUsed = $false
        FallbackReason = ''
        FullReason = ''
        LayerReasons = [pscustomobject]$layerReasons
    }
}

function Get-ImpactChangedFiles {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$ChangedFilesPath,
        [string]$BaseRef,
        [string]$HeadRef
    )

    $hasFile = -not [string]::IsNullOrWhiteSpace($ChangedFilesPath)
    $hasBase = -not [string]::IsNullOrWhiteSpace($BaseRef)
    $hasHead = -not [string]::IsNullOrWhiteSpace($HeadRef)
    if ($hasFile -and ($hasBase -or $hasHead)) {
        throw 'Use either ChangedFilesPath or BaseRef/HeadRef, not both.'
    }
    if ($hasFile) {
        if (-not (Test-Path -LiteralPath $ChangedFilesPath -PathType Leaf)) {
            throw "Changed-files input does not exist: $ChangedFilesPath"
        }
        return ConvertTo-NormalizedImpactFiles -ChangedFiles @(
            Get-Content -Encoding UTF8 -LiteralPath $ChangedFilesPath
        )
    }
    if ($hasBase -xor $hasHead) {
        throw 'BaseRef and HeadRef must be supplied together.'
    }
    if (-not $hasBase) {
        throw 'Impact scope requires ChangedFilesPath or BaseRef/HeadRef.'
    }
    if ($BaseRef -match '^0{40}$' -or $HeadRef -match '^0{40}$') {
        throw 'Push diff contains an unavailable zero SHA.'
    }
    foreach ($ref in @($BaseRef, $HeadRef)) {
        $null = git -C $RepoRoot rev-parse --verify --quiet "$ref^{commit}"
        if ($LASTEXITCODE -ne 0) { throw "Git commit is unavailable for impact scope: $ref" }
    }
    $files = @(git -c core.quotePath=false -C $RepoRoot diff --name-only --diff-filter=ACMRD $BaseRef $HeadRef)
    if ($LASTEXITCODE -ne 0) { throw "Unable to resolve impact diff between $BaseRef and $HeadRef." }
    ConvertTo-NormalizedImpactFiles -ChangedFiles $files
}

function Write-ImpactJson {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

function Get-ImpactLayerReason {
    param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)][string]$Layer)

    $property = $Plan.LayerReasons.PSObject.Properties[$Layer]
    if ($null -ne $property) { return [string]$property.Value }
    'No layer reason was recorded.'
}

function Assert-ImpactPlan {
    param([Parameter(Mandatory)]$Plan)

    $allLayers = @(Get-ImpactLayerNames)
    $selected = @($Plan.SelectedLayers)
    $excluded = @($Plan.ExcludedLayers)
    $combined = @($selected + $excluded | Sort-Object -Unique)
    if ((@($combined) -join ',') -ne (@($allLayers | Sort-Object -Unique) -join ',')) {
        throw 'Impact plan must partition every known layer into selected or excluded scope.'
    }
    if (@($selected | Where-Object { $excluded -contains $_ }).Count -gt 0) {
        throw 'Impact plan selected and excluded scopes overlap.'
    }
    if ($selected.Count -eq 0) { throw 'Impact plan cannot contain only excluded layers.' }
    $layerReasonsProperty = $Plan.PSObject.Properties['LayerReasons']
    foreach ($layer in $allLayers) {
        $reasonProperty = if ($null -ne $layerReasonsProperty -and $null -ne $layerReasonsProperty.Value) {
            $layerReasonsProperty.Value.PSObject.Properties[$layer]
        }
        else {
            $null
        }
        $reason = if ($null -ne $reasonProperty) { [string]$reasonProperty.Value } else { '' }
        if ([string]::IsNullOrWhiteSpace($reason)) {
            throw "Impact plan layer reason is missing or blank: $layer."
        }
        if ([string]::Equals(
                $reason.Trim(),
                'No layer reason was recorded.',
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            throw "Impact plan layer reason cannot use the generic placeholder: $layer."
        }
    }
    if ($Plan.FallbackUsed -and [string]::IsNullOrWhiteSpace([string]$Plan.FallbackReason)) {
        throw 'Impact fallback requires a reason.'
    }
}

function Write-ImpactPlanOutputs {
    param([Parameter(Mandatory)]$Plan)

    Assert-ImpactPlan -Plan $Plan
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
        foreach ($layer in (Get-ImpactLayerNames)) {
            $selected = if (@($Plan.SelectedLayers) -contains $layer) { 'true' } else { 'false' }
            "$(Get-ImpactOutputName -Layer $layer)=$selected" | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8NoBOM
        }
        "fallback=$($Plan.FallbackUsed.ToString().ToLowerInvariant())" | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8NoBOM
        "execution_scope=$($Plan.ExecutionScope)" | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8NoBOM
    }
}

function Write-ImpactSummary {
    param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Lines)

    $Lines | ForEach-Object { Write-Host $_ }
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
        $Lines | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8NoBOM
    }
}

function Write-ImpactPlanSummary {
    param([Parameter(Mandatory)]$Plan)

    $fallback = if ($Plan.FallbackUsed) { "yes — $($Plan.FallbackReason)" } else { 'no' }
    $fullReason = if ([string]::IsNullOrWhiteSpace([string]$Plan.FullReason)) { 'N/A' } else { [string]$Plan.FullReason }
    Write-ImpactSummary -Lines @(
        '## Impact test plan'
        ''
        "- Execution scope: $($Plan.ExecutionScope)"
        "- Selected layers: $(@($Plan.SelectedLayers) -join ', ')"
        "- Excluded layers: $(@($Plan.ExcludedLayers) -join ', ')"
        "- Fallback: $fallback"
        "- Intentional full reason: $fullReason"
        "- Changed files: $(@($Plan.ChangedFiles).Count)"
    )
}

function Get-FullFrontendCheckDefinitions {
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,
        [Parameter(Mandatory)]
        [string]$NpmCommand
    )

    @(
        New-CheckDefinition -Name 'frontend-lint' -Command $NpmCommand -Arguments @('--prefix', 'frontend', 'run', 'lint')
        New-CheckDefinition -Name 'frontend-typecheck' -Command $NpmCommand -Arguments @('--prefix', 'frontend', 'run', 'typecheck')
        New-CheckDefinition -Name 'frontend-unit-test' -Command $NpmCommand -Arguments @('--prefix', 'frontend', 'test')
        New-CheckDefinition -Name 'frontend-build' -Command $NpmCommand -Arguments @('--prefix', 'frontend', 'run', 'build:ci')
    )
}

function Get-FullBackendCheckDefinitions {
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,
        [Parameter(Mandatory)]
        [string]$MavenCommand,
        [switch]$Offline
    )

    @(
        # How: Mavenを1回だけ起動し、test-compile後に静的解析ゴールを同じプロセスで実行する。
        # Why not: 個別起動するとMaven・POM・プラグイン初期化とtest-compileが重複するため。
        New-CheckDefinition -Name 'backend-quality' -Command $MavenCommand -Arguments (Get-MavenArguments -Offline:$Offline -Goals @(
                'test-compile', 'spotless:check', 'checkstyle:check', 'spotbugs:check', 'pmd:check'
            ))
    )
}

function Get-FullContractCheckDefinitions {
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    @(
        New-CheckDefinition -Name 'oracle-preflight-contract-test' -Command 'pwsh' -Arguments @(
            '-NoProfile', '-File', (Join-Path $RepoRoot 'scripts/oracle-preflight.tests.ps1')
        )
        New-CheckDefinition -Name 'coverage-summary-contract-test' -Command 'pwsh' -Arguments @(
            '-NoProfile', '-File', (Join-Path $RepoRoot 'scripts/coverage-summary.tests.ps1')
        )
        New-CheckDefinition -Name 'coverage-gate-contract-test' -Command 'pwsh' -Arguments @(
            '-NoProfile', '-File', (Join-Path $RepoRoot 'scripts/coverage-gate.tests.ps1')
        )
        New-CheckDefinition -Name 'impact-runner-contract-test' -Command 'pwsh' -Arguments @(
            '-NoProfile', '-File', (Join-Path $RepoRoot 'scripts/impact-runner.tests.ps1')
        )
        New-CheckDefinition -Name 'impact-workflow-contract-test' -Command 'pwsh' -Arguments @(
            '-NoProfile', '-File', (Join-Path $RepoRoot 'scripts/impact-workflow.tests.ps1')
        )
        New-CheckDefinition -Name 'pmd-contract-test' -Command 'pwsh' -Arguments @(
            '-NoProfile', '-File', (Join-Path $RepoRoot 'scripts/pmd.tests.ps1')
        )
        New-CheckDefinition -Name 'quality-timeout-contract-test' -Command 'pwsh' -Arguments @(
            '-NoProfile', '-File', (Join-Path $RepoRoot 'scripts/quality-timeout.tests.ps1')
        )
    )
}

function Get-FullCheckDefinitions {
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,
        [Parameter(Mandatory)]
        [string]$NpmCommand,
        [Parameter(Mandatory)]
        [string]$MavenCommand,
        [switch]$Offline
    )

    @(
        Get-FullFrontendCheckDefinitions -RepoRoot $RepoRoot -NpmCommand $NpmCommand
        Get-FullBackendCheckDefinitions -RepoRoot $RepoRoot -MavenCommand $MavenCommand -Offline:$Offline
        Get-FullContractCheckDefinitions -RepoRoot $RepoRoot
    )
}

function Get-QuickCheckDefinitions {
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,
        [string[]]$StagedFiles = @(),
        [Parameter(Mandatory)]
        [string]$NpmCommand,
        [Parameter(Mandatory)]
        [string]$GitleaksCommand,
        [string]$MavenCommand,
        [switch]$Offline
    )

    $frontendFiles = @($StagedFiles | Where-Object { $_ -match '^frontend/.+\.(ts|tsx)$' })
    $frontendLintFiles = $frontendFiles
    $markdownFiles = @($StagedFiles | Where-Object { $_ -match '\.md$' })
    $hasJavaChanges = @($StagedFiles | Where-Object { $_ -match '^backend/.+\.java$' }).Count -gt 0
    $forbiddenPattern = '(^|/)(node_modules|target|dist|coverage|playwright-report|test-results)(/|$)|(^|/)\.tools(/|$)|\.log$'

    $definitions = [System.Collections.Generic.List[object]]::new()
    $definitions.Add((New-CheckDefinition -Name 'staged-whitespace' -Command 'git' -Arguments @('-C', $RepoRoot, 'diff', '--cached', '--check')))
    $definitions.Add((New-CheckDefinition -Name 'staged-artifacts' -Action {
        $forbidden = @($StagedFiles | Where-Object { $_ -match $forbiddenPattern })
        if ($forbidden.Count -gt 0) {
            throw "Generated or local-only files are staged: $($forbidden -join ', ')"
        }
    }.GetNewClosure()))

    if ($frontendLintFiles.Count -gt 0) {
        $definitions.Add((New-CheckDefinition -Name 'frontend-staged-lint' -Command $NpmCommand -Arguments (@(
            '--prefix', 'frontend', 'exec', '--', 'eslint'
        ) + $frontendLintFiles + @('--max-warnings', '0'))))
    }
    if ($markdownFiles.Count -gt 0) {
        $definitions.Add((New-CheckDefinition -Name 'markdown-staged-lint' -Command $NpmCommand -Arguments (@(
            'run', 'lint:markdown', '--', '--no-globs'
        ) + $markdownFiles)))
    }
    if ($hasJavaChanges) {
        $definitions.Add((New-CheckDefinition -Name 'backend-staged-spotless' -Command $MavenCommand -Arguments (
            Get-MavenArguments -Offline:$Offline -Goals @('spotless:check')
        )))
    }

    $definitions.Add((New-CheckDefinition -Name 'staged-secrets' -Command $GitleaksCommand -Arguments @(
        'git', '--pre-commit', '--staged', '--redact', '--verbose', '--config', (Join-Path $RepoRoot '.gitleaks.toml')
    )))
    $definitions
}

function Get-WorkingTreeChangedFiles {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $tracked = @(git -c core.quotePath=false -C $RepoRoot diff --name-only HEAD)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to read tracked working-tree changes.'
    }

    $untracked = @(git -c core.quotePath=false -C $RepoRoot ls-files --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to read untracked working-tree files.'
    }

    @($tracked + $untracked |
        ForEach-Object { $_.Replace('\', '/') } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique)
}

function New-SimpleFocusedUnitCheckDefinition {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][ValidateSet('Frontend', 'Backend', 'Harness')][string]$Layer,
        [string]$Target,
        [string]$NotApplicableReason,
        [Parameter(Mandatory)][string]$NpmCommand,
        [Parameter(Mandatory)][string]$MavenCommand,
        [switch]$Offline
    )

    $hasTarget = -not [string]::IsNullOrWhiteSpace($Target)
    $hasReason = -not [string]::IsNullOrWhiteSpace($NotApplicableReason)
    if ($hasTarget -eq $hasReason) {
        throw 'Simple Mode requires exactly one of FocusedUnitTarget or FocusedUnitNotApplicableReason.'
    }

    if ($hasReason) {
        return New-CheckDefinition -Name 'simple-focused-unit-na' -Action {
            Write-Host "N/A: $NotApplicableReason"
        }.GetNewClosure()
    }

    switch ($Layer) {
        'Frontend' {
            if ($Target -notmatch '^test/[A-Za-z0-9._/-]+\.(test|spec)\.(ts|tsx)$') {
                throw 'Frontend FocusedUnitTarget must be a test/*.test.ts, test/*.test.tsx, test/*.spec.ts, or test/*.spec.tsx path.'
            }
            New-CheckDefinition -Name 'simple-focused-unit' -Command $NpmCommand -Arguments @(
                '--prefix', 'frontend', 'test', '--', $Target
            )
        }
        'Backend' {
            if ($Target -notmatch '^[A-Za-z0-9_]+(?:#[A-Za-z0-9_*]+)?$') {
                throw 'Backend FocusedUnitTarget must be a test class or class#method name.'
            }
            New-CheckDefinition -Name 'simple-focused-unit' -Command $MavenCommand -Arguments (
                Get-MavenArguments -Offline:$Offline -Goals @("-Dtest=$Target", 'test')
            )
        }
        'Harness' {
            $normalizedTarget = $Target.Replace('\', '/')
            if ($normalizedTarget -notmatch '^scripts/[A-Za-z0-9._/-]+\.tests\.ps1$') {
                throw 'Harness FocusedUnitTarget must be a scripts/*.tests.ps1 path.'
            }
            $targetPath = Join-Path $RepoRoot $normalizedTarget
            if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
                throw "Harness FocusedUnitTarget does not exist: $normalizedTarget"
            }
            New-CheckDefinition -Name 'simple-focused-unit' -Command 'pwsh' -Arguments @(
                '-NoProfile', '-File', $targetPath
            )
        }
    }
}

function New-SimpleBrowserCheckDefinition {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$NpmCommand,
        [string]$BrowserCase,
        [string]$BrowserManualReason
    )

    $hasCase = -not [string]::IsNullOrWhiteSpace($BrowserCase)
    $hasReason = -not [string]::IsNullOrWhiteSpace($BrowserManualReason)
    if ($hasCase -eq $hasReason) {
        throw 'DisplayRequirement requires exactly one of BrowserCase or BrowserManualReason.'
    }

    if ($hasCase) {
        # How: Playwrightの設定とtestDirをFrontendプロジェクト基準で解決する。
        # Why not: npmの--prefixは依存解決先を変えるだけで、Playwrightの設定探索用カレントディレクトリを変えないため。
        return New-CheckDefinition -Name 'simple-frontend-browser' -Command $NpmCommand -Arguments @(
            '--prefix', 'frontend', 'exec', '--', 'playwright', 'test', '--grep', $BrowserCase
        ) -WorkingDirectory (Join-Path $RepoRoot 'frontend')
    }

    New-CheckDefinition -Name 'simple-browser-manual' -Action {
        throw "BROWSER_UNVERIFIED: $BrowserManualReason"
    }.GetNewClosure()
}

function Get-SimpleCheckDefinitions {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][ValidateSet('Docs', 'Frontend', 'Backend', 'Harness', 'Mixed')][string]$Scope,
        [string]$FocusedUnitScope,
        [string]$FocusedUnitTarget,
        [string]$FocusedUnitNotApplicableReason,
        [switch]$DisplayRequirement,
        [string]$BrowserCase,
        [string]$BrowserManualReason,
        [string[]]$ChangedFiles = @(),
        [string]$NpmCommand = 'npm.cmd',
        [string]$MavenCommand = 'backend/mvnw.cmd',
        [switch]$Offline
    )

    $hasBrowserCase = -not [string]::IsNullOrWhiteSpace($BrowserCase)
    $hasBrowserReason = -not [string]::IsNullOrWhiteSpace($BrowserManualReason)
    if (-not [string]::IsNullOrWhiteSpace($FocusedUnitScope) -and $FocusedUnitScope -notin @('Frontend', 'Backend', 'Harness')) {
        throw 'FocusedUnitScope must be Frontend, Backend, or Harness.'
    }
    if ($hasBrowserCase -and $hasBrowserReason) {
        throw 'BrowserCase and BrowserManualReason cannot be used together.'
    }
    if ($DisplayRequirement -and -not ($hasBrowserCase -xor $hasBrowserReason)) {
        throw 'DisplayRequirement requires BrowserCase or BrowserManualReason.'
    }
    if (-not $DisplayRequirement -and ($hasBrowserCase -or $hasBrowserReason)) {
        throw 'BrowserCase or BrowserManualReason requires DisplayRequirement.'
    }
    if ($DisplayRequirement -and $Scope -notin @('Frontend', 'Mixed')) {
        throw 'DisplayRequirement requires Frontend or Mixed Scope.'
    }

    $focusedScope = $FocusedUnitScope
    if ($Scope -eq 'Mixed' -and [string]::IsNullOrWhiteSpace($focusedScope)) {
        throw 'Mixed Scope requires FocusedUnitScope.'
    }
    if ($Scope -in @('Frontend', 'Backend', 'Harness') -and [string]::IsNullOrWhiteSpace($focusedScope)) {
        $focusedScope = $Scope
    }

    $normalizedFiles = @($ChangedFiles |
        ForEach-Object { $_.Replace('\', '/') } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique)
    $definitions = [System.Collections.Generic.List[object]]::new()

    $qualityReportFiles = @($normalizedFiles | Where-Object {
            $_ -like 'docs/AI活用開発研究/コード品質確認画面/*'
        })

    if ($Scope -eq 'Docs') {
        if (-not [string]::IsNullOrWhiteSpace($FocusedUnitTarget)) {
            throw 'Docs Scope does not accept a FocusedUnitTarget.'
        }
        if ([string]::IsNullOrWhiteSpace($FocusedUnitNotApplicableReason)) {
            throw 'Docs Scope requires FocusedUnitNotApplicableReason.'
        }
        $definitions.Add((New-CheckDefinition -Name 'simple-focused-unit-na' -Action {
                    Write-Host "N/A: $FocusedUnitNotApplicableReason"
                }.GetNewClosure()))
    }
    else {
        $definitions.Add((New-SimpleFocusedUnitCheckDefinition -RepoRoot $RepoRoot -Layer $focusedScope `
                -Target $FocusedUnitTarget -NotApplicableReason $FocusedUnitNotApplicableReason `
                -NpmCommand $NpmCommand -MavenCommand $MavenCommand -Offline:$Offline))
    }

    if ($Scope -in @('Frontend', 'Mixed')) {
        $definitions.Add((New-CheckDefinition -Name 'simple-frontend-lint' -Command $NpmCommand -Arguments @(
                    '--prefix', 'frontend', 'run', 'lint'
                )))
        $definitions.Add((New-CheckDefinition -Name 'simple-frontend-typecheck' -Command $NpmCommand -Arguments @(
                    '--prefix', 'frontend', 'run', 'typecheck'
                )))
        $definitions.Add((New-CheckDefinition -Name 'simple-frontend-build' -Command $NpmCommand -Arguments @(
                    '--prefix', 'frontend', 'run', 'build:ci'
                )))
    }

    if ($Scope -in @('Backend', 'Mixed')) {
        $definitions.Add((New-CheckDefinition -Name 'simple-backend-spotless' -Command $MavenCommand -Arguments (
                    Get-MavenArguments -Offline:$Offline -Goals @('spotless:check')
                )))
        $definitions.Add((New-CheckDefinition -Name 'simple-backend-checkstyle' -Command $MavenCommand -Arguments (
                    Get-MavenArguments -Offline:$Offline -Goals @('checkstyle:check')
                )))
        $definitions.Add((New-CheckDefinition -Name 'simple-backend-test-compile' -Command $MavenCommand -Arguments (
                    Get-MavenArguments -Offline:$Offline -Goals @('test-compile')
                )))
        $definitions.Add((New-CheckDefinition -Name 'simple-backend-pmd' -Command $MavenCommand -Arguments (
                    Get-MavenArguments -Offline:$Offline -Goals @('pmd:check')
                )))
    }

    $markdownFiles = @($normalizedFiles | Where-Object { $_ -match '\.md$' })
    if ($Scope -eq 'Docs') {
        if ($markdownFiles.Count -eq 0 -and $qualityReportFiles.Count -eq 0) {
            throw 'Docs Scope requires at least one changed Markdown file.'
        }
        if ($markdownFiles.Count -gt 0) {
            $definitions.Add((New-CheckDefinition -Name 'simple-docs-markdown-lint' -Command $NpmCommand -Arguments (@(
                        'run', 'lint:markdown', '--', '--no-globs'
                    ) + $markdownFiles)))
        }
        if ($qualityReportFiles.Count -gt 0) {
            $qualityReportRunner = Join-Path $RepoRoot 'scripts/check-quality-reports.ps1'
            $definitions.Add((New-CheckDefinition -Name 'simple-quality-report' -Command 'pwsh' -Arguments @(
                        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $qualityReportRunner, '-ValidateOnly'
                    ) -WorkingDirectory $RepoRoot))
        }
    }
    elseif ($Scope -eq 'Harness' -and $markdownFiles.Count -gt 0) {
        $definitions.Add((New-CheckDefinition -Name 'simple-harness-markdown-lint' -Command $NpmCommand -Arguments (@(
                    'run', 'lint:markdown', '--', '--no-globs'
                ) + $markdownFiles)))
    }

    if ($DisplayRequirement) {
        $definitions.Add((New-SimpleBrowserCheckDefinition -RepoRoot $RepoRoot -NpmCommand $NpmCommand `
                -BrowserCase $BrowserCase -BrowserManualReason $BrowserManualReason))
    }

    $definitions
}

function Get-PushRefRecords {
    param([Parameter(Mandatory)][string]$InputText)

    $zeroSha = '0000000000000000000000000000000000000000'
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($line in ($InputText -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $columns = @($line.Trim() -split '\s+')
        if ($columns.Count -ne 4) {
            throw "Invalid pre-push input line: $line"
        }

        foreach ($sha in @($columns[1], $columns[3])) {
            if ($sha -notmatch '(?i)^[0-9a-f]{40}$') {
                throw "Invalid pre-push sha: $sha"
            }
        }

        $records.Add([pscustomobject]@{
                LocalRef  = $columns[0]
                LocalSha  = $columns[1]
                RemoteRef = $columns[2]
                RemoteSha = $columns[3]
            })
    }

    if ($records.Count -eq 0) {
        throw 'Pre-push input did not contain any ref update.'
    }

    $records
}

function Get-PrePushUnsharedCommits {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$LocalSha
    )

    $commits = @(git -C $RepoRoot rev-list --reverse $LocalSha --not --remotes)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to enumerate unshared commits for $LocalSha."
    }
    if ($commits.Count -eq 0) {
        return @($LocalSha)
    }
    $commits
}

function Get-PrePushChangedFiles {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][object[]]$PushRefs
    )

    $zeroSha = '0000000000000000000000000000000000000000'
    $changedFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($pushRef in $PushRefs) {
        if ($pushRef.LocalSha -eq $zeroSha) {
            continue
        }

        $null = git -C $RepoRoot cat-file -e "$($pushRef.LocalSha)^{commit}" 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Local pre-push commit is not available: $($pushRef.LocalSha)"
        }

        if ($pushRef.RemoteSha -ne $zeroSha) {
            $null = git -C $RepoRoot cat-file -e "$($pushRef.RemoteSha)^{commit}" 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "Remote pre-push commit is not available locally: $($pushRef.RemoteSha)"
            }
            $files = @(git -C $RepoRoot diff --name-only --diff-filter=ACMR $pushRef.RemoteSha $pushRef.LocalSha)
            if ($LASTEXITCODE -ne 0) {
                throw "Unable to resolve changed files between $($pushRef.RemoteSha) and $($pushRef.LocalSha)."
            }
        }
        else {
            $files = [System.Collections.Generic.List[string]]::new()
            foreach ($commit in (Get-PrePushUnsharedCommits -RepoRoot $RepoRoot -LocalSha $pushRef.LocalSha)) {
                $commitFiles = @(git -C $RepoRoot diff-tree --root --no-commit-id --name-only --diff-filter=ACMR -r $commit)
                if ($LASTEXITCODE -ne 0) {
                    throw "Unable to resolve changed files for commit $commit."
                }
                $commitFiles | ForEach-Object { $files.Add($_) }
            }
        }

        foreach ($file in $files) {
            if (-not [string]::IsNullOrWhiteSpace($file)) {
                $normalized = $file.Replace('\', '/')
                $null = $changedFiles.Add($normalized)
            }
        }
    }

    @($changedFiles | Sort-Object)
}

function Invoke-PrePushDiffCheck {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][object[]]$PushRefs
    )

    $zeroSha = '0000000000000000000000000000000000000000'
    foreach ($pushRef in $PushRefs) {
        if ($pushRef.LocalSha -eq $zeroSha) {
            continue
        }

        if ($pushRef.RemoteSha -ne $zeroSha) {
            $output = @(git -C $RepoRoot diff --check $pushRef.RemoteSha $pushRef.LocalSha 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "Whitespace errors found between $($pushRef.RemoteSha) and $($pushRef.LocalSha): $($output -join ' ')"
            }
            continue
        }

        foreach ($commit in (Get-PrePushUnsharedCommits -RepoRoot $RepoRoot -LocalSha $pushRef.LocalSha)) {
            $output = @(git -C $RepoRoot diff-tree --check --root --no-commit-id -r $commit 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "Whitespace errors found in commit ${commit}: $($output -join ' ')"
            }
        }
    }
}

function Get-PrePushCheckDefinitions {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string[]]$ChangedFiles = @(),
        [object[]]$PushRefs = @(),
        [Parameter(Mandatory)][string]$NpmCommand,
        [Parameter(Mandatory)][string]$MavenCommand,
        [Parameter(Mandatory)][string]$GitleaksCommand,
        [switch]$Offline
    )

    $normalizedFiles = @($ChangedFiles | ForEach-Object { $_.Replace('\', '/') } | Sort-Object -Unique)
    $frontendCodeFiles = @($normalizedFiles | Where-Object { $_ -match '^frontend/.+\.(ts|tsx)$' })
    $frontendConfigChanged = @($normalizedFiles | Where-Object {
            $_ -match '^frontend/(package(-lock)?\.json|vite\.config\..+|tsconfig.*\.json|eslint\.config\..+)$'
        }).Count -gt 0
    $markdownFiles = @($normalizedFiles | Where-Object { $_ -match '\.md$' })
    $hasJavaChanges = @($normalizedFiles | Where-Object { $_ -match '^backend/.+\.java$' }).Count -gt 0
    $forbiddenPattern = '(^|/)(node_modules|target|dist|coverage|playwright-report|test-results)(/|$)|(^|/)\.tools(/|$)|\.log$'

    $definitions = [System.Collections.Generic.List[object]]::new()
    $definitions.Add((New-CheckDefinition -Name 'pre-push-diff-check' -Action {
                Invoke-PrePushDiffCheck -RepoRoot $RepoRoot -PushRefs $PushRefs
            }.GetNewClosure()))
    $definitions.Add((New-CheckDefinition -Name 'pre-push-artifact-check' -Action {
                $forbidden = @($normalizedFiles | Where-Object { $_ -match $forbiddenPattern })
                if ($forbidden.Count -gt 0) {
                    throw "Generated or local-only files are part of the push: $($forbidden -join ', ')"
                }
            }.GetNewClosure()))
    $definitions.Add((New-CheckDefinition -Name 'pre-push-secrets' -Command $GitleaksCommand -Arguments @(
            'dir', '--redact', '--config', (Join-Path $RepoRoot '.gitleaks.toml'), '.'
        )))

    if ($frontendConfigChanged) {
        $definitions.Add((New-CheckDefinition -Name 'frontend-pre-push-lint' -Command $NpmCommand -Arguments @(
                '--prefix', 'frontend', 'run', 'lint'
            )))
    }
    elseif ($frontendCodeFiles.Count -gt 0) {
        $definitions.Add((New-CheckDefinition -Name 'frontend-pre-push-lint' -Command $NpmCommand -Arguments (@(
                    '--prefix', 'frontend', 'exec', '--', 'eslint'
                ) + $frontendCodeFiles + @('--max-warnings', '0'))))
    }

    if ($markdownFiles.Count -gt 0) {
        $definitions.Add((New-CheckDefinition -Name 'markdown-pre-push-lint' -Command $NpmCommand -Arguments (@(
                    'run', 'lint:markdown', '--', '--no-globs'
                ) + $markdownFiles)))
    }
    if ($hasJavaChanges) {
        $definitions.Add((New-CheckDefinition -Name 'backend-pre-push-spotless' -Command $MavenCommand -Arguments (
                Get-MavenArguments -Offline:$Offline -Goals @('spotless:check')
            )))
    }

    $definitions
}

function Get-PrePushInputText {
    param([string]$ProvidedInput)

    if (-not [string]::IsNullOrWhiteSpace($ProvidedInput)) {
        return $ProvidedInput
    }
    if (-not [Console]::IsInputRedirected) {
        throw 'PrePush requires ref input on stdin.'
    }
    $inputText = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($inputText)) {
        throw 'PrePush stdin was empty.'
    }
    $inputText
}

function Get-CiTaskDefinitions {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FullFrontend', 'FullBackend', 'FrontendCoverage', 'BackendCoverage', 'BackendUnit', 'E2E', 'E2EOracle', 'DirectorySecrets', 'DependencyAudit')]
        [string]$CiTask,
        [Parameter(Mandatory)]
        [string]$RepoRoot,
        [Parameter(Mandatory)]
        [string]$NpmCommand,
        [Parameter(Mandatory)]
        [string]$MavenCommand,
        [Parameter(Mandatory)]
        [string]$OracleScript,
        [string]$OracleConfigPath,
        [string]$GitleaksCommand = 'gitleaks',
        [switch]$Offline
    )

    switch ($CiTask) {
        'FullFrontend' {
            Get-FullFrontendCheckDefinitions -RepoRoot $RepoRoot -NpmCommand $NpmCommand
        }
        'FullBackend' {
            @(
                Get-FullBackendCheckDefinitions -RepoRoot $RepoRoot -MavenCommand $MavenCommand -Offline:$Offline
                Get-FullContractCheckDefinitions -RepoRoot $RepoRoot
            )
        }
        'FrontendCoverage' {
            @(
                New-CheckDefinition -Name 'frontend-coverage' -Command $NpmCommand -Arguments @('--prefix', 'frontend', 'run', 'coverage')
                New-CoverageReportCheckDefinition -Name 'frontend-coverage-report' -Paths @(
                    (Join-Path $RepoRoot 'frontend/coverage/index.html')
                    (Join-Path $RepoRoot 'frontend/coverage/coverage-summary.json')
                    (Join-Path $RepoRoot 'frontend/coverage/lcov.info')
                )
            )
        }
        'BackendCoverage' {
            $arguments = @('-NoProfile', '-File', $OracleScript)
            if (-not [string]::IsNullOrWhiteSpace($OracleConfigPath)) {
                $arguments += @('-ConfigPath', $OracleConfigPath)
            }
            $arguments += @('-Pcoverage', 'verify')
            @(
                New-CheckDefinition -Name 'backend-coverage' -Command 'pwsh' -Arguments $arguments
                New-CoverageReportCheckDefinition -Name 'backend-coverage-report' -FailureCode 'JACOCO_REPORT_MISSING' `
                    -DependsOn @('backend-coverage') -Paths @(
                    (Join-Path $RepoRoot 'backend/target/jacoco.exec')
                    (Join-Path $RepoRoot 'backend/target/site/jacoco/index.html')
                    (Join-Path $RepoRoot 'backend/target/site/jacoco/jacoco.xml')
                    (Join-Path $RepoRoot 'backend/target/site/jacoco/jacoco.csv')
                )
            )
        }
        'BackendUnit' {
            New-CheckDefinition -Name 'backend-unit-test' -Command $MavenCommand -Arguments (Get-MavenArguments -Offline:$Offline -Goals @(
                '-Dtest=ApiExceptionHandlerTest,BusinessEventLoggingTest,MasterDataRepositoryTest,RequestIdFilterTest,RequestMetadataInterceptorTest,TimeRulesTest'
                'test'
            ))
        }
        'E2E' {
            @(
                New-CheckDefinition -Name 'frontend-e2e-typecheck' -Command $NpmCommand -Arguments @('--prefix', 'frontend', 'run', 'typecheck:e2e')
                New-CheckDefinition -Name 'frontend-e2e' -Command $NpmCommand -Arguments @('--prefix', 'frontend', 'run', 'e2e:run')
            )
        }
        'E2EOracle' {
            $arguments = @('-NoProfile', '-File', (Join-Path $RepoRoot 'backend/scripts/test-e2e-oracle.ps1'))
            if (-not [string]::IsNullOrWhiteSpace($OracleConfigPath)) {
                $arguments += @('-ConfigPath', $OracleConfigPath)
            }
            New-CheckDefinition -Name 'oracle-e2e' -Command 'pwsh' -Arguments $arguments
        }
        'DirectorySecrets' {
            New-CheckDefinition -Name 'directory-secrets' -Command $GitleaksCommand -Arguments @(
                'dir', '--redact', '--config', (Join-Path $RepoRoot '.gitleaks.toml'), '.'
            )
        }
        'DependencyAudit' {
            New-CheckDefinition -Name 'root-dependency-audit' -Command $NpmCommand -Arguments @('audit', '--audit-level=high')
            New-CheckDefinition -Name 'frontend-dependency-audit' -Command $NpmCommand -Arguments @('--prefix', 'frontend', 'audit', '--audit-level=high')
            New-CheckDefinition -Name 'backend-dependency-audit' -Command $MavenCommand -Arguments (Get-MavenArguments -Offline:$Offline -Goals @(
                'org.owasp:dependency-check-maven:12.2.2:check'
            ))
        }
    }
}

function Get-OracleCheckDefinitions {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$OracleConfigPath,
        [switch]$AllowDdl,
        [string]$DdlScript
    )

    $oracleScript = Join-Path $RepoRoot 'backend/scripts/test-oracle.ps1'
    $baseArguments = @('-NoProfile', '-File', $oracleScript)
    if (-not [string]::IsNullOrWhiteSpace($OracleConfigPath)) {
        $baseArguments += @('-ConfigPath', $OracleConfigPath)
    }

    @(
        New-CheckDefinition -Name 'oracle-safety-guard' -Command 'pwsh' -Arguments ($baseArguments + @('-DskipTests', 'test-compile'))
        New-CheckDefinition -Name 'oracle-integration-tests' -Command 'pwsh' -Arguments ($baseArguments + @('test'))
    )

    if (-not [string]::IsNullOrWhiteSpace($DdlScript)) {
        if (-not $AllowDdl) {
            throw 'DdlScript requires -AllowDdl.'
        }
        New-CheckDefinition -Name 'oracle-ddl' -Command 'pwsh' -Arguments (
            $baseArguments + @('-AllowDdl', '-DdlScript', $DdlScript, '-DskipTests', 'test-compile')
        )
    }
}

function Get-ImpactLayerCheckDefinitions {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FullFrontend', 'FullBackend', 'BackendUnit', 'FrontendCoverage', 'E2E', 'DirectorySecrets', 'Oracle', 'BackendCoverage', 'E2EOracle')]
        [string]$Layer,
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$NpmCommand,
        [Parameter(Mandatory)][string]$MavenCommand,
        [Parameter(Mandatory)][string]$GitleaksCommand,
        [string]$OracleConfigPath,
        [switch]$Offline
    )

    if ($Layer -eq 'Oracle') {
        return Get-OracleCheckDefinitions -RepoRoot $RepoRoot -OracleConfigPath $OracleConfigPath
    }
    if ($Layer -eq 'BackendUnit') {
        # The existing BackendUnit CiTask remains the curated fast contract. Impact/full paths use Maven's
        # standard test discovery so a changed controller or service cannot be reported as covered by a fixed list.
        return New-CheckDefinition -Name 'impact-backend-unit-test' -Command $MavenCommand -Arguments (
            Get-MavenArguments -Offline:$Offline -Goals @('test')
        )
    }
    Get-CiTaskDefinitions -CiTask $Layer -RepoRoot $RepoRoot -NpmCommand $NpmCommand `
        -MavenCommand $MavenCommand -OracleScript (Join-Path $RepoRoot 'backend/scripts/test-oracle.ps1') `
        -OracleConfigPath $OracleConfigPath -GitleaksCommand $GitleaksCommand -Offline:$Offline
}

function Write-ImpactLayerOutput {
    param([Parameter(Mandatory)][string]$State, [Parameter(Mandatory)][bool]$Selected)

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
        "state=$($State.ToLowerInvariant())" | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8NoBOM
        "selected=$($Selected.ToString().ToLowerInvariant())" | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8NoBOM
    }
}

function Invoke-ImpactLayer {
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]
        [ValidateSet('FullFrontend', 'FullBackend', 'BackendUnit', 'FrontendCoverage', 'E2E', 'DirectorySecrets', 'Oracle', 'BackendCoverage', 'E2EOracle')]
        [string]$Layer,
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$ResultPath,
        [string]$NpmCommand = 'npm',
        [string]$MavenCommand = 'mvnw',
        [string]$GitleaksCommand = 'gitleaks',
        [string]$OracleConfigPath,
        [switch]$Offline,
        [scriptblock]$CommandInvoker
    )

    Assert-ImpactPlan -Plan $Plan
    $selected = @($Plan.SelectedLayers) -contains $Layer
    $reason = Get-ImpactLayerReason -Plan $Plan -Layer $Layer
    if (-not $selected) {
        $result = [pscustomobject][ordered]@{
            SchemaVersion = 1
            Layer = $Layer
            Selected = $false
            State = 'Excluded'
            Reason = $reason
            Checks = @()
        }
        Write-ImpactJson -Value $result -Path $ResultPath
        Write-ImpactLayerOutput -State 'Excluded' -Selected $false
        Write-ImpactSummary -Lines @('## Impact layer result', '', "- Layer: $Layer", '- State: Excluded', "- Reason: $reason")
        return 0
    }

    $failures = [System.Collections.Generic.List[string]]::new()
    $checkResults = [System.Collections.Generic.List[object]]::new()
    try {
        $definitions = @(Get-ImpactLayerCheckDefinitions -Layer $Layer -RepoRoot $RepoRoot `
            -NpmCommand $NpmCommand -MavenCommand $MavenCommand -GitleaksCommand $GitleaksCommand `
            -OracleConfigPath $OracleConfigPath -Offline:$Offline)
        if ($definitions.Count -eq 0) { throw "Selected impact layer has no checks: $Layer" }
        if ($PSBoundParameters.ContainsKey('CommandInvoker')) {
            Invoke-QualityChecks -Definitions $definitions -Failures $failures -Results $checkResults `
                -CommandInvoker $CommandInvoker
        }
        else {
            Invoke-QualityChecks -Definitions $definitions -Failures $failures -Results $checkResults
        }
    }
    catch {
        $failures.Add("impact-$($Layer.ToLowerInvariant())-definition")
        $checkResults.Add([pscustomobject][ordered]@{
                Name = 'impact-layer-definition'
                State = 'Failed'
                Detail = $_.Exception.Message
            })
        Write-Warning "FAIL impact layer ${Layer}: $($_.Exception.Message)"
    }

    $state = if ($failures.Count -eq 0) { 'Passed' } else { 'Failed' }
    $result = [pscustomobject][ordered]@{
        SchemaVersion = 1
        Layer = $Layer
        Selected = $true
        State = $state
        Reason = $reason
        Checks = @($checkResults)
    }
    Write-ImpactJson -Value $result -Path $ResultPath
    Write-ImpactLayerOutput -State $state -Selected $true
    Write-ImpactSummary -Lines @(
        '## Impact layer result'
        ''
        "- Layer: $Layer"
        "- State: $state"
        "- Reason: $reason"
        "- Failed checks: $($failures.Count)"
    )
    if ($failures.Count -gt 0) { return 1 }
    0
}

function ConvertFrom-ImpactJobMap {
    param([Parameter(Mandatory)][string]$Value)

    $map = @{}
    foreach ($entry in ($Value -split ',')) {
        $pair = @($entry.Trim() -split '=', 2)
        if ($pair.Count -ne 2 -or [string]::IsNullOrWhiteSpace($pair[0]) -or [string]::IsNullOrWhiteSpace($pair[1])) {
            throw "Invalid impact job map entry: $entry"
        }
        $map[$pair[0]] = $pair[1]
    }
    $map
}

function Test-ImpactAggregate {
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][string[]]$Layers,
        [Parameter(Mandatory)][hashtable]$JobMap,
        [Parameter(Mandatory)][hashtable]$JobResults,
        [switch]$AllowExcludedJobSkip
    )

    Assert-ImpactPlan -Plan $Plan
    $rows = [System.Collections.Generic.List[object]]::new()
    $succeeded = $true
    foreach ($layer in $Layers) {
        if (@(Get-ImpactLayerNames) -notcontains $layer) { throw "Unknown aggregate layer: $layer" }
        if (-not $JobMap.ContainsKey($layer)) { throw "Impact job map is missing layer: $layer" }
        $jobId = [string]$JobMap[$layer]
        $selected = @($Plan.SelectedLayers) -contains $layer
        $job = if ($JobResults.ContainsKey($jobId)) { $JobResults[$jobId] } else { $null }
        $jobResult = if ($null -ne $job) { [string]$job.result } else { 'missing' }
        $state = if ($null -ne $job -and $job.ContainsKey('outputs') -and $job.outputs.ContainsKey('state')) {
            [string]$job.outputs.state
        }
        else { '' }

        if ($selected) {
            $valid = $jobResult -eq 'success' -and $state -eq 'passed'
            $expected = 'Passed'
        }
        else {
            $validExplicit = $jobResult -eq 'success' -and $state -eq 'excluded'
            $validSkip = $AllowExcludedJobSkip -and $jobResult -eq 'skipped'
            $valid = $validExplicit -or $validSkip
            $expected = 'Excluded'
        }
        if (-not $valid) { $succeeded = $false }
        $rows.Add([pscustomobject][ordered]@{
                Layer = $layer
                Job = $jobId
                Selected = $selected
                Expected = $expected
                JobResult = $jobResult
                State = if ([string]::IsNullOrWhiteSpace($state)) { 'missing' } else { $state }
                Valid = $valid
            })
    }
    [pscustomobject][ordered]@{ Succeeded = $succeeded; Jobs = @($rows) }
}

function Invoke-ImpactAggregate {
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][string]$JobResultsJson,
        [Parameter(Mandatory)][string]$JobMap,
        [Parameter(Mandatory)][string]$ResultPath,
        [switch]$AllowExcludedJobSkip
    )

    $map = ConvertFrom-ImpactJobMap -Value $JobMap
    $jobResults = $JobResultsJson | ConvertFrom-Json -AsHashtable
    $layers = @($map.Keys)
    $aggregate = Test-ImpactAggregate -Plan $Plan -Layers $layers -JobMap $map -JobResults $jobResults `
        -AllowExcludedJobSkip:$AllowExcludedJobSkip
    Write-ImpactJson -Value $aggregate -Path $ResultPath

    $summary = [System.Collections.Generic.List[string]]::new()
    $summary.Add('## Impact aggregate')
    $summary.Add('')
    $summary.Add('| Layer | Expected | Job result | Recorded state | Valid |')
    $summary.Add('| --- | --- | --- | --- | --- |')
    foreach ($row in $aggregate.Jobs) {
        $summary.Add("| $($row.Layer) | $($row.Expected) | $($row.JobResult) | $($row.State) | $($row.Valid) |")
    }
    Write-ImpactSummary -Lines @($summary)
    Write-ImpactLayerOutput -State $(if ($aggregate.Succeeded) { 'Passed' } else { 'Failed' }) -Selected $true
    if ($aggregate.Succeeded) { return 0 }
    1
}

function Invoke-QualityChecks {
    param(
        [object[]]$Definitions,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Failures,
        [scriptblock]$CommandInvoker = {
            param($Command, $Arguments, $WorkingDirectory)
            $hasWorkingDirectory = -not [string]::IsNullOrWhiteSpace($WorkingDirectory)
            if ($hasWorkingDirectory) {
                Push-Location $WorkingDirectory
            }
            try {
                & $Command @Arguments | Out-Host
                $LASTEXITCODE
            }
            finally {
                if ($hasWorkingDirectory) {
                    Pop-Location
                }
            }
        },
        [System.Collections.Generic.List[object]]$Results
    )

    foreach ($definition in $Definitions) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $failedDependencies = @($definition.DependsOn | Where-Object { $Failures -contains $_ })
        if ($failedDependencies.Count -gt 0) {
            Write-Warning "SKIP $($definition.Name): dependency failed: $($failedDependencies -join ', ')"
            if ($null -ne $Results) {
                $Results.Add([pscustomobject][ordered]@{
                        Name = $definition.Name
                        State = 'Skipped'
                        Detail = "Dependency failed: $($failedDependencies -join ', ')"
                    })
            }
            continue
        }
        Write-Host "==> $($definition.Name)"
        try {
            if ($definition.Action) {
                & $definition.Action
                $exitCode = 0
            }
            else {
                $result = & $CommandInvoker $definition.Command @($definition.Arguments) $definition.WorkingDirectory
                $exitCode = if ($result -is [int]) { $result } else { [int]$result.ExitCode }
            }
            if ($exitCode -ne 0) {
                throw "Command exited with code $exitCode."
            }
            Write-Host "PASS $($definition.Name) ($([math]::Round($stopwatch.Elapsed.TotalSeconds, 2))s)"
            if ($null -ne $Results) {
                $Results.Add([pscustomobject][ordered]@{ Name = $definition.Name; State = 'Passed'; Detail = '' })
            }
        }
        catch {
            $Failures.Add($definition.Name)
            Write-Warning "FAIL $($definition.Name) ($([math]::Round($stopwatch.Elapsed.TotalSeconds, 2))s): $($_.Exception.Message)"
            if ($null -ne $Results) {
                $Results.Add([pscustomobject][ordered]@{
                        Name = $definition.Name
                        State = 'Failed'
                        Detail = $_.Exception.Message
                    })
            }
        }
        finally {
            $stopwatch.Stop()
        }
    }
}

function Get-StagedFiles {
    param([Parameter(Mandatory)][string]$RepoRoot)

    # How: 日本語を含むstagedパスをGitの引用・エスケープなしで取得し、拡張子や配置判定へ渡す。
    # Why not: Git既定のquotePath出力をそのまま使うと、引用符付きパスがMarkdownや生成物判定から漏れるため。
    $files = @(git -c core.quotePath=false -C $RepoRoot diff --cached --name-only --diff-filter=ACMR)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to read staged file names from Git.'
    }
    @($files | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-GitleaksCommand {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $binaryName = if ($isWindowsHost) { 'gitleaks.exe' } else { 'gitleaks' }
    $localPath = Join-Path $RepoRoot ".tools/gitleaks/8.30.1/$binaryName"
    if (Test-Path -LiteralPath $localPath -PathType Leaf) {
        return $localPath
    }
    'gitleaks'
}

function Invoke-QualityRunner {
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,
        [ValidateSet('Quick', 'PrePush', 'Full', 'Simple', 'Oracle', 'All', 'Impact')]
        [string]$Mode = 'Quick',
        [string]$PushInput,
        [switch]$Offline,
        [ValidateSet('None', 'FullFrontend', 'FullBackend', 'FrontendCoverage', 'BackendCoverage', 'BackendUnit', 'E2E', 'E2EOracle', 'DirectorySecrets', 'DependencyAudit')]
        [string]$CiTask = 'None',
        [switch]$AllowDdl,
        [string]$DdlScript,
        [string]$OracleConfigPath,
        [string]$Scope,
        [string]$FocusedUnitScope,
        [string]$FocusedUnitTarget,
        [string]$FocusedUnitNotApplicableReason,
        [switch]$DisplayRequirement,
        [string]$BrowserCase,
        [string]$BrowserManualReason,
        [ValidateSet('Plan', 'FullFrontend', 'FullBackend', 'BackendUnit', 'FrontendCoverage', 'E2E', 'DirectorySecrets', 'Oracle', 'BackendCoverage', 'E2EOracle', 'Aggregate')]
        [string]$ImpactTask = 'Plan',
        [string]$ChangedFilesPath,
        [string]$BaseRef,
        [string]$HeadRef,
        [string]$ImpactPlanPath,
        [string]$ImpactResultPath,
        [string]$ImpactJobResultsJson,
        [string]$ImpactJobMap,
        [string]$ForceFullReason,
        [switch]$AllowExcludedJobSkip
    )

    $failures = [System.Collections.Generic.List[string]]::new()
    $npmCommand = if ($isWindowsHost) { 'npm.cmd' } else { 'npm' }
    $gitleaksCommand = Get-GitleaksCommand -RepoRoot $RepoRoot
    $mavenCommand = if ($isWindowsHost) {
        Join-Path $RepoRoot 'backend/mvnw.cmd'
    }
    else {
        Join-Path $RepoRoot 'backend/mvnw'
    }
    Write-Host (Get-QualityTimeoutGuidance -Mode $Mode -CiTask $CiTask -ImpactTask $ImpactTask)

    Push-Location $RepoRoot
    try {
        if ($Mode -eq 'Impact' -and $CiTask -ne 'None') {
            $failures.Add('impact-definition')
            Write-Warning 'Impact Mode cannot be combined with -CiTask.'
        }
        elseif ($Mode -eq 'Impact') {
            try {
                if ([string]::IsNullOrWhiteSpace($ImpactPlanPath)) {
                    throw 'Impact Mode requires -ImpactPlanPath.'
                }
                if ($ImpactTask -eq 'Plan') {
                    if (-not [string]::IsNullOrWhiteSpace($ForceFullReason)) {
                        $plan = Get-ImpactPlan -ForceFullReason $ForceFullReason
                    }
                    else {
                        try {
                            $changedFiles = @(Get-ImpactChangedFiles -RepoRoot $RepoRoot `
                                -ChangedFilesPath $ChangedFilesPath -BaseRef $BaseRef -HeadRef $HeadRef)
                            $plan = Get-ImpactPlan -ChangedFiles $changedFiles
                        }
                        catch {
                            $plan = New-FullImpactPlan -FallbackReason "IMPACT_SCOPE_UNAVAILABLE: $($_.Exception.Message)"
                        }
                    }
                    Assert-ImpactPlan -Plan $plan
                    Write-ImpactJson -Value $plan -Path $ImpactPlanPath
                    Write-ImpactPlanOutputs -Plan $plan
                    Write-ImpactPlanSummary -Plan $plan
                }
                elseif ($ImpactTask -eq 'Aggregate') {
                    if ([string]::IsNullOrWhiteSpace($ImpactResultPath)) {
                        throw 'Impact Aggregate requires -ImpactResultPath.'
                    }
                    if ([string]::IsNullOrWhiteSpace($ImpactJobResultsJson) -or [string]::IsNullOrWhiteSpace($ImpactJobMap)) {
                        throw 'Impact Aggregate requires -ImpactJobResultsJson and -ImpactJobMap.'
                    }
                    $plan = Get-Content -Raw -Encoding UTF8 -LiteralPath $ImpactPlanPath | ConvertFrom-Json
                    $aggregateExit = Invoke-ImpactAggregate -Plan $plan -JobResultsJson $ImpactJobResultsJson `
                        -JobMap $ImpactJobMap -ResultPath $ImpactResultPath `
                        -AllowExcludedJobSkip:$AllowExcludedJobSkip
                    if ($aggregateExit -ne 0) { $failures.Add('impact-aggregate') }
                }
                else {
                    if ([string]::IsNullOrWhiteSpace($ImpactResultPath)) {
                        throw 'Impact layer execution requires -ImpactResultPath.'
                    }
                    $plan = Get-Content -Raw -Encoding UTF8 -LiteralPath $ImpactPlanPath | ConvertFrom-Json
                    $layerExit = Invoke-ImpactLayer -Plan $plan -Layer $ImpactTask -RepoRoot $RepoRoot `
                        -ResultPath $ImpactResultPath -NpmCommand $npmCommand -MavenCommand $mavenCommand `
                        -GitleaksCommand $gitleaksCommand -OracleConfigPath $OracleConfigPath -Offline:$Offline
                    if ($layerExit -ne 0) { $failures.Add("impact-$($ImpactTask.ToLowerInvariant())") }
                }
            }
            catch {
                $failures.Add('impact-definition')
                Write-Warning "FAIL impact-definition: $($_.Exception.Message)"
            }
        }
        elseif ($Mode -eq 'Simple' -and $CiTask -ne 'None') {
            $failures.Add('simple-definition')
            Write-Warning 'Simple Mode cannot be combined with -CiTask.'
        }
        elseif ($Mode -eq 'Simple') {
            try {
                if ([string]::IsNullOrWhiteSpace($Scope)) {
                    throw 'Simple Mode requires -Scope.'
                }

                $changedFiles = @(Get-WorkingTreeChangedFiles -RepoRoot $RepoRoot)
                $definitions = @(Get-SimpleCheckDefinitions -RepoRoot $RepoRoot -Scope $Scope `
                    -FocusedUnitScope $FocusedUnitScope -FocusedUnitTarget $FocusedUnitTarget `
                    -FocusedUnitNotApplicableReason $FocusedUnitNotApplicableReason `
                    -DisplayRequirement:$DisplayRequirement -BrowserCase $BrowserCase `
                    -BrowserManualReason $BrowserManualReason -ChangedFiles $changedFiles `
                    -NpmCommand $npmCommand -MavenCommand $mavenCommand -Offline:$Offline)
                Invoke-QualityChecks -Definitions $definitions -Failures $failures
            }
            catch {
                $failures.Add('simple-definition')
                Write-Warning "FAIL simple-definition: $($_.Exception.Message)"
            }
        }
        elseif ($CiTask -ne 'None') {
            $definitions = @(Get-CiTaskDefinitions -CiTask $CiTask -RepoRoot $RepoRoot -NpmCommand $npmCommand `
                -MavenCommand $mavenCommand -OracleScript (Join-Path $RepoRoot 'backend/scripts/test-oracle.ps1') `
                -OracleConfigPath $OracleConfigPath -GitleaksCommand $gitleaksCommand -Offline:$Offline)
            Invoke-QualityChecks -Definitions $definitions -Failures $failures
        }
        else {
            if ($Mode -eq 'PrePush') {
                try {
                    $pushRefs = @(Get-PushRefRecords -InputText (Get-PrePushInputText -ProvidedInput $PushInput))
                    $changedFiles = @(Get-PrePushChangedFiles -RepoRoot $RepoRoot -PushRefs $pushRefs)
                    $definitions = @(Get-PrePushCheckDefinitions -RepoRoot $RepoRoot -ChangedFiles $changedFiles `
                        -PushRefs $pushRefs -NpmCommand $npmCommand -MavenCommand $mavenCommand `
                        -GitleaksCommand $gitleaksCommand -Offline:$Offline)
                    Invoke-QualityChecks -Definitions $definitions -Failures $failures
                }
                catch {
                    $failures.Add('pre-push-definition')
                    Write-Warning "FAIL pre-push-definition: $($_.Exception.Message)"
                }
            }
            if ($Mode -in @('Quick')) {
                try {
                    $stagedFiles = @(Get-StagedFiles -RepoRoot $RepoRoot)
                    $definitions = @(Get-QuickCheckDefinitions -RepoRoot $RepoRoot -StagedFiles $stagedFiles `
                        -NpmCommand $npmCommand -MavenCommand $mavenCommand -GitleaksCommand $gitleaksCommand -Offline:$Offline)
                    Invoke-QualityChecks -Definitions $definitions -Failures $failures
                }
                catch {
                    $failures.Add('staged-file-selection')
                    Write-Warning "FAIL staged-file-selection: $($_.Exception.Message)"
                }
            }
            if ($Mode -in @('Full', 'All')) {
                $definitions = @(Get-FullCheckDefinitions -RepoRoot $RepoRoot -NpmCommand $npmCommand `
                    -MavenCommand $mavenCommand -Offline:$Offline)
                Invoke-QualityChecks -Definitions $definitions -Failures $failures
            }
            if ($Mode -in @('Oracle', 'All')) {
                try {
                    $definitions = @(Get-OracleCheckDefinitions -RepoRoot $RepoRoot -OracleConfigPath $OracleConfigPath `
                        -AllowDdl:$AllowDdl -DdlScript $DdlScript)
                    Invoke-QualityChecks -Definitions $definitions -Failures $failures
                }
                catch {
                    $failures.Add('oracle-definition')
                    Write-Warning "FAIL oracle-definition: $($_.Exception.Message)"
                }
            }
        }
    }
    finally {
        Pop-Location
    }

    if ($failures.Count -gt 0) {
        Write-Host "`nFailed checks:"
        $failures | ForEach-Object { Write-Host " - $_" }
        return 1
    }

    Write-Host "`nAll requested checks passed."
    return 0
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Error 'scripts/check.ps1 requires PowerShell 7 or later.'
        exit 1
    }

    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    exit (Invoke-QualityRunner -RepoRoot $repoRoot -Mode $Mode -PushInput $PushInput -Offline:$Offline `
        -CiTask $CiTask -AllowDdl:$AllowDdl -DdlScript $DdlScript -OracleConfigPath $OracleConfigPath `
        -Scope $Scope -FocusedUnitScope $FocusedUnitScope -FocusedUnitTarget $FocusedUnitTarget `
        -FocusedUnitNotApplicableReason $FocusedUnitNotApplicableReason `
        -DisplayRequirement:$DisplayRequirement -BrowserCase $BrowserCase -BrowserManualReason $BrowserManualReason `
        -ImpactTask $ImpactTask -ChangedFilesPath $ChangedFilesPath -BaseRef $BaseRef -HeadRef $HeadRef `
        -ImpactPlanPath $ImpactPlanPath -ImpactResultPath $ImpactResultPath `
        -ImpactJobResultsJson $ImpactJobResultsJson -ImpactJobMap $ImpactJobMap `
        -ForceFullReason $ForceFullReason -AllowExcludedJobSkip:$AllowExcludedJobSkip)
}
