# Finlynq RN mobile app inventory

Source: `finlynq/mobile` (Expo, React Navigation). 36 screens, 6 navigators, about 22k lines of TS. Paths below are relative to `mobile/src`.

## 1. Navigation map

```
Root (RootNavigator)
├─ Loading spinner
├─ LockScreen            (session + biometric enabled)
├─ LoginScreen           (login / register / server URL)
└─ Tabs (always-dark bar, "Option B: Wealth-led")
   ├─ Home        DashboardScreen (no stack, nothing tappable)
   ├─ Accounts    AccountsStack
   │   ├─ AccountsList
   │   ├─ AccountDetail ──► "Reconcile" jumps cross-tab to More > Inbox
   │   ├─ AddAccount (modal; create + edit)
   │   └─ AddTransaction (modal)
   ├─ Portfolio   PortfolioStack
   │   ├─ PortfolioOverview
   │   ├─ HoldingDetail ──► Buy / Sell shortcuts
   │   ├─ PortfolioOps (modal, 8-tile chooser)
   │   ├─ OperationForm (modal, one renderer for 8 ops)
   │   ├─ AddHolding (modal, returns to OperationForm)
   │   ├─ Performance · RealizedGains · Dividends
   ├─ Transactions TransactionsStack
   │   ├─ TransactionsList
   │   ├─ TransactionDetail (view + inline edit + delete; "In Portfolio" jumps cross-tab)
   │   ├─ AddTransaction (modal)
   │   └─ SplitsEditor (modal)
   └─ More        MoreStack (pops to root on blur)
       ├─ MoreHome (menu: Get started / Add / Tracking / Tools)
       ├─ Budgets · Goals · Categories · Import · Inbox (Reconcile)
       ├─ Reports ─► IncomeStatement · BalanceSheet · Trends · CashFlowSankey · YearOverYear
       ├─ Settings ─► ReconcileThresholds
       ├─ WhatsNew · Feedback (modal)
       └─ AddTransaction · AddCategory · AddGoal (modals)
```

AddTransaction is registered in 3 stacks (Accounts, Transactions, More). Two cross-tab jumps use `getParent()` casts.

### Task depth (taps, excluding typing)

- Add an expense: Transactions tab, "+ Add", type amount, account picker (2 taps, defaults to the first account), category picker (2), type payee, Save. About 6 to 7 taps. Not reachable from Home. Via More it is the same count. Date is a typed `YYYY-MM-DD` text field. No payee autocomplete or category suggestion.
- Transfer: More, Transfer (or Add, then the Transfer segment), from/to pickers (4), Save. About 7 taps. Same-currency only.
- Check a budget: More, Budgets = 2 taps. Home shows the top 5 budgets but the card is not tappable and "+N more" is plain text.
- Edit a budget: 2 taps to reach, long-press the card, edit inline. Adding one uses a horizontal category chip row, not the searchable picker used elsewhere.
- Record a stock buy: Portfolio tab, "New operation", Buy tile, type total cost, account picker (2), holding picker (2), type qty, Record. About 8 taps. New symbol adds a detour through AddHolding (another modal). From an existing holding: Portfolio, holding row, Buy (account and holding prefilled), type, Record. About 4 taps.
- Reconcile: More, Reconcile, then choose account, lens chips, tab. 3 to 4 taps before seeing cards. Or Accounts, account, Reconcile (jumps tabs).
- Cash-flow Sankey: More, Reports, pick range, Cash flow. 3 to 4 taps.
- Display currency: More, Settings, scroll to General, picker. 3 to 4 taps.

## 2. Per screen

