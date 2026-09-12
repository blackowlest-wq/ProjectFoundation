[CmdletBinding()]
param(
    [ValidateSet('Red', 'Green')]
    [string]$Phase = 'Green',
    [string]$Case = 'TC-PFL-025'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$checkScript = Join-Path $repoRoot 'scripts/check.ps1'
$fixtureRoot = Join-Path $repoRoot 'scripts/fixtures/project-lint'
$baseCatalogPath = Join-Path $repoRoot 'config/project-lint-policies.json'
$fixedHead = '905a9676a7d48a86bf9aab6fb34dcbf08c65f402'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Assert-Condition {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param(
        [AllowNull()][object]$Actual,
        [AllowNull()][object]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected=[$Expected] Actual=[$Actual]"
    }
}

function Assert-Contains {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Needle,
        [Parameter(Mandatory)][string]$Message
    )

    Assert-Condition $Text.Contains($Needle) "$Message Missing=[$Needle]"
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Needle,
        [Parameter(Mandatory)][string]$Message
    )

    Assert-Condition (-not $Text.Contains($Needle)) "$Message Found=[$Needle]"
}

function Assert-SetEquals {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Actual,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    $actualText = @($Actual | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join ','
    $expectedText = @($Expected | ForEach-Object { [string]$_ } | Sort-Object -Unique) -join ','
    Assert-Equal $actualText $expectedText $Message
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        $null = [System.IO.Directory]::CreateDirectory($parent)
    }
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function New-IsolatedRepository {
    param(
        [string]$CatalogSource = $baseCatalogPath,
        [switch]$InitializeGit
    )

    $name = '.check-contract-' + [Guid]::NewGuid().ToString('N')
    $path = Join-Path $repoRoot $name
    $null = [System.IO.Directory]::CreateDirectory($path)
    $catalogPath = Join-Path $path 'config/project-lint-policies.json'
    Write-Utf8File -Path $catalogPath -Content ([System.IO.File]::ReadAllText($CatalogSource, $utf8NoBom))
    if ($InitializeGit) {
        Write-Utf8File -Path (Join-Path $path 'fixture.txt') -Content "contract fixture`n"
        & git -C $path init -q | Out-Null
        & git -C $path config user.email contract@example.invalid | Out-Null
        & git -C $path config user.name contract | Out-Null
        & git -C $path add . | Out-Null
        & git -C $path commit -q -m fixture | Out-Null
    }
    $path
}

function Remove-IsolatedRepository {
    param([AllowNull()][string]$Path)

    if (-not [string]::IsNullOrWhiteSpace($Path) -and [System.IO.Directory]::Exists($Path)) {
        for ($attempt = 0; $attempt -lt 10; $attempt++) {
            if ([System.IO.Directory]::Exists($Path)) {
                Get-ChildItem -Force -Recurse -LiteralPath $Path | ForEach-Object {
                    $_.Attributes = [System.IO.FileAttributes]::Normal
                }
                try {
                    [System.IO.Directory]::Delete($Path, $true)
                    break
                }
                catch {
                    if ($attempt -eq 9) {
                        throw
                    }
                    Start-Sleep -Milliseconds 100
                }
            }
        }
    }
}

function New-CommandShim {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [switch]$InitializeGit
    )

    $shimRoot = Join-Path $RepositoryRoot '.check-shim'
    $null = [System.IO.Directory]::CreateDirectory($shimRoot)
    $recordPath = Join-Path $shimRoot 'invocations.log'
    $shimScript = Join-Path $shimRoot 'command-shim.ps1'
    $actualPwsh = (Get-Command pwsh -ErrorAction Stop).Source

    Write-Utf8File -Path $shimScript -Content @'
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Kind
)

$recordPath = $env:PROJECTFOUNDATION_SHIM_RECORD_PATH
$argumentText = [string]$env:PROJECTFOUNDATION_SHIM_ARGUMENT_TEXT
if (-not [string]::IsNullOrWhiteSpace($recordPath)) {
    Add-Content -LiteralPath $recordPath -Value "$Kind|$argumentText" -Encoding utf8NoBOM
}
if (-not [string]::IsNullOrWhiteSpace($env:PROJECTFOUNDATION_SHIM_STDOUT)) {
    [Console]::Out.WriteLine($env:PROJECTFOUNDATION_SHIM_STDOUT)
}
if (-not [string]::IsNullOrWhiteSpace($env:PROJECTFOUNDATION_SHIM_STDERR)) {
    [Console]::Error.WriteLine($env:PROJECTFOUNDATION_SHIM_STDERR)
}

$exitCode = 0
if ($Kind -eq 'pwsh' -and $argumentText -match '(?i)project-lint\.ps1') {
    $exitCode = [int]$env:PROJECTFOUNDATION_SHIM_PROJECT_LINT_EXIT
}
elseif ($Kind -eq 'maven' -and $argumentText -match '(?i)EndpointMetadataRegistryContractTest') {
    $exitCode = [int]$env:PROJECTFOUNDATION_SHIM_D_EXIT
}
elseif ($Kind -eq 'npm') {
    $exitCode = [int]$env:PROJECTFOUNDATION_SHIM_NPM_EXIT
    if ($argumentText -match '(?i)(^|\s)eslint(\s|$)') {
        $sourceRoot = Join-Path (Get-Location) 'frontend/src'
        if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
            $sourceRoot = Join-Path (Get-Location) 'src'
        }
        if (Test-Path -LiteralPath $sourceRoot -PathType Container) {
            $baseViolation = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @('.ts', '.tsx') } |
                ForEach-Object {
                    try {
                        [System.IO.File]::ReadAllText($_.FullName)
                    }
                    catch {
                        ''
                    }
                } |
                Where-Object { $_.Contains('TC-PFL-077-BASE-ESLINT-VIOLATION') })
            if ($baseViolation.Count -gt 0) {
                $exitCode = 1
            }
        }
    }
}
elseif ($Kind -eq 'gitleaks') {
    $exitCode = [int]$env:PROJECTFOUNDATION_SHIM_GITLEAKS_EXIT
}
elseif ($Kind -eq 'pwsh') {
    $exitCode = [int]$env:PROJECTFOUNDATION_SHIM_PWSH_EXIT
}
exit $exitCode
'@

    $wrapperTemplate = {
        param([Parameter(Mandatory)][string]$Kind)
        "@echo off`r`nset `"PROJECTFOUNDATION_SHIM_ARGUMENT_TEXT=%*`"`r`n`"$actualPwsh`" -NoProfile -File `"$shimScript`" -Kind $Kind`r`nexit /b %ERRORLEVEL%`r`n"
    }
    Write-Utf8File -Path (Join-Path $shimRoot 'pwsh.cmd') -Content (& $wrapperTemplate 'pwsh')
    Write-Utf8File -Path (Join-Path $shimRoot 'npm.cmd') -Content (& $wrapperTemplate 'npm')
    Write-Utf8File -Path (Join-Path $shimRoot 'gitleaks.cmd') -Content (& $wrapperTemplate 'gitleaks')
    $mavenWrapper = Join-Path $RepositoryRoot 'backend/mvnw.cmd'
    Write-Utf8File -Path $mavenWrapper -Content (& $wrapperTemplate 'maven')

    [pscustomobject]@{
        Root = $shimRoot
        RecordPath = $recordPath
        Path = "$shimRoot;$env:PATH"
    }
}

function New-BrokenFrontendConnectionCheckScript {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $scriptsPath = Join-Path $RepositoryRoot 'scripts'
    $copyPath = Join-Path $scriptsPath 'check.ps1'
    $source = [System.IO.File]::ReadAllText($checkScript, $utf8NoBom)
    $needle = "[pscustomobject]@{ PolicyId = 'PF-FE-001'; Adapter = 'A'; DefinitionNames = @('frontend-lint', 'simple-frontend-lint', 'custom-frontend-lint') }"
    Assert-Contains -Text $source -Needle $needle -Message 'TC-PFL-023 broken A fixture source seam.'
    $replacement = "[pscustomobject]@{ PolicyId = 'PF-FE-001'; Adapter = 'A'; DefinitionNames = @('broken-frontend-lint') }"
    Write-Utf8File -Path $copyPath -Content $source.Replace($needle, $replacement)
    $copyPath
}

function Invoke-Check {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [hashtable]$Environment = @{}
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command pwsh -ErrorAction Stop).Source
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    $startInfo.WorkingDirectory = $repoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($entry in $Environment.GetEnumerator()) {
        $startInfo.Environment[$entry.Key] = [string]$entry.Value
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout = $stdout
            Stderr = $stderr
        }
    }
    finally {
        $process.Dispose()
    }
}

function New-CheckEnvironment {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ResultPath,
        [Parameter(Mandatory)][object]$Shim,
        [int]$ProjectLintExit = 0,
        [int]$DExit = 0,
        [int]$NpmExit = 0,
        [int]$PwshExit = 0,
        [int]$GitleaksExit = 0,
        [string]$StdoutMarker = '',
        [string]$StderrMarker = '',
        [hashtable]$AdditionalEnvironment = @{}
    )

    @{
        PATH = $Shim.Path
        PROJECTFOUNDATION_CHECK_RESULT_PATH = $ResultPath
        PROJECTFOUNDATION_CONTRACT_PWSH_COMMAND = (Join-Path $Shim.Root 'pwsh.cmd')
        PROJECTFOUNDATION_SHIM_RECORD_PATH = $Shim.RecordPath
        PROJECTFOUNDATION_SHIM_PROJECT_LINT_EXIT = $ProjectLintExit
        PROJECTFOUNDATION_SHIM_D_EXIT = $DExit
        PROJECTFOUNDATION_SHIM_NPM_EXIT = $NpmExit
        PROJECTFOUNDATION_SHIM_PWSH_EXIT = $PwshExit
        PROJECTFOUNDATION_SHIM_GITLEAKS_EXIT = $GitleaksExit
        PROJECTFOUNDATION_SHIM_STDOUT = $StdoutMarker
        PROJECTFOUNDATION_SHIM_STDERR = $StderrMarker
    }
}

function Read-ContractResult {
    param([Parameter(Mandatory)][string]$Path)

    Assert-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "Missing C result JSON: $Path"
    Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json -Depth 100
}

function Read-ShimInvocations {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }
    @(Get-Content -Encoding UTF8 -LiteralPath $Path)
}

function Invoke-IsolatedCheck {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string[]]$CheckArguments,
        [string]$CheckScriptPath = $checkScript,
        [int]$ProjectLintExit = 0,
        [int]$DExit = 0,
        [int]$NpmExit = 0,
        [int]$PwshExit = 0,
        [int]$GitleaksExit = 0,
        [string]$StdoutMarker = '',
        [string]$StderrMarker = '',
        [hashtable]$AdditionalEnvironment = @{}
    )

    $shim = New-CommandShim -RepositoryRoot $RepositoryRoot
    $resultPath = Join-Path $RepositoryRoot '.check-result.json'
    $environment = New-CheckEnvironment -RepositoryRoot $RepositoryRoot -ResultPath $resultPath `
        -Shim $shim -ProjectLintExit $ProjectLintExit -DExit $DExit -NpmExit $NpmExit `
        -PwshExit $PwshExit -GitleaksExit $GitleaksExit -StdoutMarker $StdoutMarker -StderrMarker $StderrMarker
    foreach ($entry in $AdditionalEnvironment.GetEnumerator()) {
        $environment[$entry.Key] = $entry.Value
    }
    $arguments = @('-NoProfile', '-File', $CheckScriptPath, '-RepositoryRoot', $RepositoryRoot) + $CheckArguments
    $processResult = Invoke-Check -Arguments $arguments -Environment $environment
    [pscustomobject]@{
        Process = $processResult
        Contract = Read-ContractResult -Path $resultPath
        Invocations = @(Read-ShimInvocations -Path $shim.RecordPath)
        Root = $RepositoryRoot
    }
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$WorkingDirectory = $repoRoot,
        [hashtable]$Environment = @{}
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $command = Get-Command $FileName -ErrorAction Stop
    $startInfo.FileName = $command.Source
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($entry in $Environment.GetEnumerator()) {
        $startInfo.Environment[$entry.Key] = [string]$entry.Value
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout = $stdout
            Stderr = $stderr
        }
    }
    finally {
        $process.Dispose()
    }
}

function Get-InvocationMatches {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Invocations,
        [Parameter(Mandatory)][string]$Pattern
    )

    @($Invocations | Where-Object { $_ -match $Pattern })
}

function Test-ImpactPlanFallback {
    $changedFilesPath = Join-Path $fixtureRoot 'TC-PFL-025-impact-selector-fallback/changed-files.txt'
    $planPath = Join-Path ([System.IO.Path]::GetTempPath()) "projectfoundation-contract-$PID-plan.json"
    try {
        $result = Invoke-Check -Arguments @(
            '-NoProfile', '-File', $checkScript,
            '-Mode', 'Impact', '-ImpactTask', 'Plan',
            '-ChangedFilesPath', $changedFilesPath,
            '-ImpactPlanPath', $planPath
        )
        Assert-Equal $result.ExitCode 0 'TC-PFL-025 C exit code.'
        $plan = Get-Content -Raw -Encoding UTF8 $planPath | ConvertFrom-Json
        Assert-Equal $plan.SchemaVersion 1 'TC-PFL-025 SchemaVersion.'
        Assert-Equal $plan.ExecutionScope 'Full' 'TC-PFL-025 ExecutionScope.'
        Assert-Equal @($plan.ChangedFiles).Count 1 'TC-PFL-025 ChangedFiles count.'
        Assert-Equal $plan.ChangedFiles[0] 'config/project-lint-policies.json' 'TC-PFL-025 ChangedFiles value.'
        Assert-Equal @($plan.SelectedLayers).Count 9 'TC-PFL-025 SelectedLayers count.'
        Assert-Equal @($plan.ExcludedLayers).Count 0 'TC-PFL-025 ExcludedLayers count.'
        Assert-Equal $plan.FallbackUsed $true 'TC-PFL-025 FallbackUsed.'
        Assert-Equal $plan.FallbackReason 'IMPACT_SELECTOR_OR_GATE_CHANGED: config/project-lint-policies.json' 'TC-PFL-025 FallbackReason.'
        Assert-Equal $plan.FullReason '' 'TC-PFL-025 FullReason.'
        Assert-Equal @($plan.LayerReasons.PSObject.Properties).Count 9 'TC-PFL-025 LayerReasons count.'
    }
    finally {
        if (Test-Path -LiteralPath $planPath) {
            Remove-Item -LiteralPath $planPath -Force
        }
    }
}

