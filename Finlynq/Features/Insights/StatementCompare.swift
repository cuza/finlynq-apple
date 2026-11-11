import Charts
import SwiftUI

/// iPad portrait (iPadPStatement.dc.html): the range's net savings over a chart of every column, then one month or
/// quarter set against the range's total, category by category.
struct StatementCompare: View {
    let view: StatementView
    let statement: StatementView.Statement
    @Binding var quarterly: Bool
    @Binding var range: StatementView.Range
    @Binding var compared: String?
    /// Read so the amount columns are measured again when the text size changes.
    @Environment(\.dynamicTypeSize) private var typeSize

    private var column: StatementModel.Column? {
        statement.columns.first { $0.id == compared } ?? StatementModel.defaultColumn(statement.columns)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SegmentBar("Range", options: [(StatementView.Range.thisYear, "This year"), (.lastYear, "Last year"), (.custom, "Custom")],
                           selection: $range)
                if range == .custom { Card(padding: 12) { view.customPickers } }
                summary
                if statement.income.isEmpty && statement.expenses.isEmpty {
                    EmptyState(title: "Nothing in this range", message: "No income or expenses between these dates.", symbol: "doc.text")
                } else if let column {
                    Text("Compare a \(quarterly ? "quarter" : "month") with the \(rangeName)")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary).padding(.horizontal, 4).padding(.top, 8)
                    SegmentBar("Columns", options: [(false, "Month"), (true, "Quarter")], selection: $quarterly)
                    columnPicker(column)
                    table(column)
                    Text("Transfers between your accounts are left out.").font(.footnote).foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
    }

    private var rangeName: String { range == .custom ? "range" : "year" }

    /// "2026 total", or "Total" for a custom range.
    private var totalTitle: String { StatementModel.totalTitle(custom: range == .custom, start: view.bounds.start) }

    /// A segment per column; a menu when they don't fit, such as a long custom range.
    private func columnPicker(_ column: StatementModel.Column) -> some View {
        let selection = Binding { column.id } set: { compared = $0 }
        let picker = Picker(quarterly ? "Quarter" : "Month", selection: selection) {
            ForEach(statement.columns) { Text($0.label).tag($0.id) }
        }
        return ViewThatFits(in: .horizontal) {
            picker.pickerStyle(.segmented).labelsHidden().fixedSize()
            picker.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Summary

    private var summary: some View {
        let currency = view.currency
        let net = statement.totalIncome - statement.totalExpenses
        let rate = StatementModel.savingsRate(income: statement.totalIncome, expenses: statement.totalExpenses)
        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Net savings").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text("\(view.rangeText) \u{00B7} \(currency)").font(.footnote).foregroundStyle(Theme.secondary).monospacedDigit()
                }
                Text(MoneyText.format(net, currency: currency, signed: true, cents: false)).font(.system(size: 36, weight: .bold))
                    .foregroundStyle(net >= 0 ? Theme.text : Theme.negative).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                if let rate {
                    Chip(text: "Saved \(rate.formatted(.percent.precision(.fractionLength(0)))) of income",
                         tint: rate >= 0 ? Theme.positive : Theme.negative,
                         background: rate >= 0 ? Theme.positiveTint : Theme.negativeTint)
                }
                Divider().padding(.vertical, 2)
                HStack(alignment: .top) {
                    let income = MoneyText.format(statement.totalIncome, currency: currency, signed: true, cents: false)
                    figure("Income", income, Theme.positive)
                    figure("Expenses", MoneyText.format(-statement.totalExpenses, currency: currency, cents: false), Theme.text)
                }
                chart
                HStack(spacing: 14) {
                    swatch(Theme.positiveBar, "Income")
                    swatch(Theme.spendBar, "Expenses")
                }
                .font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
    }

    /// Every column's income and expenses; the compared one is drawn solid.
    private var chart: some View {
        let selected = column?.id
        return Chart {
            ForEach(statement.columns) { column in
                let opacity = column.id == selected ? 1 : 0.45
                BarMark(x: .value("Period", column.id), y: .value("Amount", statement.income(in: column)), width: .ratio(0.75))
                    .foregroundStyle(Theme.positiveBar.opacity(opacity)).position(by: .value("Kind", "Income"))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                BarMark(x: .value("Period", column.id), y: .value("Amount", statement.expenses(in: column)), width: .ratio(0.75))
                    .foregroundStyle(Theme.spendBar.opacity(opacity)).position(by: .value("Kind", "Expenses"))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .chartXAxis {
            AxisMarks(values: statement.columns.map(\.id)) { value in
                AxisValueLabel {
                    let id = value.as(String.self)
                    Text(statement.columns.first { $0.id == id }?.label ?? "")
                        .fontWeight(id == selected ? .bold : .regular)
                        .foregroundStyle(id == selected ? Theme.accent : Theme.secondary)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.fill)
                AxisValueLabel { Text((value.as(Double.self) ?? 0).compactMoney(view.currency)) }
            }
        }
        .barSelection(
            labels: statement.columns.map(\.id),
            tops: statement.columns.map { max(statement.income(in: $0), statement.expenses(in: $0)) }
        ) { index in
            let column = statement.columns[index]
            return [column.title, "Income \(statement.income(in: column).wholeMoney(view.currency))",
                    "Expenses \(statement.expenses(in: column).wholeMoney(view.currency))"]
        }
        .frame(height: 140)
        .accessibilityLabel("Income and expenses by period")
    }

    private func figure(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote).foregroundStyle(Theme.secondary)
            Text(value).font(.title3.weight(.bold)).foregroundStyle(color).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8); Text(label) }
    }

