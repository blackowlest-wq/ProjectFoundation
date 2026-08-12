[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $TlaJar,
    [Parameter(Mandatory = $true)]
    [string] $AlloyJar
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modelDir = Join-Path $repoRoot 'docs\AI活用開発研究\形式検証\月次集計'
$toolTemp = Join-Path ([System.IO.Path]::GetTempPath()) 'projectfoundation-formal-run'
New-Item -ItemType Directory -Force $toolTemp | Out-Null
$tlaMeta = Join-Path $toolTemp 'tla'
New-Item -ItemType Directory -Force $tlaMeta | Out-Null

Write-Host '== Z3 =='
python (Join-Path $repoRoot 'scripts\formal-verification\monthly_summary_z3.py')

$java = 'java'
Write-Host '== TLC: declared =='
& $java -cp $TlaJar tlc2.TLC -nowarning -metadir $tlaMeta -config (Join-Path $modelDir 'MonthlySummaryDeclared.cfg') (Join-Path $modelDir 'MonthlySummaryDeclared.tla')
Write-Host '== TLC: boundary counterexample =='
& $java -cp $TlaJar tlc2.TLC -nowarning -metadir $tlaMeta -config (Join-Path $modelDir 'MonthlySummaryCode_Boundary.cfg') (Join-Path $modelDir 'MonthlySummaryCode.tla')
Write-Host '== TLC: snapshot counterexample =='
& $java -cp $TlaJar tlc2.TLC -nowarning -metadir $tlaMeta -config (Join-Path $modelDir 'MonthlySummaryCode_Snapshot.cfg') (Join-Path $modelDir 'MonthlySummaryCode.tla')

Write-Host '== Alloy compile =='
javac -cp $AlloyJar -d $toolTemp (Join-Path $repoRoot 'scripts\formal-verification\AlloyRunner.java')
$alloyClasspath = "$AlloyJar;$toolTemp"
Write-Host '== Alloy: declared =='
& $java -cp $alloyClasspath AlloyRunner (Join-Path $modelDir 'MonthlySummaryDeclared.als')
Write-Host '== Alloy: implementation =='
& $java -cp $alloyClasspath AlloyRunner (Join-Path $modelDir 'MonthlySummaryCode.als')
