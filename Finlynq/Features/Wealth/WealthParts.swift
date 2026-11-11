import SwiftUI

// Pieces shared by the Wealth screens: charts, allocation bars, figures and the iPhone bottom actions.

/// One point of a value chart: a balance, a market value, or a projected debt.
nonisolated struct ValuePoint: Identifiable, Equatable {
    let day: Date
    let value: Double
    /// Cost basis, drawn as a dashed grey line under the value.
    var cost: Double?
    var id: Date { day }
}

/// 1M 6M YTD 1Y All as outlined capsules; the selected one is filled black (Investments.dc.html).
struct PeriodChips: View {
    @Binding var period: String
    static let options = [("1m", "1M"), ("6m", "6M"), ("ytd", "YTD"), ("1y", "1Y"), ("all", "All")]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Self.options, id: \.0) { option in
                let selected = option.0 == period
                Button { period = option.0 } label: {
                    Text(option.1).font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Theme.page : Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(selected ? Theme.text : .clear, in: Capsule())
                        .overlay { if !selected { Capsule().strokeBorder(Theme.hairline) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Period")
    }
}

/// A horizontal bar split into colored segments with small gaps.
struct AllocationBar: View {
    let segments: [(share: Double, color: Color)]
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 4
            let usable = max(proxy.size.width - gap * CGFloat(max(segments.count - 1, 0)), 0)
            HStack(spacing: gap) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Capsule().fill(segment.color).frame(width: max(usable * segment.share, 3))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Color of an asset type or holding in allocation bars. Securities take purple shades by rank, crypto is orange,
/// cash grey and metals yellow.
enum WealthColors {
    static let purples = [Theme.invest, Color(red: 0.61, green: 0.48, blue: 0.94), Color(red: 0.79, green: 0.72, blue: 0.97)]

    /// The holding's icon and tint in lists: a trend line for funds and stocks, a coin for crypto, a note for cash.
    static func symbol(forType type: String) -> (symbol: String, tint: Color) {
        switch type {
        case "crypto": ("bitcoinsign", Theme.spendBar)
        case "cash": ("banknote", Theme.secondary)
        case "metal": ("circle.hexagongrid", forType("metal"))
        default: ("chart.line.uptrend.xyaxis", Theme.invest)
        }
    }

    static func forType(_ type: String, rank: Int = 0) -> Color {
        switch type {
        case "crypto": Theme.spendBar
        case "cash": Theme.categoryPalette[4]
        case "metal": Color(red: 0.85, green: 0.68, blue: 0.2)
        default: purples[min(rank, purples.count - 1)]
        }
    }
}

/// A square legend swatch with a name and an optional bold figure.
struct LegendItem: View {
    let color: Color
    let name: String
    var value: String?

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(name).foregroundStyle(Theme.secondary)
            if let value { Text(value).fontWeight(.semibold).monospacedDigit().foregroundStyle(Theme.text) }
        }
        .lineLimit(1)
    }
}

/// Label over a bold figure, with an optional detail line: the stat grids of Investments, Holding and Loan.
struct Figure: View {
    let label: String
    let value: String
    var color: Color = Theme.text
    var detail: String?
    var size: CGFloat = 17

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.footnote).foregroundStyle(Theme.secondary)
            Text(value).font(.system(size: size, weight: .bold)).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let detail { Text(detail).font(.footnote).foregroundStyle(Theme.secondary).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The iPhone screens' bottom bar: one or two large buttons over the page, the first one filled blue.
struct BottomActions: View {
    struct Action: Identifiable {
        let title: String
        /// Pushes this page through the stack's path instead of running `run`, so the shell can see it.
        var route: AppRoute?
        var run: () -> Void = {}
        var id: String { title }
    }

    let actions: [Action]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                let label = Text(action.title).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundStyle(index == 0 ? .white : Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(index == 0 ? Theme.accent : Theme.accentTint, in: RoundedRectangle(cornerRadius: 16,
                        style: .continuous))
                if let route = action.route {
                    NavigationLink(value: route) { label }.buttonStyle(.plain)
                } else {
                    Button(action: action.run) { label }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        .background(Theme.page.opacity(0.96))
        .overlay(alignment: .top) { Divider() }
    }
}

extension Double {
    /// "+$1,184" or "−$228" with whole units.
    func signedWhole(_ currency: String?) -> String { (self > 0 ? "+" : "") + wholeMoney(currency) }

    /// "+12.3%" from a percent value (12.3 means 12.3%).
    var signedPercent: String {
        let text = abs(self).formatted(.number.precision(.fractionLength(1))) + "%"
        return self < 0 ? "\u{2212}" + text : "+" + text
    }

    /// Green for gains, red for losses, the text color for zero.
    var gainColor: Color { self > 0 ? Theme.positive : self < 0 ? Theme.negative : Theme.text }
}

/// The width of a line of text in a text style's current size (so it follows Dynamic Type) with tabular digits, for
/// table columns sized to their content.
enum TextWidth {
    enum Style { case body, callout, subheadline, footnote }

    static func of(_ text: String, style: Style, bold: Bool = false) -> CGFloat {
        #if canImport(UIKit)
        let textStyle: UIFont.TextStyle = switch style {
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        }
        let size = UIFont.preferredFont(forTextStyle: textStyle).pointSize
        let font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
        #else
        let textStyle: NSFont.TextStyle = switch style {
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        }
        let size = NSFont.preferredFont(forTextStyle: textStyle).pointSize
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
        #endif
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

extension APIClient {
    /// The latest payment into each account, from its newest 50 rows. Accounts without one, or whose request fails
    /// (logged), are left out.
    func lastPayments(accountIds: [Int]) async -> [Int: Transaction] {
        await withTaskGroup(of: (Int, Transaction?).self) { group in
            for id in accountIds { group.addTask { (id, await self.lastPayment(accountId: id)) } }
            var result: [Int: Transaction] = [:]
            for await (id, payment) in group { result[id] = payment }
            return result
        }
    }

    private func lastPayment(accountId id: Int) async -> Transaction? {
        do {
            let rows = try await transactions(TransactionQuery(accountId: id, limit: 50)).data.filter { $0.accountId == id }
            return WealthModel.lastPayment(rows)
        } catch {
            WealthView.log.error("payments failed for \(id): \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

extension View {
    /// The decimal number pad on iPhone and iPad. No effect on the Mac.
    func numberPad() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }
}

extension Double {
    /// "+$1,184 (0.6%) today" for a change and its percent (0.6 means 0.6%).
    static func todayText(_ amount: Double, percent: Double, currency: String?, cents: Bool = false) -> String {
        let money = cents ? MoneyText.format(amount, currency: currency, signed: true) : amount.signedWhole(currency)
        return "\(money) (\(abs(percent).formatted(.number.precision(.fractionLength(1))))%) today"
    }
}

extension Date {
    /// "Mar 2030".
    nonisolated var monthYear: String { formatted(.dateTime.month(.abbreviated).year()) }
    /// "Nov 15".
    nonisolated var monthDay: String { formatted(.dateTime.month(.abbreviated).day()) }
}
