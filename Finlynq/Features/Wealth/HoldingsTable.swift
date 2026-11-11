#if os(macOS)
import SwiftUI

/// The Mac holdings card (MacInvestments.dc.html): up to eleven sortable columns, a total row, the selected row
/// tinted, links to the tax reports and Export CSV. Each column is as wide as its widest value; when the window is too
/// narrow, Avg cost, Realized, Dividends, Shares and Price are left out in that order. Group by account splits the rows
/// under each account's name.
struct HoldingsTable: View {
    let overview: PortfolioOverview
    let groupByAccount: Bool
    @Binding var selected: String?
    @State private var sort = Column.value
    @State private var ascending = false
    @State private var export: CSVFile?
    @State private var width: Double = 0
    /// Sorts by the holding's symbol instead of a column.
    @State private var byName = false
    @Environment(\.dynamicTypeSize) private var typeSize

    enum Column: String, CaseIterable {
        case shares = "Shares", avgCost = "Avg cost", price = "Price", value = "Value", day = "Day"
        case unrealized = "Unrealized", realized = "Realized", dividends = "Dividends", total = "Total return", share = "Of portfolio"
    }

    private var currency: String { overview.displayCurrency }

    private var rows: [PortfolioOverview.Holding] {
        overview.byHolding.sorted { lhs, rhs in
            let names = ((lhs.symbol ?? lhs.name).localizedStandardCompare(rhs.symbol ?? rhs.name)) == .orderedAscending
            let order = byName ? names : key(lhs) < key(rhs) || (key(lhs) == key(rhs) && names)
            return ascending ? order : !order
        }
    }

    private func key(_ row: PortfolioOverview.Holding) -> Double {
        switch sort {
        case .shares: row.totalQty
        case .avgCost: row.avgCostDisplay ?? 0
        case .price: row.currentPriceDisplay ?? 0
        case .value: row.marketValueDisplay
        case .day: row.dayChangePct ?? 0
        case .unrealized: row.unrealizedGainDisplay
        case .realized: row.realizedGainDisplay
        case .dividends: row.dividendsDisplay
        case .total: row.totalReturnPct ?? 0
        case .share: row.pctOfPortfolio ?? 0
        }
    }

    private func text(_ column: Column, _ row: PortfolioOverview.Holding) -> String {
        switch column {
        case .shares: row.assetType == "cash" ? "" : row.totalQty.formatted(.number.precision(.fractionLength(0...4)))
        case .avgCost: row.avgCostDisplay.map { $0.money(currency) } ?? ""
        case .price: row.currentPriceDisplay.map { $0.money(currency) } ?? ""
        case .value: row.marketValueDisplay.wholeMoney(currency)
        case .day: (row.dayChangePct ?? 0).signedPercent
        case .unrealized: row.unrealizedGainDisplay.signedWhole(currency)
        case .realized: row.realizedGainDisplay.signedWhole(currency)
        case .dividends: row.dividendsDisplay.wholeMoney(currency)
        case .total: (row.totalReturnPct ?? 0).signedPercent
        case .share: (row.pctOfPortfolio ?? 0).formatted(.number.precision(.fractionLength(1))) + "%"
        }
    }

    private func color(_ column: Column, _ row: PortfolioOverview.Holding) -> Color {
        switch column {
        case .day: (row.dayChangePct ?? 0).gainColor
        case .unrealized: row.unrealizedGainDisplay.gainColor
        case .realized: row.realizedGainDisplay.gainColor
        case .total: (row.totalReturnPct ?? 0).gainColor
        default: Theme.text
        }
    }

    private func total(_ column: Column) -> (String, Color) {
        let summary = overview.summary
        return switch column {
        case .value: (summary.totalValueDisplay.wholeMoney(currency), Theme.text)
        case .day: (summary.dayChangePct.signedPercent, summary.dayChangePct.gainColor)
        case .unrealized: (summary.totalUnrealizedGainDisplay.signedWhole(currency), summary.totalUnrealizedGainDisplay.gainColor)
        case .realized: (summary.totalRealizedGainDisplay.signedWhole(currency), summary.totalRealizedGainDisplay.gainColor)
        case .dividends: (summary.totalDividendsDisplay.wholeMoney(currency), Theme.text)
        case .total: (summary.totalReturnPct.signedPercent, summary.totalReturnPct.gainColor)
        case .share: ("100%", Theme.text)
        default: ("", Theme.text)
        }
    }