| Screen | Purpose / shows | Actions | Web feature | Notes |
|---|---|---|---|---|
| Dashboard | Net worth (assets/liabilities), health-score ring, this month income/expense + savings bar, top-5 budgets, 5 recent tx | Pull to refresh only | /dashboard | Read-only. No drill-down at all. Fetches on mount only, so it goes stale after adding a tx. Any fetch error replaces the whole screen, no retry. |
| Accounts | Net-worth hero, SectionList grouped by account group | Tap row, "+" add | /accounts | Net-worth hero duplicates Dashboard. |
| AccountDetail | Balance, recent tx FlatList, "Manage account" (edit, archive, delete, reconcile mode), Reconcile link | Add tx (hidden for investment accts), edit, archive, delete | /accounts/[id] | Account admin is mixed into the activity screen. |
| AddAccount | Create/edit form | Save | accounts dialog | Plain form. |
| Portfolio | Hero, MetricGrid of returns, chips to Performance/Realized/Dividends, allocation donut (type/account), top movers, holdings list | New operation, tap holding | /portfolio | Long scroll stacking 6 sections. |
| HoldingDetail | Per-account rows, open lots, transactions | Buy, Sell shortcuts | /portfolio holding drawer | Good contextual entry point. |
| PortfolioOps | 8 tiles (Buy, Sell, Swap, Transfer, Income/Expense, FX, Deposit, Withdrawal) | Pick op | /portfolio/new | Thin chooser screen. |
| OperationForm | Config-driven form per op, lot picker for Sell, cash-sleeve precheck, edit prefill | Record / edit | portfolio op forms | Up to 10 fields (Income/Expense). Dense but well-structured. |
| AddHolding | Symbol/name/type form | Save, returns to form | holdings mgmt | Detour modal on top of a modal. |
| Performance | Period selector, value-vs-cost line, TWRR/MWRR grid | Period | /portfolio performance | Fine. |
| RealizedGains | Tax-year, term filters, base-currency toggle, one row per lot closure | Filters | /portfolio realized | Table-like list. |
| Dividends | Grouped by year / quarter / holding | Group-by | /portfolio dividends | Fine. |
| Transactions | Search + flat list (50 rows max, newest first) | Tap, long-press Edit/Delete, + Add | /transactions | Hard 50-row limit, no paging, no filters, no date grouping. A hint line "Tap to view • Long press for actions" explains hidden gestures. |
| TransactionDetail | Amount hero, fields, split chip | Inline Edit, Split, Delete, "In Portfolio" | tx edit dialog | Edit UI here differs from the Add form (two forms for one record). |
| AddTransaction | Expense/Income/Transfer segments, amount, date (text), account, category, payee, tags, note | Save | add tx + transfer dialogs | Excludes investment accounts. Load errors only logged. |
| SplitsEditor | Split rows, balance check | Save, clear | splits | Fine. |
| Budgets | Month nav (Prev/Next text), summary card, inline add form, budget cards | Add, tap to inline-edit, long-press delete | /budgets | Inline forms inside a scroll view, web style. No refetch on focus. |
| Goals | Goal cards with progress | Tap = edit form, + add | /goals | Tapping a goal opens the edit form, there is no goal detail. |
| AddGoal / AddCategory | Create/edit/delete forms | Save, delete | dialogs | Fine. |
| Categories | SectionList by group | Tap = edit, + add | /categories | Settings-grade screen sitting in "Tracking". |
| Import | 3 steps in one screen: pick file, preview (valid/dup/error counts, rows, dup toggle), result | Pick, import, cancel | /import (lite) | No column mapping or templates. |
| Inbox (Reconcile) | Account selector, lens chips, "save as policy" toast, collapsible default-mode picker, tabs (To approve or To categorize / Reconciled), card list | Approve, categorize, delete per card, change mode | /inbox, /reconcile subset | 5 control layers above the cards. Manual mode shows a "use the web app" notice. |
| ReconcileThresholds | 4 numeric tuning fields | Save | settings | Power-user tuning. |
| Reports hub | Range presets + custom month range, business-only toggle, KPI tiles, 5 links | Navigate | /reports | Hub plus 5 leaf screens. |
| IncomeStatement / Trends | Collapsible grouped category tables, Trends adds line + grouped bars + granularity/group-by | Expand groups | /reports tabs | Tables ported from web. |
| BalanceSheet | Accounts by group, converted + native balances | none | /reports | Same data as Accounts tab, rendered again. |
| CashFlowSankey | SVG Sankey in a horizontal ScrollView | Pan | /reports Sankey | Wide chart panned sideways on a phone. No tap-to-inspect. |
| YearOverYear | Two-year category comparison + monthly totals | Year select | /reports YoY | Table. |
| Settings | Connection, General (currency), Appearance, Reconciliation, Security (biometric, auto-lock), Data (wipe, delete account via password Modal), Diagnostics (app log viewer), About, Legal | Many | /settings | Long single scroll. Developer diagnostics shown to all users. |
| MoreScreen | Grouped menu | Navigate, load sample data, sign out | web sidebar | "Load sample data" stays at the top forever. Add/Transfer duplicated here. |
| WhatsNew, Feedback | Announcements; feedback form | Mark read; send | /whats-new, /feedback | Fine. |
| Login, Lock | Auth, server URL, biometric unlock | | auth | Fine. |

Thin wrappers or dumped lists: PortfolioOps (tile chooser only), BalanceSheet (repeats Accounts), Reports hub (link list), Categories (flat list), Transactions (capped dump), Goals (list that opens forms).

## 3. Missing vs web nav

Web `nav.tsx` (prod unless noted): Dashboard, What's New, MCP Guide, AI Chat (dev), Transactions, Budgets, Goals, Subscriptions, Accounts, Portfolio, Loans & Debt, Reports, Categories, Tax (dev), Scenarios (dev), FIRE (dev), Import, Settings, Admin.

