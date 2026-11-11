#if os(macOS)
import SwiftUI

/// MacStatement.dc.html: four totals over a table with one column per month (or quarter) and a total column.
/// The running month's column reads "Nov so far" and its savings rate is left out.
struct MacStatementTable: View {
    let view: StatementView
    let statement: StatementView.Statement

    private var currency: String { view.currency }
    /// The space the table has, measured, so month columns share it down to a minimum and then scroll sideways.
    @State private var available: CGFloat = 1100

    private static let nameWidth: CGFloat = 150
    private static let totalWidth: CGFloat = 100
    private static let minimumCell: CGFloat = 84

    private var cellWidth: CGFloat {
        let count = CGFloat(max(statement.columns.count, 1))
        return max(Self.minimumCell, (available - Self.nameWidth - Self.totalWidth - 40) / count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(view.rangeText) \u{00B7} \(currency)").font(.body).foregroundStyle(Theme.secondary).monospacedDigit()
                if view.isCustom {
                    view.customPickers.frame(maxWidth: 420)
                }
                kpis
                ScrollView(.horizontal) { table }
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
                Text("Transfers between your accounts are left out.").foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
    }

    // MARK: Totals

    private var kpis: some View {
        let income = statement.totalIncome
        let expenses = statement.totalExpenses
        let net = income - expenses
        let rate = StatementModel.savingsRate(income: income, expenses: expenses)
        let top = statement.income.flatMap(\.lines).max { $0.total < $1.total }
        let fullMonths = statement.months.filter { $0 != BudgetModel.monthKey(Fixtures.today) }.count
        return HStack(spacing: 14) {
            kpi("Income", MoneyText.format(income, currency: currency, signed: true, cents: false), Theme.positive,
                detail: top.map { "\($0.name) \((income > 0 ? $0.total / income : 0).formatted(.percent.precision(.fractionLength(0))))" })
            kpi("Expenses", MoneyText.format(-expenses, currency: currency, cents: false), Theme.text,
                detail: fullMonths > 0 ? "\((expenses / Double(statement.months.count)).wholeMoney(currency)) a month" : nil)
            kpi("Net savings", MoneyText.format(net, currency: currency, signed: true, cents: false),
                net >= 0 ? Theme.positive : Theme.negative,
                detail: "Since \(view.bounds.start.formatted(.dateTime.month(.abbreviated).day()))")
            kpi("Savings rate", rate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "\u{2013}", Theme.text,
                detail: "Of income saved")
        }
    }

    private func kpi(_ label: String, _ value: String, _ color: Color, detail: String?) -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label).font(.body.weight(.medium)).foregroundStyle(Theme.secondary)
                    Spacer()
                    if let detail { Text(detail).foregroundStyle(Theme.secondary).lineLimit(1) }
                }
                Text(value).font(.system(size: 22, weight: .bold)).foregroundStyle(color).monospacedDigit()
            }
        }
    }

    // MARK: Table

    private var table: some View {
        let columns = statement.columns
        return VStack(spacing: 0) {
            row(Text("Category"), columns.map { column in
                Text(column.isPartial ? "\(column.label) so far" : column.label)
            }, total: Text("Total"))
            .font(.callout.weight(.medium)).foregroundStyle(Theme.secondary).frame(height: 32)
            Divider()
            groupRow("Income", indent: 0, values: columns.map { statement.income(in: $0) }, total: statement.totalIncome, bold: true)
            ForEach(statement.income.flatMap(\.lines)) { line in lineRow(line) }
            groupRow("Expenses", indent: 0, values: columns.map { statement.expenses(in: $0) }, total: statement.totalExpenses, bold: true)
            ForEach(statement.expenses) { group in
                groupRow(group.name, indent: 6, values: columns.map { group.value(in: $0) }, total: group.total, bold: false)
                ForEach(group.lines) { line in lineRow(line) }
            }
            Divider().overlay(Theme.text.opacity(0.4))
            netRow
            rateRow
        }
        .font(.body).monospacedDigit()
        .padding(.vertical, 8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.cardBorder))
        .shadow(color: Theme.cardShadow, radius: 1, y: 1)
    }

    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }

    private func row(_ name: some View, _ cells: [some View], total: some View) -> some View {
        HStack(spacing: 0) {
            name.frame(width: Self.nameWidth, alignment: .leading)
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                cell.frame(width: cellWidth, alignment: .trailing)
            }
            total.frame(width: Self.totalWidth - 8, alignment: .trailing).padding(.trailing, 8)
                .frame(maxHeight: .infinity).background(Theme.page.opacity(0.7))
        }
        .lineLimit(1)
        .padding(.leading, 20).padding(.trailing, 12)
    }

    private func groupRow(_ name: String, indent: CGFloat, values: [Double], total: Double, bold: Bool) -> some View {
        row(Text(name).padding(.leading, indent), values.map { Text(number($0)) }, total: Text(number(total)))
            .fontWeight(bold ? .bold : .semibold).foregroundStyle(Theme.text)
            .frame(height: 29)
            .background(bold ? Theme.page.opacity(0.6) : .clear)
            .overlay(alignment: .bottom) { Divider() }
    }

    private func lineRow(_ line: StatementLine) -> some View {
        row(Text(line.name).padding(.leading, 20), statement.columns.map { Text(number(line.value(in: $0))) },
            total: Text(number(line.total)).fontWeight(.semibold))
            .foregroundStyle(Theme.text)
            .frame(height: 29)
            .overlay(alignment: .bottom) { Divider() }
    }

    private var netRow: some View {
        let nets = statement.columns.map { statement.income(in: $0) - statement.expenses(in: $0) }
        let total = statement.totalIncome - statement.totalExpenses
        func cell(_ value: Double) -> some View {
            Text((value > 0 ? "+" : "") + number(value)).foregroundStyle(value >= 0 ? Theme.positive : Theme.negative)
        }
        return row(Text("Net").foregroundStyle(Theme.text), nets.map(cell), total: cell(total))
            .fontWeight(.bold).frame(height: 32)
    }

    /// The running month's rate is a dash: a part month's income often hasn't arrived yet.
    private var rateRow: some View {
        let percent = FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength(0))
        let rates = statement.columns.map { column -> Text in
            guard !column.isPartial,
                  let rate = StatementModel.savingsRate(income: statement.income(in: column), expenses: statement.expenses(in: column))
            else { return Text("\u{2013}").foregroundStyle(Theme.secondary.opacity(0.6)) }
            return Text(rate.formatted(percent)).foregroundStyle(Theme.secondary)
        }
        let total = StatementModel.savingsRate(income: statement.totalIncome, expenses: statement.totalExpenses)
        return row(Text("Savings rate").foregroundStyle(Theme.secondary), rates,
                   total: Text(total.map { $0.formatted(percent) } ?? "\u{2013}").fontWeight(.bold).foregroundStyle(Theme.text))
            .frame(height: 30)
    }
}
#endif
