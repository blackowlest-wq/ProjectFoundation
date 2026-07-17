$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
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
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory)][string]$Message)
    [void]$script:failures.Add($Message)
}

$missingVariables = @(
    $requiredVariables | Where-Object {
        [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_, 'Process'))
    }
)
if ($missingVariables.Count -gt 0) {
    Add-Failure ("Missing protected environment variables: {0}" -f ($missingVariables -join ', '))
}

$databaseEnvironment = [Environment]::GetEnvironmentVariable('DAILY_REPORT_DB_ENV', 'Process')
if ($databaseEnvironment -and $databaseEnvironment -cne 'TEST') {
    Add-Failure 'DAILY_REPORT_DB_ENV must be TEST.'
}

$exampleConfig = Join-Path $repoRoot 'backend/config/oracle-test.example.properties'
if (-not (Test-Path -LiteralPath $exampleConfig -PathType Leaf)) {
    Add-Failure 'Oracle test example configuration is missing.'
}

$toolVersionsPath = Join-Path $repoRoot 'scripts/tool-versions.psd1'
$wrapperPropertiesPath = Join-Path $repoRoot 'backend/.mvn/wrapper/maven-wrapper.properties'
if (-not (Test-Path -LiteralPath $toolVersionsPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $wrapperPropertiesPath -PathType Leaf)) {
    Add-Failure 'Maven Wrapper version metadata is missing.'
}
else {
    $toolVersions = Import-PowerShellDataFile -LiteralPath $toolVersionsPath
    $expectedWrapperVersion = [string]$toolVersions.MavenWrapper
    $wrapperVersionLine = Get-Content -Encoding UTF8 $wrapperPropertiesPath |
        Where-Object { $_ -match '^wrapperVersion=' } |
        Select-Object -First 1
    $configuredWrapperVersion = if ($wrapperVersionLine) {
        ($wrapperVersionLine -split '=', 2)[1].Trim()
    }
    else {
        ''
    }
    if ([string]::IsNullOrWhiteSpace($expectedWrapperVersion) -or
        $configuredWrapperVersion -cne $expectedWrapperVersion) {
        Add-Failure 'Maven Wrapper version does not match the pinned tool version.'
    }
}

if ($failures.Count -eq 0) {
    try {
        $javaCommand = Get-Command java -ErrorAction Stop
        $javaExecutable = if ($javaCommand.Path) { $javaCommand.Path } else { $javaCommand.Source }
        $javaVersionOutput = (& $javaExecutable '-version' 2>&1 | Out-String)
        $javaVersion = [regex]::Match($javaVersionOutput, 'version\s+"(?<major>\d+)').Groups['major'].Value
        if ($LASTEXITCODE -ne 0 -or $javaVersion -ne '21') {
            Add-Failure 'Java 21 is required for Oracle tests.'
        }
    }
    catch {
        Add-Failure 'Java 21 is required for Oracle tests.'
    }

    $mavenWrapper = if ($IsWindows) {
        Join-Path $repoRoot 'backend/mvnw.cmd'
    }
    else {
        Join-Path $repoRoot 'backend/mvnw'
    }
    if (-not (Test-Path -LiteralPath $mavenWrapper -PathType Leaf)) {
        Add-Failure 'Maven Wrapper is missing.'
    }
    else {
        try {
            $mavenVersionOutput = (& $mavenWrapper '--version' 2>&1 | Out-String)
            if ($LASTEXITCODE -ne 0 -or $mavenVersionOutput -notmatch 'Apache Maven 3\.9\.16') {
                Add-Failure 'Maven 3.9.16 is required for Oracle tests.'
            }
        }
        catch {
            Add-Failure 'Maven 3.9.16 is required for Oracle tests.'
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Error ($failures -join [Environment]::NewLine)
    exit 1
}

Write-Output 'Oracle backend preflight passed: protected TEST configuration, Java 21, and Maven 3.9.16 are available.'
