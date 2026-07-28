$ErrorActionPreference = 'Stop'

$featureDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$generator = Join-Path $featureDir 'F-001_ログイン_生成.ps1'
$htmlPath = Join-Path $featureDir 'F-001_ログイン_コード品質確認.html'
$dataPath = Join-Path $featureDir 'F-001_ログイン_表示データ.json'

function Invoke-ReportGenerator {
    param(
        [string]$InputDataPath = $dataPath,
        [string]$OutputFilePath = $htmlPath,
        [switch]$ValidateOnly
    )

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $generator, '-DataPath', $InputDataPath, '-OutputPath', $OutputFilePath)
    if ($ValidateOnly) {
        $arguments += '-ValidateOnly'
    }
    $output = @(& pwsh @arguments 2>&1)
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output -join [Environment]::NewLine)
    }
}

function Get-GeneratedData {
    param([string]$GeneratedHtmlPath = $htmlPath)

    $html = Get-Content -LiteralPath $GeneratedHtmlPath -Raw -Encoding UTF8
    $dataJson = [regex]::Match($html, '(?s)<script type="application/json" id="quality-data">(.*?)</script>').Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($dataJson)) {
        throw "Generated HTML does not contain embedded quality data: $GeneratedHtmlPath"
    }
    return $dataJson | ConvertFrom-Json
}

$generation = Invoke-ReportGenerator
if ($generation.ExitCode -ne 0) {
    throw "Report generation failed: $($generation.Output)"
}
$html = Get-Content -LiteralPath $htmlPath -Raw -Encoding UTF8
$data = Get-GeneratedData

foreach ($forbidden in @('総合判定', '承認可能', '承認不可', 'overallStatus')) {
    if ($html.Contains($forbidden)) {
        throw "Forbidden evaluative label remains in generated HTML: $forbidden"
    }
}

foreach ($forbiddenEvidenceColumn in @('<th>実行日時</th>', '<th>証跡コミット</th>', '<th>終了コード</th>', '<th>環境</th>', '<th>鮮度</th>')) {
    if ($html.Contains($forbiddenEvidenceColumn)) {
        throw "Forbidden evidence column remains in generated HTML: $forbiddenEvidenceColumn"
    }
}

foreach ($requiredLabel in @('実行状況', 'Frontend実行状況', 'Backend実行状況', 'Oracle実行状況', '品質ゲート', '証跡状態')) {
    if (-not $html.Contains($requiredLabel)) {
        throw "Required fact label is missing from generated HTML: $requiredLabel"
    }
}

foreach ($acceptance in $data.acceptanceCriteria) {
    if ($null -ne $acceptance.PSObject.Properties['overallStatus']) {
        throw "Acceptance criterion still contains overallStatus: $($acceptance.id)"
    }
}

if (-not $html.Contains('一部未実行')) {
    throw 'Current login snapshot must expose the fact-based partial execution state.'
}

$automatedFindings = @($data.automatedFindings)
$automatedCategories = @($automatedFindings | ForEach-Object { $_.category })
foreach ($forbiddenCategory in @('期待結果・ケース設計不足', '観点判定')) {
    if ($automatedCategories -contains $forbiddenCategory) {
        throw "Semantic review category must not be automated: $forbiddenCategory"
    }
}
if ($automatedCategories -contains '要補足') {
    throw '要補足 must remain an input finding, not an automated finding.'
}
if (-not ($automatedCategories -contains 'ブロッカー')) {
    throw 'Explicit execution blocker must remain visible as an automated fact.'
}
if (-not ($automatedCategories -contains '品質ゲート')) {
    throw 'Quality gate state must remain visible as an automated fact.'
}
if (-not ($automatedCategories -contains '未実行')) {
    throw 'Unexecuted test cases must remain visible as an automated fact.'
}
if (-not $html.Contains('NG・要確認')) {
    throw 'Generated HTML must label automated findings as NG and confirmation items.'
}

