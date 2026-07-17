[CmdletBinding()]
param(
    [string]$FrontendSummaryPath,
    [string]$BackendXmlPath,
    [switch]$AllowMissing
)

$ErrorActionPreference = 'Stop'
$threshold = 85.0
$metrics = [System.Collections.Generic.List[object]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Add-Metric {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Metric,
        [Parameter(Mandatory)][double]$Percent
    )
    $status = if ($Percent -ge $script:threshold) { 'PASS' } else { 'BELOW 85%' }
    $formatted = $Percent.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture) + '%'
    [void]$script:metrics.Add([pscustomobject]@{
            Source  = $Source
            Metric  = $Metric
            Percent = $formatted
            Status  = $status
        })
}

function Resolve-InputPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ReportName
    )
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    if ($script:AllowMissing) {
        [void]$script:warnings.Add("$ReportName report is unavailable.")
        return $null
    }
    throw "$ReportName report is missing."
}

if ([string]::IsNullOrWhiteSpace($FrontendSummaryPath) -and [string]::IsNullOrWhiteSpace($BackendXmlPath)) {
    throw 'At least one coverage report path is required.'
}

if (-not [string]::IsNullOrWhiteSpace($FrontendSummaryPath)) {
    $resolvedFrontendPath = Resolve-InputPath -Path $FrontendSummaryPath -ReportName 'Frontend coverage'
    if ($resolvedFrontendPath) {
        $frontend = Get-Content -Raw -Encoding UTF8 $resolvedFrontendPath | ConvertFrom-Json
        if (-not $frontend.total) { throw 'Frontend coverage summary has no total metrics.' }
        foreach ($definition in @(
                @{ Property = 'statements'; Label = 'Statements' }
                @{ Property = 'branches'; Label = 'Branches' }
                @{ Property = 'functions'; Label = 'Functions' }
                @{ Property = 'lines'; Label = 'Lines' }
            )) {
            $metric = $frontend.total.($definition.Property)
            if ($null -eq $metric -or $null -eq $metric.pct) {
                throw "Frontend coverage summary is missing $($definition.Label)."
            }
            Add-Metric -Source 'Frontend' -Metric $definition.Label -Percent ([double]$metric.pct)
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($BackendXmlPath)) {
    $resolvedBackendPath = Resolve-InputPath -Path $BackendXmlPath -ReportName 'Backend JaCoCo'
    if ($resolvedBackendPath) {
        [xml]$backend = Get-Content -Raw -Encoding UTF8 $resolvedBackendPath
        foreach ($definition in @(
                @{ Type = 'INSTRUCTION'; Label = 'Instructions' }
                @{ Type = 'BRANCH'; Label = 'Branches' }
                @{ Type = 'METHOD'; Label = 'Methods' }
                @{ Type = 'LINE'; Label = 'Lines' }
            )) {
            $counter = $backend.SelectSingleNode("//counter[@type='$($definition.Type)']")
            if ($null -eq $counter) { throw "Backend JaCoCo report is missing $($definition.Label)." }
            $missed = [double]$counter.missed
            $covered = [double]$counter.covered
            $total = $missed + $covered
            $percent = if ($total -eq 0) { 100.0 } else { ($covered / $total) * 100.0 }
            Add-Metric -Source 'Backend' -Metric $definition.Label -Percent $percent
        }
    }
}

$lines = [System.Collections.Generic.List[string]]::new()
[void]$lines.Add('## Coverage summary')
[void]$lines.Add('')
[void]$lines.Add('| Source | Metric | Coverage | Gate |')
[void]$lines.Add('| --- | --- | ---: | --- |')
foreach ($metric in $metrics) {
    [void]$lines.Add("| $($metric.Source) | $($metric.Metric) | $($metric.Percent) | $($metric.Status) |")
}
foreach ($warning in $warnings) {
    [void]$lines.Add('')
    [void]$lines.Add("> $warning")
}
$summary = $lines -join [Environment]::NewLine
$destination = [Environment]::GetEnvironmentVariable('GITHUB_STEP_SUMMARY', 'Process')
if ([string]::IsNullOrWhiteSpace($destination)) {
    Write-Output $summary
}
else {
    Add-Content -LiteralPath $destination -Value $summary -Encoding UTF8
}
