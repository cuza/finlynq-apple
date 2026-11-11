import Charts
import SwiftUI

/// Insights (Insights.dc.html, iPadInsights.dc.html, iPadPInsights.dc.html; the Mac uses the iPad layout): where the
/// money went in a period against the usual, income and spending by month, net worth (iPad and Mac), and the reports.
struct InsightsView: View {
    enum Period: Hashable { case month, threeMonths, year, custom }

    @Environment(Session.self) private var session
    @Environment(\.layoutWidth) private var width
    @Environment(\.layoutColumn) private var column
    @State private var period = Period.month
    @State private var customStart = Calendar(identifier: .gregorian).date(byAdding: .month, value: -2, to: Fixtures.today)
        ?? Fixtures.today
    @State private var customEnd = Fixtures.today

    struct Data {
        /// The last 12 months, this one included.
        let year: Trends
        /// The custom range, when that period is picked.
        let custom: Trends?
        let netWorth: NetWorthHistory?
        let dashboard: Dashboard?
    }

    struct Spend: Identifiable {
        let id: String
        /// Nil for the "N more" row, which opens the income statement.
        var categoryId: Int?
        let name: String
        let amount: Double
        let change: Double?
        let color: Color
    }

    private static let calendar = Calendar(identifier: .gregorian)
    private static let periods: [(Period, String)] = [(.month, "Month"), (.threeMonths, "3M"), (.year, "Year"), (.custom, "Custom")]
    private var today: Date { Fixtures.today }
    var currency: String { session.currency }

    /// iPad landscape and a wide Mac window: cards side by side and the period in the toolbar. On the Mac the
    /// category table needs about 960pt; a narrower window gets the iPad portrait layout.
    var wide: Bool {
        #if os(macOS)
        LayoutWidth.fitsMacDesign(width, column: column, needs: MacDesignWidth.insights)
        #else
        width == .wide
        #endif
    }

    /// Every width but the iPhone's shows net worth and the axes.
    var roomy: Bool { width != .compact }

    /// The 12 month keys the overview loads, oldest first.
    var lastYear: [String] {
        StatementModel.months(from: Self.calendar.date(byAdding: .month, value: -11, to: today) ?? today, to: today)
    }

    private var loadKey: String {
        let custom = period == .custom ? "\(APIDate.string(customStart))|\(APIDate.string(customEnd))" : ""
        return "\(session.revision)|\(roomy)|\(custom)"
    }

    var body: some View {
        Reloader(id: loadKey, source: "insights") { try await load() } content: { data in
            if wide { regular(data) } else if roomy { medium(data) } else { phone(data) }
        }
        .background(Theme.page)
        .navigationTitle("Insights")
        #if os(iOS)
        .toolbarTitleDisplayMode(.large)
        #endif
        .routeDestinations()
        .toolbar {
            if wide {
                ToolbarItem(placement: .primaryAction) { SegmentBar("Period", options: Self.periods, selection: $period).fixedSize() }
            }
        }
    }

    private func load() async throws -> Data {
        let api = session.api
        let months = lastYear
        let end = Self.calendar.dateInterval(of: .month, for: today).map { APIDate.string($0.end.addingTimeInterval(-1)) } ?? ""
        let start = APIDate.string(customStart), finish = APIDate.string(customEnd)
        let wide = roomy, custom = period == .custom
        async let year = api.trends(from: (months.first ?? "") + "-01", to: end)
        async let customTrends = custom ? optionalLoad("custom trends") { try await api.trends(from: start, to: finish) } : nil
        async let netWorth = wide ? optionalLoad("net worth history") { try await api.netWorthHistory(period: "1y") } : nil
        async let dashboard = wide ? optionalLoad("dashboard") { try await api.dashboard() } : nil
        return try await Data(year: year, custom: customTrends, netWorth: netWorth, dashboard: dashboard)
    }

    // MARK: Figures

    /// The months the period covers, and the trends that hold them.
    private func selection(_ data: Data) -> (months: [String], trends: Trends) {
        let current = BudgetModel.monthKey(today)
        switch period {
        case .month: return ([current], data.year)
        case .threeMonths: return (Array(lastYear.suffix(3)), data.year)
        case .year: return (lastYear.filter { $0.hasPrefix(String(current.prefix(4))) }, data.year)
        case .custom: return (StatementModel.months(from: customStart, to: customEnd), data.custom ?? data.year)
        }
    }

    var periodLabel: String {
        switch period {
        case .month: return "in " + today.formatted(.dateTime.month(.wide))
        case .threeMonths: return "in 3 months"
        case .year: return "in " + today.formatted(.dateTime.year())
        case .custom:
            let day = Date.FormatStyle.dateTime.month(.abbreviated).day()
            return "from \(customStart.formatted(day)) to \(customEnd.formatted(day))"
        }
    }

