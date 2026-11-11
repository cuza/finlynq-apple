#!/bin/sh
# Screenshots app screens in fixture mode next to their designs, for design fidelity reviews.
#
#   scripts/screens.sh [--platform iphone|ipad|ipadp|mac|all] [--appearance light|dark|both] <route>...
#
# Routes are the FINLYNQ_ROUTE values in Finlynq/App/DebugRoute.swift: home, activity, budget, bills, goals,
# accounts, investments, debts, insights, review, calendar, statement, netWorth, tax, settings, signin, setup, applepay,
# add, add-invest, import, categories, categories:<id>, categories-refused:<id>, transaction:<id>, loan:<id>, account:<id>, goal:<id>, category:<id>, holding:<symbol>.
# Fixture ids: transaction 291947, loan 267, account 4100, goal 713, category 8486. Writes, all git-ignored:
#   screens/design/<Design>.png                          docs/design/<Design>.dc.html rendered by headless Chrome
#   screens/app/<platform>-<route>-<appearance>.png      the app in the simulator (iPhone 17, iPad) or the Mac window
#   screens/compare/<platform>-<route>-<appearance>.html and .png   design left, app right, same scale
# A route's design is <Design> for iPhone, iPad<Design> for iPad and Mac<Design> for Mac (see design_for),
# when that file exists. Without one, the compare page shows the app alone. ipadp is the iPad in portrait with the
# sidebar open, compared with iPadP<Design>; it shuts a landscape iPad down first so it boots upright.
# Each capture waits for the app's FINLYNQ_READY line, then for two identical frames in a row, and rejects
# a frame that is nearly one color. A failed capture is retried once, then skipped; the script then ends
# with a list of failures and exit status 1.
# Simulators: SIM_ID (default: the first "iPhone 17") and IPAD_SIM_ID (default: the first iPad Pro 11-inch,
# else iPad Air 11-inch, else any iPad). The iPad is turned to landscape to match its designs.
# The Mac capture uses `screencapture -l`, which needs Screen Recording permission for the terminal. It draws
# as an active window only when macOS lets the launched app take focus (not while you type in another app).
set -eu
cd "$(dirname "$0")/.."

PLATFORMS="iphone ipad mac"
APPEARANCES="light dark"
ROUTES=""
while [ $# -gt 0 ]; do
  case $1 in
    --platform) [ "$2" = all ] || PLATFORMS=$2; shift 2 ;;
    --appearance) [ "$2" = both ] || APPEARANCES=$2; shift 2 ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    *) ROUTES="$ROUTES $1"; shift ;;
  esac
done
[ -n "$ROUTES" ] || { echo "usage: scripts/screens.sh [--platform iphone|ipad|mac|all] [--appearance light|dark|both] <route>..." >&2; exit 1; }
for route in $ROUTES; do
  echo "$route" | grep -Eq '^(home|activity|budget|bills|goals|accounts|investments|debts|insights|review|calendar|statement|netWorth|tax|settings|signin|setup|applepay|add|add-invest|import|(settings-)?categories(:[0-9]+)?|categories-refused:[0-9]+|(transaction|loan|account|goal|category):[0-9]+|holding:[A-Za-z0-9._-]+)$' ||
    { echo "error: unknown route '$route' (see scripts/screens.sh --help)" >&2; exit 2; }
done

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
XB="xcodebuild -project Finlynq.xcodeproj -derivedDataPath build $(scripts/signing-flags.sh)"
BUNDLE=dev.cuza.finlynq
FAILED=""
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p screens/design screens/app screens/compare

# Headless Chrome screenshot of a page: chrome_shot <url> <width> <height> <scale> <out.png>
# Chrome can exit non-zero on teardown after writing the file, so success is a fresh non-empty file.
chrome_shot() {
  rm -f "$5"
  "$CHROME" --headless --disable-gpu --hide-scrollbars --user-data-dir="$TMP/chrome" --virtual-time-budget=3000 \
    --force-device-scale-factor="$4" --window-size="$2,$3" --screenshot="$5" "$1" >/dev/null 2>&1 || [ -s "$5" ]
}

