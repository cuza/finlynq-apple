#!/bin/sh
# Signs in to a Finlynq server, saves each response the app reads, and decodes them
# with the app's models. Fails when the server's JSON no longer matches.
# Usage: scripts/check-api.sh [--save dir] [server] [username] [password]   (defaults: the public demo)
# --save keeps the responses in dir, named after the API path without the query:
# /api/dashboard -> dashboard.json, /api/budgets/month -> budgets-month.json,
# /api/auth/session -> session.json (the "auth/" prefix is dropped).
# Two names carry an id that the demo picks (a staged batch and a holding): import-staged-<uuid>.json
# and portfolio-holdings-<id>-lots.json. --save replaces the previous copies of those.
# Fixtures/overlays holds hand-made files that the app reads instead of the saved file of the same name
# (budgets-month.json and subscriptions.json, because the demo has no spending budget or bills due soon; the three
# reconcile-*.json files, because the demo bank ledger is empty; reports-trends.json, converted to the saved
# fixtures' display currency and category ids).
# --save never writes there; after a --save, check the overlays still match the saved files' shape.
set -eu
SAVE=
if [ "${1:-}" = "--save" ]; then SAVE=${2:?--save needs a directory}; shift 2; fi
SERVER=${1:-https://finlynq.com}
USER=${2:-demo}
PASS=${3:-finlynq-demo}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
if [ -n "$SAVE" ]; then mkdir -p "$SAVE"; SAVE=$(cd "$SAVE" && pwd); fi

curl -sf -c "$OUT/jar" -H 'Content-Type: application/json' \
  -d "{\"identifier\":\"$USER\",\"password\":\"$PASS\"}" "$SERVER/api/auth/login" >/dev/null
TOKEN=$(awk '/pf_session/ {print $7}' "$OUT/jar")
get() { curl -sf -H "Authorization: Bearer $TOKEN" "$SERVER$2" > "$OUT/$1"; }

get session.json /api/auth/session
get dashboard.json /api/dashboard
get accounts.json /api/accounts
get categories.json /api/categories
get transactions.json "/api/transactions?limit=50"
get search.json "/api/transactions?limit=5&search=a"
get budgets-month.json /api/budgets/month
get portfolio-overview.json /api/portfolio/overview
get portfolio.json /api/portfolio
get net-worth-history.json "/api/net-worth-history?period=1y"
get spotlight.json /api/spotlight
get subscriptions.json /api/subscriptions
get recurring.json /api/recurring
get goals.json /api/goals
get fx.json "/api/fx?target=INR"
get loans.json /api/loans
get rules.json /api/rules
get user-me.json /api/user/me
get settings-display-currency.json /api/settings/display-currency
get import-email-config.json /api/import/email-config
get settings-active-currencies.json /api/settings/active-currencies
get settings-bank-feeds-simplefin-status.json /api/settings/bank-feeds/simplefin/status
get settings-fx-rate-view.json /api/settings/fx-rate-view
get portfolio-dividends.json "/api/portfolio/dividends?taxYear=2026"
get portfolio-realized-gains.json "/api/portfolio/realized-gains?taxYear=2026"
get portfolio-performance.json "/api/portfolio/performance?period=1y"
get portfolio-performance-holdings.json "/api/portfolio/performance/holdings?period=1y"
get reports.json "/api/reports?type=income-statement&startDate=2026-01-01&endDate=2026-12-31"
get reports-trends.json "/api/reports/trends?endDate=2026-12-31&period=monthly&startDate=2025-12-01"
get import-staged.json /api/import/staged
get reconcile-summary.json /api/reconcile/summary
# Ids the demo picks: the first pending batch, and the first holding that has shares.
pick() { python3 -c "import json,sys; d=json.load(open('$OUT/$1')); print($2)"; }
TX=$(pick transactions.json "d['data'][0]['id']")
get transactions-splits.json "/api/transactions/splits?transactionId=$TX"
BATCH=$(pick import-staged.json "d[0]['id'] if d else ''")
ACCOUNT=$(pick accounts.json "next((a['id'] for a in d if not a.get('isInvestment')), '')")
get reconcile-suggestions.json "/api/reconcile/suggestions?accountId=$ACCOUNT"
get reconcile-balance-summary.json "/api/reconcile/balance-summary?accountId=$ACCOUNT"
HOLDING=$(pick portfolio.json "next((h['id'] for h in d if h.get('currentShares')), '')")
[ -n "$BATCH" ] && get "import-staged-$BATCH.json" "/api/import/staged/$BATCH" && cp "$OUT/import-staged-$BATCH.json" "$OUT/import-staged-detail.json"
[ -n "$HOLDING" ] && get "portfolio-holdings-$HOLDING-lots.json" "/api/portfolio/holdings/$HOLDING/lots" && cp "$OUT/portfolio-holdings-$HOLDING-lots.json" "$OUT/holding-lots.json"

swiftc -parse-as-library -o "$OUT/check" \
  "$ROOT"/Finlynq/API/Models/*.swift "$ROOT/Finlynq/Shared/Format.swift" "$ROOT/scripts/DecodeCheck.swift"
"$OUT/check" "$OUT"

if [ -n "$SAVE" ]; then
  for f in session dashboard accounts categories transactions budgets-month portfolio-overview net-worth-history \
    spotlight fx subscriptions recurring goals loans rules user-me settings-display-currency import-email-config \
    transactions-splits portfolio-dividends portfolio-realized-gains reports reports-trends import-staged \
    reconcile-summary reconcile-suggestions reconcile-balance-summary portfolio-performance portfolio-performance-holdings \
    settings-active-currencies settings-bank-feeds-simplefin-status settings-fx-rate-view; do
    cp "$OUT/$f.json" "$SAVE/$f.json"
  done
  if [ -n "$BATCH" ]; then rm -f "$SAVE"/import-staged-*-*.json; cp "$OUT/import-staged-$BATCH.json" "$SAVE/"; fi
  if [ -n "$HOLDING" ]; then rm -f "$SAVE"/portfolio-holdings-*-lots.json; cp "$OUT/portfolio-holdings-$HOLDING-lots.json" "$SAVE/"; fi
fi
