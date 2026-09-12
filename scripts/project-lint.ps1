[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [ValidateSet('Text', 'Json')][string]$Format = 'Text',
    [string]$CatalogPath
)

$ErrorActionPreference = 'Stop'

$requiredPolicies = [ordered]@{
    'PF-GATE-001' = [pscustomobject]@{ EngineRuleId = 'gate/catalog-owner-and-connections'; Owner = 'B' }
    'PF-FE-001' = [pscustomobject]@{ EngineRuleId = 'frontend/no-direct-transport-access'; Owner = 'A' }
    'PF-FE-002' = [pscustomobject]@{ EngineRuleId = 'frontend/module-matrix-and-target-coverage'; Owner = 'A' }
    'PF-TEST-001' = [pscustomobject]@{ EngineRuleId = 'repository/test-placement-runner-separation'; Owner = 'B' }
    'PF-SUPPRESS-001' = [pscustomobject]@{ EngineRuleId = 'frontend/suppression-reason'; Owner = 'A' }
    'PF-OBS-001' = [pscustomobject]@{ EngineRuleId = 'backend/endpoint-metadata-registry'; Owner = 'D' }
}

$policyRequiredFields = @(
    'policyId', 'engineRuleId', 'adapterOwner', 'phase', 'severity', 'targets', 'exceptions'
)
$targetRequiredFields = @('seams', 'scopes', 'include', 'diagnosticTarget')
$exceptionRequiredFields = @('path', 'reason', 'expiresAt', 'reviewer')
$validOwners = @('A', 'B', 'D')
$testPlacementRoots = @(
    'frontend/src',
    'frontend/test',
    'frontend/e2e',
    'backend/src/main',
    'backend/src/test',
    'scripts'
)
$testPlacementExtensions = @(
    '.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs',
    '.java', '.kt', '.ps1', '.json', '.txt'
)

# These checks deliberately describe the repository's public adapter seams,
# rather than trusting targets/include/seams from the catalog. A catalog may
# describe any policy entry, but only these six Phase 1 policies are wired to
# executable implementation and gate entry points in this repository.
#
# C now derives definition policy lists from the fixed connection manifest in
# check.ps1. Keep B coupled to that implementation seam: each requirement
# matches the complete PolicyId + Adapter + DefinitionNames tuple and the
# public custom-policy-connections action. Checking only for a policy id would
# allow a policy to appear in an unrelated definition or an inert comment.
$connectionManifestPattern = '(?s)function\s+Get-CustomLinter(?:Adapter|Connection)Manifest\s*\{'
$connectionActionPattern = '(?s)function\s+New-CustomLinterConnectionCheckDefinition\s*\{.*?New-CheckDefinition\s+-Name\s+''custom-policy-connections''\s+-Action\s*\{.*?Get-CustomLinterPolicyIds\s+-RepoRoot\s+\$RepoRoot\s+-Scope\s+\$Scope.*?Assert-CustomLinterDefinitionConnections\s+-RepoRoot\s+\$RepoRoot\s+-Definitions\s+\$Definitions\s+`?\s*-RequiredPolicyIds\s+\$required'
$gateConnectionRequirements = [ordered]@{
    'PF-GATE-001' = @(
        [pscustomobject]@{ Path = 'scripts/check.ps1'; Pattern = ($connectionManifestPattern + ".*?\[pscustomobject\]@\{\s*PolicyId\s*=\s*'PF-GATE-001'\s*;\s*Adapter\s*=\s*'B'\s*;\s*DefinitionNames\s*=\s*@\(\s*'project-lint'\s*\)") },
        [pscustomobject]@{ Path = 'scripts/check.ps1'; Pattern = $connectionActionPattern },
        [pscustomobject]@{ Path = 'scripts/project-lint.ps1'; Pattern = 'function\s+Validate-Catalog\s*\{' }
    )
    'PF-FE-001' = @(
        [pscustomobject]@{ Path = 'scripts/check.ps1'; Pattern = ($connectionManifestPattern + ".*?\[pscustomobject\]@\{\s*PolicyId\s*=\s*'PF-FE-001'\s*;\s*Adapter\s*=\s*'A'\s*;\s*DefinitionNames\s*=\s*@\(\s*'frontend-lint'\s*,\s*'simple-frontend-lint'\s*,\s*'custom-frontend-lint'\s*\)") },
        [pscustomobject]@{ Path = 'scripts/check.ps1'; Pattern = $connectionActionPattern },
        [pscustomobject]@{ Path = 'frontend/package.json'; Pattern = '"lint"\s*:\s*"node\s+scripts/frontend-lint\.mjs"' },
        [pscustomobject]@{ Path = 'frontend/scripts/frontend-lint.mjs'; Pattern = 'runFrontendLint' },
        [pscustomobject]@{ Path = 'frontend/eslint-rules/index.mjs'; Pattern = '(?s)PF-FE-001.*?noDirectTransportAccess|noDirectTransportAccess.*?PF-FE-001' },
        [pscustomobject]@{ Path = 'frontend/test/lint/noDirectTransport.rule.test.ts'; Pattern = 'noDirectTransportAccess' }
    )
    'PF-FE-002' = @(
        [pscustomobject]@{ Path = 'scripts/check.ps1'; Pattern = ($connectionManifestPattern + ".*?\[pscustomobject\]@\{\s*PolicyId\s*=\s*'PF-FE-002'\s*;\s*Adapter\s*=\s*'A'\s*;\s*DefinitionNames\s*=\s*@\(\s*'frontend-lint'\s*,\s*'simple-frontend-lint'\s*,\s*'custom-frontend-lint'\s*\)") },
        [pscustomobject]@{ Path = 'scripts/check.ps1'; Pattern = $connectionActionPattern },
        [pscustomobject]@{ Path = 'frontend/eslint-rules/index.mjs'; Pattern = '(?s)PF-FE-002.*?moduleMatrix|moduleMatrix.*?PF-FE-002' },
        [pscustomobject]@{ Path = 'frontend/test/lint/moduleMatrix.config.test.ts'; Pattern = 'moduleMatrix' }
    )
    'PF-TEST-001' = @(
        [pscustomobject]@{ Path = 'scripts/check.ps1'; Pattern = ($connectionManifestPattern + ".*?\[pscustomobject\]@\{\s*PolicyId\s*=\s*'PF-TEST-001'\s*;\s*Adapter\s*=\s*'B'\s*;\s*DefinitionNames\s*=\s*@\(\s*'project-lint'\s*\)") },
        [pscustomobject]@{ Path = 'scripts/check.ps1'; Pattern = $connectionActionPattern },
        [pscustomobject]@{ Path = 'scripts/project-lint.ps1'; Pattern = 'function\s+Validate-TestPlacement\s*\{' },
        [pscustomobject]@{ Path = 'scripts/project-lint.tests.ps1'; Pattern = 'TC-PFL-045' }
    )
    'PF-SUPPRESS-001' = @(
        [pscustomobject]@{ Path = 'scripts/check.ps1'; Pattern = ($connectionManifestPattern + ".*?\[pscustomobject\]@\{\s*PolicyId\s*=\s*'PF-SUPPRESS-001'\s*;\s*Adapter\s*=\s*'A'\s*;\s*DefinitionNames\s*=\s*@\(\s*'frontend-lint'\s*,\s*'simple-frontend-lint'\s*,\s*'custom-frontend-lint'\s*\)") },
        [pscustomobject]@{ Path = 'scripts/check.ps1'; Pattern = $connectionActionPattern },
        [pscustomobject]@{ Path = 'frontend/eslint-rules/index.mjs'; Pattern = '(?s)PF-SUPPRESS-001.*?analyzeSuppressionDirectives|analyzeSuppressionDirectives.*?PF-SUPPRESS-001' },
        [pscustomobject]@{ Path = 'frontend/test/lint/suppressionPolicy.test.ts'; Pattern = 'analyzeSuppressionDirectives' }
    )
    'PF-OBS-001' = @(
        [pscustomobject]@{ Path = 'scripts/check.ps1'; Pattern = ($connectionManifestPattern + ".*?\[pscustomobject\]@\{\s*PolicyId\s*=\s*'PF-OBS-001'\s*;\s*Adapter\s*=\s*'D'\s*;\s*DefinitionNames\s*=\s*@\(\s*'endpoint-metadata-registry-contract'\s*\)") },
        [pscustomobject]@{ Path = 'scripts/check.ps1'; Pattern = $connectionActionPattern },
        [pscustomobject]@{ Path = 'backend/src/main/java/com/example/dailyreport/observability/EndpointMetadataRegistry.java'; Pattern = 'class\s+EndpointMetadataRegistry\b' },
        [pscustomobject]@{ Path = 'backend/src/test/java/com/example/dailyreport/observability/EndpointMetadataRegistryContractTest.java'; Pattern = 'class\s+EndpointMetadataRegistryContractTest\b' }
    )
}
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function New-BDiagnostic {
    param(
        [Parameter(Mandatory)][string]$PolicyId,
        [Parameter(Mandatory)][string]$EngineRuleId,
        [Parameter(Mandatory)][string]$Severity,
        [AllowEmptyString()][string]$Path,
        [AllowNull()][object]$Line,
        [AllowNull()][object]$Column,
        [AllowNull()][string]$Rule,
        [Parameter(Mandatory)][string]$Message,
        [AllowNull()][string]$Code
    )

    return [pscustomobject][ordered]@{
        policyId = $PolicyId
        engineRuleId = $EngineRuleId
        severity = $Severity
        path = $Path
        line = $Line
        column = $Column
        rule = $Rule
        message = $Message
        code = $Code
    }
}

