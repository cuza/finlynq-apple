import Foundation
import OSLog

private let reviewLog = Logger(subsystem: "dev.cuza.finlynq", category: "review")

// One method per server call the screens make. Shapes are in docs/api-reference.md.

private struct Items<T: Decodable>: Decodable { let items: [T] }
private struct RecurringList: Decodable { let recurring: [RecurringSuggestion] }
private struct EmailConfig: Decodable { let email: String? }
private struct SuggestReply: Decodable { struct Category: Decodable { let id: Int }; let suggestion: Category? }
/// `POST /api/bank-transactions/[id]/approve` reply: `{ success, data: { transactionId } }`.
private struct Booked: Decodable {
    let data: Transaction?
    struct Transaction: Decodable { let transactionId: Int? }
}

/// Encodes a nil amount as `null`, which is how the server clears a budget cell.
private struct BudgetLineBody: Encodable {
    let key: String
    let month: String
    let amount: Double?

    private enum CodingKeys: String, CodingKey { case key, month, amount }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(month, forKey: .month)
        try container.encode(amount, forKey: .amount)
    }
}

extension APIClient {
    // MARK: Home

    func dashboard() async throws -> Dashboard { try await get("/api/dashboard") }

    func netWorthHistory(period: String = "6m", accountId: Int? = nil) async throws -> NetWorthHistory {
        try await get("/api/net-worth-history", query: ["period": period, "accountId": accountId.map(String.init)])
    }

    func accounts() async throws -> [Account] { try await get("/api/accounts") }

    func categories() async throws -> [Category] { try await get("/api/categories") }

    func spotlight() async throws -> [SpotlightItem] {
        let list: Items<SpotlightItem> = try await get("/api/spotlight")
        return list.items
    }

    // MARK: Transactions

    func transactions(_ query: TransactionQuery = .init()) async throws -> TransactionPage {
        try await get("/api/transactions", query: query.items)
    }

    /// One row by id, or nil when the server has none.
    func transaction(id: Int) async throws -> Transaction? {
        let page: TransactionPage = try await get("/api/transactions", query: ["id": String(id)])
        return page.data.first { $0.id == id }
    }

    /// Rates from every currency to `target`, keyed by source code. The target maps to 1.
    func fxRates(target: String) async throws -> [String: Double] {
        let reply: FxRates = try await get("/api/fx", query: ["target": target])
        return reply.byCurrency
    }

    @discardableResult
    func createTransaction(_ input: TransactionInput) async throws -> TransactionWrite {
        try decode(await send("POST", "/api/transactions", body: input))
    }

    /// `POST /api/transactions/suggest`: the category the user's past transactions give this payee, or nil.
    func suggestCategory(payee: String) async throws -> Int? {
        let reply: SuggestReply = try decode(await send("POST", "/api/transactions/suggest", body: ["payee": payee]))
        return reply.suggestion?.id
    }

    /// `input.id` is required: the server updates through the collection route.
    @discardableResult
    func updateTransaction(_ input: TransactionInput) async throws -> TransactionWrite {
        precondition(input.id != nil, "updateTransaction needs an id")
        return try decode(await send("PUT", "/api/transactions", body: input))
    }

    func deleteTransaction(id: Int) async throws {
        try await send("DELETE", "/api/transactions", query: ["id": String(id)])
    }

    func createTransfer(_ input: TransferInput) async throws {
        try await send("POST", "/api/transactions/transfer", body: input)
    }

    func splits(transactionId: Int) async throws -> [Split] {
        try await get("/api/transactions/splits", query: ["transactionId": String(transactionId)])
    }

    /// Replaces all splits of a transaction. The parts must add up to the transaction's amount.
    func saveSplits(transactionId: Int, splits: [SplitInput]) async throws {
        struct Body: Encodable {
            let transactionId: Int
            let splits: [SplitInput]
        }
        try await send("POST", "/api/transactions/splits", body: Body(transactionId: transactionId, splits: splits))
    }

    func deleteSplits(transactionId: Int) async throws {
        try await send("DELETE", "/api/transactions/splits", query: ["transactionId": String(transactionId)])
    }

