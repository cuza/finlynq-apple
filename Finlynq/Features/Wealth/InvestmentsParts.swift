import SwiftUI

/// TWRR as a green pill and MWRR as grey text, top right of the market value card.
/// In a row after today's change, MWRR is a grey pill (iPadPInvestments.dc.html).
struct ReturnBadges: View {
    let performance: PortfolioPerformance?
    var inRow = false

    var body: some View {
        let layout = inRow ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(alignment: .trailing, spacing: 6))
        layout {
            if let twrr = performance?.twrr?.period {
                Chip(text: "TWRR " + (twrr * 100).signedPercent, tint: Theme.positive, background: Theme.positiveTint)
                    .help("Time-weighted return for the period")
            }
            if let mwrr = performance?.mwrr, mwrr.converged == true, let irr = mwrr.irr {
                if inRow {
                    Chip(text: "MWRR " + (irr * 100).signedPercent, tint: Theme.secondary, background: Theme.fill)
                        .help("Money-weighted return (XIRR)")
                } else {
                    Text("MWRR " + (irr * 100).signedPercent).font(.footnote.weight(.medium)).monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                        .help("Money-weighted return (XIRR)")
                }
            }
        }
    }
}

/// "— Value  - - - Cost basis $154,000" under or beside the performance chart, in the display currency.
struct PerformanceLegend: View {
    let summary: PortfolioOverview.Summary
    let currency: String
    var showsCost = true
    /// The Mac legend also shows the market value.
    var showsValue = false

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Capsule().fill(Theme.invest).frame(width: 16, height: 3)
                Text(showsValue ? "Value " + summary.totalValueDisplay.wholeMoney(currency) : "Value")
            }
            if showsCost {
                HStack(spacing: 6) {
                    Text("- - -").font(.caption2.weight(.bold)).foregroundStyle(Theme.secondary.opacity(0.7))
                    Text("Cost basis " + summary.totalCostBasisDisplay.wholeMoney(currency))
                }
            }
        }
        .font(.subheadline).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
    }
}

/// Unrealized gain, realized, dividends and total return: a 2 by 2 grid on iPhone, one row on iPad.
struct ReturnsCard: View {
    let summary: PortfolioOverview.Summary
    let currency: String
    let layout: HomeLayout

    private struct Item {
        let label: String
        let amount: Double
        let detail: String
        var signed = true
    }

    var body: some View {
        let cost = summary.totalCostBasisDisplay
        let items = [
            Item(label: "Unrealized gain", amount: summary.totalUnrealizedGainDisplay,
                 detail: cost > 0 ? "\(summary.totalUnrealizedGainPct.signedPercent) on cost" : " "),
            Item(label: "Realized", amount: summary.totalRealizedGainDisplay, detail: "From sales"),
            Item(label: "Dividends", amount: summary.totalDividendsDisplay, detail: "All time", signed: false),
            Item(label: "Total return", amount: summary.totalReturnDisplay,
                detail: cost > 0 ? "\(summary.totalReturnPct.signedPercent) on cost" : " ")
        ]
        Card(padding: 16) {
            if layout == .phone {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow { figure(items[0]); figure(items[1]) }
                    GridRow { figure(items[2]); figure(items[3]) }
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Divider() }
                        figure(item)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Returns, all time")
    }

    private func figure(_ item: Item) -> Figure {
        Figure(
            label: item.label, value: item.signed ? item.amount.signedWhole(currency) : item.amount.wholeMoney(currency),
            color: item.signed ? item.amount.gainColor : Theme.text, detail: item.detail, size: layout == .phone ? 20 : 17
        )
    }
}

/// The holdings card on iPhone and iPad: Holding, Value, Day and Gain columns (iPad adds Shares, Price and Of
/// portfolio). Columns are as wide as their widest value; when they don't fit, Shares, then Price, then Of portfolio
/// are left out. iPhone rows push the holding; iPad rows select it for the pane beside the list.
/// With `asRows` the card is a list (iPadPInvestments.dc.html, DuoInnerInvestments.dc.html): each row has an icon, the
/// shares, price and share of the portfolio under the name, and the value over today's and the total gain.
struct HoldingsList: View {
    let overview: PortfolioOverview
    let layout: HomeLayout
    @Binding var groupByAccount: Bool
    @Binding var selected: String?
    var asRows = false
    /// Rows push the holding instead of selecting it for the pane beside the list.
    var pushes: Bool?
    @State private var width: Double = 0
    /// Read so the columns are measured again when the text size changes.
    @Environment(\.dynamicTypeSize) private var typeSize