function Test-CChildExit2 {
    $subCases = @(
        [pscustomobject]@{ Name = 'one-then-two'; NpmExit = 1; ProjectLintExit = 2; First = 1; Second = 2 }
        [pscustomobject]@{ Name = 'two-then-one'; NpmExit = 2; ProjectLintExit = 1; First = 2; Second = 1 }
    )
    foreach ($subCase in $subCases) {
        $isolated = New-IsolatedRepository
        try {
            $stdoutMarker = "STDOUT_MARKER:TC-PFL-020:$($subCase.Name)"
            $stderrMarker = "STDERR_MARKER:TC-PFL-020:$($subCase.Name)"
            $execution = Invoke-IsolatedCheck -RepositoryRoot $isolated -CheckArguments @(
                '-CiTask', 'FullFrontend'
            ) -ProjectLintExit $subCase.ProjectLintExit -NpmExit $subCase.NpmExit `
                -StdoutMarker $stdoutMarker -StderrMarker $stderrMarker
            Assert-Equal $execution.Process.ExitCode 1 "TC-PFL-020 $($subCase.Name) C exit code."
            Assert-Equal $execution.Contract.Succeeded $false "TC-PFL-020 $($subCase.Name) aggregate success."
            Assert-Equal $execution.Contract.childExit 2 "TC-PFL-020 $($subCase.Name) childExit priority."
            $nonZero = @($execution.Contract.Checks |
                Where-Object { $null -ne $_.childExit -and [int]$_.childExit -ne 0 } |
                ForEach-Object { [int]$_.childExit })
            Assert-Condition ($nonZero.Count -ge 2) "TC-PFL-020 $($subCase.Name) needs two failed children."
            Assert-Equal $nonZero[0] $subCase.First "TC-PFL-020 $($subCase.Name) first child order."
            Assert-Equal $nonZero[$nonZero.Count - 1] $subCase.Second "TC-PFL-020 $($subCase.Name) last child order."
            $projectLint = @($execution.Contract.Checks | Where-Object Name -eq 'project-lint')
            Assert-Equal $projectLint.Count 1 "TC-PFL-020 $($subCase.Name) project-lint result count."
            Assert-Equal $projectLint[0].childExit $subCase.ProjectLintExit `
                "TC-PFL-020 $($subCase.Name) project-lint childExit."
            Assert-Contains -Text $execution.Process.Stdout -Needle $stdoutMarker `
                -Message "TC-PFL-020 $($subCase.Name) stdout channel."
            Assert-Contains -Text $execution.Process.Stderr -Needle $stderrMarker `
                -Message "TC-PFL-020 $($subCase.Name) stderr channel."
            Assert-NotContains -Text $execution.Process.Stdout -Needle $stderrMarker `
                -Message "TC-PFL-020 $($subCase.Name) channel swap."
            Assert-NotContains -Text $execution.Process.Stderr -Needle $stdoutMarker `
                -Message "TC-PFL-020 $($subCase.Name) channel swap."
            Assert-NotContains -Text (Get-Content -Raw -Encoding UTF8 $checkScript) `
                -Needle 'dot-source.*shim' -Message 'TC-PFL-020 check.ps1 shim coupling.'
        }
        finally {
            Remove-IsolatedRepository -Path $isolated
        }
    }
}

function Test-CLocalFull {
    $isolated = New-IsolatedRepository
    try {
        $execution = Invoke-IsolatedCheck -RepositoryRoot $isolated -CheckArguments @('-Mode', 'Full')
        Assert-Equal $execution.Process.ExitCode 0 'TC-PFL-021 C exit code.'
        Assert-Equal $execution.Contract.Succeeded $true 'TC-PFL-021 aggregate success.'
        Assert-SetEquals -Actual @($execution.Contract.Checks | ForEach-Object Name) -Expected @(
            'frontend-lint', 'frontend-typecheck', 'frontend-unit-test', 'frontend-build',
            'backend-quality', 'oracle-preflight-contract-test', 'coverage-summary-contract-test',
            'coverage-gate-contract-test', 'impact-runner-contract-test', 'impact-workflow-contract-test',
            'pmd-contract-test', 'project-lint', 'endpoint-metadata-registry-contract',
            'custom-policy-connections'
        ) -Message 'TC-PFL-021 child definitions.'
        Assert-Condition (@($execution.Contract.Checks | Where-Object { $_.childExit -ne 0 }).Count -eq 0) `
            'TC-PFL-021 all children must exit zero.'
    }
    finally {
        Remove-IsolatedRepository -Path $isolated
    }
}

function Test-CSimpleMandatory {
    $catalogSource = Join-Path $fixtureRoot 'TC-PFL-022-simple-missing-obs/config/project-lint-policies.json'
    $isolated = New-IsolatedRepository -CatalogSource $catalogSource -InitializeGit
    try {
        $execution = Invoke-IsolatedCheck -RepositoryRoot $isolated -CheckArguments @(
            '-Mode', 'Simple', '-Scope', 'Backend',
            '-FocusedUnitNotApplicableReason', 'custom-linter contract fixture'
        )
        Assert-Equal $execution.Process.ExitCode 1 'TC-PFL-022 C exit code.'
        $scopeFailure = @($execution.Contract.Checks | Where-Object Name -eq 'custom-policy-scope')
        Assert-Equal $scopeFailure.Count 1 'TC-PFL-022 scope check count.'
        Assert-Contains -Text ([string]$scopeFailure[0].Detail) `
            -Needle 'Simple scope omitted mandatory PF-OBS-001' `
            -Message 'TC-PFL-022 mandatory policy diagnostic.'
        Assert-Equal $execution.Contract.childExit 0 'TC-PFL-022 aggregate child exit remains zero for action failure.'
        $projectLint = @($execution.Contract.Checks | Where-Object Name -eq 'project-lint')
        Assert-Equal $projectLint.Count 1 'TC-PFL-022 project-lint result count.'
        Assert-Equal $projectLint[0].State 'Skipped' 'TC-PFL-022 dependent B check.'
    }
    finally {
        Remove-IsolatedRepository -Path $isolated
    }
}

function Test-CFullFrontend {
    $isolated = New-IsolatedRepository
    try {
        $execution = Invoke-IsolatedCheck -RepositoryRoot $isolated -CheckArguments @('-CiTask', 'FullFrontend')
        Assert-Equal $execution.Process.ExitCode 0 'TC-PFL-023 C exit code.'
        Assert-Equal $execution.Contract.Succeeded $true 'TC-PFL-023 aggregate success.'
        $lintInvocations = @(Get-InvocationMatches -Invocations $execution.Invocations -Pattern '^npm\|.*(?:^| )run lint(?: |$)')
        Assert-Equal $lintInvocations.Count 1 'TC-PFL-023 A invocation count.'
        $projectLintInvocations = @(Get-InvocationMatches -Invocations $execution.Invocations -Pattern '^pwsh\|.*project-lint\.ps1')
        Assert-Equal $projectLintInvocations.Count 1 'TC-PFL-023 B invocation count.'
        $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $baseCatalogPath).Hash
        $isolatedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $isolated 'config/project-lint-policies.json')).Hash
        Assert-Equal $isolatedHash $sourceHash 'TC-PFL-023 catalog hash.'
    }
    finally {
        Remove-IsolatedRepository -Path $isolated
    }

    $brokenA = New-IsolatedRepository
    try {
        $brokenCheck = New-BrokenFrontendConnectionCheckScript -RepositoryRoot $brokenA
        $execution = Invoke-IsolatedCheck -RepositoryRoot $brokenA -CheckScriptPath $brokenCheck `
            -CheckArguments @('-CiTask', 'FullFrontend')
        Assert-Equal $execution.Process.ExitCode 1 'TC-PFL-023 broken A C exit code.'
        Assert-Equal $execution.Contract.Succeeded $false 'TC-PFL-023 broken A aggregate success.'
        $connection = @($execution.Contract.Checks | Where-Object Name -eq 'custom-policy-connections')
        Assert-Equal $connection.Count 1 'TC-PFL-023 broken A connection result count.'
        Assert-Equal $connection[0].State 'Failed' 'TC-PFL-023 broken A connection state.'
        Assert-Equal $connection[0].Detail 'custom linter policy connection mismatch' `
            'TC-PFL-023 broken A connection diagnostic.'
    }
    finally {
        Remove-IsolatedRepository -Path $brokenA
    }

    $unknownPolicy = New-IsolatedRepository
    try {
        $catalogPath = Join-Path $unknownPolicy 'config/project-lint-policies.json'
        $catalog = Get-Content -Raw -Encoding UTF8 -LiteralPath $catalogPath | ConvertFrom-Json -Depth 100
        $catalog.policies = @($catalog.policies) + @([pscustomobject]@{ policyId = 'PF-FE-007'; targets = [pscustomobject]@{ include = @('frontend/src') } })
        Write-Utf8File -Path $catalogPath -Content ($catalog | ConvertTo-Json -Depth 100)
        $execution = Invoke-IsolatedCheck -RepositoryRoot $unknownPolicy -CheckArguments @('-CiTask', 'FullFrontend')
        Assert-Equal $execution.Process.ExitCode 1 'TC-PFL-023 unknown policy C exit code.'
        Assert-Equal $execution.Contract.Succeeded $false 'TC-PFL-023 unknown policy aggregate success.'
        $connection = @($execution.Contract.Checks | Where-Object Name -eq 'custom-policy-connections')
        Assert-Equal $connection.Count 1 'TC-PFL-023 unknown policy connection result count.'
        Assert-Equal $connection[0].State 'Failed' 'TC-PFL-023 unknown policy connection state.'
        Assert-Equal $connection[0].Detail 'custom linter policy connection mismatch' `
            'TC-PFL-023 unknown policy connection diagnostic.'
    }
    finally {
        Remove-IsolatedRepository -Path $unknownPolicy
    }
}

function Test-CFullBackendContract {
    $isolated = New-IsolatedRepository
    try {
        $execution = Invoke-IsolatedCheck -RepositoryRoot $isolated -CheckArguments @('-CiTask', 'FullBackend')
        Assert-Equal $execution.Process.ExitCode 0 'TC-PFL-024 C exit code.'
        Assert-Equal $execution.Contract.Succeeded $true 'TC-PFL-024 aggregate success.'
        $projectLintInvocations = @(Get-InvocationMatches -Invocations $execution.Invocations -Pattern '^pwsh\|.*project-lint\.ps1')
        Assert-Equal $projectLintInvocations.Count 1 'TC-PFL-024 B invocation count.'
        $endpointInvocations = @(Get-InvocationMatches -Invocations $execution.Invocations `
            -Pattern '^maven\|.*EndpointMetadataRegistryContractTest')
        Assert-Equal $endpointInvocations.Count 1 'TC-PFL-024 D invocation count.'
    }
    finally {
        Remove-IsolatedRepository -Path $isolated
    }
}

function Test-BaselineStageOrder {
    $manifestPath = Join-Path $fixtureRoot 'TC-PFL-074-baseline-stage-order/baseline-blobs.json'
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json -Depth 10
    Assert-Equal ([string]$manifest.fixedHead) $fixedHead 'TC-PFL-074 manifest fixed HEAD.'
    Assert-Equal @($manifest.files).Count 5 'TC-PFL-074 manifest file count.'
    Assert-SetEquals -Actual @($manifest.files | ForEach-Object { $_.path }) -Expected @(
        'backend/src/main/java/com/example/dailyreport/observability/RequestContext.java'
        'backend/src/main/java/com/example/dailyreport/observability/RequestMetadataInterceptor.java'
        'frontend/src/monthlySummary/MonthlySummaryPage.tsx'
        'frontend/src/dailyReport/DailyReportPendingApprovalList.tsx'
        'frontend/eslint.config.mjs'
    ) -Message 'TC-PFL-074 manifest baseline paths.'
    foreach ($entry in @($manifest.files)) {
        $blob = (git rev-parse "$fixedHead`:$($entry.path)").Trim()
        Assert-Equal $blob $entry.blob "TC-PFL-074 fixed HEAD blob for $($entry.path)."
    }

    Assert-Equal ([string]$manifest.evidenceStatus) 'notCaptured' 'TC-PFL-074 evidence status.'
    Assert-Equal ([string]$manifest.decision) 'hold' 'TC-PFL-074 decision.'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$manifest.reason)) `
        'TC-PFL-074 hold reason must be present.'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$manifest.recheckCondition)) `
        'TC-PFL-074 recheck condition must be present.'
    Assert-Contains -Text ([string]$manifest.reason) -Needle 'not captured' `
        -Message 'TC-PFL-074 hold reason must identify the missing artifact.'
    Assert-Contains -Text ([string]$manifest.recheckCondition) -Needle 'Stage 1' `
        -Message 'TC-PFL-074 recheck condition must start after Stage 1.'
    Assert-Contains -Text ([string]$manifest.recheckCondition) -Needle 'immutable artifact' `
        -Message 'TC-PFL-074 recheck condition must require an immutable artifact.'
    $evidenceText = @(
        [string]$manifest.evidenceStatus
        [string]$manifest.decision
        [string]$manifest.reason
        [string]$manifest.recheckCondition
    ) -join "`n"
    Assert-Condition ($evidenceText -notmatch '(?i)success|complete') `
        'TC-PFL-074 evidence metadata must not claim a completed success.'
    Assert-SetEquals -Actual @($manifest.postFixCaseIds) -Expected @(
        'TC-PFL-078', 'TC-PFL-079', 'TC-PFL-080', 'TC-PFL-081', 'TC-PFL-082'
    ) -Message 'TC-PFL-074 post-fix assertions must be isolated in TC-PFL-078..082.'
}

function Test-IgnoreStoreForbidden {
    $ignoreStore = Join-Path $fixtureRoot 'TC-PFL-075-ignore-store/ignore.json'
    Assert-Condition (-not (Test-Path -LiteralPath $ignoreStore -PathType Leaf)) `
        'TC-PFL-075 ignore store must not exist.'
    Assert-NotContains -Text (Get-Content -Raw -Encoding UTF8 $checkScript) `
        -Needle 'ignore store' -Message 'TC-PFL-075 check.ps1 must not introduce an ignore store.'
}

function Test-StageOrder {
    $isolated = New-IsolatedRepository
    try {
        $execution = Invoke-IsolatedCheck -RepositoryRoot $isolated -CheckArguments @('-Mode', 'Full') `
            -AdditionalEnvironment @{ PROJECTFOUNDATION_STAGE = '1'; PROJECTFOUNDATION_STAGE0_COMPLETE = 'false' }
        Assert-Equal $execution.Process.ExitCode 1 'TC-PFL-076 C exit code.'
        Assert-Equal $execution.Contract.Succeeded $false 'TC-PFL-076 aggregate success.'
        Assert-Equal $execution.Contract.code 'STAGE_ORDER_INVALID' 'TC-PFL-076 result code.'
        Assert-Contains -Text $execution.Process.Stdout -Needle 'STAGE_ORDER_INVALID' `
            -Message 'TC-PFL-076 diagnostic.'
    }
    finally {
        Remove-IsolatedRepository -Path $isolated
    }
}

function Test-StageCompletionMarkers {
    $fixturePath = Join-Path $fixtureRoot 'TC-PFL-120-stage-completion/stage.json'
    $fixture = Get-Content -Raw -Encoding UTF8 -LiteralPath $fixturePath | ConvertFrom-Json -Depth 10
    $expectedRequirements = @{
        stage1 = @('PROJECTFOUNDATION_STAGE0_COMPLETE')
        stage2 = @('PROJECTFOUNDATION_STAGE0_COMPLETE', 'PROJECTFOUNDATION_STAGE1_COMPLETE')
        stage3 = @('PROJECTFOUNDATION_STAGE0_COMPLETE', 'PROJECTFOUNDATION_STAGE1_COMPLETE', 'PROJECTFOUNDATION_STAGE2_COMPLETE')
        stage4 = @('PROJECTFOUNDATION_STAGE0_COMPLETE', 'PROJECTFOUNDATION_STAGE1_COMPLETE', 'PROJECTFOUNDATION_STAGE2_COMPLETE', 'PROJECTFOUNDATION_STAGE3_COMPLETE')
        stage5 = @('PROJECTFOUNDATION_STAGE0_COMPLETE', 'PROJECTFOUNDATION_STAGE1_COMPLETE', 'PROJECTFOUNDATION_STAGE2_COMPLETE', 'PROJECTFOUNDATION_STAGE3_COMPLETE', 'PROJECTFOUNDATION_STAGE4_COMPLETE')
    }
    foreach ($stageName in $expectedRequirements.Keys) {
        Assert-SetEquals -Actual @((Get-PostReviewProperty -Object $fixture -Name $stageName).requires) `
            -Expected $expectedRequirements[$stageName] -Message "TC-PFL-120 $stageName requirements."
    }

    $scenarios = @(
        [pscustomobject]@{ Stage = 0; CompleteThrough = -1; ExpectedExit = 0; MissingStage = $null }
        [pscustomobject]@{ Stage = 1; CompleteThrough = -1; ExpectedExit = 1; MissingStage = 0 }
        [pscustomobject]@{ Stage = 1; CompleteThrough = 0; ExpectedExit = 0; MissingStage = $null }
        [pscustomobject]@{ Stage = 2; CompleteThrough = 0; ExpectedExit = 1; MissingStage = 1 }
        [pscustomobject]@{ Stage = 2; CompleteThrough = 1; ExpectedExit = 0; MissingStage = $null }
        [pscustomobject]@{ Stage = 3; CompleteThrough = 0; ExpectedExit = 1; MissingStage = 1 }
        [pscustomobject]@{ Stage = 3; CompleteThrough = 2; ExpectedExit = 0; MissingStage = $null }
        [pscustomobject]@{ Stage = 4; CompleteThrough = 2; ExpectedExit = 1; MissingStage = 3 }
        [pscustomobject]@{ Stage = 4; CompleteThrough = 3; ExpectedExit = 0; MissingStage = $null }
        [pscustomobject]@{ Stage = 5; CompleteThrough = 3; ExpectedExit = 1; MissingStage = 4 }
        [pscustomobject]@{ Stage = 5; CompleteThrough = 4; ExpectedExit = 0; MissingStage = $null }
    )
    foreach ($scenario in $scenarios) {
        $environment = @{
            PROJECTFOUNDATION_STAGE = [string]$scenario.Stage
            PROJECTFOUNDATION_STAGE0_COMPLETE = 'false'
            PROJECTFOUNDATION_STAGE1_COMPLETE = 'false'
            PROJECTFOUNDATION_STAGE2_COMPLETE = 'false'
            PROJECTFOUNDATION_STAGE3_COMPLETE = 'false'
            PROJECTFOUNDATION_STAGE4_COMPLETE = 'false'
        }
        for ($completedStage = 0; $completedStage -le $scenario.CompleteThrough; $completedStage++) {
            $environment["PROJECTFOUNDATION_STAGE${completedStage}_COMPLETE"] = 'true'
        }
        $isolated = New-IsolatedRepository
        try {
            $execution = Invoke-IsolatedCheck -RepositoryRoot $isolated -CheckArguments @('-Mode', 'Full') `
                -AdditionalEnvironment $environment
            Assert-Equal $execution.Process.ExitCode $scenario.ExpectedExit `
                "TC-PFL-120 Stage $($scenario.Stage) process exit."
            Assert-Equal $execution.Contract.Succeeded ($scenario.ExpectedExit -eq 0) `
                "TC-PFL-120 Stage $($scenario.Stage) contract success."
            if ($null -ne $scenario.MissingStage) {
                Assert-Contains -Text $execution.Process.Stdout `
                    -Needle "Stage $($scenario.MissingStage) must complete before Stage $($scenario.Stage)" `
                    -Message "TC-PFL-120 Stage $($scenario.Stage) missing prerequisite diagnostic."
                Assert-Equal $execution.Contract.code 'STAGE_ORDER_INVALID' `
                    "TC-PFL-120 Stage $($scenario.Stage) result code."
            }
        }
        finally {
            Remove-IsolatedRepository -Path $isolated
        }
    }
}