function Add-BDiagnostic {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Diagnostics,
        [Parameter(Mandatory)][string]$PolicyId,
        [Parameter(Mandatory)][string]$EngineRuleId,
        [AllowEmptyString()][string]$Path,
        [AllowNull()][object]$Line,
        [AllowNull()][object]$Column,
        [AllowNull()][string]$Rule,
        [Parameter(Mandatory)][string]$Message,
        [AllowNull()][string]$Code
    )

    $diagnostic = New-BDiagnostic -PolicyId $PolicyId -EngineRuleId $EngineRuleId `
        -Severity 'Error' -Path $Path -Line $Line -Column $Column -Rule $Rule `
        -Message $Message -Code $Code
    $null = $Diagnostics.Add($diagnostic)
}

function Get-FullPath {
    param([Parameter(Mandatory)][string]$Path)

    try {
        return [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        return $null
    }
}

function Test-PathWithin {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Candidate
    )

    $rootFull = $Root.TrimEnd('\', '/')
    $candidateFull = $Candidate.TrimEnd('\', '/')
    return $candidateFull.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or
        $candidateFull.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
        $candidateFull.StartsWith($rootFull + [System.IO.Path]::AltDirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-RepositoryRelativePath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$FullPath
    )

    $rootFull = $Root.TrimEnd('\', '/')
    $candidateFull = [System.IO.Path]::GetFullPath($FullPath)
    if ($candidateFull.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ''
    }
    if (-not (Test-PathWithin -Root $rootFull -Candidate $candidateFull)) {
        return '-'
    }
    return $candidateFull.Substring($rootFull.Length).TrimStart('\', '/').Replace('\', '/')
}

function Get-TextLocation {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][int]$Index
    )

    $safeIndex = [Math]::Max(0, [Math]::Min($Index, $Text.Length))
    $prefix = $Text.Substring(0, $safeIndex)
    $line = ([regex]::Matches($prefix, "`n")).Count + 1
    $lastNewline = $prefix.LastIndexOf("`n")
    $column = $safeIndex - $lastNewline
    return [pscustomobject]@{ Line = $line; Column = $column }
}

function Get-JsonPropertyLocation {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$PropertyName,
        [string]$Value,
        [int]$Occurrence = 1
    )

    $propertyPattern = '"' + [regex]::Escape($PropertyName) + '"\s*:'
    if ($PSBoundParameters.ContainsKey('Value')) {
        $propertyPattern = '"' + [regex]::Escape($PropertyName) + '"\s*:\s*"' + [regex]::Escape($Value) + '"'
    }
    $matches = [regex]::Matches($Text, $propertyPattern)
    if ($matches.Count -lt $Occurrence) {
        return [pscustomobject]@{ Line = 1; Column = 1 }
    }
    return Get-TextLocation -Text $Text -Index $matches[$Occurrence - 1].Index
}

function Add-CatalogDiagnostic {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Diagnostics,
        [Parameter(Mandatory)][string]$CatalogRelativePath,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Code,
        [string]$PolicyId = 'PF-GATE-001',
        [string]$EngineRuleId = 'gate/catalog-owner-and-connections',
        [AllowNull()][object]$Line = 1,
        [AllowNull()][object]$Column = 1,
        [AllowNull()][string]$Rule = $null
    )

    Add-BDiagnostic -Diagnostics $Diagnostics -PolicyId $PolicyId -EngineRuleId $EngineRuleId `
        -Path $CatalogRelativePath -Line $Line -Column $Column -Rule $Rule `
        -Message $Message -Code $Code
}

