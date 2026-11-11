# Finlynq REST API reference (native client)

Source: route handlers under `src/app/api/**/route.ts`, the lib functions they call, `src/middleware.ts`, `src/lib/auth/*`. Cross-checked against `mobile/src/api/client.ts` and `shared/types.ts`.

## Demo account

- Identifier: `demo@finlynq.com` (username `demo` also works)
- Password: `finlynq-demo`
- Server: `https://finlynq.com`. Data resets nightly.
- Sources: `src/app/cloud/page.tsx` (`?demo=1` prefill), `scripts/seed-demo.ts`, `src/app/try-demo/route.ts`.

## Global conventions

- Most routes return bare JSON. Errors are `{ error: string, code?: string, ... }`. Zod validation failures are `400 { error: "<issue messages joined by '; '>" }`.
- Exception: routes wrapped in `apiHandler` without `raw` (for example `GET /api/budgets/month`) return the envelope `{ success: true, data }` / `{ success: false, error }`. None of the endpoints below use it except where noted.
- Numbers. Postgres `double precision` columns and `SUM(...)` over them arrive as JSON numbers. `count(*)` (bigint) is NOT parsed by the pg driver and arrives as a string. That affects `GET /api/transactions` `total` (see there).
- Dates. Transaction `date`: `"YYYY-MM-DD"` (text column). Month keys: `"YYYY-MM"`. `createdAt` / `updatedAt`: ISO 8601 timestamps (`"2026-11-09T14:03:22.123Z"`).
- Amount sign. `transactions.amount` is signed, in the account's currency. Expenses and money out are negative, income and money in are positive. Liability balances are negative (sum of their transactions). Transfers: source leg negative, destination leg positive. Category type `R` (transfer) is exempt from the sign advisory. A sign that disagrees with the category type is accepted and returned as a top-level `warning` string on POST/PUT.
- Account `type`: `"A"` (asset) or `"L"` (liability). Category `type`: `"E"` expense, `"I"` income, `"R"` transfer/reconciliation. Categories have a free-text `group` and NO parent.
- Display currency: per-user setting `display_currency` in the `settings` table, default `"USD"` when unset. Returned by `GET /api/auth/session` (`displayCurrency`) and `GET /api/settings/display-currency`. Dashboard, budgets, portfolio overview and net-worth-history accept `?currency=XXX` (3 letters) to override it per request, and echo the resolved value as `displayCurrency`.
- Encryption. Names (accounts, categories, holdings) and transaction `payee` / `note` / `tags` are encrypted with a per-user key (DEK) held in server memory, keyed by the session JWT's `jti`. A server restart drops it.
  - Reads do not fail. Decrypted names come back `null`; transaction `payee` / `note` / `tags` come back as raw ciphertext strings starting with `v1:`.
  - Writes (POST/PUT on accounts, categories, transactions, transfers, holdings) return `423 { error: "session_locked", message: "..." }`. The user must log in again.
  - `GET /api/auth/session` reports `encryptionLocked: true` in this state, so check it on launch and on resume.

## Authentication

### How the server authenticates (`src/lib/auth/require-auth.ts`, `strategies/account.ts`)

- Strategy selection: `X-API-Key` header, `Authorization: Bearer pf_...`, or `?token=pf_...` selects API-key auth. Everything else uses account (JWT) auth.
- Account auth reads the JWT from `Authorization: Bearer <jwt>` first, then from the `pf_session` cookie. So the session JWT works as a Bearer token.
- JWT lifetime: 24 h (`SESSION_TTL_MS`). Cookie: `pf_session`, httpOnly, `SameSite=Lax`, `Secure` in production, `Path=/`, `Max-Age=86400`.
- 401 bodies:
  - `{ error: "Authentication required. Please log in." }` (no token)
  - `{ error: "Invalid or expired session. Please log in again." }` (bad, expired or revoked)
  - `{ error: "...", code: "deploy-reauth-required" }` (server rotated tokens on deploy)
  - `{ error: "...", code: "mfa-pending" }` (an MFA pending token used outside `/api/auth/mfa/verify`)

### CSRF gate in `src/middleware.ts` (affects a native client)

For POST/PUT/PATCH/DELETE, the middleware returns `403 { error: "csrf-rejected" }` when ALL of these hold:
1. the path is not one of `/api/auth/login`, `/api/auth/register`, `/api/auth/password-reset/request`, `/api/auth/password-reset/confirm`, `/api/auth/verify-email`;
2. there is no `Authorization: Bearer ...` header, no `X-API-Key`, and no `?token=pf_...`;
3. a `pf_session` cookie is attached;
4. `Origin` (or, if absent, `Referer`) is missing or does not match the server origin or `ALLOWED_ORIGINS`.

