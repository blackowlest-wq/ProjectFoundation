[CmdletBinding()]
param(
    [string]$ProjectRoot
)

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PWD.Path }
if (-not $ProjectRoot) {
    $ProjectRoot = Split-Path -Parent $scriptRoot
}

$violations = @()
$frontendSource = Join-Path $ProjectRoot 'frontend\src'
$backendMain = Join-Path $ProjectRoot 'backend\src\main'

if (Test-Path -LiteralPath $frontendSource) {
    $violations += Get-ChildItem -LiteralPath $frontendSource -Recurse -File |
        Where-Object { $_.Name -match '\.(test|spec)\..+$' } |
        ForEach-Object { "frontend/src test file: $($_.FullName)" }
}

if (Test-Path -LiteralPath $backendMain) {
    $violations += Get-ChildItem -LiteralPath $backendMain -Recurse -File |
        Where-Object { $_.Name -match '(Test|IT)\.java$' } |
        ForEach-Object { "backend/src/main test file: $($_.FullName)" }
}

if ($violations.Count -gt 0) {
    Write-Error ("Test files must be placed under the test source directories:`n" + ($violations -join "`n"))
    exit 1
}

Write-Output 'Test layout check passed.'
