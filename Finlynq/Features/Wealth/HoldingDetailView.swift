import SwiftUI

/// A holding pushed from Investments on iPhone (Holding.dc.html). Loads the portfolio and shows `HoldingPane`.
struct HoldingDetailView: View {
    let symbol: String
    @Environment(Session.self) private var session
    @State private var overview: PortfolioOverview?
    @State private var error: String?
    @Environment(\.presentEditor) private var present
    /// The new symbol after an edit renamed the holding, so the page follows it instead of losing it.
    @State private var renamed: String?

    var body: some View {
        let shown = overview.flatMap { WealthModel.holding(in: $0.byHolding, symbol: symbol, renamed: renamed) }
        LoadState(value: overview, error: error, retry: reload) { overview in
            if let holding = shown {
                HoldingPane(
                    holding: holding, overview: overview, layout: .page, record: { present(.record($0)) }, onRename: { renamed = $0 }
                )
            } else {
                EmptyState(title: "Holding not found", message: "\(symbol) isn't in your portfolio any more.",
                    symbol: "questionmark.circle")
            }
        }
        .background(Theme.page)
        .navigationTitle(shown?.symbol ?? symbol)
        #if os(iOS)
        .toolbarTitleDisplayMode(.large)
        #endif
        .task(id: session.revision) { await load() }
    }

    private func reload() { Task { await load() } }

    private func load() async {
        do {
            overview = try await session.api.portfolioOverview()
            error = nil
        } catch is CancellationError {
        } catch {
            WealthView.log.error("holding failed: \(String(describing: error), privacy: .public)")
            self.error = error.localizedDescription
        }
    }
}

/// A holding's price, chart, position, open lots and recent activity. `page` is the iPhone screen, `pane` the iPad
/// column beside the holdings, `inspector` the Mac column (MacInvestments.dc.html). Buy and Sell call `record`
/// with a prefill for the Add sheet.
struct HoldingPane: View {
    enum Layout { case page, pane, inspector }

    let holding: PortfolioOverview.Holding
    let overview: PortfolioOverview
    let layout: Layout
    let record: (AddModel.InvestPrefill) -> Void
    var onRename: (String) -> Void = { _ in }
    @Environment(Session.self) private var session
    @Environment(\.layoutWidth) private var width
    @State private var lots: [HoldingLots.Lot] = []
    @State private var lotsFailed = false
    @State private var activity: [Transaction] = []
    @State private var activityFailed = false
    @State private var points: [ValuePoint] = []
    @State private var chartFailed = false
    @State private var showEdit = false
    @State private var period = "1y"

    /// Rows of this holding in each account.
    private var positions: [PortfolioOverview.Position] {
        (overview.holdings ?? []).filter { $0.symbol == holding.symbol && ($0.symbol != nil || $0.name == holding.name) }
    }

    /// Figures in the holding's own currency when every account holds it in one, else the display currency.
    private var native: Bool { holding.nativeCurrency != nil && holding.currentPriceNative != nil }
    private var currency: String { native ? holding.nativeCurrency ?? overview.displayCurrency : overview.displayCurrency }
    private var price: Double? { native ? holding.currentPriceNative : holding.currentPriceDisplay }
    private var dayChange: Double? {
        let total = native ? holding.dayChangeNative : holding.dayChangeDisplay
        return holding.totalQty > 0 ? total.map { $0 / holding.totalQty } : nil
    }

