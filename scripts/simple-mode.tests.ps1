$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/check.ps1')

function Assert-Condition {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Message)
    try {
        & $Action
    }
    catch {
        return
    }
    throw $Message
}

$frontend = @(Get-SimpleCheckDefinitions -RepoRoot $repoRoot -Scope Frontend `
        -FocusedUnitScope Frontend -FocusedUnitTarget 'test/App.test.tsx' `
        -ChangedFiles @('frontend/src/App.tsx', 'frontend/test/App.test.tsx'))
$frontendNames = @($frontend | ForEach-Object Name)

Assert-Condition ($frontendNames -contains 'simple-focused-unit') `
    'Frontend Simple Mode must include one focused unit definition.'
Assert-Condition ($frontendNames -contains 'simple-frontend-lint') `
    'Frontend Simple Mode must include lint.'
Assert-Condition ($frontendNames -contains 'simple-frontend-typecheck') `
    'Frontend Simple Mode must include typecheck.'
Assert-Condition ($frontendNames -contains 'simple-frontend-build') `
    'Frontend Simple Mode must include build.'
Assert-Condition (($frontendNames | Where-Object { $_ -match 'coverage|oracle|secret|full|e2e' }).Count -eq 0) `
    'Frontend Simple Mode must not add broad local checks.'

$browser = @(Get-SimpleCheckDefinitions -RepoRoot $repoRoot -Scope Frontend `
        -FocusedUnitScope Frontend -FocusedUnitTarget 'test/App.test.tsx' `
        -DisplayRequirement -BrowserCase 'verifies the daily report detail presentation in a browser' `
        -ChangedFiles @('frontend/src/App.tsx', 'frontend/test/App.test.tsx'))
$browserNames = @($browser | ForEach-Object Name)
Assert-Condition ($browserNames -contains 'simple-frontend-browser') `
    'Display requirement must add exactly one focused browser definition.'
$browserDefinition = $browser | Where-Object Name -eq 'simple-frontend-browser'
Assert-Condition ($browserDefinition.WorkingDirectory -eq (Join-Path $repoRoot 'frontend')) `
    'Focused browser definition must run from the frontend project directory.'

$manual = @(Get-SimpleCheckDefinitions -RepoRoot $repoRoot -Scope Frontend `
        -FocusedUnitScope Frontend -FocusedUnitTarget 'test/App.test.tsx' `
        -DisplayRequirement -BrowserManualReason 'BrowserCase was not executed.' `
        -ChangedFiles @('frontend/src/App.tsx', 'frontend/test/App.test.tsx'))
$manualBrowser = $manual | Where-Object Name -eq 'simple-browser-manual'
$manualFailures = [System.Collections.Generic.List[string]]::new()
Invoke-QualityChecks -Definitions @($manualBrowser) -Failures $manualFailures
Assert-Condition ($manualFailures -contains 'simple-browser-manual') `
    'BrowserManualReason must not produce a passing quality check.'

$backend = @(Get-SimpleCheckDefinitions -RepoRoot $repoRoot -Scope Backend `
        -FocusedUnitScope Backend -FocusedUnitTarget 'TimeRulesTest' `
        -ChangedFiles @('backend/src/main/java/com/example/TimeRules.java'))
$backendNames = @($backend | ForEach-Object Name)
Assert-Condition ($backendNames -contains 'simple-backend-spotless') `
    'Backend Simple Mode must include Spotless.'
Assert-Condition ($backendNames -contains 'simple-backend-checkstyle') `
    'Backend Simple Mode must include Checkstyle.'
Assert-Condition ($backendNames -contains 'simple-backend-test-compile') `
    'Backend Simple Mode must include test compile.'

$notApplicable = @(Get-SimpleCheckDefinitions -RepoRoot $repoRoot -Scope Docs `
        -FocusedUnitNotApplicableReason 'Markdown-only change has no executable unit logic.' `
        -ChangedFiles @('docs/example.md'))
Assert-Condition ((@($notApplicable | ForEach-Object Name) -contains 'simple-focused-unit-na')) `
    'N/A reason must produce an explicit non-applicable check.'

Assert-Throws {
    Get-SimpleCheckDefinitions -RepoRoot $repoRoot -Scope Frontend `
        -FocusedUnitScope Frontend -ChangedFiles @('frontend/src/App.tsx')
} 'Simple Mode must reject a missing focused unit target and N/A reason.'

Assert-Throws {
    Get-SimpleCheckDefinitions -RepoRoot $repoRoot -Scope Frontend `
        -FocusedUnitScope Frontend -FocusedUnitTarget 'test/App.test.tsx' `
        -DisplayRequirement -ChangedFiles @('frontend/src/App.tsx')
} 'Simple Mode must reject a display requirement without browser case or manual reason.'

$ciOutput = (& pwsh -NoProfile -File (Join-Path $repoRoot 'scripts/check.ps1') `
    -Mode Simple -CiTask BackendUnit 2>&1 | Out-String)
$ciExitCode = $LASTEXITCODE
Assert-Condition ($ciExitCode -ne 0) 'Simple Mode must reject CiTask.'
Assert-Condition ($ciOutput -match 'Simple Mode cannot be combined with -CiTask') `
    'Simple Mode must explain why CiTask is rejected.'

Write-Output 'Simple mode contract tests passed.'
