import SwiftUI

/// The attention list. Each row opens the screen that resolves it. Empty shows "You're all caught up".
struct NeedsAttentionCard: View {
    let items: [AttentionItem]
    var layout = HomeLayout.phone

    var body: some View {
        Card(padding: layout == .phone ? 16 : 18) {
            VStack(alignment: .leading, spacing: 4) {
                HomeCardHeader(title: "Needs attention", layout: layout)
                if items.isEmpty {
                    Label("You're all caught up", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.positive)
                        .font(layout.rowTitle)
                        .padding(.vertical, layout.rowPadding)
                } else {
                    DividedRows(items: items) { item in
                        NavigationLink(value: item.route) { row(item) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func row(_ item: AttentionItem) -> some View {
        HStack(spacing: layout == .mac ? 10 : 12) {
            tile(item)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(layout.rowTitle).foregroundStyle(Theme.text).lineLimit(2)
                Text(item.subtitle).font(layout.rowDetail).foregroundStyle(Theme.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            if let trailing = item.trailing {
                Text(trailing).font(layout.rowTitle).monospacedDigit().fixedSize()
                    .foregroundStyle(trailingColor(item.kind))
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary.opacity(0.7))
                .accessibilityHidden(true)
        }
        .padding(.vertical, layout.rowPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func trailingColor(_ kind: AttentionItem.Kind) -> Color {
        if case .budgetWarning(_, _, let left) = kind, left >= 0 { return Theme.warning }
        return Theme.negative
    }

    @ViewBuilder
    private func tile(_ item: AttentionItem) -> some View {
        let size = layout.tileSize
        switch item.kind {
        case .review(let count):
            Text("\(count)").font(layout == .mac ? .callout.weight(.bold) : .footnote.weight(.bold)).monospacedDigit()
                .foregroundStyle(Theme.accent)
                .frame(width: size, height: size)
                .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
                .accessibilityHidden(true)
        case .budgetWarning(let name, _, let left):
            IconTile(
                // The portrait boards show the category's own icon beside its name.
                symbol: item.trailing != nil ? Icons.category(name).0 : left < 0 ? "exclamationmark.circle" : "exclamationmark.triangle",
                tint: left < 0 ? Theme.negative : Theme.warning,
                background: left < 0 ? Theme.negativeTint : Theme.warningTint, size: size
            )
        case .billsThisWeek: IconTile(symbol: "calendar", tint: Theme.invest, background: Theme.investTint, size: size)
        case .applePay: IconTile(symbol: "creditcard", tint: Theme.warning, background: Theme.warningTint, size: size)
        }
    }
}
