# Finlynq web inventory: reports, tools, feedback, settings, onboarding

Source: `src/app/(app)/<route>/page.tsx` plus imported components. Dev-only means hidden unless the user turns on Dev Mode (`mode: "dev"` in `src/components/nav.tsx`, or `useDevMode()` / `DevModeGuard` inside a page).

Nav placement (prod): Reports sits under the analysis group. Tax, Scenarios and FIRE are `mode: "dev"`. Feedback ("Your feedback", with unread badge) and Settings sit in the bottom tool links.

---

## /reports (prod; two tabs are dev-only)

Purpose: income statement and balance sheet for any date range, with per-period pivot tables.

Global filter bar (applies to every tab):
- Range preset: MTD, QTD, YTD (default), last month, last quarter, last year, last 12 months, last 5 years, all time, custom. Multi-year presets switch Period to yearly.
- Start date, end date (typed; commit on blur sets preset to custom).
- Period: daily, weekly, monthly (default), quarterly, yearly.
- Group by: category or category group.
- Accounts: multi-select account filter (includes archived).
- Toggle button: "All Transactions" / "Business Only".

Summary cards (4): total income, total expenses, net savings, savings rate %.

Chart "Income vs Expenses": area chart, two series (income, expenses) per period.

Tabs:
1. Income Statement (prod, default)
   - Empty state with "Import transactions" link when no data.
   - "<Period> Breakdown": grouped bar chart, income vs expenses per period (shown when more than 1 period).
   - Income table: rows grouped by category group (collapsible), columns = Name, one column per period (last 30 max, truncation notice), Total, %. Totals row. Each category row links to the transactions list filtered by category + range, plus a small icon linking to `/categories/[id]`. CSV export button (all periods).
   - Expenses table: same shape, same export.
   - Net savings card: net amount + savings rate.
   - Unrealized gains/losses (period change), only if non-zero: 3 tiles (valuation G/L, FX G/L, total) and a per-account table (account, currency, cost basis, market value, valuation G/L, FX G/L, total; "no cost basis" flag).
2. Balance Sheet (prod): as-of end date. Assets table (account group, account, currency badge, balance) with total; liabilities table with total; net worth. CSV export.
3. Cash Flow (dev-only): Sankey diagram, income categories flowing into top 10 expense categories.
4. Year over Year (dev-only): Year 1 / Year 2 number inputs. Grouped bar chart of monthly expenses (2 years), grouped bar chart of monthly income, category comparison table (year1, year2, change % badge, red if > +5%, green if < -5%).

Actions: filters above, expand/collapse groups, 3 CSV exports, drill-through links. No create/edit.

API: `/api/reports/trends`, `/api/reports?type=balance-sheet`, `/api/reports?type=income-statement` (used only for its `unrealized` block), `/api/reports/yoy`, `/api/accounts?includeArchived=1`.

Judgement: core (weekly/monthly). Native keeps the filter set, summary cards, income/expense trend chart, grouped category tables (iPhone: drop the period pivot columns, show total + % and push a per-category period chart), balance sheet. Unrealized G/L is power-user, keep as a section. Sankey and YoY are dev-only clutter; YoY could return later as a simple comparison mode. Daily period with 30 truncated columns is a web-table artifact.

---

## /tax (dev-only, wrapped in `DevModeGuard`)

Purpose: Canadian tax helpers (TFSA, RESP, RRSP, Ontario marginal rates).

Sections:
- 3 cards: TFSA room (remaining, used, % progress bar, total room, this-year room); RESP grant (CESG example per year, static rule text); marginal rate at $100K (combined, federal, provincial).
- RRSP vs TFSA calculator: inputs annual income, contribution amount; Compare button. Output: RRSP tax refund, TFSA benefit, recommendation text.
- Marginal tax rates (Ontario) table: income level, federal, provincial, combined.
- Asset location advice: list of holdings (symbol, name, current account, recommended account type, reason).

API: `GET /api/tax`, `POST /api/tax`.

Judgement: clutter/dev-only. Hard-coded to Canada/Ontario, mostly static content. Skip in native v1.

---

## /scenarios (dev-only, `DevModeGuard`)

Purpose: four what-if calculators.

