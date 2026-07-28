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

$isWindowsHost = if ($null -ne (Get-Variable IsWindows -ErrorAction SilentlyContinue)) { [bool]$IsWindows } else { $env:OS -eq 'Windows_NT' }
$mappedDriveLetter = $null
$executionBackendDir = $backendDir
try {
    # How: Windowsのforked JVMへ日本語を含む絶対パスを渡すとJaCoCo agent引数が文字化けするため、対象ルートをASCIIドライブへ一時マッピングする。
    if ($isWindowsHost -and $backendDir -match '[^\x00-\x7F]') {
        $repoRoot = (Resolve-Path (Join-Path $backendDir '..')).Path
        $usedDriveLetters = @((Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Name) |
                ForEach-Object { $_.ToUpperInvariant() })
        $availableDriveLetter = @('Z', 'Y', 'X', 'W', 'V', 'U', 'T', 'S', 'R', 'Q', 'P') |
                Where-Object { $usedDriveLetters -notcontains $_ } |
                Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace($availableDriveLetter)) {
            throw 'No free drive letter is available for the temporary Oracle test path mapping.'
        }
        & subst "${availableDriveLetter}:" $repoRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to create temporary Oracle test path mapping on ${availableDriveLetter}:."
        }
        $mappedDriveLetter = $availableDriveLetter
        $executionBackendDir = "${availableDriveLetter}:\backend"
        Write-Host "Oracle test path mapped to ${availableDriveLetter}: for Windows non-ASCII path compatibility."
    }

    Push-Location $executionBackendDir
    try {
        $settingsPath = Join-Path $executionBackendDir 'local-maven-settings.xml'
        $wrapperPath = Join-Path $executionBackendDir 'mvnw.cmd'
        $hasTestGoal = @($MavenArgs | Where-Object { $_ -in @('test', 'verify') }).Count -gt 0
        $hasTestSelector = @($MavenArgs | Where-Object { $_ -like '-Dtest=*' }).Count -gt 0
        if ($hasTestGoal -and -not $hasTestSelector) {
            $MavenArgs = @('-Dtest=**/*Test,**/*IT') + $MavenArgs
        }
        $mavenArguments = @('-s', $settingsPath, '-B') + $MavenArgs
        & $wrapperPath @mavenArguments
        $mavenExitCode = $LASTEXITCODE
        if ($mavenExitCode -eq 0 -and $null -ne $oracleEnvironment.DdlPath) {
            Invoke-OracleSqlPlus -Environment $oracleEnvironment -Path $oracleEnvironment.DdlPath -WorkingDirectory $executionBackendDir
        }
        exit $mavenExitCode
    }
    finally {
        Pop-Location
    }
}
finally {
    if ($null -ne $mappedDriveLetter) {
        & subst "${mappedDriveLetter}:" /d | Out-Null
    }
}
