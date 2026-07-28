$ErrorActionPreference = 'Stop'

$featureDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$generator = Join-Path $featureDir 'F-002_日報登録_生成.ps1'
$dataPath = Join-Path $featureDir 'F-002_日報登録_表示データ.json'
$htmlPath = Join-Path $featureDir 'F-002_日報登録_コード品質確認.html'

$output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $generator -DataPath $dataPath -OutputPath $htmlPath 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "F-002 report generation failed: $($output -join [Environment]::NewLine)"
}

$data = Get-Content -LiteralPath $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json
$html = Get-Content -LiteralPath $htmlPath -Raw -Encoding UTF8

if ($data.feature.id -ne 'F-002' -or $data.feature.screenId -ne 'S-003') {
    throw 'F-002 display data must target F-002 / S-003.'
}
if (@($data.acceptanceCriteria).Count -ne 19) {
    throw 'F-002 display data must contain the 19 F-002 acceptance criteria.'
}
if ($null -ne $data.PSObject.Properties['automatedFindings']) {
    throw 'automatedFindings must not be stored in input display data.'
}
if (@($data.testCases | Where-Object executionStatus -eq '未実行').Count -eq 0) {
    throw 'The report must preserve unexecuted F-002 cases as facts.'
}
if ($data.coverage.backend.status -ne '未通過' -or $data.coverage.backend.reason -notmatch 'jacoco\.exec') {
    throw 'Backend coverage hold reason must remain visible as a fact.'
}

foreach ($forbidden in @('総合判定', '評価A', '承認可能', '承認不可', 'overallStatus')) {
    if ($html.Contains($forbidden)) {
        throw "Forbidden evaluative label remains in generated HTML: $forbidden"
    }
}
foreach ($required in @('F-002', 'S-003', '実行状況', '品質ゲート', 'NG・要確認', '未実行')) {
    if (-not $html.Contains($required)) {
        throw "Required fact label is missing from generated HTML: $required"
    }
}

$embedded = [regex]::Match($html, '(?s)<script type="application/json" id="quality-data">(.*?)</script>').Groups[1].Value | ConvertFrom-Json
$categories = @($embedded.automatedFindings | ForEach-Object category)
foreach ($forbiddenCategory in @('観点判定', '期待結果・ケース設計不足', '要補足')) {
    if ($categories -contains $forbiddenCategory) {
        throw "Semantic review category must not be automated: $forbiddenCategory"
    }
}
foreach ($requiredCategory in @('未実行', 'カバレッジ', '指摘・保留')) {
    if (-not ($categories -contains $requiredCategory)) {
        throw "Expected fact category is missing from generated findings: $requiredCategory"
    }
}

Write-Output 'F-002 fact-based display policy passed.'