URLSession sends no `Origin` or `Referer`, so a cookie-only write gets 403. The two ways around it:
- Send `Authorization: Bearer <pf_session JWT>` on every request (recommended). Read the JWT from `HTTPCookieStorage` after login. httpOnly only hides it from browser JS.
- Or set `Origin: https://finlynq.com` (the server origin) on writes.

### POST /api/auth/login

Body (either field name works; `identifier` takes a username or an email):
```ts
{ identifier?: string /*1..254*/; email?: string /*legacy alias*/; password: string /*1..256*/ }
```
Responses:
- `200 { success: true }` with `Set-Cookie: pf_session=<jwt>`. The token is NOT in the body.
- `200 { mfaRequired: true, mfaPendingToken: string }` when MFA is enabled. No cookie. The pending token is a JWT valid for 5 minutes.
- `401 { error: "Invalid username or password." }`
- `429 { error: "Too many login attempts. Please try again later." }` with `Retry-After` (seconds). Limits: 5/min per IP, 10/h and 50/day per identifier.
- `403` when the server is not in Postgres mode. `500 { error }` if the key unwrap fails.

### POST /api/auth/mfa/verify

Body: `{ mfaPendingToken: string, code: string /* exactly 6 chars, TOTP */ }`. The route reads the token from the body; no auth header is needed.
- `200 { success: true }` with `Set-Cookie: pf_session=<jwt>` (full session, `mfa: true`).
- `401 { error }` for a bad or expired pending token, a wrong code, or a pending session with no key.
- `429` after 5 wrong codes on one pending token (log in again) or 5/min per IP.
- `400 { error: "MFA is not configured for this account." }`
- This path is not in the CSRF bypass list. Do not attach a stale `pf_session` cookie, or send `Origin`.

### GET /api/auth/session

Never returns 401. Unauthenticated (including an MFA pending token): `200 { authenticated: false, method: null, userId: null }`.
Authenticated:
```ts
{
  authenticated: true;
  method: "account" | "api_key";
  authMethod: "account" | "api_key";   // same value
  userId: string;                      // UUID-like text
  mfaVerified: boolean;
  encryptionLocked: boolean;           // true = no key in memory, writes will 423
  onboardingComplete: boolean;
  isAdmin: boolean;
  username: string | null;
  email: string | null;
  displayName: string | null;
  displayCurrency: string;             // default "USD"
  fxRatesInverted: boolean;
}
```

### POST /api/auth/logout

No body. Always `200 { success: true }` and clears the cookie (`Max-Age=0`).
- It revokes the JWT `jti` and drops the key ONLY when it reads the token from the `pf_session` cookie. It ignores `Authorization: Bearer`.
- To revoke server-side, send the cookie plus `Authorization: Bearer <same jwt>` (the bearer skips the CSRF gate). Also delete the cookie locally.

### Token in body / Bearer summary

- No route returns the session JWT in a response body. Only the MFA branch returns `mfaPendingToken`.
- `Authorization: Bearer <session JWT>` is accepted everywhere `requireAuth` runs, and it bypasses CSRF.
- `Bearer pf_<api key>` is a separate API-key path. Those keys are created in settings.

## GET /api/dashboard

Auth: `requireAuth`. It does not 423 with a locked key. Names come back null and investment accounts fall back to the ledger balance.
Query: `currency?` (3 letters); `startDate?` and `endDate?` (`YYYY-MM-DD`). Default range is the 1st of the same month one year ago through `YYYY-MM-31` of the current month (string compare). `includeArchived` is ignored; archived accounts are always included.
```ts
{
  displayCurrency: string;
  balances: Array<{
    accountId: number;
    accountName: string | null;      // decrypted, null when locked
    alias: string | null;
    accountNameCt: string | null;    // ciphertext, ignore
    aliasCt: string | null;          // ciphertext, ignore
    accountType: "A" | "L";
    accountGroup: string;
    currency: string;                // account currency
    archived: boolean;
    isInvestment: boolean;
    balance: number;                 // account currency. Investment: holdings market value. Else: SUM(amount). Liabilities negative.
    cashFlowBasis: number;           // raw SUM(amount) in account currency
    holdingsValue: number;           // 0 when not investment or locked
    holdingsCostBasis: number;
    convertedBalance: number;        // balance converted to displayCurrency at the current rate
    displayCurrency: string;
  }>;                                // ordered by type, group
  incomeVsExpenses: Array<{ month: "YYYY-MM"; type: "I" | "E"; total: number }>;
                                     // signed: E totals are negative. Display currency, 2 dp, sorted by month.
  incomeExpenseBreakdown: Record<"YYYY-MM", {
    income: Array<{ name: string; value: number }>;
    expenses: Array<{ name: string; value: number }>;  // positive magnitudes
  }>;                                // top 10 categories + "Other"
  spendingByCategory: Array<{
    categoryId: number | null; categoryName: string; categoryGroup: string | null;
    categoryType: string | null; total: number;        // expense categories only, negative, sorted ascending (largest spend first)
  }>;
  netWorthOverTime: Array<{ month: "YYYY-MM"; cumulative: number; currency: string }>;
                                     // NOTE: despite the name this is the monthly NET CHANGE (SUM of that month's amounts).
                                     // The web page builds the running total client-side. Prefer /api/net-worth-history.
}
```
Net worth the way the web and mobile compute it: `sum(convertedBalance)` over all rows (liabilities are already negative). Status: `500 { error }` on failure.

