[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$ConfigPath,
    [int]$BackendPort = 8080,
    [int]$FrontendPort = 4173
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = (Resolve-Path (Join-Path $scriptDir '..')).Path
$repoRoot = (Resolve-Path (Join-Path $backendDir '..')).Path
$frontendDir = Join-Path $repoRoot 'frontend'
$artifactDir = Join-Path $backendDir 'target/e2e'
$oracleTestSqlRoot = [IO.Path]::GetFullPath((Join-Path $backendDir 'src/test/resources/db/oracle'))
$cleanupPath = [IO.Path]::GetFullPath((Join-Path $oracleTestSqlRoot 'e2e-cleanup.sql'))
$verifyPath = [IO.Path]::GetFullPath((Join-Path $oracleTestSqlRoot 'e2e-verify.sql'))

function Assert-SafeSqlFile {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Description
    )

    if (-not $Path.StartsWith($Root.TrimEnd('\') + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetExtension($Path) -ine '.sql' -or
        -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description must be an existing .sql file under the approved directory."
    }
}

Assert-SafeSqlFile -Root $oracleTestSqlRoot -Path $cleanupPath -Description 'The Oracle E2E cleanup script'
Assert-SafeSqlFile -Root $oracleTestSqlRoot -Path $verifyPath -Description 'The Oracle E2E verification script'

. (Join-Path $scriptDir 'oracle-test-helpers.ps1')
$oracleEnvironment = Get-OracleTestEnvironment -BackendDir $backendDir -ConfigPath $ConfigPath
Set-OracleTestEnvironment -Environment $oracleEnvironment

New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null
$backendStdout = Join-Path $artifactDir 'backend-process.stdout.log'
$backendStderr = Join-Path $artifactDir 'backend-process.stderr.log'
$frontendStdout = Join-Path $artifactDir 'frontend-preview.stdout.log'
$frontendStderr = Join-Path $artifactDir 'frontend-preview.stderr.log'
$frontendBuildStdout = Join-Path $artifactDir 'frontend-build.stdout.log'
$frontendBuildStderr = Join-Path $artifactDir 'frontend-build.stderr.log'
$playwrightStdout = Join-Path $artifactDir 'playwright.stdout.log'
$playwrightStderr = Join-Path $artifactDir 'playwright.stderr.log'
$backendLog = Join-Path $artifactDir 'backend.log'
$artifactFiles = @(
    $backendStdout, $backendStderr, $frontendStdout, $frontendStderr,
    $frontendBuildStdout, $frontendBuildStderr, $playwrightStdout, $playwrightStderr, $backendLog
)
foreach ($artifactFile in $artifactFiles) {
    if (Test-Path -LiteralPath $artifactFile -PathType Leaf) {
        Clear-Content -LiteralPath $artifactFile
    }
    else {
        New-Item -ItemType File -Force -Path $artifactFile | Out-Null
    }
}

function Get-ChildEnvironment {
    param([switch]$IncludeOracle)

    $environment = @{}
    Get-ChildItem Env: | ForEach-Object {
        if ($IncludeOracle -or $_.Name -notmatch '^(DAILY_REPORT_DB_|DAILY_REPORT_DDL_CLI_APPROVED$)') {
            $environment[$_.Name] = $_.Value
        }
    }
    $environment
}

function Get-DescendantProcessIds {
    param([Parameter(Mandatory)][int]$ParentId)

    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ParentId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        $child.ProcessId
        Get-DescendantProcessIds -ParentId ([int]$child.ProcessId)
    }
}

function Stop-ProcessTree {
    param([System.Diagnostics.Process]$Process)

    if ($null -eq $Process) {
        return
    }
    $descendantIds = @(Get-DescendantProcessIds -ParentId $Process.Id | Sort-Object -Descending)
    foreach ($processId in $descendantIds) {
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }
    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
}

function Get-ResponseStatusCode {
    param([Parameter(Mandatory)]$ErrorRecord)

    if ($null -ne $ErrorRecord.Exception.Response) {
        try {
            return [int]$ErrorRecord.Exception.Response.StatusCode
        }
        catch {
            return 0
        }
    }
    0
}

function Wait-HttpEndpoint {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][int[]]$AcceptedStatusCodes,
        [int]$TimeoutSeconds = 120
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 5
            if ($AcceptedStatusCodes -contains [int]$response.StatusCode) {
                return
            }
        }
        catch {
            if ($AcceptedStatusCodes -contains (Get-ResponseStatusCode -ErrorRecord $_)) {
                return
            }
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)

    throw "Endpoint did not become ready: $Uri"
}

$backendProcess = $null
$frontendProcess = $null
$playwrightProcess = $null
$exitCode = 1

