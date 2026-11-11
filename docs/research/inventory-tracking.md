# Finlynq web inventory: tracking routes

Source: `src/app/(app)/<route>/page.tsx` plus the components each page imports. Nav gating comes from `src/components/nav.tsx`. Every route here is `mode: "prod"`. Dev-only content inside pages is gated by `useDevMode()` (`GET /api/settings/dev-mode`).

Shared patterns across pages:
- `OnboardingTips page="…"`: dismissible first-run tip cards at the top of dashboard, transactions and budgets.
- Display currency comes from `CurrencyProvider`. Most totals are converted to it, and per-item amounts stay in their native currency.
- `buildTxDrillUrl({...})` deep-links into `/transactions` with `id`, `startDate`, `endDate`, `accountId`, `categoryId`, `search`, `tag` and `portfolioHolding`. Dashboard, budgets and categories all drill into it.
- Skeleton loaders, and `ErrorState` with a Retry button.

---

## /dashboard

**Purpose:** a one-screen overview of net worth, monthly cash flow, health ratios and items that need attention.

**Sections, top to bottom**
1. Header: a time-based greeting ("Good morning/afternoon/evening"), the subtitle "Here's your financial overview", and an avatar button that links to `/settings/general`.
2. `CurrencyAuditBanner`: an amber strip, "N transactions need a currency review. Review →", that links to `/transactions/audit`. It appears only when the unresolved count is above 0.
3. `OnboardingTips`: dismissible tips such as "View accounts" and "Import files".
4. Row 1:
   - Hero "Total Net Worth" card (2/3 width, links to `/accounts`):
     - The big animated number.
     - A month-over-month pill (+/- %) and "+$X vs last month".
     - A 12-month sparkline.
   - "Financial Health" card (1/3 width):
     - A score ring (0-100) with a grade label colored green above 70, amber from 40 to 70, red below 40.
     - A sub-score bar per component (name, score and detail).
     - An (i) button that opens the **"How is the Financial Health score calculated?"** dialog. It is read-only and shows the overall score, each component's weight and explanation, and "Your inputs".
5. Row 2, four `StatCard`s. Each has an icon, label, value, sub line and a 6- or 12-month sparkline with a hover tooltip.
   - Net Worth: sub "Assets $X", links to `/accounts`.
   - Monthly Income: the last *complete* month, with the sub line naming that month. Drills into transactions for that month.
   - Monthly Expenses: sub "N% of income", same drill.
   - Budgets: income minus expenses, with the sub line "Available to spend" or "Over budget". Links to `/budgets`. This is not a real budget figure.
6. `KeyMetrics` strip, two cells:
   - Savings Rate %: "of income saved · last 3 months". Green at 20% or more, amber from 5%, red below.
   - Debt-to-Income %: "debt payments vs income · last 12 months". Green at 36% or less, amber up to 43%, red above.
7. `NetWorthHistoryChart` "Net Worth Over Time":
   - Area chart.
   - Period toggle: 6M | 1Y | ALL.
   - "Stacked" toggle that splits the total into a stacked area of the top 10 accounts.
   - Tooltip shows the full date and value.
8. Row 3, three cards:
   - "Action Center":
     - Spotlight alerts with a severity dot (critical, warning, info), title, amount, description, a "View" link to the item's `actionUrl`, and an X to dismiss.
     - Dismissals are stored in localStorage `pf-spotlight-dismissed`.
     - Shows 3 items and a "View all N alerts" button. The empty state is "All good!".
   - "Weekly Recap" (week range in the header):
     - Spent with % change, Income, and Net Flow.
     - "Top categories" horizontal bar chart.
     - A chevron expands "Budget Status (MTD)" (top 5 categories with % used and bars), "Upcoming Bills" (name, date, amount) and "Net worth change this week".
   - "Quick Import": drag-and-drop or click to pick a `.csv`, `.ofx` or `.qfx` file. The file is handed to `/import`, which opens it.
9. **Dev-only** (`devMode`):
   - "Income vs Expenses" area chart, 12 months. A tooltip lists the categories behind each month. A "Stacked" toggle shows top-10 category stacks for income and for expenses.
   - "Spending by Category" donut, last 12 months, top 8, with the total in the center and a legend of the top 6 with % bars.
   - "Available to Spend" card: income, "Spent so far", Remaining, and a % spent bar. It duplicates the Budgets stat card.
   - `InsightsSection`, four list cards:
     - "Spending Alerts" (category, % above average, current vs average).
     - "Recurring (N)" (payee, frequency, next date, average amount, monthly total).
     - "Top Merchants" (last 6 months: payee, count, total).
     - "Category Trends" (direction per category).
10. `OnboardingWizard`: a full-screen modal on first login, shown when `onboardingComplete === false`. Steps:
   1. Welcome.
   2. Currency select.
   3. Add accounts: toggleable presets.
   4. "Import your data": "Import from my bank", "Load sample data" or "Start from scratch".
   5. "Set a starter budget".
   6. "Connect your AI assistant": copy the MCP URL.
   7. "You're all set!"

**User actions**
- Every card is a navigation link (hero, stat cards, banner, Action Center "View").
- Dismiss a spotlight item, and expand to view all.
- Expand or collapse the Weekly Recap.
- Net-worth chart: change the period, toggle stacked.
- Open the Health info dialog.
- Quick Import: drop or pick a file.
- Onboarding wizard: Back, Next, Finish, copy the MCP URL.
- No create, edit or delete actions, and no keyboard shortcuts.

**Tabs / modes:** none apart from the dev-mode extras.

**API routes**
- `/api/dashboard?currency=`
- `/api/health-score?currency=`
- `/api/auth/session`
- `/api/spotlight`
- `/api/recap`
- `/api/net-worth-history?period=`
- `/api/transactions/audit`
- Dev: `/api/insights`, `/api/recurring`
- Onboarding: `/api/accounts` (POST), `/api/budgets/seed`, `/api/onboarding/sample-data`, `/api/onboarding/complete`

**Judgement**
- Core:
  - Net-worth hero with the month-over-month change.
  - Monthly Income and Expenses tiles with drill-through.
  - Action Center.
  - Net Worth Over Time chart.
- Useful, but the content could merge:
  - Weekly Recap overlaps the income/expense tiles and the Action Center. Keep its recap figures and upcoming bills.
  - Savings Rate and DTI could sit inside the Health card.
- Clutter:
  - The "Budgets" stat tile is income minus expenses, not budget data, and is misleading. Replace it with Budgets' "Left to plan" figure.
  - The Net Worth stat tile repeats the hero.
  - Quick Import card: on native, a toolbar or share-sheet import is better.
  - Greeting header.
  - Unused `QuickImportWidget` (dead code in page.tsx).
- Dev-only: Income vs Expenses chart, Spending donut, Available to Spend, InsightsSection. The donut and Top Merchants would make a good native "Spending" card, but the Categories page already covers them.
- One-time: the onboarding wizard (keep a native version), the currency audit banner.

---

## /transactions

**Purpose:** the ledger. Search, filter, add, edit, split, bulk-edit and export transactions. Includes a calendar view.

The same `TransactionsWorkspace` is embedded on `/accounts/[id]`, locked to that account. There are no dev-mode checks in these files.

