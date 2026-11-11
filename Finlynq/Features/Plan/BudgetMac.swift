#if os(macOS)
import SwiftUI

/// MacPlan.dc.html: one card with left to spend, income and left to plan side by side.
struct MacBudgetSummary: View {
    let budget: BudgetMonth
    let currency: String
    let perDay: (Double) -> String

    var body: some View {
        let summary = budget.summary
        let left = summary.plannedSpending - summary.spent
        let slices = HomeModel.budgetSlices(budget.spending, limit: 3)
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    label(left >= 0 ? "Left to spend" : "Over budget")
                    Spacer()
                    Text("\(summary.spent.wholeMoney(currency)) of \(summary.plannedSpending.wholeMoney(currency)) spent")
                        .foregroundStyle(Theme.secondary)
                }
                figure(abs(left).wholeMoney(currency), color: left >= 0 ? Theme.text : Theme.negative)
                CategoryBar(
                    segments: slices.enumerated().map { index, slice in
                        .init(id: slice.id, label: slice.name, amount: slice.spent,
                              color: slice.isOther ? BudgetView.otherColor : Theme.categoryPalette[index])
                    },
                    total: summary.plannedSpending, height: 8
                )
                HStack(spacing: 12) {
                    ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(slice.isOther ? BudgetView.otherColor : Theme.categoryPalette[index]).frame(width: 8, height: 8)
                            Text(slice.name)
                        }
                    }
                    Spacer()
                    Text(perDay(left))
                }
                .font(.callout).foregroundStyle(Theme.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                label("Income")
                figure(summary.receivedIncome.wholeMoney(currency), color: Theme.text)
                let names = budget.income.flatMap(\.lines).filter { $0.actual > 0 }.map(\.name).joined(separator: ", ")
                Text(summary.plannedIncome > 0 ? "of \(summary.plannedIncome.wholeMoney(currency)) expected \u{00B7} \(names)" : names)
                    .foregroundStyle(Theme.secondary).lineLimit(2)
            }
            .padding(20)
            .frame(width: 205, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                label("Left to plan")
                figure(summary.leftToPlan.wholeMoney(currency), color: summary.leftToPlan < 0 ? Theme.negative : Theme.text)
                if summary.plannedIncome > 0, abs(summary.leftToPlan) < 0.5 {
                    Chip(text: "All income is budgeted", tint: Theme.positive, background: Theme.positiveTint)
                } else if summary.leftToPlan < 0 {
                    Chip(text: "Plans exceed income", tint: Theme.negative, background: Theme.negativeTint)
                }
            }
            .padding(20)
            .frame(width: 205, alignment: .leading)
        }
        .font(.body).monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.cardBorder))
        .shadow(color: Theme.cardShadow, radius: 1, y: 1)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.body.weight(.medium)).foregroundStyle(Theme.secondary)
    }

    private func figure(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 28, weight: .bold)).foregroundStyle(color)
    }
}

/// MacPlan.dc.html: groups and their categories with budgeted, spent, left, progress and the 3-month average.
/// Clicking a row selects it; the selected row's budgeted cell is a text field that saves on Return.
struct MacBudgetTable: View {
    let budget: BudgetMonth
    let currency: String
    let selected: String?
    let color: (String) -> Color
    let select: (String) -> Void
    /// Saves a budget cell and reports whether it worked.
    let save: (BudgetMonth.Line, Double?) async -> Bool
    let footer: (Double) -> String
    @State private var draft = ""
    /// Set while a cell's save is in flight, so a second Return doesn't send it again.
    @State private var saving = false
    @FocusState private var editing: Bool

    private static let columns: [CGFloat] = [100, 100, 100, 170, 110]

