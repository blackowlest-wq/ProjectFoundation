[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$MavenArgs = @("test"),
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = Resolve-Path (Join-Path $scriptDir "..")

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $backendDir "config/oracle-test.properties"
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    $examplePath = Join-Path $backendDir "config/oracle-test.example.properties"
    Write-Error "Oracle test config was not found: $ConfigPath. Copy $examplePath to $ConfigPath and set the password."
}

$values = @{}
Get-Content -Encoding UTF8 -LiteralPath $ConfigPath | ForEach-Object {
    $line = $_.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith("#")) {
        return
    }

    $separator = $line.IndexOf("=")
    if ($separator -le 0) {
        Write-Error "Invalid config line. Expected KEY=VALUE: $line"
    }

    $key = $line.Substring(0, $separator).Trim()
    $value = $line.Substring($separator + 1).Trim()
    $values[$key] = $value
}

$requiredKeys = @("DAILY_REPORT_DB_URL", "DAILY_REPORT_DB_USER", "DAILY_REPORT_DB_PASSWORD")
foreach ($key in $requiredKeys) {
    if (-not $values.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($values[$key])) {
        Write-Error "Oracle test config key is required: $key"
    }
}

foreach ($entry in $values.GetEnumerator()) {
    [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
}

Push-Location $backendDir
try {
    $settingsPath = Join-Path $backendDir "local-maven-settings.xml"
    if (Test-Path -LiteralPath $settingsPath) {
        & mvn.cmd -s $settingsPath @MavenArgs
    }
    else {
        & mvn.cmd @MavenArgs
    }
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