Tabs:
1. Home Purchase: purchase price, down payment %, interest rate, amortization years, property tax/yr, maintenance/yr. Output tiles: monthly mortgage, total monthly cost, down payment, total interest. Line chart: mortgage balance over time.
2. Extra Savings: monthly savings, expected return %, horizon years. Tiles: future value, total contributed, investment growth. Area chart: growth over time.
3. Debt Payoff: table of the user's loans (name, balance, rate, min payment; empty state points to Loans page), extra monthly budget input. Output: avalanche ("Highest Rate First") and snowball ("Lowest Balance First") cards with total interest, months to debt-free, payoff order with month; line chart of total debt over time.
4. Income Change: current income, new income, current savings rate %. Output: Current vs New cards (annual income, monthly take-home, monthly savings, savings rate), impact summary (extra take-home, extra savings, additional tax, income increase).

API: `POST /api/scenarios` (all four), `GET /api/loans`.

Judgement: clutter/dev-only. Debt payoff overlaps the Loans page; if kept, fold it into Loans. Skip the rest in v1.

---

## /fire (dev-only, `DevModeGuard`)

Purpose: FIRE (early retirement) projection.

Sections:
- Your Details form (prefilled from dashboard balances and income/expenses): current age, target retirement age, current investments, monthly savings, annual return %, inflation %, annual expenses in retirement, safe withdrawal rate %. Calculate button.
- Result tiles: FIRE number, years to FIRE, FIRE age, projected FIRE date, Coast FIRE number, Coast FIRE age.
- Area chart: projected net worth vs FIRE number.
- Monte Carlo: volatility %, years to simulate, Run Simulation. Fan chart (area bands p10/p25/p50/p75/p90), 1,000 runs; final-value tiles for P10 (worst), P25, P50 (median), P75, P90 (best).
- Sensitivity table: years to FIRE by return rate (rows) x monthly savings (columns).

API: `GET /api/dashboard`, `POST /api/fire`, `POST /api/fire/monte-carlo`.

Judgement: dev-only, power-user. Not a v1 need. If revived, it is a self-contained calculator that suits an iPad/Mac sheet.

---

## /feedback (prod)

Purpose: the user's own feedback threads with the Finlynq team.

Sections:
- Header + "Send feedback" button.
- Empty state with a second "Send feedback" button.
- List of threads: type badge (bug, idea, question, other), status, date, message preview, "New reply" flag.
- Thread dialog: original message, replies, attachments (image/file view), reply box (text + optional attachment, size/type validated). Opening marks the thread read.

Send feedback dialog (`FeedbackDialog`): type (bug/idea/question/other), message, optional attachment.

API: `GET/POST /api/feedback`, `GET /api/feedback/[id]`, `POST /api/feedback/[id]/read`, `POST /api/feedback/[id]/reply`. Nav badge reads the unread count.

Judgement: keep, low frequency. Native: "Send feedback" in Settings or the Help menu, with screenshot attach; thread list is optional.

---

## Settings shell (`settings/layout.tsx`)

Left nav on desktop, pill row on mobile. Order: General, Account & Security, Data, Categorization, Rules, Import, Bank feeds, Reconciliation, Investments, Display & Ordering, Integrations, Developer. `/settings` redirects to `/settings/general`. `/settings/securities` and `/settings/holding-accounts` redirect to `/settings/investments`. `/settings/dropdown-order` and `/settings/backfill` are sub-pages without nav items.

---

## /settings/general

Purpose: display preferences and currencies.

Sections:
- Display Preferences: display currency (combobox; changing opens a confirm dialog "Switch display currency to X?"); UI font (select from `FONT_OPTIONS`); exchange rates view: "As quoted" or "Inverted".
- Currencies you use (`ActiveCurrenciesSection`): list of active currency codes with remove; add a code (validates 3-4 letters, previews a rate vs USD).
- Custom exchange rates (`FxOverridesSection`): list of overrides; add form with currency, rate, from date, to date (optional), note (optional); delete. Adding auto-adds the currency to active currencies.
- About card: tagline, "Zero-knowledge" and "Local-first" badges, text "All data is stored locally on your machine. No data is sent to any server." (stale copy for the hosted app).

API: `/api/settings/reporting-currency/status`, `PUT /api/settings/display-currency`, `PUT /api/settings/fx-rate-view`, `GET/PUT /api/settings/active-currencies`, `/api/fx/preview`, `GET/POST/DELETE /api/fx/overrides`, `/api/auth/session`.

Judgement: native needs display currency, active currencies and rate direction (set-once). FX overrides are power-user, keep on iPad/Mac or as a sub-screen. UI font: drop (use system font, Dynamic Type). About: replace with a native About screen with version; drop the inaccurate "local" text.

---

## /settings/account (Account & Security)