    var body: some View {
        VStack(spacing: 0) {
            row(
                Text("Category"), Text("Budgeted"), Text("Spent"), Text("Left"), Text("Progress"), Text("3-mo average"),
                progressAlignment: .leading
            )
            .font(.callout.weight(.medium)).foregroundStyle(Theme.secondary).frame(height: 32)
            Divider()
            ForEach(budget.spending.filter { group in
                group.lines.contains { ($0.budgeted ?? 0) > 0 || $0.actual > 0 }
            }) { group in
                groupRow(group)
                Divider()
                ForEach(group.lines.filter { ($0.budgeted ?? 0) > 0 || $0.actual > 0 }) { line in
                    lineRow(line, group: group)
                    Divider()
                }
            }
            totalRow
        }
        .font(.body).monospacedDigit()
        .padding(.vertical, 6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.cardBorder))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .shadow(color: Theme.cardShadow, radius: 1, y: 1)
        .onChange(of: selected, initial: true) { resetDraft() }
    }

    // swiftlint:disable:next function_parameter_count
    private func row(
        _ name: some View, _ budgeted: some View, _ spent: some View, _ left: some View, _ progress: some View, _ average: some View,
        progressAlignment: Alignment = .leading
    ) -> some View {
        HStack(spacing: 12) {
            name.frame(maxWidth: .infinity, alignment: .leading)
            budgeted.frame(width: Self.columns[0], alignment: .trailing)
            spent.frame(width: Self.columns[1], alignment: .trailing)
            left.frame(width: Self.columns[2], alignment: .trailing)
            progress.frame(width: Self.columns[3], alignment: progressAlignment).padding(.leading, 16)
            average.frame(width: Self.columns[4], alignment: .trailing)
        }
        .lineLimit(1)
        .padding(.horizontal, 20)
    }

    private func money(_ value: Double?) -> String { value.map { $0.wholeMoney(currency) } ?? "\u{2013}" }

    private func progress(_ spent: Double, _ budget: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            ProgressLine(value: budget > 0 ? spent / budget : 0, color: color, height: 6).frame(width: 120)
            Text(budget > 0 ? (spent / budget).formatted(.percent.precision(.fractionLength(0))) : "")
                .font(.callout.weight(.medium)).foregroundStyle(color == Theme.overBar ? Theme.negative : Theme.secondary)
        }
    }

    private func groupRow(_ group: BudgetMonth.Group) -> some View {
        let budgeted = group.budgeted ?? group.lines.compactMap(\.budgeted).reduce(0, +)
        let left = budgeted - group.actual
        return row(
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(color(group.name)).frame(width: 9, height: 9)
                Text(group.name)
            },
            Text(money(budgeted)), Text(group.actual.wholeMoney(currency)), Text(left.wholeMoney(currency)),
            progress(group.actual, budgeted, color: color(group.name)),
            Text(money(group.average3 ?? group.lines.compactMap(\.average3).reduce(0, +)))
        )
        .fontWeight(.semibold).foregroundStyle(Theme.text)
        .frame(height: 31)
        .background(Theme.page.opacity(0.6))
    }

    private func lineRow(_ line: BudgetMonth.Line, group: BudgetMonth.Group) -> some View {
        let budgeted = line.budgeted ?? 0
        let left = budgeted - line.actual
        let status = BudgetModel.lineStatus(spent: line.actual, budget: budgeted)
        let isSelected = line.key == selected
        let barColor: Color = status == .over ? Theme.overBar : status == .warn ? Theme.spendBar : color(group.name)
        let leftText: Text = if budgeted <= 0 {
            Text("\u{2013}").foregroundStyle(Theme.secondary)
        } else if status == .over {
            Text("\((-left).wholeMoney(currency)) over").fontWeight(.semibold).foregroundStyle(Theme.negative)
        } else if left == 0 {
            Text("Paid").fontWeight(.semibold).foregroundStyle(Theme.positive)
        } else {
            Text(left.wholeMoney(currency)).fontWeight(status == .warn ? .semibold : .regular)
                .foregroundStyle(status == .warn ? Theme.warning : Theme.text)
        }
        return row(
            Text(line.name).fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(status == .over ? Theme.negative : Theme.text).padding(.leading, 16),
            budgetCell(line, isSelected: isSelected),
            Text(line.actual.wholeMoney(currency)).foregroundStyle(status == .over ? Theme.negative : Theme.text),
            leftText,
            progress(line.actual, budgeted, color: barColor),
            Text(money(line.average3)).foregroundStyle(Theme.secondary)
        )
        .frame(height: 31)
        .background(isSelected ? Theme.accentTint : status == .over ? Theme.negativeTint : .clear)
        .overlay(alignment: .leading) { if isSelected { Theme.accent.frame(width: 3) } }
        .contentShape(Rectangle())
        .onTapGesture { select(line.key) }
    }

    @ViewBuilder
    private func budgetCell(_ line: BudgetMonth.Line, isSelected: Bool) -> some View {
        if isSelected {
            HStack(spacing: 4) {
                Text(currencySymbol).foregroundStyle(Theme.secondary)
                TextField("Budget", text: $draft)
                    .textFieldStyle(.plain).multilineTextAlignment(.trailing).focused($editing)
                    .onSubmit { Task { await commit(line) } }
                    .disabled(saving)
                    .accessibilityLabel("Budget for \(line.name)")
            }
            .fontWeight(.semibold)
            .padding(.horizontal, 7).frame(width: 76, height: 24)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.accent, lineWidth: 2))
        } else {
            Text(money(line.budgeted)).foregroundStyle(Theme.text)
        }
    }

    private var currencySymbol: String {
        Locale(identifier: Locale.identifier(fromComponents: [NSLocale.Key.currencyCode.rawValue: currency])).currencySymbol ?? currency
    }

    private var selectedLine: BudgetMonth.Line? { budget.spending.flatMap(\.lines).first { $0.key == selected } }

    private func resetDraft() {
        draft = selectedLine?.budgeted.map { BudgetModel.draft($0) } ?? ""
    }

    /// An empty field clears the budget; text that is not a number leaves it as it was. A failed save puts the
    /// saved amount back in the field.
    private func commit(_ line: BudgetMonth.Line) async {
        guard !saving else { return }
        let text = draft.trimmingCharacters(in: .whitespaces)
        let amount: Double?
        if text.isEmpty {
            guard line.budgeted != nil else { return }
            amount = nil
        } else {
            guard let parsed = BudgetModel.amount(text) else { resetDraft(); return }
            guard parsed != line.budgeted else { return }
            amount = parsed
        }
        saving = true
        let saved = await save(line, amount)
        saving = false
        if !saved { resetDraft() }
    }

    private var totalRow: some View {
        let summary = budget.summary
        let left = summary.plannedSpending - summary.spent
        let average = budget.spending.flatMap(\.lines).compactMap(\.average3).reduce(0, +)
        let share = summary.plannedSpending > 0 ? summary.spent / summary.plannedSpending : 0
        let days = footer(left).prefix { $0 != "\u{00B7}" }.trimmingCharacters(in: .whitespaces)
        return row(
            Text("Total"), Text(summary.plannedSpending.wholeMoney(currency)), Text(summary.spent.wholeMoney(currency)),
            Text(left.wholeMoney(currency)),
            Text("\(share.formatted(.percent.precision(.fractionLength(0)))) spent \u{00B7} \(days) left")
                .fontWeight(.regular).foregroundStyle(Theme.secondary),
            Text(average.wholeMoney(currency))
        )
        .fontWeight(.bold).foregroundStyle(Theme.text)
        .frame(height: 36)
    }
}
#endif