# Design file name (without .dc.html) for a route on a platform, or nothing.
design_for() {
  case $2 in
    home) base=Home ;; activity) base=Activity ;; add) base=Add ;; add-invest) base=Invest ;; review) base=Review ;;
    import) base=Import ;; categories) base=CategoriesList ;; categories:*) base=CategoryEditor ;;
    categories-refused:*) base=CategoryDeleteBlocked ;;
    calendar) base=Calendar ;; budget) base=Plan ;; bills) base=Bills ;; goals) base=Goals ;;
    accounts) base=Wealth ;; investments) base=Investments ;; debts) base=Debts ;; insights) base=Insights ;;
    statement) base=Statement ;; netWorth) base=NetWorth ;; tax) base=Tax ;; settings) base=Settings ;;
    signin) base=SignIn ;; setup) base=Setup ;; applepay) base=ApplePay ;;
    transaction:*) base=Transaction ;; loan:*) base=Loan ;; account:*) base=Account ;; goal:*) base=Goal ;;
    category:*) base=Category ;; holding:*) base=Holding ;;
    *) return 0 ;;
  esac
  # The iPad portrait board for the Wealth tab is named after its sidebar row, Accounts.
  [ "$1" = ipadp ] && [ "$base" = Wealth ] && base=Accounts
  case $1 in iphone) name=$base ;; ipad) name=iPad$base ;; ipadp) name=iPadP$base ;; mac) name=Mac$base ;; esac
  [ -f "docs/design/$name.dc.html" ] && echo "$name"
  return 0
}

# Point size of a platform's design canvas.
size_for() { case $1 in iphone) echo "390 844" ;; ipad) echo "1194 834" ;; ipadp) echo "820 1180" ;; mac) echo "1440 900" ;; esac; }

first_sim() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = [d for ds in json.load(sys.stdin)["devices"].values() for d in ds]
for prefix in sys.argv[1:]:
    ids = sorted(d["udid"] for d in devices if d["name"] == prefix or d["name"].startswith(prefix + " ("))
    if ids:
        print(ids[0]); break' "$@"
}

# Waits up to 30 s for the app to log that the route's screen is up: wait_ready <log>
wait_ready() {
  for _ in $(seq 60); do
    grep -q FINLYNQ_READY "$1" 2>/dev/null && return 0
    sleep 0.5
  done
  return 1
}

# Runs a capture command (called with an output path) until two captures in a row are identical, so the
# screen has finished loading: settle <out.png> <command...>. Gives up after about 20 s and keeps the last one.
settle() {
  out=$1
  shift
  sleep 1
  "$@" "$TMP/prev.png"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 2
    "$@" "$out"
    cmp -s "$out" "$TMP/prev.png" && return
    mv "$out" "$TMP/prev.png"
  done
  mv "$TMP/prev.png" "$out"
}

# Succeeds when a screenshot is nearly one color, like a blank or launch screen: more than 97% of a 64x64
# thumbnail within 12 levels of its most common color. A real screen, even an empty placeholder, scores lower.
is_blank() {
  sips -s format bmp -z 64 64 "$1" --out "$TMP/thumb.bmp" >/dev/null 2>&1
  python3 -I - "$TMP/thumb.bmp" <<'PY'
import collections, struct, sys
data = open(sys.argv[1], "rb").read()
offset, = struct.unpack_from("<I", data, 10)
w, h = struct.unpack_from("<ii", data, 18)
step = struct.unpack_from("<H", data, 28)[0] // 8
row = (w * step + 3) & ~3
px = [data[offset + y * row + x * step:offset + y * row + x * step + 3] for y in range(abs(h)) for x in range(w)]
common = collections.Counter(px).most_common(1)[0][0]
near = sum(all(abs(a - b) <= 12 for a, b in zip(p, common)) for p in px) / len(px)
sys.exit(0 if near > 0.97 else 1)
PY
}

sim_capture() { xcrun simctl io "$SIM" screenshot "$1" >/dev/null 2>&1; }

# One simulator capture: sim_once <route> <appearance> <out>. Sets REASON when it fails.
sim_once() {
  : > "$TMP/app.log"
  SIMCTL_CHILD_FINLYNQ_FIXTURES=1 SIMCTL_CHILD_FINLYNQ_ROUTE=$1 SIMCTL_CHILD_FINLYNQ_APPEARANCE=$2 \
    xcrun simctl launch --console-pty --terminate-running-process "$SIM" $BUNDLE >"$TMP/app.log" 2>&1 &
  console=$!
  if ! wait_ready "$TMP/app.log"; then
    REASON="the app never logged FINLYNQ_READY"
  else
    settle "$3" sim_capture
    if is_blank "$3"; then REASON="the screenshot is blank"; fi
  fi
  xcrun simctl terminate "$SIM" $BUNDLE >/dev/null 2>&1 || true
  wait "$console" 2>/dev/null || true
}

