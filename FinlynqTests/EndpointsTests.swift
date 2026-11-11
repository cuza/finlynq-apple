// swiftlint:disable nesting
import Foundation
import Testing
@testable import Finlynq

/// One test per `APIClient` method: it sends the right method, path, query string and body.
/// Nested in `APIClientTests` so it shares that suite's serialized run (the URLProtocol stub is global).
extension APIClientTests {
    // swiftlint:disable:next type_body_length
    struct EndpointsTests {
        private typealias Sent = StubProtocol.Sent

        private func client(_ routes: [String: String] = [:]) -> APIClient {
            StubProtocol.statuses = []
            StubProtocol.requests = 0
            StubProtocol.sent = []
            StubProtocol.routes = routes.reduce(into: [:]) { result, route in
                // A value that names a fixture file loads it; anything else is the literal body.
                result[route.key] = route.value.hasPrefix("fixture:")
                    ? Fixtures.data(for: String(route.value.dropFirst(8))) : Data(route.value.utf8)
            }
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [StubProtocol.self]
            return APIClient(baseURL: URL(string: "https://example.test")!, session: URLSession(configuration: config))
        }

        private func expect(_ sent: Sent?, _ method: String, _ url: String, sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(sent?.method == method, sourceLocation: sourceLocation)
            #expect(sent?.url == "https://example.test" + url, sourceLocation: sourceLocation)
        }

        private func text(_ sent: Sent?) -> String {
            guard let body = sent?.body else { return "" }
            return String(bytes: body, encoding: .utf8) ?? ""
        }

