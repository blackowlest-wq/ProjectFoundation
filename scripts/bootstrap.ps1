[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet('All', 'Node', 'Maven', 'Playwright', 'Lefthook', 'Gitleaks')]
    [string]$Component = 'All',
    [switch]$Offline
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$versions = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'tool-versions.psd1')
$isWindowsHost = if ($null -ne (Get-Variable IsWindows -ErrorAction SilentlyContinue)) { [bool]$IsWindows } else { $env:OS -eq 'Windows_NT' }
$npmCommand = if ($isWindowsHost) { 'npm.cmd' } else { 'npm' }
$mavenCommand = if ($isWindowsHost) { Join-Path $repoRoot 'backend/mvnw.cmd' } else { Join-Path $repoRoot 'backend/mvnw' }

function Invoke-RequiredCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [object[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$Description
    )

    Write-Host "==> $Description"
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

function Get-CommandVersion {
    param([Parameter(Mandatory)][string]$Command, [string[]]$Arguments = @('--version'))

    $output = & $Command @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read version from $Command."
    }
    $output.Trim()
}

function Assert-NodeToolchain {
    $nodeVersion = (Get-CommandVersion -Command 'node') -replace '^v', ''
    $npmVersion = Get-CommandVersion -Command $npmCommand
    if ($nodeVersion -ne $versions.Node) {
        throw "Node.js $($versions.Node) is required; found $nodeVersion."
    }
    if ($npmVersion -ne $versions.Npm) {
        throw "npm $($versions.Npm) is required; found $npmVersion."
    }
}

function Assert-JavaToolchain {
    $versionOutput = java -version 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw 'Java is not available.'
    }
    $match = [regex]::Match($versionOutput, 'version "(?<version>\d+)')
    if (-not $match.Success -or $match.Groups['version'].Value -ne $versions.Java) {
        throw "Java major version $($versions.Java) is required."
    }
}

function Get-GitleaksAsset {
    if ($isWindowsHost) {
        return @{ Name = "gitleaks_$($versions.Gitleaks)_windows_x64.zip"; Archive = 'zip'; Binary = 'gitleaks.exe' }
    }
    return @{ Name = "gitleaks_$($versions.Gitleaks)_linux_x64.tar.gz"; Archive = 'tar.gz'; Binary = 'gitleaks' }
}

function Get-GitleaksPath {
    $asset = Get-GitleaksAsset
    $path = Join-Path $repoRoot ".tools/gitleaks/$($versions.Gitleaks)/$($asset.Binary)"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        return $path
    }
    $existing = Get-Command gitleaks -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        return $existing.Source
    }
    $null
}

function Install-Gitleaks {
    $asset = Get-GitleaksAsset
    $destination = Join-Path $repoRoot ".tools/gitleaks/$($versions.Gitleaks)"
    $binaryPath = Join-Path $destination $asset.Binary
    if (Test-Path -LiteralPath $binaryPath -PathType Leaf) {
        $versionOutput = Get-CommandVersion -Command $binaryPath -Arguments @('version')
        if ($versionOutput -notmatch [regex]::Escape($versions.Gitleaks)) {
            throw "Gitleaks at the pinned local path is not version $($versions.Gitleaks)."
        }
        Write-Host "Gitleaks $($versions.Gitleaks) is already available."
        return
    }
    $existing = Get-Command gitleaks -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        $versionOutput = Get-CommandVersion -Command $existing.Source -Arguments @('version')
        if ($versionOutput -match [regex]::Escape($versions.Gitleaks)) {
            Write-Host "Gitleaks $($versions.Gitleaks) is already available."
            return
        }
        # A different PATH version does not satisfy the pin; install the pinned local copy.
    }
    if ($Offline) {
        throw "Gitleaks $($versions.Gitleaks) is not installed and offline mode forbids download."
    }

    $downloadRoot = Join-Path ([System.IO.Path]::GetTempPath()) "projectfoundation-gitleaks-$($versions.Gitleaks)"
    New-Item -ItemType Directory -Force -Path $downloadRoot | Out-Null
    $archivePath = Join-Path $downloadRoot $asset.Name
    $checksumName = "gitleaks_$($versions.Gitleaks)_checksums.txt"
    $checksumPath = Join-Path $downloadRoot $checksumName
    $baseUrl = "https://github.com/gitleaks/gitleaks/releases/download/v$($versions.Gitleaks)"
    Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/$($asset.Name)" -OutFile $archivePath
    Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/$checksumName" -OutFile $checksumPath

    $escapedAssetName = [regex]::Escape($asset.Name)
    $checksumLine = Get-Content -Encoding UTF8 -LiteralPath $checksumPath |
        Where-Object { $_ -match "^(?<hash>[0-9a-fA-F]{64})\s+\*?$escapedAssetName\s*$" } |
        Select-Object -First 1
    if ($null -eq $checksumLine) {
        throw "Official checksum for Gitleaks asset was not found."
    }
    $expectedHash = ([regex]::Match($checksumLine, '^[0-9a-fA-F]{64}')).Value.ToLowerInvariant()
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash.ToLowerInvariant()
    if ($expectedHash -ne $actualHash) {
        throw 'Gitleaks archive SHA-256 does not match the official checksum.'
    }

    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    if ($asset.Archive -eq 'zip') {
        Expand-Archive -LiteralPath $archivePath -DestinationPath $destination -Force
    }
    else {
        tar -xzf $archivePath -C $destination
        if ($LASTEXITCODE -ne 0) {
            throw 'Unable to extract Gitleaks archive.'
        }
    }
    if (-not (Test-Path -LiteralPath $binaryPath -PathType Leaf)) {
        throw "Gitleaks binary was not found after extraction: $($asset.Binary)"
    }
}

Push-Location $repoRoot
try {
    if ($Component -in @('All', 'Node', 'Playwright', 'Lefthook')) {
        Assert-NodeToolchain
    }
    if ($Component -in @('All', 'Node')) {
        Invoke-RequiredCommand -Command $npmCommand -Arguments @('ci', '--ignore-scripts') -Description 'root npm ci'
        Invoke-RequiredCommand -Command $npmCommand -Arguments @('--prefix', 'frontend', 'ci', '--ignore-scripts') -Description 'frontend npm ci'
    }
    if ($Component -in @('All', 'Maven')) {
        Assert-JavaToolchain
        Invoke-RequiredCommand -Command $mavenCommand -Arguments @('-f', 'backend/pom.xml', '-s', 'backend/local-maven-settings.xml', '-B', 'dependency:go-offline') -Description 'Maven dependency cache'
    }
    if ($Component -in @('All', 'Playwright')) {
        Invoke-RequiredCommand -Command $npmCommand -Arguments @('--prefix', 'frontend', 'run', 'e2e:install') -Description 'Playwright Chromium installation'
    }
    if ($Component -in @('All', 'Gitleaks')) {
        Install-Gitleaks
    }
    if ($Component -in @('All', 'Lefthook')) {
        Invoke-RequiredCommand -Command $npmCommand -Arguments @('exec', '--', 'lefthook', 'validate') -Description 'Lefthook configuration validation'
        Invoke-RequiredCommand -Command $npmCommand -Arguments @('exec', '--', 'lefthook', 'install') -Description 'Lefthook installation'
    }
    if (-not (Test-Path -LiteralPath 'backend/config/oracle-test.example.properties')) {
        throw 'Oracle test configuration sample is missing.'
    }
    Write-Host 'Bootstrap completed.'
}
finally {
    Pop-Location
}
