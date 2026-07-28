[CmdletBinding()]
param(
    [string]$DataPath = (Join-Path $PSScriptRoot 'F-002_日報登録_表示データ.json'),
    [string]$OutputPath = (Join-Path $PSScriptRoot 'F-002_日報登録_コード品質確認.html'),
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$sharedGenerator = Join-Path $PSScriptRoot '..\F-001_ログイン\F-001_ログイン_生成.ps1'
if (-not (Test-Path -LiteralPath $sharedGenerator -PathType Leaf)) {
    throw "Shared quality report generator does not exist: $sharedGenerator"
}

$arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $sharedGenerator, '-DataPath', $DataPath, '-OutputPath', $OutputPath)
if ($ValidateOnly) {
    $arguments += '-ValidateOnly'
}

& pwsh @arguments
exit $LASTEXITCODE