**Sections, top to bottom**
1. `OnboardingTips`: "Find any transaction", "Categorize for better insights".
2. Header: "Transactions" with the subtitle "Manage and track all your financial transactions".
   - Split button "Add Transaction" plus a chevron menu:
     - Quick add: Transaction, Transfer.
     - Portfolio operations, each going to `/portfolio/new?op=`: Buy, Sell, Swap, In-kind transfer, Income / expense, FX conversion, Brokerage deposit, Brokerage withdrawal.
   - An "Investment Transactions" button that goes to `/portfolio/new`.
3. View tabs: **List | Calendar** (`?view=calendar`).
4. Filter card:
   - Search "Search payee, note, or tags…" (350ms debounce, clear X).
   - Start and end date (list view only).
   - Account combobox ("All accounts"; archived accounts listed with "(archived)").
   - Category combobox ("All categories").
   - "Columns" dropdown: visibility checkboxes and "Reset to default".
   - "Clear all" (shown only when something is active).
   - "Export CSV".
   - Chip rows, each removable with X:
     - "Column filters:" with the sort chip (e.g. "Sort: Amount ↓") and one chip per column filter.
     - "Holding:", "Tag:" and "Transaction: #id".
5. Calendar panel (calendar view only):
   - Week | Month | Year tabs, prev/next, Today ("This year" in year mode), and the period title.
   - Month grid: each day shows +income (green), -spending (red) and "N tx". On phones these become colored dots.
   - Week: 7 day cells with the same data.
   - Year: 12 month tiles with totals. Tapping a tile opens that month.
   - Tapping a day filters the list to that day. Tapping it again clears the selection, and the list shows the whole period.
   - Stat tiles: Income, Spending, "Net for the {period}".
   - Footnote: transfers and trades are excluded from income and spending.
   - Caption above the list: "Transactions on {day}" or "All transactions in {period}", with a "Show the whole week/month" link.
6. Bulk action bar (when rows are selected):
   - "{n} selected" and a "Choose action…" select with a conditional input, Apply, and X to deselect.
   - Actions: Change category, Change account, Change date, Change payee, Change note, Change tags (replaces the value), Delete selected. Delete confirms with "Delete {n} Transactions".
   - Selection covers the current page only.
7. Table, 50 rows per page, with pagination (page, limit, total). The empty state is "No transactions yet" with an "Import data" button.

**Columns**
- Columns can be reordered by dragging the header. Visibility, order, sort and filters are saved per user on the server.
- Default visible:
  - Select (checkbox, select-all in the header), Date, Account, Category, Note, Qty, Amount, Actions.
  - Category is a type-colored badge, with a "split" badge and a link icon when the row is linked.
  - Amount is in the entered currency. When the account currency differs, a muted "→ account amount" line appears below.
  - Actions: Edit, Split, Delete.
- Hidden by default:
  - Account type, Account name, Account alias, Portfolio, Ticker, Tags (clickable chips that set the tag filter), Created, Updated.
  - Source: Manual, Import, MCP (web), MCP (CLI), Connector, Sample data, Backup restore, Reconcile, Backfill, Auto-pilot rule.
  - Kind: the portfolio-op pill.
  - Canonical?

**Sort and filter**
- Header click cycles desc, asc, off. One column sorts at a time; the default is date descending.
- Sortable: Date, Amount, Qty, Created, Updated, Source, Account type. Text columns are encrypted, so they can't sort.
- Per-column filter popovers (funnel icon, Apply and Clear):
  - Date From/To: Date, Created, Updated.
  - Text "Contains": Account, Account name, Account alias, Payee, Portfolio, Ticker, Note, Tags, Kind.
  - Numeric =, >, < or Between: Qty, Amount.
  - Enum checkboxes: Account type, Category, Source, Canonical?. The Canonical? filter has no options and shows "No options.", which is a bug.

**Dialogs**
- **TransactionDialog**: titles New Transaction, Edit Transaction, New Transfer, Edit Transfer. In create mode a toggle switches between Transaction and Transfer.
  - Transaction fields:
    - Date
    - Amount (signed). A live FX preview below it: "Account: X (rate · source · date)", or "Rate not available, add an override".
    - Account (create mode hides investment and archived accounts)
    - Category ("group - name")
    - Payee
    - Currency
    - Note
    - Tags (comma-separated)
    - "Portfolio Holding *", required for investment accounts
  - Edit-mode extras:
    - "Linked transactions" panel listing sibling legs, which open on tap.
    - "Split this transaction" toggle with inline rows: Category, Amount, Note, "Add row", and a Balanced / left / over badge.
    - "Advanced Options": Quantity, Portfolio Holding, a "Business expense" checkbox.
    - Lot-reallocation notice with "Reallocate & save".
    - Footer showing Created, Updated and Source.
    - Delete button.
  - Transfer fields:
    - Date, "Amount sent", "From account", "To account".
    - Investment legs:
      - Both accounts investment: "Source holding *", "Quantity (shares) *", "Destination holding", "Destination quantity".
      - One account investment: "Holding in {acct} *" and "Quantity (shares) *".
    - Cross-currency: "Amount received ({ccy})", prefilled from market FX, with the implied rate and its source shown.
    - "Note (applied to both legs)", "Tags (applied to both legs)".
    - "Delete transfer (both legs)".
  - Edit routing: rows with a portfolio kind (buy, sell, fx_*, …) skip this dialog and redirect to `/portfolio/new?op=…&editId=`.
- **Split Transaction**: "Total amount" at the top. Rows of Category, Account, Amount, Note and Tags, each with a trash button. "Add row", an Allocated badge, validation that requires at least 2 rows summing to the total, and the buttons "Clear splits", Cancel, "Save splits".
- **Delete Transaction**: "Are you sure you want to delete {payee}?". If lots block the delete, it shows a reallocation notice, a "Dependent rows" list, and "Reallocate & delete".
- **Delete {n} Transactions**: the bulk delete confirm.
- Export CSV of the full filtered view: Date, Account, Category, Payee, Note, Tags, Quantity, Amount, Currency, Portfolio, Source.
- No keyboard shortcuts and no inline cell editing.

**API routes**
- `/api/transactions`: GET, POST, PUT, DELETE (`?id=&confirmReallocation=1`).
- `/api/transactions/bulk`
- `/api/transactions/splits`: GET, POST, DELETE.
- `/api/transactions/linked`
- `/api/transactions/transfer`: POST, PUT, DELETE.
- `/api/transactions/lot-replan-preview`
- `/api/transactions/calendar`
- `/api/fx/preview`
- `/api/accounts?includeArchived=1`, `/api/categories`, `/api/portfolio`, `/api/settings/active-currencies`
- `/api/settings/tx-columns`, `/api/settings/tx-sort`, `/api/settings/tx-filters`
- `/api/rules`: reachable only from the rule-suggestion path, which is off on this page.

**Judgement**
- Core:
  - List grouped by date.
  - Search plus the account, category and date filters.
  - Add, edit and delete a transaction. Add a transfer.
  - Month calendar with the income, spending and net tiles.
  - Bulk change category and bulk delete.
  - Drill-in from other screens via the URL params.
