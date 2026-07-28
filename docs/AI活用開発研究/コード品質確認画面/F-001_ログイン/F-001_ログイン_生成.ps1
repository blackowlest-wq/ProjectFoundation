[CmdletBinding()]
param(
    [string]$DataPath = (Join-Path $PSScriptRoot 'F-001_ログイン_表示データ.json'),
    [string]$OutputPath = (Join-Path $PSScriptRoot 'F-001_ログイン_コード品質確認.html'),
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Throw-ValidationError {
    param([string]$Message)

    throw [System.InvalidOperationException]::new("Quality data validation failed: $Message")
}

function Get-RequiredProperty {
    param(
        [object]$Object,
        [string]$Name,
        [string]$Context
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        Throw-ValidationError "$Context is missing '$Name'."
    }
    return $property.Value
}

function Get-Items {
    param(
        [object]$Object,
        [string]$Name
    )

    return @(Get-RequiredProperty -Object $Object -Name $Name -Context 'root data')
}

function Assert-UniqueIds {
    param(
        [object[]]$Items,
        [string]$CollectionName
    )

    $ids = @($Items | ForEach-Object {
            $id = Get-RequiredProperty -Object $_ -Name 'id' -Context $CollectionName
            if ([string]::IsNullOrWhiteSpace([string]$id)) {
                Throw-ValidationError "$CollectionName contains an empty id."
            }
            [string]$id
        })
    $duplicates = @($ids | Group-Object | Where-Object Count -gt 1)
    if ($duplicates.Count -gt 0) {
        Throw-ValidationError "$CollectionName contains duplicate ids: $($duplicates.Name -join ', ')."
    }
}

function Assert-References {
    param(
        [object[]]$Items,
        [string]$CollectionName,
        [string]$ReferenceProperty,
        [System.Collections.Generic.HashSet[string]]$KnownIds
    )

    foreach ($item in $Items) {
        $itemId = [string](Get-RequiredProperty -Object $item -Name 'id' -Context $CollectionName)
        $references = @(Get-RequiredProperty -Object $item -Name $ReferenceProperty -Context "$CollectionName $itemId")
        foreach ($reference in $references) {
            if (-not $KnownIds.Contains([string]$reference)) {
                Throw-ValidationError "$CollectionName $itemId references unknown $ReferenceProperty '$reference'."
            }
        }
    }
}

function Assert-BidirectionalAcceptanceReferences {
    param(
        [object[]]$AcceptanceCriteria,
        [object[]]$TestCases
    )

    $acceptanceById = @{}
    foreach ($acceptance in $AcceptanceCriteria) {
        $acceptanceById[[string]$acceptance.id] = $acceptance
    }

    $caseById = @{}
    foreach ($testCase in $TestCases) {
        $caseById[[string]$testCase.id] = $testCase
    }

    foreach ($acceptance in $AcceptanceCriteria) {
        $acceptanceId = [string]$acceptance.id
        foreach ($caseId in @(Get-RequiredProperty -Object $acceptance -Name 'testCaseIds' -Context "acceptanceCriteria $acceptanceId")) {
            $case = $caseById[[string]$caseId]
            $caseAcceptanceIds = @(
                Get-RequiredProperty -Object $case -Name 'acceptanceCriteriaIds' -Context "testCases $caseId"
            )
            if ($caseAcceptanceIds -notcontains $acceptanceId) {
                Throw-ValidationError "acceptanceCriteria $acceptanceId references $caseId, but the case does not reference the acceptance criterion."
            }
        }
    }

    foreach ($testCase in $TestCases) {
        $caseId = [string]$testCase.id
        foreach ($acceptanceId in @(Get-RequiredProperty -Object $testCase -Name 'acceptanceCriteriaIds' -Context "testCases $caseId")) {
            $acceptance = $acceptanceById[[string]$acceptanceId]
            $acceptanceCaseIds = @(
                Get-RequiredProperty -Object $acceptance -Name 'testCaseIds' -Context "acceptanceCriteria $acceptanceId"
            )
            if ($acceptanceCaseIds -notcontains $caseId) {
                Throw-ValidationError "testCases $caseId references $acceptanceId, but the acceptance criterion does not reference the case."
            }
        }
    }
}

function Assert-AcceptanceExecutionStateNotOverstated {
    param(
        [object[]]$AcceptanceCriteria,
        [object[]]$TestCases
    )

    foreach ($acceptance in $AcceptanceCriteria) {
        $acceptanceId = [string]$acceptance.id
        $caseIds = @(
            Get-RequiredProperty -Object $acceptance -Name 'testCaseIds' -Context "acceptanceCriteria $acceptanceId"
        )
        $relatedCases = @($TestCases | Where-Object { $caseIds -contains [string]$_.id })
        $hasFailure = @($relatedCases | Where-Object { [string]$_.executionStatus -eq '失敗' }).Count -gt 0
        $hasIncomplete = @($relatedCases | Where-Object { [string]$_.executionStatus -ne '成功' }).Count -gt 0
        $executionStatus = [string](Get-RequiredProperty -Object $acceptance -Name 'executionStatus' -Context "acceptanceCriteria $acceptanceId")
        if ($executionStatus -eq '完了' -and ($hasFailure -or $hasIncomplete)) {
            Throw-ValidationError "acceptanceCriteria $acceptanceId is marked executionStatus 完了 while a related case is not successful."
        }
    }
}

function Get-DataReferencePath {
    param([string]$ReferencePath)

    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $ReferencePath))
}

function Assert-GlobalUniqueIds {
    param([hashtable]$Collections)

    $seen = @{}
    foreach ($entry in $Collections.GetEnumerator()) {
        foreach ($item in @($entry.Value)) {
            $id = [string](Get-RequiredProperty -Object $item -Name 'id' -Context $entry.Key)
            if ($seen.ContainsKey($id)) {
                Throw-ValidationError "id '$id' is duplicated across $($seen[$id]) and $($entry.Key)."
            }
            $seen[$id] = $entry.Key
        }
    }
}

function Assert-NonEmptyProperties {
    param(
        [object[]]$Items,
        [string]$CollectionName,
        [string[]]$PropertyNames
    )

    foreach ($item in $Items) {
        $itemId = [string](Get-RequiredProperty -Object $item -Name 'id' -Context $CollectionName)
        foreach ($propertyName in $PropertyNames) {
            $value = Get-RequiredProperty -Object $item -Name $propertyName -Context "$CollectionName $itemId"
            if ([string]::IsNullOrWhiteSpace([string]$value)) {
                Throw-ValidationError "$CollectionName $itemId has an empty '$propertyName'."
            }
        }
    }
}

function Assert-ExecutionConsistency {
    param(
        [object[]]$TestCases,
        [object[]]$TestImplementations
    )

    $implementationById = @{}
    foreach ($implementation in $TestImplementations) {
        $implementationById[[string]$implementation.id] = $implementation
    }

    foreach ($testCase in $TestCases) {
        $caseId = [string]$testCase.id
        $relatedImplementations = @(
            @(Get-RequiredProperty -Object $testCase -Name 'testImplementationIds' -Context "testCases $caseId") |
                ForEach-Object { $implementationById[[string]$_] }
        )
        $caseStatus = [string](Get-RequiredProperty -Object $testCase -Name 'executionStatus' -Context "testCases $caseId")
        $hasNonSuccessImplementation = @($relatedImplementations | Where-Object { [string]$_.executionStatus -ne '成功' }).Count -gt 0
        $hasFailedImplementation = @($relatedImplementations | Where-Object { [string]$_.executionStatus -eq '失敗' }).Count -gt 0
        if ($caseStatus -eq '成功' -and $hasNonSuccessImplementation) {
            Throw-ValidationError "testCases $caseId is successful while a linked test implementation is not successful."
        }
        if ($caseStatus -eq '失敗' -and -not $hasFailedImplementation) {
            Throw-ValidationError "testCases $caseId is failed while no linked test implementation is failed."
        }
        if ($caseStatus -eq '未実行' -and @($relatedImplementations | Where-Object { [string]$_.executionStatus -eq '成功' }).Count -eq $relatedImplementations.Count -and $relatedImplementations.Count -gt 0) {
            Throw-ValidationError "testCases $caseId is unexecuted while all linked test implementations are successful."
        }
    }
}

