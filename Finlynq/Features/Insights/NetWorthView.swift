import SwiftUI

/// Net worth figures from the history's per-account members.
nonisolated enum NetWorthModel {
    /// Assets and debts at one point. `debts` is the amount owed, positive.
    struct Split: Equatable {
        let assets: Double
        let debts: Double
    }

    /// One month's change: what assets gained and how much the debt amount changed (negative when paid down).
    struct Month: Identifiable, Equatable {
        let key: String
        let assets: Double
        let debts: Double
        var net: Double { assets - debts }
        var id: String { key }
    }

    private static let calendar = Calendar(identifier: .gregorian)

    static func split(_ point: NetWorthHistory.Point, liabilities: Set<Int>) -> Split {
        let members = point.members ?? []
        return Split(
            assets: members.filter { !liabilities.contains($0.id) }.reduce(0) { $0 + $1.value },
            debts: -members.filter { liabilities.contains($0.id) }.reduce(0) { $0 + $1.value }
        )
    }

    /// The last `count` months, newest first, each from the previous month's last point to its own last point.
    static func months(_ series: [NetWorthHistory.Point], liabilities: Set<Int>, count: Int) -> [Month] {
        let keys = Array(Set(series.map { String($0.date.prefix(7)) })).sorted().suffix(count)
        return keys.reversed().compactMap { key in
            guard let end = series.last(where: { $0.date.hasPrefix(key) }) else { return nil }
            let start = series.last { String($0.date.prefix(7)) < key } ?? series.first { $0.date.hasPrefix(key) } ?? end
            let first = split(start, liabilities: liabilities)
            let last = split(end, liabilities: liabilities)
            return Month(key: key, assets: last.assets - first.assets, debts: last.debts - first.debts)
        }
    }

    /// Balance per account group at the last point and its change since the first, largest balance first.
    struct Group: Identifiable {
        let name: String
        let accounts: [String]
        let balance: Double
        let change: Double
        let isLiability: Bool
        var id: String { name }
    }

    static func groups(_ series: [NetWorthHistory.Point], accounts: [Account]) -> [Group] {
        guard let first = series.first, let last = series.last else { return [] }
        func value(_ point: NetWorthHistory.Point, _ ids: Set<Int>) -> Double {
            (point.members ?? []).filter { ids.contains($0.id) }.reduce(0) { $0 + $1.value }
        }
        return Dictionary(grouping: accounts.filter { !$0.archived }, by: \.group).map { name, list in
            let ids = Set(list.map(\.id))
            let balance = value(last, ids)
            return Group(name: name, accounts: list.map(\.displayName), balance: balance, change: balance - value(first, ids),
                         isLiability: list.allSatisfy { $0.type == "L" })
        }
        .sorted { $0.isLiability != $1.isLiability ? !$0.isLiability : abs($0.balance) > abs($1.balance) }
    }
}

/// Net worth over time (NetWorth.dc.html; iPad and Mac center the same layout): today's value and its change,
/// the chart, assets and debts, each account group's effect, and the change month by month.
struct NetWorthView: View {
    @Environment(Session.self) private var session
    @Environment(\.layoutWidth) private var width
    @State private var period = "1y"

    private var currency: String { session.currency }
    private var liabilities: Set<Int> { Set(session.accounts.filter { $0.type == "L" }.map(\.id)) }

    var body: some View {
        Reloader(id: "\(period)|\(session.revision)", source: "net worth") {
            try await session.api.netWorthHistory(period: period)
        } content: { history in
            content(history.series)
        }
        .background(Theme.page)
        .onChange(of: width, initial: true) { period = Self.period(period, compact: width == .compact) }
        .navigationTitle("Net worth")
        #if os(iOS)
        .toolbarTitleDisplayMode(.large)
        #endif
    }

    /// "in 1 year" on iPhone (NetWorth.dc.html), "past year" on wider columns (iPadPNetWorth.dc.html).
    private var periodText: String {
        let past = width != .compact
        return switch period {
        case "1m": past ? "past month" : "in 1 month"
        case "6m": past ? "past 6 months" : "in 6 months"
        case "1y": past ? "past year" : "in 1 year"
        default: "all time"
        }
    }

