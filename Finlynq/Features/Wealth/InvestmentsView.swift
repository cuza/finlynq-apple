import SwiftUI

/// Investments (Investments.dc.html, iPadInvestments.dc.html, MacInvestments.dc.html): market value with its
/// performance against cost basis, returns, allocation and the holdings. iPhone and iPad portrait (iPadPInvestments.dc.html)
/// push a holding; iPhone Duo open (DuoInnerInvestments.dc.html), iPad landscape and Mac show the selected holding
/// beside the list. Record opens the Add sheet in invest mode.
struct InvestmentsView: View {
    @Environment(Session.self) private var session
    @Environment(\.layoutWidth) private var width
    @Environment(\.layoutColumn) private var column
    /// This screen's own width, which decides between a pushed holding and one beside the list on `.medium`.
    @State private var columnWidth: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var data: InvestData?
    @State private var error: String?
    @State private var period = "1y"
    @State private var groupByAccount = false
    @State private var selected: String?
    /// The new symbol after the inspector's edit renamed the selected holding, until the reload picks it up.
    @State private var renamed: String?
    @Environment(\.presentEditor) private var present

    struct InvestData {
        /// Nil when no account is flagged as an investment account.
        let overview: PortfolioOverview?
        var performance: PortfolioPerformance?
        var points: [ValuePoint] = []
        var performanceFailed = false
        let accountNames: [String]
        let today: Date
    }

    private var layout: HomeLayout { HomeLayout(width, column: column, macNeeds: MacDesignWidth.investments) }

    /// The narrowest column that holds the list and the holding side by side on `.medium` (the Duo's open display is 669pt).
    static let paneMinimum: CGFloat = 640

    /// Whether the holding sits beside the list: on `.wide`, and on `.medium` from `paneMinimum`. iPad portrait pushes it.
    /// Until the screen has measured itself (`column` 0) it pushes, so a seeded `.wide` doesn't flash the pane.
    /// Larger text needs more room, as in `LayoutWidth`.
    static func showsPane(_ width: LayoutWidth, column: CGFloat, typeSize: DynamicTypeSize = .large) -> Bool {
        width != .compact && column / max(1, LayoutWidth.textScale(typeSize)) >= paneMinimum
    }

