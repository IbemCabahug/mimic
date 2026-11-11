# tool/build_release.ps1
#
# Release build wrapper for Mimic — refuses to build unless the security-
# critical defines are present (Phase-5 audit LIC-02 / LIC-03 / LIC-05).
#
# Usage:
#   $env:MIMIC_LICENSE_SECRET  = '<current license secret>'   # never commit
#   $env:MIMIC_ACTIVATION_URL  = '<apps script /exec url>'
#   powershell -File tool\build_release.ps1
#
# Optional:
#   -Flavor foss|playStore   (default foss)
#   -FreeTierOnly           (no new activation configuration; cached grants retained)

param(
  [ValidateSet('foss', 'playStore')]
  [string]$Flavor = 'foss',
  [switch]$FreeTierOnly
)

$ErrorActionPreference = 'Stop'

$secret = $env:MIMIC_LICENSE_SECRET
$activationUrl = $env:MIMIC_ACTIVATION_URL

if (!$FreeTierOnly -and [string]::IsNullOrWhiteSpace($secret)) {
  Write-Host 'ERROR: MIMIC_LICENSE_SECRET is not set.' -ForegroundColor Red
  Write-Host 'Set it in this session first (never commit it):'
  Write-Host "  `$env:MIMIC_LICENSE_SECRET = '<current secret>'"
  exit 1
}
if (!$FreeTierOnly -and [string]::IsNullOrWhiteSpace($activationUrl)) {
  Write-Host 'ERROR: MIMIC_ACTIVATION_URL is not set.' -ForegroundColor Red
  Write-Host 'Set it in this session first:'
  Write-Host "  `$env:MIMIC_ACTIVATION_URL = 'https://script.google.com/macros/s/<DEPLOY_ID>/exec'"
  exit 1
}

$licenseDefines = @()
if (!$FreeTierOnly) {
  $licenseDefines = @(
    "--dart-define=MIMIC_LICENSE_SECRET=$secret",
    "--dart-define=MIMIC_ACTIVATION_URL=$activationUrl"
  )
}

# A public artifact must never inherit the private staging package identity.
if ($env:ORG_GRADLE_PROJECT_mimicStaging -eq 'true') {
  throw 'Clear ORG_GRADLE_PROJECT_mimicStaging before building a public release.'
}
Write-Host "Building public release APK (flavor=$Flavor, billing enforced, offers hidden, freeTierOnly=$FreeTierOnly)..." -ForegroundColor Green

flutter build apk --release --obfuscate --split-debug-info=./debug_symbols/ `
  "--dart-define=APP_FLAVOR=$Flavor" `
  '--dart-define=BILLING_ENFORCED=true' `
  '--dart-define=MIMIC_STAGING=false' `
  '--dart-define=MIMIC_PRO_OFFERS=false' `
  @licenseDefines

exit $LASTEXITCODE