- Power-user:
  - Splits.
  - Cross-currency FX fields.
  - Investment-holding legs on transfers.
  - Per-column filter popovers.
  - Header sort.
  - Week and year calendar modes.
  - The other bulk actions (account, date, payee, note, tags).
  - CSV export.
  - Lot reallocation.
  - Linked-sibling panel.
  - Tag chips.
- Clutter or debug:
  - Kind, Canonical?, Created, Updated and Source columns.
  - Column drag-reorder and the three account-name column variants.
  - Duplicate entry points: the chevron menu and the "Investment Transactions" button. Native should use one "+" menu.
  - Two split editors (inline in the dialog and the separate dialog). Keep one.
  - Per-row split-badge fetch, an N+1 pattern.

## /transactions/audit

**Purpose:** resolve legacy transactions whose currency differs from their account's currency. This is migration cleanup. The page is not in the nav; the only way in is the dashboard banner.

**Sections, top to bottom**
- "Back to Transactions" link, the title "Currency Review", and a "Show resolved" checkbox.
- Empty state: "No flagged transactions".
- One card per flagged row:
  - "Transaction #{id}" and the date.
  - "Recorded as {amount ccy} in an account whose currency is {acctCcy}."
  - A resolution badge on resolved rows.
  - A conversion preview that loads lazily on hover: "{old} → {new} (rate · source)", and "Account balance will shift by X".

**Actions:** per row, "Convert", "Keep as-is", "Edit transaction" (links to `/transactions?id=`).

**API routes:** GET and PATCH `/api/transactions/audit`, `/api/fx/preview`.

**Judgement:** migration clutter that is empty for most users. Native should not give it its own screen. At most, show a "Needs review" item driven by the count.

---

## /budgets

**Purpose:** a monthly cash-flow budget covering expected income, debt payments and spending per category or group, with carryover.

**Sections, top to bottom**
1. `OnboardingTips`.
2. Header: "Budgets" with the subtitle "Plan the month's money in and out…".
   - "What counts" button: opens the settings dialog.
   - "Fill budgets" button: opens the Fill dialog for all spending lines.
3. Month stepper: ‹ Month YYYY ›, plus a "This month" button when you are on another month.
4. `MonthSummary` card:
   - Hero "Left to plan" (or "Over-planned") with a sentence comparing plans to expected income.
   - Stacked allocation bar: Spending, Debt payments, Left to plan. A marker shows where expected income ends, and "Over by $X" appears when plans exceed it.
   - Stat rows with progress against target: "Income received" of planned, "Spent" of budgeted, "Debt paid" of planned.
   - "$X still due this month".
   - "Age of money N days".
5. Notice and error strips, such as "Saved N budgets.", with Dismiss.
6. **Income** section. Columns: Expected (inline editable), Received, Status pill.
   - Row menu: Fill…, "Leave out of budget".
7. **Debt payments** section (only when loans exist). Columns: Planned, Paid, Status pill ("due MM-DD", paid, …).
   - The name links to the loan or account.
   - Sub line: "$P principal + $I interest" when the plan comes from the loan schedule.
   - Progress bar.
   - Menu: "Change how this account counts…", which opens the settings dialog.
8. **Spending** section, grouped by category group. Group headers collapse, and the collapsed state is kept in localStorage.
   - Filter chips with counts: All | Not budgeted | Overspent | Due later.
   - Columns: name (links to `/categories/[id]`), progress bar, Budgeted (inline editable, or "in group"), Spent, Left.
   - Icons: rollover and "payments due later".
   - Sub line: "carried in $X" and "$Y due later".
   - The Left cell tooltip shows what is left after upcoming payments.
   - Line menu:
     - Budget: "Use the 3-month average ($X)", "Fill this and later months…", "Clear this month's budget".
     - Carryover: "Roll leftover into next month" (checkbox). When on: a carry-negative toggle, "Reset carryover to 0 from this month", "Set carried in…".
     - "Leave out of budget".
   - Group menu:
     - "Budget as one line" (checkbox, with a confirm dialog).
     - "Use the 3-month average", "Fill this group…".
     - The same carryover items.
     - "Leave the group out of the budget".
   - Group row: a group budget cell (inline editable) when budgeted as one line.
9. Footer link: "N categories are left out of the budget", which opens the settings dialog.

**Inline edit:** `BudgetCell`. Click an amount to edit. Enter or blur saves, Escape cancels. It rejects values below 0 ("Enter 0 or more").

**Dialogs**
- **"Fill budgets: {scope}"**:
  - Use: last month's budget, last month's spending or income, average of 3, 6 or 12 months, the same month last year, or a fixed amount (with an amount input).
  - Months: 1 to N.
  - Increase: No change, By a percent, or By an amount. Applied once, every month, or every year in a chosen month.
  - Radio: "Only months without a budget" or "Replace existing budgets".
  - Preview (a table of rows), then Save.
- **"What counts in the budget"**:
  - Accounts list with a "Show archived" checkbox. Each account has a role select: Automatic, By category, As a debt payment, Not counted.
  - Excluded groups and categories, each with a "Bring back" button.
- **"Carried into {Month}: {name}"**: Amount ({ccy}). Buttons: "Remove pin" (work the amount out from earlier months), Cancel, Save.
- **Confirm "Budget {group} as one line"**: explains that category budgets merge into the group budget from this month on.

**API routes**
- `/api/budgets/month?month=` (GET)
- PUT: `/api/budgets/line`, `/api/budgets/settings`, `/api/budgets/carryover`
- `/api/budgets/fill` (preview and save)
- `/api/age-of-money`

**Judgement**
- Core:
  - Month stepper.
  - Left to plan hero.
  - Spending lines with inline budget edit, spent, left and progress bar.
  - Filter chips "Overspent" and "Not budgeted".
  - Income section.
  - "Use 3-month average".
- Power-user:
  - Fill dialog: its increase-per-year compounding is very advanced.
  - Carryover settings and "Set carried in".
  - Budget group as one line.
  - "What counts" account roles.
  - Debt payments section (useful for people with loans).
  - Due-later chip.
- Clutter:
  - Age of money: a YNAB-ism shown as a single number.
  - Allocation-bar marker detail.
  - Sub-line density. Rows carry name, two icons, a sub line, bar, three numbers and a menu. Native should show name, bar and left, with the detail on tap.

---

## /goals

**Purpose:** track savings, debt-payoff, investment and emergency-fund targets. Progress comes from linked account balances.

**Sections, top to bottom**
1. Header: "Financial Goals" and an "Add Goal" button.
2. Three summary cards (only when goals exist):
   - Total Target.
   - Current Progress. Both note "converted at today's rates" when any goal is in another currency.
   - Completed "N / M".
3. Empty state: "Set your first financial goal" with quick-start chips that prefill the form: Emergency Fund, Pay off debt, Save for vacation, Build investments.
4. Active goal cards, with a left border colored by type:
   - Name, a type badge (Savings, Debt Payoff, Investment, Emergency Fund), a currency badge when it differs from the display currency, linked-account badges, and a deadline badge.
   - "$current of $target", %, and a progress bar colored by %.
   - "Remaining: $X" and "$Y/mo needed".
   - Icon buttons: Edit, Mark complete, Delete.
   - "All goals completed!" state when nothing is active.
