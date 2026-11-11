import Foundation
import Testing
@testable import Finlynq

private nonisolated struct Envelope<T: Decodable>: Decodable { let data: T }
private nonisolated struct Items<T: Decodable>: Decodable { let items: [T] }
private nonisolated struct Recurring: Decodable { let recurring: [RecurringSuggestion] }
private nonisolated struct EmailConfig: Decodable { let email: String? }

struct FixtureTests {

    private static let expected: Set<String> = [
        "session.json", "dashboard.json", "accounts.json", "categories.json", "transactions.json",
        "budgets-month.json", "portfolio-overview.json", "net-worth-history.json",
        "spotlight.json", "subscriptions.json", "recurring.json", "goals.json", "loans.json", "loans-amortization.json",
        "rules.json", "user-me.json", "settings-display-currency.json", "import-email-config.json",
        "transactions-splits.json", "portfolio-dividends.json", "portfolio-realized-gains.json", "reports.json",
        "import-staged.json", "fx.json", "portfolio-performance.json", "portfolio-performance-holdings.json",
        "reconcile-summary.json", "reconcile-suggestions.json", "reconcile-balance-summary.json", "import-preview.json",
        "reports-trends.json", "settings-active-currencies.json", "settings-bank-feeds-simplefin-status.json",
        "settings-fx-rate-view.json"
    ]

    /// Fixtures whose names carry an id the demo picked: a staged batch and a holding.
    private static let stagedDetail = /import-staged-[0-9a-f-]{36}\.json/
    private static let holdingLots = /portfolio-holdings-\d+-lots\.json/

    // swiftlint:disable cyclomatic_complexity
    /// Decodes a fixture with the model the app uses for that route.
    private static func decode(_ file: String, _ data: Data) throws {
        let decoder = JSONDecoder()
        switch file {
        case "session.json": _ = try decoder.decode(SessionInfo.self, from: data)
        case "dashboard.json": _ = try decoder.decode(Dashboard.self, from: data)
        case "accounts.json": _ = try decoder.decode([Account].self, from: data)
        case "categories.json": _ = try decoder.decode([Finlynq.Category].self, from: data)
        case "transactions.json": _ = try decoder.decode(TransactionPage.self, from: data)
        case "budgets-month.json": _ = try decoder.decode(Envelope<BudgetMonth>.self, from: data)
        case "portfolio-overview.json": _ = try decoder.decode(PortfolioOverview.self, from: data)
        case "net-worth-history.json": _ = try decoder.decode(NetWorthHistory.self, from: data)
        case "spotlight.json": _ = try decoder.decode(Items<SpotlightItem>.self, from: data)
        case "subscriptions.json": _ = try decoder.decode([Subscription].self, from: data)
        case "recurring.json": _ = try decoder.decode(Recurring.self, from: data)
        case "goals.json": _ = try decoder.decode([Goal].self, from: data)
        case "loans.json": _ = try decoder.decode([Loan].self, from: data)
        case "loans-amortization.json": _ = try decoder.decode(Amortization.self, from: data)
        case "fx.json": _ = try decoder.decode(FxRates.self, from: data)
        case "rules.json": _ = try decoder.decode([Rule].self, from: data)
        case "user-me.json": _ = try decoder.decode(UserMe.self, from: data)
        case "settings-display-currency.json": _ = try decoder.decode(DisplayCurrencySetting.self, from: data)
        case "import-email-config.json": _ = try decoder.decode(EmailConfig.self, from: data)
        case "transactions-splits.json": _ = try decoder.decode([Split].self, from: data)
        case "portfolio-dividends.json": _ = try decoder.decode(Envelope<DividendIncome>.self, from: data)
        case "portfolio-realized-gains.json": _ = try decoder.decode(Envelope<RealizedGains>.self, from: data)
        case "reports.json": _ = try decoder.decode(IncomeStatement.self, from: data)
        case "reports-trends.json": _ = try decoder.decode(Trends.self, from: data)
        case "import-staged.json": _ = try decoder.decode([StagedImport].self, from: data)
        case "import-preview.json": _ = try decoder.decode(ImportPreview.self, from: data)
        case "reconcile-summary.json": _ = try decoder.decode(ReconcileSummary.self, from: data)
        case "reconcile-suggestions.json": _ = try decoder.decode(Envelope<ReconcileSnapshot>.self, from: data)
        case "portfolio-performance.json": _ = try decoder.decode(Envelope<PortfolioPerformance>.self, from: data)
        case "portfolio-performance-holdings.json": _ = try decoder.decode(Envelope<HoldingPerformance>.self, from: data)
        case "reconcile-balance-summary.json": _ = try decoder.decode(Envelope<BalanceSummary>.self, from: data)
        case "settings-active-currencies.json": _ = try decoder.decode(ActiveCurrencies.self, from: data)
        case "settings-bank-feeds-simplefin-status.json": _ = try decoder.decode(BankFeedStatus.self, from: data)
        case "settings-fx-rate-view.json": _ = try decoder.decode(Envelope<FxRateView>.self, from: data)
        case _ where file.wholeMatch(of: stagedDetail) != nil: _ = try decoder.decode(StagedDetail.self, from: data)
        case _ where file.wholeMatch(of: holdingLots) != nil: _ = try decoder.decode(HoldingLots.self, from: data)
        default: Issue.record("no model for \(file)")
        }
    }