    /// The share of this month that has passed, today included: 9/30 on November 9.
    private var monthElapsed: Double {
        let days = Double(Self.calendar.range(of: .day, in: .month, for: today)?.count ?? 30)
        return Double(Self.calendar.component(.day, from: today)) / days
    }

    /// The four largest categories, then the rest as one grey row. Month and 3M compare with the months before.
    func spends(_ data: Data) -> (rows: [Spend], total: Double) {
        let (months, trends) = selection(data)
        let earlier = lastYear.filter { $0 < (months.first ?? "") }.suffix(6)
        let lines = trends.expenses.map { line in (line, months.reduce(0) { $0 + (line.periods[$1] ?? 0) }) }
            .filter { $0.1 > 0.005 }
            .sorted { $0.1 > $1.1 }
        let total = lines.reduce(0) { $0 + $1.1 }
        var rows = lines.prefix(4).enumerated().map { index, item in
            let previous = earlier.compactMap { item.0.periods[$0] }
            let change: Double? = switch period {
            // The running month is compared with the same share of a usual month, not a whole one.
            case .month: StatementModel.versusUsual(current: item.1, previous: previous.map { $0 * monthElapsed })
            case .threeMonths: StatementModel.versusUsual(current: item.1 / Double(max(months.count, 1)), previous: previous)
            default: nil
            }
            return Spend(id: item.0.id, categoryId: item.0.categoryId, name: item.0.name, amount: item.1, change: change,
                         color: Theme.categoryPalette[index])
        }
        if lines.count > 4 {
            let rest = lines.dropFirst(4)
            rows.append(Spend(id: "more", name: "\(rest.count) more", amount: rest.reduce(0) { $0 + $1.1 }, change: nil,
                              color: Theme.categoryPalette[4]))
        }
        return (rows, total)
    }

    /// Share of income kept this calendar year.
    func savedThisYear(_ data: Data) -> Double? {
        let year = String(BudgetModel.monthKey(today).prefix(4))
        let months = data.year.timeseries.filter { $0.period.hasPrefix(year) }
        return StatementModel.savingsRate(income: months.reduce(0) { $0 + $1.income }, expenses: months.reduce(0) { $0 + $1.expenses })
    }

    // MARK: Layout

    private func phone(_ data: Data) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                SegmentBar("Period", options: Self.periods, selection: $period)
                if period == .custom { customRange }
                InsightsWhereCard(insights: self, data: data, style: .phone)
                InsightsIncomeCard(insights: self, data: data, months: Array(lastYear.suffix(6)), axis: false)
                Card(padding: 16) {
                    DividedRows(items: InsightsReport.all) { report in
                        NavigationLink(value: report.route) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(report.title).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                                    if let short = report.short { Text(short).font(.subheadline).foregroundStyle(Theme.secondary) }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                            }
                            .padding(.vertical, 12).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 4)
        }
    }

    private var customRange: some View {
        Card(padding: 12) {
            HStack {
                DatePicker("From", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
            }
            .font(.subheadline)
        }
    }

    private func regular(_ data: Data) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                if period == .custom { customRange.frame(maxWidth: 520).frame(maxWidth: .infinity, alignment: .leading) }
                // Equal halves: the chart card would otherwise take the room the table's columns need.
                HStack(alignment: .top, spacing: 16) {
                    InsightsWhereCard(insights: self, data: data, style: .table).frame(maxWidth: .infinity)
                    InsightsIncomeCard(insights: self, data: data, months: lastYear, axis: true).frame(maxWidth: .infinity)
                }
                HStack(alignment: .top, spacing: 16) {
                    NetWorthOverview(history: data.netWorth, dashboard: data.dashboard, currency: currency)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Reports").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary).padding(.leading, 4)
                        ForEach(InsightsReport.all) { report in
                            NavigationLink(value: report.route) { reportCard(report) }.buttonStyle(.plain)
                        }
                    }
                    .frame(width: 290)
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 12)
        }
    }

    /// iPadPInsights.dc.html: one column, the period on its own row, the reports in one card.
    private func medium(_ data: Data) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                SegmentBar("Period", options: Self.periods, selection: $period)
                if period == .custom { customRange }
                InsightsWhereCard(insights: self, data: data, style: .list)
                Card(padding: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reports").font(.headline.weight(.bold)).foregroundStyle(Theme.text)
                        DividedRows(items: InsightsReport.all) { report in
                            NavigationLink(value: report.route) { reportRow(report).padding(.vertical, 10) }.buttonStyle(.plain)
                        }
                    }
                }
                InsightsIncomeCard(insights: self, data: data, months: lastYear, axis: true)
                NetWorthOverview(history: data.netWorth, dashboard: data.dashboard, currency: currency, stacked: true)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
    }

    private func reportRow(_ report: InsightsReport) -> some View {
        HStack(spacing: 14) {
            IconTile(symbol: report.symbol, tint: report.tint, background: report.tint.opacity(0.14), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(report.title).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                Text(report.long).font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
        }
        .contentShape(Rectangle())
    }

    private func reportCard(_ report: InsightsReport) -> some View {
        Card(padding: 16) { reportRow(report) }
    }
}

