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

    $feature = Get-RequiredProperty -Object $Data -Name 'feature' -Context 'root data'
    foreach ($name in @('id', 'name', 'screenId', 'title', 'scope', 'reviewMode', 'snapshot')) {
        Get-RequiredProperty -Object $feature -Name $name -Context 'feature' | Out-Null
    }

    $acceptanceCriteria = Get-Items -Object $Data -Name 'acceptanceCriteria'
    $testCases = Get-Items -Object $Data -Name 'testCases'
    $viewpoints = Get-Items -Object $Data -Name 'viewpoints'
    $testImplementations = Get-Items -Object $Data -Name 'testImplementations'
    $evidence = Get-Items -Object $Data -Name 'evidence'
    $findings = Get-Items -Object $Data -Name 'findings'
    $sources = Get-Items -Object $Data -Name 'sources'
    $coverage = Get-RequiredProperty -Object $Data -Name 'coverage' -Context 'root data'

    $collections = @{
        acceptanceCriteria = $acceptanceCriteria
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

    $acceptanceIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($acceptanceCriteria.id))
    $caseIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($testCases.id))
    $implementationIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($testImplementations.id))
    $evidenceIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($evidence.id))
    $findingIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($findings.id))

    Assert-References -Items $acceptanceCriteria -CollectionName 'acceptanceCriteria' -ReferenceProperty 'testCaseIds' -KnownIds $caseIds
    Assert-References -Items $testCases -CollectionName 'testCases' -ReferenceProperty 'acceptanceCriteriaIds' -KnownIds $acceptanceIds
    Assert-References -Items $testCases -CollectionName 'testCases' -ReferenceProperty 'testImplementationIds' -KnownIds $implementationIds
    Assert-References -Items $testCases -CollectionName 'testCases' -ReferenceProperty 'evidenceIds' -KnownIds $evidenceIds
    Assert-References -Items $testCases -CollectionName 'testCases' -ReferenceProperty 'findingIds' -KnownIds $findingIds
    Assert-References -Items $viewpoints -CollectionName 'viewpoints' -ReferenceProperty 'caseIds' -KnownIds $caseIds
    Assert-References -Items $viewpoints -CollectionName 'viewpoints' -ReferenceProperty 'findingIds' -KnownIds $findingIds

    Assert-AllowedStatus -Items $acceptanceCriteria -CollectionName 'acceptanceCriteria' -PropertyName 'reviewStatus' -Allowed @('OK', '不足', '対象外', '保留')
    Assert-AllowedStatus -Items $testCases -CollectionName 'testCases' -PropertyName 'reviewStatus' -Allowed @('OK', '不足', '対象外', '保留')
    Assert-AllowedStatus -Items $testCases -CollectionName 'testCases' -PropertyName 'executionStatus' -Allowed @('成功', '失敗', '未実行')
    Assert-AllowedStatus -Items $viewpoints -CollectionName 'viewpoints' -PropertyName 'reviewStatus' -Allowed @('OK', '不足', '対象外', '保留')

    foreach ($layer in @('frontend', 'backend')) {
        $coverageItem = Get-RequiredProperty -Object $coverage -Name $layer -Context 'coverage'
        $status = [string](Get-RequiredProperty -Object $coverageItem -Name 'status' -Context "coverage $layer")
        if (@('通過', '未通過', '未生成', '対象外') -notcontains $status) {
            Throw-ValidationError "coverage $layer has invalid status '$status'."
        }
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
      <button type="button" data-panel="gaps">不足・保留</button>
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
      const acceptanceById = byId(data.acceptanceCriteria);
      const caseById = byId(data.testCases);
      const implementationById = byId(data.testImplementations);
      const evidenceById = byId(data.evidence);
      const findingById = byId(data.findings);
      const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (character) => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[character]));
      const list = (values) => (values || []).map(esc).join(', ') || '<span class="muted">なし</span>';
      const statusClass = (status) => ({ 'OK':'ok', '成功':'ok', '通過':'ok', '不足':'warn', '要補足':'warn', '対象外':'neutral', '未実行':'hold', '未生成':'hold', '保留':'hold', '失敗':'danger', '未通過':'danger', '対応済み':'ok' }[status] || 'neutral');
      const badge = (status) => `<span class="badge ${statusClass(status)}">${esc(status)}</span>`;
      const link = (item) => item && item.available !== false && item.path ? `<a href="${esc(item.path)}">参照</a>` : '<span class="muted">未生成・未確認</span>';
      const idLinks = (ids, map) => (ids || []).map((id) => map.has(id) ? `<a href="#item-${esc(id)}">${esc(id)}</a>` : `<span class="badge danger">未紐付け:${esc(id)}</span>`).join(', ') || '<span class="muted">なし</span>';
      const count = (items, predicate) => (items || []).filter(predicate).length;
      const cases = data.testCases || [];
      const viewpoints = data.viewpoints || [];
      const findings = data.findings || [];
      const gaps = [];
      (data.acceptanceCriteria || []).forEach((item) => { if (!item.testCaseIds || item.testCaseIds.length === 0) gaps.push({ category:'受入条件未対応', id:item.id, text:item.text, status:'不足' }); });
      cases.forEach((item) => {
        if (!item.testImplementationIds || item.testImplementationIds.length === 0) gaps.push({ category:'実テスト未紐付け', id:item.id, text:item.name, status:'不足' });
        if (!item.evidenceIds || item.evidenceIds.length === 0) gaps.push({ category:'証跡未紐付け', id:item.id, text:item.name, status:'不足' });
        if (item.reviewStatus === '不足') gaps.push({ category:'期待結果・レビュー不足', id:item.id, text:item.expected, status:item.reviewStatus });
        if (item.executionStatus !== '成功') gaps.push({ category:'実行未完了', id:item.id, text:item.executionNote || item.name, status:item.executionStatus });
      });
      viewpoints.filter((item) => item.reviewStatus !== 'OK').forEach((item) => gaps.push({ category:'観点判定', id:item.id, text:item.description, status:item.reviewStatus }));
      ['frontend', 'backend'].forEach((layer) => { const item = data.coverage[layer]; if (item.status !== '通過') gaps.push({ category:'カバレッジ', id:`COV-${layer.toUpperCase()}`, text:item.reason || `${layer} coverage`, status:item.status }); (item.uncoveredBranches || []).forEach((branch) => gaps.push({ category:'未通過分岐', id:branch.id, text:branch.text, status:'未通過' })); });
      findings.filter((item) => ['保留', '要補足'].includes(item.status)).forEach((item) => gaps.push({ category:'指摘・保留', id:item.id, text:item.summary, status:item.status }));

      document.title = data.feature.title;
      document.getElementById('scope').textContent = `${data.feature.id} / ${data.feature.screenId} / ${data.feature.scope.join('・')}`;
      document.getElementById('meta').innerHTML = `モード: ${esc(data.feature.reviewMode)}<br>スナップショット: ${esc(data.feature.snapshot.capturedOn)}<br>対象コミット: ${esc(data.feature.snapshot.sourceCommit)}<br>生成コミット: ${esc(data.feature.generatedCommit || '生成時に取得')}`;

      const summaryItems = [
        ['受入条件', data.acceptanceCriteria.length, '6件'],
        ['テストケース', cases.length, 'Backend・Oracle・Frontend・Static'],
        ['実テスト', (data.testImplementations || []).length, '実装参照'],
        ['観点不足', count(viewpoints, (item) => item.reviewStatus !== 'OK'), '不足・保留・対象外'],
        ['未実行・失敗', count(cases, (item) => item.executionStatus !== '成功'), 'Backend・Oracleを含む'],
        ['抽出項目', gaps.length, '確認が必要な項目']
      ];
      document.getElementById('summary').innerHTML = summaryItems.map(([label, value, note]) => `<article class="card"><div class="label">${esc(label)}</div><div class="value">${esc(value)}</div><div class="note">${esc(note)}</div></article>`).join('');

      const renderCase = (item) => {
        const implementations = (item.testImplementationIds || []).map((id) => implementationById.get(id)).filter(Boolean);
        const evidence = (item.evidenceIds || []).map((id) => evidenceById.get(id)).filter(Boolean);
        const findingsForCase = (item.findingIds || []).map((id) => findingById.get(id)).filter(Boolean);
        return `<details class="case" id="item-${esc(item.id)}"><summary>${esc(item.id)} ${esc(item.name)} ${badge(item.reviewStatus)} ${badge(item.executionStatus)}</summary><div class="case-body"><div class="case-field"><strong>目的</strong>${esc(item.purpose)}</div><div class="case-field"><strong>前提</strong>${esc(item.precondition)}</div><div class="case-field"><strong>操作</strong>${esc(item.action)}</div><div class="case-field"><strong>期待結果</strong>${esc(item.expected)}</div><div class="case-field"><strong>受入条件</strong>${idLinks(item.acceptanceCriteriaIds, acceptanceById)}</div><div class="case-field"><strong>実テスト</strong>${implementations.map((impl) => `<a href="${esc(impl.file)}">${esc(impl.name)}</a>`).join('<br>') || '<span class="muted">未紐付け</span>'}</div><div class="case-field"><strong>証跡</strong>${evidence.map((entry) => `${link(entry)} ${esc(entry.type)}`).join('<br>') || '<span class="muted">未紐付け</span>'}</div><div class="case-field"><strong>指摘・補足</strong>${findingsForCase.map((finding) => `${badge(finding.status)} ${esc(finding.summary)}`).join('<br>') || '<span class="muted">なし</span>'}</div></div>${item.executionNote ? `<div class="callout warn small">${esc(item.executionNote)}</div>` : ''}</details>`;
      };

      document.getElementById('panel-overview').innerHTML = `<h2>概要</h2><div class="callout">${esc(data.feature.snapshot.description)}</div><h3>現在の確認状態</h3><div class="grid summary"><article class="card"><div class="label">Frontend coverage</div><div class="value">${badge(data.coverage.frontend.status)}</div><div class="note">Branches ${esc(data.coverage.frontend.metrics.branches)}%</div></article><article class="card"><div class="label">Backend coverage</div><div class="value">${badge(data.coverage.backend.status)}</div><div class="note">${data.coverage.backend.status === '未生成' ? '未生成は未通過と判定しない' : '未通過分岐を抽出表示'}</div></article><article class="card"><div class="label">最優先確認</div><div class="value">${esc(gaps.filter((item) => item.status === '未実行' || item.status === '保留').length)}</div><div class="note">Oracle・Backendを含む</div></article></div><h3>主な未完了事項</h3>${gaps.slice(0, 8).map((item) => `<div class="callout ${item.status === '失敗' || item.status === '未通過' ? 'danger' : 'warn'}">${badge(item.status)} <strong>${esc(item.category)} ${esc(item.id)}</strong><br>${esc(item.text)}</div>`).join('') || '<div class="empty">未完了事項はありません。</div>'}`;

      const traceRows = (data.acceptanceCriteria || []).map((ac) => `<tr id="item-${esc(ac.id)}"><td><strong>${esc(ac.id)}</strong><br>${esc(ac.text)}<br>${badge(ac.reviewStatus)}</td><td>${idLinks(ac.testCaseIds, caseById)}</td><td>${(ac.testCaseIds || []).map((id) => caseById.get(id)).filter(Boolean).map((item) => `${esc(item.layer)} ${badge(item.executionStatus)}`).join('<br>') || '<span class="muted">未対応</span>'}</td></tr>`).join('');
      document.getElementById('panel-traceability').innerHTML = `<h2>受入条件・追跡</h2><div class="filter"><input id="trace-search" type="search" placeholder="ID・内容で検索" aria-label="受入条件検索"><select id="trace-status" aria-label="実行結果フィルター"><option value="">全実行結果</option><option>成功</option><option>未実行</option><option>失敗</option></select></div><div class="table-wrap"><table><thead><tr><th>受入条件</th><th>テストケース</th><th>実テスト結果</th></tr></thead><tbody id="trace-rows">${traceRows}</tbody></table></div><h3>ケース詳細</h3><div id="case-list" class="case-list">${cases.map(renderCase).join('')}</div>`;
      const applyTraceFilter = () => { const query = document.getElementById('trace-search').value.toLowerCase(); const status = document.getElementById('trace-status').value; document.querySelectorAll('#case-list details.case').forEach((element) => { const item = caseById.get(element.id.replace('item-', '')); const visible = item && (!query || JSON.stringify(item).toLowerCase().includes(query)) && (!status || item.executionStatus === status); element.hidden = !visible; }); document.querySelectorAll('#trace-rows tr').forEach((row) => { row.hidden = query && !row.textContent.toLowerCase().includes(query); }); };
      document.getElementById('trace-search').addEventListener('input', applyTraceFilter);
      document.getElementById('trace-status').addEventListener('change', applyTraceFilter);

      const viewpointRows = viewpoints.map((item) => `<tr id="item-${esc(item.id)}"><td><strong>${esc(item.id)}</strong><br>${esc(item.name)}</td><td>${esc(item.description)}</td><td>${badge(item.reviewStatus)}</td><td>${idLinks(item.caseIds, caseById)}</td><td>${(item.findingIds || []).map((id) => findingById.get(id)).filter(Boolean).map((finding) => `${badge(finding.status)} ${esc(finding.summary)}`).join('<br>') || '<span class="muted">なし</span>'}</td></tr>`).join('');
      document.getElementById('panel-viewpoints').innerHTML = `<h2>観点一覧</h2><div class="filter"><input id="viewpoint-search" type="search" placeholder="観点・内容で検索" aria-label="観点検索"><select id="viewpoint-status" aria-label="観点判定フィルター"><option value="">全判定</option><option>OK</option><option>不足</option><option>対象外</option><option>保留</option></select></div><div class="table-wrap"><table><thead><tr><th>観点</th><th>確認内容</th><th>判定</th><th>根拠ケース</th><th>関連指摘</th></tr></thead><tbody id="viewpoint-rows">${viewpointRows}</tbody></table></div>`;
      const applyViewpointFilter = () => { const query = document.getElementById('viewpoint-search').value.toLowerCase(); const status = document.getElementById('viewpoint-status').value; document.querySelectorAll('#viewpoint-rows tr').forEach((row) => { const item = viewpoints.find((candidate) => candidate.id === row.id.replace('item-', '')); row.hidden = !item || (query && !JSON.stringify(item).toLowerCase().includes(query)) || (status && item.reviewStatus !== status); }); };
      document.getElementById('viewpoint-search').addEventListener('input', applyViewpointFilter);
      document.getElementById('viewpoint-status').addEventListener('change', applyViewpointFilter);

      document.getElementById('panel-gaps').innerHTML = `<h2>不足・保留</h2><p class="muted">未生成は未通過分岐と区別して表示しています。</p><div class="table-wrap"><table><thead><tr><th>分類</th><th>ID</th><th>内容</th><th>状態</th></tr></thead><tbody>${gaps.map((item) => `<tr><td>${esc(item.category)}</td><td><a href="#item-${esc(item.id)}">${esc(item.id)}</a></td><td>${esc(item.text)}</td><td>${badge(item.status)}</td></tr>`).join('') || '<tr><td colspan="4" class="empty">不足・保留はありません。</td></tr>'}</tbody></table></div>`;

      const evidenceRows = (data.evidence || []).map((item) => `<tr><td>${esc(item.id)}</td><td>${esc(item.type)}</td><td>${link(item)}</td><td>${esc(item.note)}</td></tr>`).join('');
      const sourceRows = (data.sources || []).map((item) => `<tr><td>${esc(item.id)}</td><td>${esc(item.name)}</td><td><a href="${esc(item.path)}">参照</a></td><td>${esc(item.section)}</td></tr>`).join('');
      document.getElementById('panel-evidence').innerHTML = `<h2>証跡・ソース</h2><h3>証跡</h3><div class="table-wrap"><table><thead><tr><th>ID</th><th>種別</th><th>リンク</th><th>備考</th></tr></thead><tbody>${evidenceRows}</tbody></table></div><h3>正本・参照資料</h3><div class="table-wrap"><table><thead><tr><th>ID</th><th>資料</th><th>リンク</th><th>参照節</th></tr></thead><tbody>${sourceRows}</tbody></table></div>`;

      document.querySelectorAll('.nav button').forEach((button) => button.addEventListener('click', () => { document.querySelectorAll('.nav button').forEach((candidate) => candidate.classList.toggle('active', candidate === button)); document.querySelectorAll('[data-panel-content]').forEach((panel) => { panel.hidden = panel.dataset.panelContent !== button.dataset.panel; }); }));
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
$data.feature | Add-Member -NotePropertyName generatedCommit -NotePropertyValue (Get-GeneratedCommit) -Force
$embeddedJson = Get-EmbeddedJson -Data $data
$html = (Get-HtmlTemplate).Replace('__TITLE__', [System.Net.WebUtility]::HtmlEncode([string]$data.feature.title)).Replace('__QUALITY_DATA__', $embeddedJson)
$encoding = [System.Text.UTF8Encoding]::new($false)
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $outputFullPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
[System.IO.File]::WriteAllText($outputFullPath, $html, $encoding)
Write-Output "Generated quality report: $OutputPath"