## Accounts

### GET /api/accounts

Auth: `requireAuth` (no 423). Query: `includeArchived=1` to include archived accounts (default excludes them). Returns a bare array of full DB rows plus decrypted names. No balances. Balances come from `/api/dashboard` `balances`.
```ts
Array<{
  id: number;
  userId: string;
  type: "A" | "L";
  group: string;                       // "" allowed for assets
  currency: string;                    // ISO code, e.g. "CAD"
  note: string | null;
  archived: boolean;
  isInvestment: boolean;
  mode: "auto" | "approve" | "manual"; // reconciliation policy
  ofxPayeeSource: "name" | "memo";
  csvMappingMode: "confirm" | "auto";
  budgetRole: "categories" | "debt_payment" | "excluded" | null;
  budgetPaymentAmount: number | null;
  name: string | null;                 // decrypted, null when locked
  alias: string | null;
  nameCt, nameLookup, aliasCt, aliasLookup: string | null; // ciphertext / HMAC, ignore
}>
```
Ordered by `type`, then `group` (not by name).

Writes use the collection route:
- POST: body `{ name, type, group, currency, note?, alias? (<=64), isInvestment? }`. Returns `201` with the raw row (`name` absent, only ciphertext). `409` on a duplicate name. `423` when locked.
- PUT: body `{ id, name?, type?, group?, currency?, note?, archived?, alias?: string|null, isInvestment? }`. Returns the raw row. `404`, `409`, `423`.
- DELETE `?id=`: `{ ok: true }`. `409 { error }` when linked records exist (archive instead).

### GET /api/accounts/[id]

Does not exist. `src/app/api/accounts/[id]/` only has `import-prefs`, `mode` (PATCH), and `opening-balance`. Filter the list client-side.

## Transactions

### GET /api/transactions

Auth: `requireAuth` (no 423). Query params:

| Param | Meaning |
|---|---|
| `limit` (default 100), `offset` (default 0) | page |
| `startDate`, `endDate` | `YYYY-MM-DD`, inclusive |
| `accountId`, `categoryId` | single id |
| `accountIds`, `categoryIds` | comma-separated ids |
| `search` | case-insensitive substring of decrypted payee, note or tags. Scans ALL matching history. |
| `tag` | exact tag match in the comma-split tags |
| `filter_payee`, `filter_note`, `filter_tags`, `filter_accountName`, `filter_accountAlias`, `filter_portfolio`, `filter_portfolioTicker` | substring filters on decrypted text |
| `amountMin`, `amountMax`, `amountEq`, `quantityMin`, `quantityMax`, `quantityEq` | signed numeric filters |
| `sources` | comma list of source values (for example `manual`) |
| `createdAtFrom`, `createdAtTo`, `updatedAtFrom`, `updatedAtTo` | anything `new Date()` parses |
| `portfolioHoldingId`, `portfolioHolding` (name or symbol) | holding filter |
| `id` | single transaction. A non-positive or non-numeric value returns `{data:[],total:0}`. |
| `sort` | `date` (default), `amount`, `quantity`, `createdAt`, `updatedAt`, `source`, `accountType`. Tiebreak `id DESC`. |
| `sortDir` | `asc` or `desc` (default `desc`) |