    /// The server changes one field per call, so this sends one request for each field that is set.
    func bulkUpdateTransactions(ids: [Int], changes: TransactionChanges) async throws {
        for body in changes.bodies(ids: ids) {
            try await send("POST", "/api/transactions/bulk", query: [:], body: JSONSerialization.data(withJSONObject: body))
        }
    }

    // MARK: Plan

    func budgetMonth(_ month: String) async throws -> BudgetMonth {
        try await getEnveloped("/api/budgets/month", query: ["month": month])
    }

    /// `amount: nil` clears the budget for that category and month. Amounts are in the display currency.
    func setBudget(categoryId: Int, month: String, amount: Double?) async throws {
        try await send("PUT", "/api/budgets/line", body: BudgetLineBody(key: "c:\(categoryId)", month: month, amount: amount))
    }

    func subscriptions() async throws -> [Subscription] { try await get("/api/subscriptions") }

    func createSubscription(_ input: SubscriptionInput) async throws {
        try await send("POST", "/api/subscriptions", body: input)
    }

    func recurringSuggestions() async throws -> [RecurringSuggestion] {
        let list: RecurringList = try await get("/api/recurring")
        return list.recurring
    }

    func goals() async throws -> [Goal] { try await get("/api/goals") }

    func createGoal(_ input: GoalInput) async throws {
        try await send("POST", "/api/goals", body: input)
    }

    func updateGoal(_ update: GoalUpdate) async throws {
        try await send("PUT", "/api/goals", body: update)
    }

    func deleteGoal(id: Int) async throws {
        try await send("DELETE", "/api/goals", query: ["id": String(id)])
    }

    /// Runs a budget fill on the server. With `preview` it only returns the rows it would write.
    func fillBudgets(_ request: BudgetFillRequest) async throws -> BudgetFillResult {
        struct Envelope: Decodable { let data: BudgetFillResult }
        let reply: Envelope = try decode(await send("POST", "/api/budgets/fill", body: request))
        return reply.data
    }

    func loans() async throws -> [Loan] { try await get("/api/loans") }

    /// The server computes a schedule from the loan's terms in the request, so this looks the loan up first.
    /// `extra` replaces the loan's saved extra payment per period.
    func loanAmortization(id: Int, extra: Double? = nil) async throws -> Amortization {
        if Fixtures.isEnabled, let data = Fixtures.data(for: "/api/loans/amortization") { return try decode(data) }
        guard let loan = try await loans().first(where: { $0.id == id }) else {
            throw APIError.server(status: 404, message: "Loan not found")
        }
        struct Body: Encodable {
            let action = "amortization"
            let loanId: Int
            let principal: Double
            let annualRate: Double
            let termMonths: Int?
            let startDate: String
            let paymentAmount: Double?
            let paymentFrequency: String?
            let extraPayment: Double
            let residualValue: Double?
        }
        let body = Body(
            loanId: loan.id, principal: loan.principal, annualRate: loan.annualRate, termMonths: loan.termMonths,
            startDate: loan.startDate, paymentAmount: loan.paymentAmount, paymentFrequency: loan.paymentFrequency,
            extraPayment: extra ?? loan.extraPayment ?? 0, residualValue: loan.residualValue
        )
        return try decode(await send("POST", "/api/loans", body: body))
    }

    // MARK: Wealth

    func portfolioOverview() async throws -> PortfolioOverview { try await get("/api/portfolio/overview") }

    /// Market value and cost basis per day. Period: 1m, 3m, 6m, ytd, 1y or all.
    func portfolioPerformance(period: String) async throws -> PortfolioPerformance {
        try await getEnveloped("/api/portfolio/performance", query: ["period": period])
    }

    /// Each holding's value per day, for a holding's chart.
    func holdingPerformance(period: String) async throws -> HoldingPerformance {
        try await getEnveloped("/api/portfolio/performance/holdings", query: ["period": period])
    }

    func createAccount(_ input: AccountInput) async throws {
        try await send("POST", "/api/accounts", body: input)
    }

    func updateAccount(_ update: AccountUpdate) async throws {
        try await send("PUT", "/api/accounts", body: update)
    }

    /// Changes a loan. The server merges the body over the saved loan, so only the edited fields are sent.
    func updateLoan(_ update: LoanUpdate) async throws {
        try await send("PUT", "/api/loans", body: update)
    }

    func createLoan(_ input: LoanInput) async throws {
        try await send("POST", "/api/loans", body: input)
    }

