#!/bin/sh
# Quality gate: lint, unit tests, iOS build, UI smoke test, live API decode.
# OFFLINE=1 skips the live API step. ROTATE_SIM_ID adds the width change tests on that simulator (see below).
# Exits non-zero on the first failure.
set -eu
cd "$(dirname "$0")/.."
# Simulator: SIM_ID if set, else the first available "iPhone 17" by UDID (the name alone can match several).
SIM=${SIM_ID:-$(xcrun simctl list devices available -j | python3 -c '
import json, sys
ids = sorted(d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["name"] == "iPhone 17")
print(ids[0] if ids else "")')}
[ -n "$SIM" ] || { echo "error: no available iPhone 17 simulator found; set SIM_ID to a simulator UDID" >&2; exit 1; }
XB="xcodebuild -project Finlynq.xcodeproj -derivedDataPath build $(scripts/signing-flags.sh)"

echo "== swiftlint"; swiftlint --strict --quiet
echo "== xcodegen"; xcodegen generate --quiet
echo "== unit tests (macOS)"; $XB -scheme Finlynq -destination 'platform=macOS' -only-testing:FinlynqTests test -quiet
echo "== build (iPhone 17)"; $XB -scheme Finlynq -destination "platform=iOS Simulator,id=$SIM" build -quiet
echo "== UI smoke test (iPhone 17)"; $XB -scheme FinlynqUI -destination "platform=iOS Simulator,id=$SIM" test -quiet
# ROTATE_SIM_ID: an iPhone Pro Max or Plus, where turning the device swaps tabs for the sidebar. Runs the two
# width-change tests there; they skip on the iPhone 17 above. Off by default to spare a third simulator.
if [ -n "${ROTATE_SIM_ID:-}" ]; then
  echo "== width change tests ($ROTATE_SIM_ID)"
  $XB -scheme FinlynqUI -destination "platform=iOS Simulator,id=$ROTATE_SIM_ID" \
    -only-testing:FinlynqUITests/SmokeTests/testWidthChangeKeepsThePushedPage \
    -only-testing:FinlynqUITests/SmokeTests/testWidthChangeKeepsTheEditorDraft test -quiet
fi
if [ "${OFFLINE:-}" = 1 ]; then echo "== check-api skipped (OFFLINE=1)"; else echo "== check-api"; scripts/check-api.sh; fi
echo "All checks passed."