    var body: some View {
        content
            .toolbar {
                if layout == .page && !positions.isEmpty {
                    ToolbarItem(placement: .primaryAction) { Button("Edit") { showEdit = true } }
                }
            }
            .sheet(isPresented: $showEdit) { EditHoldingSheet(positions: positions, onRename: onRename) }
            .task(id: "\(holding.key)|\(session.revision)") { await load() }
            .task(id: period) { await loadChart() }
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .page:
            ScrollView {
                VStack(spacing: 12) {
                    Text(subtitleLine).font(.subheadline).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                    valueCard
                    Card(padding: 16) { position }
                    if width == .compact {
                        lotsCard
                    } else {
                        // iPadPHolding.dc.html: "Open lots" heads the card from outside.
                        VStack(spacing: 8) {
                            lotsHeader.font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary).padding(.horizontal, 4)
                            Card(padding: 16) { lotRows }
                        }
                    }
                    if !activity.isEmpty || activityFailed { Card(padding: 16) { activityList } }
                }
                .padding(.horizontal, 20).padding(.bottom, 8)
            }
            #if os(iOS)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BottomActions(actions: [.init(title: "Buy") { trade(.buy) }, .init(title: "Sell") { trade(.sell) }])
            }
            #endif
        case .pane, .inspector:
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    tradeButtons
                    Divider()
                    position
                    Divider()
                    lotsList
                    if layout == .inspector { activityList }
                }
                .padding(layout == .inspector ? 18 : 18)
            }
        }
    }

    private var subtitleLine: String {
        [holding.description ?? (holding.name == holding.symbol ? nil : holding.name),
            currency].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    private var changeText: String? {
        guard let dayChange, let pct = holding.dayChangePct else { return nil }
        return Double.todayText(dayChange, percent: pct, currency: currency, cents: true)
    }

    // MARK: Header and price

    /// The position's value and its chart. The API has value history per holding but no price history, so the card
    /// shows value, with the price per share under it.
    private var valueCard: some View {
        let value = native ? holding.marketValueNative ?? holding.marketValueDisplay : holding.marketValueDisplay
        let change = native ? holding.dayChangeNative : holding.dayChangeDisplay
        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Value").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                // The pill moves under the value when both don't fit on one line, and always on wider columns
                // (iPadPHolding.dc.html).
                ViewThatFits(in: .horizontal) {
                    if width == .compact { HStack(alignment: .center, spacing: 12) { valueText(value); changePill(change) } }
                    VStack(alignment: .leading, spacing: 8) { valueText(value); changePill(change) }
                }
                if let price {
                    Text("\(price.money(currency)) a share").font(.subheadline).monospacedDigit().foregroundStyle(Theme.secondary)
                }
                if chartFailed {
                    InlineError(message: "Couldn't load the value history") { Task { await loadChart() } }
                } else if points.count > 1 {
                    TimeSeriesChart(points: points, color: Theme.invest, height: 140, currency: currency)
                        .accessibilityLabel("Value of your \(holding.symbol ?? holding.name) position over time")
                }
                // iPadPHolding.dc.html: a segmented period row on wider columns.
                if width == .compact { PeriodChips(period: $period) } else { PeriodPicker(period: $period, options: PeriodChips.options) }
            }
        }
    }

    private func valueText(_ value: Double) -> some View {
        Text(value.money(currency)).font(.system(size: 36, weight: .bold)).monospacedDigit().foregroundStyle(Theme.text)
            .lineLimit(1).fixedSize()
    }

    @ViewBuilder
    private func changePill(_ change: Double?) -> some View {
        if let change, let pct = holding.dayChangePct {
            ChangePill(text: Double.todayText(change, percent: pct, currency: currency, cents: true), isUp: change >= 0)
                .lineLimit(1).fixedSize()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(holding.symbol ?? holding.name).font(.title2.weight(.bold)).foregroundStyle(Theme.text)
                if layout == .inspector {
                    Chip(text: holding.assetType.uppercased(), tint: Theme.invest, background: Theme.investTint)
                }
                Spacer()
                if !positions.isEmpty {
                    Button("Edit") { showEdit = true }.buttonStyle(.plain).font(.body.weight(.medium)).foregroundStyle(Theme.accent)
                }
            }
            Text(layout == .inspector ? (holding.description ?? holding.name) : subtitleLine)
                .font(.subheadline).foregroundStyle(Theme.secondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(price.map { $0.money(currency) } ?? "\u{2014}").font(.system(size: 26, weight: .bold)).monospacedDigit()
                if let changeText {
                    if layout == .inspector {
                        Text(changeText).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle((dayChange ?? 0).gainColor)
                    } else {
                        ChangePill(text: changeText, isUp: (dayChange ?? 0) >= 0)
                    }
                }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private var tradeButtons: some View {
        HStack(spacing: 10) {
            Button { trade(.buy) } label: {
                Text("Buy").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: layout == .inspector ? 28 : 44)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: layout == .inspector ? 7 : 12, style: .continuous))
            }
            Button { trade(.sell) } label: {
                Text("Sell").font(.headline).foregroundStyle(layout == .inspector ? Theme.text : Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: layout == .inspector ? 28 : 44)
                    .background(layout == .inspector ? Theme.card : Theme.accentTint,
                                in: RoundedRectangle(cornerRadius: layout == .inspector ? 7 : 12, style: .continuous))
                    .overlay {
                        if layout == .inspector { RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.hairline) }
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private func trade(_ operation: AddModel.InvestOperation) {
        record(AddModel.InvestPrefill(operation: operation, symbol: holding.symbol, accountId: positions.first?.accountId))
    }

    // MARK: Position

    private var position: some View {
        let unrealized = native ? holding.unrealizedGainNative ?? holding.unrealizedGainDisplay : holding.unrealizedGainDisplay
        let total = native ? holding.totalReturnNative ?? holding.totalReturnDisplay : holding.totalReturnDisplay
        let dividends = native ? holding.dividendsNative ?? holding.dividendsDisplay : holding.dividendsDisplay
        let value = native ? holding.marketValueNative ?? holding.marketValueDisplay : holding.marketValueDisplay
        let avg = native ? holding.avgCostNative : holding.avgCostDisplay
        let size: CGFloat = layout == .page ? 19 : 15
        let accounts = Set(positions.compactMap(\.accountName)).sorted()
        return VStack(alignment: .leading, spacing: 12) {
            if layout != .inspector { Text("Your position").font(.headline).foregroundStyle(Theme.text) }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: layout == .page ? 16 : 10) {
                GridRow {
                    Figure(label: "Shares", value: holding.totalQty.formatted(.number.precision(.fractionLength(0...4))), size: size)
                    Figure(label: "Avg cost", value: avg.map { $0.money(currency) } ?? "\u{2014}", size: size)
                }
                let marketValue = Figure(label: "Market value", value: value.money(currency), size: size)
                let unrealizedFigure = Figure(
                    label: layout == .inspector ? "Unrealized" : "Unrealized gain",
                    value: MoneyText.format(unrealized, currency: currency, signed: true), color: unrealized.gainColor,
                    detail: holding.unrealizedGainPct?.signedPercent, size: size
                )
                let share = (holding.pctOfPortfolio ?? 0).formatted(.number.precision(.fractionLength(0...1))) + "%"
                let ofPortfolio = Figure(label: "Of portfolio", value: share, size: size)
                let heldIn = Figure(label: "Held in", value: accounts.isEmpty ? "\u{2014}" : accounts.joined(separator: ", "), size: size)
                // iPhone and iPad put total return first (Holding.dc.html); the Mac inspector puts dividends first.
                let dividendsFigure = Figure(
                    label: layout == .inspector ? "Dividends" : "Dividends received", value: dividends.money(currency), size: size
                )
                let totalFigure = Figure(
                    label: "Total return", value: MoneyText.format(total, currency: currency, signed: true), color: total.gainColor,
                    detail: holding.totalReturnPct.map { $0.signedPercent + (layout == .inspector ? "" : ", with dividends") }, size: size
                )
                if layout == .pane || (layout == .page && width != .compact) {
                    // iPadPHolding.dc.html pairs value with share, the two gains, and dividends with the account; the
                    // iPad landscape and open Duo panes follow the same order.
                    GridRow { marketValue; ofPortfolio }
                    GridRow { unrealizedFigure; totalFigure }
                    GridRow { dividendsFigure; heldIn }
                } else {
                    GridRow { marketValue; unrealizedFigure }
                    GridRow {
                        if layout == .inspector { dividendsFigure; totalFigure } else { totalFigure; dividendsFigure }
                    }
                    if layout == .page { GridRow { ofPortfolio; heldIn } }
                }
            }
        }
    }

    // MARK: Lots

    private var openLots: [HoldingLots.Lot] { lots.filter { $0.status == "open" && $0.qtyRemaining > 0 } }

    private var lotsCard: some View {
        Card(padding: 16) { lotsList }
    }

    private var lotsHeader: some View {
        HStack {
            Text("Open lots \u{00B7} \(openLots.count)")
            Spacer()
            Text(layout == .inspector ? accountLabel : "Cost and gain").font(.footnote).foregroundStyle(Theme.secondary)
        }
    }

    @ViewBuilder
    private var lotsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            lotsHeader.font(.headline).foregroundStyle(Theme.text)
            lotRows
        }
    }

    @ViewBuilder
    private var lotRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            if lotsFailed {
                InlineError(message: "Couldn't load lots") { Task { await load() } }
            } else if openLots.isEmpty {
                Text("No open lots.").font(.subheadline).foregroundStyle(Theme.secondary)
            }
            ForEach(Array(openLots.enumerated()), id: \.element.id) { index, lot in
                if index > 0 { Divider() }
                lotRow(lot)
            }
        }
    }

    private var accountLabel: String { Set(positions.compactMap(\.accountName)).sorted().joined(separator: ", ") }

    private func lotRow(_ lot: HoldingLots.Lot) -> some View {
        let opened = APIDate.parse(lot.openDate)
        let shortTerm = opened.map { (Calendar(identifier: .gregorian).dateComponents([.day], from: $0, to: Fixtures.today)
            .day ?? 0) < 365 } ?? false
        let gain = price.flatMap { price in
            lot.costPerShare > 0 && lot.currency == currency ? (price - lot.costPerShare) / lot.costPerShare * 100 : nil
        }
        let shares = lot.qtyRemaining.formatted(.number.precision(.fractionLength(0...4)))
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(opened?.formatted(date: .abbreviated, time: .omitted) ?? lot.openDate).font(.subheadline.weight(.semibold))
                Text("\(shares) shares at \(lot.costPerShare.money(lot.currency))" + (shortTerm ? " \u{00B7} Short term" : ""))
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text((lot.qtyRemaining * lot.costPerShare).money(lot.currency)).font(.subheadline.weight(.semibold))
                if let gain { Text(gain.signedPercent).font(.footnote.weight(.semibold)).foregroundStyle(gain.gainColor) }
            }
            .monospacedDigit()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

