$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$preflightScript = Join-Path $repoRoot 'scripts/doctor-backend-oracle.ps1'
$preflightText = Get-Content -Raw -Encoding UTF8 $preflightScript

function Assert-Condition {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

$requiredVariables = @(
    'DAILY_REPORT_DB_URL',
    'DAILY_REPORT_DB_USER',
    'DAILY_REPORT_DB_PASSWORD',
    'DAILY_REPORT_DB_ENV',
    'DAILY_REPORT_DB_EXPECTED_HOST',
    'DAILY_REPORT_DB_EXPECTED_SERVICE',
    'DAILY_REPORT_DB_EXPECTED_NAME',
    'DAILY_REPORT_DB_EXPECTED_USER',
    'DAILY_REPORT_ALLOW_DDL'
)
$originalValues = @{}

try {
    foreach ($name in $requiredVariables) {
        $originalValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }

    [Environment]::SetEnvironmentVariable('DAILY_REPORT_DB_URL', 'jdbc:oracle:thin:@//oracle-test.invalid:1521/ORCL', 'Process')
    [Environment]::SetEnvironmentVariable('DAILY_REPORT_DB_USER', 'DAILY_REPORT_TEST', 'Process')
    [Environment]::SetEnvironmentVariable('DAILY_REPORT_DB_ENV', 'TEST', 'Process')
    [Environment]::SetEnvironmentVariable('DAILY_REPORT_DB_EXPECTED_HOST', 'oracle-test.invalid', 'Process')
    [Environment]::SetEnvironmentVariable('DAILY_REPORT_DB_EXPECTED_SERVICE', 'ORCL', 'Process')
    [Environment]::SetEnvironmentVariable('DAILY_REPORT_DB_EXPECTED_NAME', 'ORCL', 'Process')
    [Environment]::SetEnvironmentVariable('DAILY_REPORT_DB_EXPECTED_USER', 'DAILY_REPORT_TEST', 'Process')

    $missingPasswordConfig = [IO.Path]::GetTempFileName()
    try {
        @'
DAILY_REPORT_DB_URL=jdbc:oracle:thin:@//oracle-test.invalid:1521/ORCL
DAILY_REPORT_DB_USER=DAILY_REPORT_TEST
DAILY_REPORT_DB_PASSWORD=
DAILY_REPORT_DB_ENV=TEST
DAILY_REPORT_DB_EXPECTED_HOST=oracle-test.invalid
DAILY_REPORT_DB_EXPECTED_SERVICE=ORCL
DAILY_REPORT_DB_EXPECTED_NAME=ORCL
DAILY_REPORT_DB_EXPECTED_USER=DAILY_REPORT_TEST
DAILY_REPORT_ALLOW_DDL=false
'@ | Set-Content -Encoding UTF8 -LiteralPath $missingPasswordConfig

        $output = (& pwsh -NoProfile -File $preflightScript -ConfigPath $missingPasswordConfig 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE

        Assert-Condition ($exitCode -ne 0) 'Oracle preflight must fail when a protected variable is missing.'
        Assert-Condition ($output -match 'DAILY_REPORT_DB_PASSWORD') `
            'Oracle preflight must identify the missing password variable.'
        Assert-Condition ($output -notmatch 'Apache Maven') `
            'Oracle preflight must validate environment variables before invoking Maven.'
        Assert-Condition ($output -notmatch 'oracle-test\.invalid|DAILY_REPORT_TEST') `
            'Oracle preflight output must not disclose configured connection values.'
    }
    finally {
        Remove-Item -LiteralPath $missingPasswordConfig -Force -ErrorAction SilentlyContinue
    }

    $toolVersions = Import-PowerShellDataFile -LiteralPath (Join-Path $repoRoot 'scripts/tool-versions.psd1')
    $wrapperProperties = Get-Content -Encoding UTF8 (Join-Path $repoRoot 'backend/.mvn/wrapper/maven-wrapper.properties')
    $configuredWrapperVersion = (($wrapperProperties | Where-Object { $_ -match '^wrapperVersion=' } |
        Select-Object -First 1) -split '=', 2)[1].Trim()
    Assert-Condition ($configuredWrapperVersion -eq [string]$toolVersions.MavenWrapper) `
        'Maven Wrapper metadata must match the pinned tool version.'
    Assert-Condition ($preflightText -match 'Import-PowerShellDataFile') `
        'Oracle preflight must load the pinned tool versions.'
    Assert-Condition ($preflightText -match 'wrapperVersion') `
        'Oracle preflight must verify the Maven Wrapper version metadata.'

    $wrapperPath = Join-Path $repoRoot 'backend/scripts/test-oracle.cmd'
    $exampleConfig = Join-Path $repoRoot 'backend/config/oracle-test.example.properties'
    if ($IsWindows) {
        $wrapperCommand = '"{0}" -ConfigPath "{1}" -DskipTests compile' -f $wrapperPath, $exampleConfig
        $wrapperOutput = (& cmd.exe /d /c $wrapperCommand 2>&1 | Out-String)
    } else {
        # Linux CI cannot execute the Windows .cmd shim; invoke its PowerShell implementation directly.
        $wrapperScript = Join-Path $repoRoot 'backend/scripts/test-oracle.ps1'
        $wrapperOutput = (& pwsh -NoProfile -File $wrapperScript -ConfigPath $exampleConfig '-DskipTests' 'compile' 2>&1 | Out-String)
    }
    $wrapperExitCode = $LASTEXITCODE
    Assert-Condition ($wrapperExitCode -ne 0) `
        'Oracle wrapper contract must fail before Maven when the example password is empty.'
    Assert-Condition ($wrapperOutput -match 'Oracle test config key is required: DAILY_REPORT_DB_PASSWORD') `
        'Oracle wrapper must reach PowerShell configuration validation.'
    if ($IsWindows) {
        Assert-Condition ($wrapperOutput -notmatch 'is was unexpected') `
            'Oracle wrapper must not fail with a CMD parenthesis parsing error.'
    }

    $temporaryConfig = [IO.Path]::GetTempFileName()
    try {
        @'
DAILY_REPORT_DB_URL=jdbc:oracle:thin:@//oracle-test.invalid:1521/ORCL
DAILY_REPORT_DB_USER=DAILY_REPORT_TEST
DAILY_REPORT_DB_PASSWORD=contract-password
DAILY_REPORT_DB_ENV=TEST
DAILY_REPORT_DB_EXPECTED_HOST=oracle-test.invalid
DAILY_REPORT_DB_EXPECTED_SERVICE=ORCL
DAILY_REPORT_DB_EXPECTED_NAME=ORCL
DAILY_REPORT_DB_EXPECTED_USER=DAILY_REPORT_TEST
DAILY_REPORT_ALLOW_DDL=false
SESSION_COOKIE_SECURE=false
'@ | Set-Content -Encoding UTF8 -LiteralPath $temporaryConfig

        $doctorOutput = (& pwsh -NoProfile -File $preflightScript -ConfigPath $temporaryConfig 2>&1 | Out-String)
        $doctorExitCode = $LASTEXITCODE
        Assert-Condition ($doctorExitCode -eq 0) `
            'Oracle backend preflight must accept a complete explicit configuration file.'
        Assert-Condition ($doctorOutput -notmatch 'contract-password|oracle-test\.invalid|DAILY_REPORT_TEST') `
            'Oracle backend preflight must not disclose explicit configuration values.'
    }
    finally {
        Remove-Item -LiteralPath $temporaryConfig -Force -ErrorAction SilentlyContinue
    }
}
finally {
    foreach ($name in $requiredVariables) {
        [Environment]::SetEnvironmentVariable($name, $originalValues[$name], 'Process')
    }
}

Write-Output 'Oracle preflight contract tests passed.'