    enum Column: String, CaseIterable {
        case shares = "Shares", price = "Price", value = "Value", day = "Day", gain = "Gain", share = "Of portfolio"
    }

    private struct Row: Identifiable {
        let id: String
        let type: String
        /// Pushed on iPhone.
        let symbol: String
        /// Selected on iPad; nil for grouped positions, which push instead.
        let key: String?
        let title: String
        let subtitle: String
        let shares: String
        let price: String
        let value: String
        /// The value with cents, for the list rows (iPadPInvestments.dc.html).
        let exactValue: String
        let day: Double?
        let gain: Double?
        let gainPct: Double?
        let share: String
        /// The account heading this row starts, when grouped.
        var section: String?
    }

    private var currency: String { overview.displayCurrency }

    var body: some View {
        let rows = groupByAccount ? groupedRows : pooledRows
        if asRows {
            listCard(rows)
        } else {
            table(rows)
        }
    }

    private func table(_ rows: [Row]) -> some View {
        let visible = columns(rows, typeSize)
        return Card(padding: 0) {
            VStack(spacing: 0) {
                if layout == .pad { summary }
                header(visible)
                ForEach(rows) { row in
                    if let section = row.section {
                        Text(section).font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 10)
                    }
                    Divider().padding(.leading, 16)
                    link(row) { line(row, visible, selected: !pushesRows && row.key != nil && selectedKey == row.key) }
                }
            }
            .padding(.bottom, 6)
        }
        .onGeometryChange(for: Double.self) { $0.size.width } action: { width = $0 }
    }

    private var selectedKey: String? { selected ?? overview.byHolding.first?.key }

    private var pushesRows: Bool { pushes ?? (layout == .phone) }

    private var pooledRows: [Row] {
        overview.byHolding.map { holding in
            Row(
                id: holding.key, type: holding.assetType, symbol: holding.symbol ?? holding.name, key: holding.key,
                title: holding.symbol ?? holding.name,
                subtitle: Self.subtitle(holding), shares: holding.totalQty.formatted(.number.precision(.fractionLength(0...4))),
                price: holding.currentPriceDisplay.map { $0.money(currency) } ?? "", value: holding.marketValueDisplay.wholeMoney(currency),
                exactValue: holding.marketValueDisplay.money(currency),
                day: holding.dayChangePct, gain: holding.unrealizedGainDisplay, gainPct: holding.unrealizedGainPct,
                share: (holding.pctOfPortfolio ?? 0).formatted(.number.precision(.fractionLength(1))) + "%"
            )
        }
    }

    private var groupedRows: [Row] {
        let positions = Dictionary(grouping: overview.holdings ?? [], by: { $0.accountName ?? "Other" })
        return positions.keys.sorted().flatMap { account in
            (positions[account] ?? []).enumerated().map { index, position in
                Row(
                    id: "\(account)|\(position.id)", type: position.assetType ?? "stock", symbol: position.symbol ?? position.label,
                    key: nil, title: position.label,
                    subtitle: position.name ?? position.assetType?.capitalized ?? "",
                    shares: position.quantity.map { $0.formatted(.number.precision(.fractionLength(0...4))) } ?? "",
                    price: "", value: (position.marketValueDisplay ?? 0).wholeMoney(currency),
                    exactValue: (position.marketValueDisplay ?? 0).money(currency), day: position.changePct, gain: nil,
                    gainPct: position.unrealizedGainPct, share: "", section: index == 0 ? account : nil
                )
            }
        }
    }

