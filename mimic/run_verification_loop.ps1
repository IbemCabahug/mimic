# PHASE 4A VERIFICATION LOOP — runs the crypto/verifier suites N times and
# records one line per iteration. Flakiness in a crypto change is usually a
# harness that depends on shared state (the SharedPreferences document-meta
# singleton and the in-memory secure-storage fakes are both per-isolate), so a
# single green run proves very little. This repeats the SAME suites and reports
# any iteration whose count or failure differs from the first.
#
# Usage:  powershell -File run_verification_loop.ps1 -Iterations 5
param(
  [int]$Iterations = 5,
  [string]$OutFile = 'loop_results.txt'
)

$ErrorActionPreference = 'Stop'
$flutter = 'C:\src\flutter\bin\flutter.bat'

# --timeout 5m: see the note below. This is a COMMAND-LINE flag, deliberately not
# a source edit. Two source-level attempts were made first and both were wrong:
#   - `testTimeout = ...` in flutter_test_config.dart -> "Setter not found"
#   - `group(..., timeout: ...)` -> "No named parameter with the name 'timeout'",
#     because flutter_test SHADOWS test_api's group, and only test_api's takes one.
# `flutter test --timeout` is the supported mechanism and touches no source.
$testTimeout = '5m'

# The suites that carry the PHASE 4A work:
#   - the two new files (format layer + verifier dispatcher)
#   - vault_crypto_test.dart (the dispatcher and the v4 write side)
#   - crypto_isolate_test.dart (the derive-cost harness coupling)
#   - atomicity_test.dart (the staged-triple path changePin goes through)
$suites = @(
  'test/vault/crypto/authenticated_blob_format_test.dart',
  'test/vault/crypto/verifier_dispatch_test.dart',
  'test/vault/crypto/vault_crypto_test.dart',
  'test/vault/crypto/crypto_isolate_test.dart',
  'test/vault/crypto/atomicity_test.dart'
)

$results = @()

for ($i = 1; $i -le $Iterations; $i++) {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $args = @('test') + $suites + @('--timeout', $testTimeout)
  $log = "loop_iter_$i.log"
  $err = "loop_iter_$i.err.log"

  & $flutter @args 2>&1 | Out-File -FilePath $log -Encoding utf8
  $sw.Stop()

  $text = Get-Content $log -Raw
  $passed = 0
  $failed = 0
  # The success line is "NN:NN +NNN: All tests passed!" with NO -N segment, so the
  # first version of this regex (which expected "-(\d+)") never matched and every
  # iteration reported passed=0. Match the trailing count instead.
  if ($text -match '\+(\d+):\s*All tests passed') {
    $passed = [int]$Matches[1]; $failed = 0
  }
  elseif ($text -match '\+(\d+)\s*-(\d+):\s*Some tests failed') {
    $passed = [int]$Matches[1]; $failed = [int]$Matches[2]
  }
  elseif ($text -match 'TimeoutException|Error:') {
    $failed = 1
  }

  $line = "iteration=$i passed=$passed failed=$failed seconds=$([math]::Round($sw.Elapsed.TotalSeconds,1))"
  $results += $line
  Write-Host $line

  # Record any failing test names so a flake is identifiable, not just countable.
  if ($failed -gt 0) {
    $names = Select-String -Path $log -Pattern '\[E\]' |
             ForEach-Object { ($_.Line -split ': ')[-1] }
    foreach ($n in $names) { Write-Host "    FAILED: $n" }
  }
}

Write-Host ''
Write-Host '===== VERIFICATION LOOP SUMMARY ====='
$results | ForEach-Object { Write-Host $_ }

$bad = @($results | Where-Object { $_ -notmatch 'failed=0' })
if ($bad.Count -gt 0) {
  Write-Host "RESULT: FAILED - $($bad.Count) of $Iterations iteration(s) had failures"
} else {
  # Confirm the passing count was identical every time. A suite that silently
  # loses a test between runs would otherwise still report "all passed".
  $counts = @($results | ForEach-Object {
    if ($_ -match 'passed=(\d+)') { $Matches[1] }
  } | Sort-Object -Unique)
  if ($counts.Count -eq 1) {
    Write-Host "RESULT: ALL $Iterations ITERATIONS PASSED, consistently $($counts[0]) tests each"
  } else {
    Write-Host "RESULT: ALL $Iterations PASSED but the test COUNT VARIED: $($counts -join ', ')"
  }
}
Write-Host '======================================'