try {
    Write-Host '==> Verify Oracle identity before any E2E SQL'
    Assert-OracleTestIdentity -Environment $oracleEnvironment

    Write-Host '==> Clean fixed Oracle E2E data before the run'
    Invoke-OracleSqlPlus -Environment $oracleEnvironment -Path $cleanupPath -WorkingDirectory $backendDir

    $mavenWrapper = Join-Path $backendDir 'mvnw.cmd'
    $mavenArguments = @(
        '-s', (Join-Path $backendDir 'local-maven-settings.xml'),
        '-B',
        'spring-boot:run',
        '-Dspring-boot.run.profiles=oracle-test,e2e'
    )
    $backendEnvironment = Get-ChildEnvironment -IncludeOracle
    $backendEnvironment['SPRING_PROFILES_ACTIVE'] = 'oracle-test,e2e'
    $backendEnvironment['SERVER_PORT'] = [string]$BackendPort
    $backendProcess = Start-Process -FilePath $mavenWrapper -ArgumentList $mavenArguments -WorkingDirectory $backendDir `
        -Environment $backendEnvironment -RedirectStandardOutput $backendStdout -RedirectStandardError $backendStderr `
        -PassThru -WindowStyle Hidden
    Wait-HttpEndpoint -Uri "http://127.0.0.1:$BackendPort/api/auth/me" -AcceptedStatusCodes @(200, 401)

    $npmCommand = (Get-Command npm.cmd -ErrorAction Stop).Source
    $frontendEnvironment = Get-ChildEnvironment
    $frontendEnvironment['NODE_ENV'] = 'test'
    $buildProcess = Start-Process -FilePath $npmCommand -ArgumentList @('--prefix', $frontendDir, 'run', 'build') `
        -WorkingDirectory $repoRoot -Environment $frontendEnvironment -RedirectStandardOutput $frontendBuildStdout `
        -RedirectStandardError $frontendBuildStderr -PassThru -WindowStyle Hidden
    $buildProcess.WaitForExit()
    if ($buildProcess.ExitCode -ne 0) {
        throw "Frontend build failed with exit code $($buildProcess.ExitCode)."
    }

    $frontendArguments = @('--prefix', $frontendDir, 'run', 'preview', '--', '--host', '127.0.0.1',
        '--port', [string]$FrontendPort, '--strictPort')
    $frontendProcess = Start-Process -FilePath $npmCommand -ArgumentList $frontendArguments -WorkingDirectory $repoRoot `
        -Environment $frontendEnvironment -RedirectStandardOutput $frontendStdout -RedirectStandardError $frontendStderr `
        -PassThru -WindowStyle Hidden
    Wait-HttpEndpoint -Uri "http://127.0.0.1:$FrontendPort/" -AcceptedStatusCodes @(200)

    $playwrightProcess = Start-Process -FilePath $npmCommand -ArgumentList @('--prefix', $frontendDir, 'run', 'e2e:oracle') `
        -WorkingDirectory $repoRoot -Environment $frontendEnvironment -RedirectStandardOutput $playwrightStdout `
        -RedirectStandardError $playwrightStderr -PassThru -WindowStyle Hidden
    $playwrightProcess.WaitForExit()
    $exitCode = $playwrightProcess.ExitCode
    if ($exitCode -ne 0) {
        throw "Oracle E2E failed with exit code $exitCode."
    }

    if (-not (Test-Path -LiteralPath $backendLog -PathType Leaf)) {
        throw "Backend log was not produced: $backendLog"
    }
    $backendLogContent = Get-Content -Raw -Encoding UTF8 -LiteralPath $backendLog
    $createMatch = [regex]::Match($backendLogContent,
        '(?m)^.*\[requestId:(?<requestId>[0-9a-f-]{36})\].*event=daily_report.saved.*useCase=CREATE.*reportId=(?<reportId>R-[0-9a-f-]{36}).*status=DRAFT.*$')
    if (-not $createMatch.Success) {
        throw 'Backend log did not contain the daily report CREATE success event.'
    }
    $createRequestId = $createMatch.Groups['requestId'].Value
    $reportId = $createMatch.Groups['reportId'].Value
    $escapedCreateRequestId = [regex]::Escape($createRequestId)
    $escapedReportId = [regex]::Escape($reportId)
    $submitMatch = [regex]::Match($backendLogContent,
        "(?m)^.*\[requestId:(?<requestId>[0-9a-f-]{36})\].*event=daily_report.submitted.*useCase=SUBMIT.*reportId=$escapedReportId.*status=PENDING.*$")
    if (-not $submitMatch.Success) {
        throw 'Backend log did not contain the daily report SUBMIT success event.'
    }
    if (-not [regex]::IsMatch($backendLogContent,
            "(?m)^.*event=request.completed requestId=$escapedCreateRequestId.*feature=DAILY_REPORT useCase=CREATE status=201 durationMs=\d+.*$")) {
        throw 'Backend log did not contain the CREATE completion status and duration.'
    }
    if (-not [regex]::IsMatch($backendLogContent,
            "(?m)^.*event=request.completed requestId=[0-9a-f-]{36}.*feature=DAILY_REPORT useCase=SUBMIT status=200 durationMs=\d+.*$")) {
        throw 'Backend log did not contain the SUBMIT completion status and duration.'
    }
    if (-not [regex]::IsMatch($backendLogContent,
            '(?m)^.*event=business.error requestId=[0-9a-f-]{36}.*feature=DAILY_REPORT useCase=CREATE status=409 code=DUPLICATE_REPORT.*$')) {
        throw 'Backend log did not contain the duplicate business error event.'
    }
    if (-not [regex]::IsMatch($backendLogContent,
            '(?m)^.*event=request.completed requestId=[0-9a-f-]{36}.*feature=DAILY_REPORT useCase=CREATE status=409 durationMs=\d+.*$')) {
        throw 'Backend log did not contain the duplicate business error completion status and duration.'
    }
    Write-Host "==> Verify Oracle persisted report $reportId"
    Invoke-OracleSqlPlus -Environment $oracleEnvironment -Path $verifyPath -Variables @{ REPORT_ID = $reportId } `
        -WorkingDirectory $backendDir
}
catch {
    Write-Error $_
    $exitCode = 1
}
finally {
    Stop-ProcessTree -Process $playwrightProcess
    Stop-ProcessTree -Process $frontendProcess
    Stop-ProcessTree -Process $backendProcess
    try {
        Write-Host '==> Clean fixed Oracle E2E data after the run'
        Invoke-OracleSqlPlus -Environment $oracleEnvironment -Path $cleanupPath -WorkingDirectory $backendDir
    }
    catch {
        Write-Error $_
        $exitCode = 1
    }
}

exit $exitCode