prepare_sim() {
  xcrun simctl boot "$1" 2>/dev/null || true
  xcrun simctl bootstatus "$1" -b >/dev/null
  xcrun simctl install "$1" build/Build/Products/Debug-iphonesimulator/Finlynq.app
  xcrun simctl status_bar "$1" override --time 9:41 --batteryState charged --batteryLevel 100 >/dev/null 2>&1 || true
}

# simctl can't rotate a device, so a UI test (FinlynqUITests/RotateTests) turns a portrait iPad to landscape.
# The device keeps that orientation until it shuts down.
rotate_landscape() {
  sim_capture "$TMP/orientation.png"
  w=$(sips -g pixelWidth "$TMP/orientation.png" | awk '/pixelWidth/ { print $2 }')
  h=$(sips -g pixelHeight "$TMP/orientation.png" | awk '/pixelHeight/ { print $2 }')
  [ "$w" -gt "$h" ] && return 0
  echo "== ipad: rotate to landscape"
  TEST_RUNNER_FINLYNQ_ROTATE=1 $XB -scheme FinlynqUI -destination "platform=iOS Simulator,id=$1" \
    -only-testing:FinlynqUITests/RotateTests test -quiet >/dev/null
}

# A device keeps its orientation until it shuts down, so a landscape iPad is restarted to come back upright.
boot_portrait() {
  sim_capture "$TMP/orientation.png"
  w=$(sips -g pixelWidth "$TMP/orientation.png" | awk '/pixelWidth/ { print $2 }')
  h=$(sips -g pixelHeight "$TMP/orientation.png" | awk '/pixelHeight/ { print $2 }')
  [ "$w" -lt "$h" ] && return 0
  echo "== ipadp: restart in portrait"
  xcrun simctl shutdown "$1"
  prepare_sim "$1"
}

# On-screen window id of a process, waiting up to 10 s for it to appear.
window_id() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    wid=$(PID=$1 swift - <<'EOF' 2>/dev/null
import CoreGraphics
import Foundation
let pid = Int(ProcessInfo.processInfo.environment["PID"]!)!
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
if let window = windows.first(where: { $0[kCGWindowOwnerPID as String] as? Int == pid && $0[kCGWindowLayer as String] as? Int == 0 }) {
    print(window[kCGWindowNumber as String]!)
}
EOF
)
    [ -n "$wid" ] && { echo "$wid"; return; }
    sleep 1
  done
}

# One Mac capture: mac_once <route> <appearance> <out>. Sets REASON when it fails.
mac_once() {
  : > "$TMP/app.log"
  # Launch through LaunchServices so the app can become active: an inactive window draws grey controls.
  # macOS refuses when you are typing in another app at that moment; the capture then shows the inactive look.
  app="$PWD/build/Build/Products/Debug/Finlynq.app"
  open -n -a "$app" --stderr "$TMP/app.log" --env FINLYNQ_FIXTURES=1 --env "FINLYNQ_ROUTE=$1" \
    --env "FINLYNQ_APPEARANCE=$2" --env FINLYNQ_WINDOW=1440x900 --args -ApplePersistenceIgnoreState YES
  pid=""
  for _ in $(seq 20); do
    pid=$(pgrep -n -f "$app/Contents/MacOS/Finlynq") && break
    sleep 0.5
  done
  wid=""
  [ -n "$pid" ] && wid=$(window_id "$pid")
  if [ -z "$wid" ]; then
    REASON="no Finlynq window found"
  elif ! wait_ready "$TMP/app.log"; then
    REASON="the app never logged FINLYNQ_READY"
  else
    settle "$3" screencapture -x -o -l "$wid"
    size=$(sips -g pixelWidth -g pixelHeight "$3" | awk '/pixel/ { printf "%s ", $2 }')
    case $size in
      "2880 1800 "|"1440 900 ") if is_blank "$3"; then REASON="the screenshot is blank"; fi ;;
      *) REASON="the window was captured at $size pixels, not 1440x900 points" ;;
    esac
  fi
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
  fi
}