    private func text(_ column: Column, _ row: Row) -> String {
        switch column {
        case .shares: row.shares
        case .price: row.price
        case .value: row.value
        case .day: row.day.map(\.signedPercent) ?? "0.0%"
        case .gain:
            layout == .pad
                ? row.gain.map { $0.signedWhole(currency) } ?? row.gainPct.map(\.signedPercent) ?? ""
                : row.gainPct.map(\.signedPercent) ?? "0.0%"
        case .share: row.share
        }
    }

    /// The columns to show, each with the width of its widest value or title.
    private func columns(_ rows: [Row], _: DynamicTypeSize) -> [(column: Column, width: CGFloat)] {
        let all: [Column] = layout == .pad ? Column.allCases : [.value, .day, .gain]
        var widths: [Column: CGFloat] = [:]
        for column in all {
            var widest = TextWidth.of(column.rawValue, style: .footnote, bold: true)
            for row in rows { widest = max(widest, TextWidth.of(text(column, row), style: .subheadline, bold: column == .value)) }
            widths[column] = widest + 2
        }
        let pairs = all.map { ($0, Double(widths[$0] ?? 0)) }
        // Row padding: 16 on each side of the card's content.
        let kept = width > 0
            ? WealthModel.fitColumns(pairs, dropOrder: [.shares, .price, .share], available: width - 32, flexible: 90, spacing: 8)
            : all
        return kept.map { ($0, widths[$0] ?? 0) }
    }

