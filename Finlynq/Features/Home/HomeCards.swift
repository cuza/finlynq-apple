import Charts
import SwiftUI

/// Which design a Home card follows: Home (iPhone), iPadHome or MacHome.
enum HomeLayout {
    case phone, pad, mac

    /// The design for a column: the iPhone's on `.compact`, the iPad's on `.medium`, and on `.wide` the Mac's on the
    /// Mac when it fits (`macNeeds`), else the iPad's. A narrow Mac window gets the iPad and iPhone designs, as an iPad
    /// column does.
    init(_ width: LayoutWidth, column: CGFloat?, macNeeds: CGFloat) {
        #if os(macOS)
        if LayoutWidth.fitsMacDesign(width, column: column, needs: macNeeds) { self = .mac; return }
        #endif
        self = width == .compact ? .phone : .pad
    }

    var titleFont: Font {
        switch self {
        case .phone: .subheadline.weight(.bold)
        case .pad: .headline.weight(.bold)
        case .mac: .title3.weight(.bold)
        }
    }
    var rowTitle: Font { self == .mac ? .body.weight(.semibold) : .subheadline.weight(.semibold) }
    var rowDetail: Font { self == .mac ? .callout : .footnote }
    var tileSize: CGFloat {
        switch self {
        case .phone: 32
        case .pad: 36
        case .mac: 28
        }
    }
    var rowPadding: CGFloat {
        switch self {
        case .phone: 11
        case .pad: 9
        case .mac: 7
        }
    }
}

/// Card title with an optional detail or "See all" link on the right.
struct HomeCardHeader: View {
    let title: String
    var detail: String?
    var link: (title: String, route: AppRoute)?
    let layout: HomeLayout

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(layout.titleFont).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
            Spacer()
            if let detail {
                Text(detail).font(layout.rowDetail).foregroundStyle(Theme.secondary).monospacedDigit()
            }
            if let link {
                NavigationLink(link.title, value: link.route)
                    .buttonStyle(.plain).font(layout == .mac ? .body.weight(.medium) : .subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

/// Rows with a hairline between them.
struct DividedRows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider() }
                row(item)
            }
        }
    }
}

/// A money amount with its cents greyed, as in the net worth headline.
struct HeadlineMoney: View {
    let amount: Double
    let currency: String?
    let size: CGFloat

    var body: some View {
        let text = MoneyText.format(amount, currency: currency)
        let separator = Locale.current.decimalSeparator ?? "."
        let split = text.range(of: separator, options: .backwards)?.lowerBound ?? text.endIndex
        Text("\(Text(text[..<split]))\(Text(text[split...]).foregroundStyle(Theme.secondary.opacity(0.75)))")
            .font(.system(size: size, weight: .bold)).monospacedDigit().foregroundStyle(Theme.text)
            .minimumScaleFactor(0.6).lineLimit(1)
    }
}

/// Small rounded pill for a change, green when up and red when down.
struct ChangePill: View {
    let text: String
    let isUp: Bool

    var body: some View {
        Text(text).font(.footnote.weight(.semibold)).monospacedDigit()
            .foregroundStyle(isUp ? Theme.positive : Theme.negative)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(isUp ? Theme.positiveTint : Theme.negativeTint, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: Net worth

struct NetWorthCard: View {
    let layout: HomeLayout
    /// iPad portrait and iPhone Duo (iPadPHome, DuoInnerHome): the figures above the chart, or beside it when there is room.
    var portrait = false
    let data: HomeView.HomeData
    @Binding var period: String
    let currency: String?
    /// Requests the history again after it failed.
    let retry: () -> Void

    var body: some View {
        switch layout {
        case .phone: NavigationLink(value: AppRoute.netWorth) { phone }.buttonStyle(.plain)
        case .pad: if portrait { portraitCard } else { pad }
        case .mac: mac
        }
    }

    private var phone: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Net worth").font(.footnote.weight(.medium)).foregroundStyle(Theme.secondary)
                    Spacer()
                    if let change = HomeModel.monthChange(data.history, today: data.today) {
                        let text = HomeModel.signedChange(change, percent: nil, currency: currency) + " this month"
                        ChangePill(text: text, isUp: change >= 0)
                    }
                }
                HeadlineMoney(amount: data.dashboard.netWorth, currency: currency, size: 36)
                chart(height: 70)
            }
        }
    }

    private var periodChange: (text: String, isUp: Bool)? {
        HomeModel.change(data.history).map {
            let text = HomeModel.signedChange($0.amount, percent: $0.percent, currency: currency)
            return (text + " " + HomeModel.periodLabel(period), $0.amount >= 0)
        }
    }

    private var pad: some View {
        let split = HomeModel.split(data.dashboard.balances)
        return Card(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text("Net worth").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                            if let periodChange { ChangePill(text: periodChange.text, isUp: periodChange.isUp) }
                        }
                        HeadlineMoney(amount: data.dashboard.netWorth, currency: currency, size: 42)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    figure("Assets", split.assets)
                    figure("Debts", abs(split.debts))
                    PeriodPicker(period: $period).frame(width: 220)
                }
                chart(height: 110)
            }
        }
    }

    private var portraitCard: some View {
        let split = HomeModel.split(data.dashboard.balances)
        let headline = VStack(alignment: .leading, spacing: 6) {
            Text("Net worth").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
            HeadlineMoney(amount: data.dashboard.netWorth, currency: currency, size: 42)
            if let periodChange { ChangePill(text: periodChange.text, isUp: periodChange.isUp) }
        }
        return Card(padding: 20) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        headline
                        tile("Assets", split.assets)
                        tile("Debts", abs(split.debts))
                    }
                    .frame(width: 210)
                    VStack(spacing: 12) {
                        PeriodPicker(period: $period)
                        chart(height: 140)
                    }
                }
                .wideEnough(560)
                VStack(alignment: .leading, spacing: 12) {
                    headline
                    HStack(spacing: 10) {
                        tile("Assets", split.assets)
                        tile("Debts", abs(split.debts))
                    }
                    PeriodPicker(period: $period)
                    chart(height: 130)
                }
            }
        }
    }

    /// A figure on grey, as in the portrait boards' Assets and Debts.
    private func tile(_ label: String, _ amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote).foregroundStyle(Theme.secondary)
            Text(amount.wholeMoney(currency)).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func figure(_ label: String, _ amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.footnote).foregroundStyle(Theme.secondary)
            Text(amount.wholeMoney(currency)).font(.headline.weight(.bold)).monospacedDigit().foregroundStyle(Theme.text)
        }
        .padding(.top, 2)
    }

    private var mac: some View {
        let split = HomeModel.split(data.dashboard.balances)
        var parts: [String] = []
        if let first = data.history.first, let last = data.history.last {
            let format = Date.FormatStyle.dateTime.month(.abbreviated).year()
            parts.append("\(first.day.formatted(format)) to \(last.day.formatted(format))")
        }
        parts.append("assets \(split.assets.wholeMoney(currency))")
        parts.append("debts \(abs(split.debts).wholeMoney(currency))")
        return Card(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HomeCardHeader(title: "Net worth", detail: parts.joined(separator: " \u{00B7} "), layout: .mac)
                chart(height: 260)
            }
        }
    }

    @ViewBuilder
    private func chart(height: CGFloat) -> some View {
        let points = data.history
        if data.historyFailed {
            HStack(spacing: 8) {
                Text("Couldn't load history").foregroundStyle(Theme.secondary)
                Button("Retry", action: retry).buttonStyle(.borderless).foregroundStyle(Theme.accent)
            }
            .font(layout.rowDetail)
            .frame(maxWidth: .infinity, minHeight: min(height, 70))
        } else if points.count > 1 {
            // The phone card is a link to the Net worth page, which has the interactive chart.
            TimeSeriesChart(
                points: points.map { ValuePoint(day: $0.day, value: $0.value) }, height: height,
                xAxis: layout == .phone ? .hidden : .automatic(6),
                yAxis: layout == .phone ? .hidden : layout == .mac ? .leading(3) : .trailing(4),
                currency: currency, smooth: true, fillOpacity: 0.08,
                resting: layout == .phone ? .none : layout == .mac ? .tooltip : .dot, interactive: layout != .phone
            )
            .accessibilityLabel("Net worth over time")
        }
    }
}

