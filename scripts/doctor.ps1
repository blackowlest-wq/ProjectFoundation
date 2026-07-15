[CmdletBinding(PositionalBinding = $false)]
param()

$ErrorActionPreference = 'Continue'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$versions = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'tool-versions.psd1')
$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$isWindowsHost = if ($null -ne (Get-Variable IsWindows -ErrorAction SilentlyContinue)) { [bool]$IsWindows } else { $env:OS -eq 'Windows_NT' }
$npmCommand = if ($isWindowsHost) { 'npm.cmd' } else { 'npm' }

function Write-Result {
    param([ValidateSet('PASS', 'WARN', 'FAIL')][string]$Status, [string]$Name, [string]$Message)
    Write-Host ("{0,-5} {1}: {2}" -f $Status, $Name, $Message)
    if ($Status -eq 'FAIL') { $failures.Add($Name) }
    if ($Status -eq 'WARN') { $warnings.Add($Name) }
}

function Get-VersionText {
    param([string]$Command, [string[]]$Arguments = @('--version'))
    $commandInfo = Get-Command $Command -ErrorAction SilentlyContinue
    if ($null -eq $commandInfo) { return $null }
    (& $commandInfo.Source @Arguments 2>&1 | Out-String).Trim()
}

if ($PSVersionTable.PSVersion.Major -ge 7) {
    Write-Result PASS 'PowerShell' $PSVersionTable.PSVersion.ToString()
}
else {
    Write-Result FAIL 'PowerShell' 'PowerShell 7 or later is required.'
}

$node = Get-VersionText 'node'
$npm = Get-VersionText $npmCommand
if ($null -eq $node -or $null -eq $npm) {
    Write-Result FAIL 'Node/npm' 'Node.js and npm are required.'
}
else {
    $node = $node -replace '^v', ''
    if ($node -eq $versions.Node -and $npm -eq $versions.Npm) {
        Write-Result PASS 'Node/npm' "$node / $npm"
    }
    else {
        Write-Result FAIL 'Node/npm' "required $($versions.Node) / $($versions.Npm)"
    }
}

$javaOutput = if (Get-Command java -ErrorAction SilentlyContinue) { java -version 2>&1 | Out-String } else { $null }
$javaPattern = 'version "{0}' -f [regex]::Escape($versions.Java)
if ($null -eq $javaOutput -or $javaOutput -notmatch $javaPattern) {
    Write-Result FAIL 'Java' "major $($versions.Java) is required"
}
else {
    Write-Result PASS 'Java' "major $($versions.Java)"
}

$wrapperProperties = Join-Path $repoRoot 'backend/.mvn/wrapper/maven-wrapper.properties'
$wrapperVersion = if (Test-Path $wrapperProperties) { (Select-String -Path $wrapperProperties -Pattern '^wrapperVersion=(.+)$').Matches.Groups[1].Value } else { $null }
$mavenOutput = if (Test-Path (Join-Path $repoRoot 'backend/mvnw.cmd')) { & (Join-Path $repoRoot 'backend/mvnw.cmd') --version 2>&1 | Out-String } else { $null }
if ($null -eq $mavenOutput -or $mavenOutput -notmatch "Apache Maven $([regex]::Escape($versions.Maven))" -or $wrapperVersion -ne $versions.MavenWrapper) {
    Write-Result FAIL 'Maven' "Wrapper $($versions.MavenWrapper) / core $($versions.Maven) is required"
}
else {
    Write-Result PASS 'Maven' "Wrapper $wrapperVersion / core $($versions.Maven)"
}

$lefthook = Get-VersionText $npmCommand @('exec', '--', 'lefthook', 'version')
if ($null -eq $lefthook -or $lefthook -notmatch [regex]::Escape($versions.Lefthook)) {
    Write-Result FAIL 'Lefthook' "version $($versions.Lefthook) is required"
}
else {
    Write-Result PASS 'Lefthook' $versions.Lefthook
}

