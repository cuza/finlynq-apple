# Wealth views inventory (accounts, portfolio, loans)

Source: `src/app/(app)/<route>/page.tsx` plus the components each one imports. All seven routes are `mode: "prod"` in `src/components/nav.tsx` (Accounts, Portfolio, Loans & Debt are nav items; the portfolio sub-routes are linked from the Portfolio header). Dev-only parts inside these pages are gated by `useDevMode()` and are marked below.

Legend: **[core]** used weekly, **[power]** power-user, **[clutter]** candidate to cut or hide, **[dev]** dev-mode only.

---

## /accounts

Purpose: the list of every account, grouped by asset/liability and by group, with totals.

### Sections, top to bottom
- Onboarding tips banner (`OnboardingTips page="accounts"`). [clutter after first week]
- Header: title, subtitle, buttons "Manage groups", "Show/Hide archived", "Create Account".
- Two totals tiles: Total Assets, Total Liabilities, in display currency. Totals always include archived accounts. No net-worth tile on this page despite the subtitle. [core]
- Two columns: Assets and Liabilities. Each holds one card per account group. Group order comes from the user's saved order ("Other" always last). Account order inside a group follows Settings > Dropdown ordering, then name.
  - Account row: initial avatar, name, alias in parentheses, currency badge, "Archived" badge, balance in the account's own currency, and the display-currency equivalent beneath when the currencies differ. Negative balances in red. Row taps through to `/accounts/[id]`. [core]
  - Optional "Loan" link button per row when a loan is linked to that account (goes to `/loans?loan=<id>`). [power]
- Empty state: "No accounts yet" with an "Import data" link.