    /// The latest bank statement balance against Finlynq's balance for one account (enveloped).
    func balanceSummary(accountId: Int) async throws -> BalanceSummary {
        try await getEnveloped("/api/reconcile/balance-summary", query: ["accountId": String(accountId)])
    }

    func portfolioHoldings() async throws -> [PortfolioHolding] { try await get("/api/portfolio") }

    /// Changes one holding row. Only the fields being changed are sent.
    func updateHolding(_ update: HoldingUpdate) async throws {
        try await send("PUT", "/api/portfolio", body: update)
    }

    func holdingLots(holdingId: Int) async throws -> HoldingLots {
        try await get("/api/portfolio/holdings/\(holdingId)/lots")
    }

    func recordInvestment(_ operation: InvestmentOp) async throws {
        try await send("POST", operation.path, query: [:], body: operation.encoded())
    }

    func dividends(year: Int) async throws -> DividendIncome {
        try await getEnveloped("/api/portfolio/dividends", query: ["taxYear": String(year)])
    }

    func realizedGains(year: Int) async throws -> RealizedGains {
        try await getEnveloped("/api/portfolio/realized-gains", query: ["taxYear": String(year)])
    }

    /// Dates are `YYYY-MM-DD`. The server has no period grouping, so the totals cover the whole range.
    func incomeStatement(from start: String, to end: String) async throws -> IncomeStatement {
        try await get("/api/reports", query: ["type": "income-statement", "startDate": start, "endDate": end])
    }

    /// Income and expenses by category for each month from `start` to `end` (`YYYY-MM-DD`).
    func trends(from start: String, to end: String) async throws -> Trends {
        try await get("/api/reports/trends", query: ["startDate": start, "endDate": end, "period": "monthly"])
    }

    // MARK: Review and import

    /// Every pending row across all batches, each tagged with its batch id. One request for the list, one per batch.
    func stagedImports() async throws -> [StagedRow] {
        var rows: [StagedRow] = []
        for batch in try await stagedBatches() {
            let detail = try await stagedDetail(id: batch.id)
            for var row in detail.rows {
                row.importId = batch.id
                row.accountId = batch.boundAccountId
                row.importedAt = batch.receivedAt
                row.importFile = batch.originalFilename
                row.match = detail.suggestedMatches.first { $0.stagedRowId == row.id }.map { ReviewMatch(transactionId: $0.transactionId) }
                rows.append(row)
            }
        }
        return rows
    }

    /// Everything waiting for review: staged rows not yet sent anywhere, plus bank-ledger rows that no ledger
    /// transaction is linked to (an approve-each account's upload lands there directly). Bank rows carry the
    /// rule's category and a possible copy of an existing transaction. One snapshot request per account that
    /// has bank rows waiting; an account whose snapshot fails is logged and left out, so one bad account doesn't
    /// zero every badge. Snapshots cover the account's whole history (no `dateMin`): the summary's pending count
    /// does too, and a shorter window would hide old unlinked rows that the badge still counts.
    func reviewQueue() async throws -> [StagedRow] {
        var rows = try await stagedImports().filter(\.isPending)
        let summary: ReconcileSummary = try await get("/api/reconcile/summary")
        for account in summary.rows where account.pendingCount > 0 {
            let snapshot: ReconcileSnapshot
            do {
                snapshot = try await reconcileSnapshot(accountId: account.accountId)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                reviewLog.error("bank rows for account \(account.accountId) failed: \(error.localizedDescription, privacy: .public)")
                continue
            }
            rows += snapshot.unlinked.map { bank in
                let match = bank.duplicateOfTransactionId.map { id in
                    let ledger = snapshot.transactions[String(id)]
                    return ReviewMatch(transactionId: id, payee: ledger?.payee, amount: ledger?.amount, date: ledger?.date)
                }
                return StagedRow(
                    id: bank.id, date: bank.date, amount: bank.amount, currency: bank.currency, payee: bank.payee,
                    accountId: bank.accountId, importedAt: bank.firstSeenAt, bankId: bank.id,
                    categoryId: bank.suggestedCategoryId, match: match
                )
            }
        }
        return rows
    }