$gitleaksCandidates = @(
    (Join-Path $repoRoot ".tools/gitleaks/$($versions.Gitleaks)/gitleaks.exe"),
    (Join-Path $repoRoot ".tools/gitleaks/$($versions.Gitleaks)/gitleaks")
)
$gitleaksPath = $gitleaksCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if ($null -eq $gitleaksPath) {
    $command = Get-Command gitleaks -ErrorAction SilentlyContinue
    if ($null -ne $command) { $gitleaksPath = $command.Source }
}
$gitleaksVersion = if ($null -ne $gitleaksPath) { Get-VersionText $gitleaksPath @('version') } else { $null }
if ($null -eq $gitleaksVersion -or $gitleaksVersion -notmatch [regex]::Escape($versions.Gitleaks)) {
    Write-Result FAIL 'Gitleaks' "version $($versions.Gitleaks) is required"
}
else {
    Write-Result PASS 'Gitleaks' $versions.Gitleaks
}

$playwrightPackage = Join-Path $repoRoot 'frontend/node_modules/@playwright/test/package.json'
$playwrightVersion = if (Test-Path $playwrightPackage) { (Get-Content -Raw -Encoding UTF8 $playwrightPackage | ConvertFrom-Json).version } else { $null }
$browserRoot = if ($isWindowsHost) { Join-Path $env:LOCALAPPDATA 'ms-playwright' } else { Join-Path $HOME '.cache/ms-playwright' }
$chromiumInstalled = Test-Path (Join-Path $browserRoot 'chromium-*')
if ($playwrightVersion -ne $versions.Playwright -or -not $chromiumInstalled) {
    Write-Result FAIL 'Playwright' "version $($versions.Playwright) and Chromium are required"
}
else {
    Write-Result PASS 'Playwright' "$playwrightVersion and Chromium"
}

$oracleConfig = Join-Path $repoRoot 'backend/config/oracle-test.properties'
$oracleKeys = @('DAILY_REPORT_DB_URL', 'DAILY_REPORT_DB_USER', 'DAILY_REPORT_DB_PASSWORD', 'DAILY_REPORT_DB_ENV', 'DAILY_REPORT_DB_EXPECTED_HOST', 'DAILY_REPORT_DB_EXPECTED_SERVICE', 'DAILY_REPORT_DB_EXPECTED_NAME', 'DAILY_REPORT_DB_EXPECTED_USER')
$oracleFileValues = @{}
if (Test-Path -LiteralPath $oracleConfig) {
    foreach ($line in Get-Content -Encoding UTF8 -LiteralPath $oracleConfig) {
        if ($line -match '^\s*([A-Za-z0-9_.-]+)\s*=(.*)$') {
            $oracleFileValues[$Matches[1]] = $Matches[2].Trim()
        }
    }
}

$oracleAvailable = $true
foreach ($key in $oracleKeys) {
    # How: process環境変数を優先し、未設定のキーだけGit管理外のローカル設定で補完して必須値を判定する。
    # Why not: 設定ファイルの存在だけを確認すると、必須キー不足をOracle接続開始後まで見逃すため。
    $value = [Environment]::GetEnvironmentVariable($key, 'Process')
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = $oracleFileValues[$key]
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
        $oracleAvailable = $false
        break
    }
}
if ($oracleAvailable) {
    Write-Result PASS 'Oracle config' 'local config or protected process environment is present'
}
else {
    Write-Result WARN 'Oracle config' 'Oracle integration is unavailable; Quick/Full remain usable'
}

foreach ($port in @(5173, 8080)) {
    $listener = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($null -eq $listener) {
        Write-Result PASS "Port $port" 'available'
    }
    else {
        Write-Result WARN "Port $port" 'already in use'
    }
}

if ($failures.Count -gt 0) {
    Write-Host "FAILURES: $($failures -join ', ')"
    exit 1
}
if ($warnings.Count -gt 0) {
    Write-Host "WARNINGS: $($warnings -join ', ')"
}
exit 0