- Absent on mobile: Subscriptions (prod on web now, the design doc still calls it dev), Loans & Debt (prod on web now), Calendar view, AI Chat, Tax, Scenarios, FIRE, MCP Guide.
- Partial: Import (no templates, staging, connectors, email import), Reconcile (no two-pane matcher, no manual mode), Transactions (no filters, sort, bulk ops, paging), Budgets (no templates, envelope, seed-from-history), Settings (no rules editor, FX overrides, API keys, backup/export, MFA), Portfolio (no rebalancing, ETF breakdown), cross-currency transfers (server refuses, web only).
- Data the backend exposes that mobile never shows: spending anomalies, weekly recap, cash-flow forecast, recurring transactions, debt payoff plan, net-worth history chart, spotlight items (all are MCP tools on the server).

## 4. UX problems seen in code

- Tab choice is wealth-led (Accounts + Portfolio both tabs) while the daily jobs (add tx, budgets, reconcile) are under More. Budgets, Reports, Reconcile, Goals and Import are all 2 taps deep and share one menu.
- Home is a dead end: no card navigates anywhere, no add button.
- Net worth appears on Dashboard, Accounts, and Balance Sheet.
- Add Transaction exists in 3 stacks plus More plus the Transactions header. Transfer is both a menu item and a segment.
- Two edit patterns for the same thing: transactions edit inline in Detail, but are created in a modal form; budgets edit inline in a card; goals/categories/accounts edit in modal forms.
- Two picker patterns: searchable PickerSheet (Add tx, ops) vs horizontal chip row (Budgets add form).
- Hidden gestures: long-press for delete/edit on Transactions and Budgets, explained by a text hint line. No swipe actions.
- Dates are typed as `YYYY-MM-DD` text. No native date picker anywhere except the Reports month range.
- Web-style UI on a phone: collapsible category tables (IncomeStatement, Trends), YoY table, Sankey panned sideways, Settings as one long page with 9 sections, Inbox with 5 stacked control layers.
- Too many screens for one job: Reports = hub + 5 leaves; Portfolio buy = chooser + form + optional AddHolding modal; reconcile config split between AccountDetail, Inbox, Settings, and ReconcileThresholds.
- State freshness: Dashboard and Budgets fetch once and do not refetch on focus.
- Error handling: a failed fetch replaces the whole screen with red text and no retry. Partial failures (health score, categories, AddTransaction lookups) are logged and silently dropped.
- Transactions capped at 50 rows with no paging or month sections.
- No platform features: no widgets, shortcuts, share-sheet import, notifications, or iPad/large-screen layout.
- Back buttons are hand-drawn in each screen (`headerShown: false` everywhere), so there is no native nav bar, swipe-back title, or large-title behavior.

## 5. Worth keeping as ideas

- Reconcile inbox card flow (RowCard): approve / categorize / delete one bank row at a time, per account. A good phone pattern. Keep the cards, drop the stacked controls around them.
- Config-driven portfolio ops (`lib/portfolio/operations.ts`): one registry of 8 ops with fields, validation, body builder, edit prefill, and cash-sleeve precheck. Port the registry idea to Swift.
- Contextual Buy/Sell from HoldingDetail with prefilled account and holding. Make this the main entry point.
- Lot picker sheet for sells.
- Cash-flow Sankey with pure layout math (`lib/reports/sankey.ts`, unit-tested). Worth redrawing to fit the screen, or as a vertical layout on phone and full width on iPad/Mac.
- Searchable PickerSheet for accounts/categories.
- Report date-range presets (MTD, QTD, YTD, last month/quarter/year, 12 months) plus custom.
- Splits editor with a balance check.
- Health-score ring, savings-rate bar, budget progress bars as compact glance elements.
- Biometric lock + auto-lock, server URL on the login screen (self-hosting support).
- Load sample data for onboarding (as a first-run empty state, not a permanent menu row).
- Mode picker per account (auto-pilot / approve-each / manual) with gate counts.

## 6. Design notes (`mobile/design`)

- `screens.md`: per-screen specs for 15 HTML mockups (`screens/*.html`, gallery `index.html`), mostly "draft". Picks "Option B Wealth-led" tabs. Asks for 44pt touch targets, cents on tx amounts, `date · category` subtitles, conic health ring. Proposes More as a slide-up sheet (shipped as a pushed menu instead). The Portfolio spec says read-only, since superseded by full write ops.
- `design-system.md` + `tokens.css`: web-matched theme. Amber primary (#f5a623), teal positive, coral negative, near-black dark surfaces, always-dark nav chrome, lucide icons (`icons.svg`), OKLCH values with hex fallbacks.
- `gap-analysis.md`: web vs mobile matrix and decision log. Roadmap P1 Splits, P2 Reports full parity, P3 Reconcile inbox subset, P4 Settings expansion (all four shipped). Lists web-only by design: rules editor, FX overrides, backfill, two-pane reconcile, Tax/Scenarios/FIRE, admin. Its "dev" tags for Subscriptions and Loans are out of date.
- `sample-data.md`: sample data used by the mockups.
- The design work aimed at parity with web, not at phone-first tasks. That is the main thing to change.