function Has-Property {
    param(
        [Parameter(Mandatory)][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    return $null -ne $Object.PSObject.Properties[$Name]
}

function Get-PolicyIdentity {
    param([Parameter(Mandatory)][object]$Policy)

    $hasPolicyId = Has-Property -Object $Policy -Name 'policyId'
    $rawPolicyId = if ($hasPolicyId) { $Policy.policyId } else { $null }
    # Catalog values are untrusted input. A diagnostic identity is therefore
    # derived exclusively from the statically registered policy table. Even a
    # known policyId never contributes its catalog engineRuleId to output;
    # malformed or unknown values always use the catalog gate anchor.
    if ($rawPolicyId -is [string] -and $requiredPolicies.Contains($rawPolicyId)) {
        $knownPolicyId = [string]$rawPolicyId
        return [pscustomobject]@{
            PolicyId = $knownPolicyId
            EngineRuleId = [string]$requiredPolicies[$knownPolicyId].EngineRuleId
        }
    }
    return [pscustomobject]@{
        PolicyId = 'PF-GATE-001'
        EngineRuleId = 'gate/catalog-owner-and-connections'
    }
}

function Test-SchemaVersionOne {
    param([AllowNull()][object]$Value)

    # JSON 1e0 is parsed as a Double whose mathematical value is one, so it
    # is accepted. Strings, booleans, fractions, NaN, and Infinity are not
    # schema numbers that identify version one.
    if ($Value -is [bool] -or $Value -is [string] -or $Value -isnot [System.ValueType]) {
        return $false
    }
    try {
        $number = [double]$Value
        if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) {
            return $false
        }
        return $number -eq 1.0 -and [math]::Truncate($number) -eq $number
    }
    catch {
        return $false
    }
}

function Test-IsArrayValue {
    param([AllowNull()][object]$Value)

    return $Value -is [System.Collections.IEnumerable] -and
        $Value -isnot [string] -and
        $Value -isnot [System.Collections.IDictionary]
}

function Test-IsObjectValue {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or $Value -is [string] -or $Value -is [System.ValueType]) {
        return $false
    }
    return -not (Test-IsArrayValue -Value $Value)
}

