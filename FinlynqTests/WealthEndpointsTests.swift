import Foundation
import Testing
@testable import Finlynq

/// Request shapes for the Wealth screens: portfolio, holdings, accounts, loans and the balance check.
/// Nested in `APIClientTests` so it shares that suite's serialized run (the URLProtocol stub is global).
extension APIClientTests {
    struct WealthEndpointsTests {
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

        private func expect(
            _ sent: StubProtocol.Sent?, _ method: String, _ url: String, sourceLocation: SourceLocation = #_sourceLocation
        ) {
            #expect(sent?.method == method, sourceLocation: sourceLocation)
            #expect(sent?.url == "https://example.test" + url, sourceLocation: sourceLocation)
        }

        private func json(_ sent: StubProtocol.Sent?) -> [String: Any] {
            (sent?.body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        }

        @Test func portfolioOverview() async throws {
            let api = client(["GET /api/portfolio/overview": "fixture:/api/portfolio/overview"])
            _ = try await api.portfolioOverview()
            expect(StubProtocol.sent.first, "GET", "/api/portfolio/overview")
        }

        @Test func holdingLots() async throws {
            let api = client(["GET /api/portfolio/holdings/3543/lots": "fixture:/api/portfolio/holdings/3543/lots"])
            _ = try await api.holdingLots(holdingId: 3543)
            expect(StubProtocol.sent.first, "GET", "/api/portfolio/holdings/3543/lots")
        }

        @Test func portfolioPerformance() async throws {
            let api = client([
                "GET /api/portfolio/performance": "fixture:/api/portfolio/performance",
                "GET /api/portfolio/performance/holdings": "fixture:/api/portfolio/performance/holdings"
            ])
            let performance = try await api.portfolioPerformance(period: "ytd")
            _ = try await api.holdingPerformance(period: "1y")
            expect(StubProtocol.sent.first, "GET", "/api/portfolio/performance?period=ytd")
            expect(StubProtocol.sent.last, "GET", "/api/portfolio/performance/holdings?period=1y")
            #expect(!performance.series.isEmpty)
            #expect(performance.twrr?.period != nil)
        }

        @Test func transactionsByHolding() async throws {
            let api = client(["GET /api/transactions": "fixture:/api/transactions"])
            _ = try await api.transactions(TransactionQuery(limit: 3, portfolioHoldingId: 3543))
            expect(StubProtocol.sent.first, "GET", "/api/transactions?limit=3&portfolioHoldingId=3543")
        }

        @Test func createAccount() async throws {
            let api = client()
            try await api.createAccount(AccountInput(name: "TFSA", type: "A", group: "Investments", currency: "CAD", isInvestment: true))
            expect(StubProtocol.sent.first, "POST", "/api/accounts")
            let body = json(StubProtocol.sent.first)
            #expect(body["name"] as? String == "TFSA")
            #expect(body["isInvestment"] as? Bool == true)
        }

        @Test func updateAccountAlwaysSendsTheAlias() async throws {
            let api = client()
            try await api.updateAccount(AccountUpdate(id: 4100, name: "Everyday", alias: nil, group: "Banks"))
            expect(StubProtocol.sent.first, "PUT", "/api/accounts")
            let body = json(StubProtocol.sent.first)
            #expect(body["id"] as? Int == 4100)
            #expect(body["name"] as? String == "Everyday")
            #expect(body["alias"] is NSNull)
            #expect(body["archived"] == nil)
        }

        @Test func updateLoanSendsOnlyTheEditedFields() async throws {
            let api = client()
            try await api.updateLoan(LoanUpdate(id: 267, annualRate: 5.5, extraPayment: 50))
            expect(StubProtocol.sent.last, "PUT", "/api/loans")
            let body = json(StubProtocol.sent.last)
            #expect(body["id"] as? Int == 267)
            #expect(body["annualRate"] as? Double == 5.5)
            #expect(body["extraPayment"] as? Double == 50)
            // The server merges the body over the saved loan, so untouched terms are left out.
            #expect(Set(body.keys) == ["id", "annualRate", "extraPayment"])
        }

        @Test func updateHoldingSendsOnlyTheEditedFields() async throws {
            let api = client()
            try await api.updateHolding(HoldingUpdate(id: 3543, symbol: "VTI", note: "Core"))
            expect(StubProtocol.sent.last, "PUT", "/api/portfolio")
            let body = json(StubProtocol.sent.last)
            #expect(Set(body.keys) == ["id", "symbol", "note"])
            #expect(body["note"] as? String == "Core")
        }

        @Test func createLoan() async throws {
            let api = client()
            let input = LoanInput(
                name: "Car", type: "loan", accountId: 4104, currency: "USD", principal: 15000, annualRate: 5.9,
                termMonths: nil, startDate: "2026-05-15", paymentAmount: 351.59, paymentFrequency: "monthly", extraPayment: 0
            )
            try await api.createLoan(input)
            expect(StubProtocol.sent.last, "POST", "/api/loans")
            let body = json(StubProtocol.sent.last)
            #expect(body["principal"] as? Double == 15000)
            #expect(body["paymentAmount"] as? Double == 351.59)
            #expect(body["startDate"] as? String == "2026-05-15")
            #expect(body["action"] == nil)
        }

        @Test func balanceSummary() async throws {
            let api = client(["GET /api/reconcile/balance-summary": "fixture:/api/reconcile/balance-summary"])
            let summary = try await api.balanceSummary(accountId: 4100)
            expect(StubProtocol.sent.first, "GET", "/api/reconcile/balance-summary?accountId=4100")
            // The overlay (a statement anchor for the review screens) replaces the demo's `no_anchor` answer.
            #expect(summary.status == "balanced")
            #expect(summary.systemSideLatest != nil)
        }

        @Test func updateAccountSendsTheInvestmentFlag() async throws {
            let api = client()
            try await api.updateAccount(AccountUpdate(id: 4102, name: "Brokerage", alias: nil, isInvestment: true))
            #expect(json(StubProtocol.sent.first)["isInvestment"] as? Bool == true)
        }

        @Test func recordInvestmentBuy() async throws {
            let api = client()
            try await api.recordInvestment(.buy(.init(accountId: 4102, holdingId: 3543, qty: 2, totalCost: 540, date: "2026-11-09")))
            expect(StubProtocol.sent.first, "POST", "/api/portfolio/operations/buy")
            let body = json(StubProtocol.sent.first)
            #expect(body["qty"] as? Double == 2)
            #expect(body["totalCost"] as? Double == 540)
        }

        @Test func recordInvestmentRoutes() {
            let transfer = InvestmentOp.Transfer(sourceAccountId: 1, destAccountId: 2, amount: 5, date: "2026-11-09")
            #expect(InvestmentOp.deposit(transfer).path == "/api/portfolio/operations/deposit")
            #expect(InvestmentOp.withdrawal(transfer).path == "/api/portfolio/operations/withdrawal")
            let income = InvestmentOp.Income(accountId: 1, amount: 5, date: "2026-11-09")
            #expect(InvestmentOp.income(income).path == "/api/portfolio/operations/income-expense")
        }
    }
}
