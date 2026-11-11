import SwiftUI

/// White rounded container used for every block on a page. In dark mode a hairline keeps it apart from the page.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.cardBorder))
            #if os(macOS)
            .shadow(color: Theme.cardShadow, radius: 1, y: 1)
            #endif
    }
}

struct SectionTitle: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(Theme.text)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.subheadline).foregroundStyle(Theme.accent)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Rounded square with a symbol, for rows and cards.
struct IconTile: View {
    let symbol: String
    var tint: Color = Theme.accent
    var background: Color = Theme.accentTint
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Small pill label such as "Due soon" or "Over budget".
struct Chip: View {
    let text: String
    var tint: Color = Theme.accent
    var background: Color = Theme.accentTint

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
    }
}

/// Thin progress bar. `value` is a fraction; values above 1 fill the bar.
struct ProgressLine: View {
    let value: Double
    var color: Color = Theme.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.categoryPalette[4].opacity(0.5))
                Capsule().fill(color).frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(value.formatted(.percent.precision(.fractionLength(0))))
    }
}

/// A money amount with tabular digits. Negative amounts use the true minus sign (U+2212).
struct MoneyText: View {
    let amount: Double
    var currency: String?
    /// Shows "+" before positive amounts and colors by sign.
    var signed = false
    var cents = true

    var body: some View {
        Text(Self.format(amount, currency: currency, signed: signed, cents: cents))
            .monospacedDigit()
            .foregroundStyle(signed ? color : Theme.text)
    }

    private var color: Color {
        amount > 0 ? Theme.positive : amount < 0 ? Theme.negative : Theme.secondary
    }

    static func format(_ amount: Double, currency: String?, signed: Bool = false, cents: Bool = true) -> String {
        let text = abs(amount).money(currency, cents: cents)
        if amount < 0 { return "\u{2212}" + text }
        return signed && amount > 0 ? "+" + text : text
    }
}

struct EmptyState: View {
    let title: String
    let message: String
    var symbol = "tray"

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}
