$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$preflightScript = Join-Path $repoRoot 'scripts/doctor-backend-oracle.ps1'

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
    'DAILY_REPORT_DB_EXPECTED_USER'
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

    $output = (& pwsh -NoProfile -File $preflightScript 2>&1 | Out-String)
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
    foreach ($name in $requiredVariables) {
        [Environment]::SetEnvironmentVariable($name, $originalValues[$name], 'Process')
    }
}

Write-Output 'Oracle preflight contract tests passed.'