$baselineAutomatedFindings = @($data.automatedFindings | ConvertTo-Json -Depth 10 -Compress)
$statusDataPath = Join-Path $featureDir ("F-001_ログイン_レビュー状態変更_{0}.json" -f [guid]::NewGuid().ToString('N'))
$statusHtmlPath = Join-Path $featureDir ("F-001_ログイン_レビュー状態変更_{0}.html" -f [guid]::NewGuid().ToString('N'))
try {
    $statusData = Get-Content -LiteralPath $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    ($statusData.testCases | Where-Object id -eq 'BE-AUTH-010').reviewStatus = 'OK'
    ($statusData.testCases | Where-Object id -eq 'BE-AUTH-012').reviewStatus = 'OK'
    ($statusData.viewpoints | Where-Object id -eq 'VP-EXPECTED-001').reviewStatus = 'OK'
    ($statusData.acceptanceCriteria | Where-Object id -eq 'F-001-AC-003').caseDesignStatus = 'OK'
    $statusData | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $statusDataPath -Encoding UTF8

    $statusGeneration = Invoke-ReportGenerator -InputDataPath $statusDataPath -OutputFilePath $statusHtmlPath
    if ($statusGeneration.ExitCode -ne 0) {
        throw "Review-status mutation report generation failed: $($statusGeneration.Output)"
    }
    $statusResult = Get-GeneratedData -GeneratedHtmlPath $statusHtmlPath
    $statusAutomatedFindings = @($statusResult.automatedFindings | ConvertTo-Json -Depth 10 -Compress)
    if ($statusAutomatedFindings -ne $baselineAutomatedFindings) {
        throw 'Changing reviewStatus or caseDesignStatus must not change automated findings.'
    }
}
finally {
    Remove-Item -LiteralPath $statusDataPath, $statusHtmlPath -Force -ErrorAction SilentlyContinue
}

$temporaryDataPath = Join-Path $featureDir ("F-001_ログイン_一時データ_{0}.json" -f [guid]::NewGuid().ToString('N'))
$temporaryHtmlPath = Join-Path $featureDir ("F-001_ログイン_一時結果_{0}.html" -f [guid]::NewGuid().ToString('N'))
try {
    $temporaryData = Get-Content -LiteralPath $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    ($temporaryData.testCases | Where-Object id -eq 'FE-AUTH-001').evidenceIds = @()
    $temporaryData | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $temporaryDataPath -Encoding UTF8

    $temporaryGeneration = Invoke-ReportGenerator -InputDataPath $temporaryDataPath -OutputFilePath $temporaryHtmlPath
    if ($temporaryGeneration.ExitCode -ne 0) {
        throw "Temporary report generation failed: $($temporaryGeneration.Output)"
    }
    $temporaryResult = Get-GeneratedData -GeneratedHtmlPath $temporaryHtmlPath
    $missingEvidence = @($temporaryResult.automatedFindings | Where-Object { $_.category -eq '証跡未紐付け' -and $_.id -eq 'FE-AUTH-001' })
    if ($missingEvidence.Count -ne 1) {
        throw 'Removing evidenceIds must produce exactly one deterministic 証跡未紐付け result for FE-AUTH-001.'
    }
}
finally {
    Remove-Item -LiteralPath $temporaryDataPath, $temporaryHtmlPath -Force -ErrorAction SilentlyContinue
}

$invalidIdDataPath = Join-Path $featureDir ("F-001_ログイン_不正ID_{0}.json" -f [guid]::NewGuid().ToString('N'))
try {
    $invalidIdData = Get-Content -LiteralPath $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    ($invalidIdData.testCases | Where-Object id -eq 'BE-AUTH-001').testImplementationIds[0] = 'MISSING-IMPLEMENTATION'
    $invalidIdData | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $invalidIdDataPath -Encoding UTF8

    $invalidIdValidation = Invoke-ReportGenerator -InputDataPath $invalidIdDataPath -ValidateOnly
    if ($invalidIdValidation.ExitCode -eq 0) {
        throw 'Unknown implementation ID must fail ValidateOnly.'
    }
    if ($invalidIdValidation.Output -notmatch '(?s)unknown.*MISSING-IMPLEMENTATION|MISSING-IMPLEMENTATION.*unknown') {
        throw "Unknown implementation ID failure must identify the invalid ID: $($invalidIdValidation.Output)"
    }
}
finally {
    Remove-Item -LiteralPath $invalidIdDataPath -Force -ErrorAction SilentlyContinue
}

$missingRequiredDataPath = Join-Path $featureDir ("F-001_ログイン_必須項目欠落_{0}.json" -f [guid]::NewGuid().ToString('N'))
try {
    $missingRequiredData = Get-Content -LiteralPath $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    ($missingRequiredData.testCases | Where-Object id -eq 'BE-AUTH-001').PSObject.Properties.Remove('expected')
    $missingRequiredData | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $missingRequiredDataPath -Encoding UTF8

    $missingRequiredValidation = Invoke-ReportGenerator -InputDataPath $missingRequiredDataPath -ValidateOnly
    if ($missingRequiredValidation.ExitCode -eq 0) {
        throw 'Missing required expected field must fail ValidateOnly.'
    }
    if ($missingRequiredValidation.Output -notmatch '(?s)missing.*expected|expected.*missing') {
        throw "Missing required field failure must identify expected: $($missingRequiredValidation.Output)"
    }
}
finally {
    Remove-Item -LiteralPath $missingRequiredDataPath -Force -ErrorAction SilentlyContinue
}

Write-Output 'Fact-based quality display contract passed.'