Response:
```ts
{
  data: Array<{
    id: number;
    date: string;                       // YYYY-MM-DD
    accountId: number | null;
    accountName: string | null;         // decrypted
    accountAlias: string | null;
    accountType: "A" | "L" | null;
    categoryId: number | null;          // null = uncategorized
    categoryName: string | null;
    categoryType: "E" | "I" | "R" | null;
    currency: string;                   // account currency
    amount: number;                     // signed, account currency
    enteredCurrency: string | null;     // what the user typed (null on old rows)
    enteredAmount: number | null;
    enteredFxRate: number | null;
    quantity: number | null;            // shares, for portfolio rows
    portfolioHoldingId: number | null;
    portfolioHolding: string | null;    // holding display name
    portfolioHoldingSymbol: string | null;
    payee: string | null;               // decrypted; "v1:..." ciphertext when locked
    note: string | null;
    tags: string | null;                // comma-separated
    linkId: string | null;              // shared by both legs of a transfer
    createdAt: string;                  // ISO timestamp
    updatedAt: string;
    source: string;                     // "manual", "import", ...
    kind: string | null;                // portfolio op type, "opening_balance", null for normal rows
    tradeLinkId: string | null;
  }>;
  total: number | string;
}
```
`total` is a string (`"253"`) when no text filter is active (`search`, `tag`, or any `filter_*` except `filter_portfolioTicker`), because it comes from `count(*)`. With a text filter it is a number. Decode both forms.

### POST /api/transactions

Auth: `requireEncryption` (423 when locked).
```ts
{
  date: string;                 // YYYY-MM-DD
  accountId: number;            // > 0
  categoryId: number;           // > 0 (required; 0 is rejected)
  amount?: number;              // signed, account currency
  currency?: string;            // defaults to account currency
  enteredAmount?: number;       // either amount or enteredAmount is required
  enteredCurrency?: string;     // server converts to account currency at the date's rate. enteredAmount wins over amount.
  payee?: string; note?: string; tags?: string;
  quantity?: number; portfolioHoldingId?: number; portfolioHolding?: string;
  isBusiness?: number;          // 0/1
  splitPerson?: string; splitRatio?: number;  // accepted but no such columns, effectively ignored
}
```
- `201`: the raw inserted DB row, plus `warning?: string`. Caution: `payee`, `note` and `tags` in this response are ENCRYPTED (`v1:...`), and there are no name fields. Re-fetch with `GET /api/transactions?id=<id>` to display it.
- `400 { error }` validation, or `{ error, code: "fk_violation" }`, or an investment account without a holding (`{ error, code, accountId }`).
- `404 { error: "Not found" }` for a foreign or missing account or category.
- `409 { error, code: "fx-currency-needs-override", currency }` when no FX rate exists.
- `423` when the session is locked.

### PUT /api/transactions (update)

There is no `/api/transactions/[id]` PUT/PATCH/DELETE. `src/app/api/transactions/[id]/` only has `reconciliation-flag`. Update with PUT on the collection, `id` in the body:
```ts
{ id: number; date?; amount?; accountId?; categoryId?; currency?; enteredAmount?; enteredCurrency?;
  payee?; note?; tags?; quantity?; portfolioHoldingId?: number | null; portfolioHolding?;
  isBusiness?; confirmReallocation?: boolean }
```
- Changing `amount`, `currency` or `entered*` also requires `accountId` in the body, else `400 "accountId is required when amount or currency is being changed"`.
- `200`: raw updated row (payee, note and tags encrypted) plus `warning?`.
- `409 { code: "transfer_leg_edit_refused", fields, partnerTransactionId }`: you edited the amount, account or date of one transfer leg. Use PUT `/api/transactions/transfer`.
- `409 { code: "portfolio_edit_blocked", blockingClosureTxIds }`: lot-locked. Resend with `confirmReallocation: true`.
- `400`, `404` and `423` as for POST.

### DELETE /api/transactions?id=<id>

Auth: `requireAuth`. Optional `&confirmReallocation=1`.
- `200 { success: true, deletedIds: number[], cascaded: ..., reallocated?: ... }`. Deleting one transfer or trade leg cascades to its siblings.
- `400 { error: "Missing id" }`, `404`, or `409 { code: "portfolio_edit_blocked", blockingClosureTxIds }`.

### POST /api/transactions/transfer

Auth: `requireEncryption`.
```ts
{
  fromAccountId: number; toAccountId: number;   // > 0, must differ
  enteredAmount: number;        // >= 0, POSITIVE, in the source account's currency. 0 only for in-kind moves.
  date?: string;                // YYYY-MM-DD, default today
  receivedAmount?: number;      // cross-currency: amount that landed, in the destination's currency. If omitted, the server converts at its FX rate.
  note?: string; tags?: string;
  holdingName?, destHoldingName?: string; quantity?, destQuantity?: number; fromHoldingId?, toHoldingId?: number;  // in-kind share moves
}
```
`201`:
```ts
{ ok: true; linkId: string /*uuid*/; fromTransactionId: number; toTransactionId: number;
  fromAmount: number /*negative*/; fromCurrency: string; toAmount: number /*positive*/; toCurrency: string;
  enteredFxRate: number; isCrossCurrency: boolean;
  holding?: { name, destName: string; quantity, destQuantity, fromHoldingId, toHoldingId: number } }
```
Errors are `{ error, code, currency?, side?: "source"|"destination" }`:
- `409` for `fx-currency-needs-override`
- `404` for `account-not-found`, `transfer-not-found`, `not-a-transfer-pair`
- `422` for `same-account`, `invalid-amount`, `holding-not-found`, `no-cash-holding`, `invalid-holding-spec`
- `400` for an investment holding that is required but missing