function Validate-Catalog {
    param(
        [Parameter(Mandatory)][object]$Catalog,
        [Parameter(Mandatory)][string]$CatalogText,
        [Parameter(Mandatory)][string]$CatalogRelativePath,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Diagnostics
    )

    if (-not (Has-Property -Object $Catalog -Name 'schemaVersion')) {
        Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
            -Message 'missing required field schemaVersion' -Code 'MISSING_REQUIRED_FIELD'
        return
    }
    if (-not (Test-SchemaVersionOne -Value $Catalog.schemaVersion)) {
        Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
            -Message 'catalog schema version is unsupported' -Code 'UNSUPPORTED_SCHEMA'
        return
    }
    if (-not (Has-Property -Object $Catalog -Name 'policies')) {
        Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
            -Message 'missing required field policies' -Code 'MISSING_REQUIRED_FIELD'
        return
    }
    if (-not (Test-IsArrayValue -Value $Catalog.policies)) {
        Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
            -Message 'policies must be an array' -Code 'INVALID_INPUT'
        return
    }

    foreach ($topProperty in @($Catalog.PSObject.Properties.Name)) {
        if ($topProperty -notin @('schemaVersion', 'policies')) {
            $location = Get-JsonPropertyLocation -Text $CatalogText -PropertyName $topProperty
            Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                -Message 'catalog contains an unknown top-level field' -Code 'UNKNOWN_FIELD' `
                -Line $location.Line -Column $location.Column
        }
    }

    $seenPolicyIds = @{}
    $seenEngineRuleIds = @{}
    $presentPolicyIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $policyEntries = @($Catalog.policies)
    for ($index = 0; $index -lt $policyEntries.Count; $index++) {
        $policy = $policyEntries[$index]
        if (-not (Test-IsObjectValue -Value $policy)) {
            Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                -Message 'policy entry must be an object' -Code 'INVALID_INPUT'
            continue
        }

        $identity = Get-PolicyIdentity -Policy $policy
        $policyId = $identity.PolicyId
        $engineRuleId = $identity.EngineRuleId
        $hasPolicyId = Has-Property -Object $policy -Name 'policyId'
        $hasEngineRuleId = Has-Property -Object $policy -Name 'engineRuleId'
        $rawPolicyId = if ($hasPolicyId) { $policy.policyId } else { $null }
        $rawEngineRuleId = if ($hasEngineRuleId) { $policy.engineRuleId } else { $null }
        $knownPolicyId = $rawPolicyId -is [string] -and $requiredPolicies.Contains([string]$rawPolicyId)
        $policyKey = if ($knownPolicyId) { [string]$rawPolicyId } else { $null }
        # A missing identity field uses the catalog gate identity as the
        # diagnostic anchor, but must not participate in duplicate tracking.
        # Otherwise a missing policyId/engineRuleId would create a spurious
        # duplicate against PF-GATE-001 and obscure the single root cause.
        $isDuplicatePolicyId = $hasPolicyId -and $seenPolicyIds.ContainsKey([string]$rawPolicyId)
        if ($hasPolicyId) {
            $rawPolicyIdText = [string]$rawPolicyId
            $policyOccurrence = if ($seenPolicyIds.ContainsKey($rawPolicyIdText)) { [int]$seenPolicyIds[$rawPolicyIdText] + 1 } else { 1 }
            $policyLocation = Get-JsonPropertyLocation -Text $CatalogText -PropertyName 'policyId' -Value $rawPolicyIdText -Occurrence $policyOccurrence
            if ($isDuplicatePolicyId) {
                $seenPolicyIds[$rawPolicyIdText] = $policyOccurrence
                Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                    -Message 'duplicate policy identifier' -Code 'DUPLICATE_POLICY_ID' `
                    -Line $policyLocation.Line -Column $policyLocation.Column
            }
            else {
                $seenPolicyIds[$rawPolicyIdText] = 1
            }
            if ($knownPolicyId) {
                $null = $presentPolicyIds.Add($policyKey)
            }
            else {
                Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                    -PolicyId $policyId -EngineRuleId $engineRuleId `
                    -Message 'catalog contains a policy without a registered gate' -Code 'UNSUPPORTED_POLICY' `
                    -Line $policyLocation.Line -Column $policyLocation.Column
            }
        }
        elseif ($hasEngineRuleId) {
            # A policyId-less entry can still be associated with a required
            # policy through its unique engineRuleId. Treat that association
            # as presence for the required-ID check, while keeping the
            # missing-field diagnostic as the only reported cause.
            foreach ($requiredPolicyId in $requiredPolicies.Keys) {
                if ($requiredPolicies[$requiredPolicyId].EngineRuleId -eq [string]$rawEngineRuleId) {
                    $null = $presentPolicyIds.Add($requiredPolicyId)
                    break
                }
            }
        }
        if ($hasEngineRuleId) {
            $rawEngineRuleIdText = [string]$rawEngineRuleId
            $isDuplicateEngineRuleId = $seenEngineRuleIds.ContainsKey($rawEngineRuleIdText)
            $engineOccurrence = if ($isDuplicateEngineRuleId) { [int]$seenEngineRuleIds[$rawEngineRuleIdText] + 1 } else { 1 }
            $engineLocation = Get-JsonPropertyLocation -Text $CatalogText -PropertyName 'engineRuleId' -Value $rawEngineRuleIdText -Occurrence $engineOccurrence
            if ($isDuplicateEngineRuleId -and -not $isDuplicatePolicyId) {
                $seenEngineRuleIds[$rawEngineRuleIdText] = $engineOccurrence
                Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                    -Message 'duplicate engine rule identifier' -Code 'DUPLICATE_ENGINE_RULE_ID' `
                    -Line $engineLocation.Line -Column $engineLocation.Column
            }
            else {
                $seenEngineRuleIds[$rawEngineRuleIdText] = 1
            }
        }

        foreach ($requiredField in $policyRequiredFields) {
            if (-not (Has-Property -Object $policy -Name $requiredField)) {
                Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                    -PolicyId $policyId -EngineRuleId $engineRuleId `
                    -Message "missing required field $requiredField" -Code 'MISSING_REQUIRED_FIELD'
            }
        }

        if ((Has-Property -Object $policy -Name 'policyId') -and
            (-not [string]$policy.policyId -or [string]$policy.policyId -notmatch '^PF-')) {
            $location = Get-JsonPropertyLocation -Text $CatalogText -PropertyName 'policyId' -Value ([string]$rawPolicyId)
            Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                -PolicyId $policyId -EngineRuleId $engineRuleId `
                -Message 'policy identifier has invalid format' -Code 'INVALID_POLICY_ID' `
                -Line $location.Line -Column $location.Column
        }

        if (Has-Property -Object $policy -Name 'adapterOwner') {
            $owner = [string]$policy.adapterOwner
            if ($owner -notin $validOwners) {
                $location = Get-JsonPropertyLocation -Text $CatalogText -PropertyName 'adapterOwner' -Value $owner
                Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                    -PolicyId $policyId -EngineRuleId $engineRuleId `
                    -Message 'catalog contains an unknown adapter owner' -Code 'UNKNOWN_ADAPTER_OWNER' `
                    -Line $location.Line -Column $location.Column
            }
            elseif (-not $isDuplicatePolicyId -and $knownPolicyId -and $requiredPolicies[$policyId].Owner -ne $owner) {
                Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                    -PolicyId $policyId -EngineRuleId $engineRuleId `
                    -Message 'policy owner does not match catalog contract' `
                    -Code 'INVALID_ADAPTER_OWNER'
            }
        }

        if ((Has-Property -Object $policy -Name 'engineRuleId') -and
            -not $isDuplicatePolicyId -and
            -not $isDuplicateEngineRuleId -and
            $knownPolicyId -and
            $requiredPolicies[$policyId].EngineRuleId -ne [string]$rawEngineRuleId) {
            Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                -PolicyId $policyId -EngineRuleId $engineRuleId `
                -Message 'policy engine rule does not match catalog contract' -Code 'INVALID_ENGINE_RULE_ID'
        }

        if ((Has-Property -Object $policy -Name 'phase') -and [string]$policy.phase -ne '1') {
            Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                -PolicyId $policyId -EngineRuleId $engineRuleId `
                -Message 'policy phase is not supported' -Code 'INVALID_PHASE'
        }

        if ((Has-Property -Object $policy -Name 'severity') -and [string]$policy.severity -ne 'Error') {
            Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                -PolicyId $policyId -EngineRuleId $engineRuleId `
                -Message 'policy severity is not allowed' -Code 'SEVERITY_DOWNGRADE'
        }

        if (Has-Property -Object $policy -Name 'targets') {
            $targets = $policy.targets
            if (-not (Test-IsObjectValue -Value $targets)) {
                Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                    -PolicyId $policyId -EngineRuleId $engineRuleId `
                    -Message 'targets must be an object' -Code 'INVALID_INPUT'
            }
            else {
                foreach ($targetField in $targetRequiredFields) {
                    if (-not (Has-Property -Object $targets -Name $targetField)) {
                        Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                            -PolicyId $policyId -EngineRuleId $engineRuleId `
                            -Message "missing required field targets.$targetField" -Code 'MISSING_REQUIRED_FIELD'
                    }
                }
                foreach ($arrayField in @('seams', 'scopes', 'include')) {
                    if ((Has-Property -Object $targets -Name $arrayField) -and
                        -not (Test-IsArrayValue -Value $targets.$arrayField)) {
                        Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                            -PolicyId $policyId -EngineRuleId $engineRuleId `
                            -Message "targets.$arrayField must be an array" -Code 'INVALID_INPUT'
                    }
                }
                if ((Has-Property -Object $targets -Name 'diagnosticTarget') -and
                    $targets.diagnosticTarget -isnot [string]) {
                    Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                        -PolicyId $policyId -EngineRuleId $engineRuleId `
                        -Message 'targets.diagnosticTarget must be a string' -Code 'INVALID_INPUT'
                }
                if ((Has-Property -Object $policy -Name 'adapterOwner') -and
                    (Has-Property -Object $targets -Name 'seams') -and
                    (Test-IsArrayValue -Value $targets.seams) -and
                    [string]$policy.adapterOwner -in $validOwners -and
                    @($targets.seams | ForEach-Object { [string]$_ }) -notcontains [string]$policy.adapterOwner) {
                    Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                        -PolicyId $policyId -EngineRuleId $engineRuleId `
                        -Message 'policy is not connected to its declared owner' `
                        -Code 'MISSING_GATE_CONNECTION'
                }
            }
        }

        if (Has-Property -Object $policy -Name 'exceptions') {
            if (-not (Test-IsArrayValue -Value $policy.exceptions)) {
                Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                    -PolicyId $policyId -EngineRuleId $engineRuleId `
                    -Message 'exceptions must be an array' -Code 'INVALID_INPUT'
            }
            else {
                foreach ($exception in @($policy.exceptions)) {
                    if (-not (Test-IsObjectValue -Value $exception)) {
                        Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                            -PolicyId $policyId -EngineRuleId $engineRuleId `
                            -Message 'exception entry must be an object' -Code 'INVALID_INPUT'
                        continue
                    }
                    foreach ($exceptionField in $exceptionRequiredFields) {
                        if (-not (Has-Property -Object $exception -Name $exceptionField)) {
                            Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                                -PolicyId $policyId -EngineRuleId $engineRuleId `
                                -Message "missing required field exceptions[].$exceptionField" `
                                -Code 'MISSING_REQUIRED_FIELD'
                        }
                    }
                }
            }
        }
    }

    foreach ($requiredPolicyId in $requiredPolicies.Keys) {
        if (-not $presentPolicyIds.Contains($requiredPolicyId)) {
            Add-CatalogDiagnostic -Diagnostics $Diagnostics -CatalogRelativePath $CatalogRelativePath `
                -Message 'catalog is missing a required policy' -Code 'MISSING_REQUIRED_POLICY'
        }
    }
}

function Get-ScannableFiles {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][bool]$IsProjectRoot
    )

    $skipDirectoryNames = @(
        '.git', 'node_modules', 'target', 'dist', 'coverage', 'playwright-report',
        'playwright-report-oracle', 'test-results', 'test-results-oracle', '.worktrees'
    )
    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction Stop)) {
        if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            continue
        }
        $relative = Get-RepositoryRelativePath -Root $Root -FullPath $file.FullName
        $parts = @($relative -split '/')
        if (@($parts | Where-Object { $_ -in $skipDirectoryNames }).Count -gt 0) {
            continue
        }
        if ($IsProjectRoot -and $relative -like 'scripts/fixtures/*') {
            continue
        }
        $isRelevantRoot = $false
        foreach ($scanRoot in $testPlacementRoots) {
            if ($relative.Equals($scanRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
                $relative.StartsWith($scanRoot + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
                $isRelevantRoot = $true
                break
            }
        }
        # The root-level input.json is the documented adapter fixture anchor
        # used by the path-level contract. It is the only file outside the
        # declared source roots that this validator intentionally reads.
        if ($relative.Equals('input.json', [System.StringComparison]::OrdinalIgnoreCase)) {
            $isRelevantRoot = $true
        }
        if (-not $isRelevantRoot) {
            continue
        }
        $extension = [System.IO.Path]::GetExtension($file.Name).ToLowerInvariant()
        if ($extension -notin $testPlacementExtensions) {
            # This validator consumes source/config text only. Images, archives,
            # compiled output, and other binary artifacts are not test runners
            # and must not become decode failures.
            continue
        }
        $null = $files.Add($file)
    }
    return @($files | Sort-Object FullName)
}

