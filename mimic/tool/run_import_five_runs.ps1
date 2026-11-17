# Runs the bulk media import reliability & UI navigation lifecycle test suites
# five times sequentially with distinct randomization seeds (1..5), ensuring
# zero concurrent sqlite3/flutter-lock contention and recording exact per-run
# pass/fail/skip counts and elapsed wall-clock durations.
param(
    [string]$OutDir = "$env:TEMP\mimic-ibem-import-five-runs",
    [int]$MinPassedCount = 33
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path $root -Parent
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$summaryRows = @()
$targets = @(
    'test/vault/services/import_reliability_regression_test.dart',
    'test/vault/screens/import_navigation_lifecycle_test.dart'
)
$startedAtUtc = [DateTime]::UtcNow.ToString('o')
$gitHead = (& git -C $repoRoot rev-parse HEAD 2>$null | Select-Object -First 1)
if (-not $gitHead) { $gitHead = 'unknown' }
$gitDirtyCount = @(& git -C $repoRoot status --porcelain 2>$null).Count

Push-Location $root
try {
    for ($seed = 1; $seed -le 5; $seed++) {
        $logFile = Join-Path $OutDir ("run_{0}_seed_{0}.log" -f $seed)
        if (Test-Path $logFile) { Remove-Item $logFile }

        Write-Host "=== Run $seed/5 (seed=$seed) started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        & flutter test --no-pub -j 1 -r expanded --test-randomize-ordering-seed=$seed @targets *>&1 |
        Tee-Object -FilePath $logFile
        $exitCode = $LASTEXITCODE
        $sw.Stop()

        $lines = Get-Content $logFile -ErrorAction SilentlyContinue
        $summaryMatch = $lines |
        Select-String -Pattern '^\d{2}:\d{2}\s+\+(\d+)(?:\s+~(\d+))?(?:\s+-(\d+))?:\s+(All tests passed!|Some tests failed\.)' |
        Select-Object -Last 1
        $passedCount = if ($summaryMatch) { [int]$summaryMatch.Matches[0].Groups[1].Value } else { 0 }
        $skippedCount = if ($summaryMatch -and $summaryMatch.Matches[0].Groups[2].Success) { [int]$summaryMatch.Matches[0].Groups[2].Value } else { 0 }
        $failedCount = if ($summaryMatch -and $summaryMatch.Matches[0].Groups[3].Success) { [int]$summaryMatch.Matches[0].Groups[3].Value } else { 0 }
        $allPassed = [bool]($summaryMatch -and $summaryMatch.Matches[0].Groups[4].Value -eq 'All tests passed!')
        $countMeetsFloor = ($passedCount -ge $MinPassedCount -and $skippedCount -eq 0 -and $failedCount -eq 0)
        $failedTestLines = @($lines | Select-String -Pattern '\[E\]' | ForEach-Object { $_.Line.Trim() })

        $row = [PSCustomObject]@{
            Run             = $seed
            Seed            = $seed
            ExitCode        = $exitCode
            PassedCount     = $passedCount
            SkippedCount    = $skippedCount
            FailedCount     = $failedCount
            AllPassed       = $allPassed
            CountMeetsFloor = $countMeetsFloor
            FailedLines     = $failedTestLines
            ElapsedSec      = [Math]::Round($sw.Elapsed.TotalSeconds, 2)
            LogPath         = $logFile
        }
        $summaryRows += $row
        Write-Host ("=== Run {0}/5 finished: exit={1}, +{2} ~{3} -{4}, allPassed={5}, floorOk={6}, elapsed={7}s ===" -f `
                $seed, $exitCode, $passedCount, $skippedCount, $failedCount, $allPassed, $countMeetsFloor, $row.ElapsedSec)

        if ($exitCode -ne 0 -or -not $allPassed -or -not $countMeetsFloor) {
            Write-Host "Run $seed validation failed (see $logFile)" -ForegroundColor Red
        }
    }

    $completedAtUtc = [DateTime]::UtcNow.ToString('o')
    $allRunsValid = ($summaryRows | Where-Object {
            $_.ExitCode -ne 0 -or -not $_.AllPassed -or -not $_.CountMeetsFloor
        }).Count -eq 0

    $summaryJson = Join-Path $OutDir 'summary.json'
    $report = [PSCustomObject]@{
        gitHead        = $gitHead.Trim()
        gitDirtyCount  = $gitDirtyCount
        startedAtUtc   = $startedAtUtc
        completedAtUtc = $completedAtUtc
        targets        = $targets
        minPassedCount = $MinPassedCount
        allRunsValid   = $allRunsValid
        runs           = $summaryRows
    }
    $report | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 $summaryJson

    Write-Host ""
    Write-Host "=== Five-Run Sequential Summary ==="
    $summaryRows | Format-Table -AutoSize
    Write-Host "Summary JSON: $summaryJson"

    if (-not $allRunsValid) {
        exit 1
    }
    exit 0
}
finally {
    Pop-Location
}