    /// iPad: the title, Group by account and the allocation bar sit inside the card (iPadInvestments.dc.html). In the
    /// list the bar gets its own line and the legend goes under it.
    private var summary: some View {
        let slices = WealthModel.allocation(overview.byType)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Holdings \u{00B7} \(overview.byHolding.count)").font(.headline)
                Spacer()
                Toggle("Group by account", isOn: $groupByAccount).font(.subheadline).fixedSize()
            }
            let bar = AllocationBar(segments: slices.map { ($0.share, WealthColors.forType($0.id)) }, height: 8)
            let legend = ForEach(slices) { slice in
                LegendItem(color: WealthColors.forType(slice.id), name: slice.name, value: "\(Int((slice.share * 100).rounded()))%")
                    .fixedSize()
            }
            Group {
                if asRows {
                    bar
                    HStack(spacing: 12) { legend }
                } else {
                    HStack(spacing: 12) { bar; legend }
                }
            }
            .font(.footnote)
        }
        .padding(.horizontal, 18).padding(.top, 16)
    }

    private func listCard(_ rows: [Row]) -> some View {
        let gains = showsGain(rows, typeSize)
        return Card(padding: 0) {
            VStack(spacing: 0) {
                summary
                Group {
                    if gains {
                        listHeader("Holding \u{00B7} shares \u{00B7} of portfolio", "Value \u{00B7} today \u{00B7} gain")
                    } else {
                        listHeader("Holding", "Value \u{00B7} today")
                    }
                }
                .font(.footnote).foregroundStyle(Theme.secondary).lineLimit(1)
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 6)
                ForEach(rows) { row in
                    if let section = row.section {
                        Text(section).font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.top, 10)
                    }
                    Divider().padding(.leading, 18)
                    link(row) { listRow(row, gain: gains, selected: !pushesRows && row.key != nil && selectedKey == row.key) }
                }
            }
            .padding(.bottom, 6)
        }
        .onGeometryChange(for: Double.self) { $0.size.width } action: { width = $0 }
    }

    /// The row's second figure: "+2.8% · +$3,298 (54.9%)" with the total gain, or just today's change.
    private func trailing(_ row: Row, gain: Bool) -> Text {
        let day = Text(row.day.map(\.signedPercent) ?? "0.0%").foregroundStyle((row.day ?? 0).gainColor)
        guard gain, let total = row.gain else { return day }
        let percent = row.gainPct.map { " (" + abs($0).formatted(.number.precision(.fractionLength(1))) + "%)" } ?? ""
        return Text("\(day) \u{00B7} \(Text(total.signedWhole(currency) + percent).foregroundStyle(total.gainColor))")
    }

    private func trailingText(_ row: Row) -> String {
        let day = row.day.map(\.signedPercent) ?? "0.0%"
        guard let total = row.gain else { return day }
        let percent = row.gainPct.map { " (" + abs($0).formatted(.number.precision(.fractionLength(1))) + "%)" } ?? ""
        return "\(day) \u{00B7} \(total.signedWhole(currency))\(percent)"
    }

    /// Whether every row has room for the total gain beside a name column of at least `nameMinimum`. A narrow pane
    /// (the Duo's open display) shows value and today only (DuoInnerInvestments.dc.html). Until the card has measured
    /// itself, the layout decides: a list that pushes has the whole column (iPad portrait), a list beside the pane
    /// doesn't, so the narrow pane doesn't flash the gain column.
    private func showsGain(_ rows: [Row], _: DynamicTypeSize) -> Bool {
        guard width > 0 else { return pushesRows }
        let trailing = rows.map {
            max(TextWidth.of(trailingText($0), style: .footnote, bold: true), TextWidth.of($0.exactValue, style: .body, bold: true))
        }.max() ?? 0
        // Row insets 36, icon 36, two gaps of 12.
        return width - 36 - 36 - 24 - trailing >= Self.nameMinimum
    }

    static let nameMinimum: CGFloat = 140

    private func listHeader(_ leading: String, _ trailing: String) -> some View {
        HStack(spacing: 12) {
            Text(leading)
            Spacer(minLength: 8)
            Text(trailing)
        }
    }

    private func listRow(_ row: Row, gain: Bool, selected: Bool) -> some View {
        let icon = WealthColors.symbol(forType: row.type)
        // "25 shares at $372.06 · 41.6%", "0.0215 at $92,170 · 8.9%" for crypto, "$342.99 · 1.5%" for cash.
        let quantity = row.type == "crypto" || row.shares.isEmpty ? row.shares : "\(row.shares) shares"
        let held = row.type == "cash" ? row.exactValue : row.price.isEmpty ? quantity : "\(quantity) at \(row.price)"
        let detail = [held, row.share].filter { !$0.isEmpty }
        return HStack(spacing: 12) {
            IconTile(symbol: icon.symbol, tint: icon.tint, background: icon.tint.opacity(0.14), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Text(row.title).font(.body.weight(.semibold)).foregroundStyle(Theme.text)) \(Text(row.subtitle).font(.footnote))")
                    .foregroundStyle(Theme.secondary).lineLimit(1)
                Text(detail.joined(separator: " \u{00B7} ")).font(.footnote).foregroundStyle(Theme.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.exactValue).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                trailing(row, gain: gain).font(.footnote.weight(.semibold))
            }
            .monospacedDigit().lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(selected ? Theme.accentTint : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func header(_ visible: [(column: Column, width: CGFloat)]) -> some View {
        HStack(spacing: 8) {
            Text("Holding").frame(maxWidth: .infinity, alignment: .leading)
            ForEach(visible, id: \.column) { Text($0.column.rawValue).frame(width: $0.width, alignment: .trailing) }
        }
        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary).lineLimit(1)
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
    }

    @ViewBuilder
    private func link(_ row: Row, @ViewBuilder label: () -> some View) -> some View {
        if pushesRows || row.key == nil {
            NavigationLink(value: AppRoute.holding(row.symbol)) { label() }.buttonStyle(.plain)
        } else {
            Button { selected = row.key } label: { label() }.buttonStyle(.plain)
        }
    }

    private func line(_ row: Row, _ visible: [(column: Column, width: CGFloat)], selected: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                Text(row.subtitle).font(.footnote).foregroundStyle(Theme.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(visible, id: \.column) { item in cell(item.column, row).frame(width: item.width, alignment: .trailing) }
        }
        .font(.subheadline).monospacedDigit().lineLimit(1)
        .padding(.horizontal, 10).padding(.vertical, 10)
        .background(selected ? Theme.accentTint : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func cell(_ column: Column, _ row: Row) -> some View {
        switch column {
        case .value: Text(text(column, row)).fontWeight(.semibold)
        case .day: Text(text(column, row)).foregroundStyle((row.day ?? 0).gainColor)
        case .gain:
            if layout == .pad, let gain = row.gain {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(text(column, row)).foregroundStyle(gain.gainColor)
                    Text(row.gainPct.map(\.signedPercent) ?? "").font(.footnote).foregroundStyle(Theme.secondary)
                }
            } else {
                Text(text(column, row)).foregroundStyle((row.gainPct ?? 0).gainColor)
            }
        default: Text(text(column, row))
        }
    }

    /// The security's long name, or its asset type when the server has no name for it.
    static func subtitle(_ holding: PortfolioOverview.Holding) -> String {
        if let description = holding.description, !description.isEmpty, description != holding.symbol { return description }
        if holding.name != holding.symbol { return holding.name }
        let types = ["etf": "ETF", "stock": "Stock", "crypto": "Crypto", "cash": "Cash", "metal": "Metal"]
        return types[holding.assetType] ?? holding.assetType
    }
}

#if os(macOS)
/// Market value, today, unrealized gain and total return tiles across the top of the Mac Investments page.
struct InvestmentKPIs: View {
    let overview: PortfolioOverview
    let performance: PortfolioPerformance?
    let accountNames: [String]

    var body: some View {
        let summary = overview.summary
        let currency = overview.displayCurrency
        let count = overview.byHolding.filter { $0.assetType != "cash" || $0.marketValueDisplay > 0 }.count
        let accounts = accountNames.count == 1 ? "in \(accountNames[0])" : "in \(accountNames.count) accounts"
        HStack(spacing: 16) {
            tile("Market value", summary.totalValueDisplay.wholeMoney(currency), Theme.text) {
                Text("\(count) holdings \(accounts)").foregroundStyle(Theme.secondary)
            }
            tile("Today", summary.dayChangeDisplay.signedWhole(currency), summary.dayChangeDisplay.gainColor) {
                Text(summary.dayChangePct.signedPercent).foregroundStyle(summary.dayChangeDisplay.gainColor)
            }
            tile("Unrealized gain", summary.totalUnrealizedGainDisplay.signedWhole(currency),
                summary.totalUnrealizedGainDisplay.gainColor) {
                Text("\(summary.totalUnrealizedGainPct.signedPercent) on cost")
                    .foregroundStyle(summary.totalUnrealizedGainDisplay.gainColor)
            }
            tile("Total return", summary.totalReturnDisplay.signedWhole(currency), summary.totalReturnDisplay.gainColor) {
                HStack(spacing: 6) {
                    Text(summary.totalReturnPct.signedPercent).foregroundStyle(summary.totalReturnDisplay.gainColor)
                    if let twrr = performance?.twrr?.period {
                        Chip(text: "TWRR " + (twrr * 100).signedPercent, tint: Theme.invest, background: Theme.investTint)
                    }
                }
                if let mwrr = performance?.mwrr, mwrr.converged == true, let irr = mwrr.irr {
                    Chip(text: "MWRR " + (irr * 100).signedPercent, tint: Theme.invest, background: Theme.investTint)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ label: String, _ value: String, _ color: Color, @ViewBuilder detail: () -> some View) -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.body.weight(.medium)).foregroundStyle(Theme.secondary)
                Text(value).font(.system(size: 24, weight: .bold)).monospacedDigit().foregroundStyle(color).lineLimit(1)
                    .minimumScaleFactor(0.6)
                detail().font(.body.weight(.semibold)).monospacedDigit().lineLimit(1)
            }
        }
        .frame(maxHeight: .infinity)
    }
}
#endif