Sections:
- Change Password: current, new, confirm.
- Change Email: new email, password.
- API Key: masked key, show/hide, copy, regenerate (shows "Save this key now" once; server stores a hash).
- Privacy & Backup: AES-256 note; "Download Full Backup" (JSON); "Restore From Backup" multi-step (pick file, preview contents, type confirmation, warning that it replaces all data).

API: `/api/user/me`, `POST /api/settings/change-password`, `POST /api/settings/change-email`, `GET/POST /api/settings/api-key`, `GET /api/data/export`, `POST /api/data/import`.

Judgement: password and email change are set-once but a native app needs them (or a link out). API key is web-only (MCP/scripts). Backup download could be a share-sheet export on native; restore is a destructive, rare action, web-only or Mac-only.

---

## /settings/data

Sections:
- Import Data: CSV import for accounts, categories or portfolio holdings, with preview table and Confirm/Cancel.
- Data Export: 4 buttons for CSV of accounts, categories, transactions (with splits), portfolio.
- Backfill transactions: description + link to `/settings/backfill`.
- Rebuild balance history: button that starts a background rebuild of daily snapshots and polls status.
- Data Management (danger zone): Clear all data (2-step, type "DELETE"); Delete account (2-step, type "DELETE" + password).

API: `POST /api/accounts`, `POST /api/categories`, `POST /api/portfolio` (CSV import rows), `GET /api/accounts|categories|transactions?limit=99999|portfolio`, `/api/transactions/splits`, `POST /api/portfolio/snapshots/rebuild`, `/api/portfolio/snapshots/rebuild/status`, `DELETE /api/data`, `POST /api/auth/delete-account`.

Judgement: mostly web-only maintenance. Native must keep "Delete account" (App Store guideline 5.1.1(v) requires in-app account deletion when accounts can be created in-app). CSV export fits a share sheet. Rebuild balance history is power-user, one button is cheap. CSV entity import and Clear all data: web-only.

---

## /settings/backfill and /settings/backfill/[runId]

Purpose: wizard that rewrites legacy investment transactions into canonical form so lots and realized gains work.

- Wizard: Step 0 "Cash-sleeve symbols" fix button; Step 1 mode (refuse orphans vs synthesize orphans); Step 2 scope (all investment accounts, specific accounts, optional from/to dates); "Compute proposals".
- Review page (2,043 lines): left pane proposal list with confidence chips, sort, summary; right pane detail (displaced rows vs replacement rows, override kind picker, drift variant radio, counterpart candidate picker, dependency warning); per-proposal accept/override, apply run, undo per proposal; "Canonicalization coverage" card.

API: `/api/accounts`, `POST /api/settings/backfill`, `POST /api/settings/backfill/fix-cash-sleeve-symbols`, `GET/PATCH /api/settings/backfill/[runId]`, `POST .../apply`, `POST .../undo/[proposalId]`, `GET .../counterpart-candidates`, `GET /api/settings/backfill/coverage`.

Judgement: dev/maintenance tool, web-only. Skip in native.

---

## /settings/categorization

Purpose: category CRUD.

Sections: Category Management card. Add form: name, group (free text), type (Expense, Income, Reconciliation). List grouped by group heading; each row: name, type badge, inline rename (pencil), delete.

API: `GET/POST/PUT/DELETE /api/categories`.

Judgement: native needs it (set-once, occasional edits). Note that `/categories` (main nav) also exists; on native, merge category management into the Categories screen instead of Settings.

---

## /settings/rules

Purpose: transaction auto-categorization rules.

Sections: Transaction Rules card, sorted by priority (first match wins). Each rule card: name, "disabled" badge, auto-generated "When: ... Then: ..." summary, active toggle, edit, delete. Add rule button. Empty state.

Rule editor dialog (`components/rules/rule-editor-dialog.tsx`): rule name, priority, active switch; conditions (AND only): field (payee, amount, account, date, currency, note, tags, quantity, security name, ticker...) with ops contains / exact / regex for text, > / < / = / between for numbers; actions (ordered): set category, set tags, rename payee, set entered currency, move to account (approve-time only), create transfer pair (approve-time only), record investment transaction (buy, sell, dividend, interest, fee, deposit, withdrawal; with row quantity/price/amount or fixed values, investment account, bank account, holding, category). Live preview panel runs the pure actions against a typed sample transaction.

API: `GET/POST/PUT/DELETE /api/rules`, `/api/categories`, `/api/accounts`, `/api/portfolio`.

Judgement: power-user. Native v1: list with active toggle, delete, and a simple editor (payee contains, then set category/tags/rename). Full multi-action investment editor is iPad/Mac or web.

---