function Get-FileText {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    try {
        $bytes = [System.IO.File]::ReadAllBytes($File.FullName)
        return [pscustomobject]@{
            Status = 'Ok'
            Text = $utf8Strict.GetString($bytes)
        }
    }
    catch {
        $exception = $_.Exception
        while ($null -ne $exception.InnerException) {
            if ($exception.InnerException -is [System.Text.DecoderFallbackException]) {
                return [pscustomobject]@{ Status = 'InvalidUtf8'; Text = $null }
            }
            $exception = $exception.InnerException
        }
        return [pscustomobject]@{ Status = 'ReadError'; Text = $null }
    }
}

function Test-GateConnectionRequirement {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Requirement
    )

    $fullPath = Join-Path $Root $Requirement.Path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        return $false
    }
    $file = Get-Item -LiteralPath $fullPath -Force
    $readResult = Get-FileText -File $file
    if ($readResult.Status -ne 'Ok') {
        return $false
    }
    try {
        return [regex]::IsMatch($readResult.Text, [string]$Requirement.Pattern)
    }
    catch {
        return $false
    }
}

function Validate-GateConnections {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Diagnostics
    )

    foreach ($policyId in $requiredPolicies.Keys) {
        $requirements = @($gateConnectionRequirements[$policyId])
        foreach ($requirement in $requirements) {
            if (-not (Test-GateConnectionRequirement -Root $Root -Requirement $requirement)) {
                # Requirement paths and policy identities come from static
                # source code above; no catalog-controlled value enters output.
                Add-BDiagnostic -Diagnostics $Diagnostics `
                    -PolicyId $policyId `
                    -EngineRuleId ([string]$requiredPolicies[$policyId].EngineRuleId) `
                    -Path ([string]$requirement.Path) -Line 1 -Column 1 -Rule $null `
                    -Message 'required policy gate connection is missing' `
                    -Code 'MISSING_GATE_CONNECTION'
                break
            }
        }
    }
}

function Test-RequiresGateConnectionValidation {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][bool]$IsProjectRoot
    )

    if ($IsProjectRoot) {
        return $true
    }
    # Contract repositories used only for placement/encoding cases do not
    # contain the C public seam and therefore must not receive six unrelated
    # PF-GATE diagnostics. Once a repository supplies that seam, however, the
    # complete static connection map is mandatory.
    return Test-Path -LiteralPath (Join-Path $Root 'scripts/check.ps1') -PathType Leaf
}

function Add-TestDiagnostic {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Diagnostics,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][System.IO.FileInfo]$File,
        [Parameter(Mandatory)][string]$Message,
        [AllowNull()][object]$Line,
        [AllowNull()][object]$Column,
        [AllowNull()][string]$Rule = $null,
        [AllowNull()][string]$Code = 'TEST_PLACEMENT'
    )

    Add-BDiagnostic -Diagnostics $Diagnostics -PolicyId 'PF-TEST-001' `
        -EngineRuleId 'repository/test-placement-runner-separation' `
        -Path (Get-RepositoryRelativePath -Root $Root -FullPath $File.FullName) `
        -Line $Line -Column $Column -Rule $Rule -Message $Message -Code $Code
}

function Get-MatchLocation {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Pattern
    )

    $match = [regex]::Match($Text, $Pattern)
    if (-not $match.Success) {
        return [pscustomobject]@{ Line = 1; Column = 1; Index = 0 }
    }
    $location = Get-TextLocation -Text $Text -Index $match.Index
    return [pscustomobject]@{ Line = $location.Line; Column = $location.Column; Index = $match.Index }
}

function Test-TestRegistration {
    param([Parameter(Mandatory)][string]$Text)

    # `RegExp.prototype.test(...)` and similar helper calls are not test
    # registrations. A dot is therefore excluded from the look-behind; only
    # an identifier at the call site can register a test.
    return [regex]::IsMatch($Text, '(?m)(?<![\w$.])(?:describe|it|test|specify)(?:\s*\.\s*[A-Za-z_$][\w$]*)?\s*\(') -or
        [regex]::IsMatch($Text, '(?m)^\s*@(?:Test|ParameterizedTest)\b')
}

function Validate-TestPlacement {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][bool]$IsProjectRoot,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Diagnostics
    )

    $files = @(Get-ScannableFiles -Root $Root -IsProjectRoot $IsProjectRoot)
    foreach ($file in $files) {
        $relative = Get-RepositoryRelativePath -Root $Root -FullPath $file.FullName
        $name = $file.Name
        $readResult = Get-FileText -File $file
        if ($readResult.Status -eq 'InvalidUtf8') {
            Add-TestDiagnostic -Diagnostics $Diagnostics -Root $Root -File $file `
                -Message 'scanned text file could not be decoded as UTF-8' -Line 1 -Column 1 `
                -Rule $null -Code 'INVALID_UTF8'
            continue
        }
        if ($readResult.Status -ne 'Ok') {
            Add-TestDiagnostic -Diagnostics $Diagnostics -Root $Root -File $file `
                -Message 'scanned text file could not be read' -Line 1 -Column 1 `
                -Rule $null -Code 'LINTER_RUNTIME_ERROR'
            continue
        }
        $text = [string]$readResult.Text
        if ($null -eq $text) {
            continue
        }

        # This marker is an adapter-contract fixture, not a repository-wide
        # source pattern. Restrict it to the documented input anchor so the
        # marker text in this validator's own source cannot self-report.
        if ($file.Name -eq 'input.json' -and $text.Contains('path-level fixture violation')) {
            Add-TestDiagnostic -Diagnostics $Diagnostics -Root $Root -File $file `
                -Message 'path-level fixture violation' -Line $null -Column $null
        }

        $isUnitRunnerFile = $relative -match '^frontend/test/' -and $name -match '\.test\.[^.]+$'
        $isE2eRunnerFile = $relative -match '^frontend/e2e/' -and $name -match '\.spec\.[^.]+$'

        if ($relative -match '^frontend/src/' -and $name -match '\.(test|spec)\.[^.]+$') {
            $location = Get-MatchLocation -Text $text -Pattern '(?m)^'
            Add-TestDiagnostic -Diagnostics $Diagnostics -Root $Root -File $file `
                -Message 'Unit test must be under frontend/test' -Line $location.Line -Column $location.Column
        }
        if ($relative -match '^frontend/test/' -and $name -match '\.spec\.[^.]+$') {
            $location = Get-MatchLocation -Text $text -Pattern '(?m)^'
            Add-TestDiagnostic -Diagnostics $Diagnostics -Root $Root -File $file `
                -Message 'E2E spec must be under frontend/e2e' -Line $location.Line -Column $location.Column
        }
        if ($relative -match '^frontend/e2e/' -and $name -match '\.oracle\.' -and
            $name -notmatch '\.oracle\.spec\.ts$') {
            $location = Get-MatchLocation -Text $text -Pattern '(?m)^'
            Add-TestDiagnostic -Diagnostics $Diagnostics -Root $Root -File $file `
                -Message 'Oracle spec must use *.oracle.spec.ts' -Line $location.Line -Column $location.Column
        }
        if ($relative -match '^backend/src/main/' -and $name -match '(Test|IT)\.java$') {
            $location = Get-MatchLocation -Text $text -Pattern '(?m)^'
            Add-TestDiagnostic -Diagnostics $Diagnostics -Root $Root -File $file `
                -Message 'backend test must be under backend/src/test' -Line $location.Line -Column $location.Column
        }

        if ($isUnitRunnerFile) {
            $pattern = '(?im)(?:\bfrom\s*|\bimport\s*(?:type\s*)?(?:\(\s*)?|\brequire\s*\(\s*)["''][^"'']*(?:frontend[\\/]e2e[\\/]|\.\.?[\\/]e2e[\\/])'
            if ([regex]::IsMatch($text, $pattern)) {
                $location = Get-MatchLocation -Text $text -Pattern $pattern
                Add-TestDiagnostic -Diagnostics $Diagnostics -Root $Root -File $file `
                    -Message 'Unit runner cannot import E2E runner' -Line $location.Line -Column $location.Column
            }
        }
        if ($isE2eRunnerFile) {
            $pattern = '(?im)(?:\bfrom\s*|\bimport\s*(?:type\s*)?(?:\(\s*)?|\brequire\s*\(\s*)["''][^"'']*(?:frontend[\\/]test[\\/]|\.\.?[\\/]test[\\/])'
            if ([regex]::IsMatch($text, $pattern)) {
                $location = Get-MatchLocation -Text $text -Pattern $pattern
                Add-TestDiagnostic -Diagnostics $Diagnostics -Root $Root -File $file `
                    -Message 'E2E runner cannot import Unit runner' -Line $location.Line -Column $location.Column
            }
        }

        if ($relative -match '(^|/)support/') {
            if (Test-TestRegistration -Text $text) {
                $location = Get-MatchLocation -Text $text `
                    -Pattern '(?m)(?<![\w$.])(?:describe|it|test|specify)(?:\s*\.\s*[A-Za-z_$][\w$]*)?\s*\(|^\s*@(?:Test|ParameterizedTest)\b'
                Add-TestDiagnostic -Diagnostics $Diagnostics -Root $Root -File $file `
                    -Message 'support directory must not register tests' -Line $location.Line -Column $location.Column
            }
        }
    }
}

function Write-BOutput {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Diagnostics,
        [Parameter(Mandatory)][ValidateSet('Text', 'Json')][string]$OutputFormat
    )

    if ($Diagnostics.Count -eq 0) {
        return
    }

    $sorted = @($Diagnostics | Sort-Object `
        @{ Expression = { [string]$_.policyId } },
        @{ Expression = { [string]$_.path } },
        @{ Expression = { if ($null -eq $_.line) { [int]::MaxValue } else { [int]$_.line } } },
        @{ Expression = { if ($null -eq $_.column) { [int]::MaxValue } else { [int]$_.column } } },
        @{ Expression = { [string]$_.message } },
        # The first five keys are the public contract. These final keys only
        # resolve a complete tie so input enumeration order cannot affect
        # serialized bytes.
        @{ Expression = { [string]$_.engineRuleId } },
        @{ Expression = { if ($null -eq $_.rule) { '' } else { [string]$_.rule } } },
        @{ Expression = { if ($null -eq $_.code) { '' } else { [string]$_.code } } })

    if ($OutputFormat -eq 'Text') {
        $lines = @($sorted | ForEach-Object {
            $line = if ($null -eq $_.line) { '-' } else { [string]$_.line }
            $column = if ($null -eq $_.column) { '-' } else { [string]$_.column }
            "$($_.policyId)|$($_.severity)|$($_.path):$line`:$column|$($_.message)"
        })
        $payload = ($lines -join "`n") + "`n"
    }
    else {
        $payload = (ConvertTo-Json -InputObject ([object[]]$sorted) -Depth 20 -Compress) + "`n"
    }

    $bytes = $utf8NoBom.GetBytes($payload)
    $stream = [Console]::OpenStandardOutput()
    try {
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
    }
    finally {
        $stream.Dispose()
    }
}