PUT on the same path takes `{ linkId? | transactionId?, ...same optional fields }`. DELETE takes `{ linkId? | transactionId? }`.

## GET /api/categories

Auth: `requireAuth` (no 423). No params. Bare array, ordered by `type`, then `group`:
```ts
Array<{ id: number; userId: string; type: "E" | "I" | "R"; group: string; note: string | null;
        name: string | null /*decrypted*/; nameCt: string | null; nameLookup: string | null }>
```
No parent and no hierarchy. `group` is the only grouping.
- POST body `{ name, type, group, note? }`. `type` also accepts aliases such as `"expense"` and `"income"`, normalized to the single-letter code. Returns `201` with the raw row.
- PUT body `{ id, ... }`.
- DELETE `?id=`: `409` when the category is in use.

## Budgets

### GET /api/budgets (legacy per-category; the one mobile uses)

Auth: `requireAuth`. Query:
- `month=YYYY-MM`. Omit it and you get every month.
- `spending=1` computes spending. It only takes effect together with `month`.
- `rollover=1`, also only with `month`.
- `currency?`

Income-category budgets are filtered out. Ordered by category group.
```ts
Array<{
  id: number; categoryId: number;
  categoryName: string;               // "Category #<id>" style fallback when locked
  categoryGroup: string | null; categoryType: "E" | "R" | null;
  month: "YYYY-MM";
  amount: number;                     // budgeted, in `currency`, positive
  currency: string;
  convertedAmount: number;            // budgeted in displayCurrency
  displayCurrency: string;
  spent: 0;                           // ALWAYS 0, never filled. Use convertedSpent.
  convertedSpent: number;             // positive magnitude, display currency, 2 dp. 0 unless spending=1&month=.
  rolloverAmount: number;             // 0 unless rollover=1&month=
}>
```
POST `{ categoryId, month, amount, currency? }` upserts and returns `201` with the row. DELETE `?id=` returns `{ success: true }`.

### GET /api/budgets/month?month=YYYY-MM (Budget v2; what the web page uses)

ENVELOPED: `{ success: true, data: BudgetMonth }`. `400 { success:false, error:"month must be YYYY-MM." }`. Defaults to the current month. All numbers are in display currency. Spending is positive, refunds are netted.
```ts
BudgetMonth = {
  month: string; currency: string; today: string;
  summary: { plannedIncome, receivedIncome, plannedSpending, spent, plannedDebt, paidDebt, leftToPlan, netCashFlow, upcoming: number };
  counts: { notBudgeted, overspent, withUpcoming: number };
  income: BudgetGroup[]; spending: BudgetGroup[]; debt: DebtLine[];
  excluded: Array<{ key: string; categoryId: number; name: string; group: string; type: "E"|"I"; by: "category"|"group" }>;
  accounts: Array<{ id; name; type; currency; isInvestment; archived; role; storedRole; automaticRole; paymentAmount; linkedLoans }>;
}
BudgetGroup = { key: string /* "c:<id>" | "g:<name>" */; name: string; byGroup: boolean; rollover: boolean;
  rolloverNegative: "carry"|"reset"; budgeted: number|null; actual: number; carriedIn: number|null; left: number|null;
  upcoming: number; average3: number; status: Status; lines: BudgetLine[] }
BudgetLine = { key; categoryId: number|null; name: string; budgeted: number|null; actual: number; carriedIn: number|null;
  left: number|null; rollover: boolean; rolloverNegative; average3: number; upcoming: number; status: Status }
Status = "unbudgeted"|"ok"|"warn"|"over"|"received"|"expected"
```

## Portfolio

### GET /api/portfolio/overview (web portfolio page and mobile PortfolioScreen)