    // swiftlint:enable cyclomatic_complexity

    @Test func decodesEveryFixture() throws {
        let dir = try #require(Bundle.main.url(forResource: "Fixtures", withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") }
        let named = files.filter { $0.wholeMatch(of: Self.stagedDetail) != nil || $0.wholeMatch(of: Self.holdingLots) != nil }
        #expect(named.count == 2, "one staged batch and one holding fixture")
        #expect(Set(files).subtracting(named) == Self.expected)
        for file in files {
            let data = try Data(contentsOf: dir.appending(path: file))
            #expect(throws: Never.self, Comment(rawValue: file)) { try Self.decode(file, data) }
        }
    }

    /// Overlays replace a saved fixture of the same name, so each one decodes with that fixture's model.
    @Test func decodesEveryOverlay() throws {
        let dir = try #require(Bundle.main.url(forResource: "Fixtures", withExtension: nil)).appending(path: "overlays")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") }
        #expect(Set(files) == [
            "budgets-month.json", "subscriptions.json", "import-email-config.json", "reports-trends.json",
            "reconcile-summary.json", "reconcile-suggestions.json", "reconcile-balance-summary.json"
        ])
        #expect(Set(files).isSubset(of: Self.expected), "an overlay replaces a saved fixture")
        for file in files {
            let data = try Data(contentsOf: dir.appending(path: file))
            #expect(throws: Never.self, Comment(rawValue: file)) { try Self.decode(file, data) }
        }
    }

    @Test func overlayWinsOverTheSavedFixture() throws {
        let data = try #require(Fixtures.data(for: "/api/subscriptions"))
        let subscriptions = try JSONDecoder().decode([Subscription].self, from: data)
        #expect(subscriptions.map(\.displayName).contains("Netflix"))
    }

    @Test func mapsPathsToFixtureFiles() throws {
        #expect(Fixtures.data(for: "/api/dashboard") != nil)
        #expect(Fixtures.data(for: "/api/budgets/month") != nil)
        #expect(Fixtures.data(for: "/api/auth/session") != nil)
        #expect(Fixtures.data(for: "/api/portfolio/holdings/3543/lots") != nil)
        #expect(Fixtures.data(for: "/api/reports") != nil)
        #expect(Fixtures.data(for: "/api/missing") == nil)
        #expect(try Fixtures.respond(method: "POST", path: "/api/transactions") == Data("{}".utf8))
        #expect(throws: APIError.self) { try Fixtures.respond(method: "GET", path: "/api/missing") }
        #expect(throws: APIError.self) { try Fixtures.respond(method: "DELETE", path: "/api/categories") }
    }
}