function Test-QuickPrePushUnchanged {
    $scenarios = @(
        [pscustomobject]@{ Name = 'quick-pf-fe-001-only'; Mode = 'Quick'; ConfigChanged = $false; BaseViolation = $false }
        [pscustomobject]@{ Name = 'quick-ignored-lint-fixture'; Mode = 'Quick'; ConfigChanged = $false; BaseViolation = $false; IgnoredFixture = $true }
        [pscustomobject]@{ Name = 'quick-base-eslint'; Mode = 'Quick'; ConfigChanged = $false; BaseViolation = $true }
        [pscustomobject]@{ Name = 'pre-push-pf-fe-001-only'; Mode = 'PrePush'; ConfigChanged = $true; BaseViolation = $false }
        [pscustomobject]@{ Name = 'pre-push-base-eslint'; Mode = 'PrePush'; ConfigChanged = $true; BaseViolation = $true }
    )

    foreach ($scenario in $scenarios) {
        $isolated = New-IsolatedRepository -InitializeGit
        try {
            $fixturePath = if ($scenario.IgnoredFixture) {
                'frontend/test/lint/fixtures/TC-PFL-077-ignored-fixture.ts'
            }
            elseif ($scenario.BaseViolation) {
                'frontend/src/TC-PFL-077-base-eslint.tsx'
            }
            else {
                'frontend/src/TC-PFL-077-pf-fe-001-only.tsx'
            }
            $fixtureContent = if ($scenario.BaseViolation) {
                "// TC-PFL-077-BASE-ESLINT-VIOLATION`nexport const baseLintViolation = missingBaseGlobal;`n"
            }
            elseif ($scenario.IgnoredFixture) {
                "export const ignoredLintFixture = () => 'TC-PFL-077';`n"
            }
            else {
                "export const pfFe001Only = () => fetch('/api/orders');`n"
            }
            Write-Utf8File -Path (Join-Path $isolated $fixturePath) -Content $fixtureContent
            if ($scenario.ConfigChanged) {
                Write-Utf8File -Path (Join-Path $isolated 'frontend/eslint.config.mjs') -Content "export default [];`n"
            }

            if ($scenario.Mode -eq 'Quick') {
                & git -C $isolated add -- $fixturePath
                if ($LASTEXITCODE -ne 0) { throw "TC-PFL-077 $($scenario.Name) could not stage fixture." }
                $execution = Invoke-IsolatedCheck -RepositoryRoot $isolated -CheckArguments @('-Mode', 'Quick')
                Assert-SetEquals -Actual @($execution.Contract.Checks | ForEach-Object Name) -Expected @(
                    'staged-whitespace', 'staged-artifacts', 'frontend-staged-lint', 'staged-secrets'
                ) -Message "TC-PFL-077 $($scenario.Name) Quick command list."
            }
            else {
                & git -C $isolated add -- frontend
                if ($LASTEXITCODE -ne 0) { throw "TC-PFL-077 $($scenario.Name) could not stage fixture." }
                & git -C $isolated commit -q -m fixture
                if ($LASTEXITCODE -ne 0) { throw "TC-PFL-077 $($scenario.Name) could not commit fixture." }
                $baseSha = (& git -C $isolated rev-parse HEAD^).Trim()
                $localSha = (& git -C $isolated rev-parse HEAD).Trim()
                $pushInput = "refs/heads/main $localSha refs/remotes/origin/main $baseSha"
                $execution = Invoke-IsolatedCheck -RepositoryRoot $isolated -CheckArguments @(
                    '-Mode', 'PrePush', '-PushInput', $pushInput
                )
                Assert-SetEquals -Actual @($execution.Contract.Checks | ForEach-Object Name) -Expected @(
                    'pre-push-diff-check', 'pre-push-artifact-check', 'pre-push-secrets', 'frontend-pre-push-lint'
                ) -Message "TC-PFL-077 $($scenario.Name) PrePush command list."
            }

            $eslintInvocations = @(Get-InvocationMatches -Invocations $execution.Invocations -Pattern '^npm\|.*(?:^| )eslint(?: |$)')
            Assert-Equal $eslintInvocations.Count 1 "TC-PFL-077 $($scenario.Name) raw ESLint invocation count."
            Assert-Contains -Text $eslintInvocations[0] -Needle 'frontend/no-direct-transport-access:off' `
                -Message "TC-PFL-077 $($scenario.Name) PF-FE-001 override."
            Assert-Contains -Text $eslintInvocations[0] -Needle 'frontend/module-matrix:off' `
                -Message "TC-PFL-077 $($scenario.Name) PF-FE-002 override."
            if ($scenario.Mode -eq 'Quick') {
                Assert-Contains -Text $eslintInvocations[0] -Needle '--no-warn-ignored' `
                    -Message "TC-PFL-077 $($scenario.Name) ignored staged fixture handling."
            }
            else {
                Assert-NotContains -Text $eslintInvocations[0] -Needle '--no-warn-ignored' `
                    -Message "TC-PFL-077 $($scenario.Name) pre-push base lint options."
            }
            Assert-NotContains -Text $eslintInvocations[0] -Needle 'run lint' `
                -Message "TC-PFL-077 $($scenario.Name) wrapper invocation."
            Assert-NotContains -Text $eslintInvocations[0] -Needle 'frontend-lint.mjs' `
                -Message "TC-PFL-077 $($scenario.Name) custom wrapper invocation."
            if ($scenario.ConfigChanged) {
                Assert-Contains -Text $eslintInvocations[0] -Needle 'eslint .' `
                    -Message "TC-PFL-077 $($scenario.Name) full frontend target."
            }
            elseif ($scenario.IgnoredFixture) {
                Assert-Contains -Text $eslintInvocations[0] -Needle 'test/lint/fixtures/TC-PFL-077-ignored-fixture.ts' `
                    -Message "TC-PFL-077 $($scenario.Name) ignored fixture target."
            }
            else {
                Assert-Contains -Text $eslintInvocations[0] -Needle 'src/TC-PFL-077-' `
                    -Message "TC-PFL-077 $($scenario.Name) changed-file target."
            }

            if ($scenario.BaseViolation) {
                Assert-Equal $execution.Process.ExitCode 1 "TC-PFL-077 $($scenario.Name) base ESLint exit code."
                Assert-Equal $execution.Contract.Succeeded $false "TC-PFL-077 $($scenario.Name) base ESLint success."
                $lintFailure = @($execution.Contract.Checks | Where-Object Name -eq $(if ($scenario.Mode -eq 'Quick') { 'frontend-staged-lint' } else { 'frontend-pre-push-lint' }))
                Assert-Equal $lintFailure.Count 1 "TC-PFL-077 $($scenario.Name) base ESLint result count."
                Assert-Equal $lintFailure[0].State 'Failed' "TC-PFL-077 $($scenario.Name) base ESLint state."
                Assert-Equal $lintFailure[0].childExit 1 "TC-PFL-077 $($scenario.Name) base ESLint child exit."
            }
            else {
                Assert-Equal $execution.Process.ExitCode 0 "TC-PFL-077 $($scenario.Name) PF-FE-001-only exit code."
                Assert-Equal $execution.Contract.Succeeded $true "TC-PFL-077 $($scenario.Name) PF-FE-001-only success."
            }
            Assert-Equal @(Get-InvocationMatches -Invocations $execution.Invocations -Pattern 'project-lint\.ps1').Count 0 `
                "TC-PFL-077 $($scenario.Name) must not invoke custom policy."
        }
        finally {
            Remove-IsolatedRepository -Path $isolated
        }
    }
}

function Test-RealRepositoryZero {
    $frontend = Invoke-ExternalCommand -FileName 'npm.cmd' -Arguments @(
        '--prefix', 'frontend', 'run', '--silent', 'lint'
    )
    Assert-Equal $frontend.ExitCode 0 'TC-PFL-083 A exit code.'
    Assert-Equal $frontend.Stdout '' 'TC-PFL-083 A stdout.'
    Assert-Equal $frontend.Stderr '' 'TC-PFL-083 A stderr.'

    $backend = Invoke-ExternalCommand -FileName 'pwsh' -Arguments @(
        '-NoProfile', '-File', (Join-Path $repoRoot 'scripts/project-lint.ps1'),
        '-RepositoryRoot', $repoRoot, '-Format', 'Text'
    )
    Assert-Equal $backend.ExitCode 0 'TC-PFL-083 B exit code.'
    Assert-Equal $backend.Stdout '' 'TC-PFL-083 B stdout.'
    Assert-Equal $backend.Stderr '' 'TC-PFL-083 B stderr.'

    $d = Invoke-ExternalCommand -FileName (Join-Path $repoRoot 'backend/mvnw.cmd') -Arguments @(
        '-f', 'backend/pom.xml', '-s', 'backend/local-maven-settings.xml',
        '-B', '-Dtest=EndpointMetadataRegistryContractTest', 'test'
    ) -Environment @{
        MAVEN_OPTS = "-Dmaven.repo.local=$(Join-Path $env:USERPROFILE '.m2/repository')"
    }
    Assert-Equal $d.ExitCode 0 'TC-PFL-083 D exit code.'
    Assert-Contains -Text $d.Stdout -Needle 'Failures: 0' -Message 'TC-PFL-083 D failures.'
    Assert-Contains -Text $d.Stdout -Needle 'Errors: 0' -Message 'TC-PFL-083 D errors.'
    Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'config/project-lint-ignore.json'))) `
        'TC-PFL-083 ignore store must not be present.'
}

function Test-StandardsRecord {
    $documents = @(
        'docs/AI活用開発研究/作業記録/カスタムLinter_実装計画.md'
        'docs/AI活用開発研究/作業記録/カスタムLinter_テストケース.md'
        'docs/AI活用開発研究/作業記録/カスタムLinter_実装前レビュー.md'
        'docs/AI活用開発研究/作業記録/カスタムLinter_統合品質記録.md'
        'docs/AI活用開発研究/設計判断記録/ADR-PFL-001-静的解析の統一入口と責務分担.md'
    )
    $policyIds = @('PF-GATE-001', 'PF-FE-001', 'PF-FE-002', 'PF-TEST-001', 'PF-SUPPRESS-001', 'PF-OBS-001')
    $baselineIds = @('FIND-PFL-BASE-001', 'FIND-PFL-BASE-002', 'FIND-PFL-BASE-003', 'FIND-PFL-BASE-004', 'FIND-PFL-BASE-005')
    foreach ($document in $documents) {
        $text = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot $document)
        foreach ($policyId in $policyIds) {
            Assert-Contains -Text $text -Needle $policyId -Message "TC-PFL-084 $document policy ID."
        }
        foreach ($baselineId in $baselineIds) {
            Assert-Contains -Text $text -Needle $baselineId -Message "TC-PFL-084 $document baseline ID."
        }
        Assert-Condition ($text -match '(?is)scope.{0,80}matrix') "TC-PFL-084 $document scope matrix."
        Assert-Contains -Text $text -Needle 'Stage 0' -Message "TC-PFL-084 $document Stage 0."
        Assert-Condition ($text.Contains('Stage 5') -or $text.Contains('| 5 |')) `
            "TC-PFL-084 $document Stage 5."
    }
}

function Get-PostReviewProperty {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    $property.Value
}