    var body: some View {
        LoadState(value: data, error: error, retry: reload) { data in
            if let overview = data.overview {
                switch layout {
                case .phone: phone(data, overview)
                case .pad where Self.showsPane(width, column: columnWidth, typeSize: typeSize): pad(data, overview)
                case .pad: portrait(data, overview)
                case .mac: mac(data, overview)
                }
            } else {
                EmptyState(
                    title: "No investment accounts",
                    message: "Open your brokerage account under Accounts, tap Edit and turn on \"Investment account\". "
                        + "Its holdings, returns and performance then show here.",
                    symbol: "chart.line.uptrend.xyaxis"
                )
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columnWidth = $0 }
        .background(Theme.page)
        .navigationTitle("Investments")
        #if os(iOS)
        .toolbarTitleDisplayMode(.large)
        #endif
        .navigationDestination(for: AppRoute.self) { RouteDestination(route: $0) }
        .toolbar { toolbar }
        .task(id: session.revision) { await load() }
        .onChange(of: data?.overview?.byHolding.map(\.key)) {
            selected = WealthModel.reselect(data?.overview?.byHolding ?? [], selected: selected, renamed: renamed)
            renamed = nil
        }
        .onChange(of: period) { Task { await loadPerformance() } }
        .refreshable { await load() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        #if os(macOS)
        // No Record or period controls until an account is flagged as an investment account.
        if data?.overview != nil {
            // The iPad and iPhone layouts of a narrower window have the period and grouping in their content.
            if layout == .mac {
                ToolbarItem(placement: .primaryAction) { PeriodPicker(period: $period, options: PeriodChips.options).fixedSize() }
                ToolbarItem(placement: .primaryAction) {
                    Toggle("Group by account", isOn: $groupByAccount).toggleStyle(.switch).controlSize(.small)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Record", systemImage: "cart.badge.plus") { record(nil) }
                    .macTitleAndIcon()
                    .help("Record a buy, sell, dividend or other operation")
            }
        }
        #else
        if layout == .phone && data?.overview != nil {
            ToolbarItem(placement: .primaryAction) { Button("Record", systemImage: "cart.badge.plus") { record(nil) } }
        }
        #endif
    }

    private func reload() { Task { await load() } }

    private func record(_ prefill: AddModel.InvestPrefill?) { present(.record(prefill)) }

    // MARK: iPhone

    private func phone(_ data: InvestData, _ overview: PortfolioOverview) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                marketValueCard(data, overview)
                ReturnsCard(summary: overview.summary, currency: overview.displayCurrency, layout: layout)
                allocationCard(overview)
                HStack {
                    Text("Holdings \u{00B7} \(overview.byHolding.count)").font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    Toggle("Group by account", isOn: $groupByAccount).font(.subheadline.weight(.medium)).fixedSize()
                }
                .padding(.horizontal, 4).padding(.top, 6)
                HoldingsList(overview: overview, layout: layout, groupByAccount: $groupByAccount, selected: $selected)
                taxLinks
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
    }

    private func marketValueCard(_ data: InvestData, _ overview: PortfolioOverview) -> some View {
        let summary = overview.summary
        let currency = overview.displayCurrency
        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Market value").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                        Text(summary.totalValueDisplay.wholeMoney(currency))
                            .font(.system(size: layout == .phone ? 36 : 32, weight: .bold)).monospacedDigit()
                            .foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.6)
                        Text(todayText(summary, currency: currency))
                            .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(summary.dayChangeDisplay.gainColor)
                    }
                    Spacer(minLength: 8)
                    ReturnBadges(performance: data.performance)
                }
                performanceChart(data, height: layout == .phone ? 150 : 110)
                if layout == .phone {
                    PerformanceLegend(
                        summary: overview.summary, currency: overview.displayCurrency, showsCost: data.points.last?.cost != nil,
                        showsValue: layout == .mac
                    )
                    PeriodChips(period: $period).padding(.top, 4)
                } else {
                    HStack {
                        PerformanceLegend(
                            summary: overview.summary, currency: overview.displayCurrency, showsCost: data.points.last?.cost != nil,
                            showsValue: layout == .mac
                        )
                        Spacer()
                        PeriodChips(period: $period).frame(width: 260)
                    }
                }
            }
        }
    }

    /// "In Insights, Tax time" (Investments.dc.html): dividends and realized gains open the tax reports.
    private var taxLinks: some View {
        VStack(spacing: 8) {
            WealthSectionHeader(title: "In Insights, Tax time") { EmptyView() }
            Card(padding: 0) {
                VStack(spacing: 0) {
                    taxRow("Dividends", "By year and holding", symbol: "dollarsign.circle", tint: Theme.positiveBar)
                    Divider().padding(.leading, 16)
                    taxRow("Realized gains", "Short and long term, by tax year", symbol: "doc.text", tint: Theme.invest)
                }
            }
        }
    }

    private func taxRow(_ title: String, _ detail: String, symbol: String, tint: Color) -> some View {
        NavigationLink(value: AppRoute.tax) {
            HStack(spacing: 12) {
                if layout != .phone { IconTile(symbol: symbol, tint: tint, background: tint.opacity(0.14), size: 36) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(detail).font(.subheadline).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func todayText(_ summary: PortfolioOverview.Summary, currency: String) -> String {
        Double.todayText(summary.dayChangeDisplay, percent: summary.dayChangePct, currency: currency)
    }

    @ViewBuilder
    private func performanceChart(_ data: InvestData, height: CGFloat) -> some View {
        if data.performanceFailed {
            InlineError(message: "Couldn't load performance", retry: reload)
        } else if data.points.count > 1 {
            TimeSeriesChart(points: data.points, color: Theme.invest, height: height, yAxis: layout == .mac ? .leading(3) : .hidden,
                            currency: data.overview?.displayCurrency)
                .accessibilityLabel(chartSummary(data))
        } else {
            Text("No performance history for this period yet.").font(.subheadline).foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
        }
    }

    private func chartSummary(_ data: InvestData) -> String {
        guard let first = data.points.first, let last = data.points.last else { return "Performance" }
        let currency = data.overview?.displayCurrency
        return "Market value went from \(first.value.wholeMoney(currency)) to \(last.value.wholeMoney(currency))"
    }

    private func allocationCard(_ overview: PortfolioOverview) -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Allocation").font(.headline).foregroundStyle(Theme.text)
                allocation(overview)
            }
        }
    }

    @ViewBuilder
    private func allocation(_ overview: PortfolioOverview) -> some View {
        let slices = WealthModel.allocation(overview.byType)
        AllocationBar(segments: slices.map { ($0.share, WealthColors.forType($0.id)) })
        HStack(spacing: 12) {
            ForEach(slices) { slice in
                LegendItem(color: WealthColors.forType(slice.id), name: slice.name, value: "\(Int((slice.share * 100).rounded()))%")
                if slice != slices.last { Spacer(minLength: 0) }
            }
        }
        .font(layout == .phone ? .subheadline : .footnote)
        .accessibilityElement(children: .combine)
    }

    // MARK: iPad

    /// iPad landscape (iPadInvestments.dc.html), and the Duo's open display (DuoInnerInvestments.dc.html), whose
    /// narrower list stacks the returns and shows the holdings as list rows.
    private func pad(_ data: InvestData, _ overview: PortfolioOverview) -> some View {
        // On the Mac a wide column under iPad landscape's 900pt is too narrow for four returns. `column` is nil on iOS,
        // where every wide column has four returns.
        let narrow = !LayoutWidth.fitsMacDesign(width, column: column, needs: MacDesignWidth.investmentsReturns)
        return HStack(alignment: .top, spacing: 16) {
            ScrollView {
                VStack(spacing: 12) {
                    if narrow { portraitValueCard(data, overview) } else { marketValueCard(data, overview) }
                    ReturnsCard(summary: overview.summary, currency: overview.displayCurrency, layout: narrow ? .phone : layout)
                    HoldingsList(overview: overview, layout: layout, groupByAccount: $groupByAccount, selected: $selected,
                                 asRows: narrow)
                }
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
            inspector(overview)
                .frame(minWidth: 260, maxWidth: narrow ? .infinity : 320)
                .listCard(radius: Theme.cardRadius)
                .padding(.top, 8)
        }
        .padding(.horizontal, narrow ? 16 : 28)
    }

    @ViewBuilder
    private func inspector(_ overview: PortfolioOverview) -> some View {
        if let key = (selected ?? overview.byHolding.first?.key), let holding = overview.byHolding.first(where: { $0.key == key }) {
            HoldingPane(
                holding: holding, overview: overview, layout: layout == .mac ? .inspector : .pane,
                record: { record($0) }, onRename: { renamed = $0 }
            )
                .id(key)
        } else {
            EmptyState(title: "No holdings", message: "Record a buy to start tracking a holding.", symbol: "chart.pie")
        }
    }

    // MARK: Mac

    private func mac(_ data: InvestData, _ overview: PortfolioOverview) -> some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    #if os(macOS)
                    InvestmentKPIs(overview: overview, performance: data.performance, accountNames: data.accountNames)
                    Card(padding: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Performance").font(.title3.weight(.bold))
                                Spacer()
                                PerformanceLegend(
                                    summary: overview.summary, currency: overview.displayCurrency, showsCost: data.points.last?.cost != nil,
                                    showsValue: layout == .mac
                                )
                                if let first = data.points.first, let last = data.points.last {
                                    Text("\(first.day.monthYear) to \(last.day.monthYear)").font(.subheadline)
                                        .foregroundStyle(Theme.secondary)
                                }
                            }
                            performanceChart(data, height: 190)
                        }
                    }
                    HoldingsTable(overview: overview, groupByAccount: groupByAccount, selected: Binding(
                        get: { (selected ?? overview.byHolding.first?.key) }, set: { selected = $0 }
                    ))
                    #endif
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity)
            Divider()
            inspector(overview)
                .frame(width: 280)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.toolbarBackground)
        }
    }
}

