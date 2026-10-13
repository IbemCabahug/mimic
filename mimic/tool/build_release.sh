#!/usr/bin/env bash
# tool/build_release.sh
#
# Release build wrapper for Mimic — refuses to build unless the security-
# critical defines are present (Phase-5 audit LIC-02 / LIC-03 / LIC-05).
#
# Usage:
#   export MIMIC_LICENSE_SECRET='<current license secret>'   # never commit
#   export MIMIC_ACTIVATION_URL='<apps script /exec url>'
#   ./tool/build_release.sh
#
# Optional: FLAVOR=foss|playStore (default foss)

set -euo pipefail

: "${MIMIC_LICENSE_SECRET:?ERROR: MIMIC_LICENSE_SECRET is not set — export it in this session (never commit it)}"
: "${MIMIC_ACTIVATION_URL:?ERROR: MIMIC_ACTIVATION_URL is not set — export it in this session}"

FLAVOR="${FLAVOR:-foss}"

echo "Building release APK (flavor=$FLAVOR, billing enforced, license defines present)..."

flutter build apk --release --obfuscate --split-debug-info=./debug_symbols/ \
  "--dart-define=APP_FLAVOR=$FLAVOR" \
  "--dart-define=BILLING_ENFORCED=true" \
  "--dart-define=MIMIC_LICENSE_SECRET=$MIMIC_LICENSE_SECRET" \
  "--dart-define=MIMIC_ACTIVATION_URL=$MIMIC_ACTIVATION_URL"
