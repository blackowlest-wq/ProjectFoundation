[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$FeaturePath
)

$ErrorActionPreference = 'Stop'
$featureDirectory = Get-Item -LiteralPath $FeaturePath -ErrorAction Stop
if (-not ($featureDirectory -is [System.IO.DirectoryInfo])) {
    throw "FeaturePath must be a directory: $FeaturePath"
}

function Get-SingleFeatureFile {
    param(
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Label
    )
    $matches = @(Get-ChildItem -LiteralPath $featureDirectory.FullName -File | Where-Object { $_.Name -like $Pattern })
    if ($matches.Count -ne 1) {
        throw "$($featureDirectory.Name) must contain exactly one $Label matching '$Pattern'. Found $($matches.Count)."
    }
    return $matches[0]
}

function Get-EmbeddedData {
    param([Parameter(Mandatory)][string]$HtmlPath)
    $html = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8
    $marker = '<script type="application/json" id="quality-data">'
    $start = $html.IndexOf($marker)
    if ($start -lt 0) { throw "Generated HTML does not contain quality data: $HtmlPath" }
    $start += $marker.Length
    $end = $html.IndexOf('</script>', $start)
    if ($end -lt 0) { throw "Generated HTML quality data is not closed: $HtmlPath" }
    return $html.Substring($start, $end - $start) | ConvertFrom-Json
}

$requiredRootProperties = @(
    'schemaVersion', 'feature', 'acceptanceCriteria', 'qualityGates',
    'rootCauses', 'testCases', 'viewpoints', 'testImplementations',
    'evidence', 'findings', 'coverage', 'sources', 'automatedFindings'
)
$dataFile = Get-SingleFeatureFile -Pattern '*_表示データ.json' -Label 'display data'
$generatorFile = Get-SingleFeatureFile -Pattern '*_生成.ps1' -Label 'generator'
$temporaryHtmlPath = Join-Path $featureDirectory.FullName ("品質確認共通契約_{0}.html" -f [guid]::NewGuid().ToString('N'))
$pwshCommand = (Get-Command pwsh -ErrorAction Stop).Source

try {
    $inputData = Get-Content -LiteralPath $dataFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -ne $inputData.PSObject.Properties['automatedFindings']) {
        throw 'Input data must not contain generated automatedFindings.'
    }

    & $pwshCommand -NoProfile -ExecutionPolicy Bypass -File $generatorFile.FullName `
        -DataPath $dataFile.FullName -OutputPath $temporaryHtmlPath
    if ($LASTEXITCODE -ne 0) {
        throw "$($generatorFile.Name) failed with exit code $LASTEXITCODE."
    }

    $html = Get-Content -LiteralPath $temporaryHtmlPath -Raw -Encoding UTF8
    $data = Get-EmbeddedData -HtmlPath $temporaryHtmlPath
    foreach ($property in $requiredRootProperties) {
        if ($null -eq $data.PSObject.Properties[$property]) {
            throw "Generated data property is missing: $property"
        }
    }
    if ([string]$data.schemaVersion -ne '1.0') {
        throw 'Generated data schemaVersion must be 1.0.'
    }
    foreach ($finding in @($data.automatedFindings)) {
        foreach ($property in @('category', 'id', 'text', 'status')) {
            if ($null -eq $finding.PSObject.Properties[$property]) {
                throw "Automated finding property is missing: $property"
            }
        }
    }
    $categories = @($data.automatedFindings | ForEach-Object { [string]$_.category })
    foreach ($forbidden in @('期待結果・ケース設計不足', '観点判定', '要補足')) {
        if ($categories -contains $forbidden) {
            throw "Semantic review category was automated: $forbidden"
        }
    }
    foreach ($forbiddenLabel in @('総合判定', '承認可能', '承認不可', 'overallStatus')) {
        if ($html.Contains($forbiddenLabel)) {
            throw "Forbidden evaluative label remains in generated HTML: $forbiddenLabel"
        }
    }
    if (-not $html.Contains('NG・要確認')) {
        throw 'Generated HTML must expose the NG and confirmation tab.'
    }
}
finally {
    Remove-Item -LiteralPath $temporaryHtmlPath -Force -ErrorAction SilentlyContinue
}

Write-Output "Quality report contract passed: $($featureDirectory.Name)"
