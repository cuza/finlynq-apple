import SwiftUI

// MARK: Card

/// One row to review: date and account, payee and amount, its category, and a possible match to resolve.
/// `wide` is the iPad card: category chips and the Create a rule toggle.
struct ReviewCard: View {
    let row: StagedRow
    let wide: Bool
    let position: Int
    let total: Int
    let account: String?
    let category: Category?
    let needsChoice: Bool
    let quick: [Category]
    @Binding var createsRule: Bool
    let onPick: () -> Void
    let onChoose: (Int) -> Void
    let onLink: () -> Void
    let onKeepSeparate: () -> Void
    let onDelete: () -> Void
    @Environment(\.layoutWidth) private var width

    /// iPad portrait (iPadPReview): the iPad card with the amount on its own line under the payee, at full size.
    private var stacked: Bool { wide && width == .medium }

    var body: some View {
        VStack(alignment: .leading, spacing: wide ? 16 : 14) {
            HStack {
                Label(header, systemImage: "square.and.arrow.down").labelStyle(ReviewIconLabel())
                    .font(.footnote).foregroundStyle(Theme.secondary)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(Theme.secondary)
                        .frame(width: wide ? 44 : 36, height: wide ? 44 : 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(wide ? -12 : -8).padding(.leading, wide ? 12 : 8)
                .accessibilityLabel("Delete this row")
            }
            if stacked {
                VStack(alignment: .leading, spacing: 8) {
                    titleBlock(size: 26)
                    amount(size: 40).fixedSize()
                }
                chips
            } else if wide {
                HStack(alignment: .bottom, spacing: 16) {
                    titleBlock(size: 26)
                    Spacer(minLength: 0)
                    amount(size: 40).lineLimit(1).minimumScaleFactor(0.6)
                }
                chips
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    titleBlock(size: 22)
                    amount(size: 36).lineLimit(1).minimumScaleFactor(0.6).padding(.top, 10)
                }
                categoryButton
            }
            if needsChoice, let match = row.match { matchBox(match) }
            if wide { ruleToggle }
        }
        .padding(wide ? 20 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.cardBorder))
        .shadow(color: Theme.text.opacity(0.06), radius: 5, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Imported row \(position) of \(total)")
    }