Auth: `requireAuth`. Query: `currency?`. When locked, names and symbols are null and prices cannot be looked up, so check `encryptionLocked` first. Units: `*Display` fields are in `displayCurrency`. Unsuffixed or `*Native` money fields are in the holding's quote currency (`quoteCurrency ?? currency`).
```ts
{
  displayCurrency: string;
  holdings: Array<{                      // one row per position (holding x account)
    id: number; securityId: number | null; securityName: string | null;
    accountId: number | null; accountName: string /* "Unknown" fallback */;
    name: string | null; symbol: string | null; quoteName: string | null;
    currency: string; quoteCurrency: string | null;
    assetType: "etf" | "stock" | "crypto" | "cash" | "metal";
    price: number | null; change: number | null; changePct: number | null; dayChangeDisplay: number | null;
    marketCap: number | null; image: string | null;
    quantity: number | null; avgCostPerShare: number | null;
    totalCostBasis: number | null; costBasisDisplay: number | null; lifetimeCostBasis: number | null;
    marketValue: number | null; marketValueDisplay: number | null;
    unrealizedGain: number | null; unrealizedGainPct: number | null; unrealizedGainDisplay: number | null;
    realizedGain: number | null; realizedGainDisplay: number | null;
    dividendsReceived: number | null;
    totalReturn: number | null; totalReturnDisplay: number | null; totalReturnPct: number | null;
    firstPurchaseDate: string | null /*YYYY-MM-DD*/; daysHeld: number | null;
    pctOfPortfolio: number | null;       // percent, 2 dp
  }>;
  byHolding: Array<{                     // same security pooled across accounts, sorted by marketValueDisplay desc
    key: string; symbol: string | null; name: string; description: string | null; assetType: string;
    totalQty: number; avgCostDisplay: number | null; currentPriceDisplay: number | null;
    costBasisDisplay: number; marketValueDisplay: number; unrealizedGainDisplay: number; unrealizedGainPct: number | null;
    realizedGainDisplay: number; dividendsDisplay: number; totalReturnDisplay: number; totalReturnPct: number | null;
    dayChangeDisplay: number | null; dayChangePct: number | null;
    nativeCurrency: string | null;       // null when members differ; then every *Native field is null
    avgCostNative, currentPriceNative, costBasisNative, marketValueNative, unrealizedGainNative,
    realizedGainNative, dividendsNative, totalReturnNative, dayChangeNative: number | null;
    pctOfPortfolio: number | null; accountCount: number; image: string | null;
  }>;
  summary: {
    totalHoldings: number; totalAccounts: number; totalValueDisplay: number;
    dayChangeDisplay: number; dayChangePct: number; hasQuantityData: boolean;
    totalCostBasisDisplay: number; totalUnrealizedGainDisplay: number; totalUnrealizedGainPct: number;
    totalRealizedGainDisplay: number; totalDividendsDisplay: number; totalReturnDisplay: number; totalReturnPct: number;
  };                                     // all numbers, 2 dp, never null
  byType: Record<"etf"|"stock"|"crypto"|"cash"|"metal", { count: number; value: number /* display, unrounded */ }>;
  byAccount: Record<string /* account name */, { count: number; value: number }>;
  etfXray: { etfCount: number; etfTotalValueDisplay: number; etfs: EtfDetail[]; regions: Record<string, number>;
             sectors: Record<string, number>; aggregatedStocks: AggregatedStock[] };
  topGainers: Array<{ key: string; symbol: string | null; name: string; image: string | null;
                      dayChangeDisplay: number; changePct: number | null }>;   // up to 5
  topLosers:  same shape;
}
```
Percentages are in percent units (12.34 means 12.34%), not fractions.

### GET /api/portfolio (holding list for pickers)

Bare array: `{ id, accountId: number|null, accountName: string|null, name: string|null, symbol: string|null, currency: string, isCrypto: number /*0|1*/, isCash: boolean, note: string|null, currentShares: number }[]`. No prices.

## GET /api/net-worth-history

Auth: `requireAuth`. Query:
- `period`: `6m` (default), `1y`, or `all`
- `accountId?`: one account
- `basis`: `native`, only honored together with `accountId`; otherwise `reporting`
- `currency?`
```ts
{
  displayCurrency: string;
  period: "6m" | "1y" | "all";
  accountId: number | null;
  series: Array<{
    date: string;                       // YYYY-MM-DD, one point per DAY
    value: number;                      // net worth, liabilities negative, in seriesCurrency
    breakdown: Array<{ id?: number; name: string; value: number }>;  // top 10 accounts by |value| + "Other" (the "Other" row has no id)
    members: Array<{ id: number; name: string; value: number }>;           // every account
  }>;
  hasInvestmentData: boolean;
  fxApproximation: boolean;
  basisUsed: "reporting" | "native";    // label the chart from this
  seriesCurrency: string;
}
```
The last point is today's live value. Snapshots rebuild in the background, so a first call after edits can be stale. `500 { error }` on failure.

## Routes added for the native screens

Each shape below was checked against the route handler and a GET on the demo. Swift method names are in `Finlynq/API/Endpoints.swift`. Writes to these routes were not run against the demo.