extension InvestmentsView {
    // MARK: Loading

    private func load() async {
        let api = session.api
        do {
            let dashboard = try await api.dashboard()
            let accounts = WealthModel.investmentAccounts(dashboard.balances)
            guard !accounts.isEmpty else {
                data = InvestData(overview: nil, accountNames: [], today: Fixtures.today)
                error = nil
                return
            }
            let overview = try await api.portfolioOverview()
            data = InvestData(overview: overview, accountNames: accounts.map(\.name), today: Fixtures.today)
            error = nil
            await loadPerformance()
        } catch is CancellationError {
        } catch {
            WealthView.log.error("investments failed: \(String(describing: error), privacy: .public)")
            self.error = error.localizedDescription
        }
    }

    private func loadPerformance() async {
        guard data?.overview != nil else { return }
        let period = period
        do {
            let performance = try await session.api.portfolioPerformance(period: period)
            let today = data?.today ?? Fixtures.today
            data?.performance = performance
            // The series is in the server's currency; scale it so its last point is today's display-currency value.
            let scale = WealthModel.displayScale(performance.series.last?.marketValue, display: data?.overview?.summary.totalValueDisplay)
            data?.points = WealthModel.trim(performance.series, period: period, today: today) { $0.day }
                .map { ValuePoint(day: $0.day, value: $0.marketValue * scale, cost: $0.costBasis.map { $0 * scale }) }
            data?.performanceFailed = false
        } catch is CancellationError {
        } catch {
            WealthView.log.error("performance failed: \(String(describing: error), privacy: .public)")
            data?.performanceFailed = true
        }
    }
}