    private var header: String {
        let day = APIDate.parse(row.date)?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) ?? row.date
        return [day, account, wide ? "Row \(position) of \(total)" : nil].compactMap(\.self).joined(separator: " · ")
    }

    private func titleBlock(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: wide ? 4 : 2) {
            Text(row.payee ?? "No payee").font(.system(size: size, weight: .bold)).tracking(-0.01 * size)
                .foregroundStyle(Theme.text)
            if let note = row.note, !note.isEmpty {
                Text("Bank text: \(note)").font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func amount(size: CGFloat) -> some View {
        Text(reviewMoney(row.amount, row.currency))
            .font(.system(size: size, weight: .bold)).tracking(-0.03 * size).monospacedDigit()
            .foregroundStyle(row.amount > 0 ? Theme.positive : Theme.text)
    }

    /// iPhone: one row that opens the category picker.
    private var categoryButton: some View {
        Button(action: onPick) {
            HStack(spacing: 12) {
                let icon = category.map(Icons.category) ?? Icons.fallback
                IconTile(symbol: icon.0, tint: icon.1, background: icon.1.opacity(0.14), size: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(category == nil ? "Category" : "Suggested category").font(.footnote).foregroundStyle(Theme.secondary)
                    Text(category?.displayName ?? "Choose a category").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.secondary.opacity(0.7))
            }
            .padding(12)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// iPad: the suggested category and a few others as chips, then All categories.
    private var chips: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Category").font(.subheadline.weight(.bold))
                Spacer()
                if let category { Text("\(category.displayName) is suggested").font(.footnote).foregroundStyle(Theme.secondary) }
            }
            ReviewFlow(spacing: 8) {
                ForEach(quick) { item in
                    let isOn = item.id == row.categoryId
                    Button { onChoose(item.id) } label: {
                        HStack(spacing: 6) {
                            if isOn { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                            Text(item.displayName)
                        }
                        .font(.subheadline.weight(isOn ? .semibold : .medium))
                        .foregroundStyle(isOn ? Theme.card : Theme.text)
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(isOn ? Theme.text : Theme.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(isOn ? .clear : Theme.hairline))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
                Button(action: onPick) {
                    HStack(spacing: 4) {
                        Text("All categories")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(Theme.accentTint, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func matchBox(_ match: ReviewMatch) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "link").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accent).padding(.top, 1)
                matchText(match).font(.subheadline).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Button(action: onLink) {
                    Text("Link").frame(maxWidth: .infinity).frame(height: 44).foregroundStyle(.white)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Button(action: onKeepSeparate) {
                    Text("Keep separate").frame(maxWidth: .infinity).frame(height: 44)
                        .foregroundStyle(Theme.accent)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func matchText(_ match: ReviewMatch) -> Text {
        let what = [match.payee, match.amount.map { reviewMoney($0, row.currency) }].compactMap(\.self).joined(separator: " ")
        let day = match.date.flatMap { APIDate.parse($0) }?.formatted(.dateTime.month(.abbreviated).day())
        let place = wide ? account.map { " in \($0)" } ?? "" : ""
        return Text("Looks like your manual entry ") + Text(what.isEmpty ? "#\(match.transactionId)" : what).fontWeight(.semibold)
            + Text((day.map { " on \($0)" } ?? "") + place + ".")
    }

    private var ruleToggle: some View {
        VStack(spacing: 14) {
            Rectangle().fill(Theme.fill).frame(height: 1)
            Toggle(isOn: $createsRule) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Create a rule").font(.subheadline.weight(.semibold))
                    if let text = ReviewModel.rulePayee(row) {
                        Text("Payee contains \"\(text)\"" + (category.map { ", set \($0.displayName)" } ?? ""))
                            .font(.footnote).foregroundStyle(Theme.secondary)
                    }
                }
            }
            .toggleStyle(ReviewCheckbox())
            .disabled(category == nil)
        }
    }
}

/// Two lighter cards peeking out below, so the card reads as the top of a stack.
struct ReviewStack<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.bottom, 14)
            .background(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20).fill(Theme.fill)
                        .frame(height: 40).padding(.horizontal, 24)
                    UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22).fill(Theme.fill.opacity(0.6))
                        .frame(height: 40).padding(.horizontal, 12).padding(.bottom, 7)
                }
                .accessibilityHidden(true)
            }
    }
}

/// Small rounded status label: "Suggested", "Needs category", "Approved".
struct ReviewBadge: View {
    let text: String
    var symbol: String?
    let tint: Color
    let background: Color

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
            Text(text)
        }
        .font(.caption.weight(.semibold)).foregroundStyle(tint)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct ReviewIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 13, weight: .medium))
            configuration.title
        }
    }
}

/// A square checkbox, as in the iPad design's Create a rule row.
struct ReviewCheckbox: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22)).foregroundStyle(configuration.isOn ? Theme.accent : Theme.secondary)
                configuration.label.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Theme.text)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

/// Lays children out in rows, wrapping to the next row when one is full.
struct ReviewFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// Every category, newest-kind first: expense categories for money out, income for money in.
struct ReviewCategoryPicker: View {
    let amount: Double
    let selected: Int?
    let onPick: (Int) -> Void
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.0) { title, items in
                    Section(title) {
                        ForEach(items) { item in
                            Button { onPick(item.id) } label: {
                                HStack {
                                    let icon = Icons.category(item)
                                    IconTile(symbol: icon.0, tint: icon.1, background: icon.1.opacity(0.14), size: 30)
                                    Text(item.displayName).foregroundStyle(Theme.text)
                                    Spacer()
                                    if item.id == selected { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search categories")
            .navigationTitle("Category")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 440)
        #endif
    }

    private var sections: [(String, [Category])] {
        let matching = session.categories.filter { search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search) }
        let first = amount > 0 ? "I" : "E"
        let order = [first, first == "E" ? "I" : "E", "R"]
        let titles = ["E": "Spending", "I": "Income", "R": "Transfers"]
        return order.compactMap { type in
            let items = matching.filter { $0.type == type }
            return items.isEmpty ? nil : (titles[type] ?? type, items)
        }
    }
}

/// "−$27.99" or "+$3,200.00".
func reviewMoney(_ amount: Double, _ currency: String?) -> String {
    MoneyText.format(amount, currency: currency, signed: true)
}

/// "Nov 8".
func reviewDay(_ date: String) -> String {
    APIDate.parse(date)?.formatted(.dateTime.month(.abbreviated).day()) ?? date
}