/// "Where it went": the period's spending by category, with each against its usual.
private struct InsightsWhereCard: View {
    /// iPhone rows, the iPad landscape table, or iPad portrait rows with the share and usual under the name.
    enum Style { case phone, table, list }

    let insights: InsightsView
    let data: InsightsView.Data
    let style: Style
    private var table: Bool { style == .table }

    var body: some View {
        let (rows, total) = insights.spends(data)
        Card(padding: style == .phone ? 16 : 18) {
            VStack(alignment: .leading, spacing: 10) {
                HomeCardHeader(title: "Where it went", detail: "\(total.wholeMoney(insights.currency)) \(insights.periodLabel)",
                               layout: style == .phone ? .phone : .pad)
                if rows.isEmpty {
                    Text("No spending in this period.").font(.subheadline).foregroundStyle(Theme.secondary)
                } else {
                    CategoryBar(segments: rows.map { .init(id: $0.id, label: $0.name, amount: $0.amount, color: $0.color) },
                                total: total, height: 12)
                    if table {
                        HStack {
                            Text("Category").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 20)
                            Text("Share").frame(width: 56, alignment: .trailing)
                            Text("Vs usual").frame(width: 130, alignment: .trailing)
                            Text("Spent").frame(width: 84, alignment: .trailing)
                        }
                        .font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 6)
                        Divider()
                    }
                    DividedRows(items: rows) { row in self.row(row, total: total) }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ row: InsightsView.Spend, total: Double) -> some View {
        let color = row.change.map { abs($0) < 0.05 ? Theme.secondary : $0 > 0 ? Theme.warning : Theme.positive } ?? Theme.secondary
        if style == .list {
            listRow(row, total: total, color: color)
        } else {
            columns(row, total: total, color: color)
        }
    }

    /// "Health & Personal Care / 17% of spending · 140% over usual", the amount on the right.
    /// A row opens its category, and "N more" opens the income statement (iPadPInsights.dc.html).
    private func listRow(_ row: InsightsView.Spend, total: Double, color: Color) -> some View {
        NavigationLink(value: row.categoryId.map(AppRoute.category) ?? AppRoute.statement) {
            HStack(spacing: 10) {
                listLine(row, total: total, color: color)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func listLine(_ row: InsightsView.Spend, total: Double, color: Color) -> some View {
        let share = Text(((total > 0 ? row.amount / total : 0)).formatted(.percent.precision(.fractionLength(0))) + " of spending")
        let usual = row.change.map { Text(" \u{00B7} ") + Text(StatementModel.usualLabel($0)).foregroundStyle(color) } ?? Text("")
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(row.color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(2)
                Text("\(share)\(usual)").font(.subheadline).foregroundStyle(Theme.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.amount.wholeMoney(insights.currency)).font(.body.weight(.bold)).foregroundStyle(Theme.text)
                .monospacedDigit().fixedSize()
        }
        .padding(.vertical, 9)
    }

    private func columns(_ row: InsightsView.Spend, total: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(row.color).frame(width: 10, height: 10)
            Text(row.name).foregroundStyle(Theme.text).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if table {
                Text((row.amount / total).formatted(.percent.precision(.fractionLength(0)))).foregroundStyle(Theme.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
            Text(row.change.map(StatementModel.usualLabel) ?? "").font(table ? .body : .caption.weight(.medium)).foregroundStyle(color)
                .multilineTextAlignment(.trailing).frame(width: table ? 130 : 96, alignment: .trailing)
            Text(row.amount.wholeMoney(insights.currency)).fontWeight(.bold).foregroundStyle(Theme.text)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .font(.body).monospacedDigit()
        .padding(.vertical, table ? 11 : 8)
    }
}

/// "Income and spending": income and spending bars by month. The running month is drawn lighter.
private struct InsightsIncomeCard: View {
    let insights: InsightsView
    let data: InsightsView.Data
    let months: [String]
    /// iPad and Mac: totals, a y axis and a legend.
    let axis: Bool
    @Environment(\.layoutWidth) private var width

    var body: some View {
        let byMonth = Dictionary(data.year.timeseries.map { ($0.period, $0) }) { first, _ in first }
        let saved = insights.savedThisYear(data)
        let current = BudgetModel.monthKey(Fixtures.today)
        let currency = insights.currency
        Card(padding: axis ? 18 : 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Income and spending").font(axis ? .headline.weight(.bold) : .subheadline.weight(.bold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    if axis {
                        Text("Last 12 months").font(.subheadline).foregroundStyle(Theme.secondary)
                    } else if let saved {
                        Text("Saved \(saved.formatted(.percent.precision(.fractionLength(0)))) this year")
                            .font(.footnote.weight(.semibold)).foregroundStyle(saved >= 0 ? Theme.positive : Theme.negative)
                    }
                }
                if axis {
                    let savedChip = saved.map {
                        Chip(text: "Saved \($0.formatted(.percent.precision(.fractionLength(0)))) this year",
                             tint: Theme.positive, background: Theme.positiveTint)
                    }
                    let income = total("Income", months.reduce(0) { $0 + (byMonth[$1]?.income ?? 0) })
                    let spending = total("Spending", months.reduce(0) { $0 + (byMonth[$1]?.expenses ?? 0) })
                    if width == .medium {
                        // iPadPInsights.dc.html: the two totals split the card in half.
                        HStack(alignment: .bottom, spacing: 16) {
                            income.frame(maxWidth: .infinity, alignment: .leading)
                            spending.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        HStack(alignment: .bottom, spacing: 28) { income; spending; Spacer(); savedChip }
                    }
                    // iPadPInsights.dc.html: the chip goes under the totals.
                    if width == .medium { savedChip }
                }
                Chart {
                    ForEach(months, id: \.self) { key in
                        let point = byMonth[key]
                        let opacity = key == current ? 0.45 : 1
                        BarMark(x: .value("Month", key), y: .value("Amount", point?.income ?? 0), width: .ratio(0.8))
                            .foregroundStyle(Theme.positiveBar.opacity(opacity)).position(by: .value("Kind", "Income"))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        BarMark(x: .value("Month", key), y: .value("Amount", point?.expenses ?? 0), width: .ratio(0.8))
                            .foregroundStyle(Theme.spendBar.opacity(opacity)).position(by: .value("Kind", "Spending"))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: months) { value in
                        AxisValueLabel {
                            Text(StatementModel.date(ofMonth: value.as(String.self) ?? "").formatted(.dateTime.month(.abbreviated)))
                        }
                    }
                }
                .chartYAxis {
                    if axis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine().foregroundStyle(Theme.fill)
                            AxisValueLabel { Text((value.as(Double.self) ?? 0).compactMoney(currency)) }
                        }
                    } else {
                        AxisMarks { _ in }
                    }
                }
                .barSelection(labels: months, tops: months.map { max(byMonth[$0]?.income ?? 0, byMonth[$0]?.expenses ?? 0) }) { index in
                    let key = months[index]
                    return [StatementModel.monthTitle(key),
                            "Income \((byMonth[key]?.income ?? 0).wholeMoney(currency))",
                            "Spending \((byMonth[key]?.expenses ?? 0).wholeMoney(currency))"]
                }
                .frame(height: axis ? 200 : 110)
                .accessibilityLabel("Income and spending by month")
                if axis {
                    HStack(spacing: 16) {
                        swatch(Theme.positiveBar, "Income")
                        swatch(Theme.spendBar, "Spending")
                    }
                    .font(.subheadline).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private func total(_ label: String, _ amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline).foregroundStyle(Theme.secondary)
            Text(amount.wholeMoney(insights.currency)).font(.title2.weight(.bold)).foregroundStyle(Theme.text).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9); Text(label) }
    }
}

/// The report links on Insights.
struct InsightsReport: Identifiable {
    let title: String
    let short: String?
    let long: String
    let symbol: String
    let tint: Color
    let route: AppRoute
    var id: String { title }

    static let all = [
        InsightsReport(title: "Income statement", short: nil, long: "Income and expenses by month", symbol: "doc.text",
                       tint: Theme.accent, route: .statement),
        InsightsReport(title: "Net worth over time", short: nil, long: "Assets and debts by month",
                       symbol: "chart.line.uptrend.xyaxis", tint: Theme.positiveBar, route: .netWorth),
        InsightsReport(title: "Tax time", short: "Dividends and realized gains", long: "Dividends and realized gains",
                       symbol: "dollarsign.circle", tint: Theme.spendBar, route: .tax)
    ]
}