function Get-PostReviewExpectedArtifactPaths {
    @(
        'docs/AI活用開発研究/作業記録/カスタムLinter_実装後レビュー.md'
        'docs/AI活用開発研究/作業記録/カスタムLinter_テストケース.md'
        'docs/AI活用開発研究/作業記録/カスタムLinter_統合品質記録.md'
        'docs/AI活用開発研究/作業記録/カスタムLinter_作業記録.md'
        'docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md'
    )
}

function Get-PostReviewExpectedSourcePaths {
    # Keep this list explicit and ordered. The evidence must bind every
    # execution record to the exact implementation and test bytes it covered;
    # a broad glob would make an added or reordered source file invisible.
    @(
        'docs/AI活用開発研究/作業記録/カスタムLinter_実装後レビュー.md'
        'docs/AI活用開発研究/作業記録/カスタムLinter_テストケース.md'
        'docs/AI活用開発研究/作業記録/カスタムLinter_統合品質記録.md'
        'docs/AI活用開発研究/作業記録/カスタムLinter_作業記録.md'
        'docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md'
        'scripts/check.ps1'
        'scripts/check.contract.tests.ps1'
        'scripts/project-lint.ps1'
        'scripts/project-lint.tests.ps1'
        'frontend/eslint-rules/index.mjs'
        'frontend/scripts/frontend-lint.mjs'
        'frontend/test/lint/baselineSuppression.test.ts'
        'frontend/test/lint/frontendLint.cli.test.ts'
        'frontend/test/lint/frontendLint.integration.test.ts'
        'frontend/test/lint/moduleMatrix.config.test.ts'
        'frontend/test/lint/noDirectTransport.rule.test.ts'
        'frontend/test/lint/suppressionPolicy.test.ts'
        'backend/src/main/java/com/example/dailyreport/observability/EndpointMetadataRegistry.java'
        'backend/src/test/java/com/example/dailyreport/observability/EndpointMetadataRegistryContractTest.java'
    )
}

function Get-PostReviewExpectedAdditionalIds {
    [ordered]@{
        lunaFindings = @(
            'FIND-LUNA-P0-001'
            'FIND-LUNA-P1-001'
            'FIND-LUNA-P1-003'
            'FIND-LUNA-P1-004'
        )
    }
}

function Get-PostReviewExpectedRangeDefinitions {
    [ordered]@{
        acceptance = [pscustomobject]@{ Prefix = 'AC-PFL-'; Start = 1; End = 9 }
        testCases = [pscustomobject]@{ Prefix = 'TC-PFL-'; Start = 1; End = 105 }
        runtimeTests = [pscustomobject]@{ Prefix = 'RT-PFL-'; Start = 1; End = 105 }
        baselineFindings = [pscustomobject]@{ Prefix = 'FIND-PFL-BASE-'; Start = 1; End = 5 }
        postReviewFindings = [pscustomobject]@{ Prefix = 'FIND-PFL-P1R-'; Start = 1; End = 13 }
    }
}

function Get-PostReviewRangeIds {
    param([Parameter(Mandatory)][object]$Range)

    $ids = [System.Collections.Generic.List[string]]::new()
    for ($number = [int]$Range.Start; $number -le [int]$Range.End; $number++) {
        [void]$ids.Add(('{0}{1:D3}' -f $Range.Prefix, $number))
    }
    $ids.ToArray()
}

function Split-PostReviewTableCells {
    param([Parameter(Mandatory)][string]$Line)

    $trimmed = $Line.Trim()
    if (-not $trimmed.StartsWith('|')) {
        return @()
    }
    $body = $trimmed.Substring(1)
    if ($body.EndsWith('|')) {
        $body = $body.Substring(0, $body.Length - 1)
    }
    $cells = [System.Collections.Generic.List[string]]::new()
    $cell = [System.Text.StringBuilder]::new()
    $inCodeSpan = $false
    for ($index = 0; $index -lt $body.Length; $index++) {
        $character = $body[$index]
        if ($character -eq '`') {
            $inCodeSpan = -not $inCodeSpan
            [void]$cell.Append($character)
            continue
        }
        if ($character -eq '\' -and $index + 1 -lt $body.Length -and $body[$index + 1] -eq '|') {
            [void]$cell.Append('|')
            $index++
            continue
        }
        if ($character -eq '|' -and -not $inCodeSpan) {
            [void]$cells.Add($cell.ToString().Trim())
            $null = $cell.Clear()
            continue
        }
        [void]$cell.Append($character)
    }
    [void]$cells.Add($cell.ToString().Trim())
    $cells.ToArray()
}

function Get-PostReviewTraceTable {
    param([Parameter(Mandatory)][string]$Text)

    $lines = $Text -split "`r?`n"
    for ($headerIndex = 0; $headerIndex -lt $lines.Count; $headerIndex++) {
        $line = $lines[$headerIndex]
        if ($line -notmatch '^\s*\|.*\bTC ID' -or
            $line -notmatch '\bRT ID' -or
            $line -notmatch '(?i)status') {
            continue
        }
        $header = @(Split-PostReviewTableCells -Line $line)
        $rows = [System.Collections.Generic.List[object]]::new()
        for ($rowIndex = $headerIndex + 1; $rowIndex -lt $lines.Count; $rowIndex++) {
            $rowLine = $lines[$rowIndex]
            if ([string]::IsNullOrWhiteSpace($rowLine) -or $rowLine.TrimStart().StartsWith('#')) {
                break
            }
            if (-not $rowLine.TrimStart().StartsWith('|')) {
                break
            }
            if ($rowLine -match '^\s*\|[\s\-:|]+\|?\s*$') {
                continue
            }
            $cells = @(Split-PostReviewTableCells -Line $rowLine)
            if ($cells.Count -gt 0) {
                [void]$rows.Add($cells)
            }
        }
        return [pscustomobject]@{
            Header = $header
            Rows = $rows.ToArray()
        }
    }
    $null
}

function Get-PostReviewColumnIndex {
    param(
        [Parameter(Mandatory)][object[]]$Header,
        [Parameter(Mandatory)][string]$Pattern
    )

    for ($index = 0; $index -lt $Header.Count; $index++) {
        if ([string]$Header[$index] -match $Pattern) {
            return $index
        }
    }
    -1
}

function Get-PostReviewCell {
    param(
        [Parameter(Mandatory)][object[]]$Row,
        [int]$Index
    )

    if ($Index -lt 0 -or $Index -ge $Row.Count) {
        return ''
    }
    [string]$Row[$Index]
}

function Get-PostReviewIdCell {
    param(
        [Parameter(Mandatory)][object[]]$Row,
        [int]$Index,
        [Parameter(Mandatory)][string]$Prefix
    )

    $cell = Get-PostReviewCell -Row $Row -Index $Index
    $pattern = '(?<![A-Za-z0-9_-])' + [regex]::Escape($Prefix) + '\d{3}(?![A-Za-z0-9_-])'
    $matches = [regex]::Matches($cell, $pattern)
    if ($matches.Count -eq 1) {
        return $matches[0].Value
    }
    $cell.Trim()
}

function Get-PostReviewTraceViolations {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string[]]$ExpectedTestCaseIds
    )

    $violations = [System.Collections.Generic.List[string]]::new()
    $table = Get-PostReviewTraceTable -Text $Text
    if ($null -eq $table) {
        [void]$violations.Add("$Label canonical TC/RT table is missing")
        return $violations.ToArray()
    }

    $tcIndex = Get-PostReviewColumnIndex -Header $table.Header -Pattern '(?i)^TC\s*ID'
    $rtIndex = Get-PostReviewColumnIndex -Header $table.Header -Pattern '(?i)^RT\s*ID'
    $locatorIndex = Get-PostReviewColumnIndex -Header $table.Header -Pattern '(?i)(test\s+path|canonical\s+test|test\s+name|function|spec)'
    $commandIndex = Get-PostReviewColumnIndex -Header $table.Header -Pattern '(?i)^command$|\bcommand\b'
    $statusIndex = Get-PostReviewColumnIndex -Header $table.Header -Pattern '(?i)^status$|\bstatus\b'

    if ($tcIndex -lt 0) { [void]$violations.Add("$Label canonical TC/RT table is missing TC ID column") }
    if ($rtIndex -lt 0) { [void]$violations.Add("$Label canonical TC/RT table is missing RT ID column") }
    if ($locatorIndex -lt 0) { [void]$violations.Add("$Label canonical TC/RT table is missing implementation reference column") }
    if ($commandIndex -lt 0) { [void]$violations.Add("$Label canonical TC/RT table is missing command column") }
    if ($statusIndex -lt 0) { [void]$violations.Add("$Label canonical TC/RT table is missing result status column") }

    if ($table.Rows.Count -ne $ExpectedTestCaseIds.Count) {
        [void]$violations.Add("$Label canonical TC/RT row count is $($table.Rows.Count), expected $($ExpectedTestCaseIds.Count)")
    }

    if ($tcIndex -ge 0) {
        $tcIds = @($table.Rows | ForEach-Object {
                Get-PostReviewIdCell -Row $_ -Index $tcIndex -Prefix 'TC-PFL-'
            })
        $uniqueTcIds = @($tcIds | Sort-Object -Unique)
        if ($uniqueTcIds.Count -ne $ExpectedTestCaseIds.Count) {
            [void]$violations.Add("$Label canonical TC ID unique count is $($uniqueTcIds.Count), expected $($ExpectedTestCaseIds.Count)")
        }
        foreach ($testCaseId in $ExpectedTestCaseIds) {
            $count = @($tcIds | Where-Object { $_ -eq $testCaseId }).Count
            if ($count -eq 0) {
                [void]$violations.Add("$Label missing $testCaseId")
            }
            elseif ($count -ne 1) {
                [void]$violations.Add("$Label duplicate $testCaseId count=$count")
            }
        }
        foreach ($unexpectedId in @($uniqueTcIds | Where-Object { $ExpectedTestCaseIds -notcontains $_ })) {
            [void]$violations.Add("$Label unexpected TC ID $unexpectedId")
        }
    }

    if ($rtIndex -ge 0) {
        $expectedRuntimeTestIds = @($ExpectedTestCaseIds | ForEach-Object {
                [string]$_ -replace '^TC-PFL-', 'RT-PFL-'
            })
        $rtIds = @($table.Rows | ForEach-Object {
                Get-PostReviewIdCell -Row $_ -Index $rtIndex -Prefix 'RT-PFL-'
            })
        $uniqueRtIds = @($rtIds | Sort-Object -Unique)
        if ($uniqueRtIds.Count -ne $expectedRuntimeTestIds.Count) {
            [void]$violations.Add("$Label canonical RT ID unique count is $($uniqueRtIds.Count), expected $($expectedRuntimeTestIds.Count)")
        }
        foreach ($runtimeTestId in $expectedRuntimeTestIds) {
            $count = @($rtIds | Where-Object { $_ -eq $runtimeTestId }).Count
            if ($count -eq 0) {
                [void]$violations.Add("$Label missing $runtimeTestId")
            }
            elseif ($count -ne 1) {
                [void]$violations.Add("$Label duplicate $runtimeTestId count=$count")
            }
        }
        foreach ($unexpectedId in @($uniqueRtIds | Where-Object { $expectedRuntimeTestIds -notcontains $_ })) {
            [void]$violations.Add("$Label unexpected RT ID $unexpectedId")
        }
    }

    $badLocatorCount = 0
    $badCommandCount = 0
    $badStatusCount = 0
    foreach ($row in @($table.Rows)) {
        $testCaseId = Get-PostReviewIdCell -Row $row -Index $tcIndex -Prefix 'TC-PFL-'
        $rowText = ($row -join ' | ')
        if ($locatorIndex -ge 0) {
            $locator = Get-PostReviewCell -Row $row -Index $locatorIndex
            if ([string]::IsNullOrWhiteSpace($locator) -or
                $locator -notmatch '(?i)\.(ps1|psm1|java|ts|tsx|js|mjs|cs|py)\b') {
                $badLocatorCount++
            }
        }
        if ($commandIndex -ge 0) {
            $command = Get-PostReviewCell -Row $row -Index $commandIndex
            if ([string]::IsNullOrWhiteSpace($command) -or $command -notmatch '(?i)\b(pwsh|npm|mvnw?)\b') {
                $badCommandCount++
            }
        }
        if ($statusIndex -ge 0) {
            $status = Get-PostReviewCell -Row $row -Index $statusIndex
            if ($status -notmatch '(?i)^\s*(PASS|HOLD)\b') {
                $badStatusCount++
            }
        }
        if ($tcIndex -ge 0 -and $rtIndex -ge 0 -and $testCaseId -match '^TC-PFL-(\d{3})$') {
            $expectedRuntimeId = 'RT-PFL-' + $Matches[1]
            $actualRuntimeId = Get-PostReviewCell -Row $row -Index $rtIndex
            if ($actualRuntimeId -ne $expectedRuntimeId) {
                [void]$violations.Add("$Label $testCaseId must map to $expectedRuntimeId")
            }
        }
    }
    if ($badLocatorCount -gt 0) { [void]$violations.Add("$Label trace rows missing implementation references count=$badLocatorCount") }
    if ($badCommandCount -gt 0) { [void]$violations.Add("$Label trace rows missing executable commands count=$badCommandCount") }
    if ($badStatusCount -gt 0) {
        [void]$violations.Add("$Label trace rows missing PASS/HOLD result status count=$badStatusCount")
    }
    $holdRows = @()
    if ($statusIndex -ge 0) {
        $holdRows = @($table.Rows | Where-Object {
                (Get-PostReviewCell -Row $_ -Index $statusIndex) -match '(?i)^\s*HOLD\b'
            })
    }
    if ($holdRows.Count -gt 0 -and $Text -notmatch '(?i)(reason|理由)') {
        [void]$violations.Add("$Label HOLD status requires a reason in the same document")
    }
    if ($holdRows.Count -gt 0 -and $Text -notmatch '(?i)(recheck|再確認)') {
        [void]$violations.Add("$Label HOLD status requires a recheck condition in the same document")
    }
    [string[]]$violations.ToArray()
}

function Get-PostReviewTraceRows {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Text
    )

    $table = Get-PostReviewTraceTable -Text $Text
    if ($null -eq $table) {
        return @()
    }
    $tcIndex = Get-PostReviewColumnIndex -Header $table.Header -Pattern '(?i)^TC\s*ID'
    $rtIndex = Get-PostReviewColumnIndex -Header $table.Header -Pattern '(?i)^RT\s*ID'
    $locatorIndex = Get-PostReviewColumnIndex -Header $table.Header -Pattern '(?i)(test\s+path|canonical\s+test|test\s+name|function|spec)'
    $commandIndex = Get-PostReviewColumnIndex -Header $table.Header -Pattern '(?i)^command$|\bcommand\b'
    $statusIndex = Get-PostReviewColumnIndex -Header $table.Header -Pattern '(?i)^status$|\bstatus\b'
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($row in @($table.Rows)) {
        [void]$rows.Add([pscustomobject][ordered]@{
                Label = $Label
                CaseId = if ($tcIndex -ge 0) {
                    Get-PostReviewIdCell -Row $row -Index $tcIndex -Prefix 'TC-PFL-'
                }
                else { '' }
                RuntimeId = if ($rtIndex -ge 0) {
                    Get-PostReviewIdCell -Row $row -Index $rtIndex -Prefix 'RT-PFL-'
                }
                else { '' }
                RawText = ($row -join ' | ')
                Locator = Get-PostReviewCell -Row $row -Index $locatorIndex
                Command = Get-PostReviewCell -Row $row -Index $commandIndex
                Status = Get-PostReviewCell -Row $row -Index $statusIndex
            })
    }
    $rows.ToArray()
}

