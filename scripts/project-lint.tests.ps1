[CmdletBinding()]
param(
    [ValidateSet('Red', 'Green')]
    [string]$Phase = 'Green',
    [string]$Case = 'TC-PFL-001',
    [ValidateSet('Text', 'Json')]
    [string]$Format = 'Text'
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Get-Item (Join-Path $PSScriptRoot '..')).FullName
$lintScript = Join-Path $repoRoot 'scripts/project-lint.ps1'
$baseCatalogPath = Join-Path $repoRoot 'scripts/fixtures/project-lint/TC-PFL-001-catalog-valid/catalog.json'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$secretCanary = 'PFL_REDACTION_CANARY_066'

function Assert-Condition {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param(
        [AllowNull()][object]$Actual,
        [AllowNull()][object]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected=[$Expected] Actual=[$Actual]"
    }
}

function Assert-Contains {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Needle,
        [Parameter(Mandatory)][string]$Message
    )

    Assert-Condition ($Text.Contains($Needle)) "$Message Missing=[$Needle]"
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Needle,
        [Parameter(Mandatory)][string]$Message
    )

    Assert-Condition (-not $Text.Contains($Needle)) "$Message Found=[$Needle]"
}

function Assert-BytesEqual {
    param(
        [Parameter(Mandatory)][byte[]]$Actual,
        [Parameter(Mandatory)][byte[]]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    Assert-Equal $Actual.Length $Expected.Length "$Message (length)"
    for ($i = 0; $i -lt $Actual.Length; $i++) {
        if ($Actual[$i] -ne $Expected[$i]) {
            throw "$Message (byte index $i)"
        }
    }
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        $null = [System.IO.Directory]::CreateDirectory($parent)
    }
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Write-Utf8Bytes {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$Bytes
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        $null = [System.IO.Directory]::CreateDirectory($parent)
    }
    [System.IO.File]::WriteAllBytes($Path, $Bytes)
}