function Assert-QualityGateOutcomeNotOverstated {
    param(
        [object[]]$QualityGates,
        [object[]]$TestCases
    )

    foreach ($gate in $QualityGates) {
        $gateId = [string]$gate.id
        $caseIds = @(Get-RequiredProperty -Object $gate -Name 'testCaseIds' -Context "qualityGates $gateId")
        $relatedCases = @($TestCases | Where-Object { $caseIds -contains [string]$_.id })
        if ([string]$gate.status -eq '通過' -and @($relatedCases | Where-Object { [string]$_.executionStatus -ne '成功' }).Count -gt 0) {
            Throw-ValidationError "qualityGates $gateId is marked 通過 while a required case is not successful."
        }
    }
}

function Assert-TargetReferences {
    param(
        [object[]]$Findings,
        [System.Collections.Generic.HashSet[string]]$KnownTargetIds
    )

    foreach ($finding in $Findings) {
        $findingId = [string]$finding.id
        foreach ($targetId in @(Get-RequiredProperty -Object $finding -Name 'targetIds' -Context "findings $findingId")) {
            if (-not $KnownTargetIds.Contains([string]$targetId)) {
                Throw-ValidationError "findings $findingId references unknown targetId '$targetId'."
            }
        }
    }
}

function Assert-ReferencedFilesExist {
    param(
        [object[]]$Evidence,
        [object[]]$Sources
    )

    foreach ($entry in $Evidence) {
        $entryId = [string]$entry.id
        $path = [string](Get-RequiredProperty -Object $entry -Name 'path' -Context "evidence $entryId")
        $exists = Test-Path -LiteralPath (Get-DataReferencePath -ReferencePath $path) -PathType Leaf
        $available = [bool](Get-RequiredProperty -Object $entry -Name 'available' -Context "evidence $entryId")
        if ($available -and -not $exists) {
            Throw-ValidationError "evidence $entryId is marked available but file does not exist: $path"
        }
        $summaryProperty = $entry.PSObject.Properties['summaryPath']
        if ($null -ne $summaryProperty -and -not [string]::IsNullOrWhiteSpace([string]$summaryProperty.Value)) {
            $summaryPath = [string]$summaryProperty.Value
            if ($available -and -not (Test-Path -LiteralPath (Get-DataReferencePath -ReferencePath $summaryPath) -PathType Leaf)) {
                Throw-ValidationError "evidence $entryId is marked available but summary file does not exist: $summaryPath"
            }
        }
    }

    foreach ($entry in $Sources) {
        $entryId = [string]$entry.id
        $path = [string](Get-RequiredProperty -Object $entry -Name 'path' -Context "sources $entryId")
        if (-not (Test-Path -LiteralPath (Get-DataReferencePath -ReferencePath $path) -PathType Leaf)) {
            Throw-ValidationError "source $entryId file does not exist: $path"
        }
    }
}

function Assert-CoverageThresholds {
    param([object]$Coverage)

    $branchThreshold = 85.0
    foreach ($layer in @('frontend', 'backend')) {
        $coverageItem = Get-RequiredProperty -Object $Coverage -Name $layer -Context 'coverage'
        $status = [string](Get-RequiredProperty -Object $coverageItem -Name 'status' -Context "coverage $layer")
        if ($status -eq '通過') {
            $metrics = Get-RequiredProperty -Object $coverageItem -Name 'metrics' -Context "coverage $layer"
            $branchPropertyName = if ($null -ne $metrics.PSObject.Properties['branch']) { 'branch' } else { 'branches' }
            $branch = [double](Get-RequiredProperty -Object $metrics -Name $branchPropertyName -Context "coverage $layer metrics")
            if ($branch -lt $branchThreshold) {
                Throw-ValidationError "coverage $layer is marked 通過 but branch $branch is below $branchThreshold."
            }
        }
    }
}

# 機械的に検証した事実を、HTMLへ渡す共通の結果形式へ整える。
function New-AutomatedFinding {
    param(
        [string]$Category,
        [string]$Id,
        [string]$Text,
        [string]$Status,
        [string]$Priority = ''
    )

    $finding = [ordered]@{
        category = $Category
        id = $Id
        text = $Text
        status = $Status
    }
    if (-not [string]::IsNullOrWhiteSpace($Priority)) {
        $finding.priority = $Priority
    }
    return [pscustomobject]$finding
}

# 実行状態と明示された照合条件だけから、影響ケースを原因単位へ集約する。
function Get-RootCauseGroups {
    param(
        [object[]]$RootCauses,
        [object[]]$TestCases
    )

    $groups = @()
    foreach ($definition in $RootCauses) {
        $matchProperty = $definition.PSObject.Properties['match']
        if ($null -eq $matchProperty -or $null -eq $matchProperty.Value) {
            continue
        }
        $match = $matchProperty.Value
        $layer = [string]$match.layer
        $noteContains = [string]$match.executionNoteContains
        $affectedCases = @($TestCases | Where-Object {
                [string]$_.executionStatus -ne '成功' -and
                [string]$_.layer -eq $layer -and
                [string]$_.executionNote -like "*$noteContains*"
            })
        if ($affectedCases.Count -eq 0) {
            continue
        }
        $hasFailure = @($affectedCases | Where-Object { [string]$_.executionStatus -eq '失敗' }).Count -gt 0
        $groups += [pscustomobject]@{
            id = [string]$definition.id
            name = [string]$definition.name
            reason = [string]$definition.reason
            status = if ($hasFailure) { 'NG' } else { '保留' }
            caseIds = @($affectedCases | ForEach-Object { [string]$_.id })
            impactCaseCount = $affectedCases.Count
        }
    }
    return @($groups)
}