5. "Completed" section: compact rows with Edit, Reactivate and Delete.

**Dialogs**
- **"New Financial Goal"** and **"Edit Goal"** (same form):
  - Goal Name (placeholder "e.g. Emergency Fund").
  - Type: Savings, Debt Payoff, Investment, Emergency Fund.
  - Currency.
  - Target Amount.
  - Deadline (date).
  - Priority: High, Medium, Low.
  - Linked Accounts: a multi-select combobox with removable chips.
  - Note.
  - Cancel and Save.
  - There is no current-amount field. The current amount is derived from the linked accounts.
- **Confirm "Delete goal"**.

**Actions:** create, edit, delete, toggle complete or active. No filter, sort or tabs.

**API routes:** `/api/goals` (GET, POST, PUT for edit and status, DELETE `?id=`), `/api/accounts`.

**Judgement**
- Core: goal cards with the progress bar, remaining and monthly-needed figures; add and edit.
- Power-user: multi-account linking, per-goal currency.
- Clutter: Priority is collected but nothing sorts or shows it. The three summary cards add up dissimilar goals, so a sum of the targets means little.

---

## /subscriptions

**Purpose:** recurring bills and subscriptions: cost per month and year, next due date, and detection of untracked recurring payments. `/calendar` redirects here with `?view=calendar`.

**Sections, top to bottom**
1. Header: "Subscriptions" with the subtitle "Recurring bills and subscriptions…", and an "Add subscription" button.
2. Three stat cards: Per month, Per year, "Due in next 30 days". All in the display currency.
3. Tabs: **List | Calendar**. In list view, a "Sort by" select: Next payment, Monthly cost, Name.
4. List view:
   - "Found in your transactions" card. Detected recurring payees that aren't tracked yet: payee, "$avg / freq · seen N× · last date".
     - Buttons: "Review" (opens the dialog prefilled) and "Track" (adds it directly).
     - Shows 3 entries, with "Show all N" or "Show fewer".
   - Empty state: "No subscriptions tracked yet".
   - Groups: Active, Paused and Cancelled, each with a count. Each row has:
     - Name, a status badge, and "Cancel reminder {date}" when a reminder is set.
     - A meta line: "next {date} (in N days)" and the category.
     - "$amount / freq" and "≈ $X / mo".
     - Tapping the row opens Edit.
     - Row menu: Edit, "Remind me to cancel" or "Remove cancel reminder", Pause, "Mark cancelled", Resume (when paused), Reactivate (when cancelled), Delete.
5. Calendar view (`SubscriptionsCalendar`):
   - Month grid with prev/next. Each day shows event chips (bill or income) with a name and amount tooltip.
   - Tapping a day opens a side panel listing that day's events. Each has "Edit" (tracked) or "Track" (detected). Empty days show "Nothing expected on this day."
   - Month stats: Expected bills, Expected income, Net.

**Dialogs**
- **"New subscription"** and **"Edit subscription"**:
  - Name (placeholder "e.g. Netflix, car insurance, domain renewal").
  - Amount per payment.
  - How often: Weekly, Every 2 weeks, Monthly, Quarterly, Semi-annual, Annual.
  - Currency.
  - Next payment (date).
  - Category.
  - Paid from (account).
  - "Remind me to cancel on" (date).
  - Notes.
  - Save.
- **Confirm "Delete subscription"**: "Your transactions are not affected."

**API routes:** `/api/subscriptions` (GET, POST, PUT, DELETE `?id=`), `/api/recurring`, `/api/categories`, `/api/accounts`.

**Judgement**
- Core: monthly and yearly totals, the active list sorted by next payment, add and edit, and the "Found in your transactions" Track button (the best onboarding for this page).
- Power-user:
  - Cancel reminder.
  - Pause and cancel states.
  - The calendar view. It duplicates the transactions calendar idea, but this one is for future bills, so it earns its place. On native, Upcoming could be a list section instead of a grid.
- Clutter: the "Review" and "Track" pair (keep Track plus swipe to edit), and sort by Name.

---

## /import

### Where the import code lives
- `/import` (`src/app/(app)/import/page.tsx`) does not render `src/app/(app)/import/components/*` directly. It renders `src/components/inbox/*`.
- Its Upload drawer (`src/components/inbox/upload-drawer.tsx`) uses only three of those files: `column-mapping-dialog`, `ofx-confirm-dialog` and `file-drop-zone`, the last through `src/components/reconcile/upload-card.tsx`.
- The other `import/components` files surface on `/settings/import`. Its tabs are Templates, Email Import, "Migrate from another app" and "Investment statements".
- Dead code nothing imports:
  - `csv-mapper-dialog` (older CSV mapper)
  - `excel-mapper-dialog` (Excel import)
  - `pdf-preview` (PDF import)
  - `components/inbox/available-next-phase.tsx`
- `save-template-dialog` can never open: its host, `import-preview-dialog`, is only reached from the WealthPosition connector, which never passes `csvHeaders`.
- Excel and PDF import are not reachable from the current UI.
- Nav: `/import` is `mode: "prod"`, in the sidebar and the mobile bar.
- No devMode, isDev or NODE_ENV checks exist in any of these files.
- Redirects in `next.config.ts`: `/inbox`, `/reconcile`, `/import/reconcile` and `/import/classic` all go to `/import`. `/import/pending` is still its own route.

**Purpose:** one screen per account for getting money in. You upload a statement, then review the rows through one of three "lenses": Auto-pilot, Approve-each or Manual review.

### Sections, top to bottom
1. **Header.** "Import", a subtitle, and an **Upload** button that opens the UploadDrawer.
2. **Error banner** (red).
3. **Account card**
   - Account select. Items read "Name · CUR", plus " · hidden" for hidden accounts.
   - The list leaves out archived accounts and accounts hidden in settings, except a hidden account opened by deep link.
   - **LensChip.** A pill that opens a popover titled "View lens", with three options:
     - Auto-pilot: "File → ledger. Rules auto-categorize." 0 gates.
     - Approve-each: "File → bank. You approve each ledger entry." 1 gate.
     - Manual review: "Two gates. Staging two-pane, then bank-vs-transactions two-pane." 2 gates.
   - Popover badges: `policy`, `current lens`, `n/a`. Approve-each is disabled for investment accounts.
   - Popover footer link: "Open account settings (to change the policy)", to `/accounts/{id}#reconciliation-mode`.
   - **ModeBanner.** "{lens label} · {subLabel}", plus "Policy is X." when the lens differs from the policy.
4. **ReconcileSummaryPanel.** Collapsible: "Reconciliation summary · balance, last import & reconcile per account".
   - Loads on first expand.
   - Sortable table. Columns: Account (+ccy), Current balance (market value for investment accounts), Last import, Last reconciled, Pending (amber when above 0), and an **Open** button that switches the page's account.
   - **Refresh** button.
5. **Tabs**, set by the lens. **Email** is always shown and is not tied to an account.
   - Manual: Staging, Reconcile, Reconciled, Email. Opens on Staging.
   - Approve-each: To approve, Reconciled, Email. Opens on To approve.
   - Auto-pilot: To categorize, Reconciled, Email. Opens on To categorize.