function Get-PostReviewLocatorSegments {
    param([Parameter(Mandatory)][string]$Locator)

    $segments = [System.Collections.Generic.List[object]]::new()
    foreach ($rawSegment in ($Locator -split '(?i)<br\s*/?>|;|\r?\n')) {
        $segment = $rawSegment.Trim().Trim('`')
        if ([string]::IsNullOrWhiteSpace($segment)) {
            continue
        }
        $match = [regex]::Match($segment,
            '^(?<path>[^`<>\s;|]+?\.(?i:ps1|psm1|java|ts|tsx|js|mjs|cs|py))(?:::(?<symbol>.*))?$')
        if ($match.Success) {
            [void]$segments.Add([pscustomobject][ordered]@{
                    Raw = $segment
                    Path = $match.Groups['path'].Value
                    HasSymbolSyntax = $match.Groups['symbol'].Success
                    Symbol = if ($match.Groups['symbol'].Success) {
                        $match.Groups['symbol'].Value.Trim().Trim('`')
                    }
                    else { '' }
                })
        }
        else {
            [void]$segments.Add([pscustomobject][ordered]@{
                    Raw = $segment
                    Path = ''
                    HasSymbolSyntax = $false
                    Symbol = ''
                })
        }
    }
    $segments.ToArray()
}

function Resolve-PostReviewRepositoryPath {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Path
    )

    $normalized = $Path.Trim().Replace('\', '/')
    while ($normalized.StartsWith('./', [System.StringComparison]::Ordinal)) {
        $normalized = $normalized.Substring(2)
    }
    if ([string]::IsNullOrWhiteSpace($normalized) -or
        [System.IO.Path]::IsPathRooted($normalized) -or
        $normalized -match '^[A-Za-z]:($|/)' -or
        $normalized -match '(^|/)\.\.(/|$)') {
        return $null
    }
    try {
        $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $root $normalized))
        $rootPrefix = $root.TrimEnd([char]'\', [char]'/') + [System.IO.Path]::DirectorySeparatorChar
        if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $null
        }
        [pscustomobject][ordered]@{
            RelativePath = $normalized
            FullPath = $fullPath
        }
    }
    catch {
        $null
    }
}

function Get-PostReviewCaseSymbolToken {
    param([Parameter(Mandatory)][string]$CaseId)

    if ($CaseId -match '^TC-PFL-(\d{3})$') {
        return "tcPfl$($Matches[1])"
    }
    ''
}

function Test-PostReviewFileContainsCase {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$CaseId
    )

    $literal = [regex]::Escape($CaseId)
    $symbolToken = [regex]::Escape((Get-PostReviewCaseSymbolToken -CaseId $CaseId))
    $Text -match $literal -or
        (-not [string]::IsNullOrWhiteSpace($symbolToken) -and $Text -match "(?i)$symbolToken")
}

function Get-PostReviewPowerShellFunctionBody {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Name
    )

    $pattern = '(?ms)^\s*function\s+' + [regex]::Escape($Name) + '\b.*?(?=^\s*function\s+|\z)'
    $match = [regex]::Match($Text, $pattern)
    if ($match.Success) { return $match.Value }
    ''
}

function Get-PostReviewSymbolDefinitionViolation {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$SourceText,
        [Parameter(Mandatory)][string]$Symbol,
        [Parameter(Mandatory)][string]$CaseId
    )

    $trimmedSymbol = $Symbol.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedSymbol)) {
        return 'locator symbol is required and cannot be empty'
    }
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -in @('.ps1', '.psm1')) {
        $selector = [regex]::Match($trimmedSymbol,
            '^(?<name>[A-Za-z_][A-Za-z0-9_$-]*)(?:\[(?<case>TC-PFL-\d{3})\])?$')
        if (-not $selector.Success) {
            return "locator symbol is not a PowerShell function selector: $trimmedSymbol"
        }
        $name = $selector.Groups['name'].Value
        $functionBody = Get-PostReviewPowerShellFunctionBody -Text $SourceText -Name $name
        if ([string]::IsNullOrWhiteSpace($functionBody)) {
            return "locator symbol does not exist as a PowerShell function: $name"
        }
        if ($selector.Groups['case'].Success) {
            $selectorCaseId = $selector.Groups['case'].Value.ToUpperInvariant()
            if ($selectorCaseId -ne $CaseId.ToUpperInvariant()) {
                return "locator case mismatch: $selectorCaseId"
            }
            if ($functionBody -notmatch [regex]::Escape($selectorCaseId)) {
                return "locator case selector is not implemented by $($name): $selectorCaseId"
            }
        }
        elseif ($functionBody -notmatch [regex]::Escape($CaseId)) {
            return "locator symbol is not bound to case $($CaseId): $name"
        }
        return ''
    }

    if ($extension -eq '.java') {
        $selector = [regex]::Match($trimmedSymbol,
            '^(?<name>[A-Za-z_$][A-Za-z0-9_$]*)(?:\s*\(\s*\))?$')
        if (-not $selector.Success) {
            return "locator symbol is not a Java method selector: $trimmedSymbol"
        }
        $name = $selector.Groups['name'].Value
        $methodPattern = '(?m)^\s*(?:(?:public|protected|private|static|final|synchronized|default)\s+)*(?:[A-Za-z_$][A-Za-z0-9_$<>\[\],.?]*\s+)+' +
            [regex]::Escape($name) + '\s*\('
        $methodLine = @($SourceText -split '\r?\n' | Where-Object {
                $_ -notmatch '^\s*(?://|/\*|\*)' -and $_ -match $methodPattern
            })
        if ($methodLine.Count -eq 0) {
            return "locator symbol does not exist as a Java method: $name"
        }
        $expectedToken = Get-PostReviewCaseSymbolToken -CaseId $CaseId
        if (-not $name.StartsWith($expectedToken, [System.StringComparison]::OrdinalIgnoreCase)) {
            return "locator symbol is not bound to case $($CaseId): $name"
        }
        return ''
    }

    if ($extension -in @('.ts', '.tsx', '.js', '.mjs')) {
        $selector = [regex]::Match($trimmedSymbol,
            '(?i)^(?<name>it|test|describe)\s*\(')
        if (-not $selector.Success) {
            return "locator symbol is not a test selector: $trimmedSymbol"
        }
        $selectorCaseIds = @([regex]::Matches($trimmedSymbol, '(?i)TC-PFL-\d{3}') |
            ForEach-Object { $_.Value.ToUpperInvariant() } | Sort-Object -Unique)
        if ($selectorCaseIds.Count -ne 1 -or $selectorCaseIds[0] -ne $CaseId.ToUpperInvariant()) {
            return "locator case selector does not match $($CaseId): $trimmedSymbol"
        }
        $testName = $selector.Groups['name'].Value
        $casePattern = '(?im)^\s*' + [regex]::Escape($testName) +
            '\s*\(\s*["''`]\s*' + [regex]::Escape($CaseId) + '(?:\s|["''`])'
        if ($SourceText -notmatch $casePattern) {
            return "locator symbol does not exist as a test selector for $($CaseId): $testName"
        }
        return ''
    }

    return "locator symbol language is unsupported for source path: $Path"
}

