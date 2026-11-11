import SwiftUI

/// One row in the split editor. The amount is a positive magnitude; the parent's sign is applied on save.
struct SplitDraft: Identifiable, Equatable {
    let id = UUID()
    var categoryId: Int?
    var amount: Double
    var note = ""

    /// True when the parts add up to the transaction's amount to the cent.
    nonisolated static func isBalanced(total: Double, amounts: [Double]) -> Bool {
        guard !amounts.isEmpty else { return false }
        return cents(amounts.reduce(0, +)) == cents(abs(total))
    }

    nonisolated static func inputs(_ drafts: [SplitDraft], total: Double) -> [SplitInput] {
        let sign: Double = total < 0 ? -1 : 1
        return drafts.map { SplitInput(categoryId: $0.categoryId, amount: sign * $0.amount, note: $0.note.isEmpty ? nil : $0.note) }
    }

    private nonisolated static func cents(_ value: Double) -> Int { Int((value * 100).rounded()) }
}

/// The split card (Transaction.dc.html): title and Balanced or Left/Over badge, a bar of the parts, one row per
/// part, and Add split. Save split shows while the parts differ from what is saved.
/// `compact` is the Mac inspector's version, with color squares instead of icons.
struct SplitEditor: View {
    @Environment(Session.self) private var session
    @Binding var drafts: [SplitDraft]
    let total: Double
    let currency: String
    var seedCategoryId: Int?
    var compact = false
    var dirty = false
    var saving = false
    let onSave: () -> Void
    let onClear: () -> Void

    private var allocated: Double { drafts.reduce(0) { $0 + $1.amount } }
    private var balanced: Bool { SplitDraft.isBalanced(total: total, amounts: drafts.map(\.amount)) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack {
                Text("Split").font(compact ? .body.weight(.bold) : .subheadline.weight(.bold)).foregroundStyle(Theme.text)
                Spacer()
                badge
            }
            if !drafts.isEmpty {
                CategoryBar(
                    segments: drafts.enumerated().map { index, draft in
                        .init(id: draft.id.uuidString, label: name(draft), amount: draft.amount, color: color(index))
                    },
                    total: abs(total), height: compact ? 6 : 8
                )
            }
            VStack(spacing: 0) {
                ForEach($drafts) { $draft in
                    let index = drafts.firstIndex { $0.id == draft.id } ?? 0
                    if !compact && index > 0 { Divider() }
                    row($draft, index: index)
                }
                if !compact && !drafts.isEmpty { Divider() }
                actions
            }
        }
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.top, compact ? 10 : 14)
        .padding(.bottom, compact ? 10 : 4)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: compact ? 10 : 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 10 : 18, style: .continuous)
                .strokeBorder(compact ? Theme.hairline.opacity(0.7) : Theme.cardBorder)
        )
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                // The first part starts as the whole amount in the transaction's category.
                drafts.append(SplitDraft(categoryId: drafts.isEmpty ? seedCategoryId : nil, amount: max(abs(total) - allocated, 0)))
            } label: {
                Label("Add split", systemImage: "plus").labelStyle(.titleAndIcon)
                    .fontWeight(compact ? .medium : .semibold).foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            Spacer()
            if dirty && !drafts.isEmpty {
                Button("Save split", action: onSave)
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .controlSize(compact ? .small : .regular)
                    .disabled(!balanced || saving)
            } else if !drafts.isEmpty {
                Button("Remove splits", role: .destructive, action: onClear)
                    .buttonStyle(.plain).foregroundStyle(Theme.negative)
            }
        }
        .frame(minHeight: compact ? 24 : 44)
        .padding(.top, compact ? 2 : 0)
    }

    @ViewBuilder
    private var badge: some View {
        if drafts.isEmpty {
            EmptyView()
        } else if balanced {
            Chip(text: "Balanced", tint: Theme.positive, background: Theme.positiveTint)
        } else {
            let diff = abs(total) - allocated
            Chip(
                text: diff > 0 ? "\(diff.money(currency)) left" : "\((-diff).money(currency)) over",
                tint: Theme.warning, background: Theme.warningTint
            )
        }
    }

    private func name(_ draft: SplitDraft) -> String {
        session.categories.first { $0.id == draft.categoryId }?.displayName ?? "Choose a category"
    }

    private func color(_ index: Int) -> Color { Theme.categoryPalette[index % 4] }

    private func categoryMenu(_ draft: Binding<SplitDraft>) -> some View {
        Menu {
            Picker("Category", selection: draft.categoryId) {
                Text("No category").tag(Int?.none)
                ForEach(session.categories) { Text($0.displayName).tag(Int?.some($0.id)) }
            }
            Divider()
            Button("Remove this split", role: .destructive) { drafts.removeAll { $0.id == draft.wrappedValue.id } }
        } label: {
            Text(name(draft.wrappedValue))
                .fontWeight(compact ? .regular : .semibold)
                .foregroundStyle(draft.wrappedValue.categoryId == nil ? Theme.warning : Theme.text)
                .lineLimit(1)
        }
        .plainMenu()
        .fixedSize()
    }

    private func amountField(_ draft: Binding<SplitDraft>) -> some View {
        TextField("Amount", value: draft.amount, format: .number.precision(.fractionLength(2)))
            .textFieldStyle(.plain)
            .fontWeight(compact ? .medium : .semibold).monospacedDigit()
            .multilineTextAlignment(.trailing).frame(width: compact ? 70 : 90)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
    }

    @ViewBuilder
    private func row(_ draft: Binding<SplitDraft>, index: Int) -> some View {
        if compact {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(color(index)).frame(width: 8, height: 8)
                categoryMenu(draft)
                TextField("Note", text: draft.note).textFieldStyle(.plain).foregroundStyle(Theme.secondary)
                amountField(draft)
            }
            .frame(minHeight: 22)
        } else {
            let icon = session.categories.first { $0.id == draft.wrappedValue.categoryId }.map(Icons.category) ?? Icons.fallback
            HStack(spacing: 12) {
                IconTile(symbol: icon.0, tint: icon.1, background: icon.1.opacity(0.15), size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    categoryMenu(draft)
                    TextField("Note", text: draft.note).textFieldStyle(.plain).font(.footnote).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 8)
                amountField(draft)
            }
            .padding(.vertical, 9)
        }
    }
}
