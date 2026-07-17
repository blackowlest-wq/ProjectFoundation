[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$MavenArgs = @('test'),
    [string]$ConfigPath,
    [switch]$AllowDdl,
    [string]$DdlScript
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = (Resolve-Path (Join-Path $scriptDir '..')).Path
. (Join-Path $scriptDir 'oracle-test-helpers.ps1')

$oracleEnvironment = Get-OracleTestEnvironment -BackendDir $backendDir -ConfigPath $ConfigPath -AllowDdl:$AllowDdl -DdlScript $DdlScript
Set-OracleTestEnvironment -Environment $oracleEnvironment -AllowDdl:$AllowDdl

Push-Location $backendDir
try {
    $settingsPath = Join-Path $backendDir 'local-maven-settings.xml'
    $wrapperPath = Join-Path $backendDir 'mvnw.cmd'
    $hasTestGoal = @($MavenArgs | Where-Object { $_ -in @('test', 'verify') }).Count -gt 0
    $hasTestSelector = @($MavenArgs | Where-Object { $_ -like '-Dtest=*' }).Count -gt 0
    if ($hasTestGoal -and -not $hasTestSelector) {
        $MavenArgs = @('-Dtest=**/*Test,**/*IT') + $MavenArgs
    }
    $mavenArguments = @('-s', $settingsPath, '-B') + $MavenArgs
    & $wrapperPath @mavenArguments
    $mavenExitCode = $LASTEXITCODE
    if ($mavenExitCode -eq 0 -and $null -ne $oracleEnvironment.DdlPath) {
        Invoke-OracleSqlPlus -Environment $oracleEnvironment -Path $oracleEnvironment.DdlPath -WorkingDirectory $backendDir
    }
    exit $mavenExitCode
}
finally {
    Pop-Location
}