function Get-PostReviewTraceContentViolations {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string[]]$ExpectedTestCaseIds
    )

    $violations = [System.Collections.Generic.List[string]]::new()
    $rows = @(Get-PostReviewTraceRows -Label $Label -Text $Text)
    foreach ($row in $rows) {
        if ($ExpectedTestCaseIds -notcontains $row.CaseId) {
            continue
        }
        $segments = @(Get-PostReviewLocatorSegments -Locator ([string]$row.Locator))
        if ($segments.Count -eq 0) {
            [void]$violations.Add("$Label $($row.CaseId) locator has no repository-relative path")
            continue
        }
        $validSegments = 0
        foreach ($segment in $segments) {
            if ([string]::IsNullOrWhiteSpace($segment.Path)) {
                [void]$violations.Add("$Label $($row.CaseId) locator is not a repository-relative source path: $($segment.Raw)")
                continue
            }
            $resolved = Resolve-PostReviewRepositoryPath -RepositoryRoot $RepositoryRoot -Path $segment.Path
            if ($null -eq $resolved -or -not (Test-Path -LiteralPath $resolved.FullPath -PathType Leaf)) {
                [void]$violations.Add("$Label $($row.CaseId) locator path does not exist: $($segment.Path)")
                continue
            }
            $validSegments++
            if (-not $segment.HasSymbolSyntax -or [string]::IsNullOrWhiteSpace([string]$segment.Symbol)) {
                [void]$violations.Add("$Label $($row.CaseId) locator symbol is required (path::symbol): $($segment.Raw)")
                continue
            }
            try {
                $sourceText = [System.IO.File]::ReadAllText($resolved.FullPath, $utf8NoBom)
            }
            catch {
                [void]$violations.Add("$Label $($row.CaseId) locator source cannot be read: $($segment.Path)")
                continue
            }

            $symbol = [string]$segment.Symbol
            $symbolViolation = Get-PostReviewSymbolDefinitionViolation -Path $segment.Path `
                -SourceText $sourceText -Symbol $symbol -CaseId ([string]$row.CaseId)
            if (-not [string]::IsNullOrWhiteSpace($symbolViolation)) {
                [void]$violations.Add("$Label $($row.CaseId) $symbolViolation in $($segment.Path)")
            }
        }
        if ($validSegments -eq 0) {
            continue
        }

        $commands = @(
            ([regex]::Replace([string]$row.Command, '(?i)<br\s*/?>', "`n")) -split '\r?\n' |
                ForEach-Object { $_.Trim().Trim('`') } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        if ($commands.Count -eq 0) {
            [void]$violations.Add("$Label $($row.CaseId) command has no public runner invocation")
            continue
        }
        foreach ($command in $commands) {
            foreach ($commandViolation in @(Test-PostReviewPublicCommand -CaseId $row.CaseId `
                        -Command $command -LocatorSegments $segments)) {
                [void]$violations.Add("$Label $($row.CaseId) $commandViolation")
            }
        }
    }
    $violations.ToArray()
}

function Test-PostReviewPublicCommand {
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][object[]]$LocatorSegments
    )

    $violations = [System.Collections.Generic.List[string]]::new()
    $normalized = $Command.Trim().Trim('`').Replace('\', '/') -replace '\s+', ' '
    $commandCaseIds = @([regex]::Matches($normalized, '(?i)TC-PFL-\d{3}') |
        ForEach-Object { $_.Value.ToUpperInvariant() })
    foreach ($commandCaseId in $commandCaseIds) {
        if ($commandCaseId -ne $CaseId) {
            [void]$violations.Add("command case mismatch: $commandCaseId")
        }
    }
    $locatorPaths = @($LocatorSegments | ForEach-Object {
            [string]$_.Path.Trim().Replace('\', '/')
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($normalized -match '^(?i:pwsh(?:\.exe)?)\s+-NoProfile\s+-File\s+(?<runner>scripts/(?:project-lint\.tests|check\.contract\.tests)\.ps1)\s+-Case\s+(?<case>TC-PFL-\d{3})(?:\s+-Format\s+(?:Text|Json))?$') {
        if ($Matches.case.ToUpperInvariant() -ne $CaseId) {
            [void]$violations.Add("command case mismatch: $($Matches.case)")
        }
        if ($locatorPaths -notcontains $Matches.runner) {
            [void]$violations.Add("command runner does not match locator: $($Matches.runner)")
        }
        return $violations.ToArray()
    }

    if ($normalized -match '^(?i:npm(?:\.cmd)?)\s+--prefix\s+frontend\s+run\s+test\s+--\s+(?<test>test/lint/[^\s]+\.test\.[cm]?[jt]s)\s+-t\s+(?<case>TC-PFL-\d{3})$') {
        if ($Matches.case.ToUpperInvariant() -ne $CaseId) {
            [void]$violations.Add("command case mismatch: $($Matches.case)")
        }
        $commandPath = "frontend/$($Matches.test)"
        if ($locatorPaths -notcontains $commandPath) {
            [void]$violations.Add("command test path does not match locator: $commandPath")
        }
        return $violations.ToArray()
    }

    if ($normalized -match '^(?<runner>backend/mvnw(?:\.cmd)?)\s+-B\s+-Dtest=(?<class>[A-Za-z0-9_$]+)\s+test$') {
        $classPathMatch = @($locatorPaths | Where-Object {
                $_ -match ("(?i)/" + [regex]::Escape($Matches.class) + '\.java$')
            })
        if ($classPathMatch.Count -eq 0) {
            [void]$violations.Add("command test class does not match locator: $($Matches.class)")
        }
        $caseToken = Get-PostReviewCaseSymbolToken -CaseId $CaseId
        $hasCaseToken = @($LocatorSegments | ForEach-Object { [string]$_.Symbol } |
            Where-Object { $_ -match "(?i)$([regex]::Escape($caseToken))" }).Count -gt 0
        if (-not $hasCaseToken) {
            [void]$violations.Add("command has no locator symbol for case: $CaseId")
        }
        return $violations.ToArray()
    }

    [void]$violations.Add('command does not invoke an allowed public runner')
    $violations.ToArray()
}

function Read-PostReviewDocuments {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][object]$Specification
    )

    $documents = [ordered]@{}
    $artifactValues = Get-PostReviewProperty -Object $Specification -Name 'requiredArtifacts'
    foreach ($artifact in @($artifactValues)) {
        $relativePath = [string]$artifact
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            continue
        }
        $fullPath = Join-Path $RepositoryRoot $relativePath
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            try {
                $documents[$relativePath] = [System.IO.File]::ReadAllText($fullPath, $utf8NoBom)
            }
            catch {
                $documents[$relativePath] = $null
            }
        }
        else {
            $documents[$relativePath] = $null
        }
    }
    $documents
}

function Get-PostReviewExecutionEvidenceViolations {
    param(
        [AllowNull()][object]$Specification,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][object[]]$TraceRows
    )

    $violations = [System.Collections.Generic.List[string]]::new()
    $evidence = Get-PostReviewProperty -Object $Specification -Name 'executionEvidence'
    if ($null -eq $evidence) {
        [void]$violations.Add('fixture executionEvidence is missing')
        return $violations.ToArray()
    }
    $relativePath = [string](Get-PostReviewProperty -Object $evidence -Name 'path')
    $resolved = if ([string]::IsNullOrWhiteSpace($relativePath)) {
        $null
    }
    else {
        Resolve-PostReviewRepositoryPath -RepositoryRoot $RepositoryRoot -Path $relativePath
    }
    if ($null -eq $resolved -or -not (Test-Path -LiteralPath $resolved.FullPath -PathType Leaf)) {
        [void]$violations.Add("execution evidence artifact does not exist: $relativePath")
        return $violations.ToArray()
    }

    $expectedArtifactHash = [string](Get-PostReviewProperty -Object $evidence -Name 'sha256')
    if ($expectedArtifactHash -notmatch '^(?i:[0-9a-f]{64})$') {
        [void]$violations.Add('fixture executionEvidence.sha256 must be a SHA-256 digest')
    }
    else {
        try {
            $actualArtifactHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolved.FullPath).Hash
            if (-not $actualArtifactHash.Equals($expectedArtifactHash, [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$violations.Add("execution evidence artifact hash mismatch: $relativePath")
            }
        }
        catch {
            [void]$violations.Add("execution evidence artifact cannot be hashed: $relativePath")
        }
    }

    try {
        $artifact = Get-Content -Raw -Encoding UTF8 -LiteralPath $resolved.FullPath | ConvertFrom-Json -Depth 100
    }
    catch {
        [void]$violations.Add("execution evidence artifact is not valid JSON: $relativePath")
        return $violations.ToArray()
    }
    if ([int](Get-PostReviewProperty -Object $artifact -Name 'schemaVersion') -ne 2) {
        [void]$violations.Add('execution evidence artifact schemaVersion must be 2')
    }
    $head = (& git -C $RepositoryRoot rev-parse --verify HEAD 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($head)) {
        [void]$violations.Add('current repository commit could not be resolved for execution evidence')
    }
    elseif ([string](Get-PostReviewProperty -Object $artifact -Name 'commit') -ne $head) {
        [void]$violations.Add("execution evidence commit does not match current repository commit: $head")
    }

    $expectedSourcePaths = @(Get-PostReviewExpectedSourcePaths)
    $sourceArtifacts = @(
        Get-PostReviewProperty -Object $artifact -Name 'sourceArtifacts' |
            Where-Object { $null -ne $_ }
    )
    $sourceArtifactsProperty = $artifact.PSObject.Properties['sourceArtifacts']
    if ($null -eq $sourceArtifactsProperty -or -not ($sourceArtifactsProperty.Value -is [System.Array])) {
        [void]$violations.Add('execution evidence sourceArtifacts must be an array')
    }
    if ($sourceArtifacts.Count -ne $expectedSourcePaths.Count) {
        [void]$violations.Add("execution evidence source artifact count is $($sourceArtifacts.Count), expected $($expectedSourcePaths.Count)")
    }
    $sourceHashByPath = @{}
    $seenSourcePaths = @{}
    for ($sourceIndex = 0; $sourceIndex -lt $sourceArtifacts.Count; $sourceIndex++) {
        $sourceEntry = $sourceArtifacts[$sourceIndex]
        $sourcePath = ([string](Get-PostReviewProperty -Object $sourceEntry -Name 'path')).Trim().Replace('\', '/')
        $sourceHash = ([string](Get-PostReviewProperty -Object $sourceEntry -Name 'sha256')).Trim()
        if ($sourceIndex -lt $expectedSourcePaths.Count -and $sourcePath -ne $expectedSourcePaths[$sourceIndex]) {
            [void]$violations.Add("execution evidence source artifact order mismatch at index $sourceIndex")
        }
        if ([string]::IsNullOrWhiteSpace($sourcePath) -or $expectedSourcePaths -notcontains $sourcePath) {
            [void]$violations.Add("execution evidence contains unexpected source artifact: $sourcePath")
            continue
        }
        if ($seenSourcePaths.ContainsKey($sourcePath)) {
            [void]$violations.Add("execution evidence duplicates source artifact: $sourcePath")
            continue
        }
        $seenSourcePaths[$sourcePath] = $true
        $sourceResolved = Resolve-PostReviewRepositoryPath -RepositoryRoot $RepositoryRoot -Path $sourcePath
        if ($null -eq $sourceResolved -or -not (Test-Path -LiteralPath $sourceResolved.FullPath -PathType Leaf)) {
            [void]$violations.Add("execution evidence source path does not exist: $sourcePath")
            continue
        }
        if ($sourceHash -notmatch '^(?i:[0-9a-f]{64})$') {
            [void]$violations.Add("execution evidence source hash is invalid: $sourcePath")
            continue
        }
        $actualSourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceResolved.FullPath).Hash
        if (-not $actualSourceHash.Equals($sourceHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$violations.Add("execution evidence source hash mismatch: $sourcePath")
            continue
        }
        $sourceHashByPath[$sourcePath] = $sourceHash.ToUpperInvariant()
    }
    foreach ($expectedSourcePath in $expectedSourcePaths) {
        if (-not $sourceHashByPath.ContainsKey($expectedSourcePath)) {
            [void]$violations.Add("execution evidence is missing source artifact: $expectedSourcePath")
        }
    }

    if ($null -ne $artifact.PSObject.Properties['caseResults']) {
        [void]$violations.Add('execution evidence caseResults/default is prohibited; use executions.coveredCases')
    }
    if ($null -ne $artifact.PSObject.Properties['default']) {
        [void]$violations.Add('execution evidence default status is prohibited; use executions.coveredCases')
    }

    $expectedCaseIds = @(Get-PostReviewRangeIds -Range (Get-PostReviewExpectedRangeDefinitions).testCases)
    $traceRowsByCase = @{}
    foreach ($row in $TraceRows) {
        $caseId = ([string]$row.CaseId).Trim().ToUpperInvariant()
        if ($caseId -notmatch '^TC-PFL-\d{3}$') {
            continue
        }
        if (-not $traceRowsByCase.ContainsKey($caseId)) {
            $traceRowsByCase[$caseId] = [System.Collections.Generic.List[object]]::new()
        }
        [void]$traceRowsByCase[$caseId].Add($row)
    }

    $executions = @(
        Get-PostReviewProperty -Object $artifact -Name 'executions' |
            Where-Object { $null -ne $_ }
    )
    $executionsProperty = $artifact.PSObject.Properties['executions']
    if ($null -eq $executionsProperty -or -not ($executionsProperty.Value -is [System.Array])) {
        [void]$violations.Add('execution evidence executions must be an array')
    }
    if ($executions.Count -eq 0) {
        [void]$violations.Add('execution evidence executions is missing or empty')
    }
    $seenExecutionIds = @{}
    $coveredCases = @{}
    foreach ($execution in $executions) {
        $executionId = ([string](Get-PostReviewProperty -Object $execution -Name 'id')).Trim()
        if ([string]::IsNullOrWhiteSpace($executionId)) {
            [void]$violations.Add('execution evidence execution id is missing')
        }
        elseif ($seenExecutionIds.ContainsKey($executionId)) {
            [void]$violations.Add("execution evidence execution id is duplicated: $executionId")
        }
        else {
            $seenExecutionIds[$executionId] = $true
        }

        $coveredCasesProperty = $execution.PSObject.Properties['coveredCases']
        if ($null -eq $coveredCasesProperty -or -not ($coveredCasesProperty.Value -is [System.Array])) {
            [void]$violations.Add("execution evidence $executionId coveredCases must be an array")
        }
        $coveredCaseValues = @(
            Get-PostReviewProperty -Object $execution -Name 'coveredCases' |
                Where-Object { $null -ne $_ }
        )
        if ($coveredCaseValues.Count -eq 0) {
            [void]$violations.Add("execution evidence $executionId has no coveredCases")
            continue
        }
        $recordCaseIds = @{}
        foreach ($coveredCaseValue in $coveredCaseValues) {
            $caseId = ([string]$coveredCaseValue).Trim().ToUpperInvariant()
            if ($caseId -notmatch '^TC-PFL-\d{3}$' -or $expectedCaseIds -notcontains $caseId) {
                [void]$violations.Add("execution evidence $executionId references unexpected caseId: $caseId")
                continue
            }
            if ($recordCaseIds.ContainsKey($caseId)) {
                [void]$violations.Add("execution evidence $executionId duplicates covered caseId: $caseId")
                continue
            }
            $recordCaseIds[$caseId] = $true
            if ($coveredCases.ContainsKey($caseId)) {
                [void]$violations.Add("execution evidence case coverage is duplicated: $caseId")
            }
            else {
                $coveredCases[$caseId] = $executionId
            }
        }

        $commandText = ([string](Get-PostReviewProperty -Object $execution -Name 'command')).Trim()
        if ([string]::IsNullOrWhiteSpace($commandText)) {
            [void]$violations.Add("execution evidence $executionId command is missing")
        }
        $result = ([string](Get-PostReviewProperty -Object $execution -Name 'result')).Trim().ToUpperInvariant()
        if ($result -notin @('PASS', 'HOLD')) {
            [void]$violations.Add("execution evidence $executionId result must be PASS or HOLD")
        }
        $exitProperty = $execution.PSObject.Properties['exitCode']
        $exitCode = 0
        if ($null -eq $exitProperty -or $null -eq $exitProperty.Value -or
            -not [int]::TryParse(([string]$exitProperty.Value), [ref]$exitCode)) {
            [void]$violations.Add("execution evidence $executionId exitCode is missing or not an integer")
        }
        elseif ($exitCode -ne 0) {
            [void]$violations.Add("execution evidence $executionId $result requires exitCode 0")
        }

        foreach ($streamName in @('stdout', 'stderr')) {
            $streamProperty = $execution.PSObject.Properties[$streamName]
            $hashProperty = $execution.PSObject.Properties["${streamName}Sha256"]
            if ($null -eq $streamProperty -and $null -eq $hashProperty) {
                [void]$violations.Add("execution evidence $executionId must include ${streamName} or ${streamName}Sha256")
            }
            elseif ($null -ne $hashProperty -and ([string]$hashProperty.Value).Trim() -notmatch '^(?i:[0-9a-f]{64})$') {
                [void]$violations.Add("execution evidence $executionId ${streamName}Sha256 is invalid")
            }
        }

        $executionSources = @(
            Get-PostReviewProperty -Object $execution -Name 'sourceArtifacts' |
                Where-Object { $null -ne $_ }
        )
        if ($executionSources.Count -eq 0) {
            [void]$violations.Add("execution evidence $executionId sourceArtifacts is missing")
        }
        $seenExecutionSources = @{}
        foreach ($executionSource in $executionSources) {
            $executionSourcePath = ([string](Get-PostReviewProperty -Object $executionSource -Name 'path')).Trim().Replace('\', '/')
            $executionSourceHash = ([string](Get-PostReviewProperty -Object $executionSource -Name 'sha256')).Trim()
            if ($seenExecutionSources.ContainsKey($executionSourcePath)) {
                [void]$violations.Add("execution evidence $executionId duplicates source artifact: $executionSourcePath")
                continue
            }
            $seenExecutionSources[$executionSourcePath] = $true
            if (-not $sourceHashByPath.ContainsKey($executionSourcePath)) {
                [void]$violations.Add("execution evidence $executionId references unpinned source artifact: $executionSourcePath")
                continue
            }
            if ($executionSourceHash -notmatch '^(?i:[0-9a-f]{64})$' -or
                -not $executionSourceHash.Equals($sourceHashByPath[$executionSourcePath], [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$violations.Add("execution evidence $executionId source hash does not match pinned artifact: $executionSourcePath")
            }
        }
        $executionSourcePaths = @{}
        foreach ($executionSource in $executionSources) {
            $executionSourcePath = ([string](Get-PostReviewProperty -Object $executionSource -Name 'path')).Trim().Replace('\', '/')
            if (-not [string]::IsNullOrWhiteSpace($executionSourcePath)) {
                $executionSourcePaths[$executionSourcePath] = $true
            }
        }

        $commands = @(
            ([regex]::Replace($commandText, '(?i)<br\s*/?>', "`n")) -split '\r?\n' |
                ForEach-Object { $_.Trim().Trim('`') } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        foreach ($caseId in @($recordCaseIds.Keys)) {
            if (-not $traceRowsByCase.ContainsKey($caseId)) {
                [void]$violations.Add("execution evidence $executionId has no trace row for $caseId")
                continue
            }
            foreach ($row in @($traceRowsByCase[$caseId])) {
                $rowStatus = ([string]$row.Status).Trim().ToUpperInvariant()
                if ($rowStatus -ne $result) {
                    [void]$violations.Add("$($row.Label) $caseId status does not match execution evidence: row=$rowStatus artifact=$result")
                }
                $normalize = { param([string]$Value) ($Value.Trim().Replace('\', '/') -replace '\s+', ' ') }
                if ((& $normalize $commandText) -ne (& $normalize ([string]$row.Command))) {
                    [void]$violations.Add("$($row.Label) $caseId command does not match execution evidence")
                }
                $locatorSegments = @(Get-PostReviewLocatorSegments -Locator ([string]$row.Locator))
                foreach ($locatorSegment in $locatorSegments) {
                    $locatorPath = ([string]$locatorSegment.Path).Trim().Replace('\', '/')
                    if (-not $executionSourcePaths.ContainsKey($locatorPath)) {
                        [void]$violations.Add("execution evidence $executionId does not bind locator source artifact: $locatorPath")
                    }
                }
                foreach ($command in $commands) {
                    foreach ($commandViolation in @(Test-PostReviewPublicCommand -CaseId $caseId `
                                -Command $command -LocatorSegments $locatorSegments)) {
                        [void]$violations.Add("$($row.Label) $caseId $commandViolation")
                    }
                }
                if ($result -eq 'HOLD') {
                    if ($caseId -ne 'TC-PFL-074') {
                        [void]$violations.Add("execution evidence HOLD is only allowed for TC-PFL-074: $caseId")
                    }
                    $rowText = [string](Get-PostReviewProperty -Object $row -Name 'RawText')
                    if ($rowText -notmatch '(?i)(理由|reason|未取得|not\s+captured)') {
                        [void]$violations.Add("$($row.Label) $caseId HOLD row is missing a reason")
                    }
                    if ($rowText -notmatch '(?i)(再確認|recheck|Stage\s*1.*Stage\s*2|次回|next)') {
                        [void]$violations.Add("$($row.Label) $caseId HOLD row is missing a recheck condition")
                    }
                }
            }
        }
    }
    if ($coveredCases.Count -ne $expectedCaseIds.Count) {
        [void]$violations.Add("execution evidence case coverage count is $($coveredCases.Count), expected $($expectedCaseIds.Count)")
    }
    foreach ($expectedCaseId in $expectedCaseIds) {
        if (-not $coveredCases.ContainsKey($expectedCaseId)) {
            [void]$violations.Add("execution evidence case coverage is missing: $expectedCaseId")
        }
    }
    $violations.ToArray()
}

function Get-PostReviewGateViolations {
    param(
        [AllowNull()][object]$Specification,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Documents,
        [string]$RepositoryRoot = ''
    )

    $violations = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Specification) {
        [void]$violations.Add('post-review fixture is missing')
        return $violations.ToArray()
    }
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        $RepositoryRoot = $repoRoot
    }

    $artifactValues = Get-PostReviewProperty -Object $Specification -Name 'requiredArtifacts'
    if ($null -eq $artifactValues) {
        [void]$violations.Add('fixture requiredArtifacts is missing')
        $artifactPaths = @()
    }
    else {
        $artifactPaths = @($artifactValues | ForEach-Object { [string]$_ })
    }
    $expectedArtifactPaths = @(Get-PostReviewExpectedArtifactPaths)
    if ($artifactPaths.Count -ne $expectedArtifactPaths.Count) {
        [void]$violations.Add("fixture requiredArtifacts count is $($artifactPaths.Count), expected $($expectedArtifactPaths.Count)")
    }
    foreach ($expectedArtifact in $expectedArtifactPaths) {
        if ($artifactPaths -notcontains $expectedArtifact) {
            [void]$violations.Add("fixture requiredArtifacts is missing $expectedArtifact")
        }
    }
    foreach ($artifactPath in $artifactPaths) {
        if ([string]::IsNullOrWhiteSpace($artifactPath)) {
            [void]$violations.Add('fixture requiredArtifacts contains a blank path')
        }
        elseif ($expectedArtifactPaths -notcontains $artifactPath) {
            [void]$violations.Add("fixture requiredArtifacts contains unexpected path $artifactPath")
        }
    }
    if ($null -ne (Get-PostReviewProperty -Object $Specification -Name 'requiredArtifactPaths')) {
        [void]$violations.Add('fixture must use requiredArtifacts, not requiredArtifactPaths')
    }
    foreach ($expectedArtifact in $expectedArtifactPaths) {
        if (-not (@($Documents.Keys) -contains $expectedArtifact) -or $null -eq $Documents[$expectedArtifact]) {
            [void]$violations.Add("missing required artifact: $expectedArtifact")
        }
    }

    $rangeDefinitions = Get-PostReviewExpectedRangeDefinitions
    $configuredRanges = Get-PostReviewProperty -Object $Specification -Name 'requiredIdRanges'
    if ($null -eq $configuredRanges) {
        [void]$violations.Add('fixture requiredIdRanges is missing')
        $expectedIdsByGroup = [ordered]@{}
    }
    else {
        $expectedIdsByGroup = [ordered]@{}
        foreach ($definition in $rangeDefinitions.GetEnumerator()) {
            $configured = Get-PostReviewProperty -Object $configuredRanges -Name $definition.Key
            $expected = $definition.Value
            if ($null -eq $configured) {
                [void]$violations.Add("fixture requiredIdRanges is missing $($definition.Key)")
                continue
            }
            $prefix = [string](Get-PostReviewProperty -Object $configured -Name 'prefix')
            $startText = [string](Get-PostReviewProperty -Object $configured -Name 'start')
            $endText = [string](Get-PostReviewProperty -Object $configured -Name 'end')
            $start = 0
            $end = 0
            $validStart = [int]::TryParse($startText, [ref]$start)
            $validEnd = [int]::TryParse($endText, [ref]$end)
            if (-not $validStart -or -not $validEnd -or $prefix -ne $expected.Prefix -or
                $start -ne $expected.Start -or $end -ne $expected.End) {
                [void]$violations.Add("fixture requiredIdRanges $($definition.Key) is not the required range")
                continue
            }
            $expectedIdsByGroup[$definition.Key] = @(Get-PostReviewRangeIds -Range $expected)
        }
    }

    $allText = @($Documents.Values | Where-Object { $null -ne $_ }) -join "`n"
    $additionalIdDefinitions = Get-PostReviewExpectedAdditionalIds
    $configuredAdditionalIds = Get-PostReviewProperty -Object $Specification -Name 'requiredAdditionalIds'
    if ($null -eq $configuredAdditionalIds) {
        [void]$violations.Add('fixture requiredAdditionalIds is missing')
    }
    else {
        foreach ($additionalDefinition in $additionalIdDefinitions.GetEnumerator()) {
            $expectedAdditional = @($additionalDefinition.Value)
            $configuredAdditional = @(Get-PostReviewProperty -Object $configuredAdditionalIds -Name $additionalDefinition.Key)
            if ((@($configuredAdditional | ForEach-Object { [string]$_ }) -join ',') -ne ($expectedAdditional -join ',')) {
                [void]$violations.Add("fixture requiredAdditionalIds $($additionalDefinition.Key) is not the required set")
            }
            foreach ($requiredId in $expectedAdditional) {
                $idPattern = '(?<![A-Za-z0-9_-])' + [regex]::Escape([string]$requiredId) + '(?![A-Za-z0-9_-])'
                if ($allText -notmatch $idPattern) {
                    [void]$violations.Add("missing required additional ID $requiredId")
                }
            }
        }
    }

    $configuredMarkers = @(Get-PostReviewProperty -Object $Specification -Name 'forbiddenStaleMarkers')
    if ($configuredMarkers.Count -eq 0) {
        [void]$violations.Add('fixture forbiddenStaleMarkers is missing')
    }
    $minimumMarkers = @(
        '未実行（Do前Plan）'
        'Stage 0のまま'
        '本番コード、テスト、runner、workflowは変更していない'
        'Stage0レビュー解消・Do開始可'
        'Stage 0レビュー解消・Do開始可'
        '本番コード、testコード、fixture、workflow、CI/gate接続は未実施'
        '本番コード、テストコード、fixture、workflow、C接続は未変更'
        '本番コード、testコード、fixture、workflow、C接続は未変更'
        '本番コード、テストコード、fixture、validator、ESLint設定、workflow、scripts/check.ps1接続を変更していない'
    )
    foreach ($marker in $minimumMarkers) {
        if ($configuredMarkers -notcontains $marker) {
            [void]$violations.Add("fixture forbiddenStaleMarkers is missing [$marker]")
        }
    }

    $documentPaths = [ordered]@{
        review = 'docs/AI活用開発研究/作業記録/カスタムLinter_実装後レビュー.md'
        quality = 'docs/AI活用開発研究/作業記録/カスタムLinter_統合品質記録.md'
        work = 'docs/AI活用開発研究/作業記録/カスタムLinter_作業記録.md'
        issues = 'docs/AI活用開発研究/作業記録/日報登録編集_指摘一覧.md'
        cases = 'docs/AI活用開発研究/作業記録/カスタムLinter_テストケース.md'
    }
    foreach ($document in $documentPaths.GetEnumerator()) {
        $path = $document.Value
        if (-not (@($Documents.Keys) -contains $path) -or $null -eq $Documents[$path]) {
            continue
        }
        $text = [string]$Documents[$path]
        foreach ($marker in $configuredMarkers) {
            if (-not [string]::IsNullOrWhiteSpace([string]$marker) -and $text.Contains([string]$marker)) {
                [void]$violations.Add("$($document.Key) contains forbidden stale marker [$marker]")
            }
        }
    }

    foreach ($group in $expectedIdsByGroup.GetEnumerator()) {
        foreach ($requiredId in $group.Value) {
            $idPattern = '(?<![A-Za-z0-9_-])' + [regex]::Escape([string]$requiredId) + '(?![A-Za-z0-9_-])'
            if ($allText -notmatch $idPattern) {
                [void]$violations.Add("missing required ID $requiredId")
            }
        }
    }

    if ($expectedIdsByGroup.Contains('testCases')) {
        $casePath = $documentPaths.cases
        if (@($Documents.Keys) -contains $casePath -and $null -ne $Documents[$casePath]) {
            foreach ($traceViolation in @(Get-PostReviewTraceViolations -Label 'cases' `
                        -Text ([string]$Documents[$casePath]) -ExpectedTestCaseIds @($expectedIdsByGroup.testCases))) {
                [void]$violations.Add([string]$traceViolation)
            }
        }
        $qualityPath = $documentPaths.quality
        if (@($Documents.Keys) -contains $qualityPath -and $null -ne $Documents[$qualityPath]) {
            foreach ($traceViolation in @(Get-PostReviewTraceViolations -Label 'quality' `
                        -Text ([string]$Documents[$qualityPath]) -ExpectedTestCaseIds @($expectedIdsByGroup.testCases))) {
                [void]$violations.Add([string]$traceViolation)
            }
        }
    }
    $traceRows = [System.Collections.Generic.List[object]]::new()
    foreach ($traceDocument in @(
            [pscustomobject]@{ Label = 'cases'; Path = $documentPaths.cases }
            [pscustomobject]@{ Label = 'quality'; Path = $documentPaths.quality }
        )) {
        if (@($Documents.Keys) -contains $traceDocument.Path -and $null -ne $Documents[$traceDocument.Path]) {
            foreach ($row in @(Get-PostReviewTraceRows -Label $traceDocument.Label -Text ([string]$Documents[$traceDocument.Path]))) {
                [void]$traceRows.Add($row)
            }
            foreach ($traceViolation in @(Get-PostReviewTraceContentViolations -Label $traceDocument.Label `
                        -Text ([string]$Documents[$traceDocument.Path]) -RepositoryRoot $RepositoryRoot `
                        -ExpectedTestCaseIds @($expectedIdsByGroup.testCases))) {
                [void]$violations.Add([string]$traceViolation)
            }
        }
    }
    foreach ($evidenceViolation in @(Get-PostReviewExecutionEvidenceViolations -Specification $Specification `
                -RepositoryRoot $RepositoryRoot -TraceRows $traceRows.ToArray())) {
        [void]$violations.Add([string]$evidenceViolation)
    }
    @($violations | Sort-Object -Unique)
}

function Test-PostReviewCompletionFlagCannotBypass {
    param(
        [Parameter(Mandatory)][object]$Specification,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Documents
    )

    $negativeDocuments = [ordered]@{}
    foreach ($artifactPath in @(Get-PostReviewExpectedArtifactPaths)) {
        if ($Documents.Contains($artifactPath)) {
            $negativeDocuments[$artifactPath] = $Documents[$artifactPath]
        }
        else {
            $negativeDocuments[$artifactPath] = $null
        }
    }

    # Keep one missing artifact and one stale marker in the helper-only input so
    # the assertion remains meaningful even after the production documents pass.
    $reviewPath = 'docs/AI活用開発研究/作業記録/カスタムLinter_実装後レビュー.md'
    $qualityPath = 'docs/AI活用開発研究/作業記録/カスタムLinter_統合品質記録.md'
    $negativeDocuments[$reviewPath] = $null
    $staleMarker = @(
        Get-PostReviewProperty -Object $Specification -Name 'forbiddenStaleMarkers' |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    ) | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($staleMarker)) {
        $staleMarker = '未実行（Do前Plan）'
    }
    $negativeDocuments[$qualityPath] = ([string]$negativeDocuments[$qualityPath]) + "`n" + $staleMarker

    $withoutCompletionFlag = @(Get-PostReviewGateViolations `
            -Specification $Specification -Documents $negativeDocuments)
    $completionFixture = $Specification | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
    Add-Member -InputObject $completionFixture -NotePropertyName 'postReviewStatus' `
        -NotePropertyValue 'complete' -Force
    $withCompletionFlag = @(Get-PostReviewGateViolations `
            -Specification $completionFixture -Documents $negativeDocuments)

    Assert-Condition ($withoutCompletionFlag.Count -gt 0) `
        'TC-PFL-085 helper negative input must fail missing/stale document checks.'
    Assert-SetEquals -Actual $withCompletionFlag -Expected $withoutCompletionFlag `
        'TC-PFL-085 postReviewStatus=complete must not bypass missing/stale document checks.'
}

function Copy-PostReviewDocuments {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Documents)

    $copy = [ordered]@{}
    foreach ($entry in $Documents.GetEnumerator()) {
        $copy[$entry.Key] = $entry.Value
    }
    $copy
}

function Assert-PostReviewViolationContains {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Violations,
        [Parameter(Mandatory)][string]$Needle,
        [Parameter(Mandatory)][string]$Message
    )

    Assert-Condition (@($Violations | Where-Object { $_.Contains($Needle) }).Count -gt 0) `
        "$Message Missing=[$Needle] Violations=[$($Violations -join ' | ')]"
}

function Get-PostReviewEvidenceMutationViolations {
    param(
        [Parameter(Mandatory)][object]$Specification,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Documents,
        [Parameter(Mandatory)][scriptblock]$Mutate,
        [Parameter(Mandatory)][string]$Name
    )

    $evidencePath = [string](Get-PostReviewProperty -Object `
            (Get-PostReviewProperty -Object $Specification -Name 'executionEvidence') -Name 'path')
    $evidenceFullPath = Join-Path $repoRoot $evidencePath
    $mutatedEvidence = Get-Content -Raw -Encoding UTF8 -LiteralPath $evidenceFullPath | ConvertFrom-Json -Depth 100
    & $Mutate $mutatedEvidence | Out-Null

    $temporaryEvidenceName = ".check-contract-$PID-tc085-$Name.json"
    $temporaryEvidencePath = Join-Path $repoRoot $temporaryEvidenceName
    try {
        Write-Utf8File -Path $temporaryEvidencePath -Content ($mutatedEvidence | ConvertTo-Json -Depth 100)
        $mutatedSpecification = $Specification | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
        $mutatedSpecification.executionEvidence.path = $temporaryEvidenceName
        $mutatedSpecification.executionEvidence.sha256 = (Get-FileHash -Algorithm SHA256 `
                -LiteralPath $temporaryEvidencePath).Hash
        @(Get-PostReviewGateViolations -Specification $mutatedSpecification `
                -Documents $Documents -RepositoryRoot $repoRoot)
    }
    finally {
        if (Test-Path -LiteralPath $temporaryEvidencePath) {
            Remove-Item -LiteralPath $temporaryEvidencePath -Force
        }
    }
}

function Test-PostReviewTraceNegativeCases {
    param(
        [Parameter(Mandatory)][object]$Specification,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Documents
    )

    $tracePaths = @(
        'docs/AI活用開発研究/作業記録/カスタムLinter_テストケース.md'
        'docs/AI活用開発研究/作業記録/カスタムLinter_統合品質記録.md'
    )
    $replaceInTraceDocuments = {
        param([string]$Old, [string]$New)
        $copy = Copy-PostReviewDocuments -Documents $Documents
        foreach ($path in $tracePaths) {
            $copy[$path] = ([string]$copy[$path]).Replace($Old, $New)
        }
        $copy
    }

    $fictionalPathDocuments = & $replaceInTraceDocuments `
        'scripts/project-lint.tests.ps1::Test-CatalogCases[TC-PFL-001]' `
        'scripts/project-lint-not-real.tests.ps1::Test-CatalogCases[TC-PFL-001]'
    $fictionalPathViolations = @(Get-PostReviewGateViolations -Specification $Specification `
            -Documents $fictionalPathDocuments -RepositoryRoot $repoRoot)
    Assert-PostReviewViolationContains -Violations $fictionalPathViolations `
        -Needle 'locator path does not exist' `
        -Message 'TC-PFL-085 fictional locator path must fail the content gate.'

    $fictionalSymbolDocuments = & $replaceInTraceDocuments `
        'scripts/project-lint.tests.ps1::Test-CatalogCases[TC-PFL-001]' `
        'scripts/project-lint.tests.ps1::Test-PostReviewSymbolDoesNotExist[TC-PFL-001]'
    $fictionalSymbolViolations = @(Get-PostReviewGateViolations -Specification $Specification `
            -Documents $fictionalSymbolDocuments -RepositoryRoot $repoRoot)
    Assert-PostReviewViolationContains -Violations $fictionalSymbolViolations `
        -Needle 'locator symbol does not exist' `
        -Message 'TC-PFL-085 fictional locator symbol must fail the content gate.'

    $pathOnlyDocuments = & $replaceInTraceDocuments `
        'scripts/project-lint.tests.ps1::Test-CatalogCases[TC-PFL-001]' `
        'scripts/project-lint.tests.ps1'
    $pathOnlyViolations = @(Get-PostReviewGateViolations -Specification $Specification `
            -Documents $pathOnlyDocuments -RepositoryRoot $repoRoot)
    Assert-PostReviewViolationContains -Violations $pathOnlyViolations `
        -Needle 'locator symbol is required' `
        -Message 'TC-PFL-085 path-only locator must fail the content gate.'

    $emptySymbolDocuments = & $replaceInTraceDocuments `
        'scripts/project-lint.tests.ps1::Test-CatalogCases[TC-PFL-001]' `
        'scripts/project-lint.tests.ps1::'
    $emptySymbolViolations = @(Get-PostReviewGateViolations -Specification $Specification `
            -Documents $emptySymbolDocuments -RepositoryRoot $repoRoot)
    Assert-PostReviewViolationContains -Violations $emptySymbolViolations `
        -Needle 'locator symbol is required' `
        -Message 'TC-PFL-085 empty locator symbol must fail the content gate.'

    $caseMismatchDocuments = & $replaceInTraceDocuments `
        'scripts/project-lint.tests.ps1::Test-CatalogCases[TC-PFL-001]' `
        'scripts/project-lint.tests.ps1::Test-CatalogCases[TC-PFL-002]'
    foreach ($path in $tracePaths) {
        $caseMismatchDocuments[$path] = ([string]$caseMismatchDocuments[$path]).Replace(
            ' -Case TC-PFL-001', ' -Case TC-PFL-002')
    }
    $caseMismatchViolations = @(Get-PostReviewGateViolations -Specification $Specification `
            -Documents $caseMismatchDocuments -RepositoryRoot $repoRoot)
    Assert-PostReviewViolationContains -Violations $caseMismatchViolations `
        -Needle 'case mismatch' `
        -Message 'TC-PFL-085 case-mismatched locator/command must fail the content gate.'

    $inconsistentViolations = @(Get-PostReviewEvidenceMutationViolations `
            -Specification $Specification -Documents $Documents -Name 'pass-exit' `
            -Mutate {
                param($artifact)
                $artifact.executions[0].exitCode = 1
            })
    Assert-PostReviewViolationContains -Violations $inconsistentViolations `
        -Needle 'requires exitCode 0' `
        -Message 'TC-PFL-085 PASS with a non-zero evidence exit must fail the content gate.'

    $allHoldViolations = @(Get-PostReviewEvidenceMutationViolations `
            -Specification $Specification -Documents $Documents -Name 'all-hold' `
            -Mutate {
                param($artifact)
                foreach ($execution in @($artifact.executions)) {
                    $execution.result = 'HOLD'
                }
            })
    Assert-PostReviewViolationContains -Violations $allHoldViolations `
        -Needle 'HOLD is only allowed for TC-PFL-074' `
        -Message 'TC-PFL-085 all-105 HOLD evidence must fail closed.'

    $otherHoldViolations = @(Get-PostReviewEvidenceMutationViolations `
            -Specification $Specification -Documents $Documents -Name 'other-hold' `
            -Mutate {
                param($artifact)
                $artifact.executions[0].result = 'HOLD'
            })
    Assert-PostReviewViolationContains -Violations $otherHoldViolations `
        -Needle 'HOLD is only allowed for TC-PFL-074' `
        -Message 'TC-PFL-085 HOLD on a non-TC074 case must fail closed.'

    $coverageMissingViolations = @(Get-PostReviewEvidenceMutationViolations `
            -Specification $Specification -Documents $Documents -Name 'coverage-missing' `
            -Mutate {
                param($artifact)
                $artifact.executions = @($artifact.executions | Where-Object {
                        @($_.coveredCases) -notcontains 'TC-PFL-001'
                    })
            })
    Assert-PostReviewViolationContains -Violations $coverageMissingViolations `
        -Needle 'case coverage is missing: TC-PFL-001' `
        -Message 'TC-PFL-085 missing case coverage must fail closed.'

    $defaultStatusViolations = @(Get-PostReviewEvidenceMutationViolations `
            -Specification $Specification -Documents $Documents -Name 'default-status' `
            -Mutate {
                param($artifact)
                Add-Member -InputObject $artifact -NotePropertyName 'caseResults' `
                    -NotePropertyValue ([pscustomobject]@{ default = [pscustomobject]@{ status = 'PASS' } }) -Force
            })
    Assert-PostReviewViolationContains -Violations $defaultStatusViolations `
        -Needle 'caseResults/default is prohibited' `
        -Message 'TC-PFL-085 default status evidence must be prohibited.'

    $sourceHashMismatchViolations = @(Get-PostReviewEvidenceMutationViolations `
            -Specification $Specification -Documents $Documents -Name 'source-hash-mismatch' `
            -Mutate {
                param($artifact)
                $artifact.sourceArtifacts[0].sha256 = '0' * 64
            })
    Assert-PostReviewViolationContains -Violations $sourceHashMismatchViolations `
        -Needle 'execution evidence source hash mismatch' `
        -Message 'TC-PFL-085 a source artifact hash mismatch must fail the content gate.'

    $duplicateExecutionViolations = @(Get-PostReviewEvidenceMutationViolations `
            -Specification $Specification -Documents $Documents -Name 'duplicate-execution' `
            -Mutate {
                param($artifact)
                $artifact.executions[1].id = $artifact.executions[0].id
            })
    Assert-PostReviewViolationContains -Violations $duplicateExecutionViolations `
        -Needle 'execution id is duplicated' `
        -Message 'TC-PFL-085 duplicate execution IDs must fail the content gate.'

    $duplicateCoverageViolations = @(Get-PostReviewEvidenceMutationViolations `
            -Specification $Specification -Documents $Documents -Name 'duplicate-coverage' `
            -Mutate {
                param($artifact)
                $artifact.executions[1].coveredCases = @('TC-PFL-001')
            })
    Assert-PostReviewViolationContains -Violations $duplicateCoverageViolations `
        -Needle 'case coverage is duplicated: TC-PFL-001' `
        -Message 'TC-PFL-085 duplicate case coverage must fail the content gate.'

    $reasonMissingDocuments = & $replaceInTraceDocuments '未取得' '取得済み'
    $reasonMissingViolations = @(Get-PostReviewGateViolations -Specification $Specification `
            -Documents $reasonMissingDocuments -RepositoryRoot $repoRoot)
    Assert-PostReviewViolationContains -Violations $reasonMissingViolations `
        -Needle 'HOLD row is missing a reason' `
        -Message 'TC-PFL-085 HOLD rows must carry a row-level reason.'

    $recheckMissingDocuments = & $replaceInTraceDocuments 'Stage 1後・Stage 2前' 'stage evidence pending'
    $recheckMissingViolations = @(Get-PostReviewGateViolations -Specification $Specification `
            -Documents $recheckMissingDocuments -RepositoryRoot $repoRoot)
    Assert-PostReviewViolationContains -Violations $recheckMissingViolations `
        -Needle 'HOLD row is missing a recheck condition' `
        -Message 'TC-PFL-085 HOLD rows must carry a row-level recheck condition.'

    $hashMismatchSpecification = $Specification | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
    $hashMismatchSpecification.executionEvidence.sha256 = '0' * 64
    $hashMismatchViolations = @(Get-PostReviewGateViolations -Specification $hashMismatchSpecification `
            -Documents $Documents -RepositoryRoot $repoRoot)
    Assert-PostReviewViolationContains -Violations $hashMismatchViolations `
        -Needle 'execution evidence artifact hash mismatch' `
        -Message 'TC-PFL-085 an incorrect execution evidence hash must fail the content gate.'
}

function Test-PostReviewGate {
    $fixturePath = Join-Path $fixtureRoot 'TC-PFL-085-post-review-gate/post-review.json'
    $fixture = Get-Content -Raw -Encoding UTF8 -LiteralPath $fixturePath | ConvertFrom-Json -Depth 20
    $documents = Read-PostReviewDocuments -RepositoryRoot $repoRoot -Specification $fixture
    $productionViolations = @(Get-PostReviewGateViolations -Specification $fixture -Documents $documents)

    # The production input must also be invariant under an untrusted completion flag.
    $completeFixture = $fixture | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
    Add-Member -InputObject $completeFixture -NotePropertyName 'postReviewStatus' `
        -NotePropertyValue 'complete' -Force
    $completeViolations = @(Get-PostReviewGateViolations -Specification $completeFixture -Documents $documents)
    Assert-SetEquals -Actual $completeViolations -Expected $productionViolations `
        'TC-PFL-085 complete-only fixture mutation must not alter validation failures.'
    Test-PostReviewCompletionFlagCannotBypass -Specification $fixture -Documents $documents
    Test-PostReviewTraceNegativeCases -Specification $fixture -Documents $documents

    if ($productionViolations.Count -gt 0) {
        throw ("TC-PFL-085 production post-review gate failed:`n" +
            (($productionViolations | ForEach-Object { '- ' + $_ }) -join "`n"))
    }
}

function Test-ImpactAggregateUnresolvedSelectedJob {
    $planPath = Join-Path $fixtureRoot 'TC-PFL-092-impact-aggregate-unresolved/plan.json'
    $resultPath = Join-Path ([System.IO.Path]::GetTempPath()) "projectfoundation-contract-$PID-aggregate.json"
    $jobResultsPath = Join-Path $fixtureRoot 'TC-PFL-092-impact-aggregate-unresolved/job-results.json'
    try {
        $jobResultsJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $jobResultsPath
        $execution = Invoke-Check -Arguments @(
            '-NoProfile', '-File', $checkScript,
            '-Mode', 'Impact', '-ImpactTask', 'Aggregate',
            '-ImpactPlanPath', $planPath, '-ImpactResultPath', $resultPath,
            '-ImpactJobResultsJson', $jobResultsJson,
            '-ImpactJobMap', 'FullFrontend=full-windows-frontend'
        )
        Assert-Equal $execution.ExitCode 1 'TC-PFL-092 C exit code.'
        $aggregate = Get-Content -Raw -Encoding UTF8 -LiteralPath $resultPath | ConvertFrom-Json -Depth 20
        Assert-Equal $aggregate.Succeeded $false 'TC-PFL-092 Succeeded.'
        Assert-Equal @($aggregate.Jobs).Count 1 'TC-PFL-092 Jobs count.'
        $job = @($aggregate.Jobs)[0]
        Assert-Equal $job.Layer 'FullFrontend' 'TC-PFL-092 Layer.'
        Assert-Equal $job.Job 'full-windows-frontend' 'TC-PFL-092 Job.'
        Assert-Equal $job.Selected $true 'TC-PFL-092 Selected.'
        Assert-Equal $job.JobResult 'success' 'TC-PFL-092 JobResult.'
        Assert-Equal $job.State 'missing' 'TC-PFL-092 State.'
        Assert-Equal $job.Valid $false 'TC-PFL-092 Valid.'
    }
    finally {
        if (Test-Path -LiteralPath $resultPath) {
            Remove-Item -LiteralPath $resultPath -Force
        }
    }
}

function Test-ImpactAggregatePlanMapMismatch {
    $fixturePath = Join-Path $fixtureRoot 'TC-PFL-121-impact-aggregate-plan-map-mismatch'
    $planPath = Join-Path $fixturePath 'plan.json'
    $jobResultsPath = Join-Path $fixturePath 'job-results.json'
    $resultPath = Join-Path ([System.IO.Path]::GetTempPath()) "projectfoundation-contract-$PID-plan-map.json"
    try {
        $jobResultsJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $jobResultsPath
        $execution = Invoke-Check -Arguments @(
            '-NoProfile', '-File', $checkScript,
            '-Mode', 'Impact', '-ImpactTask', 'Aggregate',
            '-ImpactPlanPath', $planPath, '-ImpactResultPath', $resultPath,
            '-ImpactJobResultsJson', $jobResultsJson,
            '-ImpactJobMap', 'FullFrontend=full-windows-frontend,Oracle=oracle-integration'
        )
        Assert-Equal $execution.ExitCode 1 'TC-PFL-121 C exit code.'
        $aggregate = Get-Content -Raw -Encoding UTF8 -LiteralPath $resultPath | ConvertFrom-Json -Depth 30
        Assert-Equal $aggregate.Succeeded $false 'TC-PFL-121 Succeeded.'
        Assert-Equal $aggregate.Contract 'FocusedFrontendOracle' 'TC-PFL-121 aggregate contract.'
        Assert-Contains -Text ([string]($aggregate.Violations -join "`n")) `
            -Needle 'missing selected layer: FullBackend' `
            -Message 'TC-PFL-121 selected layer missing from JobMap diagnostic.'
        $missingRow = @($aggregate.Jobs | Where-Object Layer -eq 'FullBackend')
        Assert-Equal $missingRow.Count 1 'TC-PFL-121 missing selected layer row count.'
        Assert-Equal $missingRow[0].Job 'missing-map' 'TC-PFL-121 missing selected layer job marker.'
        Assert-Equal $missingRow[0].Valid $false 'TC-PFL-121 missing selected layer validity.'

        # A different mixed map must not become an implicit allow-list.  This
        # map is outside both named workflow contracts and deliberately omits
        # selected FullBackend; Custom must remain fail-closed.
        $customExecution = Invoke-Check -Arguments @(
            '-NoProfile', '-File', $checkScript,
            '-Mode', 'Impact', '-ImpactTask', 'Aggregate',
            '-ImpactPlanPath', $planPath, '-ImpactResultPath', $resultPath,
            '-ImpactJobResultsJson', $jobResultsJson,
            '-ImpactJobMap', 'FullFrontend=full-windows-frontend,Oracle=oracle-integration,BackendUnit=backend-unit'
        )
        Assert-Equal $customExecution.ExitCode 1 'TC-PFL-121 Custom mixed-map C exit code.'
        $customAggregate = Get-Content -Raw -Encoding UTF8 -LiteralPath $resultPath | ConvertFrom-Json -Depth 30
        Assert-Equal $customAggregate.Succeeded $false 'TC-PFL-121 Custom mixed-map Succeeded.'
        Assert-Equal $customAggregate.Contract 'Custom' 'TC-PFL-121 Custom mixed-map contract.'
        Assert-Contains -Text ([string]($customAggregate.Violations -join "`n")) `
            -Needle 'missing selected layer: FullBackend' `
            -Message 'TC-PFL-121 Custom mixed map must not authorize a selected layer omission.'
    }
    finally {
        if (Test-Path -LiteralPath $resultPath) {
            Remove-Item -LiteralPath $resultPath -Force
        }
    }
}

switch ($Case) {
    'TC-PFL-020' { Test-CChildExit2 }
    'TC-PFL-021' { Test-CLocalFull }
    'TC-PFL-022' { Test-CSimpleMandatory }
    'TC-PFL-023' { Test-CFullFrontend }
    'TC-PFL-024' { Test-CFullBackendContract }
    'TC-PFL-025' { Test-ImpactPlanFallback }
    'TC-PFL-074' { Test-BaselineStageOrder }
    'TC-PFL-075' { Test-IgnoreStoreForbidden }
    'TC-PFL-076' { Test-StageOrder }
    'TC-PFL-120' { Test-StageCompletionMarkers }
    'TC-PFL-077' { Test-QuickPrePushUnchanged }
    'TC-PFL-083' { Test-RealRepositoryZero }
    'TC-PFL-084' { Test-StandardsRecord }
    'TC-PFL-085' { Test-PostReviewGate }
    'TC-PFL-092' { Test-ImpactAggregateUnresolvedSelectedJob }
    'TC-PFL-121' { Test-ImpactAggregatePlanMapMismatch }
    default { throw "Unsupported contract case: $Case" }
}
Write-Output "C contract case passed: $Case ($Phase)"