    /// One account's bank rows, ledger transactions and pairings. `dateMin` is `YYYY-MM-DD`.
    func reconcileSnapshot(accountId: Int, dateMin: String? = nil) async throws -> ReconcileSnapshot {
        try await getEnveloped("/api/reconcile/suggestions", query: ["accountId": String(accountId), "dateMin": dateMin])
    }

    /// Books a bank-ledger row as a ledger transaction in `categoryId` and returns the transaction id. This is the web
    /// To approve call. A staged row must reach the bank ledger first (its whole import, `approveStaged(importId:)`),
    /// so it is refused.
    @discardableResult
    func approveReviewRow(_ row: StagedRow, categoryId: Int) async throws -> Int? {
        guard let bankId = row.bankId else { throw APIError.server(status: 409, message: Self.notInBankLedger) }
        struct Body: Encodable { let categoryId: Int }
        let reply: Booked = try decode(await send("POST", "/api/bank-transactions/\(bankId)/approve", body: Body(categoryId: categoryId)))
        return reply.data?.transactionId
    }

    /// Marks a bank-ledger row as the same payment as `row.match`, without booking a new transaction.
    func linkReviewRow(_ row: StagedRow) async throws {
        guard let match = row.match else { return }
        guard let bankId = row.bankId else { throw APIError.server(status: 409, message: Self.notInBankLedger) }
        try await linkBankRows(bankIds: [bankId], transactionIds: [match.transactionId])
    }

    static let notInBankLedger = "This row isn't in your bank ledger yet. Send its import first."

    /// Deletes a bank-ledger row for good (`DELETE /api/bank-transactions/[id]`).
    func removeReviewRow(_ row: StagedRow) async throws {
        guard let bankId = row.bankId else { throw APIError.server(status: 409, message: Self.notInBankLedger) }
        try await send("DELETE", "/api/bank-transactions/\(bankId)")
    }

    /// Links bank rows to ledger transactions: every pair of the two lists. One pair uses the single-link route.
    func linkBankRows(bankIds: [String], transactionIds: [Int]) async throws {
        if bankIds.count == 1, transactionIds.count == 1 {
            struct Body: Encodable { let transactionId: Int; let bankTransactionId: String }
            try await send("POST", "/api/reconcile/links", body: Body(transactionId: transactionIds[0], bankTransactionId: bankIds[0]))
        } else {
            struct Body: Encodable { let transactionIds: [Int]; let bankTransactionIds: [String] }
            try await send("POST", "/api/reconcile/links/bulk", body: Body(transactionIds: transactionIds, bankTransactionIds: bankIds))
        }
    }

    func stagedBatches() async throws -> [StagedImport] { try await get("/api/import/staged") }

    func stagedDetail(id: String) async throws -> StagedDetail { try await get("/api/import/staged/\(id)") }

    /// Sends the rows to the bank ledger. Omit `ids` to send every row that is not a duplicate. Send a whole import in
    /// one call: the server numbers identical rows only within one call, so a row sent alone can merge into an
    /// identical row already in the ledger.
    @discardableResult
    func approveStaged(importId: String, ids: [String]? = nil) async throws -> ApproveResult {
        struct Body: Encodable { let rowIds: [String]? }
        return try decode(await send("POST", "/api/import/staged/\(importId)/approve", body: Body(rowIds: ids)))
    }

    /// Marks a staged row as the same payment as an existing transaction.
    func linkStaged(importId: String, rowId: String, transactionId: Int) async throws {
        let patch = StagedRowPatch(reconcileState: "linked", linkedTransactionId: transactionId)
        try await send("PATCH", "/api/import/staged/\(importId)/rows/\(rowId)", body: patch)
    }

    /// Parses a statement without saving it. The server ignores `accountId` here: CSV rows name their account
    /// and OFX rows are bound to one at execute time.
    func importPreview(file: UploadFile, accountId: Int? = nil) async throws -> ImportPreview {
        // A POST answers `{}` in fixture mode; the hand-made preview lets the import sheet show a parsed file.
        if Fixtures.isEnabled, let data = Fixtures.data(for: "/api/import/preview") { return try decode(data) }
        let multipart = Multipart(fields: ["accountId": accountId.map(String.init)], file: file)
        return try decode(await send("POST", "/api/import/preview", body: multipart.body, contentType: multipart.contentType))
    }

