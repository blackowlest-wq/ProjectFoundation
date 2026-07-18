[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet('Quick', 'PrePush', 'Full', 'Oracle', 'All')]
    [string]$Mode = 'Quick',
    [string]$PushInput,
    [switch]$Offline,
    [ValidateSet('None', 'FrontendCoverage', 'BackendCoverage', 'BackendUnit', 'E2E', 'E2EOracle', 'DirectorySecrets', 'DependencyAudit')]
    [string]$CiTask = 'None',
    [switch]$AllowDdl,
    [string]$DdlScript,
    [string]$OracleConfigPath
)

$ErrorActionPreference = 'Stop'
$isWindowsHost = if ($null -ne (Get-Variable IsWindows -ErrorAction SilentlyContinue)) { [bool]$IsWindows } else { $env:OS -eq 'Windows_NT' }

function New-CheckDefinition {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$Command,
        [object[]]$Arguments = @(),
        [scriptblock]$Action
    )

    $definition = [ordered]@{
        Name = $Name
        Action = $Action
    }
    if ($PSBoundParameters.ContainsKey('Command')) {
        $definition.Command = $Command
        $definition.Arguments = @($Arguments)
    }

    [pscustomobject]$definition
}

function New-CoverageReportCheckDefinition {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string[]]$Paths)

    New-CheckDefinition -Name $Name -Action {
        $missing = @($Paths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
        if ($missing.Count -gt 0) { throw "Coverage reports are missing: $($missing -join ', ')" }
        Write-Host 'Coverage reports:'
        $Paths | ForEach-Object { Write-Host " - $_" }
    }.GetNewClosure()
}

function Get-MavenArguments {
    param(
        [switch]$Offline,
        [Parameter(Mandatory)]
        [string[]]$Goals
    )

    $arguments = @('-f', 'backend/pom.xml', '-s', 'backend/local-maven-settings.xml', '-B')
    if ($Offline) {
        $arguments += '-o'
    }
    $arguments + $Goals
}

function Get-FullCheckDefinitions {
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,
        [Parameter(Mandatory)]
        [string]$NpmCommand,
        [Parameter(Mandatory)]
        [string]$MavenCommand,
        [switch]$Offline
    )

    # How: Mavenは集約POM、Frontendはプロジェクト境界のaggregate scriptを入口にし、
    # moduleやpackageを個別列挙せず追加分を自動的に検査へ含める。
    # Why not: moduleごとのパスをrunnerへ固定すると、追加時に品質ゲートの更新漏れが起きるため。
    @(
        New-CheckDefinition -Name 'frontend-lint' -Command $NpmCommand -Arguments @('--prefix', 'frontend', 'run', 'lint')
        New-CheckDefinition -Name 'frontend-typecheck' -Command $NpmCommand -Arguments @('--prefix', 'frontend', 'run', 'typecheck')
        New-CheckDefinition -Name 'frontend-unit-test' -Command $NpmCommand -Arguments @('--prefix', 'frontend', 'test')
        New-CheckDefinition -Name 'frontend-build' -Command $NpmCommand -Arguments @('--prefix', 'frontend', 'run', 'build')
        New-CheckDefinition -Name 'backend-test-compile' -Command $MavenCommand -Arguments (Get-MavenArguments -Offline:$Offline -Goals @('test-compile'))
        New-CheckDefinition -Name 'backend-spotless' -Command $MavenCommand -Arguments (Get-MavenArguments -Offline:$Offline -Goals @('spotless:check'))
        New-CheckDefinition -Name 'backend-checkstyle' -Command $MavenCommand -Arguments (Get-MavenArguments -Offline:$Offline -Goals @('checkstyle:check'))
        New-CheckDefinition -Name 'backend-spotbugs' -Command $MavenCommand -Arguments (Get-MavenArguments -Offline:$Offline -Goals @('test-compile', 'spotbugs:check'))
        New-CheckDefinition -Name 'oracle-preflight-contract-test' -Command 'pwsh' -Arguments @(
            '-NoProfile', '-File', (Join-Path $RepoRoot 'scripts/oracle-preflight.tests.ps1')
        )
        New-CheckDefinition -Name 'coverage-summary-contract-test' -Command 'pwsh' -Arguments @(
            '-NoProfile', '-File', (Join-Path $RepoRoot 'scripts/coverage-summary.tests.ps1')
        )
        New-CheckDefinition -Name 'coverage-gate-contract-test' -Command 'pwsh' -Arguments @(
            '-NoProfile', '-File', (Join-Path $RepoRoot 'scripts/coverage-gate.tests.ps1')
        )
    )
}