extension InvestmentsView {
    // MARK: iPad portrait

    private func portrait(_ data: InvestData, _ overview: PortfolioOverview) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                portraitValueCard(data, overview)
                ReturnsCard(summary: overview.summary, currency: overview.displayCurrency, layout: .phone)
                HoldingsList(overview: overview, layout: layout, groupByAccount: $groupByAccount, selected: $selected,
                             asRows: true, pushes: true)
                taxLinks
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
    }

    /// iPadPInvestments.dc.html: the hero on its own line, today and the returns under it, the period picker on its own row.
    private func portraitValueCard(_ data: InvestData, _ overview: PortfolioOverview) -> some View {
        let summary = overview.summary
        let currency = overview.displayCurrency
        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Market value").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                Text(summary.totalValueDisplay.wholeMoney(currency))
                    .font(.system(size: 36, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.6)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { todayLine(summary, currency: currency); ReturnBadges(performance: data.performance, inRow: true) }
                    VStack(alignment: .leading, spacing: 6) {
                        todayLine(summary, currency: currency)
                        ReturnBadges(performance: data.performance, inRow: true)
                    }
                }
                performanceChart(data, height: 130).padding(.top, 6)
                PerformanceLegend(summary: summary, currency: currency, showsCost: data.points.last?.cost != nil)
                PeriodPicker(period: $period, options: PeriodChips.options).padding(.top, 6)
            }
        }
    }

    private func todayLine(_ summary: PortfolioOverview.Summary, currency: String) -> some View {
        Text(todayText(summary, currency: currency))
            .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(summary.dayChangeDisplay.gainColor)
            .lineLimit(1).fixedSize()
    }
}
