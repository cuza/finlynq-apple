import OSLog
import SwiftUI

/// The Wealth tab (Wealth.dc.html) and the Accounts sidebar item on iPad and Mac: net worth split into assets and
/// debts, the investments summary, cash accounts and debts. Rows push the account, investments, debts or loan.
struct WealthView: View {
    static let log = Logger(subsystem: "dev.cuza.finlynq", category: "wealth")
    @Environment(Session.self) private var session
    /// The shell: the sidebar names this page Accounts, the tab bar names it Wealth.
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.layoutWidth) private var width
    @State private var data: WealthData?
    @State private var error: String?
    @Environment(\.presentEditor) private var present

    struct WealthData {
        let dashboard: Dashboard
        var overview: PortfolioOverview?
        var performance: [ValuePoint] = []
        /// Net worth a year ago to today, for the change under the net worth.
        var netWorth: [NetWorthHistory.Point] = []
        /// Wider columns only: a line under each cash account, by account id (iPadPAccounts.dc.html).
        var cashNotes: [Int: String] = [:]
        var loans: [Loan] = []
        /// The latest payment into each credit card, by account id.
        var cardPayments: [Int: Transaction] = [:]
        /// Sources that failed, so their cards show a retry instead of looking empty.
        var failed: Set<String> = []
        let today: Date
    }

    private var isWide: Bool { width == .wide }

    private var title: String {
        #if os(macOS)
        "Accounts"
        #else
        sizeClass == .regular ? "Accounts" : "Wealth"
        #endif
    }

    var body: some View {
        LoadState(value: data, error: error, retry: reload) { data in
            ScrollView { content(data) }
        }
        .background(Theme.page)
        .navigationTitle(title)
        #if os(iOS)
        .toolbarTitleDisplayMode(.large)
        #endif
        .navigationDestination(for: AppRoute.self) { RouteDestination(route: $0) }
        .task(id: "\(session.revision)|\(width == .compact)") { await load() }
        .refreshable { await load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add account", systemImage: "rectangle.stack.badge.plus") { present(.addAccount) }
                    .macTitleAndIcon()
                    .help("Add an account")
            }
        }
    }

    @ViewBuilder
    private func content(_ data: WealthData) -> some View {
        let currency = data.dashboard.displayCurrency
        let rich = width != .compact
        let netWorth = NetWorthSplitCard(dashboard: data.dashboard, history: data.netWorth, currency: currency, whole: rich)
        let investments = InvestmentsSummaryCard(data: data, currency: currency, precise: rich) { Task { await load() } }
        let cash = CashSection(balances: WealthModel.cash(data.dashboard.balances), notes: data.cashNotes, currency: currency, icons: rich)
        let debts = DebtsSection(data: data, currency: currency, icons: rich) { Task { await load() } }
        if isWide {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) { netWorth; investments }.frame(maxWidth: .infinity)
                VStack(spacing: 16) { cash; debts }.frame(maxWidth: .infinity)
            }
            .padding(20)
        } else {
            VStack(spacing: 12) { netWorth; investments; cash; debts }
                .padding(.horizontal, 20).padding(.vertical, 8)
        }
    }

    private func reload() { Task { await load() } }

    /// Each cash account's bank check, or else its latest money in. Accounts with neither get no line.
    private func cashNotes(_ ids: [Int]) async -> [Int: String] {
        let api = session.api
        // All 2N requests run at once, so the first paint waits about one round trip, not 2N.
        async let latestIn = api.lastPayments(accountIds: ids)
        let checks = await withTaskGroup(of: (Int, BalanceSummary?).self) { group in
            for id in ids { group.addTask { (id, try? await api.balanceSummary(accountId: id)) } }
            var checks: [Int: BalanceSummary] = [:]
            for await (id, check) in group { checks[id] = check }
            return checks
        }
        let payments = await latestIn
        var notes: [Int: String] = [:]
        for id in ids { notes[id] = WealthModel.cashNote(check: checks[id], latestIn: payments[id]) }
        return notes
    }

    private func load() async {
        let api = session.api
        do {
            let dashboard = try await api.dashboard()
            var next = WealthData(dashboard: dashboard, today: Fixtures.today)
            let hasInvestments = !WealthModel.investmentAccounts(dashboard.balances).isEmpty
            async let overview = hasInvestments ? optionalLoad("portfolio") { try await api.portfolioOverview() } : nil
            async let performance = hasInvestments ? optionalLoad("performance") { try await api.portfolioPerformance(period: "1y") } : nil
            async let loans = optionalLoad("loans") { try await api.loans() }
            async let history = optionalLoad("net worth") { try await api.netWorthHistory(period: "1y") }
            if hasInvestments {
                next.overview = await overview
                if next.overview == nil { next.failed.insert("portfolio") }
                next.performance = await performance.map { series in
                    WealthModel.trim(series.series, period: "6m", today: next.today) { $0.day }
                        .map { ValuePoint(day: $0.day, value: $0.marketValue) }
                } ?? []
            }
            if let loaded = await loans { next.loans = loaded } else { next.failed.insert("loans") }
            next.netWorth = await history?.series ?? []
            let cards = WealthModel.debts(dashboard.balances).filter { card in !next.loans.contains { $0.accountId == card.accountId } }
            next.cardPayments = await api.lastPayments(accountIds: cards.map(\.accountId))
            if width != .compact { next.cashNotes = await cashNotes(WealthModel.cash(dashboard.balances).map(\.accountId)) }
            data = next
            error = nil
        } catch is CancellationError {
        } catch {
            Self.log.error("dashboard failed: \(String(describing: error), privacy: .public)")
            self.error = error.localizedDescription
        }
    }
}

