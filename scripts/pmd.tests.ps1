$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
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

$pomPath = Join-Path $repoRoot 'backend/pom.xml'
$rulesetPath = Join-Path $repoRoot 'backend/config/pmd.xml'
$pomText = Get-Content -Raw -Encoding UTF8 $pomPath

$oracleScript = Join-Path $repoRoot 'backend/scripts/test-oracle.ps1'
$fullBackend = @(Get-CiTaskDefinitions -CiTask FullBackend -RepoRoot $repoRoot `
        -NpmCommand 'npm.cmd' -MavenCommand 'backend/mvnw.cmd' -OracleScript $oracleScript)
$simpleBackend = @(Get-SimpleCheckDefinitions -RepoRoot $repoRoot -Scope Backend `
        -FocusedUnitScope Backend -FocusedUnitTarget 'TimeRulesTest' `
        -ChangedFiles @('backend/src/main/java/com/example/TimeRules.java'))
$fullContracts = @(Get-FullContractCheckDefinitions -RepoRoot $repoRoot | ForEach-Object Name)

Assert-Condition ($pomText -match '<artifactId>maven-pmd-plugin</artifactId>') `
    'PMD Maven Plugin is missing.'
Assert-Condition ($pomText -match '<maven-pmd-plugin\.version>3\.23\.0</maven-pmd-plugin\.version>') `
    'PMD plugin version property is missing or incorrect.'
Assert-Condition ($pomText -match '<ruleset>config/pmd\.xml</ruleset>') `
    'PMD ruleset path is missing.'
Assert-Condition ($pomText -match '<failOnViolation>true</failOnViolation>') `
    'PMD must fail on violations.'
Assert-Condition ($pomText -match '<includeTests>true</includeTests>') `
    'PMD must include test sources.'
Assert-Condition (Test-Path -LiteralPath $rulesetPath) `
    'PMD ruleset file is missing.'

$rulesetText = Get-Content -Raw -Encoding UTF8 $rulesetPath
foreach ($rule in @('CognitiveComplexity', 'CyclomaticComplexity', 'NPathComplexity')) {
    Assert-Condition ($rulesetText -match [regex]::Escape($rule)) "PMD rule is missing: $rule"
}
Assert-Condition ($rulesetText -match 'property name="reportLevel" value="15"') `
    'CognitiveComplexity threshold must be 15.'
Assert-Condition ($rulesetText -match 'property name="methodReportLevel" value="10"') `
    'Cyclomatic method threshold must be 10.'
Assert-Condition ($rulesetText -match 'property name="classReportLevel" value="80"') `
    'Cyclomatic class threshold must be 80.'
Assert-Condition ($rulesetText -match 'property name="reportLevel" value="200"') `
    'NPath threshold must be 200.'

$fullQuality = $fullBackend | Where-Object Name -eq 'backend-quality'
Assert-Condition ($null -ne $fullQuality) 'FullBackend must include the combined backend quality command.'
Assert-Condition (@($fullQuality.Arguments) -contains 'pmd:check') `
    'FullBackend must run pmd:check.'

$simplePmd = $simpleBackend | Where-Object Name -eq 'simple-backend-pmd'
Assert-Condition ($null -ne $simplePmd) 'Backend Simple Mode must include PMD.'
Assert-Condition (@($simplePmd.Arguments) -contains 'pmd:check') `
    'Backend Simple Mode must run pmd:check.'
Assert-Condition ($fullContracts -contains 'pmd-contract-test') `
    'PMD contract test must be part of Full contracts.'

Write-Output 'PMD contract tests passed.'