6. **LensToast.** A floating toast shown while the lens differs from the account's policy.
   - Text: "Viewing X through Y lens · Layout-only…"
   - Buttons:
     - **Revert**: returns to the account's policy.
     - **Keep for now**: does nothing.
     - **Save as default**: `PATCH /api/accounts/{id}/mode {mode}`.
- URL state: `?account=`, `?tab=`, and `?window=all`, which opens the Reconcile tab on All.
- The dashboard Quick Import card can hand a file over. The drawer then opens and starts the upload on its own.

### Upload drawer ("Upload to {account}")
- **Header:** "Policy: X · N gates".
- **Amber card** when the account's CSV mapping mode is auto: "This account imports automatically", with button **Switch to confirm-first**.
- **ReconcileUploadCard fields:**
  - Account: read-only, locked to the page's account.
  - "Settlement-vs-posting fuzz (days)": number, 0 to 30, default 3.
  - "CSV template (optional…)": combobox, default "Auto-detect". Picking a template fills in its skip rows, date format and default currency.
  - "Statement balance (optional, CSV only)": number.
  - FileDropZone: `.csv,.ofx,.qfx`, drag and drop or click.
- **"After upload, {policy}" bullets:**
  - Auto-pilot: matched rules go to Reconciled, unmatched go to To categorize.
  - Approve-each: rows land in To approve.
  - Manual: rows land in Staging, and approved rows move to Reconcile.
- **Result panel**
  - "Upload complete: N rows from your CSV/OFX added…", plus the skipped-duplicate and error counts.
  - "Statement snapshot": Statement balance (+date), Date range, Rows parsed, Balance anchors.
  - "Where they landed".
  - Buttons: **Upload another**, **View rows**. Without a result: **Cancel**.
- Esc closes the drawer.
- **File-type flows.** Everything goes to `POST /api/import/staging/upload`, and the server branches on the account's policy. A 422 response opens one of two dialogs:
  - **CSV, `csv-needs-mapping` or `csv-confirm-mapping`: ColumnMappingDialog.** Title "Map CSV Columns" or "Confirm Column Mapping".
    - Import options:
      - Skip N header rows and Skip N footer rows: 0 to 100. Each change re-parses the file after a 400 ms pause, via `POST /api/import/preview`.
      - Date format: Auto-detect, DD/MM/YYYY, MM/DD/YYYY, YYYY-MM-DD.
      - Default currency.
      - "Flip sign of amounts" checkbox.
    - Column selects: Date*, Amount*, Account, Payee / Description, Category, Currency, Note, Tags, Balance (running).
    - Investment accounts add Ticker / Symbol / ISIN, Security name and Quantity.
    - Default Account.
    - "Save this mapping as a template": name field.
    - Radio "On future uploads to this account": "Ask me to confirm first" or "Apply this mapping automatically".
    - Sample table of the first 5 rows.
    - Buttons: **Cancel**, **Continue** (in confirm mode, **Import with this mapping**).
    - On confirm:
      - `PATCH /api/accounts/{id}/import-prefs`
      - `POST /api/import/templates`
      - the upload is re-sent with `confirmedMapping=1`
  - **OFX/QFX, `ofx-confirm`: OfxConfirmDialog.** Title "Confirm import, OFX statement".
    - Strip: "{n} transactions", "Statement balance", "Currency".
    - Preview table, first 50 rows. Columns: Date, Payee, Note, Type, Amount.
    - Radio "Payee comes from": Name field or Memo field. Switching swaps Payee and Note on screen.
    - Radio "On future uploads": confirm first or apply automatically.
    - Buttons: **Cancel**, **Import statement**.
    - On confirm: `PATCH /api/accounts/{id}/import-prefs`, then the upload is re-sent with `confirmedImport=1`.
  - **Investment statements, MoneyPro, connectors and template management** are not reachable from `/import`. They live on `/settings/import` (see the end of this section).

### Tab: Staging (Manual lens)
- This is the same component as `/import/pending`, embedded and limited to the current account. See the next section.
- The list view adds three things here:
  - Summary chips: "N batches pending review", "N rows pending to be loaded", "N duplicates (skipped by default)", "· N total parsed".
  - A "Loaded into the bank ledger" panel (RecentUploadsPanel), with batch undo.
  - A **Refresh** button.

### Tab: Reconcile (Manual lens)
Two panes that match ledger transactions against bank rows.
- **Date window.** From and To date inputs, plus presets **30d / 60d / 90d / 6mo / All**. The default is 60 days back with no end date.
- **BalanceSummaryCard:**
  - "Bank says (as of DATE)"
  - "Finlynq has"
  - "Delta": "✓ Balanced" or a signed amount in red
  - With no anchor yet: "Upload a statement balance to enable validation"
- **Left pane, "Transactions."**
  - Columns: checkbox, Date, Payee · category, status pill, Amount.
  - A suggestion appears as a SuggestionCard under its row:
    - "Exact match · import_hash match", or "Fuzzy match · score · reason"
    - **Reject** (hidden locally, never saved) and **Accept**
- **Right pane, "Bank ledger."**
  - Columns: checkbox, Date, Payee, status pill, Amount, Actions.
  - Investment accounts add Ticker, Security and Qty, plus a "→ buy" chip.
- **Status pills:** linked, extra link, suggested (exact), suggested (fuzzy), bank-only, tx-only.
- **Footer:** "N linked · N suggested · N bank-only · N tx-only".
- **Actions**
  - Accept a suggestion: `POST /api/reconcile/links {transactionId, bankTransactionId, linkType:"primary"}`.
  - **Unlink**: `DELETE /api/reconcile/links`.
  - **Create** on a bank-only row:
    - Cash account: opens TransactionDialog prefilled from the row. It opens on the Transfer tab when a transfer rule matches. After saving it calls `POST /api/reconcile/links`.
    - Investment account with a suggested op: opens InvestmentOpPreviewDialog (read-only).
      - Fields: Operation, Security, Quantity, Amount, Account.
      - **Record {op}**: `POST /api/reconcile/apply-rules {bankRowIds}`.
    - Investment account with no op: goes to `/portfolio/new?fromBankTransactionId=`.
  - Trash on any bank row: `DELETE /api/bank-transactions/{id}`. A 409 opens ConfirmDeleteBankRow (see the shared dialogs below).
  - Clicking a row highlights its linked rows in both panes. This includes trade and swap siblings.
  - Selection: checkboxes on each row, plus select-all in each pane header.
  - **Bulk link bar** (shown while anything is selected):
    - Text: "N tx (sum) × M bank (sum) = K links · Δ"
    - **Reconcile selected**: `POST /api/reconcile/links/bulk {transactionIds, bankTransactionIds}`
    - X clears the selection
  - **RecentUploadsPanel**, "Recent uploads (N)":
    - Rows show the date and time, a simplified/detailed chip, an upload/email/connector chip, "has linked tx", the filename, current/total rows and anchor count.
    - **Delete batch**: `DELETE /api/import/uploads/{batchId} {deleteLinkedTransactions}`.
    - A 409 opens "Delete batch with linked transactions?" with three buttons: "Delete all (bank rows + transactions)", "Keep transactions (drop bank lineage)", "Cancel".