    /// Parses a CSV with the given columns; rows without an account get `defaultAccount`. Saves nothing.
    func importMapCSV(file: UploadFile, mapping: ColumnMapping, defaultAccount: String?) async throws -> ImportPreview {
        let json = String(bytes: try JSONEncoder().encode(mapping), encoding: .utf8)
        let multipart = Multipart(fields: ["columnMapping": json, "defaultAccount": defaultAccount], file: file)
        return try decode(await send("POST", "/api/import/csv-map", body: multipart.body, contentType: multipart.contentType))
    }

    @discardableResult
    func importExecute(_ rows: [ImportRow], forceImportIndices: [Int] = []) async throws -> ImportResult {
        struct Body: Encodable {
            let rows: [ImportRow]
            let forceImportIndices: [Int]
        }
        return try decode(await send("POST", "/api/import/execute", body: Body(rows: rows, forceImportIndices: forceImportIndices)))
    }

    /// Uploads a statement into the review queue. This is the route the web Import page uses.
    /// `statementBalance` is the ending balance the user typed; the server records it as the bank's balance.
    func uploadStatement(file: UploadFile, accountId: Int?, statementBalance: Double? = nil) async throws -> StagingUploadResult {
        let fields = [
            "accountId": accountId.map(String.init), "confirmedMapping": "1", "confirmedImport": "1",
            "statementBalance": statementBalance.map { String($0) }
        ]
        let multipart = Multipart(fields: fields, file: file)
        return try decode(await send("POST", "/api/import/staging/upload", body: multipart.body, contentType: multipart.contentType))
    }

    /// Puts one payment in the review queue by uploading a one-row CSV with the canonical headers.
    func stageTransaction(_ input: StageInput) async throws -> StagingUploadResult {
        func cell(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let csv = "Date,Account,Amount,Payee,Currency,Note\n"
            + [input.date, input.accountName, String(input.amount), input.payee, input.currency ?? "", input.note ?? ""]
            .map(cell).joined(separator: ",") + "\n"
        let file = UploadFile(filename: "payment.csv", data: Data(csv.utf8))
        return try await uploadStatement(file: file, accountId: input.accountId)
    }

    func rules() async throws -> [Rule] { try await get("/api/rules") }

    func createRule(_ input: RuleInput) async throws {
        try await send("POST", "/api/rules", body: input)
    }

    // MARK: Settings

    func settings() async throws -> AppSettings {
        async let profile: UserMe = get("/api/user/me")
        async let currency: DisplayCurrencySetting = get("/api/settings/display-currency")
        let (user, display) = try await (profile, currency)
        return AppSettings(
            userId: user.userId, username: user.username, email: user.email,
            displayName: user.displayName, displayCurrency: display.displayCurrency
        )
    }

    func setDisplayCurrency(_ code: String) async throws {
        struct Body: Encodable { let displayCurrency: String }
        try await send("PUT", "/api/settings/display-currency", body: Body(displayCurrency: code))
    }

    /// The address that turns forwarded email into staged rows, or nil if none was generated yet.
    func importEmailAddress() async throws -> String? {
        let config: EmailConfig = try await get("/api/import/email-config")
        return config.email
    }

    /// Permanently deletes the account and all its data. Pass `mfaCode` when the user has MFA on.
    func deleteAccount(password: String, mfaCode: String? = nil) async throws {
        struct Body: Encodable {
            let password: String
            let confirmation = "DELETE"
            let mfaCode: String?
        }
        // No sign-in retry: a 401 here means a wrong password or code, and the server allows 3 tries an hour.
        let body = try JSONEncoder().encode(Body(password: password, mfaCode: mfaCode))
        try await send("POST", "/api/auth/delete-account", body: body, retry: false)
    }
}

/// A multipart/form-data body with one file part named `file`. Nil fields are left out.
private struct Multipart {
    let boundary = "finlynq-\(UUID().uuidString)"
    let body: Data
    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    init(fields: [String: String?], file: UploadFile) {
        var data = Data()
        func add(_ text: String) { data.append(Data(text.utf8)) }
        let boundary = boundary
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            guard let value else { continue }
            add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        let filename = file.filename.replacingOccurrences(of: "\"", with: "_")
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        add("Content-Type: application/octet-stream\r\n\r\n")
        data.append(file.data)
        add("\r\n--\(boundary)--\r\n")
        body = data
    }
}