// MARK: Cards

private struct NetWorthSplitCard: View {
    let dashboard: Dashboard
    let history: [NetWorthHistory.Point]
    let currency: String
    /// iPadPAccounts.dc.html shows the net worth in whole units.
    var whole = false

    var body: some View {
        let split = WealthModel.split(dashboard.balances)
        let total = split.assets + abs(split.debts)
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Net worth").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                if whole {
                    Text(dashboard.netWorth.wholeMoney(currency)).font(.system(size: 36, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.6)
                } else {
                    HeadlineMoney(amount: dashboard.netWorth, currency: currency, size: 36)
                }
                if let change = HomeModel.change(history) {
                    let text = HomeModel.signedChange(change.amount, percent: change.percent, currency: currency)
                    ChangePill(text: text + " past year", isUp: change.amount >= 0)
                }
                if total > 0 {
                    AllocationBar(segments: [(split.assets / total, Theme.accent), (abs(split.debts) / total, Theme.spendBar)])
                }
                let assets = LegendItem(color: Theme.accent, name: "Assets", value: split.assets.wholeMoney(currency)).fixedSize()
                let debts = LegendItem(color: Theme.spendBar, name: "Debts", value: abs(split.debts).wholeMoney(currency)).fixedSize()
                // Amounts never truncate: on a narrow column the two figures stack.
                ViewThatFits(in: .horizontal) {
                    HStack { assets; Spacer(minLength: 12); debts }
                    VStack(alignment: .leading, spacing: 6) { assets; debts }
                }
                .font(.subheadline)
            }
        }
    }
}

private struct InvestmentsSummaryCard: View {
    let data: WealthView.WealthData
    let currency: String
    /// Shares to one decimal (iPadPAccounts.dc.html).
    var precise = false
    let retry: () -> Void

