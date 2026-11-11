// Decodes saved API responses with the app's models. Run through scripts/check-api.sh.
import Foundation

@main
struct DecodeCheck {
    static func main() throws {
        let dir = URL(fileURLWithPath: CommandLine.arguments[1])
        func load<T: Decodable>(_ file: String, _ type: T.Type) throws -> T {
            let data = try Data(contentsOf: dir.appending(path: file))
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                print("FAIL \(file): \(error)")
                exit(1)
            }
        }
        struct Envelope<T: Decodable>: Decodable { let data: T }

        let session = try load("session.json", SessionInfo.self)
        precondition(session.authenticated, "not signed in")
        let dashboard = try load("dashboard.json", Dashboard.self)
        precondition(!dashboard.balances.isEmpty, "no balances")
        _ = try load("accounts.json", [Account].self)
        _ = try load("categories.json", [Category].self)
        let page = try load("transactions.json", TransactionPage.self)
        precondition(page.total >= page.data.count, "bad total")
        _ = try load("search.json", TransactionPage.self)
        _ = try load("budgets-month.json", Envelope<BudgetMonth>.self)
        _ = try load("portfolio-overview.json", PortfolioOverview.self)
        _ = try load("net-worth-history.json", NetWorthHistory.self)
        struct Items<T: Decodable>: Decodable { let items: [T] }
        struct Recurring: Decodable { let recurring: [RecurringSuggestion] }
        _ = try load("spotlight.json", Items<SpotlightItem>.self)
        _ = try load("subscriptions.json", [Subscription].self)
        _ = try load("recurring.json", Recurring.self)
        _ = try load("goals.json", [Goal].self)
        _ = try load("loans.json", [Loan].self)
        _ = try load("fx.json", FxRates.self)
        _ = try load("rules.json", [Rule].self)
        _ = try load("user-me.json", UserMe.self)
        _ = try load("settings-display-currency.json", DisplayCurrencySetting.self)
        _ = try load("transactions-splits.json", [Split].self)
        _ = try load("portfolio-dividends.json", Envelope<DividendIncome>.self)
        _ = try load("portfolio-realized-gains.json", Envelope<RealizedGains>.self)
        _ = try load("reports.json", IncomeStatement.self)
        _ = try load("reports-trends.json", Trends.self)
        _ = try load("import-staged.json", [StagedImport].self)
        _ = try load("reconcile-summary.json", ReconcileSummary.self)
        _ = try load("reconcile-suggestions.json", Envelope<ReconcileSnapshot>.self)
        _ = try load("portfolio-performance.json", Envelope<PortfolioPerformance>.self)
        _ = try load("portfolio-performance-holdings.json", Envelope<HoldingPerformance>.self)
        _ = try load("reconcile-balance-summary.json", Envelope<BalanceSummary>.self)
        _ = try load("settings-active-currencies.json", ActiveCurrencies.self)
        _ = try load("settings-bank-feeds-simplefin-status.json", BankFeedStatus.self)
        _ = try load("settings-fx-rate-view.json", Envelope<FxRateView>.self)
        if FileManager.default.fileExists(atPath: dir.appending(path: "import-staged-detail.json").path) {
            _ = try load("import-staged-detail.json", StagedDetail.self)
        }
        if FileManager.default.fileExists(atPath: dir.appending(path: "holding-lots.json").path) {
            _ = try load("holding-lots.json", HoldingLots.self)
        }

        print("OK: net worth \(dashboard.netWorth.money(dashboard.displayCurrency)), \(page.total) transactions")
    }
}