## /settings/import (+ /settings/import/reconcile-visibility)

Purpose: import management (templates, email import, connectors).

Sections top to bottom:
- "Confirm field mapping before importing" toggle (CSV mapping / OFX Name vs Memo preview before staging).
- "Reconcile dropdown visibility" card with link and hidden count. Sub-page lists all accounts (incl. archived) with a hide/show toggle each.
- Tabs:
  1. Templates: saved CSV column-mapping templates (`TemplateManager`): list with account, set default, delete.
  2. Email Import: unique import address with copy and regenerate (or "Generate Import Email Address"); "How it works" steps; Imported-email retention select (days); Email rules list (`EmailRulesManager`): enable/disable, delete.
  3. Migrate from another app: WealthPosition connector (credentials save/delete, ZIP probe, preview, execute), MoneyPro connector (file preview, map accounts, execute), generic CSV connector (preview, execute).
  4. Investment statements: statement file importer (preview, execute into an account).

API: `/api/accounts`, `/api/import/templates`, `DELETE /api/import/templates/[id]`, `GET/POST /api/import/email-config`, `GET/PUT /api/settings/confirm-csv-mapping`, `GET/PUT /api/settings/email-retention`, `GET/PUT /api/settings/reconcile-hidden-accounts`, `/api/email-rules`, `/api/email-rules/[id]`, `/api/import/connectors/wealthposition/{credentials,zip-probe,zip-preview,zip-execute}`, `/api/import/connectors/moneypro/{preview,execute}`, `/api/import/connectors/generic-csv/{preview,execute}`, `/api/import/preview`, `/api/import/execute`.

Judgement: set-once configuration. Native needs: show/copy the import email address (handy on iPhone for forwarding), email rules toggle. Migration connectors, templates and statement importer are file-heavy and one-time: web or Mac only. Reconcile visibility and confirm-mapping toggles only matter if native has the import flow; otherwise web-only.

---

## /settings/bank-feeds

Purpose: SimpleFIN bank connection with on-demand sync.

Sections:
- Not connected: explanation (simplefin.org, $15/yr), setup token field, Connect button, link to SimpleFIN.
- Connected: last synced time, "Sync now" (detects accounts), last-sync failure/partial banner with problem list; Detected accounts list where each new bank account gets "Create new" or "Link existing" (select of Finlynq accounts); "Stage" button sends transactions to `/import/pending`; result summary (staged, pending skipped, skipped without choice); Disconnect (confirm dialog).
- Pending charges card: holds not added to the ledger; rows show account, date, payee, amount, currency.

API: `GET /api/settings/bank-feeds/simplefin/status`, `GET .../pending`, `POST .../connect`, `POST .../preview`, `POST .../sync`, `DELETE .../disconnect`.

Judgement: connect is set-once; "Sync now" plus account mapping is weekly and fits native well (pull-to-refresh style). Pending charges is a nice glanceable list. Keep in native, likely surfaced from Accounts/Import rather than Settings.

---

## /settings/reconciliation

Purpose: tune fuzzy-match thresholds for `/reconcile`.

Fields: date tolerance (days), amount tolerance (%), amount tolerance floor, score threshold. Save and Reset to defaults.

API: `GET/PUT /api/settings/reconcile-thresholds`.

Judgement: power-user, set-once. Web-only (or hidden advanced section on Mac).

---

## /settings/investments (absorbs /settings/securities and /settings/holding-accounts, which redirect)

Purpose: securities catalog and which accounts hold which securities.

Sections:
- Cost basis method (`CostBasisSetting`): simple average vs lot allocation (display-only switch, no data change).
- Tabs:
  1. Securities: unpriceable-ticker warning card (per security: "Change to <suggested>", "Fix symbol", "Use manual price"). Table: symbol, description, type, currency, pricing (auto / manual, "No price yet"), actions (edit, prices, delete if unused). Sortable headers, per-column filter inputs. "Add security" button.
  2. By security: collapsible securities, each lists holding accounts; "+ Account" link dialog; unlink (transaction-free positions only).
  3. By account: collapsible investment accounts, each lists securities and cash sleeves; "+ Security" link dialog; "Add cash sleeve".
- Dialogs: Add security (ticker with live lookup that fills name and currency, name, holding currency, crypto checkbox, pricing Auto-fetch/Manual); Edit security (ticker, display name, asset type stock/ETF/..., pricing); Link (choose account or security); Add cash sleeve (currency code incl. XAU); Prices (`ManagePricesDialog`: list of manual price points, add date + price, delete); delete confirm.

