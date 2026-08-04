$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'scripts/check.ps1')

function Assert-Condition {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$cases = @(
    @{ Name = 'Quick'; Mode = 'Quick'; CiTask = 'None'; ImpactTask = 'Plan'; Expected = 180 }
    @{ Name = 'PrePush'; Mode = 'PrePush'; CiTask = 'None'; ImpactTask = 'Plan'; Expected = 180 }
    @{ Name = 'Full'; Mode = 'Full'; CiTask = 'None'; ImpactTask = 'Plan'; Expected = 600 }
    @{ Name = 'Oracle'; Mode = 'Oracle'; CiTask = 'None'; ImpactTask = 'Plan'; Expected = 1800 }
    @{ Name = 'All'; Mode = 'All'; CiTask = 'None'; ImpactTask = 'Plan'; Expected = 1800 }
    @{ Name = 'Impact FullBackend'; Mode = 'Impact'; CiTask = 'None'; ImpactTask = 'FullBackend'; Expected = 600 }
    @{ Name = 'Impact Oracle'; Mode = 'Impact'; CiTask = 'None'; ImpactTask = 'Oracle'; Expected = 1800 }
    @{ Name = 'CiTask BackendCoverage'; Mode = 'Quick'; CiTask = 'BackendCoverage'; ImpactTask = 'Plan'; Expected = 1800 }
    @{ Name = 'CiTask FullFrontend'; Mode = 'Quick'; CiTask = 'FullFrontend'; ImpactTask = 'Plan'; Expected = 600 }
)

foreach ($case in $cases) {
    $actual = Get-QualityTimeoutBudgetSeconds -Mode $case.Mode -CiTask $case.CiTask -ImpactTask $case.ImpactTask
    Assert-Condition ($actual -eq $case.Expected) `
        "$($case.Name) timeout budget must be $($case.Expected) seconds, actual: $actual."
}

$fullGuidance = Get-QualityTimeoutGuidance -Mode Full -CiTask None -ImpactTask Plan
Assert-Condition ($fullGuidance -match '600s \(10min\)') `
    "Full timeout guidance must include 600s (10min): $fullGuidance"

$oracleGuidance = Get-QualityTimeoutGuidance -Mode Oracle -CiTask None -ImpactTask Plan
Assert-Condition ($oracleGuidance -match '1800s \(30min\)') `
    "Oracle timeout guidance must include 1800s (30min): $oracleGuidance"

Write-Output 'Quality timeout contract tests passed.'
