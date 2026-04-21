#!/usr/bin/env bash
# scripts/smoke/carplay-entitlement.sh
#
# This script verifies that the iPhone target’s entitlements include the
# CarPlay Maps entitlement (com.apple.developer.carplay-maps). It exits with
# status 0 when the entitlement is present and 1 otherwise.

set -euo pipefail

# Locate all .entitlements files in the repository. In most projects the
# iPhone target’s entitlements live alongside the iOS app bundle, but we
# conservatively check every .entitlements file.
entitlement_files=$(find . -type f -name "*.entitlements")

if [[ -z "$entitlement_files" ]]; then
  echo "❌ No .entitlements files found in the project."
  exit 1
fi

found=0

# Iterate over each entitlements file and look for the CarPlay Maps key.
for file in $entitlement_files; do
  # Use PlistBuddy to safely query the plist. It returns a non‑zero exit
  # code if the key does not exist.
  if /usr/libexec/PlistBuddy -c "Print :com.apple.developer.carplay-maps" "$file" >/dev/null 2>&1; then
    found=1
    break
  fi
done

if [[ $found -eq 1 ]]; then
  echo "✅ CarPlay Maps entitlement (com.apple.developer.carplay-maps) found."
  exit 0
else
  echo "❌ CarPlay Maps entitlement (com.apple.developer.carplay-maps) missing."
  exit 1
fi