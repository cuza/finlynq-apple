#!/bin/sh
# Prints extra xcodebuild settings for check.sh and screens.sh. It prints nothing when this Mac has a valid
# Apple Development identity whose certificate OU is the DEVELOPMENT_TEAM in Config/Local.xcconfig, so Xcode signs
# with the team. Otherwise, or when ADHOC=1 is set, it prints settings that sign ad-hoc and drop the team.
set -eu
cd "$(dirname "$0")/.."
TEAM=$( [ -f Config/Local.xcconfig ] && sed -n 's/^ *DEVELOPMENT_TEAM *= *\([A-Z0-9]*\).*/\1/p' Config/Local.xcconfig | head -n 1 || true)
if [ "${ADHOC:-}" != 1 ] && [ -n "$TEAM" ] && command -v security >/dev/null; then
  for hash in $(security find-identity -v -p codesigning | awk '/"Apple Development: /{print $2}'); do
    if security find-certificate -a -Z -p -c "Apple Development" |
      awk -v h="$hash" '/^SHA-1 hash:/{p = ($3 == h); next} /^SHA-256 hash:/{next} p' |
      openssl x509 -noout -subject 2>/dev/null | grep -Eq "[/, ]OU ?= ?$TEAM([,/]|$)"; then
      exit 0
    fi
  done
fi
echo "CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM="