function Get-QuickCheckDefinitions {
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,
        [string[]]$StagedFiles = @(),
        [Parameter(Mandatory)]
        [string]$NpmCommand,
        [Parameter(Mandatory)]
        [string]$GitleaksCommand,
        [string]$MavenCommand,
        [switch]$Offline
    )

    $frontendFiles = @($StagedFiles | Where-Object { $_ -match '^frontend/.+\.(ts|tsx)$' })
    $frontendLintFiles = $frontendFiles
    $markdownFiles = @($StagedFiles | Where-Object { $_ -match '\.md$' })
    $hasJavaChanges = @($StagedFiles | Where-Object { $_ -match '^backend/.+\.java$' }).Count -gt 0
    $forbiddenPattern = '(^|/)(node_modules|target|dist|coverage|playwright-report|test-results)(/|$)|(^|/)\.tools(/|$)|\.log$'

    $definitions = [System.Collections.Generic.List[object]]::new()
    $definitions.Add((New-CheckDefinition -Name 'staged-whitespace' -Command 'git' -Arguments @('-C', $RepoRoot, 'diff', '--cached', '--check')))
    $definitions.Add((New-CheckDefinition -Name 'staged-artifacts' -Action {
        $forbidden = @($StagedFiles | Where-Object { $_ -match $forbiddenPattern })
        if ($forbidden.Count -gt 0) {
            throw "Generated or local-only files are staged: $($forbidden -join ', ')"
        }
    }.GetNewClosure()))

    if ($frontendLintFiles.Count -gt 0) {
        $definitions.Add((New-CheckDefinition -Name 'frontend-staged-lint' -Command $NpmCommand -Arguments (@(
            '--prefix', 'frontend', 'exec', '--', 'eslint'
        ) + $frontendLintFiles + @('--max-warnings', '0'))))
    }
    if ($markdownFiles.Count -gt 0) {
        $definitions.Add((New-CheckDefinition -Name 'markdown-staged-lint' -Command $NpmCommand -Arguments (@(
            'run', 'lint:markdown', '--', '--no-globs'
        ) + $markdownFiles)))
    }
    if ($hasJavaChanges) {
        $definitions.Add((New-CheckDefinition -Name 'backend-staged-spotless' -Command $MavenCommand -Arguments (
            Get-MavenArguments -Offline:$Offline -Goals @('spotless:check')
        )))
    }

    $definitions.Add((New-CheckDefinition -Name 'staged-secrets' -Command $GitleaksCommand -Arguments @(
        'git', '--pre-commit', '--staged', '--redact', '--verbose', '--config', (Join-Path $RepoRoot '.gitleaks.toml')
    )))
    $definitions
}