    var body: some View {
        NavigationLink(value: AppRoute.investments) {
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        IconTile(symbol: "chart.line.uptrend.xyaxis", tint: Theme.invest, background: Theme.investTint, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Investments").font(.headline).foregroundStyle(Theme.text)
                            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Theme.secondary).lineLimit(1) }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                    }
                    body(for: data)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// "Brokerage · 5 holdings" (iPadPAccounts.dc.html).
    private var subtitle: String? {
        let names = WealthModel.investmentAccounts(data.dashboard.balances).map(\.name)
        guard !names.isEmpty else { return nil }
        let holdings = data.overview.map { "\($0.byHolding.count) \($0.byHolding.count == 1 ? "holding" : "holdings")" }
        return [ListFormatter.localizedString(byJoining: names), holdings].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    @ViewBuilder
    private func body(for data: WealthView.WealthData) -> some View {
        if WealthModel.investmentAccounts(data.dashboard.balances).isEmpty {
            Text("No investment accounts yet. Open your brokerage account below, tap Edit and turn on "
                + "\"Investment account\" to see its holdings here.")
                .font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        } else if let overview = data.overview {
            let summary = overview.summary
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.totalValueDisplay.wholeMoney(currency))
                        .font(.system(size: 26, weight: .bold)).monospacedDigit().foregroundStyle(Theme.text)
                    Text(Double.todayText(summary.dayChangeDisplay, percent: summary.dayChangePct, currency: currency))
                        .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(summary.dayChangeDisplay.gainColor)
                }
                Spacer(minLength: 12)
                if data.performance.count > 1 {
                    TimeSeriesChart(points: data.performance, color: Theme.invest, height: 44, xAxis: .hidden, interactive: false)
                        .frame(width: 120)
                        .accessibilityHidden(true)
                }
            }
            let top = WealthModel.topHoldings(overview.byHolding, limit: 4)
            if !top.isEmpty {
                let colors = colors(top, overview)
                AllocationBar(segments: zip(top, colors).map { ($0.share, $1) })
                HStack(spacing: 14) {
                    ForEach(top) { slice in
                        let share = precise ? (slice.share * 100).formatted(.number.precision(.fractionLength(1)))
                            : String(Int((slice.share * 100).rounded()))
                        Text("\(slice.name) \(share)%").lineLimit(1)
                    }
                }
                .font(.subheadline).monospacedDigit().foregroundStyle(Theme.secondary)
            }
        } else if data.failed.contains("portfolio") {
            InlineError(message: "Couldn't load holdings", retry: retry)
        }
    }

    private func colors(_ top: [WealthModel.Slice], _ overview: PortfolioOverview) -> [Color] {
        var rank = 0
        return top.map { slice in
            let type = overview.byHolding.first { $0.key == slice.id }?.assetType ?? "stock"
            defer { if type != "crypto" && type != "cash" { rank += 1 } }
            return WealthColors.forType(type, rank: rank)
        }
    }
}

/// Section header above a card: a grey title on the left, a figure or link on the right.
struct WealthSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary).accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
        .padding(.horizontal, 4).padding(.top, 6)
    }
}

private struct CashSection: View {
    let balances: [Dashboard.Balance]
    let notes: [Int: String]
    let currency: String
    let icons: Bool

