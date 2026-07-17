$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/check.ps1')

function Assert-Condition {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

$oracleScript = Join-Path $repoRoot 'backend/scripts/test-oracle.ps1'
$frontend = @(Get-CiTaskDefinitions -CiTask FrontendCoverage -RepoRoot $repoRoot `
        -NpmCommand 'npm.cmd' -MavenCommand 'backend/mvnw.cmd' -OracleScript $oracleScript)
$backend = @(Get-CiTaskDefinitions -CiTask BackendCoverage -RepoRoot $repoRoot `
        -NpmCommand 'npm.cmd' -MavenCommand 'backend/mvnw.cmd' -OracleScript $oracleScript)

$frontendCommand = $frontend[0]
$backendCommand = $backend[0]
$frontendArguments = @($frontendCommand.Arguments)
$backendArguments = @($backendCommand.Arguments)
$frontendNames = @($frontend | ForEach-Object Name)
$backendNames = @($backend | ForEach-Object Name)
$packageJson = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'frontend/package.json')
$bootstrapText = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'scripts/bootstrap.ps1')
$pomText = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'backend/pom.xml')
$wrapperMode = @(git -C $repoRoot ls-files -s backend/mvnw)[0].Split()[0]
$ratchetReference = [regex]::Match($pomText, '<ratchetFrom>(?<reference>[^<]+)</ratchetFrom>').Groups['reference'].Value

Assert-Condition ($frontend.Count -eq 2) 'Frontend coverage must return two direct definitions.'
Assert-Condition ($backend.Count -eq 2) 'Backend coverage must return two direct definitions.'
Assert-Condition ($backendCommand.Command -eq 'pwsh') 'Backend coverage must use the Oracle wrapper.'
Assert-Condition ($backendArguments[0] -eq '-NoProfile') 'Backend coverage must start with -NoProfile.'
Assert-Condition ($backendArguments[1] -eq '-File') 'Backend coverage must invoke the wrapper script with -File.'
Assert-Condition ($backendArguments[2] -eq $oracleScript) 'Backend coverage must target backend/scripts/test-oracle.ps1.'
Assert-Condition ($backendArguments -contains '-Pcoverage') 'Backend coverage profile is missing.'
Assert-Condition ($backendArguments -contains 'verify') 'Backend coverage must run Maven verify.'
Assert-Condition ($backendNames -contains 'backend-coverage-report') 'Backend report check is missing.'
Assert-Condition ($frontendArguments -contains 'coverage') 'Frontend coverage must invoke npm coverage.'
Assert-Condition ($frontendNames -contains 'frontend-coverage-report') 'Frontend report check is missing.'
Assert-Condition ($packageJson -match 'pwsh -NoProfile -ExecutionPolicy Bypass -File') `
    'Frontend test-layout check must use pwsh.'
Assert-Condition ($bootstrapText -match "'-f', 'backend/pom.xml'") `
    'Maven bootstrap must target backend/pom.xml.'
Assert-Condition ($bootstrapText -match '\[System\.IO\.Path\]::GetTempPath\(\)') `
    'Gitleaks temporary files must use an OS-independent temp path.'
Assert-Condition ($wrapperMode -eq '100755') 'Unix Maven wrapper must have the executable bit.'
Assert-Condition ($ratchetReference -match '^[0-9a-f]{40}$') `
    'Spotless ratchetFrom must use a remote-resolvable commit SHA.'

Write-Output 'Coverage gate contract tests passed.'