function Get-PushRefRecords {
    param([Parameter(Mandatory)][string]$InputText)

    $zeroSha = '0000000000000000000000000000000000000000'
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($line in ($InputText -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $columns = @($line.Trim() -split '\s+')
        if ($columns.Count -ne 4) {
            throw "Invalid pre-push input line: $line"
        }

        foreach ($sha in @($columns[1], $columns[3])) {
            if ($sha -notmatch '(?i)^[0-9a-f]{40}$') {
                throw "Invalid pre-push sha: $sha"
            }
        }

        $records.Add([pscustomobject]@{
                LocalRef  = $columns[0]
                LocalSha  = $columns[1]
                RemoteRef = $columns[2]
                RemoteSha = $columns[3]
            })
    }

    if ($records.Count -eq 0) {
        throw 'Pre-push input did not contain any ref update.'
    }

    $records
}

function Get-PrePushUnsharedCommits {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$LocalSha
    )

    $commits = @(git -C $RepoRoot rev-list --reverse $LocalSha --not --remotes)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to enumerate unshared commits for $LocalSha."
    }
    if ($commits.Count -eq 0) {
        return @($LocalSha)
    }
    $commits
}

function Get-PrePushChangedFiles {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][object[]]$PushRefs
    )

    $zeroSha = '0000000000000000000000000000000000000000'
    $changedFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($pushRef in $PushRefs) {
        if ($pushRef.LocalSha -eq $zeroSha) {
            continue
        }

        $null = git -C $RepoRoot cat-file -e "$($pushRef.LocalSha)^{commit}" 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Local pre-push commit is not available: $($pushRef.LocalSha)"
        }

        if ($pushRef.RemoteSha -ne $zeroSha) {
            $null = git -C $RepoRoot cat-file -e "$($pushRef.RemoteSha)^{commit}" 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "Remote pre-push commit is not available locally: $($pushRef.RemoteSha)"
            }
            $files = @(git -C $RepoRoot diff --name-only --diff-filter=ACMR $pushRef.RemoteSha $pushRef.LocalSha)
            if ($LASTEXITCODE -ne 0) {
                throw "Unable to resolve changed files between $($pushRef.RemoteSha) and $($pushRef.LocalSha)."
            }
        }
        else {
            $files = [System.Collections.Generic.List[string]]::new()
            foreach ($commit in (Get-PrePushUnsharedCommits -RepoRoot $RepoRoot -LocalSha $pushRef.LocalSha)) {
                $commitFiles = @(git -C $RepoRoot diff-tree --root --no-commit-id --name-only --diff-filter=ACMR -r $commit)
                if ($LASTEXITCODE -ne 0) {
                    throw "Unable to resolve changed files for commit $commit."
                }
                $commitFiles | ForEach-Object { $files.Add($_) }
            }
        }

        foreach ($file in $files) {
            if (-not [string]::IsNullOrWhiteSpace($file)) {
                $normalized = $file.Replace('\', '/')
                $null = $changedFiles.Add($normalized)
            }
        }
    }

    @($changedFiles | Sort-Object)
}

function Invoke-PrePushDiffCheck {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][object[]]$PushRefs
    )

    $zeroSha = '0000000000000000000000000000000000000000'
    foreach ($pushRef in $PushRefs) {
        if ($pushRef.LocalSha -eq $zeroSha) {
            continue
        }

        if ($pushRef.RemoteSha -ne $zeroSha) {
            $output = @(git -C $RepoRoot diff --check $pushRef.RemoteSha $pushRef.LocalSha 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "Whitespace errors found between $($pushRef.RemoteSha) and $($pushRef.LocalSha): $($output -join ' ')"
            }
            continue
        }

        foreach ($commit in (Get-PrePushUnsharedCommits -RepoRoot $RepoRoot -LocalSha $pushRef.LocalSha)) {
            $output = @(git -C $RepoRoot diff-tree --check --root --no-commit-id -r $commit 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "Whitespace errors found in commit ${commit}: $($output -join ' ')"
            }
        }
    }
}