        private func json(_ sent: Sent?) -> [String: Any] {
            (sent?.body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        }

        // MARK: Home

        @Test func dashboard() async throws {
            let api = client(["GET /api/dashboard": "fixture:/api/dashboard"])
            _ = try await api.dashboard()
            expect(StubProtocol.sent.first, "GET", "/api/dashboard")
        }

        @Test func netWorthHistory() async throws {
            let api = client(["GET /api/net-worth-history": "fixture:/api/net-worth-history"])
            _ = try await api.netWorthHistory(period: "1y", accountId: 4100)
            expect(StubProtocol.sent.first, "GET", "/api/net-worth-history?accountId=4100&period=1y")
        }

        @Test func accountsAndCategories() async throws {
            let api = client(["GET /api/accounts": "fixture:/api/accounts", "GET /api/categories": "fixture:/api/categories"])
            _ = try await api.accounts()
            _ = try await api.categories()
            expect(StubProtocol.sent.first, "GET", "/api/accounts")
            expect(StubProtocol.sent.last, "GET", "/api/categories")
        }

        @Test func spotlight() async throws {
            let api = client(["GET /api/spotlight": "fixture:/api/spotlight"])
            _ = try await api.spotlight()
            expect(StubProtocol.sent.first, "GET", "/api/spotlight")
        }

        // MARK: Transactions

        @Test func transactionsSortsQueryKeys() async throws {
            let api = client(["GET /api/transactions": "fixture:/api/transactions"])
            _ = try await api.transactions(.init(search: "lob", accountId: 4100, limit: 50, offset: 100))
            expect(StubProtocol.sent.first, "GET", "/api/transactions?accountId=4100&limit=50&offset=100&search=lob")
        }

        @Test func newestTransactionMonthAsksForOneRow() async throws {
            let api = client(["GET /api/transactions": "fixture:/api/transactions"])
            let month = try await api.newestTransactionMonth(categoryId: 8487)
            // The server sorts by date, newest first, by default.
            expect(StubProtocol.sent.first, "GET", "/api/transactions?categoryId=8487&limit=1")
            #expect(month.map(APIDate.string) == "2026-11-01")
        }

        @Test func transactionsWithoutFiltersHasNoQuery() async throws {
            let api = client(["GET /api/transactions": "fixture:/api/transactions"])
            _ = try await api.transactions()
            expect(StubProtocol.sent.first, "GET", "/api/transactions")
        }

        @Test func createTransaction() async throws {
            let api = client()
            try await api.createTransaction(.init(date: "2026-11-09", accountId: 4100, categoryId: 8486, amount: -12.5, payee: "Cafe"))
            expect(StubProtocol.sent.first, "POST", "/api/transactions")
            let body = json(StubProtocol.sent.first)
            #expect(body["accountId"] as? Int == 4100)
            #expect(body["amount"] as? Double == -12.5)
            #expect(body["note"] == nil)
        }

        @Test func updateTransactionPutsToCollectionWithId() async throws {
            let api = client()
            try await api.updateTransaction(.init(id: 77, note: "split with Sam"))
            expect(StubProtocol.sent.first, "PUT", "/api/transactions")
            #expect(json(StubProtocol.sent.first)["id"] as? Int == 77)
        }

        @Test func deleteTransaction() async throws {
            let api = client()
            try await api.deleteTransaction(id: 77)
            expect(StubProtocol.sent.first, "DELETE", "/api/transactions?id=77")
        }

        @Test func createTransfer() async throws {
            let api = client()
            try await api.createTransfer(.init(fromAccountId: 4100, toAccountId: 4101, enteredAmount: 250, date: "2026-11-09"))
            expect(StubProtocol.sent.first, "POST", "/api/transactions/transfer")
            #expect(json(StubProtocol.sent.first)["toAccountId"] as? Int == 4101)
        }

        @Test func transactionByIdUsesTheIdQuery() async throws {
            let api = client(["GET /api/transactions": "fixture:/api/transactions"])
            let row = try await api.transaction(id: 291947)
            expect(StubProtocol.sent.first, "GET", "/api/transactions?id=291947")
            #expect(row != nil)
            let none = client(["GET /api/transactions": #"{"data":[],"total":0}"#])
            #expect(try await none.transaction(id: 0) == nil)
        }

        @Test func fxRatesKeyedBySourceCurrency() async throws {
            let api = client(["GET /api/fx": #"{"displayCurrency":"INR","rates":{"USDINR":93.5,"CADINR":68}}"#])
            let rates = try await api.fxRates(target: "INR")
            expect(StubProtocol.sent.first, "GET", "/api/fx?target=INR")
            #expect(rates == ["INR": 1, "USD": 93.5, "CAD": 68])
        }

        @Test func splits() async throws {
            let api = client(["GET /api/transactions/splits": "[]"])
            _ = try await api.splits(transactionId: 9)
            expect(StubProtocol.sent.first, "GET", "/api/transactions/splits?transactionId=9")
        }

        @Test func saveAndDeleteSplits() async throws {
            let api = client(["POST /api/transactions/splits": "[]"])
            try await api.saveSplits(transactionId: 9, splits: [
                .init(categoryId: 8486, amount: -112.80, note: "Food"), .init(categoryId: nil, amount: -30)
            ])
            try await api.deleteSplits(transactionId: 9)
            expect(StubProtocol.sent.first, "POST", "/api/transactions/splits")
            let body = json(StubProtocol.sent.first)
            #expect(body["transactionId"] as? Int == 9)
            let parts = body["splits"] as? [[String: Any]]
            #expect(parts?.count == 2)
            #expect(parts?.first?["categoryId"] as? Int == 8486)
            #expect(parts?.first?["amount"] as? Double == -112.80)
            #expect(parts?.first?["note"] as? String == "Food")
            expect(StubProtocol.sent.last, "DELETE", "/api/transactions/splits?transactionId=9")
        }

        @Test func bulkUpdateSendsOneRequestPerField() async throws {
            let api = client()
            try await api.bulkUpdateTransactions(ids: [1, 2], changes: .init(categoryId: 8486, tags: "trip"))
            #expect(StubProtocol.sent.count == 2)
            expect(StubProtocol.sent.first, "POST", "/api/transactions/bulk")
            #expect(json(StubProtocol.sent.first)["action"] as? String == "update_category")
            #expect(json(StubProtocol.sent.first)["ids"] as? [Int] == [1, 2])
            #expect(json(StubProtocol.sent.last)["action"] as? String == "update_tags")
            #expect(json(StubProtocol.sent.last)["tags"] as? String == "trip")
        }

        // MARK: Plan

        @Test func budgetMonth() async throws {
            let api = client(["GET /api/budgets/month": "fixture:/api/budgets/month"])
            _ = try await api.budgetMonth("2026-11")
            expect(StubProtocol.sent.first, "GET", "/api/budgets/month?month=2026-11")
        }

        @Test func setBudget() async throws {
            let api = client()
            try await api.setBudget(categoryId: 8486, month: "2026-11", amount: 300)
            expect(StubProtocol.sent.first, "PUT", "/api/budgets/line")
            let body = json(StubProtocol.sent.first)
            #expect(body["key"] as? String == "c:8486")
            #expect(body["amount"] as? Double == 300)
        }

        @Test func clearingABudgetSendsNull() async throws {
            let api = client()
            try await api.setBudget(categoryId: 8486, month: "2026-11", amount: nil)
            #expect(json(StubProtocol.sent.first)["amount"] is NSNull)
        }

        @Test func subscriptionsAndCreate() async throws {
            let api = client(["GET /api/subscriptions": "fixture:/api/subscriptions"])
            _ = try await api.subscriptions()
            try await api.createSubscription(.init(name: "Netflix", amount: 15.99, frequency: "monthly"))
            expect(StubProtocol.sent.first, "GET", "/api/subscriptions")
            expect(StubProtocol.sent.last, "POST", "/api/subscriptions")
            #expect(json(StubProtocol.sent.last)["name"] as? String == "Netflix")
        }

        @Test func recurringSuggestions() async throws {
            let api = client(["GET /api/recurring": "fixture:/api/recurring"])
            let list = try await api.recurringSuggestions()
            expect(StubProtocol.sent.first, "GET", "/api/recurring")
            #expect(!list.isEmpty)
        }

        @Test func goalsAndLoans() async throws {
            let api = client(["GET /api/goals": "fixture:/api/goals", "GET /api/loans": "fixture:/api/loans"])
            _ = try await api.goals()
            _ = try await api.loans()
            expect(StubProtocol.sent.first, "GET", "/api/goals")
            expect(StubProtocol.sent.last, "GET", "/api/loans")
        }

        @Test func loanAmortizationPostsTheLoansTerms() async throws {
            let api = client([
                "GET /api/loans": "fixture:/api/loans",
                "POST /api/loans": "fixture:/api/loans/amortization"
            ])
            let result = try await api.loanAmortization(id: 267, extra: 100)
            expect(StubProtocol.sent.first, "GET", "/api/loans")
            expect(StubProtocol.sent.last, "POST", "/api/loans")
            let body = json(StubProtocol.sent.last)
            #expect(body["action"] as? String == "amortization")
            #expect(body["principal"] as? Double == 15000)
            #expect(body["extraPayment"] as? Double == 100)
            #expect(result.schedule.count == 48)
        }

        @Test func loanAmortizationFailsForAnUnknownLoan() async {
            let api = client(["GET /api/loans": "fixture:/api/loans"])
            await #expect(throws: APIError.self) { _ = try await api.loanAmortization(id: 1) }
        }

        @Test func dividendsUseTaxYear() async throws {
            let api = client(["GET /api/portfolio/dividends": "fixture:/api/portfolio/dividends"])
            _ = try await api.dividends(year: 2026)
            expect(StubProtocol.sent.first, "GET", "/api/portfolio/dividends?taxYear=2026")
        }

        @Test func realizedGainsUseTaxYear() async throws {
            let api = client(["GET /api/portfolio/realized-gains": "fixture:/api/portfolio/realized-gains"])
            let gains = try await api.realizedGains(year: 2026)
            expect(StubProtocol.sent.first, "GET", "/api/portfolio/realized-gains?taxYear=2026")
            #expect(gains.rows.count == gains.totals.rowCount)
        }

        @Test func incomeStatement() async throws {
            let api = client(["GET /api/reports": "fixture:/api/reports"])
            _ = try await api.incomeStatement(from: "2026-01-01", to: "2026-12-31")
            expect(StubProtocol.sent.first, "GET", "/api/reports?endDate=2026-12-31&startDate=2026-01-01&type=income-statement")
        }

        @Test func createGoalSendsTheZodShapeWithoutNulls() async throws {
            let api = client()
            try await api.createGoal(.init(name: "Trip", type: "savings", targetAmount: 5000, deadline: "2027-03-01", accountIds: [4101]))
            expect(StubProtocol.sent.first, "POST", "/api/goals")
            let body = json(StubProtocol.sent.first)
            // Nil fields are left out: the zod schema takes a missing key but rejects null.
            #expect(Set(body.keys) == ["name", "type", "targetAmount", "deadline", "accountIds"])
            #expect(body["accountIds"] as? [Int] == [4101])
            #expect(body["targetAmount"] as? Double == 5000)
        }

        @Test func updateGoalSendsOnlyTheChangedFields() async throws {
            let api = client()
            try await api.updateGoal(.init(id: 713, status: "completed"))
            expect(StubProtocol.sent.first, "PUT", "/api/goals")
            let body = json(StubProtocol.sent.first)
            #expect(Set(body.keys) == ["id", "status"])
            #expect(body["id"] as? Int == 713)
            try await api.updateGoal(.init(id: 713, accountIds: [4100, 4101]))
            #expect(json(StubProtocol.sent.last)["accountIds"] as? [Int] == [4100, 4101])
        }

        @Test func deleteGoal() async throws {
            let api = client()
            try await api.deleteGoal(id: 713)
            expect(StubProtocol.sent.first, "DELETE", "/api/goals?id=713")
        }

        @Test func fillBudgetsPreviewsFromTheAverage() async throws {
            let reply = #"{"success":true,"data":{"rows":[{"key":"c:8487","name":"Dining","month":"2026-11","amount":402,"previous":416}],"#
                + #""applied":false,"total":402,"currency":"USD"}}"#
            let api = client(["POST /api/budgets/fill": reply])
            let result = try await api.fillBudgets(.init(months: ["2026-11"], source: .init(months: 3), overwrite: true, preview: true))
            expect(StubProtocol.sent.first, "POST", "/api/budgets/fill")
            let body = json(StubProtocol.sent.first)
            #expect(body["months"] as? [String] == ["2026-11"])
            #expect((body["source"] as? [String: Any])?["kind"] as? String == "average")
            #expect((body["source"] as? [String: Any])?["months"] as? Int == 3)
            #expect(body["preview"] as? Bool == true)
            #expect(body["overwrite"] as? Bool == true)
            #expect(result.rows.first?.name == "Dining")
            #expect(result.applied == false)
        }

        @Test func trendsAreMonthly() async throws {
            let api = client(["GET /api/reports/trends": "fixture:/api/reports/trends"])
            let trends = try await api.trends(from: "2026-01-01", to: "2026-11-30")
            expect(StubProtocol.sent.first, "GET", "/api/reports/trends?endDate=2026-11-30&period=monthly&startDate=2026-01-01")
            #expect(!trends.expenses.isEmpty)
        }

        // MARK: Review and import

        @Test func stagedImportsTagsRowsWithTheirBatch() async throws {
            let list = try #require(Fixtures.data(for: "/api/import/staged"))
            let batch = try #require((try JSONSerialization.jsonObject(with: list) as? [[String: Any]])?.first?["id"] as? String)
            let api = client([
                "GET /api/import/staged": "fixture:/api/import/staged",
                "GET /api/import/staged/\(batch)": "fixture:/api/import/staged/\(batch)"
            ])
            let rows = try await api.stagedImports()
            expect(StubProtocol.sent.first, "GET", "/api/import/staged")
            expect(StubProtocol.sent.last, "GET", "/api/import/staged/\(batch)")
            #expect(!rows.isEmpty)
            #expect(rows.allSatisfy { $0.importId == batch })
        }

        @Test func approveStaged() async throws {
            let api = client()
            try await api.approveStaged(importId: "b1", ids: ["r1", "r2"])
            expect(StubProtocol.sent.first, "POST", "/api/import/staged/b1/approve")
            #expect(json(StubProtocol.sent.first)["rowIds"] as? [String] == ["r1", "r2"])
        }

        @Test func linkStaged() async throws {
            let api = client()
            try await api.linkStaged(importId: "b1", rowId: "r1", transactionId: 55)
            expect(StubProtocol.sent.first, "PATCH", "/api/import/staged/b1/rows/r1")
            let body = json(StubProtocol.sent.first)
            #expect(body["reconcileState"] as? String == "linked")
            #expect(body["linkedTransactionId"] as? Int == 55)
        }

        @Test func importPreviewUploadsAFile() async throws {
            let api = client(["POST /api/import/preview": #"{"type":"csv","valid":[],"duplicates":[]}"#])
            let file = UploadFile(filename: "bank.csv", data: Data("Date,Amount\n".utf8))
            let preview = try await api.importPreview(file: file, accountId: 4100)
            expect(StubProtocol.sent.first, "POST", "/api/import/preview")
            #expect(StubProtocol.sent.first?.contentType?.hasPrefix("multipart/form-data; boundary=") == true)
            let text = text(StubProtocol.sent.first)
            #expect(text.contains("filename=\"bank.csv\""))
            #expect(text.contains("name=\"accountId\"\r\n\r\n4100"))
            #expect(preview.type == "csv")
        }

        @Test func importExecute() async throws {
            let api = client(["POST /api/import/execute": #"{"total":1,"imported":1,"skippedDuplicates":0}"#])
            let row = ImportRow(date: "2026-11-09", account: "Chequing", amount: -4, payee: "Cafe")
            let result = try await api.importExecute([row], forceImportIndices: [0])
            expect(StubProtocol.sent.first, "POST", "/api/import/execute")
            #expect((json(StubProtocol.sent.first)["rows"] as? [[String: Any]])?.count == 1)
            #expect(json(StubProtocol.sent.first)["forceImportIndices"] as? [Int] == [0])
            #expect(result.imported == 1)
        }

        @Test func stageTransactionUploadsAOneRowCSV() async throws {
            let api = client(["POST /api/import/staging/upload": #"{"stagedImportId":"b9"}"#])
            let input = StageInput(date: "2026-11-09", accountId: 4100, accountName: "Chequing", amount: -4.5, payee: "Cafe \"One\"")
            let result = try await api.stageTransaction(input)
            expect(StubProtocol.sent.first, "POST", "/api/import/staging/upload")
            let text = text(StubProtocol.sent.first)
            #expect(text.contains("Date,Account,Amount,Payee,Currency,Note\n\"2026-11-09\",\"Chequing\",\"-4.5\",\"Cafe \"\"One\"\"\""))
            #expect(text.contains("name=\"accountId\"\r\n\r\n4100"))
            #expect(result.stagedImportId == "b9")
        }

        @Test func rulesAndCreate() async throws {
            let api = client(["GET /api/rules": "fixture:/api/rules"])
            let list = try await api.rules()
            #expect(list.first?.conditions.all.first?.field == "payee")
            let input = RuleInput(
                name: "Cafe", conditions: .init(all: [.init(field: "payee", op: "contains", value: .text("Cafe"))]),
                actions: [.init(kind: "set_category", categoryId: 8486)]
            )
            try await api.createRule(input)
            expect(StubProtocol.sent.first, "GET", "/api/rules")
            expect(StubProtocol.sent.last, "POST", "/api/rules")
            #expect((json(StubProtocol.sent.last)["actions"] as? [[String: Any]])?.first?["categoryId"] as? Int == 8486)
        }

        // MARK: Settings

        @Test func settingsReadsProfileAndCurrency() async throws {
            let api = client([
                "GET /api/user/me": "fixture:/api/user/me",
                "GET /api/settings/display-currency": "fixture:/api/settings/display-currency"
            ])
            let settings = try await api.settings()
            #expect(Set(StubProtocol.sent.map(\.path)) == ["/api/user/me", "/api/settings/display-currency"])
            #expect(settings.displayCurrency == "INR")
            #expect(settings.username == "demo")
        }

        @Test func setDisplayCurrency() async throws {
            let api = client()
            try await api.setDisplayCurrency("EUR")
            expect(StubProtocol.sent.first, "PUT", "/api/settings/display-currency")
            #expect(json(StubProtocol.sent.first)["displayCurrency"] as? String == "EUR")
        }

        @Test func importEmailAddress() async throws {
            let api = client(["GET /api/import/email-config": #"{"email":"import-abc@finlynq.com"}"#])
            let address = try await api.importEmailAddress()
            expect(StubProtocol.sent.first, "GET", "/api/import/email-config")
            #expect(address == "import-abc@finlynq.com")
        }

        @Test func deleteAccountSendsThePasswordAndConfirmation() async throws {
            let api = client()
            try await api.deleteAccount(password: "pw")
            expect(StubProtocol.sent.first, "POST", "/api/auth/delete-account")
            let body = json(StubProtocol.sent.first)
            #expect(body["password"] as? String == "pw")
            #expect(body["confirmation"] as? String == "DELETE")
            #expect(body["mfaCode"] == nil)
        }
    }
}
// swiftlint:enable nesting
