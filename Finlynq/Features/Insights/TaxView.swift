import SwiftUI

/// Tax time (Tax.dc.html; iPad and Mac center the same layout): a year's dividends by quarter and holding, and its
/// realized gains split into long and short term, with a CSV export of both.
struct TaxView: View {
    @Environment(Session.self) private var session
    @Environment(\.layoutWidth) private var width
    @State private var year = Calendar(identifier: .gregorian).component(.year, from: Fixtures.today)
    @State private var attempt = 0
    @State private var exporting: CSVExport?

    struct Data {
        let dividends: DividendIncome?
        let gains: RealizedGains?
    }

    private static let calendar = Calendar(identifier: .gregorian)
    private var thisYear: Int { Self.calendar.component(.year, from: Fixtures.today) }

    var body: some View {
        Reloader(id: "\(year)|\(session.revision)|\(attempt)", source: "tax") {
            async let dividends = optionalLoad("dividends") { try await session.api.dividends(year: year) }
            async let gains = optionalLoad("realized gains") { try await session.api.realizedGains(year: year) }
            return await Data(dividends: dividends, gains: gains)
        } content: { data in
            content(data)
        }
        .background(Theme.page)
        .navigationTitle("Tax time")
        #if os(iOS)
        .toolbarTitleDisplayMode(.large)
        #endif
    }

    // MARK: Figures

    /// The year's currencies, the most used first. Dividends and gains are in each holding's own currency.
    private func currencies(_ data: Data) -> [String] {
        let codes = (data.dividends?.rows ?? []).map(\.currency) + (data.gains?.rows ?? []).map(\.currency)
        return Dictionary(grouping: codes, by: { $0 }).sorted { $0.value.count > $1.value.count }.map(\.key)
    }

    private func currency(_ data: Data) -> String { currencies(data).first ?? session.currency }

    private var yearNote: String {
        if year == thisYear {
            return "\(year) so far, through \(Fixtures.today.formatted(.dateTime.month(.abbreviated).day()))."
        }
        return "\(year)."
    }

    private func export(_ data: Data) -> CSVExport {
        var lines = ["Kind,Date,Holding,Account,Quantity,Amount,Currency,Term"]
        for row in data.dividends?.rows ?? [] {
            let kind = row.isWithholding == true ? "Withholding" : row.isReinvested == true ? "Dividend reinvested" : "Dividend"
            let text = [kind, String(row.date.prefix(10)), row.holdingName ?? row.payee ?? "", row.accountName ?? ""]
            lines.append((text.map(CSV.text) + ["", CSV.number(row.amount), row.currency, ""])
                .joined(separator: ","))
        }
        for row in data.gains?.rows ?? [] {
            let text = ["Realized gain", String(row.closeDate.prefix(10)), row.holdingName ?? "", row.accountName ?? ""]
            let numbers = [
                CSV.number(row.qtyClosed), CSV.number(row.realizedGain), row.currency, row.term ?? ""
            ]
            lines.append((text.map(CSV.text) + numbers).joined(separator: ","))
        }
        return CSVExport(name: "Finlynq tax \(year).csv", text: lines.joined(separator: "\n") + "\n")
    }

    // MARK: Layout

    private func content(_ data: Data) -> some View {
        let wide = width != .compact
        let codes = currencies(data)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SegmentBar("Tax year", options: [(thisYear, String(thisYear)), (thisYear - 1, String(thisYear - 1))], selection: $year)
                Text("\(yearNote) Amounts in \(codes.isEmpty ? session.currency : ListFormatter.localizedString(byJoining: codes)).")
                    .font(.footnote).foregroundStyle(Theme.secondary).padding(.horizontal, 4)
                TaxDividendsCard(dividends: data.dividends, year: year, currency: currency(data)) { attempt += 1 }
                TaxGainsCard(gains: data.gains, currency: currency(data)) { attempt += 1 }
                Text("Gains use simple average cost basis. Short term means held 365 days or less.")
                    .font(.footnote).foregroundStyle(Theme.secondary).padding(.horizontal, 4)
            }
            .padding(.horizontal, wide ? 28 : 20).padding(.bottom, 16)
            .frame(maxWidth: wide ? 720 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            #if os(iOS)
            if !wide { exportBar(data) }
            #else
            exportBar(data)
            #endif
        }
        #if os(iOS)
        .toolbar {
            // iPadPTax.dc.html: Export CSV sits in the toolbar on wider columns.
            if wide {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: export(data), preview: SharePreview("Finlynq tax \(String(year)).csv")) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        #endif
    }

