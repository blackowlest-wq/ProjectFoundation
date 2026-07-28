[CmdletBinding()]
param(
    [string[]]$FeaturePath,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$qualityRoot = Join-Path $repoRoot 'docs/AI活用開発研究/コード品質確認画面'
$pwshCommand = (Get-Command pwsh -ErrorAction Stop).Source
$contractTestFile = Get-Item -LiteralPath (Join-Path $repoRoot 'scripts/quality-report-contract.tests.ps1') -ErrorAction Stop

function Get-FeatureDirectories {
    param([string[]]$RequestedPaths)

    if ($RequestedPaths.Count -eq 0) {
        if (-not (Test-Path -LiteralPath $qualityRoot -PathType Container)) {
            throw "Quality report root does not exist: $qualityRoot"
        }
        return @(
            Get-ChildItem -LiteralPath $qualityRoot -Directory |
                Where-Object {
                    @(Get-ChildItem -LiteralPath $_.FullName -File |
                        Where-Object { $_.Name -like '*_表示データ.json' -or $_.Name -like '*_生成.ps1' -or $_.Name -like '*_表示方針.tests.ps1' }).Count -gt 0
                } |
                Sort-Object Name
        )
    }

    $resolved = [System.Collections.Generic.List[object]]::new()
    $qualityRootFullPath = [System.IO.Path]::GetFullPath($qualityRoot)
    foreach ($requestedPath in $RequestedPaths) {
        $candidatePath = if ([System.IO.Path]::IsPathRooted($requestedPath)) {
            [System.IO.Path]::GetFullPath($requestedPath)
        }
        else {
            [System.IO.Path]::GetFullPath((Join-Path $repoRoot $requestedPath))
        }
        if (-not (Test-Path -LiteralPath $candidatePath -PathType Container)) {
            throw "Quality report feature directory does not exist: $requestedPath"
        }
        $relativePath = [System.IO.Path]::GetRelativePath($qualityRootFullPath, $candidatePath)
        if ($relativePath -eq '..' -or $relativePath.StartsWith("..$([System.IO.Path]::DirectorySeparatorChar)")) {
            throw "Quality report feature directory is outside the quality report root: $requestedPath"
        }
        $resolved.Add((Get-Item -LiteralPath $candidatePath))
    }
    return @($resolved | Sort-Object FullName -Unique)
}

function Get-RequiredFeatureFile {
    param(
        [Parameter(Mandatory)][System.IO.DirectoryInfo]$Directory,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Label
    )
    $matches = @(Get-ChildItem -LiteralPath $Directory.FullName -File | Where-Object { $_.Name -like $Pattern })
    if ($matches.Count -ne 1) {
        throw "$($Directory.Name) must contain exactly one $Label matching '$Pattern'. Found $($matches.Count)."
    }
    return $matches[0]
}

function Invoke-PowerShellFile {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$ScriptFile,
        [string[]]$Arguments = @()
    )
    & $pwshCommand -NoProfile -ExecutionPolicy Bypass -File $ScriptFile.FullName @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$($ScriptFile.Name) failed with exit code $LASTEXITCODE."
    }
}

function Get-EmbeddedQualityData {
    param([Parameter(Mandatory)][System.IO.FileInfo]$HtmlFile)
    $html = Get-Content -LiteralPath $HtmlFile.FullName -Raw -Encoding UTF8
    $marker = '<script type="application/json" id="quality-data">'
    $start = $html.IndexOf($marker)
    if ($start -lt 0) {
        throw "Generated HTML does not contain quality data: $($HtmlFile.FullName)"
    }
    $start += $marker.Length
    $end = $html.IndexOf('</script>', $start)
    if ($end -lt 0) {
        throw "Generated HTML quality data is not closed: $($HtmlFile.FullName)"
    }
    return $html.Substring($start, $end - $start) | ConvertFrom-Json
}

$featureDirectories = @(Get-FeatureDirectories -RequestedPaths $FeaturePath)
if ($featureDirectories.Count -eq 0) {
    throw "No quality report feature directories were found under: $qualityRoot"
}

foreach ($featureDirectory in $featureDirectories) {
    $testFile = Get-RequiredFeatureFile -Directory $featureDirectory -Pattern '*_表示方針.tests.ps1' -Label 'display policy test'
    $generatorFile = Get-RequiredFeatureFile -Directory $featureDirectory -Pattern '*_生成.ps1' -Label 'generator'
    $dataFile = Get-RequiredFeatureFile -Directory $featureDirectory -Pattern '*_表示データ.json' -Label 'display data'
    $htmlFile = Get-RequiredFeatureFile -Directory $featureDirectory -Pattern '*_コード品質確認.html' -Label 'generated HTML'

    Write-Host "==> quality-report $($featureDirectory.Name)"
    Invoke-PowerShellFile -ScriptFile $contractTestFile -Arguments @('-FeaturePath', $featureDirectory.FullName)
    Invoke-PowerShellFile -ScriptFile $testFile
    Invoke-PowerShellFile -ScriptFile $generatorFile -Arguments @('-DataPath', $dataFile.FullName, '-OutputPath', $htmlFile.FullName, '-ValidateOnly')

    if ($ValidateOnly) {
        Write-Output "Validated quality report: $($featureDirectory.Name)"
        continue
    }

    Invoke-PowerShellFile -ScriptFile $generatorFile -Arguments @('-DataPath', $dataFile.FullName, '-OutputPath', $htmlFile.FullName)
    $data = Get-EmbeddedQualityData -HtmlFile $htmlFile
    $categorySummary = @($data.automatedFindings | Group-Object category | Sort-Object Name |
        ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '
    Write-Output "Generated quality report: $($featureDirectory.Name) [$categorySummary]"
}