### Tab: To approve (Approve-each lens)
- **Header:** "N rows waiting · M with a suggestion", with button **Accept all suggested (M)**. It sends every approve call at once and skips duplicates.
- **RowCard list**, newest first.
  - Line 1: date, payee, amount.
  - Line 2 is one of:
    - "Possible duplicate of an existing transaction · …"
    - "no match, needs your decision"
    - "match tx #N"
    - "transfer to [Account]"
    - "create as [Category]"
- **Buttons**
  - **Approve**: `POST /api/bank-transactions/{id}/approve` with `{categoryId}` or `{transferDestAccountId}`.
  - **Categorize** and pencil ("Edit row"): open TransactionDialog. After saving, `POST /api/reconcile/links`.
  - **Link to existing**: `POST /api/reconcile/links`.
  - **Keep separate**.
  - Trash ("Delete row"): `DELETE /api/bank-transactions/{id}`. A 409 opens the confirm modal.
- Investment accounts are blocked on this lens.

### Tab: To categorize (Auto-pilot lens)
- **Caption:** "N rows need categorizing, no rule matched these at upload."
- Uses the same RowCard as To approve, with these differences:
  - A category suggestion books the row with `POST /api/bank-transactions/{id}/categorize {categoryId}`.
  - Investment rows show **Record {op}**, which opens InvestmentOpPreviewDialog and calls `POST /api/reconcile/apply-rules`.
  - There is no "Accept all" and no transfer suggestion.
- **Empty state:** "Auto-pilot is handling everything…"

### Tab: Reconciled (all lenses)
- Read-only list: "Fully reconciled rows… N links."
- Each row shows the date, payee, a "primary" or "extra" badge, a category badge and the amount.
- The Auto-pilot lens adds the AutoRuleBanner:
  - Header: "N rows auto-applied by rules in the last 7 days".
  - Shows 5 rows, with a "Show N more" toggle.
  - Clicking a row goes to `/transactions?focusId=`.
  - Data: `GET /api/reconcile/auto-rule-recent?accountId`.

### Tab: Email (all lenses)
- **Header:** intro text and a **Refresh** button.
- **Email cards.**
  - Status badge: Pending, Needs review, Auto-recorded, Recorded, Duplicate, Unparseable or Discarded.
  - Subject, sender, received date, "purges {date}", the parsed amount and payee, and "rule matched".
  - Trash icon deletes the email.
- **Expanded card**
  - The email body, shown in a sandbox (an iframe with scripts blocked).
  - **"What we identified":** amount (outflow or inflow, sign assumed, card ending), payee, date, and "Why this needs review:" with the reasons.
  - **Create rule from this email** button.
  - **Rule hold box:**
    - When the email looks like a duplicate: **Record anyway** and **Discard**.
    - Otherwise: **Record with this rule**.
  - **Inline record form:** Account, Category, Amount, Date, Payee. Buttons **Record** and **Discard**.
  - After a duplicate warning on Record: **Record anyway** re-sends with force.
- **EmailRuleDialog** (titles "Create rule from this email", "Edit email rule", "New email rule"):
  - Rule name.
  - Conditions, all of which must match:
    - Field: Sender, Subject, Body, Payee, Amount.
    - Text fields: contains, exact, regex.
    - Amount: greater than, less than, between.
    - **Add condition** and remove buttons.
  - Target: Account, then Category or "Transfer to", then mode auto or review.
  - Field mapping: Reverse amount sign; Use date (from the body or the received date); Payee override; Currency.
  - "Will record: …" preview.
  - Buttons: **Create rule & record**, **Save changes** or **Add rule**.
  - Calls: `POST /api/email-rules` or `PUT /api/email-rules/{id}`, then `PATCH /api/import/email-inbox/{id}`.

### Shared dialogs
- **TransactionDialog** (`components/transactions/transaction-dialog.tsx`)
  - Transaction mode fields: Date, Amount, Account, Category, Payee, Currency, Note, Tags.
  - Optional parts: Portfolio Holding; "Split this transaction"; Advanced options (Quantity, Business expense).
  - Rule offer: "Also create a rule for next time". "Customize…" opens RuleEditorDialog.
  - Transfer mode fields: Amount sent, From account, To account, Amount received (when currencies differ), "Note (applied to both legs)", Tags.
  - Calls:
    - `POST /api/transactions`
    - `POST /api/transactions/transfer`
    - `POST /api/transactions/splits`
    - `GET /api/fx/preview`
    - `POST /api/rules`
- **ConfirmDeleteBankRow**
  - Title: "Delete bank-ledger row with linked transaction(s)?"
  - Buttons: "Delete all (bank row + transaction)", "Keep transaction (drop bank lineage)", "Cancel".

### API routes for /import
- **Page**
  - `GET /api/accounts`
  - `GET /api/settings/reconcile-hidden-accounts`
  - `PATCH /api/accounts/{id}/mode`
  - `GET /api/reconcile/summary`
- **Upload drawer**
  - `GET /api/import/templates`
  - `POST /api/import/staging/upload` (multipart, with these fields):
    - `accountId`, `templateId`, `tolerance`, `statementBalance`
    - `skipHeaderRows`, `skipFooterRows`, `dateFormatOverride`
    - `defaultCurrency`, `payeeSource`
    - `confirmedMapping`, `confirmedImport`
  - `POST /api/import/preview`
  - `POST /api/import/templates`
  - `PATCH /api/accounts/{id}/import-prefs`
- **Reconcile tab**
  - `GET /api/reconcile/suggestions?accountId&dateMin&dateMax`
  - `GET /api/reconcile/balance-summary?accountId`
  - `POST /api/reconcile/links` and `DELETE /api/reconcile/links`
  - `POST /api/reconcile/links/bulk`
  - `POST /api/reconcile/apply-rules`
  - `GET /api/categories`
  - `GET /api/portfolio`
  - `GET /api/import/uploads?accountId&limit=20`
  - `DELETE /api/import/uploads/{batchId}`
- **Approve and categorize queues**
  - `POST /api/bank-transactions/{id}/approve`
  - `POST /api/bank-transactions/{id}/categorize`
  - `DELETE /api/bank-transactions/{id}`
- **Email tab**
  - `GET /api/import/email-inbox`
  - `GET`, `PATCH` and `DELETE` on `/api/import/email-inbox/{id}` (PATCH `action`: record, record_rule or discard)
  - `POST /api/email-rules` and `PUT /api/email-rules/{id}`

### Judgement for /import
- **Core (weekly)**
  - Upload. The native version is `.fileImporter` plus drop.
  - The CSV mapping dialog (first time per bank) and the OFX confirm dialog.
  - The To approve and To categorize queues. These should merge into one native "Needs review" list with Approve, Categorize, Link to existing, Keep separate, Delete and Accept all.
  - The Bank vs Finlynq balance check.
  - The summary table, which works as the per-account entry list with a pending count.
  - Email review, for users who forward emails.