    var body: some View {
        if !balances.isEmpty {
            VStack(spacing: 8) {
                WealthSectionHeader(title: "Cash") {
                    Text(balances.reduce(0) { $0 + $1.convertedBalance }.wholeMoney(currency))
                        .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.secondary)
                }
                Card(padding: 0) {
                    DividedRows(items: balances) { balance in
                        NavigationLink(value: AppRoute.account(balance.accountId)) {
                            AccountLine(name: balance.name, detail: notes[balance.accountId], amount: balance.balance,
                                        currency: balance.currency, icon: icons ? Self.icon(balance) : nil)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

private struct DebtsSection: View {
    let data: WealthView.WealthData
    let currency: String
    let icons: Bool
    let retry: () -> Void

    var body: some View {
        let debts = WealthModel.debts(data.dashboard.balances)
        if !debts.isEmpty {
            VStack(spacing: 8) {
                WealthSectionHeader(title: "Debts \u{00B7} " + debts.reduce(0) { $0 + $1.convertedBalance }.wholeMoney(currency)) {
                    NavigationLink("Payoff plan", value: AppRoute.debts)
                        .buttonStyle(.plain).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                Card(padding: 0) {
                    DividedRows(items: debts) { balance in
                        let loan = data.loans.first { $0.accountId == balance.accountId }
                        NavigationLink(value: loan.map { AppRoute.loan($0.id) } ?? AppRoute.account(balance.accountId)) {
                            row(balance, loan: loan)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                }
                if data.failed.contains("loans") { InlineError(message: "Couldn't load loans", retry: retry) }
            }
        }
    }

    private func row(_ balance: Dashboard.Balance, loan: Loan?) -> some View {
        VStack(spacing: 0) {
            if let loan {
                let payment = WealthModel.paymentLabel(loan, short: true)
                let payoff = loan.payoffDate.flatMap(APIDate.parse)
                let payoffText = payoff.map { "paid off \($0.monthYear)" } ?? "no payoff date"
                AccountLine(
                    name: loan.displayName, detail: "\(payment) \u{00B7} \(payoffText)",
                    amount: balance.balance, currency: balance.currency,
                    icon: icons ? (DebtsView.symbol(loan), Theme.warning) : nil
                )
                ProgressLine(value: WealthModel.percentPaid(loan), color: Theme.spendBar, height: 6)
                    .padding(.leading, icons ? 48 : 0).padding(.bottom, 14)
            } else {
                AccountLine(
                    name: balance.name, detail: data.cardPayments[balance.accountId].map(WealthModel.lastPaidText),
                    amount: balance.balance, currency: balance.currency, icon: icons ? ("creditcard", Theme.accent) : nil
                )
            }
        }
    }
}

/// An account row: bold name with an optional grey detail line, and the balance in the account's currency.
struct AccountLine: View {
    let name: String
    let detail: String?
    let amount: Double
    let currency: String
    /// A tile before the name on wider columns (iPadPAccounts.dc.html).
    var icon: (symbol: String, tint: Color)?

    var body: some View {
        HStack(spacing: 12) {
            if let icon { IconTile(symbol: icon.symbol, tint: icon.tint, background: icon.tint.opacity(0.14), size: 36) }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                if let detail, !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(Theme.secondary).lineLimit(2) }
            }
            Spacer(minLength: 8)
            Text(MoneyText.format(amount, currency: currency))
                .font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.text).fixedSize()
        }
        .padding(.vertical, detail == nil ? 14 : 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension CashSection {
    /// A cash account's tile: a dollar sign for savings, the bank building otherwise (iPadPAccounts.dc.html).
    static func icon(_ balance: Dashboard.Balance) -> (symbol: String, tint: Color) {
        "\(balance.name) \(balance.accountGroup)".lowercased().contains("saving")
            ? ("dollarsign.circle", Theme.positive) : ("building.columns", Theme.accent)
    }
}

// MARK: Add account

/// Creates an account with `POST /api/accounts`: name, asset or liability, group, currency, and the investment flag.
/// A preset (from first-run setup) fills the form in.
struct AddAccountSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type = "A"
    @State private var group = ""
    @State private var currency = ""
    @State private var isInvestment = false
    @State private var saving = false
    @State private var error: String?

    init(preset: AccountPreset? = nil) {
        guard let preset, !preset.isOther else { return }
        _name = State(initialValue: preset.title)
        _type = State(initialValue: preset.type)
        _group = State(initialValue: preset.group)
        _isInvestment = State(initialValue: preset.isInvestment)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Type", selection: $type) {
                    Text("Asset").tag("A")
                    Text("Liability").tag("L")
                }
                TextField("Group, such as Banks or Credit Cards", text: $group)
                TextField("Currency", text: $currency)
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
                if type == "A" { Toggle("Investment account", isOn: $isInvestment) }
                if let error { Text(error).foregroundStyle(Theme.negative) }
            }
            .formStyle(.grouped)
            .navigationTitle("New account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await save() } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onAppear { if currency.isEmpty { currency = session.currency } }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await session.api.createAccount(AccountInput(
                name: name.trimmingCharacters(in: .whitespaces), type: type, group: group.trimmingCharacters(in: .whitespaces),
                currency: currency.trimmingCharacters(in: .whitespaces).uppercased(), isInvestment: type == "A" && isInvestment
            ))
            await session.didSave()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
