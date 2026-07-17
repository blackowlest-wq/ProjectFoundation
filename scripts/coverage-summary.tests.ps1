$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$summaryScript = Join-Path $repoRoot 'scripts/write-coverage-summary.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('projectfoundation-coverage-summary-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null

function Assert-Condition {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

$frontendPath = Join-Path $testRoot 'coverage-summary.json'
$backendPath = Join-Path $testRoot 'jacoco.xml'
$summaryPath = Join-Path $testRoot 'summary.md'
$frontendFixture = [ordered]@{
    total = [ordered]@{
        statements = [ordered]@{ pct = 91.11 }
        branches = [ordered]@{ pct = 88.88 }
        functions = [ordered]@{ pct = 92.00 }
        lines = [ordered]@{ pct = 90.00 }
    }
} | ConvertTo-Json -Depth 4
$backendFixture = @'
<report name="test">
  <counter type="INSTRUCTION" missed="10" covered="90" />
  <counter type="BRANCH" missed="1" covered="9" />
  <counter type="METHOD" missed="2" covered="18" />
  <counter type="LINE" missed="3" covered="27" />
</report>
'@
Set-Content -LiteralPath $frontendPath -Value $frontendFixture -Encoding UTF8
Set-Content -LiteralPath $backendPath -Value $backendFixture -Encoding UTF8

$originalSummary = [Environment]::GetEnvironmentVariable('GITHUB_STEP_SUMMARY', 'Process')
try {
    [Environment]::SetEnvironmentVariable('GITHUB_STEP_SUMMARY', $summaryPath, 'Process')
    & pwsh -NoProfile -File $summaryScript -FrontendSummaryPath $frontendPath -BackendXmlPath $backendPath
    Assert-Condition ($LASTEXITCODE -eq 0) 'Coverage summary generation must succeed for valid reports.'

    $summary = Get-Content -Raw -Encoding UTF8 $summaryPath
    foreach ($metric in @('Statements', 'Branches', 'Functions', 'Lines', 'Instructions', 'Methods')) {
        Assert-Condition ($summary -match [regex]::Escape($metric)) "Coverage summary is missing the $metric metric."
    }
    foreach ($percentage in @('91.11%', '88.88%', '92.00%', '90.00%')) {
        Assert-Condition ($summary -match [regex]::Escape($percentage)) "Coverage summary is missing $percentage."
    }
    Assert-Condition ($summary -match 'PASS') 'Coverage summary must show the gate result.'

    $missingPath = Join-Path $testRoot 'missing.json'
    & pwsh -NoProfile -File $summaryScript -FrontendSummaryPath $missingPath 2>&1 | Out-String | Out-Null
    Assert-Condition ($LASTEXITCODE -ne 0) 'Coverage summary must fail when an input report is missing.'
}
finally {
    [Environment]::SetEnvironmentVariable('GITHUB_STEP_SUMMARY', $originalSummary, 'Process')
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}

Write-Output 'Coverage summary contract tests passed.'