function Get-PrePushCheckDefinitions {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string[]]$ChangedFiles,
        [object[]]$PushRefs = @(),
        [Parameter(Mandatory)][string]$NpmCommand,
        [Parameter(Mandatory)][string]$MavenCommand,
        [Parameter(Mandatory)][string]$GitleaksCommand,
        [switch]$Offline
    )

    $normalizedFiles = @($ChangedFiles | ForEach-Object { $_.Replace('\', '/') } | Sort-Object -Unique)
    $frontendCodeFiles = @($normalizedFiles | Where-Object { $_ -match '^frontend/.+\.(ts|tsx)$' })
    $frontendConfigChanged = @($normalizedFiles | Where-Object {
            $_ -match '^frontend/(package(-lock)?\.json|vite\.config\..+|tsconfig.*\.json|eslint\.config\..+)$'
        }).Count -gt 0
    $markdownFiles = @($normalizedFiles | Where-Object { $_ -match '\.md$' })
    $hasJavaChanges = @($normalizedFiles | Where-Object { $_ -match '^backend/.+\.java$' }).Count -gt 0
    $forbiddenPattern = '(^|/)(node_modules|target|dist|coverage|playwright-report|test-results)(/|$)|(^|/)\.tools(/|$)|\.log$'

    $definitions = [System.Collections.Generic.List[object]]::new()
    $definitions.Add((New-CheckDefinition -Name 'pre-push-diff-check' -Action {
                Invoke-PrePushDiffCheck -RepoRoot $RepoRoot -PushRefs $PushRefs
            }.GetNewClosure()))
    $definitions.Add((New-CheckDefinition -Name 'pre-push-artifact-check' -Action {
                $forbidden = @($normalizedFiles | Where-Object { $_ -match $forbiddenPattern })
                if ($forbidden.Count -gt 0) {
                    throw "Generated or local-only files are part of the push: $($forbidden -join ', ')"
                }
            }.GetNewClosure()))
    $definitions.Add((New-CheckDefinition -Name 'pre-push-secrets' -Command $GitleaksCommand -Arguments @(
            'dir', '--redact', '--config', (Join-Path $RepoRoot '.gitleaks.toml'), '.'
        )))

    if ($frontendConfigChanged) {
        $definitions.Add((New-CheckDefinition -Name 'frontend-pre-push-lint' -Command $NpmCommand -Arguments @(
                '--prefix', 'frontend', 'run', 'lint'
            )))
    }
    elseif ($frontendCodeFiles.Count -gt 0) {
        $definitions.Add((New-CheckDefinition -Name 'frontend-pre-push-lint' -Command $NpmCommand -Arguments (@(
                    '--prefix', 'frontend', 'exec', '--', 'eslint'
                ) + $frontendCodeFiles + @('--max-warnings', '0'))))
    }

    if ($markdownFiles.Count -gt 0) {
        $definitions.Add((New-CheckDefinition -Name 'markdown-pre-push-lint' -Command $NpmCommand -Arguments (@(
                    'run', 'lint:markdown', '--', '--no-globs'
                ) + $markdownFiles)))
    }
    if ($hasJavaChanges) {
        $definitions.Add((New-CheckDefinition -Name 'backend-pre-push-spotless' -Command $MavenCommand -Arguments (
                Get-MavenArguments -Offline:$Offline -Goals @('spotless:check')
            )))
    }

    $definitions
}

function Get-PrePushInputText {
    param([string]$ProvidedInput)

    if (-not [string]::IsNullOrWhiteSpace($ProvidedInput)) {
        return $ProvidedInput
    }
    if (-not [Console]::IsInputRedirected) {
        throw 'PrePush requires ref input on stdin.'
    }
    $inputText = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($inputText)) {
        throw 'PrePush stdin was empty.'
    }
    $inputText
}

function Get-CiTaskDefinitions {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FrontendCoverage', 'BackendCoverage', 'BackendUnit', 'E2E', 'E2EOracle', 'DirectorySecrets', 'DependencyAudit')]
        [string]$CiTask,
        [Parameter(Mandatory)]
        [string]$RepoRoot,
        [Parameter(Mandatory)]
        [string]$NpmCommand,
        [Parameter(Mandatory)]
        [string]$MavenCommand,
        [Parameter(Mandatory)]
        [string]$OracleScript,
        [string]$OracleConfigPath,
        [string]$GitleaksCommand = 'gitleaks',
        [switch]$Offline
    )

    switch ($CiTask) {
        'FrontendCoverage' {
            @(
                New-CheckDefinition -Name 'frontend-coverage' -Command $NpmCommand -Arguments @('--prefix', 'frontend', 'run', 'coverage')
                New-CoverageReportCheckDefinition -Name 'frontend-coverage-report' -Paths @(
                    (Join-Path $RepoRoot 'frontend/coverage/index.html')
                    (Join-Path $RepoRoot 'frontend/coverage/coverage-summary.json')
                    (Join-Path $RepoRoot 'frontend/coverage/lcov.info')
                )
            )
        }
        'BackendCoverage' {
            $arguments = @('-NoProfile', '-File', $OracleScript)
            if (-not [string]::IsNullOrWhiteSpace($OracleConfigPath)) {
                $arguments += @('-ConfigPath', $OracleConfigPath)
            }
            $arguments += @('-Pcoverage', 'verify')
            @(
                New-CheckDefinition -Name 'backend-coverage' -Command 'pwsh' -Arguments $arguments
                New-CoverageReportCheckDefinition -Name 'backend-coverage-report' -Paths @(
                    (Join-Path $RepoRoot 'backend/target/site/jacoco/index.html')
                    (Join-Path $RepoRoot 'backend/target/site/jacoco/jacoco.xml')
                    (Join-Path $RepoRoot 'backend/target/site/jacoco/jacoco.csv')
                )
            )
        }
        'BackendUnit' {
            New-CheckDefinition -Name 'backend-unit-test' -Command $MavenCommand -Arguments (Get-MavenArguments -Offline:$Offline -Goals @(
                '-Dtest=ApiExceptionHandlerTest,BusinessEventLoggingTest,MasterDataRepositoryTest,RequestIdFilterTest,RequestMetadataInterceptorTest,TimeRulesTest'
                'test'
            ))
        }
        'E2E' {
            New-CheckDefinition -Name 'frontend-e2e' -Command $NpmCommand -Arguments @('--prefix', 'frontend', 'run', 'e2e')
        }
        'E2EOracle' {
            $arguments = @('-NoProfile', '-File', (Join-Path $RepoRoot 'backend/scripts/test-e2e-oracle.ps1'))
            if (-not [string]::IsNullOrWhiteSpace($OracleConfigPath)) {
                $arguments += @('-ConfigPath', $OracleConfigPath)
            }
            New-CheckDefinition -Name 'oracle-e2e' -Command 'pwsh' -Arguments $arguments
        }
        'DirectorySecrets' {
            New-CheckDefinition -Name 'directory-secrets' -Command $GitleaksCommand -Arguments @(
                'dir', '--redact', '--config', (Join-Path $RepoRoot '.gitleaks.toml'), '.'
            )
        }
        'DependencyAudit' {
            New-CheckDefinition -Name 'root-dependency-audit' -Command $NpmCommand -Arguments @('audit', '--audit-level=high')
            New-CheckDefinition -Name 'frontend-dependency-audit' -Command $NpmCommand -Arguments @('--prefix', 'frontend', 'audit', '--audit-level=high')
            New-CheckDefinition -Name 'backend-dependency-audit' -Command $MavenCommand -Arguments (Get-MavenArguments -Offline:$Offline -Goals @(
                'org.owasp:dependency-check-maven:12.2.2:check'
            ))
        }
    }
}