- **Power-user**
  - The Manual two-pane Reconcile: N×M bulk link, cross-pane highlighting, date presets, batch undo.
  - The lens versus policy model. It should collapse to one per-account setting; the temporary lens plus the toast is web cleverness.
  - The email rule editor, the AutoRuleBanner, and InvestmentOpPreviewDialog.
- **Clutter**
  - The Reconciled tab: a read-only list. It could be a filter on Transactions instead.
  - LensToast and the Keep-for-now state.
  - The ModeBanner text.
  - The fuzz-days field in the upload card.
  - RecentUploadsPanel, shown in two places.
  - The hide-accounts setting.

### /settings/import (reached from the import flow, listed for completeness)
- **Templates.** TemplateManager: "Saved Templates (N)".
  - Each row shows the name, "{n} headers · {defaultAccount}" and a `default` badge.
  - Pencil opens EditTemplateDialog:
    - Fields: Template Name, Default Account, "Default template" checkbox.
    - Upload Mode radio: Detailed or Simplified.
    - The same 9 column selects as the CSV mapping dialog, plus the import options.
    - Saves with `PUT /api/import/templates/{id}`.
  - Trash deletes with no confirmation: `DELETE /api/import/templates/{id}`.
  - Power-user.
- **Email Import.** EmailRulesManager:
  - Add, Enable/Disable, edit and delete rules (delete has no confirmation).
  - Calls `GET`, `PUT` and `DELETE` on `/api/email-rules`.
- **Migrate from another app.** One-time migration; clutter for a native app.
  - WealthPosition:
    - ZIP probe, then the mapping dialog "Map WealthPosition to Finlynq" (auto-create checkboxes, transfer and opening-balance categories, start date, per-entity overrides), then ImportPreviewDialog, then execute.
    - Optional API key and the "Reconcile balances" dialog.
    - Calls `/api/import/connectors/wealthposition/{credentials,zip-probe,zip-preview,zip-execute}`.
  - Money Pro: CSV preview, a map-accounts list (combobox or "+ Create new account" with Asset or Liability), then execute. Calls `/api/import/connectors/moneypro/{preview,execute}`.
  - Generic CSV (full ledger): 9 column selects, Default currency, "Import opening-balance rows", then map accounts. Calls `/api/import/connectors/generic-csv/{preview,execute}`.
- **Investment statements.** Accepts IBKR FlexQuery XML and OFX/QFX `INVSTMTRS` files.
  - The preview dialog binds each account in the file to a Finlynq account, shows Credits and Debits totals, and has an **Import N rows** button.
  - Calls `POST /api/import/preview` and `POST /api/import/execute`. This path skips staging.
  - Power-user, monthly at most.
- Bugs not worth copying:
  - The drop zone's "Supports CSV, OFX, and QFX" label is hard-coded, so it is wrong for XML.
  - The template empty state points to an unreachable "Save as Template" button.
  - The WealthPosition probable-duplicate checkboxes do nothing.

---

## /import/pending

**Purpose:** review staged imports (email forwards, file uploads, bank feeds) before they go into the bank ledger. It is the same `StagedReviewSurface` (`src/components/import/staged-review-surface.tsx`) as the Staging tab. This route covers all accounts and handles deep links: `?id=` opens a batch and `?account=` sets the default account.

### List view
- Header: "Pending Imports", "…Rows auto-expire after 60 days.", and a **Refresh** button.
- Toast and error cards.
- One card per batch:
  - Icon: Mail, Upload or Landmark (bank feed).
  - Headline: the email subject, the filename, or "Bank feed".
  - Subline: "from X · received …", "CSV upload · …", or "Bank feed · synced …".
  - Badges: "N rows", "N dupes", "Nd left".
- Empty state: "Nothing pending", with a **View import options** button that goes to `/import`.
- Click a card to open the detail view.

### Detail view, top to bottom
1. **ReconcileHeader**
   - "Back to Pending Imports".
   - Title: the filename or subject. Subline: "CSV upload · N rows · start → end".
   - Buttons:
     - **Open reconciliation**: link to `/reconcile`, which redirects to `/import`.
     - **Re-apply rules**: opens the "Re-apply rules?" dialog (warns that manual edits may be overwritten; Cancel / Re-apply).
     - **Discard all**: browser `confirm()`.
     - **Send to bank ledger (N)**.
2. **ReconciliationCallout**, shown only when the batch has a statement balance.
   - Columns: "Statement says (as of D)", "Bank ledger has", "After sending N rows".
   - ✓ or ⚠ with a 0.01 tolerance. On a mismatch it shows "Difference of X…".
   - Updates as checkboxes change.
3. **BalanceWarningBanner**
   - "Bank balance check: N days don't match the bank's reported balance".
   - **Details** / **Hide** opens a table. Columns: Date, Prior anchor, Expected, Bank says, Δ.
4. **Anchors-only hint**: "All N transactions … already in the bank ledger…"
5. **UnresolvedCategoriesBanner**, shown after an approve fails with `unresolved_categories`.
   - "N rows need a category before import".
   - One line per payee with a **Create rule** button, which opens RuleEditorDialog.
     - Title "Create rule from row", submit button "Create rule + apply".
     - Seeded with `payee contains X`.
     - Saves with `POST /api/import/staged/{id}/create-rule`.
6. **AccountSelector.** Hidden with one account. With several it is a Select: "Name · CUR (N rows)".
7. **Link-mode banner:** "Pick a transaction on the left pane to link to staged row #N", with **Cancel**.
8. **UnboundImportPicker.** Replaces the panes when an email CSV matched no template.
   - Header: "This email import didn't match any saved template", then From, subject and row count.
   - Preview table of the headers and sample rows.
   - "Apply a saved template": a select where matching templates are marked "★ matches headers", and an **Apply template** button.
   - "…or just bind to an account": an account select and a **Bind to account** button.
   - Both buttons call `PATCH /api/import/staged/{id}/bind`.
9. **Toolbar**
   - Legend: Matched (green), Only in file (amber), Only in ledger (slate).
   - "X new · Y only in ledger".
   - "Show only unmatched" toggle.
10. **Two panes**
    - Left, "Bank ledger (continuous)", DbPane.
      - Columns: Date, Payee · category, Type, Amount, Calculated (running balance), Loaded (bank anchor), Actions.
      - Type badges: Transfer, Income, True-up, Expense, linked, missing from statement.
      - Row actions:
        - **Pick**, only in link mode.
        - Flag ("Mark as missing from this statement") or unflag.
        - Trash ("Delete this bank-ledger row").
    - Right, "From the file (staged)", FilePane.
      - Columns: select-all checkbox, expand chevron, Date, Payee · category, Type, Amount, Balance (shown when the file has anchors), Actions.
      - Badges: dupe, imported, linked, suggested, already imported.
      - Row actions:
        - Link icon ("Link to a DB row").
        - X ("Mark as already imported"), which skips the row.
        - Un-skip.
        - Unlink.
    - **SuggestionsGroup** above the file table, "Suggested matches (N)".
      - Each card: an exact or fuzzy badge, "payee on date · amount ↔ existing tx #ID (…)".
      - Buttons: **Link**, and X to reject (local only).