# AIの意味評価を参照せず、JSONの構造・紐付け・実行・基準値から確認項目を生成する。
function Get-AutomatedFindings {
    param([object]$Data)

    $acceptanceCriteria = @(Get-Items -Object $Data -Name 'acceptanceCriteria')
    $qualityGates = @(Get-Items -Object $Data -Name 'qualityGates')
    $rootCauses = @(Get-Items -Object $Data -Name 'rootCauses')
    $testCases = @(Get-Items -Object $Data -Name 'testCases')
    $findings = @(Get-Items -Object $Data -Name 'findings')
    $coverage = Get-RequiredProperty -Object $Data -Name 'coverage' -Context 'root data'

    $automatedFindings = @()
    foreach ($acceptance in $acceptanceCriteria) {
        $caseIds = @(Get-RequiredProperty -Object $acceptance -Name 'testCaseIds' -Context "acceptanceCriteria $($acceptance.id)")
        if ($caseIds.Count -eq 0) {
            $automatedFindings += New-AutomatedFinding -Category '受入条件未対応' -Id ([string]$acceptance.id) -Text ([string]$acceptance.text) -Status '未対応'
        }
    }

    foreach ($testCase in $testCases) {
        $caseId = [string]$testCase.id
        $implementationIds = @(Get-RequiredProperty -Object $testCase -Name 'testImplementationIds' -Context "testCases $caseId")
        $evidenceIds = @(Get-RequiredProperty -Object $testCase -Name 'evidenceIds' -Context "testCases $caseId")
        if ($implementationIds.Count -eq 0) {
            $automatedFindings += New-AutomatedFinding -Category '実テスト未紐付け' -Id $caseId -Text ([string]$testCase.name) -Status '未紐付け'
        }
        if ($evidenceIds.Count -eq 0) {
            $automatedFindings += New-AutomatedFinding -Category '証跡未紐付け' -Id $caseId -Text ([string]$testCase.name) -Status '未紐付け'
        }
    }

    $rootCauseGroups = @(Get-RootCauseGroups -RootCauses $rootCauses -TestCases $testCases)
    foreach ($rootCause in $rootCauseGroups) {
        $text = "{0} / 原因: {1} / 影響ケース: {2}件" -f $rootCause.name, $rootCause.reason, $rootCause.impactCaseCount
        $automatedFindings += New-AutomatedFinding -Category 'ブロッカー' -Id ([string]$rootCause.id) -Text $text -Status ([string]$rootCause.status) -Priority 'ブロッカー'
    }

    foreach ($testCase in $testCases | Where-Object { [string]$_.executionStatus -ne '成功' }) {
        $category = if ([string]$testCase.executionStatus -eq '失敗') { '失敗' } else { '未実行' }
        $automatedFindings += New-AutomatedFinding -Category $category -Id ([string]$testCase.id) -Text ([string]($testCase.executionNote ?? $testCase.name)) -Status ([string]$testCase.executionStatus)
    }

    $caseById = @{}
    foreach ($testCase in $testCases) {
        $caseById[[string]$testCase.id] = $testCase
    }
    foreach ($gate in $qualityGates) {
        $gateCases = @((Get-RequiredProperty -Object $gate -Name 'testCaseIds' -Context "qualityGates $($gate.id)") | ForEach-Object { $caseById[[string]$_] } | Where-Object { $null -ne $_ })
        $failures = @($gateCases | Where-Object { [string]$_.executionStatus -eq '失敗' })
        $incomplete = @($gateCases | Where-Object { [string]$_.executionStatus -ne '成功' })
        if ($failures.Count -gt 0) {
            $gateStatus = 'NG'
            $gateReason = "必須ケースの失敗: $($failures.id -join ', ')"
        }
        elseif ($incomplete.Count -gt 0) {
            $gateStatus = '未通過'
            $gateReason = '必須ケースが未実行'
        }
        else {
            $gateStatus = '通過'
            $gateReason = ''
        }
        if ($gateStatus -ne '通過') {
            $automatedFindings += New-AutomatedFinding -Category '品質ゲート' -Id ([string]$gate.id) -Text ([string]($gateReason ?? $gate.reason)) -Status $gateStatus -Priority '品質ゲート'
        }
    }

    foreach ($layer in @('frontend', 'backend')) {
        $coverageItem = Get-RequiredProperty -Object $coverage -Name $layer -Context 'coverage'
        $coverageStatus = [string](Get-RequiredProperty -Object $coverageItem -Name 'status' -Context "coverage $layer")
        if ($coverageStatus -ne '通過') {
            $automatedFindings += New-AutomatedFinding -Category 'カバレッジ' -Id ("COV-{0}" -f $layer.ToUpperInvariant()) -Text ([string]($coverageItem.reason ?? "$layer coverage")) -Status $coverageStatus
        }
        foreach ($branch in @($coverageItem.uncoveredBranches)) {
            $automatedFindings += New-AutomatedFinding -Category '未通過分岐' -Id ([string]$branch.id) -Text ([string]$branch.text) -Status '未通過'
        }
    }

    foreach ($finding in $findings | Where-Object { [string]$_.status -eq '保留' }) {
        $automatedFindings += New-AutomatedFinding -Category '指摘・保留' -Id ([string]$finding.id) -Text ([string]$finding.summary) -Status '保留' -Priority ([string]$finding.priority)
    }

    return @($automatedFindings)
}

function Update-EvidenceMetadata {
    param(
        [object]$Data,
        [string]$CurrentCommit
    )

    foreach ($entry in @($Data.evidence)) {
        $path = [string]$entry.path
        $fullPath = Get-DataReferencePath -ReferencePath $path
        $exists = Test-Path -LiteralPath $fullPath -PathType Leaf
        $entry | Add-Member -NotePropertyName available -NotePropertyValue $exists -Force
        $infoProperty = $entry.PSObject.Properties['executionInfo']
        if ($null -eq $infoProperty -or $null -eq $infoProperty.Value) {
            $entry | Add-Member -NotePropertyName executionInfo -NotePropertyValue ([pscustomobject]@{
                    executedAt = $null
                    sourceCommit = $null
                    command = $null
                    exitCode = $null
                    environment = $null
                    reportGeneratedAt = $null
                    isStale = $null
                }) -Force
        }
        $executionInfo = $entry.executionInfo
        if ($exists) {
            $executionInfo.reportGeneratedAt = (Get-Item -LiteralPath $fullPath).LastWriteTime.ToString('o')
        }
        $sourceCommitProperty = $executionInfo.PSObject.Properties['sourceCommit']
        if ($null -ne $sourceCommitProperty -and -not [string]::IsNullOrWhiteSpace([string]$sourceCommitProperty.Value)) {
            $executionInfo.isStale = [string]$sourceCommitProperty.Value -ne $CurrentCommit
            if ($executionInfo.isStale) {
                Write-Warning "evidence $($entry.id) sourceCommit $($sourceCommitProperty.Value) differs from generated commit $CurrentCommit."
            }
        }
    }
}

function Assert-AllowedStatus {
    param(
        [object[]]$Items,
        [string]$CollectionName,
        [string]$PropertyName,
        [string[]]$Allowed
    )

    foreach ($item in $Items) {
        $itemId = [string](Get-RequiredProperty -Object $item -Name 'id' -Context $CollectionName)
        $value = [string](Get-RequiredProperty -Object $item -Name $PropertyName -Context "$CollectionName $itemId")
        if ($Allowed -notcontains $value) {
            Throw-ValidationError "$CollectionName $itemId has invalid $PropertyName '$value'."
        }
    }
}

function Assert-NoSecretValues {
    param([string]$JsonText)

    $patterns = @(
        '(?i)jdbc:[^\s"}]+',
        '(?i)(api[_-]?key|access[_-]?token|client[_-]?secret)\s*[:=]\s*[^\s,"}]+',
        '(?i)-----BEGIN [A-Z ]+ PRIVATE KEY-----',
        '(?i)password\s*[:=]\s*[^\s,"}]{8,}'
    )
    foreach ($pattern in $patterns) {
        if ($JsonText -match $pattern) {
            Throw-ValidationError "possible secret value matched pattern '$pattern'."
        }
    }
}

function Read-QualityData {
    if (-not (Test-Path -LiteralPath $DataPath -PathType Leaf)) {
        Throw-ValidationError "data file does not exist: $DataPath"
    }
    $jsonText = Get-Content -Raw -Encoding UTF8 -LiteralPath $DataPath
    if ([string]::IsNullOrWhiteSpace($jsonText)) {
        Throw-ValidationError 'data file is empty.'
    }
    Assert-NoSecretValues -JsonText $jsonText
    try {
        return $jsonText | ConvertFrom-Json
    }
    catch {
        Throw-ValidationError "data file is not valid JSON: $($_.Exception.Message)"
    }
}