| Method | Route | Notes |
|---|---|---|
| `spotlight()` | GET `/api/spotlight` | `{ items: [{ id, type, severity, title, description, actionUrl, amount?, currency }] }`. Empty on the demo. |
| `subscriptions()` | GET `/api/subscriptions` | Bare array. `name`, `categoryName`, `accountName` are decrypted. `displayAmount` is in the display currency. |
| `createSubscription(_:)` | POST `/api/subscriptions` | `{ name, amount, currency?, frequency?, categoryId?, accountId?, nextDate?, status?, notes? }`. 423 when locked. |
| `recurringSuggestions()` | GET `/api/recurring` | `{ recurring: [{ payee, avgAmount, currency, avgAmountDisplay, frequency, count, lastDate, nextDate, accountId, categoryId }], displayCurrency, monthlyRecurringTotal, count }`. |
| `goals()` | GET `/api/goals` | Bare array with progress fields (`currentAmount`, `percentComplete`, `remaining`, `monthlyNeeded`). |
| `loans()` | GET `/api/loans` | Bare array with the loan terms plus a computed summary. |
| `loanAmortization(id:extra:)` | POST `/api/loans` `{ action: "amortization", loanId, principal, annualRate, termMonths, startDate, paymentAmount, paymentFrequency, extraPayment, residualValue }` | The server needs the terms in the body, so the client reads `GET /api/loans` first. Returns `{ monthlyPayment, totalInterest, payoffDate, schedule[], monthlyAccrual[] }`. `Fixtures/loans-amortization.json` is the demo's answer for the fixture loan's terms (a compute-only call; nothing is saved). |
| `createLoan(_:)`, `updateLoan(_:)` | POST and PUT `/api/loans` | POST takes the loan's terms (`name, type, accountId, currency, principal, annualRate, termMonths or paymentAmount, startDate, paymentFrequency, extraPayment`). PUT takes `id` plus only the changed fields; the server merges them over the saved loan. Not run against a server. |
| `balanceSummary(accountId:)` | GET `/api/reconcile/balance-summary?accountId=` | Enveloped `{ accountId, currency, latestAnchor, bankSideLatest, systemSideLatest, delta, status }`. The demo has no statement anchors, so `status` is `no_anchor` and `latestAnchor` is null there. |
| `budgetMonth(_:)` | GET `/api/budgets/month?month=` | Enveloped. |
| `setBudget(categoryId:month:amount:)` | PUT `/api/budgets/line` `{ key: "c:<categoryId>", month, amount \| null }` | Amount in the display currency. `null` clears the cell. |
| `holdingLots(holdingId:)` | GET `/api/portfolio/holdings/[id]/lots` | Bare `{ lots[], closures[] }`. |
| `recordInvestment(_:)` | POST `/api/portfolio/operations/{buy,sell,income-expense,deposit,withdrawal,swap}` | Bodies in the zod schemas of each route. Not wrapped in the envelope. 400 `cash_sleeve_not_found` and similar carry a `code`. |
| `dividends(year:)` | GET `/api/portfolio/dividends?taxYear=` | Enveloped. The param is `taxYear`, not `year`. |
| `realizedGains(year:)` | GET `/api/portfolio/realized-gains?taxYear=` | Enveloped. |
| `incomeStatement(from:to:)` | GET `/api/reports?type=income-statement&startDate=&endDate=` | Bare. There is no `period` parameter, so the client has no `period:` argument. |
| `stagedBatches()` | GET `/api/import/staged` | Bare array of batches, not rows. 423 when locked. |
| `stagedDetail(id:)` | GET `/api/import/staged/[id]` | `{ staged, rows[], suggestedMatches[], balanceWarnings, ... }`. `stagedImports()` flattens every batch's rows and tags each with `importId`. |
| `approveStaged(importId:ids:)` | POST `/api/import/staged/[id]/approve` `{ rowIds? }` | Sends the rows to the bank ledger, not to `transactions`. |
| `linkStaged(importId:rowId:transactionId:)` | PATCH `/api/import/staged/[id]/rows/[rowId]` `{ reconcileState: "linked", linkedTransactionId }` | |
| `importPreview(file:accountId:)` | POST `/api/import/preview` (multipart `file`) | The response shape depends on the file type (`csv`, `ofx`, `pdf`, `excel`, `investment-statement`, `csv-needs-mapping`). The route ignores `accountId`. |
| `importExecute(_:)` | POST `/api/import/execute` `{ rows[], forceImportIndices? }` | Returns `{ total, imported, skippedDuplicates, errors? }`. |
| `uploadStatement(file:accountId:)` | POST `/api/import/staging/upload` (multipart) | Creates a staged batch. The web Import page uses it. 422 opens a mapping or OFX confirmation step unless `confirmedMapping=1` and `confirmedImport=1` are sent. |
| `rules()`, `createRule(_:)` | GET and POST `/api/rules` | `{ name, conditions: { all: [...] }, actions: [...], priority?, isActive? }`. |
| `settings()` | GET `/api/user/me` and GET `/api/settings/display-currency` | There is no `/api/settings` route (it 404s). |
| `setDisplayCurrency(_:)` | PUT `/api/settings/display-currency` `{ displayCurrency }` | 400 `currency-unsupported` for codes without a live rate. |
| `importEmailAddress()` | GET `/api/import/email-config` | `{ email: string \| null }`. POST on the same route generates one and returns `{ email, webhookSecret }`. |
| `deleteAccount(password:mfaCode:)` | POST `/api/auth/delete-account` `{ password, confirmation: "DELETE", mfaCode? }` | Rate limit 3 per hour. Account session only. |
| `bulkUpdateTransactions(ids:changes:)` | POST `/api/transactions/bulk` `{ action, ids, <field> }` | Actions: `delete`, `update_category`, `update_account`, `update_date`, `update_note`, `update_payee`, `update_tags`. One field per call. |
| `splits(transactionId:)` | GET `/api/transactions/splits?transactionId=` | Bare array. |
| `stageTransaction(_:)` | POST `/api/import/staging/upload` | The only session-authenticated way to create a staged row. The client uploads a one-row CSV with the headers `Date,Account,Amount,Payee,Currency,Note`. Not run against a server. |