11. **Expanded staged row editor.** Every field autosaves on blur or change.
    - Type: Expense, Income or Transfer.
    - Category: free text, placeholder "e.g. Groceries". There is no picker.
    - Payee.
    - Transfer only: "Pair with sibling row" (rows with the opposite amount) or "Or target account". Pick one; choosing one clears the other.
    - Investment only: Holding ("Cash (auto)" or a holding) and Quantity.
    - Entered amount.
    - Entered currency (ISO, max 4 characters).
    - Tags (comma-separated).
    - Note (max 2000 characters).
- There is no totals row. The aggregates are the callout figures, the counts in the toolbar and the count on the Send button.
- No keyboard shortcuts and no sort controls. The server returns rows newest first.

### User actions and APIs
- **Opening a batch**
  - `GET /api/import/staged`
  - `GET /api/import/staged/{id}`, `GET /api/accounts`, `GET /api/portfolio`
  - `GET /api/import/bank-ledger?accountId=`
- **Row edits:** `PATCH /api/import/staged/{id}/rows/{rowId}`. The same route handles:
  - link: `{reconcileState:"linked", linkedTransactionId}`
  - unlink: `unmatched`, `linkedTransactionId: null`
  - skip: `skipped_duplicate`
  - unskip: `unmatched`
- **Bank-row flags**
  - Flag: `POST /api/transactions/{txId}/reconciliation-flag {flag_kind:"missing_from_statement"}`
  - Unflag: `DELETE /api/transactions/{txId}/reconciliation-flag`
- **Delete bank row:** `DELETE /api/bank-transactions/{bankId}`. A 409 opens the delete modal with three choices.
- **Re-apply rules:** `POST /api/import/staged/{id}/apply-rules`, then a toast: "N rows updated by rules".
- **Send to bank ledger:** `POST /api/import/staged/{id}/approve {rowIds}`.
  - Writes only to `bank_transactions`.
  - The view stays open and approved rows are marked "imported".
- **Discard all:** `DELETE /api/import/staged/{id}`.
- **Create rule:** `POST /api/import/staged/{id}/create-rule`.
- **Bind:** `PATCH /api/import/staged/{id}/bind`.
- **Embedded Staging tab only:** `GET /api/import/uploads?accountId&limit=20` and `DELETE /api/import/uploads/{batchId}` (batch undo).
- **Select all:** "Select all sendable rows" skips rows that are imported, linked or skipped.

### Judgement for /import/pending
- **Core (weekly)**
  - Batch list, then open a batch.
  - Checkboxes and select-all, then **Send to bank ledger**.
  - Expanding a row to edit Type, Category and Payee.
  - Skip and un-skip.
  - Suggested matches: Link or reject.
  - Match colors and "Show only unmatched".
  - The statement-balance callout.
  - Discard.
  - The unresolved-categories banner with **Create rule**.
- **Power-user**
  - Manual link mode.
  - Flag "missing from statement".
  - Deleting a bank row from the three-way modal.
  - Re-apply rules.
  - The balance-warning details table and the Calculated and Loaded columns.
  - Transfer pairing, holding and quantity, entered amount and currency, tags and note.
  - AccountSelector, which only matters for CSVs covering several accounts.
  - UnboundImportPicker (email imports only).
- **Clutter**
  - Having both a standalone route and the embedded Staging tab. Natively, keep one screen plus a deep link for email imports.
  - "Open reconciliation", which duplicates the Reconcile tab.
  - The click-to-highlight, which duplicates the match colors.
  - The anchors-only hint.
  - The balance-drift banner built from the bank ledger, which duplicates Reconcile.
  - Category as a free-text box. Use a real picker natively.
- **Overlap with /import:** the bank pane overlaps the Manual Reconcile tab. The native app could fold "staging" into the queue model (parse review, then Needs review) and keep the two-pane view as an advanced screen.

Source root: `src/` in the Finlynq web repo (github.com/finlynq/finlynq).

---

## /categories

**Purpose:** see where money went in a month by category, compared with each category's usual month. This page is read-only. Category create, rename and delete are not here; they live in Settings (`/settings/categorization`) or MCP.

**Sections, top to bottom**
1. Header: "Categories".
   - Tabs: **Spending | Income** (`?type=I`).
   - Month stepper ‹ Month › (`?month=`). The next button is disabled at the current month.
2. Summary card:
   - "{Spending|Income} in {Month}" plus "so far" when the month is partial.
   - The big total.
   - "Usual month $X" with a % change colored good or bad.
   - A 100% stacked horizontal bar of the top segments plus "Other". The legend shows "Name N%".
3. "By category" list, with the description "Compared with each category's average over the previous complete months (up to 11) · CCY". Each row links to `/categories/[id]` and shows:
   - Color dot, name, and a sub line: "Group · usually $avg · budget $X".
   - A 12-month sparkline and "N% of {Mon}".
   - The amount and "+N% vs usual", or "none" / "none yet".
4. Footnote for a partial month: the amounts are month-to-date and converted at historical rates.

**Actions:** switch type, step the month, open a category. No create, edit, delete, sort or filter.

**API routes:** `/api/reports/categories?month=&type=&months=12`.

**Judgement:** core as the "where did my money go" view. It is clean and compact. The stacked bar and per-row sparkline are good native candidates (Swift Charts).

## /categories/[id]

**Purpose:** one category's history: monthly amounts against the average and budget, top payees, and recent transactions.

**Sections, top to bottom**
1. Header:
   - "← Categories" back link, the category name, a type badge (Income, Expense or Transfer) and a group badge.
   - Category switcher combobox.
   - Range tabs: **6M | 12M | 24M** (`?months=`).
2. Five stat tiles:
   - "This month so far".
   - "Last month (Mon)" with "±N% vs average".
   - "Monthly average" with "median $X".
   - "{Month} last year": the same month a year ago.
   - "Share of {spending|income}" over the last N months.
3. "Monthly {spending|income}" card:
   - Recharts ComposedChart: monthly bars, a dashed average line, and an amber budget marker when the category has a budget. The current month is styled as partial.
   - Tooltip: month, amount, transaction count, budget.
4. Two cards side by side:
   - "Top payees": payee, total and count. Each links to transactions filtered by category, payee and window. Shows "Unlock your data to see payees." when the data is locked.
   - "Recent transactions": payee, date, account and amount. Each links to `/transactions?id=`, and a "View all" link opens the filtered transactions.
5. Empty state: "No transactions in this category in the last N months".

**Actions:** switch category, change the range, drill into transactions. Read-only.

**API routes:** `/api/reports/category?categoryId=&months=`, `/api/categories`.

**Judgement:** core as a drill-down from Budgets and Categories. The 5 stat tiles are a lot. Keep this month, the average and last year, and drop Share and Last month or fold them into the chart.

---

## Cross-route notes for native

- Three calendars exist: the transactions calendar, the subscriptions calendar, and `/calendar` redirecting to subscriptions. Consider one calendar that shows past transactions and upcoming bills.
- "Recurring" appears in three places: the dashboard dev Insights, Subscriptions "Found in your transactions", and the Weekly Recap "Upcoming Bills". Make Subscriptions the single home.
- Month steppers appear on Budgets, Categories and the transactions calendar. One shared month picker would cover all three.
- Category management (CRUD) is not on any of these routes. Native needs to decide where it goes, probably Settings.