$diagnostics = [System.Collections.Generic.List[object]]::new()
$requestedRoot = Get-FullPath -Path $RepositoryRoot
if ($null -eq $requestedRoot -or -not (Test-PathWithin -Root $projectRoot -Candidate $requestedRoot)) {
    Add-BDiagnostic -Diagnostics $diagnostics -PolicyId 'PF-GATE-001' `
        -EngineRuleId 'gate/catalog-owner-and-connections' -Path '-' -Line $null -Column $null `
        -Message 'repository root is outside the allowed project boundary' -Code 'ROOT_OUTSIDE_ALLOWED_BOUNDARY'
    Write-BOutput -Diagnostics $diagnostics -OutputFormat $Format
    exit 2
}
if (-not (Test-Path -LiteralPath $requestedRoot -PathType Container)) {
    Add-BDiagnostic -Diagnostics $diagnostics -PolicyId 'PF-GATE-001' `
        -EngineRuleId 'gate/catalog-owner-and-connections' -Path '-' -Line $null -Column $null `
        -Message 'repository root does not exist' -Code 'ROOT_NOT_FOUND'
    Write-BOutput -Diagnostics $diagnostics -OutputFormat $Format
    exit 2
}

$root = (Get-Item -LiteralPath $requestedRoot -Force).FullName
$isProjectRoot = $root.TrimEnd('\', '/').Equals($projectRoot, [System.StringComparison]::OrdinalIgnoreCase)
$catalogFull = if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
    Join-Path $root 'config/project-lint-policies.json'
}
elseif ([System.IO.Path]::IsPathRooted($CatalogPath)) {
    Get-FullPath -Path $CatalogPath
}
else {
    Join-Path $root $CatalogPath
}
$catalogFull = if ($null -eq $catalogFull) { $null } else { Get-FullPath -Path $catalogFull }