# Captures the app, retrying once: capture <platform> <route> <appearance> <out>. On failure nothing is written.
capture() {
  for attempt in 1 2; do
    REASON=""
    rm -f "$4"
    if [ "$1" = mac ]; then mac_once "$2" "$3" "$4"; else sim_once "$2" "$3" "$4"; fi
    [ -z "$REASON" ] && return 0
    echo "warning: $1 $2 $3: $REASON (attempt $attempt of 2)" >&2
  done
  rm -f "$4"
  FAILED="$FAILED
  $1 $2 $3: $REASON"
  return 1
}

# Side-by-side page and PNG: compare <platform> <design name or empty> <app png> <out base>
compare() {
  # shellcheck disable=SC2046 # split "W H" into two arguments
  set -- "$1" "$2" "$3" "$4" $(size_for "$1")
  width=$(sips -g pixelWidth "$3" | awk '/pixelWidth/ { print $2 }')
  case $1 in iphone) scale=3 ;; ipad|ipadp) scale=2 ;; mac) scale=$((width / 1440)) ;; esac
  app_w=$((width / scale))
  height=$(sips -g pixelHeight "$3" | awk '/pixelHeight/ { print $2 / '"$scale"' }')
  fig=""
  [ -n "$2" ] && fig="<figure><figcaption>Design: $2</figcaption><img src=\"../design/$2.png\" width=\"$5\"></figure>"
  cat > "$4.html" <<EOF
<!doctype html><meta charset="utf-8"><title>$(basename "$4")</title>
<style>body{margin:0;padding:16px;background:#888;font:600 14px -apple-system,sans-serif;display:flex;gap:16px;align-items:flex-start}
figure{margin:0}figcaption{margin-bottom:8px;color:#fff}img{display:block}</style>
$fig<figure><figcaption>App: $(basename "$3")</figcaption><img src="../app/$(basename "$3")" width="$app_w"></figure>
EOF
  if [ -n "$2" ]; then
    page_w=$(($5 + app_w + 48))
    page_h=$(awk "BEGIN { h = $6 > $height ? $6 : $height; print int(h) + 64 }")
  else
    page_w=$((app_w + 32))
    page_h=$(awk "BEGIN { print int($height) + 64 }")
  fi
  chrome_shot "file://$PWD/$4.html" $page_w "$page_h" 1 "$4.png"
  echo "$4.png"
}

for platform in $PLATFORMS; do
  case $platform in
    iphone)
      SIM=${SIM_ID:-$(first_sim "iPhone 17")}
      [ -n "$SIM" ] || { echo "error: no iPhone 17 simulator; set SIM_ID" >&2; exit 1; } ;;
    ipad|ipadp)
      SIM=${IPAD_SIM_ID:-$(first_sim "iPad Pro 11-inch" "iPad Air 11-inch" "iPad")}
      [ -n "$SIM" ] || { echo "error: no iPad simulator; set IPAD_SIM_ID" >&2; exit 1; } ;;
    mac) SIM="" ;;
    *) echo "error: unknown platform $platform" >&2; exit 1 ;;
  esac
  echo "== $platform: build"
  if [ "$platform" = mac ]; then
    $XB -scheme Finlynq -destination 'platform=macOS' build -quiet
  else
    $XB -scheme Finlynq -destination "platform=iOS Simulator,id=$SIM" build -quiet
    prepare_sim "$SIM"
    [ "$platform" = ipad ] && rotate_landscape "$SIM"
    [ "$platform" = ipadp ] && boot_portrait "$SIM"
  fi
  for route in $ROUTES; do
    design=$(design_for "$platform" "$route")
    if [ -n "$design" ]; then
      # shellcheck disable=SC2046 # split "W H" into two arguments
      set -- $(size_for "$platform")
      chrome_shot "file://$PWD/docs/design/$design.dc.html" "$1" "$2" 2 "screens/design/$design.png"
      echo "screens/design/$design.png"
    fi
    for appearance in $APPEARANCES; do
      name="$platform-$(echo "$route" | tr ':' '-')-$appearance"
      out="screens/app/$name.png"
      rm -f "screens/compare/$name.html" "screens/compare/$name.png"
      if capture "$platform" "$route" "$appearance" "$out"; then
        echo "$out"
        compare "$platform" "$design" "$out" "screens/compare/$name"
      fi
    done
  done
done

if [ -n "$FAILED" ]; then
  echo "error: these captures failed and have no app screenshot or compare page:$FAILED" >&2
  exit 1
fi