    private func exportBar(_ data: Data) -> some View {
        let label = HStack(spacing: 8) {
            Image(systemName: "square.and.arrow.up")
            Text("Export \(String(year)) as CSV")
        }
        .font(.body.weight(.semibold)).foregroundStyle(.white)
        .frame(maxWidth: .infinity).frame(height: 50)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        return VStack(spacing: 0) {
            Divider()
            Group {
                #if os(macOS)
                Button { exporting = export(data) } label: { label }
                    .buttonStyle(.plain)
                    .fileExporter(
                        isPresented: Binding { exporting != nil } set: { if !$0 { exporting = nil } },
                        document: exporting.map { CSVFile(text: $0.text) }, contentType: .commaSeparatedText,
                        defaultFilename: exporting?.name
                    ) { _ in exporting = nil }
                #else
                ShareLink(item: export(data), preview: SharePreview("Finlynq tax \(String(year)).csv")) { label }
                #endif
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Theme.page)
    }
}

/// Holding symbol in a small rounded tile, as in Tax.dc.html.
struct SymbolTile: View {
    let symbol: String
    var tint = Theme.invest
    var background = Theme.investTint

    var body: some View {
        Text(String(symbol.prefix(4)).uppercased())
            .font(.system(size: 10, weight: .bold)).foregroundStyle(tint).minimumScaleFactor(0.6).lineLimit(1)
            .padding(.horizontal, 3)
            .frame(width: 34, height: 34)
            .background(background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Dividends: the total with reinvested and withheld amounts, the four quarters, and each holding.
private struct TaxDividendsCard: View {
    let dividends: DividendIncome?
    let year: Int
    let currency: String
    let retry: () -> Void
    @Environment(\.layoutWidth) private var width
    /// Each quarter's bar slot in the quarters row, for the selection.
    @State private var slots: [Int: CGRect] = [:]

    private struct Holding: Identifiable {
        let name: String
        let total: Double
        let payments: Int
        let withheld: Double
        let allReinvested: Bool
        var id: String { name }
    }

    var body: some View {
        Card(padding: 18) {
            if let dividends {
                content(dividends)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dividends").font(.headline).foregroundStyle(Theme.text)
                    InlineError(message: "Couldn't load dividends", retry: retry)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ dividends: DividendIncome) -> some View {
        let rows = dividends.rows ?? []
        let reinvested = rows.filter { $0.isReinvested == true }.reduce(0) { $0 + $1.amount }
        let withheld = abs(rows.filter { $0.isWithholding == true }.reduce(0) { $0 + $1.amount })
        let parts = [reinvested > 0 ? "\(reinvested.money(currency)) reinvested" : nil,
                     withheld > 0 ? "\(withheld.money(currency)) withheld" : nil].compactMap { $0 }
        let total = Text(MoneyText.format(dividends.totals.amount, currency: currency, signed: true))
            .font(.system(size: width == .compact ? 26 : 34, weight: .bold)).foregroundStyle(Theme.positive).monospacedDigit()
        VStack(alignment: .leading, spacing: 14) {
            if width == .compact {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dividends").font(.headline).foregroundStyle(Theme.text)
                        if !parts.isEmpty {
                            Text(parts.joined(separator: " \u{00B7} ")).font(.footnote).foregroundStyle(Theme.secondary)
                        }
                    }
                    Spacer()
                    total
                }
            } else {
                // iPadPTax.dc.html: the title and the details on one line, the total on its own line under them.
                HStack(alignment: .firstTextBaseline) {
                    Text("Dividends").font(.headline).foregroundStyle(Theme.text)
                    Spacer()
                    Text(parts.joined(separator: " \u{00B7} ")).font(.footnote).foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.trailing)
                }
                total.lineLimit(1).minimumScaleFactor(0.6)
            }
            if rows.isEmpty {
                Text("No dividends in \(String(year)).").font(.subheadline).foregroundStyle(Theme.secondary)
            } else {
                quarters(rows)
                Divider()
                Text("By holding").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                DividedRows(items: holdings(rows)) { holding in
                    HStack(spacing: 12) {
                        SymbolTile(symbol: holding.name)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(holding.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                            Text(detail(holding)).font(.footnote).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Text(MoneyText.format(holding.total, currency: currency, signed: true))
                            .font(.body.weight(.semibold)).foregroundStyle(Theme.positive).monospacedDigit()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func detail(_ holding: Holding) -> String {
        var parts = ["\(holding.payments) \(holding.payments == 1 ? "payment" : "payments")"]
        if holding.allReinvested { parts.append("all reinvested") }
        if holding.withheld > 0 { parts.append("\(holding.withheld.money(currency)) withheld") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func holdings(_ rows: [DividendIncome.Row]) -> [Holding] {
        Dictionary(grouping: rows, by: { $0.holdingName ?? $0.payee ?? "Other" }).map { name, list in
            let payments = list.filter { $0.isWithholding != true }
            return Holding(
                name: name, total: list.reduce(0) { $0 + $1.amount }, payments: payments.count,
                withheld: abs(list.filter { $0.isWithholding == true }.reduce(0) { $0 + $1.amount }),
                allReinvested: !payments.isEmpty && payments.allSatisfy { $0.isReinvested == true }
            )
        }
        .sorted { $0.total > $1.total }
    }

    /// Four quarter bars with their totals. A quarter that hasn't started is a dashed outline.
    private func quarters(_ rows: [DividendIncome.Row]) -> some View {
        let calendar = Calendar(identifier: .gregorian)
        let totals = (1...4).map { quarter in
            rows.filter { row in
                let month = APIDate.parse(row.date).map { calendar.component(.month, from: $0) } ?? 0
                return (month - 1) / 3 + 1 == quarter
            }
            .reduce(0) { $0 + $1.amount }
        }
        let todayQuarter = year < calendar.component(.year, from: Fixtures.today)
            ? 4 : (calendar.component(.month, from: Fixtures.today) - 1) / 3 + 1
        let top = max(totals.max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(0..<4, id: \.self) { index in
                VStack(spacing: 6) {
                    Text(index + 1 > todayQuarter ? " " : totals[index].wholeMoney(currency))
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.text).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Group {
                        if index + 1 > todayQuarter {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Theme.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .frame(height: 62)
                        } else {
                            RoundedRectangle(cornerRadius: 6).fill(Theme.invest.opacity(totals[index] > 0 ? 1 : 0.15))
                                .frame(height: max(6, 62 * totals[index] / top))
                        }
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("quarters")) } action: { slots[index] = $0 }
                    Text("Q\(index + 1)").font(.footnote).foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 104, alignment: .bottom)
        .coordinateSpace(.named("quarters"))
        .overlay {
            // The band and tooltip stay in the 62 pt bar area above the quarter names; the band starts at the bar,
            // under its amount.
            let bars = (0..<4).compactMap { slots[$0] }
            if bars.count == 4, let bottom = bars.map(\.maxY).max() {
                let plot = CGRect(x: 0, y: bottom - 62, width: bars[3].maxX, height: 62)
                ChartSelectionLayer(
                    plot: plot, style: .bar(width: bars[0].width + 6, hugsBar: true),
                    pick: { location in ChartMath.nearest(bars.map { Double($0.midX) }, to: Double(location.x)) },
                    anchor: { CGPoint(x: bars[$0].midX, y: bars[$0].minY) },
                    tip: { index in
                        ["Q\(index + 1) \(String(year))", index + 1 > todayQuarter ? "Not started" : totals[index].wholeMoney(currency)]
                    }
                )
            }
        }
    }
}

/// Realized gains: the total, the long and short split, and each sale.
private struct TaxGainsCard: View {
    let gains: RealizedGains?
    let currency: String
    let retry: () -> Void
    @Environment(\.layoutWidth) private var width

    var body: some View {
        Card(padding: 18) {
            if let gains {
                content(gains)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Realized gains").font(.headline).foregroundStyle(Theme.text)
                    InlineError(message: "Couldn't load realized gains", retry: retry)
                }
            }
        }
    }

    private func isLong(_ row: RealizedGains.Row) -> Bool { row.term == "long" || (row.daysHeld ?? 0) > 365 }

    @ViewBuilder
    private func content(_ gains: RealizedGains) -> some View {
        let rows = gains.rows.sorted { $0.closeDate < $1.closeDate }
        let long = rows.filter(isLong).reduce(0) { $0 + $1.realizedGain }
        let short = rows.filter { !isLong($0) }.reduce(0) { $0 + $1.realizedGain }
        let sales = "\(rows.count) \(rows.count == 1 ? "sale" : "sales")"
        let total = Text(MoneyText.format(gains.totals.realizedGain, currency: currency, signed: true))
            .font(.system(size: width == .compact ? 26 : 34, weight: .bold))
            .foregroundStyle(gains.totals.realizedGain >= 0 ? Theme.positive : Theme.negative)
            .monospacedDigit()
        VStack(alignment: .leading, spacing: 14) {
            if width == .compact {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Realized gains").font(.headline).foregroundStyle(Theme.text)
                        Text(sales).font(.footnote).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    total
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("Realized gains").font(.headline).foregroundStyle(Theme.text)
                    Spacer()
                    Text(sales).font(.footnote).foregroundStyle(Theme.secondary)
                }
                total.lineLimit(1).minimumScaleFactor(0.6)
            }
            if rows.isEmpty {
                Text("No sales this year.").font(.subheadline).foregroundStyle(Theme.secondary)
            } else {
                CategoryBar(segments: [.init(id: "long", label: "Long term", amount: max(long, 0), color: Theme.accent),
                                       .init(id: "short", label: "Short term", amount: max(short, 0), color: Theme.spendBar)],
                            total: max(long, 0) + max(short, 0), height: 8)
                HStack(alignment: .top) {
                    split("Long term", long, Theme.accent)
                    split("Short term", short, Theme.spendBar)
                }
                Divider()
                Text("Sales").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                DividedRows(items: rows) { row in sale(row) }
            }
        }
    }

    private func split(_ label: String, _ amount: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8); Text(label) }
                .font(.footnote).foregroundStyle(Theme.secondary)
            Text(MoneyText.format(amount, currency: currency, signed: true)).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "2y 5m" past a year, else "140 days".
    private func held(_ days: Int?) -> String? {
        guard let days else { return nil }
        if days <= 365 { return "held \(days) days" }
        return "held \(days / 365)y \((days % 365) / 30)m"
    }

    private func sale(_ row: RealizedGains.Row) -> some View {
        let long = isLong(row)
        let name = row.holdingName ?? "Holding"
        let quantity = row.qtyClosed.formatted(.number.precision(.fractionLength(0...4)))
        let sold = APIDate.parse(row.closeDate).map { "Sold " + $0.formatted(.dateTime.month(.abbreviated).day()) }
        return HStack(spacing: 12) {
            SymbolTile(symbol: name, tint: long ? Theme.invest : Theme.warning, background: long ? Theme.investTint : Theme.warningTint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(name) \u{00B7} \(quantity) shares").font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Chip(text: long ? "Long" : "Short", tint: long ? Theme.accent : Theme.warning,
                         background: long ? Theme.accentTint : Theme.warningTint)
                        .fixedSize()
                }
                Text([sold, held(row.daysHeld)].compactMap { $0 }.joined(separator: " \u{00B7} "))
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(MoneyText.format(row.realizedGain, currency: row.currency, signed: true))
                    .font(.body.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(row.realizedGain >= 0 ? Theme.positive : Theme.negative)
                Text("for \((row.qtyClosed * row.proceedsPerShare).money(row.currency))").font(.footnote).foregroundStyle(Theme.secondary)
                    .monospacedDigit()
            }
            .fixedSize()
        }
        .padding(.vertical, 8)
    }
}
