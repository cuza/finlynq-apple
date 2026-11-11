import SwiftUI

struct HomeView: View {
    @Environment(Session.self) private var session
    @Environment(ReviewStatus.self) private var review
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.layoutWidth) private var width
    @Environment(\.layoutColumn) private var column
    @State private var data: HomeData?
    @State private var error: String?
    @State private var period = "1y"
    @Environment(\.showSettings) private var showSettings

    /// Everything Home shows. Only the dashboard is required: the rest degrades to empty.
    struct HomeData {
        let dashboard: Dashboard
        var history: [NetWorthHistory.Point]
        /// The history request failed, so the chart shows a retry instead of an empty card.
        var historyFailed = false
        let budget: BudgetMonth?
        let bills: [Subscription]
        /// The account that pays each loan, keyed by the loan's account id.
        let loanPayers: [Int: (id: Int, name: String)]
        let recent: [Transaction]
        let today: Date
    }

    private var layout: HomeLayout { HomeLayout(width, column: column, macNeeds: MacDesignWidth.home) }

    /// iPad portrait (iPadPHome) and iPhone Duo's open display (DuoInnerHome): the iPad cards, stacked.
    private var portrait: Bool { layout == .pad && width == .medium }

    var body: some View {
        Group {
            if let data {
                content(data)
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.page)
        .navigationTitle("Home")
        .navigationDestination(for: AppRoute.self) { RouteDestination(route: $0) }
        .task(id: session.revision) { await load() }
        .refreshable { await load() }
        .onChange(of: period) { Task { await reloadHistory() } }
        #if os(macOS)
        .toolbar {
            // MacHome has the period in the toolbar; the iPad and iPhone cards have their own.
            if layout == .mac { ToolbarItem(placement: .primaryAction) { PeriodPicker(period: $period).frame(width: 176) } }
        }
        #else
        .toolbarTitleDisplayMode(.large)
        .toolbar {
            // iPad opens Settings from the sidebar.
            if sizeClass == .compact {
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "person.crop.circle") { showSettings() }
                }
            }
        }
        #endif
    }

    // MARK: Layout

    private func content(_ data: HomeData) -> some View {
        let currency = session.currency
        let bills = HomeModel.billsThisWeek(data.bills, budget: data.budget, loanPayers: data.loanPayers, today: data.today)
        let netWorth = NetWorthCard(layout: layout, portrait: portrait, data: data, period: $period, currency: currency, retry: retry)
        let attention = NeedsAttentionCard(items: attentionItems(data, bills: bills), layout: layout)
        let budget = BudgetCard(layout: layout, portrait: portrait, budget: data.budget, today: data.today, currency: currency)
        let billsCard = BillsCard(
            layout: layout, bills: bills, today: data.today, currency: currency,
            afterBills: HomeModel.afterBills(bills, balances: data.dashboard.balances)
        )
        let recent = RecentCard(layout: layout, portrait: portrait, transactions: Array(data.recent.prefix(3)), today: data.today)
        return ScrollView {
            switch layout {
            case .pad where portrait:
                stacked(netWorth: netWorth, attention: attention, budget: budget, bills: billsCard, recent: recent)
            case .phone:
                VStack(spacing: 14) {
                    netWorth; attention; budget
                    RecentCard(layout: .phone, transactions: Array(data.recent.prefix(2)), today: data.today)
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
            case .pad:
                VStack(spacing: 18) {
                    netWorth
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 16) { attention; recent }
                        VStack(spacing: 16) { budget; billsCard }
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 12)
            case .mac:
                VStack(spacing: 16) {
                    #if os(macOS)
                    KPIRow(data: data, period: period, currency: currency)
                    #endif
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 16) {
                            netWorth
                            RecentCard(layout: .mac, transactions: Array(data.recent.prefix(5)), today: data.today)
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 16) { attention; budget; billsCard }
                            .frame(minWidth: 320, maxWidth: 390)
                    }
                }
                .padding(20)
            }
        }
    }

    private func attentionItems(_ data: HomeData, bills: [Bill]) -> [AttentionItem] {
        let reviewAccount = review.accountId.flatMap { id in data.dashboard.balances.first { $0.accountId == id }?.name }
        return HomeModel.attention(
            stagedCount: review.count, budget: data.budget, bills: bills, today: data.today, currency: session.currency,
            reviewAccount: reviewAccount, wide: layout != .phone, trailing: portrait
        ) + [HomeModel.applePayItem(ApplePayCapture.store.items)].compactMap(\.self)
    }

    /// Two columns when the column has room (DuoInnerHome), else one (iPadPHome).
    private func stacked(
        netWorth: NetWorthCard, attention: NeedsAttentionCard, budget: BudgetCard, bills: BillsCard, recent: RecentCard
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            VStack(spacing: 14) {
                netWorth
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 14) { attention; bills }
                    VStack(spacing: 14) { budget; recent }
                }
            }
            .wideEnough(600)
            VStack(spacing: 14) { netWorth; attention; budget; bills; recent }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }

    // MARK: Loading

    private func load() async {
        let api = session.api
        let today = Fixtures.today
        let month = String(APIDate.string(today).prefix(7))
        do {
            let dashboard = try await api.dashboard()
            async let history = fetchHistory()
            async let budget = optionalLoad("budget") { try await api.budgetMonth(month) }
            async let bills = optionalLoad("subscriptions") { try await api.subscriptions() }
            async let recent = optionalLoad("recent transactions") { try await api.transactions(TransactionQuery(limit: 5)) }
            let budgetMonth = await budget
            let points = await history
            let home = await HomeData(
                dashboard: dashboard, history: points ?? [], historyFailed: points == nil, budget: budgetMonth,
                bills: bills ?? [], loanPayers: await loanPayers(budgetMonth), recent: recent?.data ?? [], today: today
            )
            // A cancelled load (the tab changed, or a newer load started) fails its requests; showing that would put
            // "Couldn't load history" or an error on screen for a load nobody is waiting for.
            guard !Task.isCancelled else { return }
            data = home
            error = nil
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            self.error = error.localizedDescription
        }
    }

    /// For each unpaid loan in the budget, the account that paid its latest payment (two small requests per loan).
    private func loanPayers(_ budget: BudgetMonth?) async -> [Int: (id: Int, name: String)] {
        var payers: [Int: (id: Int, name: String)] = [:]
        for debt in budget?.debt ?? [] where debt.paid < debt.planned {
            guard let legs = await optionalLoad("loan payments", {
                      try await session.api.transactions(TransactionQuery(accountId: debt.accountId, limit: 10)).data
                  }),
                  let day = legs.filter(\.isTransfer).map({ String($0.date.prefix(10)) }).max(),
                  let sameDay = await optionalLoad("loan payer", {
                      try await session.api.transactions(TransactionQuery(startDate: day, endDate: day, limit: 50)).data
                  })
            else { continue }
            payers[debt.accountId] = HomeModel.payingAccount(loanLegs: legs, sameDay: sameDay)
        }
        return payers
    }

    private func retry() { Task { await reloadHistory() } }

    private func reloadHistory() async {
        let points = await fetchHistory()
        guard !Task.isCancelled, var current = data else { return }
        current.history = points ?? []
        current.historyFailed = points == nil
        data = current
    }

    /// The chart's points for the selected period, or nil when the request fails.
    private func fetchHistory() async -> [NetWorthHistory.Point]? {
        let period = period
        let series = await optionalLoad("net worth history") {
            try await session.api.netWorthHistory(period: HomeModel.requestPeriod(period)).series
        }
        return series.map { HomeModel.trim($0, period: period, today: Fixtures.today) }
    }
}