### User actions
- Create account: `AccountDialog` (mode create). Fields:
  - Account Name (required), Alias (optional, max 64, warns on clash with another account's name or alias), Type (Asset/Liability, changing it resets Group), Group (free-text combobox `GroupField` seeded with defaults plus existing groups), Currency (searchable combobox, active currencies), Note (optional).
  - Opening balance block (hidden when Investment is checked): Amount, Date.
  - "Investment account" checkbox (forces every transaction to reference a holding or the Cash sleeve).
  - Header link "Connect your bank" to `/settings/bank-feeds`.
  - Retry-safe: a failed opening-balance save does not create a duplicate account.
- Manage groups: `ManageGroupsDialog`. Per type (Asset/Liability) list of groups with: move up, move down, rename inline (save/cancel), "Merge into Other" (behind a confirm dialog). [power]
- Show/hide archived toggle (list filter only). [power]
- No edit, delete, sort or bulk actions on this page. Edit lives on the detail page.

### API
- `GET /api/dashboard?currency=` (balances; this page reuses the dashboard endpoint)
- `GET|PUT /api/settings/account-group-order`
- `PATCH /api/accounts/groups` (rename, merge)
- `POST /api/accounts`
- `GET|PUT /api/accounts/[id]/opening-balance`
- `GET /api/loans` (via `useLinkedLoans`, for the per-row Loan link)

### Judgement
- Core: grouped list with native and converted balances, totals, create account.
- Power: manage groups, show archived, loan links.
- Clutter: onboarding tips; the two-button header could fold into one "..." menu. Dead constants `ACCOUNT_TYPES` / `ACCOUNT_GROUPS` in `page.tsx` are unused.
- Native note: add a net-worth figure (assets minus liabilities); the subtitle promises it and it is missing.

---

## /accounts/[id]

Purpose: one account's balance, balance history, and its full transaction list, plus the account's settings.

### Sections, top to bottom
- "Back to Accounts" link.
- Header: avatar initial, name, badges (currency, Asset/Liability, Investment, Archived, Loan).
- Quick actions (right side):
  - Non-investment accounts: "New transaction" button opens the shared `TransactionDialog` with this account preselected (Transfer tab seeded with this account as the source). [core]
  - "Investment transaction" dropdown. Investment accounts list all 8 portfolio ops (Buy, Sell, Swap, In-kind transfer, Deposit, Withdrawal, Income / expense, FX conversion). Normal accounts list only Deposit and Withdrawal ("Brokerage cash move"). Each navigates to `/portfolio/new?op=<op>&account=<id>[&accountField=dest]`. [core for investment accounts]
  - "View loan" button per linked loan. [power]
  - "Edit" button. [core]
- Three stat tiles:
  - Balance, or "Market value" when the account holds securities. Investment accounts also show "Cash flow: <sum of transactions>". [core]
  - Group name. [clutter]
  - Transaction count. [clutter]
- Balance Over Time chart (`NetWorthHistoryChart`, area chart). Period buttons 6M / 1Y / ALL. Native vs reporting currency basis toggle (shown only when they differ). The stacked by-account toggle is hidden on single-account charts. [core]
- Transactions: the full `TransactionsWorkspace` from `/transactions`, locked to this account (account filter forced and hidden, no URL sync). It brings filters (date range, category, search, holding, tag, id), per-column filters, column customize, header sort, list/calendar view, inline edit, multi-select bulk actions (set category, account, date, note, payee, tags, bulk delete with confirm), CSV export of the filtered set, and pagination. Inventory that surface with the Transactions route. [core]

### Dialogs
- Edit account: `AccountDialog` (mode edit) with tabs:
  - Details: same fields as Create (name, alias, type, group, currency, note, opening balance amount + date for cash accounts, investment checkbox). Footer: Save Changes. "Account actions" block: "Archive or delete account" (one smart action: hard delete if empty, archive if referenced), or "Unarchive" + "Delete" when archived. Confirm dialog "Remove account". [core for edit, power for archive]
  - Reconciliation: `ModePicker` with three upload-pipeline modes (Auto-pilot, Approve-each, Manual review). [power]
  - Import: `ImportPrefsPicker`. CSV mapping mode ("Ask me to confirm first" / "Apply automatically") and OFX payee source ("Name field" / "Memo field"). [power]
  - Cash sleeves: table (Currency, Name, Transactions count, Delete). "Add sleeve" opens "Add cash sleeve" dialog (Currency combobox). Delete is disabled while the sleeve has transactions, and confirms through "Delete cash sleeve". [power; arguably should be automatic]
  - Deep links: `#reconciliation-mode` and `#import-prefs` open the dialog on that tab.
- New transaction: shared `TransactionDialog` (categories and holdings load lazily on first open).

### API
- `GET /api/accounts?includeArchived=1`
- `GET /api/dashboard` (balance, cashFlowBasis, holdingsValue)
- `GET /api/transactions?accountId=&limit=1` (count only)
- `GET /api/transactions?portfolioHoldingId=&limit=1` (once per cash sleeve, N+1)
- `GET /api/portfolio` (sleeves and dialog holdings)
- `POST|DELETE /api/portfolio/holdings/cash-sleeve`
- `GET /api/categories`
- `PUT|DELETE /api/accounts` (edit, archive, unarchive, delete)
- `GET|PUT /api/accounts/[id]/opening-balance`
- `PUT /api/accounts/[id]/mode`
- `PUT /api/accounts/[id]/import-prefs`
- `GET /api/net-worth-history?accountId=&period=&basis=`
- `GET /api/loans` (linked loans)
- Plus everything `TransactionsWorkspace` and `TransactionDialog` call (`/api/transactions` and related).

### Judgement
- Core: balance header, balance chart, transaction list, New transaction, Edit details.
- Power: investment op menu on normal accounts (only Deposit/Withdrawal), Reconciliation and Import tabs, cash sleeves, archive/delete.
- Clutter: Group and Transactions-count tiles; Reconciliation and Import tabs belong in an account settings sheet, not next to the main edit form.
- Native note: the sleeve count fetch is N+1; ask for a server-side count.

---

## /portfolio

Purpose: investment overview. Performance, P&L, every holding (rolled up by ticker), allocation, and per-account holdings.

### Sections, top to bottom
- Header: title, "N holdings across M accounts". Buttons: "Realized gains", "Dividends", "Add holding" (links to `/settings/investments`; no inline create).
- Performance chart (`PerformanceChart`). [core]
  - Line chart of market value and cost basis; "Lines" toggle: Value & cost / Value / Cost.
  - Periods: 1M, 3M, 6M, YTD, 1Y, ALL.
  - Stack toggles: "By holding (value)" and "By account" switch to a stacked area chart of the top 10 members.
  - Header badges: TWRR (period), TWRR (annualized), MWRR (XIRR, only if it converged), Net new money (deposits/withdrawals in period), "Incomplete history: N days filled".
  - Empty state mentions the nightly snapshot cron and a backfill script. [dev wording leaks into prod]
- Warning banner when some transactions could not be decrypted ("Sign in again"). [edge case]
- Four hero tiles: Total Holdings (count, accounts), Day Change (% and amount), ETFs/Stocks (counts), Crypto (count, plus cash position count). [Day Change core; the three count tiles are clutter]
- Investment Returns card (shown when cost basis exists): Market Value, Cost Basis, Unrealized G/L ($ and %), Realized G/L, Dividends, Total Return ($ and %). [core]
- Top Gainers and Top Losers cards: logo, symbol, name, day change % and amount. [power; nice glance]
- All Holdings table (`HoldingsTable`). [core]
  - Subtitle "Live prices from Yahoo Finance & CoinGecko" and `CostBasisNote` (one line naming the cost-basis method: simple average or lot allocation; opens an explainer that links to the setting).
  - Filter chips by asset type with counts: All, ETFs, Stocks, Crypto, Cash, Metals.
  - Toggles: "Hiding empty / Showing all" (default hides zero-qty), "In <display ccy> / Holding currency".
  - CSV export of the rolled-up rows.
  - Columns (all sortable, default Market value desc): Name (symbol badge, asset-type badge, Short badge), Qty, Avg Cost, Price, Mkt Value, Cost, Day Chg $, Day Chg %, Unrealized $, Unrealized %, Realized, Accounts (count).
  - Row expands to: info grid (First purchase, Days held, % of portfolio, Cost basis, Dividends, Total return), then a per-account sub-table (Account, Qty, Avg Cost, Mkt Value, Unrealized G/L, Realized G/L) with per-row actions: edit holding (click the account name), "Lots" (Lot inspector), "Transactions" (drill to `/transactions` filtered by holding and account). Footer link "View transactions" for the whole ticker.
- ETF X-Ray card. **[dev]** Tabs: Stocks (look-through table: #, Stock, Ticker, Sector, Country, Weight, Value, Exposure bar, Via ETFs; paginated 25/page; CSV), Regions (pie), Sectors (pie), Per ETF (table: ETF, Fund Name, Account, Holdings, Portfolio Weight).
- Allocation charts: two donut/pie charts, "By Asset Type" and "By Account", with legend amounts and %. [core]
- Performance vs Benchmarks line chart. **[dev]** Periods YTD, 1Y, 3Y, 5Y.
- Holdings by Account card (`HoldingsByAccount`): own hide-empty toggle. Collapsible row per account: name, holding count, hidden count, type counts (ETFs, stocks, crypto, cash, metals), Mkt Value, Unrealized, Realized. Expanded table: Holding (Short badge), Qty, Avg Cost, Price, Mkt Value, Unrealized G/L, Day Chg, Transactions link. [power; duplicates the All Holdings expand]

### Dialogs
- Edit Holding (`HoldingEditForm`): Name, Account (select), Symbol / ticker (accepts ticker, ISIN or currency code; live lookup resolves ISIN to a Yahoo symbol and fills the name), Holding currency, "Crypto" checkbox, Note. Footer: Delete (inline confirm "Delete holding"; transactions stay but stop aggregating), Cancel, Save. [power]
- Lot inspector (`LotInspectorDialog`), per holding per account. [power]
  - Lists each lot: Lot #, side (long/short), origin, status, open date, remaining/original qty, cost per share. Under each lot, its closures: kind (sell, transfer, etc.), tx #, close date, qty, proceeds/share, realized gain, ⚠ when the lot opened after the close.
  - "Edit allocation" per sell closure: lot picker with per-lot qty inputs (including used-up lots and a "Sold short" row), running total vs sale qty, "Preview" (restated realized gain and opened shorts) then "Save".
  - "Edit all allocations": full-screen matrix (`LotAllocationMatrix`) of sales x buys with per-cell qty, Auto fill buttons (FIFO, HIFO, LIFO, Current), filters by sale year or date range and buy year or date range, "Clear all", "Save allocation".
  - "Rebuild lots": confirm dialog, replays the ticker's transactions in date order; shows lots, closures and transactions processed plus warnings.

### API
- `GET /api/portfolio/overview?currency=`
- `GET /api/portfolio/performance?…` and `GET /api/portfolio/performance/holdings?…`
- `GET /api/portfolio/benchmarks?period=` (dev only)
- `GET|PUT /api/settings/lot-allocation` (cost-basis note)
- Holding edit: `GET /api/accounts`, `GET|PUT|DELETE /api/portfolio`, `GET /api/portfolio/symbol-info?symbol=&crypto=`
- Lots: `GET /api/portfolio/holdings/[holdingId]/lots?accountId=`, `POST …/lots/reassign` (preview and commit), `POST …/lots/allocate`, `POST …/lots/rebuild`

### Judgement
- Core: Performance chart (value line + period + TWRR), Investment Returns strip, All Holdings table (name, qty, price, value, day change, unrealized), allocation by type, Day Change.
- Power: Lot inspector and allocation matrix, Edit holding, native-currency toggle, CSV, Top movers, per-account sub-tables, stacked performance modes, MWRR.
- Clutter: three count tiles (Total Holdings, ETFs/Stocks, Crypto); Holdings by Account card duplicates the expand region of All Holdings (one of the two can go; a native app can offer "Group by account" as a toggle); 12 sortable columns are too many for iPhone (keep 4 to 5, rest in detail view); decrypt banner; snapshot-cron empty-state wording.
- Dev: ETF X-Ray, Performance vs Benchmarks.

---

## /portfolio/new

Purpose: record a portfolio operation. A chooser of 8 tiles, or the chosen form when `?op=` is set.

### Chooser
- Title "New portfolio operation", link back to Portfolio.
- 8 tiles (title + one-line description): Buy, Sell, Swap, In-kind transfer, Income / expense, FX conversion, Deposit, Withdrawal.

### Forms (each is a card; title switches to "Edit <op>" when `?editId=` is present; deep-link params `account` and `accountField` preselect an account; empty states when the user lacks the needed account types; submit returns to `/transactions`)
- Buy [core]: Account (investment), Holding, Quantity, Total cost (holding currency), Date, Payee, Note, Tags. Debits the matching cash sleeve.
- Sell [core]: Account, Holding, Quantity to sell, Total proceeds, Date, Payee, Note, Tags. Checkbox "Choose specific lots (advanced)" shows `LotPicker` (each open lot: open date, open qty, cost/share, qty input; qty becomes the sum of selected lots; default FIFO). Overselling opens a short.
- Swap [power]: Account, Source holding (sell), Destination holding (buy), Source qty, Source proceeds, Destination qty, Destination cost, Date, Payee, Note.
- In-kind transfer [power]: Source account, Destination account, Holding (from source account), Quantity, Date, Payee, Note. Keeps lot cost basis.
- Income / expense [core, dividends]: Account, Direction (Income + / Expense −), Settle into (Cash sleeve / Holding shares), Quantity (shares, when settling into shares), Currency / cash sleeve, Entry type (Income: Dividend, Interest, Other income; Expense: Fee, Other expense), Amount (or "Dollar value" in shares mode), Date, Related holding (optional; "Holding to receive shares" in shares mode), Category (optional), Payee, Note, Tags.
- FX conversion [power]: Account, From currency, From amount, To currency, To amount, Fee amount (optional), Fee charged to sleeve, Date, Payee (placeholder "Norbert's Gambit"), Note.
- Deposit [core]: From account (non-investment), To brokerage, Cash sleeve, Amount, Date, Payee, Note, Tags.
- Withdrawal [core]: From brokerage, To account (non-investment), Cash sleeve, Amount, Date, Payee, Note, Tags.

### API
- `GET /api/accounts`, `GET /api/portfolio`, `GET /api/categories` (form data)
- `GET /api/portfolio/operations/load?id=` (edit mode)
- `POST /api/portfolio/operations/{buy|sell|swap|transfer|income-expense|fx-conversion|deposit|withdrawal}`
- `GET /api/portfolio/lots?holdingId=&openOnly=1` (Sell lot picker)

### Judgement
- Core: Buy, Sell, Deposit, Withdrawal, Income / expense (dividends).
- Power: Swap, In-kind transfer, FX conversion, specific-lot selection on Sell.
- Clutter: the chooser as a separate page. In native, present the op as a sheet launched from Portfolio, a holding, or an account, with a segmented op picker; Swap can be "Sell then Buy" with a link.
- Payee and Tags on investment ops are rarely needed; collapse them under "More".

---

## /portfolio/dividends

Purpose: dividend income report by year, quarter or holding, including reinvestments and withholding.

### Sections, top to bottom
- Header: title, explainer ("Every transaction categorized as Dividends…"), "← Overview" link, CSV download link.
- Controls: Group by (Year / Quarter / Holding); currency basis (Native currency / Reporting currency).
- Date filters: Tax year select ("All years" + list), From date, To date, "Clear". Tax year and date range are mutually exclusive.
- Result card: title "N dividend rows"; total badges (one per currency, or one reporting-currency total); table with Period or Holding, Rows, Reinvested, Withholding, then one amount column per currency (native) or a single Total (reporting). Negative values red.
- No chart.

### User actions
- Group-by, basis, tax year, date range, clear, CSV export. Read-only otherwise.

### API
- `GET /api/portfolio/dividends?groupBy=&pivot=1&reportingCurrency=1&from=&to=&taxYear=` (and the same with `format=csv` for the download)

### Judgement
- Core (monthly/annual, tax season): yearly total, per-holding breakdown.
- Power: quarter pivot, native multi-currency columns, Rows/Reinvested/Withholding counts, CSV.
- Native note: a bar chart by year/quarter would replace most of the table; keep the per-holding list as a drill-down.

---

## /portfolio/realized-gains

Purpose: capital-gains report, one row per lot closure, filtered by tax year and holding term.

### Sections, top to bottom
- Header: title, "← Portfolio" link, "Export CSV" button (client-side CSV of the visible rows or groups).
- Filter row: Tax year chips (recent years) + "All time" (defaults to current year); Term chips All / Short (≤365d) / Long (>365d); checkbox "Show in <reporting ccy>"; checkbox "Hide zero-gain rows".
- Group by: Off / Holding / Account / Holding + account. Grouping is disabled until "Show in <ccy>" is on (no summing across currencies), with a hint.
- Result card: title with counts ("N closed lots" or "N groups · M closed lots"); total badges per currency or one unified total.
  - Ungrouped table: Closed, Opened, Days, Term (badge), Holding, Account, Qty, Cost / sh, Proceeds / sh, Realized; kind badge with tooltip for Short open, Short close, Swap, Currency (FX lot).
  - Grouped table: Holding and/or Account, Closures, Qty, Date range, Realized (reporting ccy).
- Empty states mention a lot-backfill admin script. [dev wording leaks into prod]
- No chart.

### User actions
- Filters and toggles above, group by, CSV export. Read-only (lot edits live in the Lot inspector on /portfolio).

### API
- `GET /api/portfolio/realized-gains?taxYear=&term=&…`

### Judgement
- Core (tax season, not weekly): year total, short vs long split.
- Power: per-closure table, grouping, kind badges, hide-zero, CSV.
- Clutter: the "Currency" kind rows (FX lot closures with zero native gain) are noise for most users; hide by default.
- Native note: dividends and realized gains can be one "Income & gains" report with a segmented control and a shared tax-year picker.

---

## /loans

Purpose: track loans and debts, their balances, payments, and amortization schedules.

### Sections, top to bottom
- Header: "Loans & Debt", subtitle, "Add Loan" button.
- Three tiles: Total Debt (sum of remaining balance in display currency, "converted at today's rates" note when foreign loans exist), Monthly Payments (monthly-equivalent total for active loans), Active Loans (count). [core]
- Empty state "No loans tracked yet".
- Active loans list (`LoansList`, sortable data table; sorting by amount uses display-currency values). [core]
  - Columns: Loan (name; click opens schedule, or Edit if the loan cannot be scheduled; "Manual" and "Can't schedule" badges), Type, Remaining (native currency; links to the linked account when the balance comes from it), Payment (per period + frequency), Rate (nominal, plus "eff." effective rate for flat/total interest), Total interest, Payoff (date; "Term end" for leases), Paid (progress), Actions (View schedule, Edit, Delete).
- "Completed (N)" collapsible section of paid-off loans, same list, collapsed by default. [power]
- Amortization panel for the selected loan (appears below the list, scrolls into view; deep link `?loan=<id>&tab=<tab>`). Figures in the loan's own currency. Tabs:
  - Chart: stacked bar chart of principal vs interest per payment (down-sampled to ~60 bars), and a line chart of balance. [core]
  - Table (`LoanScheduleEditor`): columns #, Date, Payment, Principal, Interest, Balance. Calculated mode: per-row inline interest edit (Save/Cancel, reset per row), "Reset edited interest", "Switch to manual". Manual mode: "Edit rows" (draft grid with Date, Payment, Interest, add row, remove row), "Save schedule", "Discard changes", "Back to calculated". Both modes: "Download template" (CSV) and "Upload schedule" (CSV). Mode switches confirm first. [power]
  - Monthly Interest: table Month, Interest Accrued (day-weighted calendar-month accrual). [power, tax]
  - Interest entries (`LoanInterestEntries`): Interest category picker, "New category" (inline name + "Create and use"), "Post N entries" for all due dates. Table: Payment date, Calculated interest, Booked, Entry ("Generate" per row). Rate check: compares booked vs calculated interest and offers "Use X%" (confirm "Change the rate to X%?"). [power]
  - What-If: table Extra/Month (100, 200, 500, 1000), Months Saved, Interest Saved, New Payoff. [power; nice]

### Dialogs
- Add Loan / Edit Loan (same form): Name, Type (Mortgage, Lease, Loan, Student Loan, Credit Card), Currency, Principal, Interest method (Yearly rate / Fixed amount each payment / Total for the whole loan), then Annual Rate (%) or Interest each payment or Total interest, Term (months) or Payment (one solves the other), Frequency (Weekly, Biweekly, Semi-monthly, Monthly, Quarterly, Annual), Extra/Payment, Start Date, Residual / Buyout (lease only), Linked Account (combobox, non-investment accounts; picking one copies its currency). [core]
- "Change loan currency?" confirm (re-labels amounts, no conversion). [edge case]
- "Delete loan" confirm.

### API
- `GET|POST|PUT|DELETE /api/loans` (POST also takes `action: "amortization"` and `action: "what-if"`)
- `GET /api/accounts`
- `PUT /api/loans/schedule`
- `GET|POST /api/loans/interest`
- `GET|POST /api/categories`

### Judgement
- Core: totals tiles, loan list (remaining, payment, payoff, progress), add/edit loan, amortization chart.
- Power: schedule editing (per-row interest, manual mode, CSV template round trip), interest entries posting, monthly accrual, what-if, completed section, interest method variants, currency re-denomination.
- Clutter: Active Loans count tile; Total interest and Rate both in the list row on iPhone (move to detail). The amortization panel under the list is a web workaround; native should push a loan detail screen with these tabs.

---

## Cross-route notes for the native design
- Investment op entry points exist in three places: account detail dropdown, `/portfolio/new` chooser, and (indirectly) Edit links via `?editId=`. Consolidate into one "Record" sheet.
- Holding create lives outside these routes (`/settings/investments`); Edit Holding is on /portfolio. Pick one home.
- Two holding lists on /portfolio (All Holdings expand vs Holdings by Account). Keep one with a group-by toggle.
- Cost-basis method (`/api/settings/lot-allocation`) decides whether lot figures matter at all. When it is "simple average", the Lot inspector and the Sell lot picker can stay hidden.
- Dev-only on these routes: ETF X-Ray and Performance vs Benchmarks (both on /portfolio).