    /// iPhone has no 1M chip, so a 1M period picked on a wider column falls back to 6M.
    static func period(_ period: String, compact: Bool) -> String { compact && period == "1m" ? "6m" : period }

    private func content(_ series: [NetWorthHistory.Point]) -> some View {
        let wide = width != .compact
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if wide {
                    // iPadPNetWorth.dc.html: a segmented period row.
                    PeriodPicker(period: $period)
                } else {
                    HStack(spacing: 8) {
                        ForEach([("6m", "6M"), ("1y", "1Y"), ("all", "All")], id: \.0) { value, title in
                            FilterChip(title: title, active: period == value) { period = value }
                        }
                    }
                }
                if series.isEmpty {
                    EmptyState(title: "No history yet", message: "Net worth history appears after your first balances.",
                               symbol: "chart.xyaxis.line")
                } else {
                    summaryCard(series)
                    groupsSection(series)
                    monthsSection(series)
                }
            }
            .padding(.horizontal, wide ? 28 : 20).padding(.bottom, 24)
            .frame(maxWidth: wide ? 720 : .infinity)
            .frame(maxWidth: .infinity)
        }
    }

    private func summaryCard(_ series: [NetWorthHistory.Point]) -> some View {
        let last = series[series.count - 1]
        let now = NetWorthModel.split(last, liabilities: liabilities)
        let then = NetWorthModel.split(series[0], liabilities: liabilities)
        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                let change = HomeModel.change(series).map { change in
                    ChangePill(text: HomeModel.signedChange(change.amount, percent: change.percent, currency: currency) + " " + periodText,
                               isUp: change.amount >= 0)
                }
                HStack {
                    Text("Today").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                    Spacer()
                    if width == .compact { change }
                }
                HeadlineMoney(amount: last.value, currency: currency, size: 36)
                // Wider columns keep the value on its own line and put the change under it.
                if width != .compact { change }
                Divider()
                TimeSeriesChart(points: series.map { ValuePoint(day: $0.day, value: $0.value) }, height: 150, xAxis: .months(5),
                                yAxis: .leading(4), currency: currency, smooth: true, fillOpacity: 0.08)
                    .accessibilityLabel("Net worth over time")
                Divider()
                HStack(alignment: .top) {
                    figure("Assets", Theme.accent, now.assets.wholeMoney(currency),
                           detail: HomeModel.signedChange(now.assets - then.assets, percent: nil, currency: currency),
                           color: now.assets >= then.assets ? Theme.positive : Theme.negative)
                    let paid = then.debts - now.debts
                    figure("Debts", Theme.spendBar, now.debts.wholeMoney(currency),
                           detail: paid >= 0 ? "\(paid.wholeMoney(currency)) paid down" : "\((-paid).wholeMoney(currency)) more owed",
                           color: paid >= 0 ? Theme.positive : Theme.negative)
                }
            }
        }
    }

    private func figure(_ label: String, _ swatch: Color, _ value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(swatch).frame(width: 8, height: 8); Text(label) }
                .font(.footnote).foregroundStyle(Theme.secondary)
            Text(value).font(.title3.weight(.bold)).foregroundStyle(Theme.text).monospacedDigit()
            Text(detail).font(.footnote.weight(.semibold)).foregroundStyle(color).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(_ title: String, _ detail: String? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let detail { Text(detail) }
        }
        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary).padding(.horizontal, 4).padding(.top, 8)
    }

    /// iPhone heads each card from outside; wider columns put the title inside the card (iPadPNetWorth.dc.html).
    @ViewBuilder
    private func section(_ title: String, _ detail: String? = nil, @ViewBuilder rows: () -> some View) -> some View {
        if width == .compact {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(title, detail)
                Card(padding: 16) { rows() }
            }
        } else {
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title).font(.headline).foregroundStyle(Theme.text)
                        Spacer()
                        if let detail { Text(detail).font(.footnote).foregroundStyle(Theme.secondary) }
                    }
                    rows()
                }
            }
        }
    }

    private func groupsSection(_ series: [NetWorthHistory.Point]) -> some View {
        let groups = NetWorthModel.groups(series, accounts: session.accounts)
        return section("By account group", "Effect on net worth") {
            DividedRows(items: groups) { group in
                HStack(spacing: 14) {
                    let symbol = Icons.account(group: group.name, isLiability: group.isLiability,
                                               isInvestment: group.name.lowercased().contains("invest"))
                    let invest = group.name.lowercased().contains("invest")
                    let tint = group.isLiability ? Theme.spendBar : invest ? Theme.invest : Theme.accent
                    IconTile(symbol: symbol, tint: tint, background: tint.opacity(0.14), size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                        Text(group.accounts.joined(separator: ", ")).font(.subheadline).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(MoneyText.format(group.balance, currency: currency, cents: false))
                            .font(.body.weight(.semibold)).foregroundStyle(Theme.text).monospacedDigit()
                        ChangePill(text: HomeModel.signedChange(group.change, percent: nil, currency: currency),
                                   isUp: group.change >= 0)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func monthsSection(_ series: [NetWorthHistory.Point]) -> some View {
        let months = NetWorthModel.months(series, liabilities: liabilities, count: 6)
        let current = BudgetModel.monthKey(Fixtures.today)
        return section("Month by month") {
            DividedRows(items: months) { month in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        let name = StatementModel.date(ofMonth: month.key).formatted(.dateTime.month(.wide))
                        Text(month.key == current ? "\(name) so far" : name).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                        Text("Assets \(HomeModel.signedChange(month.assets, percent: nil, currency: currency)) \u{00B7} debts "
                            + HomeModel.signedChange(month.debts, percent: nil, currency: currency))
                            .font(.subheadline).foregroundStyle(Theme.secondary).monospacedDigit()
                    }
                    Spacer()
                    Text(HomeModel.signedChange(month.net, percent: nil, currency: currency))
                        .font(.body.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(month.net >= 0 ? Theme.positive : Theme.negative)
                }
                .padding(.vertical, 9)
            }
        }
    }
}

/// iPadInsights.dc.html: net worth today, its change over the year, assets and debts, and the year's chart.
struct NetWorthOverview: View {
    let history: NetWorthHistory?
    let dashboard: Dashboard?
    let currency: String
    /// iPad portrait: the value on its own line, the change and the split under it.
    var stacked = false

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Net worth over time").font(.headline.weight(.bold)).foregroundStyle(Theme.text)
                    Spacer()
                    NavigationLink("Details", value: AppRoute.netWorth).buttonStyle(.plain).font(.body.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
                if let dashboard {
                    let split = HomeModel.split(dashboard.balances)
                    let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                        : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
                    layout {
                        Text(dashboard.netWorth.wholeMoney(currency)).font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.text)
                            .monospacedDigit().fixedSize()
                        if let change = HomeModel.change(history?.series ?? []) {
                            let text = HomeModel.signedChange(change.amount, percent: change.percent, currency: currency)
                            ChangePill(text: text + " in 1 year", isUp: change.amount >= 0)
                        }
                        Text("Assets \(split.assets.wholeMoney(currency)) \u{00B7} Debts \(abs(split.debts).wholeMoney(currency))")
                            .font(.subheadline).foregroundStyle(Theme.secondary).monospacedDigit()
                    }
                }
                if let series = history?.series, series.count > 1 {
                    TimeSeriesChart(points: series.map { ValuePoint(day: $0.day, value: $0.value) }, height: 170, xAxis: .months(5),
                                yAxis: .leading(4), currency: currency, smooth: true, fillOpacity: 0.08)
                    .accessibilityLabel("Net worth over time")
                } else {
                    Text(history == nil ? "Couldn't load net worth history." : "Not enough history yet.")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                }
            }
        }
    }
}