    // MARK: Table

    private func table(_ column: StatementModel.Column) -> some View {
        let rows = StatementModel.compareRows(income: statement.income, expenses: statement.expenses, column: column)
        let currency = view.currency
        let text = { (amount: Double) in StatementModel.compareText(amount, currency: currency) }
        // Each amount column is as wide as its widest figure, so the figures line up and never wrap.
        let valueWidth = rows.map { TextWidth.of(text($0.value), style: .subheadline, bold: true) }.max() ?? 0
        let totalWidth = rows.map { TextWidth.of(text($0.total), style: .subheadline, bold: true) }.max() ?? 0
        let widths = (max(valueWidth, TextWidth.of(column.label, style: .footnote, bold: true)) + 2,
                      max(totalWidth, TextWidth.of(totalTitle, style: .footnote)) + 2)
        return Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Text("Category").frame(maxWidth: .infinity, alignment: .leading)
                    Text(column.label + (column.isPartial ? " so far" : "")).fontWeight(.semibold).foregroundStyle(Theme.accent)
                        .frame(minWidth: widths.0, alignment: .trailing).fixedSize()
                    Text(totalTitle).frame(width: widths.1, alignment: .trailing)
                }
                .font(.footnote).foregroundStyle(Theme.secondary).lineLimit(1)
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 10)
                ForEach(rows) { row in
                    Divider()
                    tableRow(row, value: text(row.value), total: text(row.total), widths: widths)
                }
            }
        }
    }

    private func tableRow(_ row: StatementModel.CompareRow, value: String, total: String, widths: (CGFloat, CGFloat)) -> some View {
        let bold = row.kind != .line
        let color = { (amount: Double) -> Color in
            switch StatementModel.compareTone(amount) {
            case .zero: Theme.secondary
            case .moneyIn: Theme.positive
            case .moneyOut: Theme.text
            }
        }
        return HStack(spacing: 16) {
            Text(row.name).fontWeight(bold ? .semibold : .regular).foregroundStyle(Theme.text).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, row.kind == .line ? 14 : 0)
            Text(value).foregroundStyle(color(row.value)).frame(minWidth: widths.0, alignment: .trailing)
            Text(total).foregroundStyle(color(row.total)).frame(width: widths.1, alignment: .trailing)
        }
        .font(.subheadline.weight(bold ? .semibold : .regular)).monospacedDigit().lineLimit(1)
        .padding(.horizontal, 18).padding(.vertical, 11)
        .background(row.kind == .section ? Theme.page.opacity(0.7) : .clear)
        .accessibilityElement(children: .combine)
    }
}