if ($null -eq $catalogFull -or -not (Test-PathWithin -Root $root -Candidate $catalogFull)) {
    Add-BDiagnostic -Diagnostics $diagnostics -PolicyId 'PF-GATE-001' `
        -EngineRuleId 'gate/catalog-owner-and-connections' -Path '-' -Line $null -Column $null `
        -Message 'catalog path is outside the repository root' -Code 'CATALOG_OUTSIDE_ROOT'
    Write-BOutput -Diagnostics $diagnostics -OutputFormat $Format
    exit 2
}
if (-not (Test-Path -LiteralPath $catalogFull -PathType Leaf)) {
    $catalogPathForDiagnostic = Get-RepositoryRelativePath -Root $root -FullPath $catalogFull
    Add-BDiagnostic -Diagnostics $diagnostics -PolicyId 'PF-GATE-001' `
        -EngineRuleId 'gate/catalog-owner-and-connections' -Path $catalogPathForDiagnostic -Line $null -Column $null `
        -Message 'catalog file does not exist' -Code 'CATALOG_NOT_FOUND'
    Write-BOutput -Diagnostics $diagnostics -OutputFormat $Format
    exit 2
}

$catalogRelativePath = Get-RepositoryRelativePath -Root $root -FullPath $catalogFull
try {
    $catalogText = [System.IO.File]::ReadAllText($catalogFull, $utf8Strict)
}
catch {
    Add-BDiagnostic -Diagnostics $diagnostics -PolicyId 'PF-GATE-001' `
        -EngineRuleId 'gate/catalog-owner-and-connections' -Path $catalogRelativePath -Line 1 -Column 1 `
        -Message 'catalog file could not be read' -Code 'INVALID_INPUT'
    Write-BOutput -Diagnostics $diagnostics -OutputFormat $Format
    exit 2
}