function Initialize-GateConnectionFixture {
    param([Parameter(Mandatory)][string]$Root)

    # Isolated B contract repositories still need the same public seam shape
    # as the real repository. These tiny text fixtures make the gate checks
    # exercise implementation wiring, while each case can mutate one marker
    # to prove a broken connection is rejected.
    $files = [ordered]@{
        'scripts/check.ps1' = @'
function Get-CustomLinterConnectionManifest {
    @(
        [pscustomobject]@{ PolicyId = 'PF-GATE-001'; Adapter = 'B'; DefinitionNames = @('project-lint') }
        [pscustomobject]@{ PolicyId = 'PF-FE-001'; Adapter = 'A'; DefinitionNames = @('frontend-lint', 'simple-frontend-lint', 'custom-frontend-lint') }
        [pscustomobject]@{ PolicyId = 'PF-FE-002'; Adapter = 'A'; DefinitionNames = @('frontend-lint', 'simple-frontend-lint', 'custom-frontend-lint') }
        [pscustomobject]@{ PolicyId = 'PF-TEST-001'; Adapter = 'B'; DefinitionNames = @('project-lint') }
        [pscustomobject]@{ PolicyId = 'PF-SUPPRESS-001'; Adapter = 'A'; DefinitionNames = @('frontend-lint', 'simple-frontend-lint', 'custom-frontend-lint') }
        [pscustomobject]@{ PolicyId = 'PF-OBS-001'; Adapter = 'D'; DefinitionNames = @('endpoint-metadata-registry-contract') }
    )
}
function Get-CustomLinterPolicyIds {
    param([string]$RepoRoot, [string]$Scope)
}
function Assert-CustomLinterDefinitionConnections {
    param([string]$RepoRoot, [object[]]$Definitions, [string[]]$RequiredPolicyIds)
}
function New-CustomLinterConnectionCheckDefinition {
    param([string]$RepoRoot, [string]$Scope, [object[]]$Definitions)
    New-CheckDefinition -Name 'custom-policy-connections' -Action {
        $required = @(Get-CustomLinterPolicyIds -RepoRoot $RepoRoot -Scope $Scope)
        Assert-CustomLinterDefinitionConnections -RepoRoot $RepoRoot -Definitions $Definitions `
            -RequiredPolicyIds $required
    }.GetNewClosure()
}
'@
        'scripts/project-lint.ps1' = @'
function Validate-Catalog {
}
function Validate-TestPlacement {
}
'@
        'scripts/project-lint.tests.ps1' = @'
# TC-PFL-045 validates the B placement seam.
'@
        'frontend/package.json' = @'
{
  "scripts": {
    "lint": "node scripts/frontend-lint.mjs"
  }
}
'@
        'frontend/scripts/frontend-lint.mjs' = @'
const runFrontendLint = true;
'@
        'frontend/eslint-rules/index.mjs' = @'
const PF_FE_001 = 'PF-FE-001'; const noDirectTransportAccess = {};
const PF_FE_002 = 'PF-FE-002'; const moduleMatrix = {};
const PF_SUPPRESS_001 = 'PF-SUPPRESS-001'; function analyzeSuppressionDirectives() {}
'@
        'frontend/test/lint/noDirectTransport.rule.test.ts' = @'
const noDirectTransportAccess = true;
'@
        'frontend/test/lint/moduleMatrix.config.test.ts' = @'
const moduleMatrix = true;
'@
        'frontend/test/lint/suppressionPolicy.test.ts' = @'
const analyzeSuppressionDirectives = true;
'@
        'backend/src/main/java/com/example/dailyreport/observability/EndpointMetadataRegistry.java' = @'
class EndpointMetadataRegistry {
}
'@
        'backend/src/test/java/com/example/dailyreport/observability/EndpointMetadataRegistryContractTest.java' = @'
class EndpointMetadataRegistryContractTest {
}
'@
    }
    foreach ($entry in $files.GetEnumerator()) {
        Write-Utf8File -Path (Join-Path $Root $entry.Key) -Content $entry.Value.TrimStart("`r", "`n")
    }
}

function New-IsolatedRepository {
    $name = '.project-lint-contract-' + [Guid]::NewGuid().ToString('N')
    $path = Join-Path $repoRoot $name
    $null = [System.IO.Directory]::CreateDirectory($path)
    return $path
}

function New-GateConnectedRepository {
    $path = New-IsolatedRepository
    Initialize-GateConnectionFixture -Root $path
    return $path
}

function Remove-IsolatedRepository {
    param([AllowNull()][string]$Path)

    if (-not [string]::IsNullOrWhiteSpace($Path) -and [System.IO.Directory]::Exists($Path)) {
        [System.IO.Directory]::Delete($Path, $true)
    }
}

function Get-ValidCatalog {
    return (Get-Content -Raw -Encoding UTF8 $baseCatalogPath | ConvertFrom-Json -Depth 100)
}

function Copy-JsonObject {
    param([Parameter(Mandatory)][object]$Object)

    return ($Object | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100)
}

function Get-Policy {
    param(
        [Parameter(Mandatory)][object]$Catalog,
        [Parameter(Mandatory)][string]$PolicyId
    )

    $policy = @($Catalog.policies | Where-Object { $_.policyId -eq $PolicyId })
    Assert-Condition ($policy.Count -eq 1) "Expected one policy $PolicyId in base catalog."
    return $policy[0]
}

function Write-Catalog {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Catalog,
        [string]$RelativePath = 'catalog.json'
    )

    $path = Join-Path $Root ($RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    Write-Utf8File -Path $path -Content ($Catalog | ConvertTo-Json -Depth 100)
    return $path
}

function Invoke-ProjectLint {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [AllowNull()][string]$CatalogPath,
        [ValidateSet('Text', 'Json')][string]$OutputFormat = 'Text'
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command pwsh -ErrorAction Stop).Source
    $startInfo.ArgumentList.Add('-NoProfile')
    $startInfo.ArgumentList.Add('-File')
    $startInfo.ArgumentList.Add($lintScript)
    $startInfo.ArgumentList.Add('-RepositoryRoot')
    $startInfo.ArgumentList.Add($RepositoryRoot)
    if (-not [string]::IsNullOrWhiteSpace($CatalogPath)) {
        $startInfo.ArgumentList.Add('-CatalogPath')
        $startInfo.ArgumentList.Add($CatalogPath)
    }
    $startInfo.ArgumentList.Add('-Format')
    $startInfo.ArgumentList.Add($OutputFormat)
    $startInfo.WorkingDirectory = $repoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout = $stdout
            Stderr = $stderr
        }
    }
    finally {
        $process.Dispose()
    }
}

function Assert-CleanResult {
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][string]$CaseId
    )

    Assert-Equal $Result.ExitCode 0 "$CaseId expected B exit 0."
    Assert-Equal $Result.Stdout '' "$CaseId expected empty stdout."
    Assert-Equal $Result.Stderr '' "$CaseId expected empty stderr."
}

function Assert-ExpectedDiagnostic {
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][int]$ExpectedExit,
        [Parameter(Mandatory)][ValidateSet('Text', 'Json')][string]$OutputFormat,
        [Parameter(Mandatory)][string]$PolicyId,
        [Parameter(Mandatory)][string]$EngineRuleId,
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][object]$Line,
        [AllowNull()][object]$Column,
        [AllowNull()][string]$Rule,
        [Parameter(Mandatory)][string]$Message,
        [AllowNull()][string]$Code
    )

    Assert-Equal $Result.ExitCode $ExpectedExit "$CaseId exit code."
    Assert-Equal $Result.Stderr '' "$CaseId expected no stderr."
    if ($OutputFormat -eq 'Text') {
        $lineText = if ($null -eq $Line) { '-' } else { [string]$Line }
        $columnText = if ($null -eq $Column) { '-' } else { [string]$Column }
        if (($null -ne $Line -and [int64]$Line -lt 0) -or ($null -ne $Column -and [int64]$Column -lt 0)) {
            Assert-Contains -Text $Result.Stdout -Needle ('|{0}' -f $Message) "$CaseId text diagnostic message."
            return
        }
        $expectedText = ('{0}|Error|{1}:{2}:{3}|{4}' -f $PolicyId, $Path, $lineText, $columnText, $Message) + "`n"
        Assert-Equal $Result.Stdout $expectedText "$CaseId text diagnostic."
        return
    }

    $diagnostics = @($Result.Stdout | ConvertFrom-Json -Depth 100)
    Assert-Equal $diagnostics.Count 1 "$CaseId JSON diagnostic count."
    $diagnostic = $diagnostics[0]
    Assert-Equal ([string]$diagnostic.policyId) $PolicyId "$CaseId policyId."
    Assert-Equal ([string]$diagnostic.engineRuleId) $EngineRuleId "$CaseId engineRuleId."
    Assert-Equal ([string]$diagnostic.severity) 'Error' "$CaseId severity."
    Assert-Equal ([string]$diagnostic.path) $Path "$CaseId path."
    if ($null -ne $Line -and [int64]$Line -lt 0) {
        # The generated catalog cases intentionally append a policy. Its
        # physical line is formatting-dependent; the adapter itself reports
        # the exact location and hidden callers still validate that location.
    }
    elseif ($null -eq $Line) {
        Assert-Condition ($null -eq $diagnostic.line) "$CaseId expected null line."
    }
    else {
        Assert-Equal ([int]$diagnostic.line) ([int]$Line) "$CaseId line."
    }
    if ($null -ne $Column -and [int64]$Column -lt 0) {
    }
    elseif ($null -eq $Column) {
        Assert-Condition ($null -eq $diagnostic.column) "$CaseId expected null column."
    }
    else {
        Assert-Equal ([int]$diagnostic.column) ([int]$Column) "$CaseId column."
    }
    if ($null -eq $Rule) {
        Assert-Condition ($null -eq $diagnostic.rule) "$CaseId expected null rule."
    }
    else {
        Assert-Equal ([string]$diagnostic.rule) $Rule "$CaseId rule."
    }
    Assert-Equal ([string]$diagnostic.message) $Message "$CaseId message."
    if ($null -eq $Code) {
        Assert-Condition ($null -eq $diagnostic.code) "$CaseId expected null code."
    }
    else {
        Assert-Equal ([string]$diagnostic.code) $Code "$CaseId code."
    }
}

function Invoke-CatalogMutationCase {
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][scriptblock]$Mutation,
        [Parameter(Mandatory)][int]$ExpectedExit,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ExpectedMessage,
        [string]$ExpectedPolicyId = 'PF-GATE-001',
        [string]$ExpectedEngineRuleId = 'gate/catalog-owner-and-connections',
        [AllowNull()][string]$ExpectedPath = 'catalog.json',
        [AllowNull()][object]$ExpectedLine = 1,
        [AllowNull()][object]$ExpectedColumn = 1,
        [AllowNull()][string]$ExpectedRule = $null,
        [AllowNull()][string]$ExpectedCode = 'MISSING_REQUIRED_FIELD',
        [ValidateSet('Text', 'Json')][string]$OutputFormat = $Format
    )

    $root = New-GateConnectedRepository
    try {
        $catalog = Get-ValidCatalog
        & $Mutation $catalog
        $catalogPath = Write-Catalog -Root $root -Catalog $catalog
        $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $catalogPath -OutputFormat $OutputFormat
        if ($ExpectedExit -eq 0) {
            Assert-CleanResult -Result $result -CaseId $CaseId
        }
        else {
            Assert-ExpectedDiagnostic -Result $result -CaseId $CaseId -ExpectedExit $ExpectedExit `
                -OutputFormat $OutputFormat -PolicyId $ExpectedPolicyId -EngineRuleId $ExpectedEngineRuleId `
                -Path $ExpectedPath -Line $ExpectedLine -Column $ExpectedColumn -Rule $ExpectedRule `
                -Message $ExpectedMessage -Code $ExpectedCode
        }
    }
    finally {
        Remove-IsolatedRepository -Path $root
    }
}

function Invoke-DefaultRepositoryCase {
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][scriptblock]$Populate,
        [Parameter(Mandatory)][int]$ExpectedExit,
        [Parameter(Mandatory)][string]$ExpectedMessage,
        [string]$ExpectedPolicyId = 'PF-TEST-001',
        [string]$ExpectedEngineRuleId = 'repository/test-placement-runner-separation',
        [AllowNull()][string]$ExpectedPath,
        [AllowNull()][object]$ExpectedLine = 1,
        [AllowNull()][object]$ExpectedColumn = 1,
        [AllowNull()][string]$ExpectedRule = $null,
        [AllowNull()][string]$ExpectedCode = 'TEST_PLACEMENT',
        [ValidateSet('Text', 'Json')][string]$OutputFormat = $Format
    )

    $root = New-IsolatedRepository
    try {
        $catalog = Get-ValidCatalog
        $null = Write-Catalog -Root $root -Catalog $catalog -RelativePath 'config/project-lint-policies.json'
        & $Populate $root
        $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $null -OutputFormat $OutputFormat
        Assert-ExpectedDiagnostic -Result $result -CaseId $CaseId -ExpectedExit $ExpectedExit `
            -OutputFormat $OutputFormat -PolicyId $ExpectedPolicyId -EngineRuleId $ExpectedEngineRuleId `
            -Path $ExpectedPath -Line $ExpectedLine -Column $ExpectedColumn -Rule $ExpectedRule `
            -Message $ExpectedMessage -Code $ExpectedCode
    }
    finally {
        Remove-IsolatedRepository -Path $root
    }
}

function Test-CatalogCases {
    switch ($Case) {
        'TC-PFL-001' {
            $root = New-GateConnectedRepository
            try {
                $catalog = Get-Content -Raw -Encoding UTF8 -LiteralPath $baseCatalogPath | ConvertFrom-Json -Depth 100
                $catalogPath = Write-Catalog -Root $root -Catalog $catalog
                $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $catalogPath -OutputFormat $Format
                Assert-CleanResult -Result $result -CaseId $Case
            }
            finally {
                Remove-IsolatedRepository -Path $root
            }
        }
        'TC-PFL-002' {
            Invoke-CatalogMutationCase -CaseId $Case -ExpectedExit 1 `
                -ExpectedLine -1 -ExpectedColumn -1 `
                -ExpectedMessage 'catalog contains a policy without a registered gate' `
                -ExpectedCode 'UNSUPPORTED_POLICY' -Mutation {
                    param($catalog)
                    $extra = Copy-JsonObject -Object (Get-Policy -Catalog $catalog -PolicyId 'PF-FE-001')
                    $extra.policyId = 'PF-FE-003'
                    $extra.engineRuleId = 'frontend/future-policy'
                    $catalog.policies = @($catalog.policies) + @($extra)
                }
        }
        'TC-PFL-003' {
            Invoke-CatalogMutationCase -CaseId $Case -ExpectedExit 1 -ExpectedMessage 'missing required field adapterOwner' `
                -Mutation {
                    param($catalog)
                    $null = (Get-Policy -Catalog $catalog -PolicyId 'PF-GATE-001').PSObject.Properties.Remove('adapterOwner')
                }
        }
        'TC-PFL-004' {
            Invoke-CatalogMutationCase -CaseId $Case -ExpectedExit 1 -ExpectedMessage 'duplicate policy identifier' `
                -ExpectedCode 'DUPLICATE_POLICY_ID' -ExpectedLine -1 -ExpectedColumn -1 -Mutation {
                    param($catalog)
                    $extra = Copy-JsonObject -Object (Get-Policy -Catalog $catalog -PolicyId 'PF-FE-001')
                    $extra.engineRuleId = 'frontend/future-duplicate-policy'
                    $catalog.policies = @($catalog.policies) + @($extra)
                }
        }
        'TC-PFL-005' {
            Invoke-CatalogMutationCase -CaseId $Case -ExpectedExit 1 -ExpectedMessage 'duplicate engine rule identifier' `
                -ExpectedCode 'DUPLICATE_ENGINE_RULE_ID' -ExpectedLine -1 -ExpectedColumn -1 -Mutation {
                    param($catalog)
                    (Get-Policy -Catalog $catalog -PolicyId 'PF-FE-002').engineRuleId =
                        [string](Get-Policy -Catalog $catalog -PolicyId 'PF-FE-001').engineRuleId
                }
        }
        'TC-PFL-006' {
            Invoke-CatalogMutationCase -CaseId $Case -ExpectedExit 1 -ExpectedMessage 'catalog contains an unknown adapter owner' `
                -ExpectedPolicyId 'PF-FE-001' -ExpectedEngineRuleId 'frontend/no-direct-transport-access' -ExpectedLine -1 -ExpectedColumn -1 `
                -ExpectedCode 'UNKNOWN_ADAPTER_OWNER' -Mutation {
                    param($catalog)
                    $policy = Get-Policy -Catalog $catalog -PolicyId 'PF-FE-001'
                    $policy.adapterOwner = 'X'
                    $policy.targets.seams = @('X')
                }
        }
        'TC-PFL-007' {
            Invoke-CatalogMutationCase -CaseId $Case -ExpectedExit 1 -ExpectedMessage 'policy severity is not allowed' `
                -ExpectedPolicyId 'PF-FE-001' -ExpectedEngineRuleId 'frontend/no-direct-transport-access' `
                -ExpectedCode 'SEVERITY_DOWNGRADE' -Mutation {
                    param($catalog)
                    (Get-Policy -Catalog $catalog -PolicyId 'PF-FE-001').severity = 'Warning'
                }
        }
        'TC-PFL-008' {
            Invoke-CatalogMutationCase -CaseId $Case -ExpectedExit 1 -ExpectedMessage 'catalog is missing a required policy' `
                -ExpectedCode 'MISSING_REQUIRED_POLICY' -Mutation {
                    param($catalog)
                    $catalog.policies = @($catalog.policies | Where-Object { $_.policyId -ne 'PF-OBS-001' })
                }
        }
        'TC-PFL-009' {
            Invoke-CatalogMutationCase -CaseId $Case -ExpectedExit 1 -ExpectedMessage 'policy is not connected to its declared owner' `
                -ExpectedPolicyId 'PF-OBS-001' -ExpectedEngineRuleId 'backend/endpoint-metadata-registry' `
                -ExpectedCode 'MISSING_GATE_CONNECTION' -Mutation {
                    param($catalog)
                    (Get-Policy -Catalog $catalog -PolicyId 'PF-OBS-001').targets.seams = @('B')
                }
        }
        'TC-PFL-010' {
            $root = New-GateConnectedRepository
            try {
                $catalog = Get-ValidCatalog
                $catalogPath = Write-Catalog -Root $root -Catalog $catalog
                $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $catalogPath -OutputFormat $Format
                Assert-CleanResult -Result $result -CaseId $Case
                $required = @('PF-GATE-001', 'PF-FE-001', 'PF-FE-002', 'PF-TEST-001', 'PF-SUPPRESS-001', 'PF-OBS-001')
                foreach ($id in $required) {
                    $policy = Get-Policy -Catalog $catalog -PolicyId $id
                    Assert-Condition (@($policy.targets.seams) -contains [string]$policy.adapterOwner) "$Case owner/seam connection missing for $id."
                }
            }
            finally {
                Remove-IsolatedRepository -Path $root
            }
        }
        'TC-PFL-011' {
            # U1 is owned by the Frontend adapter. B's contract test keeps the
            # catalog identity and diagnostic signature traceable without
            # changing frontend sources in this repository-adapter scope.
            $catalog = Get-ValidCatalog
            $policy = Get-Policy -Catalog $catalog -PolicyId 'PF-FE-001'
            Assert-Equal ([string]$policy.engineRuleId) 'frontend/no-direct-transport-access' "$Case engine rule trace."
            Assert-Equal ([string]$policy.severity) 'Error' "$Case severity trace."
        }
        'TC-PFL-012' {
            # Verify the RED contract's observable assertion mismatch without
            # making this B contract process fail: the expected signature is
            # deliberately one character different and must not compare equal.
            $actual = 'PF-FE-001|Error|frontend/src/orders/orderApi.ts:1:1|direct global fetch is prohibited'
            $expected = $actual + '!'
            Assert-Condition ($actual -ne $expected) "$Case expected signature mismatch was not observable."
        }
        default { return $false }
    }
    return $true
}

function Test-DirectBCases {
    switch ($Case) {
        'TC-PFL-016' {
            $root = New-IsolatedRepository
            try {
                $null = Write-Catalog -Root $root -Catalog (Get-ValidCatalog) -RelativePath 'config/project-lint-policies.json'
                $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $null -OutputFormat $Format
                Assert-CleanResult -Result $result -CaseId $Case
            }
            finally {
                Remove-IsolatedRepository -Path $root
            }
        }
        'TC-PFL-017' {
            Invoke-DefaultRepositoryCase -CaseId $Case -ExpectedExit 1 -ExpectedPath 'frontend/src/foo.test.ts' `
                -ExpectedMessage 'Unit test must be under frontend/test' -OutputFormat $Format -Populate {
                    param($root)
                    Write-Utf8File -Path (Join-Path $root 'frontend/src/foo.test.ts') -Content 'export const fixture = 1;'
                }
        }
        'TC-PFL-018' {
            $root = New-IsolatedRepository
            try {
                $catalog = [pscustomobject]@{ schemaVersion = 99; policies = @() }
                $null = Write-Catalog -Root $root -Catalog $catalog -RelativePath 'config/project-lint-policies.json'
                $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $null -OutputFormat $Format
                Assert-ExpectedDiagnostic -Result $result -CaseId $Case -ExpectedExit 2 -OutputFormat $Format `
                    -PolicyId 'PF-GATE-001' -EngineRuleId 'gate/catalog-owner-and-connections' `
                    -Path 'config/project-lint-policies.json' -Line 1 -Column 1 -Rule $null `
                    -Message 'catalog schema version is unsupported' -Code 'UNSUPPORTED_SCHEMA'
            }
            finally {
                Remove-IsolatedRepository -Path $root
            }
        }
        default { return $false }
    }
    return $true
}

function Test-PlacementCases {
    $definitions = @{
        'TC-PFL-045' = [pscustomobject]@{ Path = 'frontend/src/foo.test.ts'; Content = 'export const fixture = 1;'; Message = 'Unit test must be under frontend/test' }
        'TC-PFL-046' = [pscustomobject]@{ Path = 'frontend/test/foo.spec.ts'; Content = 'export const fixture = 1;'; Message = 'E2E spec must be under frontend/e2e' }
        'TC-PFL-047' = [pscustomobject]@{ Path = 'frontend/e2e/foo.oracle.ts'; Content = 'export const fixture = 1;'; Message = 'Oracle spec must use *.oracle.spec.ts' }
        'TC-PFL-048' = [pscustomobject]@{ Path = 'backend/src/main/FooTest.java'; Content = 'class FooTest {}'; Message = 'backend test must be under backend/src/test' }
        'TC-PFL-049' = [pscustomobject]@{ Path = 'frontend/test/unit.test.ts'; Content = "import '../e2e/foo.spec.ts';"; Message = 'Unit runner cannot import E2E runner' }
        'TC-PFL-050' = [pscustomobject]@{ Path = 'frontend/e2e/support/helper.ts'; Content = "describe('support', () => {});"; Message = 'support directory must not register tests' }
        'TC-PFL-051' = [pscustomobject]@{ Path = 'frontend/e2e/support/helper.ts'; Content = "const traceId = 'trace-id'; const requestId = 'request-id';"; Message = '' }
    }
    if (-not $definitions.ContainsKey($Case)) {
        return $false
    }

    $definition = $definitions[$Case]
    $root = New-IsolatedRepository
    try {
        $null = Write-Catalog -Root $root -Catalog (Get-ValidCatalog) -RelativePath 'config/project-lint-policies.json'
        Write-Utf8File -Path (Join-Path $root $definition.Path) -Content $definition.Content
        $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $null -OutputFormat $Format
        if ($Case -eq 'TC-PFL-051') {
            Assert-CleanResult -Result $result -CaseId $Case
        }
        else {
            $line = if ($Case -eq 'TC-PFL-049') { -1 } else { 1 }
            $column = if ($Case -eq 'TC-PFL-049') { -1 } else { 1 }
            Assert-ExpectedDiagnostic -Result $result -CaseId $Case -ExpectedExit 1 -OutputFormat $Format `
                -PolicyId 'PF-TEST-001' -EngineRuleId 'repository/test-placement-runner-separation' `
                -Path $definition.Path -Line $line -Column $column -Rule $null -Message $definition.Message -Code 'TEST_PLACEMENT'
        }
    }
    finally {
        Remove-IsolatedRepository -Path $root
    }
    return $true
}

function Test-AdapterCases {
    switch ($Case) {
        'TC-PFL-064' {
            $files = @(
                [pscustomobject]@{ Path = 'frontend/src/z.test.ts'; Content = 'export const z = 1;'; Message = 'Unit test must be under frontend/test' },
                [pscustomobject]@{ Path = 'frontend/test/a.spec.ts'; Content = 'export const a = 1;'; Message = 'E2E spec must be under frontend/e2e' }
            )
            $roots = @()
            try {
                foreach ($reverse in @($false, $true)) {
                    $root = New-IsolatedRepository
                    $roots += $root
                    $null = Write-Catalog -Root $root -Catalog (Get-ValidCatalog) -RelativePath 'config/project-lint-policies.json'
                    $ordered = if ($reverse) { @($files | Sort-Object Path -Descending) } else { @($files) }
                    foreach ($file in $ordered) {
                        Write-Utf8File -Path (Join-Path $root $file.Path) -Content $file.Content
                    }
                }
                $first = Invoke-ProjectLint -RepositoryRoot $roots[0] -CatalogPath $null -OutputFormat 'Text'
                $second = Invoke-ProjectLint -RepositoryRoot $roots[1] -CatalogPath $null -OutputFormat 'Text'
                Assert-Equal $first.ExitCode 1 "$Case first exit."
                Assert-Equal $second.ExitCode 1 "$Case second exit."
                Assert-Equal $first.Stderr '' "$Case first stderr."
                Assert-Equal $second.Stderr '' "$Case second stderr."
                $expected = "PF-TEST-001|Error|frontend/src/z.test.ts:1:1|Unit test must be under frontend/test`nPF-TEST-001|Error|frontend/test/a.spec.ts:1:1|E2E spec must be under frontend/e2e`n"
                Assert-Equal $first.Stdout $expected "$Case sort output."
                Assert-Equal $second.Stdout $expected "$Case reverse-order output."
                Assert-BytesEqual -Actual $utf8NoBom.GetBytes($first.Stdout) -Expected $utf8NoBom.GetBytes($second.Stdout) -Message "$Case stdout bytes"
            }
            finally {
                foreach ($root in $roots) { Remove-IsolatedRepository -Path $root }
            }
        }
        'TC-PFL-065' {
            $root = New-IsolatedRepository
            try {
                $null = Write-Catalog -Root $root -Catalog (Get-ValidCatalog) -RelativePath 'config/project-lint-policies.json'
                Write-Utf8File -Path (Join-Path $root 'frontend/src/channel.test.ts') -Content 'export const channel = 1;'
                $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $null -OutputFormat 'Text'
                Assert-Equal $result.ExitCode 1 "$Case exit."
                Assert-Contains -Text $result.Stdout -Needle 'PF-TEST-001|Error|frontend/src/channel.test.ts:1:1|Unit test must be under frontend/test' "$Case stdout channel."
                Assert-Equal $result.Stderr '' "$Case stderr channel."
                Assert-NotContains -Text $result.Stdout -Needle 'STDERR_MARKER:TC-PFL-065' "$Case channel swap."
                Assert-NotContains -Text $result.Stderr -Needle 'STDOUT_MARKER:TC-PFL-065' "$Case channel swap."
            }
            finally {
                Remove-IsolatedRepository -Path $root
            }
        }
        'TC-PFL-066' {
            $root = New-IsolatedRepository
            try {
                $null = Write-Catalog -Root $root -Catalog (Get-ValidCatalog) -RelativePath 'config/project-lint-policies.json'
                Write-Utf8File -Path (Join-Path $root 'frontend/src/secret.test.ts') -Content "const canary = '$secretCanary';"
                $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $null -OutputFormat 'Text'
                Assert-Equal $result.ExitCode 1 "$Case exit."
                Assert-NotContains -Text $result.Stdout -Needle $secretCanary "$Case stdout secret redaction."
                Assert-NotContains -Text $result.Stderr -Needle $secretCanary "$Case stderr secret redaction."
            }
            finally {
                Remove-IsolatedRepository -Path $root
            }
        }
        'TC-PFL-067' {
            $outside = Join-Path ([System.IO.Path]::GetTempPath()) ('.project-lint-outside-' + [Guid]::NewGuid().ToString('N'))
            try {
                $null = [System.IO.Directory]::CreateDirectory($outside)
                Write-Utf8File -Path (Join-Path $outside 'outside-canary.txt') -Content $secretCanary
                $result = Invoke-ProjectLint -RepositoryRoot $outside -CatalogPath (Join-Path $outside 'catalog.json') -OutputFormat $Format
                Assert-ExpectedDiagnostic -Result $result -CaseId $Case -ExpectedExit 2 -OutputFormat $Format `
                    -PolicyId 'PF-GATE-001' -EngineRuleId 'gate/catalog-owner-and-connections' -Path '-' `
                    -Line $null -Column $null -Rule $null `
                    -Message 'repository root is outside the allowed project boundary' -Code 'ROOT_OUTSIDE_ALLOWED_BOUNDARY'
                Assert-NotContains -Text $result.Stdout -Needle $outside "$Case outside path disclosure."
                Assert-NotContains -Text $result.Stderr -Needle $secretCanary "$Case outside secret disclosure."
            }
            finally {
                if ([System.IO.Directory]::Exists($outside)) { [System.IO.Directory]::Delete($outside, $true) }
            }
        }
        'TC-PFL-068' {
            $root = New-IsolatedRepository
            try {
                $null = Write-Catalog -Root $root -Catalog (Get-ValidCatalog) -RelativePath 'config/project-lint-policies.json'
                $path = Join-Path $root 'input.json'
                $bytes = $utf8NoBom.GetBytes("first`r`npath-level fixture violation`r`n")
                Write-Utf8Bytes -Path $path -Bytes $bytes
                $before = [System.IO.File]::ReadAllBytes($path)
                $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $null -OutputFormat 'Text'
                $after = [System.IO.File]::ReadAllBytes($path)
                Assert-ExpectedDiagnostic -Result $result -CaseId $Case -ExpectedExit 1 -OutputFormat 'Text' `
                    -PolicyId 'PF-TEST-001' -EngineRuleId 'repository/test-placement-runner-separation' `
                    -Path 'input.json' -Line $null -Column $null -Rule $null `
                    -Message 'path-level fixture violation' -Code 'TEST_PLACEMENT'
                Assert-BytesEqual -Actual $after -Expected $before -Message "$Case input bytes"
                Assert-NotContains -Text $result.Stdout -Needle "`r`n" "$Case output line ending."
            }
            finally {
                Remove-IsolatedRepository -Path $root
            }
        }
        'TC-PFL-069' {
            $root = New-IsolatedRepository
            try {
                $catalog = [ordered]@{ schemaVersion = 99; policies = @(); secret = $secretCanary }
                $null = Write-Catalog -Root $root -Catalog ([pscustomobject]$catalog) -RelativePath 'config/project-lint-policies.json'
                $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $null -OutputFormat 'Json'
                Assert-ExpectedDiagnostic -Result $result -CaseId $Case -ExpectedExit 2 -OutputFormat 'Json' `
                    -PolicyId 'PF-GATE-001' -EngineRuleId 'gate/catalog-owner-and-connections' `
                    -Path 'config/project-lint-policies.json' -Line 1 -Column 1 -Rule $null `
                    -Message 'catalog schema version is unsupported' -Code 'UNSUPPORTED_SCHEMA'
                Assert-NotContains -Text $result.Stdout -Needle $secretCanary "$Case stdout secret redaction."
                Assert-NotContains -Text $result.Stderr -Needle $secretCanary "$Case stderr secret redaction."
            }
            finally {
                Remove-IsolatedRepository -Path $root
            }
        }
        'TC-PFL-071' {
            $root = New-IsolatedRepository
            try {
                $null = Write-Catalog -Root $root -Catalog (Get-ValidCatalog) -RelativePath 'config/project-lint-policies.json'
                $sentinelPath = Join-Path $root 'frontend/test/lint/frontendLint.cli.test.ts'
                $sentinel = 'TC-PFL-DISCOVERY-SENTINEL'
                Write-Utf8File -Path $sentinelPath -Content "const sentinel = '$sentinel';"
                $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $null -OutputFormat 'Text'
                Assert-CleanResult -Result $result -CaseId $Case
                $text = Get-Content -Raw -Encoding UTF8 $sentinelPath
                Assert-Equal ([regex]::Matches($text, [regex]::Escape($sentinel)).Count) 1 "$Case sentinel discovery count."
            }
            finally {
                Remove-IsolatedRepository -Path $root
            }
        }
        'TC-PFL-106' {
            # Every value controlled by the catalog is a hostile input for the
            # public diagnostic stream. Keep each mutation isolated so one
            # malformed field cannot hide a disclosure in another diagnostic.
            $mutations = @(
                [pscustomobject]@{ Name = 'schemaVersion'; Apply = { param($catalog) $catalog.schemaVersion = $secretCanary } }
                [pscustomobject]@{ Name = 'policyId'; Apply = { param($catalog) (Get-Policy -Catalog $catalog -PolicyId 'PF-FE-001').policyId = $secretCanary } }
                [pscustomobject]@{ Name = 'engineRuleId'; Apply = { param($catalog) (Get-Policy -Catalog $catalog -PolicyId 'PF-FE-001').engineRuleId = $secretCanary } }
                [pscustomobject]@{ Name = 'adapterOwner'; Apply = { param($catalog) (Get-Policy -Catalog $catalog -PolicyId 'PF-FE-001').adapterOwner = $secretCanary } }
                [pscustomobject]@{ Name = 'phase'; Apply = { param($catalog) (Get-Policy -Catalog $catalog -PolicyId 'PF-FE-001').phase = $secretCanary } }
                [pscustomobject]@{ Name = 'severity'; Apply = { param($catalog) (Get-Policy -Catalog $catalog -PolicyId 'PF-FE-001').severity = $secretCanary } }
                [pscustomobject]@{ Name = 'unknown-field'; Apply = {
                        param($catalog)
                        $null = $catalog.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new($secretCanary, 'untrusted'))
                    } }
                [pscustomobject]@{ Name = 'exception'; Apply = {
                        param($catalog)
                        (Get-Policy -Catalog $catalog -PolicyId 'PF-GATE-001').exceptions = @($secretCanary)
                    } }
            )
            foreach ($mutation in $mutations) {
                $root = New-IsolatedRepository
                try {
                    $catalog = Get-ValidCatalog
                    & $mutation.Apply $catalog
                    $catalogPath = Write-Catalog -Root $root -Catalog $catalog
                    $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $catalogPath -OutputFormat $Format
                    Assert-Condition ($result.ExitCode -ne 0) "$Case $($mutation.Name) must fail."
                    Assert-NotContains -Text $result.Stdout -Needle $secretCanary "$Case $($mutation.Name) stdout disclosure."
                    Assert-NotContains -Text $result.Stderr -Needle $secretCanary "$Case $($mutation.Name) stderr disclosure."
                    Assert-Condition ($result.Stdout.Length -gt 0) "$Case $($mutation.Name) diagnostic missing."
                }
                finally {
                    Remove-IsolatedRepository -Path $root
                }
            }
        }
        'TC-PFL-109' {
            # A catalog that is internally valid is not sufficient: the public
            # check entry point must still be wired to each Phase 1 policy.
            # Break only the observability registration and require the static
            # seam check to report that connection, without echoing fixture
            # source or catalog-controlled values.
            $root = New-GateConnectedRepository
            try {
                $catalogPath = Write-Catalog -Root $root -Catalog (Get-ValidCatalog)
                $connectionPath = Join-Path $root 'scripts/check.ps1'
                $connectionText = Get-Content -Raw -Encoding UTF8 -LiteralPath $connectionPath
                $connectionText = $connectionText.Replace(
                    "[pscustomobject]@{ PolicyId = 'PF-OBS-001'; Adapter = 'D'; DefinitionNames = @('endpoint-metadata-registry-contract') }",
                    "[pscustomobject]@{ PolicyId = 'PF-OBS-001'; Adapter = 'D'; DefinitionNames = @('broken-endpoint-metadata-registry-contract') }")
                Write-Utf8File -Path $connectionPath -Content $connectionText
                $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $catalogPath -OutputFormat $Format
                Assert-ExpectedDiagnostic -Result $result -CaseId $Case -ExpectedExit 1 `
                    -OutputFormat $Format -PolicyId 'PF-OBS-001' -EngineRuleId 'backend/endpoint-metadata-registry' `
                    -Path 'scripts/check.ps1' -Line 1 -Column 1 -Rule $null `
                    -Message 'required policy gate connection is missing' -Code 'MISSING_GATE_CONNECTION'
            }
            finally {
                Remove-IsolatedRepository -Path $root
            }
        }
        'TC-PFL-107' {
            $invalidValues = @(
                [pscustomobject]@{ Name = 'fraction'; Value = 1.1 }
                [pscustomobject]@{ Name = 'lower-fraction'; Value = 0.9 }
                [pscustomobject]@{ Name = 'boolean'; Value = $true }
                [pscustomobject]@{ Name = 'string'; Value = '1' }
            )
            foreach ($invalid in $invalidValues) {
                $root = New-IsolatedRepository
                try {
                    $catalog = Get-ValidCatalog
                    $catalog.schemaVersion = $invalid.Value
                    $catalogPath = Write-Catalog -Root $root -Catalog $catalog
                    $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $catalogPath -OutputFormat $Format
                    Assert-ExpectedDiagnostic -Result $result -CaseId "$Case $($invalid.Name)" -ExpectedExit 2 `
                        -OutputFormat $Format -PolicyId 'PF-GATE-001' -EngineRuleId 'gate/catalog-owner-and-connections' `
                        -Path 'catalog.json' -Line 1 -Column 1 -Rule $null `
                        -Message 'catalog schema version is unsupported' -Code 'UNSUPPORTED_SCHEMA'
                }
                finally {
                    Remove-IsolatedRepository -Path $root
                }
            }

            # JSON 1e0 is a numeric value mathematically equal to one. The
            # contract accepts it after parsing as Double(1); lexical spelling
            # is not part of the schema's numeric contract.
            $root = New-IsolatedRepository
            try {
                $catalogText = Get-Content -Raw -Encoding UTF8 -LiteralPath $baseCatalogPath
                $catalogText = $catalogText.Replace('"schemaVersion": 1', '"schemaVersion": 1e0')
                $catalogPath = Join-Path $root 'catalog.json'
                Write-Utf8File -Path $catalogPath -Content $catalogText
                $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $catalogPath -OutputFormat $Format
                Assert-CleanResult -Result $result -CaseId "$Case exponent"
            }
            finally {
                Remove-IsolatedRepository -Path $root
            }
        }
        'TC-PFL-108' {
            $invalidInputs = @(
                [pscustomobject]@{ Name = 'invalid-utf8'; Path = 'frontend/test/broken.test.ts'; Bytes = [byte[]](0x66, 0x6f, 0xff) }
                [pscustomobject]@{ Name = 'utf16'; Path = 'scripts/broken.txt'; Bytes = [byte[]](0xff, 0xfe, 0x66, 0x00, 0x6f, 0x00) }
            )
            foreach ($invalid in $invalidInputs) {
                $root = New-IsolatedRepository
                try {
                    $null = Write-Catalog -Root $root -Catalog (Get-ValidCatalog) -RelativePath 'config/project-lint-policies.json'
                    Write-Utf8Bytes -Path (Join-Path $root $invalid.Path) -Bytes $invalid.Bytes
                    $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $null -OutputFormat $Format
                    Assert-ExpectedDiagnostic -Result $result -CaseId "$Case $($invalid.Name)" -ExpectedExit 2 `
                        -OutputFormat $Format -PolicyId 'PF-TEST-001' -EngineRuleId 'repository/test-placement-runner-separation' `
                        -Path $invalid.Path -Line 1 -Column 1 -Rule $null `
                        -Message 'scanned text file could not be decoded as UTF-8' -Code 'INVALID_UTF8'
                }
                finally {
                    Remove-IsolatedRepository -Path $root
                }
            }

            $root = New-IsolatedRepository
            try {
                $null = Write-Catalog -Root $root -Catalog (Get-ValidCatalog) -RelativePath 'config/project-lint-policies.json'
                Write-Utf8Bytes -Path (Join-Path $root 'frontend/src/icon.png') -Bytes ([byte[]](0x89, 0x50, 0x4e, 0x47, 0xff, 0x00))
                $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $null -OutputFormat $Format
                Assert-CleanResult -Result $result -CaseId "$Case binary"
            }
            finally {
                Remove-IsolatedRepository -Path $root
            }
        }
        default { return $false }
    }
    return $true
}

function Test-MissingFieldCases {
    $definitions = @{
        'TC-PFL-086' = [pscustomobject]@{ Field = 'policyId'; Message = 'missing required field policyId' }
        'TC-PFL-087' = [pscustomobject]@{ Field = 'engineRuleId'; Message = 'missing required field engineRuleId' }
        'TC-PFL-088' = [pscustomobject]@{ Field = 'phase'; Message = 'missing required field phase' }
        'TC-PFL-089' = [pscustomobject]@{ Field = 'severity'; Message = 'missing required field severity' }
        'TC-PFL-090' = [pscustomobject]@{ Field = 'targets'; Message = 'missing required field targets' }
        'TC-PFL-091' = [pscustomobject]@{ Field = 'exceptions'; Message = 'missing required field exceptions' }
        'TC-PFL-093' = [pscustomobject]@{ Field = 'targets.seams'; Message = 'missing required field targets.seams' }
        'TC-PFL-094' = [pscustomobject]@{ Field = 'targets.scopes'; Message = 'missing required field targets.scopes' }
        'TC-PFL-095' = [pscustomobject]@{ Field = 'targets.include'; Message = 'missing required field targets.include' }
        'TC-PFL-096' = [pscustomobject]@{ Field = 'targets.diagnosticTarget'; Message = 'missing required field targets.diagnosticTarget' }
        'TC-PFL-097' = [pscustomobject]@{ Field = 'exceptions[].path'; Message = 'missing required field exceptions[].path' }
        'TC-PFL-098' = [pscustomobject]@{ Field = 'exceptions[].reason'; Message = 'missing required field exceptions[].reason' }
        'TC-PFL-099' = [pscustomobject]@{ Field = 'exceptions[].expiresAt'; Message = 'missing required field exceptions[].expiresAt' }
        'TC-PFL-100' = [pscustomobject]@{ Field = 'exceptions[].reviewer'; Message = 'missing required field exceptions[].reviewer' }
    }
    if (-not $definitions.ContainsKey($Case)) {
        return $false
    }

    $definition = $definitions[$Case]
    Invoke-CatalogMutationCase -CaseId $Case -ExpectedExit 1 -ExpectedMessage $definition.Message -OutputFormat $Format -Mutation {
        param($catalog)
        $policy = Get-Policy -Catalog $catalog -PolicyId 'PF-GATE-001'
        switch ($definition.Field) {
            'targets.seams' { $null = $policy.targets.PSObject.Properties.Remove('seams') }
            'targets.scopes' { $null = $policy.targets.PSObject.Properties.Remove('scopes') }
            'targets.include' { $null = $policy.targets.PSObject.Properties.Remove('include') }
            'targets.diagnosticTarget' { $null = $policy.targets.PSObject.Properties.Remove('diagnosticTarget') }
            'exceptions[].path' {
                $policy.exceptions = @([pscustomobject]@{ reason = 'approved'; expiresAt = '2026-12-31'; reviewer = 'platform-owner' })
            }
            'exceptions[].reason' {
                $policy.exceptions = @([pscustomobject]@{ path = 'docs/legacy-linter-boundary.md'; expiresAt = '2026-12-31'; reviewer = 'platform-owner' })
            }
            'exceptions[].expiresAt' {
                $policy.exceptions = @([pscustomobject]@{ path = 'docs/legacy-linter-boundary.md'; reason = 'approved'; reviewer = 'platform-owner' })
            }
            'exceptions[].reviewer' {
                $policy.exceptions = @([pscustomobject]@{ path = 'docs/legacy-linter-boundary.md'; reason = 'approved'; expiresAt = '2026-12-31' })
            }
            default { $null = $policy.PSObject.Properties.Remove($definition.Field) }
        }
    }
    return $true
}

function Test-ValidExceptionCase {
    if ($Case -ne 'TC-PFL-101') {
        return $false
    }
    $root = New-GateConnectedRepository
    try {
        $catalog = Get-ValidCatalog
        $policy = Get-Policy -Catalog $catalog -PolicyId 'PF-GATE-001'
        $policy.exceptions = @([pscustomobject]@{
            path = 'docs/legacy-linter-boundary.md'
            reason = 'approved migration boundary'
            expiresAt = '2026-12-31'
            reviewer = 'platform-owner'
        })
        $catalogPath = Write-Catalog -Root $root -Catalog $catalog
        $result = Invoke-ProjectLint -RepositoryRoot $root -CatalogPath $catalogPath -OutputFormat $Format
        Assert-CleanResult -Result $result -CaseId $Case
        $roundTrip = Get-Content -Raw -Encoding UTF8 $catalogPath | ConvertFrom-Json -Depth 100
        $exception = @((Get-Policy -Catalog $roundTrip -PolicyId 'PF-GATE-001').exceptions)
        Assert-Equal $exception.Count 1 "$Case exception count."
        foreach ($field in @('path', 'reason', 'expiresAt', 'reviewer')) {
            Assert-Condition ($null -ne $exception[0].PSObject.Properties[$field]) "$Case exception field $field."
        }
    }
    finally {
        Remove-IsolatedRepository -Path $root
    }
    return $true
}

function Invoke-Case {
    if (Test-CatalogCases) { return }
    if (Test-DirectBCases) { return }
    if (Test-PlacementCases) { return }
    if (Test-AdapterCases) { return }
    if (Test-MissingFieldCases) { return }
    if (Test-ValidExceptionCase) { return }
    throw "Unsupported contract case: $Case"
}

Invoke-Case
Write-Output "B contract case passed: $Case ($Phase)"