/// A segmented period control. 1M 6M 1Y All by default, for the net worth chart in the iPad card and the Mac toolbar.
struct PeriodPicker: View {
    @Binding var period: String
    var options = [("1m", "1M"), ("6m", "6M"), ("1y", "1Y"), ("all", "All")]

    var body: some View {
        Picker("Period", selection: $period) {
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
        }
        .pickerStyle(.segmented).labelsHidden()
    }
}

// MARK: Mac KPI row

#if os(macOS)
struct KPIRow: View {
    let data: HomeView.HomeData
    let period: String
    let currency: String?

    var body: some View {
        let summary = data.budget?.summary
        let planned = summary?.plannedSpending ?? 0
        let spent = summary?.spent ?? 0
        let income = summary?.receivedIncome ?? 0
        let left = planned - spent
        let perDay = HomeModel.perDay(left: left, today: data.today)
        let investments = data.dashboard.balances.filter { $0.isInvestment && !$0.archived }
        let invested = investments.reduce(0) { $0 + $1.convertedBalance }
        let change = HomeModel.change(data.history)
        let today = HomeModel.investedToday(data.history, investmentIds: Set(investments.map(\.accountId)))
        HStack(spacing: 16) {
            tile(
                "Net worth", MoneyText.format(data.dashboard.netWorth, currency: currency),
                change.map {
                    (HomeModel.signedChange($0.amount, percent: $0.percent, currency: currency) + " " + HomeModel.periodLabel(period),
                     sign($0.amount))
                },
                route: .netWorth
            )
            tile(
                "Left to spend this month", planned > 0 ? left.wholeMoney(currency) : "No budget",
                planned > 0 && left > 0
                    ? ("\(perDay.amount.wholeMoney(currency))/day for \(perDay.days) \(perDay.days == 1 ? "day" : "days")", nil) : nil,
                route: .budget
            )
            tile(
                "Income this month", income.wholeMoney(currency),
                ("\(spent.wholeMoney(currency)) spent \u{00B7} net "
                    + HomeModel.signedChange(income - spent, percent: nil, currency: currency), nil),
                route: .statement
            )
            tile(
                "Invested", invested.wholeMoney(currency),
                investments.isEmpty
                    ? ("No investment accounts", nil)
                    : today.map {
                        (HomeModel.signedChange($0.amount, percent: $0.percent, currency: currency) + " today", sign($0.amount))
                    },
                route: .investments
            )
        }
    }

    private func sign(_ amount: Double) -> Color { amount >= 0 ? Theme.positive : Theme.negative }

    /// A KPI card. A colored detail line is a change and is semibold; a nil color is plain secondary text.
    private func tile(_ label: String, _ value: String, _ detail: (String, Color?)?, route: AppRoute) -> some View {
        NavigationLink(value: route) {
            Card(padding: 17) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(label).font(.body.weight(.medium)).foregroundStyle(Theme.secondary)
                    Text(value).font(.system(size: 26, weight: .bold)).monospacedDigit().foregroundStyle(Theme.text)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(detail?.0 ?? " ").font(detail?.1 == nil ? .body : .body.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(detail?.1 ?? Theme.secondary).lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
#endif