function Get-OracleCheckDefinitions {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$OracleConfigPath,
        [switch]$AllowDdl,
        [string]$DdlScript
    )

    $oracleScript = Join-Path $RepoRoot 'backend/scripts/test-oracle.ps1'
    $baseArguments = @('-NoProfile', '-File', $oracleScript)
    if (-not [string]::IsNullOrWhiteSpace($OracleConfigPath)) {
        $baseArguments += @('-ConfigPath', $OracleConfigPath)
    }

    @(
        New-CheckDefinition -Name 'oracle-safety-guard' -Command 'pwsh' -Arguments ($baseArguments + @('-DskipTests', 'test-compile'))
        New-CheckDefinition -Name 'oracle-integration-tests' -Command 'pwsh' -Arguments ($baseArguments + @('test'))
    )

    if (-not [string]::IsNullOrWhiteSpace($DdlScript)) {
        if (-not $AllowDdl) {
            throw 'DdlScript requires -AllowDdl.'
        }
        New-CheckDefinition -Name 'oracle-ddl' -Command 'pwsh' -Arguments (
            $baseArguments + @('-AllowDdl', '-DdlScript', $DdlScript, '-DskipTests', 'test-compile')
        )
    }
}

function Invoke-QualityChecks {
    param(
        [object[]]$Definitions,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Failures,
        [scriptblock]$CommandInvoker = {
            param($Command, $Arguments)
            & $Command @Arguments | Out-Host
            $LASTEXITCODE
        }
    )

    foreach ($definition in $Definitions) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Host "==> $($definition.Name)"
        try {
            if ($definition.Action) {
                & $definition.Action
                $exitCode = 0
            }
            else {
                $result = & $CommandInvoker $definition.Command @($definition.Arguments)
                $exitCode = if ($result -is [int]) { $result } else { [int]$result.ExitCode }
            }
            if ($exitCode -ne 0) {
                throw "Command exited with code $exitCode."
            }
            Write-Host "PASS $($definition.Name) ($([math]::Round($stopwatch.Elapsed.TotalSeconds, 2))s)"
        }
        catch {
            $Failures.Add($definition.Name)
            Write-Warning "FAIL $($definition.Name) ($([math]::Round($stopwatch.Elapsed.TotalSeconds, 2))s): $($_.Exception.Message)"
        }
        finally {
            $stopwatch.Stop()
        }
    }
}