API: `GET/POST/PATCH/DELETE /api/securities`, `POST/DELETE /api/securities/define`, `/api/securities/lookup`, `GET/POST/DELETE /api/securities/prices`, `POST /api/portfolio/holdings/cash-sleeve`, `/api/accounts`, `GET/PUT /api/settings/lot-allocation`.

Judgement: power-user for investors. Native: securities list + add/edit + manual prices belong in the Portfolio area; the account-security linking matrix is iPad/Mac. Cost-basis method is set-once.

---

## /settings/display (Display & Ordering) and /settings/dropdown-order

- Display: a single card "Dropdown Ordering" with an Open button to `/settings/dropdown-order`.
- Dropdown Ordering: "Which dropdown" select (category, account, holding, currency); Pinned list with drag handle, up/down buttons, unpin; Unpinned list (alphabetical) with Pin. Saves the whole structure.
- API: `GET/PUT /api/settings/dropdown-order`, `/api/categories`, `/api/accounts?includeArchived=1`, `/api/portfolio`, `/api/settings/active-currencies`.

Judgement: set-once. Display page is a one-link wrapper (clutter). Native can replace pinning with recents + search in pickers; if kept, a native reorderable List (edit mode) works. Low priority.

---

## /settings/integrations

Purpose: connected OAuth apps (MCP clients).

Section: Connected apps list (client name, scope badge, connected date), Revoke with confirm dialog, Retry on error.

API: `GET/DELETE /api/settings/connected-apps`.

Judgement: web-only (OAuth/MCP management).

---

## /settings/developer

Purpose: Dev Mode toggle ("Show advanced and experimental features in the navigation").

API: `GET/PUT /api/settings/dev-mode`.

Judgement: dev-only. Native: omit, or a hidden debug toggle.

---

## Onboarding

1. `OnboardingWizard` (`src/components/onboarding-wizard.tsx`), shown as a modal on `/dashboard` when `/api/auth/session` returns `onboardingComplete === false`. Steps:
   - Welcome.
   - Currency: pick display currency.
   - Accounts: preset toggles (Checking, Savings, Credit Card, Investment Account, ...), echoes currency with "Change" link.
   - Import: choose "Import from my bank", "Load sample data", or "Start from scratch".
   - Budget: starter budget amounts (number inputs, step 10), seeds budgets.
   - Connect AI: MCP URL and Claude Desktop setup steps (copy URL).
   - Done: "You're all set!".
   - API: `POST /api/accounts`, `POST /api/budgets/seed`, `POST /api/onboarding/sample-data`, `POST /api/onboarding/complete`.
2. `OnboardingTips` (`src/components/onboarding-tips.tsx`): dismissible tip cards per page (dashboard, accounts, transactions, budgets), dismissal stored in `localStorage` key `pf-dismissed-tips`. No API.

Judgement: native needs a first-run flow (currency, accounts, import or sample data). Drop the Connect AI step (MCP is web-only) or make it a link. Tips cards: replace with native TipKit if wanted.

---

## Native triage summary

| Route | Class | Native |
|---|---|---|
| reports | core | Yes: income statement, balance sheet, trend chart. Drop Sankey, YoY (dev). |
| tax | dev-only | No |
| scenarios | dev-only | No (debt payoff maybe in Loans later) |
| fire | dev-only | No in v1 |
| feedback | low-frequency | Yes, simple send + optional thread list |
| settings/general | set-once | Yes: display currency, active currencies, rate direction. FX overrides on iPad/Mac. Drop font + About copy. |
| settings/account | set-once | Password/email yes (or link out). API key web-only. Backup export via share sheet; restore web-only. |
| settings/data | maintenance | Delete account yes (App Store rule). CSV export via share sheet. Rest web-only. |
| settings/backfill | dev/maintenance | No |
| settings/categorization | set-once | Yes, merge into Categories screen |
| settings/rules | power-user | Simple list/toggle/editor; full editor iPad/Mac |
| settings/import (+ reconcile-visibility) | set-once | Import email address copy, email rules toggle. Connectors/templates web or Mac. |
| settings/bank-feeds | weekly (sync) | Yes: Sync now, account mapping, pending charges |
| settings/reconciliation | power-user | No (web) |
| settings/investments | power-user | Securities + manual prices under Portfolio; linking matrix iPad/Mac |
| settings/display, dropdown-order | set-once / clutter | Replace with recents + search; low priority |
| settings/integrations | web-only | No |
| settings/developer | dev-only | No |
| settings/securities, holding-accounts | redirects | No |
