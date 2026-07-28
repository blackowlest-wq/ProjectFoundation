$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runner = Join-Path $repoRoot 'scripts/check-quality-reports.ps1'
$featurePath = Join-Path $repoRoot 'docs/AI活用開発研究/コード品質確認画面/F-001_ログイン'

if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
    throw 'Quality report batch runner must exist.'
}

$output = (& pwsh -NoProfile -ExecutionPolicy Bypass -File $runner -FeaturePath $featurePath -ValidateOnly 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) {
    throw "Quality report batch validation failed: $output"
}
if ($output -notmatch 'F-001_ログイン') {
    throw 'Quality report batch output must identify the validated feature.'
}
if ($output -notmatch 'Quality report contract passed') {
    throw 'Quality report batch must run the generic quality report contract.'
}

Write-Output 'Quality report batch contract passed.'