function Test-QualityData {
    param([object]$Data)

    $schemaVersion = [string](Get-RequiredProperty -Object $Data -Name 'schemaVersion' -Context 'root data')
    if ($schemaVersion -ne '1.0') {
        Throw-ValidationError "root data schemaVersion must be 1.0, got '$schemaVersion'."
    }

    $feature = Get-RequiredProperty -Object $Data -Name 'feature' -Context 'root data'
    foreach ($name in @('id', 'name', 'screenId', 'title', 'scope', 'reviewMode', 'snapshot')) {
        Get-RequiredProperty -Object $feature -Name $name -Context 'feature' | Out-Null
    }

    $acceptanceCriteria = Get-Items -Object $Data -Name 'acceptanceCriteria'
    $qualityGates = Get-Items -Object $Data -Name 'qualityGates'
    $rootCauses = Get-Items -Object $Data -Name 'rootCauses'
    $testCases = Get-Items -Object $Data -Name 'testCases'
    $viewpoints = Get-Items -Object $Data -Name 'viewpoints'
    $testImplementations = Get-Items -Object $Data -Name 'testImplementations'
    $evidence = Get-Items -Object $Data -Name 'evidence'
    $findings = Get-Items -Object $Data -Name 'findings'
    $sources = Get-Items -Object $Data -Name 'sources'
    $coverage = Get-RequiredProperty -Object $Data -Name 'coverage' -Context 'root data'

    $collections = @{
        acceptanceCriteria = $acceptanceCriteria
        qualityGates = $qualityGates
        rootCauses = $rootCauses
        testCases = $testCases
        viewpoints = $viewpoints
        testImplementations = $testImplementations
        evidence = $evidence
        findings = $findings
        sources = $sources
    }
    foreach ($entry in $collections.GetEnumerator()) {
        Assert-UniqueIds -Items $entry.Value -CollectionName $entry.Key
    }
    Assert-GlobalUniqueIds -Collections $collections
    Assert-NonEmptyProperties -Items $acceptanceCriteria -CollectionName 'acceptanceCriteria' -PropertyNames @('text', 'blockingReason')
    Assert-NonEmptyProperties -Items $qualityGates -CollectionName 'qualityGates' -PropertyNames @('name', 'reason')
    Assert-NonEmptyProperties -Items $rootCauses -CollectionName 'rootCauses' -PropertyNames @('name', 'reason')
    Assert-NonEmptyProperties -Items $testCases -CollectionName 'testCases' -PropertyNames @('name', 'purpose', 'precondition', 'action', 'expected')
    Assert-NonEmptyProperties -Items $testImplementations -CollectionName 'testImplementations' -PropertyNames @('file', 'name', 'runCommand')
    Assert-NonEmptyProperties -Items $evidence -CollectionName 'evidence' -PropertyNames @('type', 'path', 'note')
    Assert-NonEmptyProperties -Items $sources -CollectionName 'sources' -PropertyNames @('name', 'path', 'section')

    $acceptanceIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($acceptanceCriteria.id))
    $caseIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($testCases.id))
    $implementationIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($testImplementations.id))
    $evidenceIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($evidence.id))
    $findingIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($findings.id))
    $rootCauseIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($rootCauses.id))
    $knownTargetIds = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($collection in @($acceptanceCriteria, $qualityGates, $rootCauses, $testCases, $viewpoints, $testImplementations, $evidence, $findings, $sources)) {
        foreach ($item in $collection) {
            $knownTargetIds.Add([string]$item.id) | Out-Null
        }
    }

    Assert-References -Items $acceptanceCriteria -CollectionName 'acceptanceCriteria' -ReferenceProperty 'testCaseIds' -KnownIds $caseIds
    Assert-References -Items $qualityGates -CollectionName 'qualityGates' -ReferenceProperty 'testCaseIds' -KnownIds $caseIds
    Assert-References -Items $testCases -CollectionName 'testCases' -ReferenceProperty 'acceptanceCriteriaIds' -KnownIds $acceptanceIds
    Assert-References -Items $testCases -CollectionName 'testCases' -ReferenceProperty 'testImplementationIds' -KnownIds $implementationIds
    Assert-References -Items $testCases -CollectionName 'testCases' -ReferenceProperty 'evidenceIds' -KnownIds $evidenceIds
    Assert-References -Items $testCases -CollectionName 'testCases' -ReferenceProperty 'findingIds' -KnownIds $findingIds
    Assert-References -Items $viewpoints -CollectionName 'viewpoints' -ReferenceProperty 'caseIds' -KnownIds $caseIds
    Assert-References -Items $viewpoints -CollectionName 'viewpoints' -ReferenceProperty 'findingIds' -KnownIds $findingIds
    Assert-BidirectionalAcceptanceReferences -AcceptanceCriteria $acceptanceCriteria -TestCases $testCases
    Assert-AcceptanceExecutionStateNotOverstated -AcceptanceCriteria $acceptanceCriteria -TestCases $testCases
    Assert-ExecutionConsistency -TestCases $testCases -TestImplementations $testImplementations
    Assert-QualityGateOutcomeNotOverstated -QualityGates $qualityGates -TestCases $testCases
    Assert-TargetReferences -Findings $findings -KnownTargetIds $knownTargetIds
    Assert-ReferencedFilesExist -Evidence $evidence -Sources $sources
    Assert-CoverageThresholds -Coverage $coverage

    Assert-AllowedStatus -Items $acceptanceCriteria -CollectionName 'acceptanceCriteria' -PropertyName 'reviewStatus' -Allowed @('OK', '不足', '対象外', '保留')
    Assert-AllowedStatus -Items $acceptanceCriteria -CollectionName 'acceptanceCriteria' -PropertyName 'caseDesignStatus' -Allowed @('OK', '不足', '対象外', '保留')
    Assert-AllowedStatus -Items $acceptanceCriteria -CollectionName 'acceptanceCriteria' -PropertyName 'executionStatus' -Allowed @('完了', '未完了', '失敗')
    Assert-AllowedStatus -Items $qualityGates -CollectionName 'qualityGates' -PropertyName 'status' -Allowed @('通過', '未通過', '保留', 'NG')
    Assert-AllowedStatus -Items $rootCauses -CollectionName 'rootCauses' -PropertyName 'status' -Allowed @('解消', '保留', 'NG')
    Assert-AllowedStatus -Items $testCases -CollectionName 'testCases' -PropertyName 'reviewStatus' -Allowed @('OK', '不足', '対象外', '保留')
    Assert-AllowedStatus -Items $testCases -CollectionName 'testCases' -PropertyName 'executionStatus' -Allowed @('成功', '失敗', '未実行')
    Assert-AllowedStatus -Items $testImplementations -CollectionName 'testImplementations' -PropertyName 'executionStatus' -Allowed @('成功', '失敗', '未実行')
    Assert-AllowedStatus -Items $viewpoints -CollectionName 'viewpoints' -PropertyName 'reviewStatus' -Allowed @('OK', '不足', '対象外', '保留')

    foreach ($layer in @('frontend', 'backend')) {
        $coverageItem = Get-RequiredProperty -Object $coverage -Name $layer -Context 'coverage'
        $status = [string](Get-RequiredProperty -Object $coverageItem -Name 'status' -Context "coverage $layer")
        if (@('通過', '未通過', '未生成', '対象外') -notcontains $status) {
            Throw-ValidationError "coverage $layer has invalid status '$status'."
        }
    }

    $successfulWithoutExecutionDate = @($testImplementations | Where-Object {
            [string]$_.executionStatus -eq '成功' -and
            ($null -eq $_.PSObject.Properties['executedAt'] -or [string]::IsNullOrWhiteSpace([string]$_.executedAt))
        }).Count
    if ($successfulWithoutExecutionDate -gt 0) {
        Write-Warning "$successfulWithoutExecutionDate successful test implementations have no executedAt; execution time is not available in the snapshot."
    }

    return $true
}

function Get-GeneratedCommit {
    try {
        $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
        $commit = (& git -C $repositoryRoot rev-parse --short HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$commit)) {
            return ([string]$commit).Trim()
        }
    }
    catch {
        return 'unknown'
    }
    return 'unknown'
}

function Get-EmbeddedJson {
    param([object]$Data)

    $json = $Data | ConvertTo-Json -Depth 50 -Compress
    return $json.Replace('</script>', '<\/script>')
}