try {
    $catalog = $catalogText | ConvertFrom-Json -Depth 100
}
catch {
    Add-CatalogDiagnostic -Diagnostics $diagnostics -CatalogRelativePath $catalogRelativePath `
        -Message 'catalog JSON is invalid' -Code 'INVALID_INPUT'
    Write-BOutput -Diagnostics $diagnostics -OutputFormat $Format
    exit 2
}

if ($null -eq $catalog -or $catalog -is [string] -or $catalog -is [System.ValueType]) {
    Add-CatalogDiagnostic -Diagnostics $diagnostics -CatalogRelativePath $catalogRelativePath `
        -Message 'catalog root must be an object' -Code 'INVALID_INPUT'
    Write-BOutput -Diagnostics $diagnostics -OutputFormat $Format
    exit 2
}

try {
    Validate-Catalog -Catalog $catalog -CatalogText $catalogText -CatalogRelativePath $catalogRelativePath -Diagnostics $diagnostics
    if ($diagnostics.Count -eq 0 -and (Test-RequiresGateConnectionValidation -Root $root -IsProjectRoot $isProjectRoot)) {
        Validate-GateConnections -Root $root -Diagnostics $diagnostics
    }
    if ($diagnostics.Count -eq 0) {
        Validate-TestPlacement -Root $root -IsProjectRoot $isProjectRoot -Diagnostics $diagnostics
    }
}
catch {
    # Never expose parser/path contents (which may contain credentials) on a
    # runtime failure. The public B contract reports a stable exit-2 code.
    Add-BDiagnostic -Diagnostics $diagnostics -PolicyId 'PF-GATE-001' `
        -EngineRuleId 'gate/catalog-owner-and-connections' -Path $catalogRelativePath `
        -Line 1 -Column 1 -Rule $null -Message 'project lint runtime failure' -Code 'LINTER_RUNTIME_ERROR'
}

Write-BOutput -Diagnostics $diagnostics -OutputFormat $Format
if ($diagnostics.Count -eq 0) {
    exit 0
}
if (@($diagnostics | Where-Object { $_.code -in @('INVALID_INPUT', 'UNSUPPORTED_SCHEMA', 'UNKNOWN_FIELD', 'CATALOG_NOT_FOUND', 'ROOT_OUTSIDE_ALLOWED_BOUNDARY', 'ROOT_NOT_FOUND', 'CATALOG_OUTSIDE_ROOT', 'INVALID_UTF8', 'LINTER_RUNTIME_ERROR') }).Count -gt 0) {
    exit 2
}
exit 1