function Get-StagedFiles {
    param([Parameter(Mandatory)][string]$RepoRoot)

    # How: 日本語を含むstagedパスをGitの引用・エスケープなしで取得し、拡張子や配置判定へ渡す。
    # Why not: Git既定のquotePath出力をそのまま使うと、引用符付きパスがMarkdownや生成物判定から漏れるため。
    $files = @(git -c core.quotePath=false -C $RepoRoot diff --cached --name-only --diff-filter=ACMR)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to read staged file names from Git.'
    }
    @($files | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-GitleaksCommand {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $binaryName = if ($isWindowsHost) { 'gitleaks.exe' } else { 'gitleaks' }
    $localPath = Join-Path $RepoRoot ".tools/gitleaks/8.30.1/$binaryName"
    if (Test-Path -LiteralPath $localPath -PathType Leaf) {
        return $localPath
    }
    'gitleaks'
}

function Invoke-QualityRunner {
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,
        [ValidateSet('Quick', 'PrePush', 'Full', 'Oracle', 'All')]
        [string]$Mode = 'Quick',
        [string]$PushInput,
        [switch]$Offline,
        [ValidateSet('None', 'FrontendCoverage', 'BackendCoverage', 'BackendUnit', 'E2E', 'E2EOracle', 'DirectorySecrets', 'DependencyAudit')]
        [string]$CiTask = 'None',
        [switch]$AllowDdl,
        [string]$DdlScript,
        [string]$OracleConfigPath
    )

    $failures = [System.Collections.Generic.List[string]]::new()
    $npmCommand = if ($isWindowsHost) { 'npm.cmd' } else { 'npm' }
    $gitleaksCommand = Get-GitleaksCommand -RepoRoot $RepoRoot
    $mavenCommand = if ($isWindowsHost) {
        Join-Path $RepoRoot 'backend/mvnw.cmd'
    }
    else {
        Join-Path $RepoRoot 'backend/mvnw'
    }

    Push-Location $RepoRoot
    try {
        if ($CiTask -ne 'None') {
            $definitions = @(Get-CiTaskDefinitions -CiTask $CiTask -RepoRoot $RepoRoot -NpmCommand $npmCommand `
                -MavenCommand $mavenCommand -OracleScript (Join-Path $RepoRoot 'backend/scripts/test-oracle.ps1') `
                -OracleConfigPath $OracleConfigPath -GitleaksCommand $gitleaksCommand -Offline:$Offline)
            Invoke-QualityChecks -Definitions $definitions -Failures $failures
        }
        else {
            if ($Mode -eq 'PrePush') {
                try {
                    $pushRefs = @(Get-PushRefRecords -InputText (Get-PrePushInputText -ProvidedInput $PushInput))
                    $changedFiles = @(Get-PrePushChangedFiles -RepoRoot $RepoRoot -PushRefs $pushRefs)
                    $definitions = @(Get-PrePushCheckDefinitions -RepoRoot $RepoRoot -ChangedFiles $changedFiles `
                        -PushRefs $pushRefs -NpmCommand $npmCommand -MavenCommand $mavenCommand `
                        -GitleaksCommand $gitleaksCommand -Offline:$Offline)
                    Invoke-QualityChecks -Definitions $definitions -Failures $failures
                }
                catch {
                    $failures.Add('pre-push-definition')
                    Write-Warning "FAIL pre-push-definition: $($_.Exception.Message)"
                }
            }
            if ($Mode -in @('Quick')) {
                try {
                    $stagedFiles = @(Get-StagedFiles -RepoRoot $RepoRoot)
                    $definitions = @(Get-QuickCheckDefinitions -RepoRoot $RepoRoot -StagedFiles $stagedFiles `
                        -NpmCommand $npmCommand -MavenCommand $mavenCommand -GitleaksCommand $gitleaksCommand -Offline:$Offline)
                    Invoke-QualityChecks -Definitions $definitions -Failures $failures
                }
                catch {
                    $failures.Add('staged-file-selection')
                    Write-Warning "FAIL staged-file-selection: $($_.Exception.Message)"
                }
            }
            if ($Mode -in @('Full', 'All')) {
                $definitions = @(Get-FullCheckDefinitions -RepoRoot $RepoRoot -NpmCommand $npmCommand `
                    -MavenCommand $mavenCommand -Offline:$Offline)
                Invoke-QualityChecks -Definitions $definitions -Failures $failures
            }
            if ($Mode -in @('Oracle', 'All')) {
                try {
                    $definitions = @(Get-OracleCheckDefinitions -RepoRoot $RepoRoot -OracleConfigPath $OracleConfigPath `
                        -AllowDdl:$AllowDdl -DdlScript $DdlScript)
                    Invoke-QualityChecks -Definitions $definitions -Failures $failures
                }
                catch {
                    $failures.Add('oracle-definition')
                    Write-Warning "FAIL oracle-definition: $($_.Exception.Message)"
                }
            }
        }
    }
    finally {
        Pop-Location
    }

    if ($failures.Count -gt 0) {
        Write-Host "`nFailed checks:"
        $failures | ForEach-Object { Write-Host " - $_" }
        return 1
    }

    Write-Host "`nAll requested checks passed."
    return 0
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Error 'scripts/check.ps1 requires PowerShell 7 or later.'
        exit 1
    }

    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    exit (Invoke-QualityRunner -RepoRoot $repoRoot -Mode $Mode -PushInput $PushInput -Offline:$Offline `
        -CiTask $CiTask -AllowDdl:$AllowDdl -DdlScript $DdlScript -OracleConfigPath $OracleConfigPath)
}