extension HoldingPane {
    // MARK: Activity

    @ViewBuilder
    private var activityList: some View {
        if activityFailed {
            InlineError(message: "Couldn't load recent activity") { Task { await load() } }
        } else if !activity.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent \(holding.symbol ?? holding.name) activity").font(.headline).foregroundStyle(Theme.text)
                ForEach(Array(activity.enumerated()), id: \.element.id) { index, transaction in
                    if index > 0 { Divider() }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activityTitle(transaction)).font(.subheadline.weight(.semibold))
                            Text([transaction.day.monthDay, transaction.account].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                                .font(.footnote).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Text(MoneyText.format(transaction.amount, currency: transaction.currency, signed: true))
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(transaction.amount > 0 ? Theme.positive : Theme.text)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func activityTitle(_ transaction: Transaction) -> String {
        guard let quantity = transaction.quantity, quantity != 0 else { return transaction.categoryName ?? transaction.title }
        let shares = abs(quantity).formatted(.number.precision(.fractionLength(0...4)))
        return "\(quantity > 0 ? "Buy" : "Sell") \(shares) shares"
    }

    // MARK: Loading

    private func load() async {
        let api = session.api
        var loaded: [HoldingLots.Lot] = []
        var failed = false
        for position in positions where !position.isCash {
            do {
                loaded += try await api.holdingLots(holdingId: position.id).lots
            } catch is CancellationError {
                return
            } catch {
                WealthView.log.error("lots failed for \(position.id): \(String(describing: error), privacy: .public)")
                failed = true
            }
        }
        lots = loaded.sorted { $0.openDate < $1.openDate }
        lotsFailed = failed
        let ids = Set(positions.map(\.id))
        guard let first = positions.first else { return }
        do {
            let page = try await api.transactions(TransactionQuery(limit: 20, portfolioHoldingId: first.id))
            activity = Array(page.data.filter { ($0.portfolioHoldingId).map(ids.contains) ?? false }.prefix(3))
            activityFailed = false
        } catch is CancellationError {
        } catch {
            WealthView.log.error("holding activity failed: \(String(describing: error), privacy: .public)")
            activityFailed = true
        }
    }

    private func loadChart() async {
        guard layout == .page else { return }
        do {
            let performance = try await session.api.holdingPerformance(period: period)
            let ids = Set(positions.map(\.id))
            let series = performance.points.compactMap { point -> ValuePoint? in
                let members = point.members.filter { ($0.id.map(ids.contains) ?? false) || $0.name == holding.symbol }
                return members.isEmpty ? nil : ValuePoint(day: point.day, value: members.reduce(0) { $0 + $1.value })
            }
            points = WealthModel.trim(series, period: period, today: Fixtures.today) { $0.day }
            chartFailed = false
        } catch is CancellationError {
        } catch {
            WealthView.log.error("holding chart failed: \(String(describing: error), privacy: .public)")
            points = []
            chartFailed = true
        }
    }
}
