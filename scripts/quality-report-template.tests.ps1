$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$templatePath = Join-Path $repoRoot 'docs/AI活用開発研究/コード品質確認画面/品質確認表示データ.template.json'
$featureDir = Join-Path $repoRoot 'docs/AI活用開発研究/コード品質確認画面/F-001_ログイン'
$dataPath = Join-Path $featureDir 'F-001_ログイン_表示データ.json'
$generator = Join-Path $featureDir 'F-001_ログイン_生成.ps1'

function Assert-Condition {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JSON file does not exist: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

$requiredRootProperties = @(
    'schemaVersion', 'feature', 'acceptanceCriteria', 'qualityGates',
    'rootCauses', 'testCases', 'viewpoints', 'testImplementations',
    'evidence', 'findings', 'coverage', 'sources'
)
$template = Read-JsonFile -Path $templatePath
foreach ($property in $requiredRootProperties) {
    Assert-Condition ($null -ne $template.PSObject.Properties[$property]) "Template property is missing: $property"
}
Assert-Condition ([string]$template.schemaVersion -eq '1.0') 'Template schemaVersion must be 1.0.'
Assert-Condition ($null -eq $template.PSObject.Properties['automatedFindings']) 'Template must not contain generated automatedFindings.'

$data = Read-JsonFile -Path $dataPath
Assert-Condition ([string]$data.schemaVersion -eq '1.0') 'F-001 data schemaVersion must be 1.0.'
Assert-Condition ($null -eq $data.PSObject.Properties['automatedFindings']) 'Input data must not contain generated automatedFindings.'

$validationOutput = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $generator -DataPath $dataPath -ValidateOnly 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "F-001 schema validation failed: $($validationOutput -join [Environment]::NewLine)"
}

$invalidPath = Join-Path $featureDir ("F-001_ログイン_不正スキーマ_{0}.json" -f [guid]::NewGuid().ToString('N'))
try {
    $invalid = Read-JsonFile -Path $dataPath
    $invalid.schemaVersion = '9.9'
    $invalid | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $invalidPath -Encoding UTF8
    $invalidOutput = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $generator -DataPath $invalidPath -ValidateOnly 2>&1)
    if ($LASTEXITCODE -eq 0) {
        throw 'Unsupported schemaVersion must fail ValidateOnly.'
    }
    if (($invalidOutput -join [Environment]::NewLine) -notmatch 'schemaVersion') {
        throw "Schema validation failure must identify schemaVersion: $($invalidOutput -join [Environment]::NewLine)"
    }
}
finally {
    Remove-Item -LiteralPath $invalidPath -Force -ErrorAction SilentlyContinue
}

Write-Output 'Template schema contract passed.'
