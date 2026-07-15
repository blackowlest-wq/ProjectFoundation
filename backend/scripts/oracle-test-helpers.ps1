$ErrorActionPreference = 'Stop'

function Read-PropertiesFile {
    param([Parameter(Mandatory)][string]$Path)

    $result = @{}
    Get-Content -Encoding UTF8 -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith('#')) {
            return
        }

        $separator = $line.IndexOf('=')
        if ($separator -le 0) {
            throw 'Invalid Oracle config line. Expected KEY=VALUE.'
        }

        $key = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1).Trim()
        $result[$key] = $value
    }
    $result
}

function Get-ConfiguredValue {
    param(
        [Parameter(Mandatory)][hashtable]$Values,
        [Parameter(Mandatory)][string]$Key
    )

    if ($Values.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace($Values[$Key])) {
        return [string]$Values[$Key]
    }
    [Environment]::GetEnvironmentVariable($Key, 'Process')
}

function Require-ConfiguredValue {
    param(
        [Parameter(Mandatory)][hashtable]$Values,
        [Parameter(Mandatory)][string]$Key
    )

    $value = Get-ConfiguredValue -Values $Values -Key $Key
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Oracle test config key is required: $Key"
    }
    $Values[$Key] = $value
    $value
}

function Get-OracleTestEnvironment {
    param(
        [Parameter(Mandatory)][string]$BackendDir,
        [string]$ConfigPath,
        [switch]$AllowDdl,
        [string]$DdlScript
    )

    $defaultConfigPath = Join-Path $BackendDir 'config/oracle-test.properties'
    $requiredKeys = @(
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

    $configWasExplicit = -not [string]::IsNullOrWhiteSpace($ConfigPath)
    if (-not $configWasExplicit) {
        $ConfigPath = $defaultConfigPath
    }

    $values = @{}
    if (Test-Path -LiteralPath $ConfigPath) {
        foreach ($entry in (Read-PropertiesFile -Path $ConfigPath).GetEnumerator()) {
            $values[$entry.Key] = $entry.Value
        }
    }
    elseif ($configWasExplicit) {
        throw "Oracle test config was not found: $ConfigPath"
    }

    foreach ($key in $requiredKeys) {
        [void](Require-ConfiguredValue -Values $values -Key $key)
    }
    $sessionCookieSecure = Get-ConfiguredValue -Values $values -Key 'SESSION_COOKIE_SECURE'
    $values['SESSION_COOKIE_SECURE'] = if ([string]::IsNullOrWhiteSpace($sessionCookieSecure)) { 'false' } else { $sessionCookieSecure }

    if ($values.DAILY_REPORT_DB_ENV -cne 'TEST') {
        throw 'Oracle environment must be TEST.'
    }
    if ($values.DAILY_REPORT_DB_USER -cne $values.DAILY_REPORT_DB_EXPECTED_USER) {
        throw 'Oracle user does not match the expected test user.'
    }
    if ($values.DAILY_REPORT_DB_USER -match '^(SYS|SYSTEM)$|PROD') {
        throw 'Administrative or production-like Oracle users are forbidden.'
    }

    $urlPattern = '^jdbc:oracle:thin:@//(?<host>[^:/]+):(?<port>[0-9]+)/(?<service>[^/?]+)$'
    $urlMatch = [regex]::Match($values.DAILY_REPORT_DB_URL, $urlPattern)
    if (-not $urlMatch.Success) {
        throw 'Oracle JDBC URL must use the //host:port/service form.'
    }
    if (-not $urlMatch.Groups['host'].Value.Equals($values.DAILY_REPORT_DB_EXPECTED_HOST, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Oracle host does not match the expected test host.'
    }
    if (-not $urlMatch.Groups['service'].Value.Equals($values.DAILY_REPORT_DB_EXPECTED_SERVICE, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Oracle service does not match the expected test service.'
    }

    $ddlPath = $null
    $ddlConfigEnabled = $values.DAILY_REPORT_ALLOW_DDL -ieq 'true'
    if ($ddlConfigEnabled -and -not $AllowDdl) {
        throw 'DAILY_REPORT_ALLOW_DDL=true requires the -AllowDdl switch.'
    }
    if ($AllowDdl -and [string]::IsNullOrWhiteSpace($DdlScript)) {
        throw '-AllowDdl requires an explicit -DdlScript path.'
    }
    if (-not [string]::IsNullOrWhiteSpace($DdlScript)) {
        if (-not $AllowDdl -or -not $ddlConfigEnabled) {
            throw 'DDL requires both -AllowDdl and DAILY_REPORT_ALLOW_DDL=true.'
        }

        $ddlRoot = [IO.Path]::GetFullPath((Join-Path $BackendDir 'src/main/resources/db/oracle'))
        $candidate = if ([IO.Path]::IsPathRooted($DdlScript)) {
            [IO.Path]::GetFullPath($DdlScript)
        }
        else {
            [IO.Path]::GetFullPath((Join-Path $BackendDir $DdlScript))
        }
        $ddlRootPrefix = $ddlRoot.TrimEnd('\') + [IO.Path]::DirectorySeparatorChar
        if (-not $candidate.StartsWith($ddlRootPrefix, [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetExtension($candidate) -ine '.sql' -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw 'DdlScript must be an existing .sql file under backend/src/main/resources/db/oracle.'
        }
        $ddlPath = $candidate
    }

    [pscustomobject]@{
        Values = $values
        UrlMatch = $urlMatch
        DdlPath = $ddlPath
    }
}

function Set-OracleTestEnvironment {
    param(
        [Parameter(Mandatory)][pscustomobject]$Environment,
        [switch]$AllowDdl
    )

    foreach ($entry in $Environment.Values.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
    [Environment]::SetEnvironmentVariable(
        'DAILY_REPORT_DDL_CLI_APPROVED',
        $(if ($AllowDdl) { 'true' } else { 'false' }),
        'Process'
    )
}

function Get-OracleTarget {
    param([Parameter(Mandatory)][pscustomobject]$Environment)

    "$($Environment.UrlMatch.Groups['host'].Value):$($Environment.UrlMatch.Groups['port'].Value)/$($Environment.UrlMatch.Groups['service'].Value)"
}

function Get-OracleTestIdentity {
    param([Parameter(Mandatory)][pscustomobject]$Environment)

    $sqlPlus = Get-Command sqlplus -ErrorAction SilentlyContinue
    if ($null -eq $sqlPlus) {
        throw 'Oracle SQL execution requires sqlplus on the isolated Oracle runner.'
    }

    $target = Get-OracleTarget -Environment $Environment
    $commands = @(
        'whenever sqlerror exit sql.sqlcode',
        "connect $($Environment.Values.DAILY_REPORT_DB_USER)/$($Environment.Values.DAILY_REPORT_DB_PASSWORD)@$target",
        'set heading off feedback off pagesize 0 verify off echo off',
        "SELECT SYS_CONTEXT('USERENV', 'DB_NAME') || '|' || SYS_CONTEXT('USERENV', 'SERVICE_NAME') || '|' || SYS_CONTEXT('USERENV', 'SESSION_USER') FROM dual;",
        'exit'
    ) -join [Environment]::NewLine
    $output = @($commands | & $sqlPlus.Source -L -S /nolog 2>$null | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^[^|]+\|[^|]+\|[^|]+$' })
    if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0) {
        throw 'Oracle identity query failed.'
    }

    $parts = $output[-1].Split('|')
    [pscustomobject]@{
        DbName = $parts[0]
        ServiceName = $parts[1]
        SessionUser = $parts[2]
    }
}

function Assert-OracleTestIdentity {
    param([Parameter(Mandatory)][pscustomobject]$Environment)

    $identity = Get-OracleTestIdentity -Environment $Environment
    $checks = @(
        @('DB_NAME', $identity.DbName, $Environment.Values.DAILY_REPORT_DB_EXPECTED_NAME),
        @('SERVICE_NAME', $identity.ServiceName, $Environment.Values.DAILY_REPORT_DB_EXPECTED_SERVICE),
        @('SESSION_USER', $identity.SessionUser, $Environment.Values.DAILY_REPORT_DB_EXPECTED_USER)
    )
    foreach ($check in $checks) {
        if (-not $check[1].Equals($check[2], [StringComparison]::OrdinalIgnoreCase)) {
            throw "Oracle test identity mismatch: $($check[0])"
        }
    }
}

function Invoke-OracleSqlPlus {
    param(
        [Parameter(Mandatory)][pscustomobject]$Environment,
        [Parameter(Mandatory)][string]$Path,
        [hashtable]$Variables = @{},
        [string]$WorkingDirectory
    )

    $sqlPlus = Get-Command sqlplus -ErrorAction SilentlyContinue
    if ($null -eq $sqlPlus) {
        throw 'Oracle SQL execution requires sqlplus on the isolated Oracle runner.'
    }

    $target = Get-OracleTarget -Environment $Environment
    $defineCommands = @()
    foreach ($entry in $Variables.GetEnumerator()) {
        if ($entry.Key -notmatch '^[A-Za-z][A-Za-z0-9_]*$' -or [string]$entry.Value -match "['`r`n]") {
            throw 'Oracle SQL variable names or values are invalid.'
        }
        $defineCommands += "define $($entry.Key) = '$($entry.Value)'"
    }
    $scriptPath = [IO.Path]::GetFullPath($Path)
    $runDirectory = (Get-Location).Path
    $restoreLocation = $false
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $runDirectory = [IO.Path]::GetFullPath($WorkingDirectory)
        $runDirectoryPrefix = $runDirectory.TrimEnd('\') + [IO.Path]::DirectorySeparatorChar
        if (-not $scriptPath.StartsWith($runDirectoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Oracle SQL script must be under the SQLPlus working directory.'
        }
        $scriptPath = [IO.Path]::GetRelativePath($runDirectory, $scriptPath).Replace('\', '/')
        Push-Location $runDirectory
        $restoreLocation = $true
    }
    try {
        $commands = @(
        'whenever sqlerror exit sql.sqlcode',
        "connect $($Environment.Values.DAILY_REPORT_DB_USER)/$($Environment.Values.DAILY_REPORT_DB_PASSWORD)@$target"
        ) + $defineCommands + @(
            "@$scriptPath",
            'exit'
        ) -join [Environment]::NewLine
        $null = $commands | & $sqlPlus.Source -L /nolog 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw 'Oracle SQL execution failed.'
        }
    }
    finally {
        if ($restoreLocation) {
            Pop-Location
        }
    }
}
