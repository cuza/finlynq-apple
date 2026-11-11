import SwiftUI

/// A horizontal stacked bar of spending by category. What is left of `total` shows as a grey segment.
struct CategoryBar: View {
    struct Segment: Identifiable {
        let id: String
        let label: String
        let amount: Double
        let color: Color
    }

    let segments: [Segment]
    let total: Double
    var height: CGFloat = 10

    init(segments: [Segment], total: Double, height: CGFloat = 10) {
        self.segments = segments
        self.total = total
        self.height = height
    }

    var body: some View {
        let amounts = segments.map(\.amount)
        let fractions = Self.fractions(amounts, total: total)
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(Array(zip(segments, fractions)), id: \.0.id) { segment, fraction in
                    segment.color.frame(width: max(0, proxy.size.width * fraction))
                }
                Theme.categoryPalette[4].opacity(0.5).frame(maxWidth: .infinity)
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segments.map { "\($0.label) \($0.amount.formatted())" }.joined(separator: ", "))
    }

    /// Each amount as a share of `total`. Negatives count as 0. When the amounts add up to more than
    /// `total`, they are scaled to sum to 1. A zero or negative `total` gives all zeros.
    static func fractions(_ amounts: [Double], total: Double) -> [Double] {
        guard total > 0 else { return amounts.map { _ in 0 } }
        let clamped = amounts.map { max(0, $0) }
        let denominator = max(total, clamped.reduce(0, +))
        return clamped.map { $0 / denominator }
    }

    /// The unspent share of the bar, shown grey.
    static func remainder(_ amounts: [Double], total: Double) -> Double {
        guard total > 0 else { return 0 }
        return max(0, 1 - fractions(amounts, total: total).reduce(0, +))
    }
}