    /// The columns that fit, each as wide as its widest value, total or title.
    private func columns(_: DynamicTypeSize) -> [(column: Column, width: CGFloat)] {
        var widths: [Column: CGFloat] = [:]
        for column in Column.allCases {
            var widest = TextWidth.of(column.rawValue, style: .callout, bold: true) + 10
            widest = max(widest, TextWidth.of(total(column).0, style: .body, bold: true))
            for row in overview.byHolding {
                widest = max(widest, TextWidth.of(text(column, row), style: .body, bold: column == .value))
            }
            widths[column] = widest + 2
        }
        let all = Column.allCases.map { ($0, Double(widths[$0] ?? 0)) }
        // 26pt of padding on each side of a row.
        let kept = width > 0
            ? WealthModel.fitColumns(all, dropOrder: [.avgCost, .realized, .dividends, .shares, .price], available: width - 52,
                                     flexible: 150, spacing: 6)
            : Column.allCases
        return kept.map { ($0, widths[$0] ?? 0) }
    }

    var body: some View {
        let visible = columns(typeSize)
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Text("Holdings \u{00B7} \(overview.byHolding.count)").font(.title3.weight(.bold))
                    Spacer()
                    NavigationLink("Dividends", value: AppRoute.tax).buttonStyle(.plain).foregroundStyle(Theme.accent)
                    NavigationLink("Realized gains", value: AppRoute.tax).buttonStyle(.plain).foregroundStyle(Theme.accent)
                    Button { export = CSVFile(text: WealthModel.holdingsCSV(rows)) } label: {
                        MacPopupLabel(text: "Export CSV", symbol: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                }
                .font(.body.weight(.medium))
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
                header(visible)
                if groupByAccount {
                    let positions = overview.holdings ?? []
                    ForEach(Set(positions.compactMap(\.accountName)).sorted(), id: \.self) { account in
                        Text(account).font(.callout.weight(.semibold)).foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 26).padding(.top, 10).padding(.bottom, 4)
                        let symbols = Set(positions.filter { $0.accountName == account }.compactMap { $0.symbol ?? $0.name })
                        ForEach(rows.filter { symbols.contains($0.symbol ?? $0.name) }) { row($0, visible) }
                    }
                } else {
                    ForEach(rows) { row($0, visible) }
                }
                totalRow(visible)
            }
            .padding(.bottom, 8)
        }
        .onGeometryChange(for: Double.self) { $0.size.width } action: { width = $0 }
        .fileExporter(isPresented: Binding(get: { export != nil }, set: { if !$0 { export = nil } }), document: export,
                      contentType: .commaSeparatedText, defaultFilename: "Finlynq holdings.csv") { _ in export = nil }
        .accessibilityLabel("Holdings, sorted by \(byName ? "holding" : sort.rawValue.lowercased())")
    }

    private func header(_ visible: [(column: Column, width: CGFloat)]) -> some View {
        HStack(spacing: 6) {
            Button {
                if byName { ascending.toggle() } else { byName = true; ascending = true }
            } label: {
                HStack(spacing: 2) {
                    Text("Holding")
                    if byName { Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold)) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fontWeight(byName ? .semibold : .regular)
            .foregroundStyle(byName ? Theme.text : Theme.secondary)
            ForEach(visible, id: \.column) { item in
                Button {
                    if !byName && sort == item.column {
                        ascending.toggle()
                    } else {
                        byName = false
                        sort = item.column
                        ascending = false
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(item.column.rawValue).lineLimit(1)
                        if !byName && sort == item.column {
                            Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
                        }
                    }
                    .frame(width: item.width, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fontWeight(!byName && sort == item.column ? .semibold : .regular)
                .foregroundStyle(!byName && sort == item.column ? Theme.text : Theme.secondary)
            }
        }
        .font(.callout)
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, 26).padding(.bottom, 6)
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 20) }
    }

    private func row(_ holding: PortfolioOverview.Holding, _ visible: [(column: Column, width: CGFloat)]) -> some View {
        let isSelected = selected == holding.key
        return Button { selected = holding.key } label: {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(holding.symbol ?? holding.name).fontWeight(.semibold)
                    if let description = holding.description ?? (holding.name != holding.symbol ? holding.name : nil) {
                        Text(description).foregroundStyle(Theme.text.opacity(0.85))
                    }
                }
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(visible, id: \.column) { item in
                    Text(text(item.column, holding))
                        .fontWeight(item.column == .value || item.column == .total ? .semibold : .regular)
                        .foregroundStyle(color(item.column, holding)).lineLimit(1)
                        .frame(width: item.width, alignment: .trailing)
                }
            }
            .font(.body).monospacedDigit()
            .padding(.horizontal, 6).frame(height: 36)
            .background(isSelected ? Theme.accentTint : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 20) }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func totalRow(_ visible: [(column: Column, width: CGFloat)]) -> some View {
        HStack(spacing: 6) {
            Text("Total").frame(maxWidth: .infinity, alignment: .leading)
            ForEach(visible, id: \.column) { item in
                let value = total(item.column)
                Text(value.0).foregroundStyle(value.1).lineLimit(1).frame(width: item.width, alignment: .trailing)
            }
        }
        .font(.body.weight(.semibold)).monospacedDigit()
        .padding(.horizontal, 26).frame(height: 38)
    }
}
#endif