### Missing endpoints

- `period` grouping for the income statement. `/api/reports` takes only a date range.
- A single settings document. `GET /api/settings` does not exist.
- A direct "create staged row" call. `/api/import/email-webhook` needs a provider signature or the webhook secret and is not usable from a session.
- A row-level review queue endpoint. Staged rows are only reachable per batch.
- Approving a staged row into `transactions` in one call. `approve` writes to the bank ledger. Creating the transaction then takes `POST /api/bank-transactions/[bankId]/approve` or `POST /api/reconcile/materialize`, and the bank row ids come from `/api/import/bank-ledger?accountId=`.

## Mismatches with the Expo client (`mobile/src/api/client.ts`, `shared/types.ts`)

1. MFA login is broken on mobile. The MFA branch returns HTTP 200, so `authRequest` gives `ok: true`, and `useAuth` marks the user signed in before it checks `mfaRequired`. That check never runs. The native client must check `mfaRequired` first.
2. Mobile tries to read the token from `Set-Cookie` or `data.token`. The server never puts the session token in the body. Native: read `pf_session` from `HTTPCookieStorage`.
3. Cookie-only writes from a native HTTP stack hit the CSRF gate (403) because no `Origin` is sent. Send `Authorization: Bearer <jwt>`.
4. `POST /api/auth/logout` ignores Bearer. It needs the cookie to revoke the session.
5. `GET /api/transactions` `total` is a string in the unfiltered case. Mobile ignores `total` and only reads `data`.
6. The mobile `Transaction` type declares `isBusiness`, `splitPerson`, `splitRatio`, `importHash` and `fitId`. The list endpoint returns none of them. It does return `accountName`, `accountType`, `categoryType`, `entered*`, `linkId`, `kind`, `source`, `createdAt` and `updatedAt`, which the type omits.
7. `createTransaction` and `updateTransaction` are typed as `Transaction`, but the response is the raw DB row with encrypted payee, note and tags and no names.
8. `GET /api/budgets`: `spent` is always 0. `BudgetWithSpending` has no `spent` field and correctly uses `convertedSpent`. The web app moved to `/api/budgets/month` (enveloped).
9. `PortfolioOverview.topGainers` and `topLosers` are typed `EnrichedHolding[]`, but the server returns mover rows (`{ key, symbol, name, image, dayChangeDisplay, changePct }`). `etfXray` is missing from the type. `byType` also has a `metal` key.
10. `/api/dashboard` `netWorthOverTime[].cumulative` is a per-month delta, not a running total. Mobile does not use it.
11. A mobile comment says cross-currency transfers are refused and must use the web. The server accepts them. It converts with its FX rate, or uses `receivedAmount` if the client sends it. It returns 409 only when no rate exists. `TransferPayload` lacks `receivedAmount`.
12. `composeDashboard` falls back to currency `"CAD"`. The server default display currency is `"USD"`. `balances[].displayCurrency` is always present, so use it.
13. `DELETE /api/transactions` returns `{ success: true, ... }`. `request()` treats that as an envelope and `data` is undefined. That is harmless.
14. `GET /api/accounts/[id]` and `/api/transactions/[id]` (PUT/PATCH/DELETE) do not exist. Mobile correctly uses the collection routes with `id` in the body or query.
