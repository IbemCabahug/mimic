// Offline wrapper contract: intercept Flutter, never build or read credentials.
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const test = require('node:test');

const wrapper = path.join(__dirname, 'build_release.ps1').replaceAll("'", "''");

function run(mode, staging = '') {
  return spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', `
    $env:MIMIC_LICENSE_SECRET = $null
    $env:MIMIC_ACTIVATION_URL = $null
    $env:ORG_GRADLE_PROJECT_mimicStaging = '${staging}'
    function flutter {
      $required = @('apk', '--release', '--obfuscate',
        '--dart-define=BILLING_ENFORCED=true',
        '--dart-define=MIMIC_PRO_OFFERS=false',
        '--dart-define=MIMIC_STAGING=false')
      foreach ($flag in $required) {
        if ($args -notcontains $flag) { throw "Missing build flag: $flag" }
      }
      if ($args -match 'MIMIC_LICENSE_SECRET=|MIMIC_ACTIVATION_URL=') {
        throw 'Free-tier mode must not include activation credentials'
      }
      $global:LASTEXITCODE = 0
      Write-Output 'FREE_TIER_CONTRACT_PASSED'
    }
    & '${wrapper}' ${mode}
  `], { encoding: 'utf8', timeout: 120000 });
}

test('free-tier wrapper works without credentials and enforces public flags', () => {
  const result = run('-FreeTierOnly');
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /FREE_TIER_CONTRACT_PASSED/);
});

test('normal wrapper still refuses missing licensing credentials', () => {
  const result = run('');
  assert.equal(result.status, 1, result.stderr);
  assert.match(result.stdout, /MIMIC_LICENSE_SECRET is not set/);
  assert.doesNotMatch(result.stdout, /FREE_TIER_CONTRACT_PASSED/);
});

test('free-tier wrapper rejects an inherited staging package flag', () => {
  const result = run('-FreeTierOnly', 'true');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Clear ORG_GRADLE_PROJECT_mimicStaging/);
  assert.doesNotMatch(result.stdout, /FREE_TIER_CONTRACT_PASSED/);
});