function Get-HtmlTemplate {
    return @'
<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>__TITLE__</title>
  <style>
    :root { color-scheme: light; --ink:#1e293b; --muted:#64748b; --line:#dbe3ee; --panel:#ffffff; --bg:#f4f7fb; --accent:#2457a6; --ok:#177245; --warn:#a15c00; --danger:#b42318; --hold:#6b4ca1; }
    * { box-sizing:border-box; }
    body { margin:0; background:var(--bg); color:var(--ink); font-family:"Segoe UI","Yu Gothic UI",Meiryo,sans-serif; line-height:1.55; }
    a { color:var(--accent); }
    .shell { max-width:1440px; margin:0 auto; padding:28px; }
    .hero { display:flex; flex-wrap:wrap; justify-content:space-between; gap:20px; align-items:flex-end; margin-bottom:22px; }
    .eyebrow { margin:0 0 4px; color:var(--accent); font-size:12px; font-weight:700; letter-spacing:.12em; text-transform:uppercase; }
    h1,h2,h3 { line-height:1.25; }
    h1 { margin:0; font-size:32px; }
    h2 { margin:0 0 14px; font-size:22px; }
    h3 { margin:18px 0 8px; font-size:16px; }
    .meta { color:var(--muted); font-size:13px; text-align:right; }
    .grid { display:grid; gap:12px; }
    .summary { grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); margin-bottom:18px; }
    .assessment-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(160px,1fr)); gap:10px; margin-top:12px; }
    .assessment-grid > div { background:rgba(255,255,255,.72); border:1px solid var(--line); border-radius:8px; padding:9px 11px; }
    .card,.panel { background:var(--panel); border:1px solid var(--line); border-radius:14px; box-shadow:0 4px 18px rgba(31,55,89,.06); }
    .card { padding:16px; }
    .card .label { color:var(--muted); font-size:12px; }
    .card .value { margin-top:3px; font-size:26px; font-weight:750; }
    .card .note { color:var(--muted); font-size:12px; }
    .nav { display:flex; flex-wrap:wrap; gap:8px; margin:0 0 16px; }
    .nav button,.filter button { border:1px solid var(--line); border-radius:9px; background:#fff; color:var(--ink); cursor:pointer; padding:9px 12px; }
    .nav button.active,.nav button:hover,.filter button:hover { background:#e8f0ff; border-color:#a8c2ef; color:#163e78; }
    .panel { padding:20px; margin-bottom:16px; }
    .panel[hidden] { display:none; }
    .filter { display:flex; flex-wrap:wrap; gap:8px; margin:0 0 14px; }
    .filter input,.filter select { border:1px solid var(--line); border-radius:9px; background:#fff; color:var(--ink); padding:9px 10px; min-width:190px; }
    .table-wrap { overflow:auto; }
    table { width:100%; border-collapse:collapse; min-width:760px; }
    th,td { border-bottom:1px solid var(--line); padding:10px 9px; text-align:left; vertical-align:top; }
    th { background:#f8fafc; color:#475569; font-size:12px; white-space:nowrap; }
    td { font-size:13px; }
    tr:last-child td { border-bottom:0; }
    .badge { display:inline-block; border-radius:999px; padding:2px 8px; font-size:12px; font-weight:700; white-space:nowrap; }
    .badge.ok { background:#e4f5eb; color:var(--ok); }
    .badge.warn { background:#fff1d6; color:var(--warn); }
    .badge.danger { background:#ffe4e1; color:var(--danger); }
    .badge.hold { background:#eee7fb; color:var(--hold); }
    .badge.neutral { background:#e9eef5; color:#536174; }
    .muted { color:var(--muted); }
    .callout { border-left:4px solid var(--accent); background:#f3f7ff; padding:12px 14px; border-radius:8px; margin:10px 0; }
    .callout.warn { border-left-color:var(--warn); background:#fff9ed; }
    .callout.danger { border-left-color:var(--danger); background:#fff4f2; }
    .target-flash { outline:3px solid #f2bd4b; outline-offset:3px; transition:outline-color .3s ease; }
    .case-list { display:grid; gap:8px; }
    details.case { border:1px solid var(--line); border-radius:10px; padding:8px 11px; background:#fbfdff; }
    details.case summary { cursor:pointer; font-weight:650; }
    .case-body { display:grid; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); gap:10px; margin:10px 0 4px; }
    .case-field { background:#fff; border:1px solid #edf1f6; border-radius:8px; padding:9px; }
    .case-field strong { display:block; color:#475569; font-size:11px; margin-bottom:3px; }
    .empty { padding:22px; color:var(--muted); text-align:center; }
    .small { font-size:12px; }
    .footer { color:var(--muted); font-size:12px; padding:4px 0 22px; }
    @media (max-width:700px) { .shell { padding:16px; } h1 { font-size:26px; } .meta { text-align:left; } }
  </style>
</head>
<body>
  <main class="shell">
    <header class="hero">
      <div>
        <p class="eyebrow">Code Quality Review</p>
        <h1>__TITLE__</h1>
        <p id="scope" class="muted"></p>
      </div>
      <div id="meta" class="meta"></div>
    </header>
    <section id="summary" class="grid summary" aria-label="概要"></section>
    <nav class="nav" aria-label="表示切替">
      <button type="button" data-panel="overview" class="active">概要</button>
      <button type="button" data-panel="traceability">受入条件・追跡</button>
      <button type="button" data-panel="viewpoints">観点一覧</button>
      <button type="button" data-panel="gaps">NG・要確認</button>
      <button type="button" data-panel="evidence">証跡・ソース</button>
    </nav>
    <section id="panel-overview" class="panel" data-panel-content="overview"></section>
    <section id="panel-traceability" class="panel" data-panel-content="traceability" hidden></section>
    <section id="panel-viewpoints" class="panel" data-panel-content="viewpoints" hidden></section>
    <section id="panel-gaps" class="panel" data-panel-content="gaps" hidden></section>
    <section id="panel-evidence" class="panel" data-panel-content="evidence" hidden></section>
    <footer class="footer">この画面は表示用スナップショットを閲覧する資料です。仕様とテストケースの正本はリンク先の資料を参照してください。</footer>
  </main>
  <script type="application/json" id="quality-data">__QUALITY_DATA__</script>
  <script>
    (() => {
      'use strict';
      const data = JSON.parse(document.getElementById('quality-data').textContent);
      const byId = (items) => new Map((items || []).map((item) => [item.id, item]));
      const cases = data.testCases || [];
      const viewpoints = data.viewpoints || [];
      const findings = data.findings || [];
      const rootCauseDefinitions = data.rootCauses || [];
      const matchesRootCause = (item, definition) => item.executionStatus !== '成功' && item.layer === definition.match?.layer && String(item.executionNote || '').includes(definition.match?.executionNoteContains || '');
      const rootCauseGroups = rootCauseDefinitions.map((definition) => {
        const affectedCases = cases.filter((item) => matchesRootCause(item, definition));
        const hasFailure = affectedCases.some((item) => item.executionStatus === '失敗');
        return { ...definition, status: hasFailure ? 'NG' : '保留', caseIds: affectedCases.map((item) => item.id), impactCaseCount: affectedCases.length };
      }).filter((item) => item.impactCaseCount > 0);
      const rootCauseNamesForCases = (items) => [...new Set(items.flatMap((item) => rootCauseGroups.filter((rootCause) => rootCause.caseIds.includes(item.id)).map((rootCause) => rootCause.name)))];
      const deriveAcceptance = (acceptance) => {
        const relatedCases = (acceptance.testCaseIds || []).map((id) => cases.find((item) => item.id === id)).filter(Boolean);
        const failures = relatedCases.filter((item) => item.executionStatus === '失敗');
        const incomplete = relatedCases.filter((item) => item.executionStatus !== '成功');
        const rootCauseNames = rootCauseNamesForCases(incomplete);
        let confirmationStatus = '確認済み';
        let executionStatus = '完了';
        let blockingReason = '';
        if (failures.length > 0) {
          confirmationStatus = '実行失敗';
          executionStatus = '失敗';
          blockingReason = `必須ケースの失敗: ${failures.map((item) => item.id).join(', ')}`;
        } else if (incomplete.length > 0) {
          confirmationStatus = '未完了';
          executionStatus = '未完了';
          blockingReason = rootCauseNames.join('、') || '必須ケースが未実行';
        }
        return { ...acceptance, executionStatus, confirmationStatus, blockingReason };
      };
      const acceptanceStates = (data.acceptanceCriteria || []).map(deriveAcceptance);
      const acceptanceById = byId(acceptanceStates);
      const caseById = byId(cases);
      const implementationById = byId(data.testImplementations);
      const evidenceById = byId(data.evidence);
      const findingById = byId(data.findings);
      const evidenceWarnings = (data.evidence || []).filter((item) => item.available === false);
      const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (character) => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[character]));
      const list = (values) => (values || []).map(esc).join(', ') || '<span class="muted">なし</span>';
      const statusClass = (status) => ({ 'OK':'ok', '成功':'ok', '確認済み':'ok', '全件実行済み':'ok', '通過':'ok', '不足':'warn', '設計不足':'warn', '要補足':'warn', '対象外':'neutral', '未実行':'hold', '一部未実行':'hold', '未完了':'hold', '未生成':'hold', '保留':'hold', '失敗':'danger', '実行失敗':'danger', '失敗あり':'danger', 'NG':'danger', '未通過':'danger', '対応済み':'ok' }[status] || 'neutral');
      const badge = (status) => `<span class="badge ${statusClass(status)}">${esc(status)}</span>`;
      const link = (item) => item && item.available !== false && item.path ? `<a href="${esc(item.path)}">参照</a>` : '<span class="muted">未生成・未確認</span>';
      const idLinks = (ids, map) => (ids || []).map((id) => map.has(id) ? `<a href="#item-${esc(id)}">${esc(id)}</a>` : `<span class="badge danger">未紐付け:${esc(id)}</span>`).join(', ') || '<span class="muted">なし</span>';
      const qualityGates = (data.qualityGates || []).map((gate) => {
        const relatedCases = (gate.testCaseIds || []).map((id) => caseById.get(id)).filter(Boolean);
        const failures = relatedCases.filter((item) => item.executionStatus === '失敗');
        const incomplete = relatedCases.filter((item) => item.executionStatus !== '成功');
        const rootCauseNames = rootCauseNamesForCases(incomplete);
        const status = failures.length > 0 ? 'NG' : incomplete.length > 0 ? '未通過' : '通過';
        const reason = failures.length > 0 ? `必須ケースの失敗: ${failures.map((item) => item.id).join(', ')}` : incomplete.length > 0 ? (rootCauseNames.join('、') || '必須ケースが未実行') : '';
        return { ...gate, status, reason, impactCaseCount: incomplete.length };
      });
      const scopeExecutionFacts = (items) => {
        const total = items.length;
        const successCount = items.filter((item) => item.executionStatus === '成功').length;
        const failedCount = items.filter((item) => item.executionStatus === '失敗').length;
        const unexecutedCount = items.filter((item) => item.executionStatus === '未実行').length;
        const status = total === 0 ? '対象外' : failedCount > 0 ? '失敗あり' : unexecutedCount > 0 ? (successCount > 0 ? '一部未実行' : '未実行') : '全件実行済み';
        return { status, total, successCount, failedCount, unexecutedCount };
      };
      const frontendScopeFacts = scopeExecutionFacts(cases.filter((item) => item.layer.startsWith('Frontend') || item.layer === 'Static'));
      const backendScopeFacts = scopeExecutionFacts(cases.filter((item) => item.layer === 'Backend'));
      const oracleScopeFacts = scopeExecutionFacts(cases.filter((item) => item.layer === 'Oracle'));
      const featureExecutionFacts = scopeExecutionFacts(cases);
      const automatedFindings = data.automatedFindings || [];
      const gapRank = (item) => ({ '失敗': 1, 'ブロッカー': 2, '品質ゲート': 3, '未通過分岐': 4, 'カバレッジ': 4, '受入条件未対応': 5, '実テスト未紐付け': 5, '証跡未紐付け': 5, '未実行': 6, '指摘・保留': 7 }[item.category] || 9);
      const orderedGaps = automatedFindings.map((item, index) => ({ ...item, order: index })).sort((left, right) => gapRank(left) - gapRank(right) || left.order - right.order);
      const targetIds = new Set([
        ...acceptanceStates.map((item) => item.id),
        ...cases.map((item) => item.id),
        ...viewpoints.map((item) => item.id),
        ...findings.map((item) => item.id),
        ...qualityGates.map((item) => item.id),
        ...rootCauseGroups.map((item) => item.id),
        'COV-FRONTEND',
        'COV-BACKEND',
        ...['frontend', 'backend'].flatMap((layer) => (data.coverage[layer].uncoveredBranches || []).map((item) => item.id))
      ]);
      const targetLink = (id) => targetIds.has(id) ? `<a href="#item-${esc(id)}">${esc(id)}</a>` : `<span class="muted">${esc(id)}</span>`;

      document.title = data.feature.title;
      document.getElementById('scope').textContent = `${data.feature.id} / ${data.feature.screenId} / ${data.feature.scope.join('・')}`;
      document.getElementById('meta').innerHTML = `モード: ${esc(data.feature.reviewMode)}<br>スナップショット: ${esc(data.feature.snapshot.capturedOn)}<br>対象コミット: ${esc(data.feature.snapshot.sourceCommit)}<br>生成コミット: ${esc(data.feature.generatedCommit || '生成時に取得')}`;

      const summaryItems = [
        ['実行状況', featureExecutionFacts.status, `成功 ${featureExecutionFacts.successCount}件 / 未実行 ${featureExecutionFacts.unexecutedCount}件 / 失敗 ${featureExecutionFacts.failedCount}件`],
        ['根本原因', rootCauseGroups.length, '概要は原因単位'],
        ['影響ケース', rootCauseGroups.reduce((total, item) => total + item.impactCaseCount, 0), '根本原因に紐付く件数'],
        ['品質ゲート', `${qualityGates.filter((item) => item.status === '通過').length}/${qualityGates.length}`, '通過数 / 全ゲート数'],
        ['受入条件', acceptanceStates.length, '実行状態・確認状況を事実表示'],
        ['テストケース', cases.length, 'Backend・Oracle・Frontend・Static'],
        ['実テスト', (data.testImplementations || []).length, '実装参照'],
        ['観点一覧', viewpoints.length, '入力された観点件数（判定は自動評価しない）'],
        ['確認項目', orderedGaps.length, '優先順位付き']
      ];
      document.getElementById('summary').innerHTML = summaryItems.map(([label, value, note]) => `<article class="card"><div class="label">${esc(label)}</div><div class="value">${esc(value)}</div><div class="note">${esc(note)}</div></article>`).join('');

      const renderScopeFacts = (label, facts) => `<div><strong>${esc(label)}</strong><br>${badge(facts.status)}<br><span class="muted">成功 ${esc(facts.successCount)} / 未実行 ${esc(facts.unexecutedCount)} / 失敗 ${esc(facts.failedCount)}</span></div>`;

      const renderCase = (item) => {
        const implementations = (item.testImplementationIds || []).map((id) => implementationById.get(id)).filter(Boolean);
        const evidence = (item.evidenceIds || []).map((id) => evidenceById.get(id)).filter(Boolean);
        const findingsForCase = (item.findingIds || []).map((id) => findingById.get(id)).filter(Boolean);
        return `<details class="case" id="item-${esc(item.id)}"><summary>${esc(item.id)} ${esc(item.name)} ${badge(item.executionStatus)}</summary><div class="case-body"><div class="case-field"><strong>目的</strong>${esc(item.purpose)}</div><div class="case-field"><strong>前提</strong>${esc(item.precondition)}</div><div class="case-field"><strong>操作</strong>${esc(item.action)}</div><div class="case-field"><strong>期待結果</strong>${esc(item.expected)}</div><div class="case-field"><strong>レビュー記録（入力）</strong>${badge(item.reviewStatus)}</div><div class="case-field"><strong>受入条件</strong>${idLinks(item.acceptanceCriteriaIds, acceptanceById)}</div><div class="case-field"><strong>実テスト</strong>${implementations.map((impl) => `<a href="${esc(impl.file)}">${esc(impl.name)}</a>`).join('<br>') || '<span class="muted">未紐付け</span>'}</div><div class="case-field"><strong>証跡</strong>${evidence.map((entry) => `${link(entry)} ${esc(entry.type)}`).join('<br>') || '<span class="muted">未紐付け</span>'}</div><div class="case-field"><strong>指摘・補足（入力）</strong>${findingsForCase.map((finding) => `${badge(finding.status)} ${esc(finding.summary)}`).join('<br>') || '<span class="muted">なし</span>'}</div></div>${item.executionNote ? `<div class="callout warn small">${esc(item.executionNote)}</div>` : ''}</details>`;
      };

      const overviewTone = featureExecutionFacts.status === '失敗あり' ? 'danger' : featureExecutionFacts.unexecutedCount > 0 ? 'warn' : '';
      document.getElementById('panel-overview').innerHTML = `<h2>概要</h2><div id="execution-summary" class="callout ${overviewTone}"><h3>実行状況: ${badge(featureExecutionFacts.status)}</h3><p>成功 ${esc(featureExecutionFacts.successCount)}件 / 未実行 ${esc(featureExecutionFacts.unexecutedCount)}件 / 失敗 ${esc(featureExecutionFacts.failedCount)}件</p><div class="assessment-grid">${renderScopeFacts('Frontend実行状況', frontendScopeFacts)}${renderScopeFacts('Backend実行状況', backendScopeFacts)}${renderScopeFacts('Oracle実行状況', oracleScopeFacts)}</div></div><div class="callout">${esc(data.feature.snapshot.description)}</div><div class="callout"><strong>表示方針</strong><br>品質の自動評価は表示せず、実行結果・品質ゲート・証跡・カバレッジを個別に表示しています。</div>${evidenceWarnings.length > 0 ? `<div class="callout warn"><strong>証跡警告</strong><br>${evidenceWarnings.map((item) => `${esc(item.id)}: ファイル未生成・未確認`).join('<br>')}</div>` : '<div class="callout"><strong>証跡状態</strong><br>ファイル存在を生成時に確認。実行情報は取得できた項目だけを表示しています。</div>'}<h3>品質ゲート</h3>${qualityGates.map((gate) => `<div id="item-${esc(gate.id)}" class="callout ${gate.status === 'NG' ? 'danger' : gate.status === '通過' ? '' : 'warn'}">${badge(gate.status)} <strong>${esc(gate.id)} ${esc(gate.name)}</strong><br>${esc(gate.reason || '判定理由なし')}<br>影響ケース: ${esc(gate.impactCaseCount)}件</div>`).join('') || '<div class="empty">品質ゲートはありません。</div>'}<h3>根本原因</h3>${rootCauseGroups.map((rootCause) => `<div id="item-${esc(rootCause.id)}" class="callout warn"><strong>${esc(rootCause.name)}</strong> ${badge(rootCause.status)}<br>原因: ${esc(rootCause.reason)}<br>影響ケース: ${esc(rootCause.impactCaseCount)}件</div>`).join('') || '<div class="empty">根本原因はありません。</div>'}<h3>カバレッジ詳細</h3><div id="item-COV-FRONTEND" class="callout"><strong>Frontend</strong> ${badge(data.coverage.frontend.status)}<br>Branches: ${esc(data.coverage.frontend.metrics.branches)}%</div><div id="item-COV-BACKEND" class="callout ${data.coverage.backend.status === '通過' ? '' : 'warn'}"><strong>Backend</strong> ${badge(data.coverage.backend.status)}<br>Branches: ${esc(data.coverage.backend.metrics.branch)}%<br>${esc(data.coverage.backend.reason || '')}${(data.coverage.backend.uncoveredBranches || []).map((branch) => `<div id="item-${esc(branch.id)}" class="callout danger small">${esc(branch.file)}: ${esc(branch.text)}</div>`).join('')}</div><h3>取得済みメトリクス</h3><div class="grid summary"><article class="card"><div class="label">Frontend coverage</div><div class="value">${badge(data.coverage.frontend.status)}</div><div class="note">Branches ${esc(data.coverage.frontend.metrics.branches)}%</div></article><article class="card"><div class="label">Backend coverage</div><div class="value">${badge(data.coverage.backend.status)}</div><div class="note">${data.coverage.backend.status === '未生成' ? '未生成のため数値なし' : '未通過分岐を抽出表示'}</div></article><article class="card"><div class="label">根本原因 / 影響ケース</div><div class="value">${esc(rootCauseGroups.length)} / ${esc(rootCauseGroups.reduce((total, item) => total + item.impactCaseCount, 0))}</div><div class="note">ケース単位ではなく原因単位</div></article></div><h3>優先順位付きの主な確認事項</h3>${orderedGaps.slice(0, 8).map((item) => `<div class="callout ${item.status === '失敗' || item.status === 'NG' || item.status === '未通過' ? 'danger' : 'warn'}">${badge(item.status)} <strong>${esc(item.category)} ${esc(item.id)}</strong><br>${esc(item.text)}</div>`).join('') || '<div class="empty">確認事項はありません。</div>'}`;

      const traceRows = acceptanceStates.map((ac) => `<tr id="item-${esc(ac.id)}"><td><strong>${esc(ac.id)}</strong><br>${esc(ac.text)}<br><span class="muted">実行状態</span> ${badge(ac.executionStatus)}<br><span class="muted">確認状況</span> ${badge(ac.confirmationStatus)}<br><span class="muted">理由</span> ${esc(ac.blockingReason || 'なし')}</td><td>${idLinks(ac.testCaseIds, caseById)}</td><td>${(ac.testCaseIds || []).map((id) => caseById.get(id)).filter(Boolean).map((item) => `${esc(item.layer)} ${badge(item.executionStatus)}`).join('<br>') || '<span class="muted">未対応</span>'}</td></tr>`).join('');
      document.getElementById('panel-traceability').innerHTML = `<h2>受入条件・追跡</h2><div class="filter"><input id="trace-search" type="search" placeholder="ID・内容で検索" aria-label="受入条件検索"><select id="trace-status" aria-label="実行結果フィルター"><option value="">全実行結果</option><option>成功</option><option>未実行</option><option>失敗</option></select></div><div class="table-wrap"><table><thead><tr><th>受入条件（実行・確認）</th><th>テストケース</th><th>ケース実行結果</th></tr></thead><tbody id="trace-rows">${traceRows}</tbody></table></div><h3>ケース詳細</h3><div id="case-list" class="case-list">${cases.map(renderCase).join('')}</div>`;
      const applyTraceFilter = () => {
        const query = document.getElementById('trace-search').value.toLowerCase();
        const status = document.getElementById('trace-status').value;
        document.querySelectorAll('#case-list details.case').forEach((element) => {
          const item = caseById.get(element.id.replace('item-', ''));
          const visible = item && (!query || JSON.stringify(item).toLowerCase().includes(query)) && (!status || item.executionStatus === status);
          element.hidden = !visible;
        });
        document.querySelectorAll('#trace-rows tr').forEach((row) => {
          const acceptance = acceptanceById.get(row.id.replace('item-', ''));
          const relatedCases = (acceptance?.testCaseIds || []).map((id) => caseById.get(id)).filter(Boolean);
          const visible = acceptance && (!query || row.textContent.toLowerCase().includes(query)) && (!status || relatedCases.some((item) => item.executionStatus === status));
          row.hidden = !visible;
        });
      };
      document.getElementById('trace-search').addEventListener('input', applyTraceFilter);
      document.getElementById('trace-status').addEventListener('change', applyTraceFilter);

      const viewpointRows = viewpoints.map((item) => `<tr id="item-${esc(item.id)}"><td><strong>${esc(item.id)}</strong><br>${esc(item.name)}</td><td>${esc(item.description)}</td><td>${badge(item.reviewStatus)}</td><td>${idLinks(item.caseIds, caseById)}</td><td>${(item.findingIds || []).map((id) => findingById.get(id)).filter(Boolean).map((finding) => `${badge(finding.status)} ${esc(finding.summary)}`).join('<br>') || '<span class="muted">なし</span>'}</td></tr>`).join('');
      document.getElementById('panel-viewpoints').innerHTML = `<h2>観点一覧</h2><div class="filter"><input id="viewpoint-search" type="search" placeholder="観点・内容で検索" aria-label="観点検索"><select id="viewpoint-status" aria-label="レビュー記録フィルター"><option value="">全レビュー記録</option><option>OK</option><option>不足</option><option>対象外</option><option>保留</option></select></div><div class="table-wrap"><table><thead><tr><th>観点</th><th>確認内容</th><th>レビュー記録（入力）</th><th>根拠ケース</th><th>関連指摘</th></tr></thead><tbody id="viewpoint-rows">${viewpointRows}</tbody></table></div>`;
      const applyViewpointFilter = () => { const query = document.getElementById('viewpoint-search').value.toLowerCase(); const status = document.getElementById('viewpoint-status').value; document.querySelectorAll('#viewpoint-rows tr').forEach((row) => { const item = viewpoints.find((candidate) => candidate.id === row.id.replace('item-', '')); row.hidden = !item || (query && !JSON.stringify(item).toLowerCase().includes(query)) || (status && item.reviewStatus !== status); }); };
      document.getElementById('viewpoint-search').addEventListener('input', applyViewpointFilter);
      document.getElementById('viewpoint-status').addEventListener('change', applyViewpointFilter);

      document.getElementById('panel-gaps').innerHTML = `<h2>機械検証結果</h2><p class="muted">JSONの構造、ID、紐付け、実行結果、品質ゲート、カバレッジ、明示された保留だけを表示しています。レビュー状態や意味評価は自動判定していません。</p><div class="table-wrap"><table><thead><tr><th>分類</th><th>ID</th><th>内容</th><th>状態</th></tr></thead><tbody>${orderedGaps.map((item) => `<tr><td>${esc(item.category)}</td><td>${targetLink(item.id)}</td><td>${esc(item.text)}</td><td>${badge(item.status)}</td></tr>`).join('') || '<tr><td colspan="4" class="empty">機械検証上の確認事項はありません。</td></tr>'}</tbody></table></div>`;

      const displayNullable = (value) => value === null || value === undefined || value === '' ? '未取得' : String(value);
      const executionForEvidence = (evidence) => {
        const implementations = cases.filter((item) => (item.evidenceIds || []).includes(evidence.id)).flatMap((item) => (item.testImplementationIds || []).map((id) => implementationById.get(id)).filter(Boolean));
        const statuses = [...new Set(implementations.map((item) => item.executionStatus))];
        const status = statuses.includes('失敗') ? '失敗' : statuses.includes('未実行') && statuses.includes('成功') ? '混在' : statuses.includes('未実行') ? '未実行' : statuses.includes('成功') ? '成功' : '未取得';
        const commands = [...new Set(implementations.map((item) => item.runCommand).filter(Boolean))];
        return { status, command: commands.join(' / ') || null };
      };
      const evidenceRows = (data.evidence || []).map((item) => { const info = item.executionInfo || {}; const execution = executionForEvidence(item); return `<tr><td>${esc(item.id)}</td><td>${esc(item.type)}</td><td>${link(item)}</td><td>${esc(item.note)}</td><td>${badge(execution.status)}</td><td>${esc(displayNullable(info.command || execution.command))}</td><td>${esc(displayNullable(info.reportGeneratedAt))}</td></tr>`; }).join('');
      const sourceRows = (data.sources || []).map((item) => `<tr><td>${esc(item.id)}</td><td>${esc(item.name)}</td><td><a href="${esc(item.path)}">参照</a></td><td>${esc(item.section)}</td></tr>`).join('');
      const findingRows = findings.map((item) => `<tr id="item-${esc(item.id)}"><td>${esc(item.id)}</td><td>${esc(item.priority)}</td><td>${badge(item.status)}</td><td>${esc(item.summary)}</td><td>${esc(item.action)}</td></tr>`).join('');
      document.getElementById('panel-evidence').innerHTML = `<h2>証跡・ソース</h2><h3>証跡</h3><div class="table-wrap"><table><thead><tr><th>ID</th><th>種別</th><th>リンク</th><th>備考</th><th>実行結果</th><th>コマンド</th><th>レポート生成日時</th></tr></thead><tbody>${evidenceRows}</tbody></table></div><h3>指摘一覧</h3><div class="table-wrap"><table><thead><tr><th>ID</th><th>優先度</th><th>状態</th><th>概要</th><th>対応</th></tr></thead><tbody>${findingRows}</tbody></table></div><h3>正本・参照資料</h3><div class="table-wrap"><table><thead><tr><th>ID</th><th>資料</th><th>リンク</th><th>参照節</th></tr></thead><tbody>${sourceRows}</tbody></table></div>`;

      const showPanel = (panelName) => { document.querySelectorAll('.nav button').forEach((button) => button.classList.toggle('active', button.dataset.panel === panelName)); document.querySelectorAll('[data-panel-content]').forEach((panel) => { panel.hidden = panel.dataset.panelContent !== panelName; }); };
      const focusTarget = (id) => { const target = document.getElementById(`item-${id}`); if (!target) return false; const panel = target.closest('[data-panel-content]'); if (panel) showPanel(panel.dataset.panelContent); if (target.tagName === 'DETAILS') target.open = true; target.classList.remove('target-flash'); void target.offsetWidth; target.classList.add('target-flash'); target.scrollIntoView({ block: 'center' }); window.setTimeout(() => target.classList.remove('target-flash'), 1800); return true; };
      document.querySelectorAll('.nav button').forEach((button) => button.addEventListener('click', () => showPanel(button.dataset.panel)));
      document.addEventListener('click', (event) => { const anchor = event.target.closest('a[href^="#item-"]'); if (!anchor) return; const id = decodeURIComponent(anchor.getAttribute('href').slice('#item-'.length)); if (focusTarget(id)) event.preventDefault(); });
      if (window.location.hash.startsWith('#item-')) focusTarget(decodeURIComponent(window.location.hash.slice('#item-'.length)));
    })();
  </script>
</body>
</html>
'@
}

$data = Read-QualityData
Test-QualityData -Data $data | Out-Null
Write-Output "Validated quality data: $DataPath"

if ($ValidateOnly) {
    exit 0
}

$data.feature | Add-Member -NotePropertyName generatedAt -NotePropertyValue (Get-Date).ToString('o') -Force
$generatedCommit = Get-GeneratedCommit
$data.feature | Add-Member -NotePropertyName generatedCommit -NotePropertyValue $generatedCommit -Force
$data | Add-Member -NotePropertyName automatedFindings -NotePropertyValue @(Get-AutomatedFindings -Data $data) -Force
Update-EvidenceMetadata -Data $data -CurrentCommit $generatedCommit
$embeddedJson = Get-EmbeddedJson -Data $data
$html = (Get-HtmlTemplate).Replace('__TITLE__', [System.Net.WebUtility]::HtmlEncode([string]$data.feature.title)).Replace('__QUALITY_DATA__', $embeddedJson)
$encoding = [System.Text.UTF8Encoding]::new($false)
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $outputFullPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
[System.IO.File]::WriteAllText($outputFullPath, $html, $encoding)
Write-Output "Generated quality report: $OutputPath"
