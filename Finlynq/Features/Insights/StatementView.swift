import Charts
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// The income statement (Statement.dc.html on iPhone and iPad landscape, iPadPStatement.dc.html on iPad portrait,
/// MacStatement.dc.html on the Mac): income and expenses by category for a year or a custom range, by month or
/// quarter. iPad portrait sets one month or quarter against the range's total. The running month is "so far": it is drawn
/// lighter and its savings rate is left out, since a part month reads as an alarming negative rate.
struct StatementView: View {
    enum Range: Hashable { case thisYear, lastYear, custom }

    @Environment(Session.self) private var session
    @Environment(\.layoutWidth) private var width
    @Environment(\.layoutColumn) private var column
    /// The month or quarter iPad portrait compares with the range, by column id. Nil is the latest full one.
    @State private var compared: String?
    @State private var range = Range.thisYear
    @State private var quarterly = false
    @State private var customStart = Calendar(identifier: .gregorian).date(byAdding: .month, value: -5, to: Fixtures.today)
        ?? Fixtures.today
    @State private var customEnd = Fixtures.today
    @State private var expanded: String?
    @State private var exporting: CSVExport?

    private static let calendar = Calendar(identifier: .gregorian)
    private var today: Date { Fixtures.today }
    var currency: String { session.currency }

    /// The range's first and last day. "This year" ends today.
    var bounds: (start: Date, end: Date) {
        let year = Self.calendar.component(.year, from: today)
        func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
            Self.calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? today
        }
        switch range {
        case .thisYear: return (day(year, 1, 1), today)
        case .lastYear: return (day(year - 1, 1, 1), day(year - 1, 12, 31))
        case .custom: return (customStart, customEnd)
        }
    }

    /// Everything the screen shows, built from the trends response.
    struct Statement {
        let months: [String]
        let columns: [StatementModel.Column]
        let income: [StatementGroup]
        let expenses: [StatementGroup]
        var totalIncome: Double { income.reduce(0) { $0 + $1.total } }
        var totalExpenses: Double { expenses.reduce(0) { $0 + $1.total } }
        func income(in column: StatementModel.Column) -> Double { income.reduce(0) { $0 + $1.value(in: column) } }
        func expenses(in column: StatementModel.Column) -> Double { expenses.reduce(0) { $0 + $1.value(in: column) } }
    }

    private func statement(_ trends: Trends) -> Statement {
        let months = StatementModel.months(from: bounds.start, to: bounds.end)
        return Statement(
            months: months, columns: StatementModel.columns(months, quarterly: quarterly, today: today),
            income: StatementModel.rows(from: trends.income, months: months),
            expenses: StatementModel.rows(from: trends.expenses, months: months)
        )
    }

    var body: some View {
        let bounds = bounds
        Reloader(id: "\(APIDate.string(bounds.start))|\(APIDate.string(bounds.end))|\(session.revision)", source: "statement") {
            try await session.api.trends(from: APIDate.string(bounds.start), to: APIDate.string(bounds.end))
        } content: { trends in
            let statement = statement(trends)
            #if os(macOS)
            Group {
                if macDesign { MacStatementTable(view: self, statement: statement) } else { narrow(statement) }
            }
            .toolbar { macToolbar(statement) }
            .fileExporter(
                isPresented: Binding { exporting != nil } set: { if !$0 { exporting = nil } },
                document: exporting.map { CSVFile(text: $0.text) }, contentType: .commaSeparatedText,
                defaultFilename: exporting?.name
            ) { _ in exporting = nil }
            #else
            narrow(statement)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: export(statement), preview: SharePreview(export(statement).name)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Export as CSV")
                    }
                }
            #endif
        }
        .background(Theme.page)
        .navigationTitle("Income statement")
        #if os(iOS)
        .toolbarTitleDisplayMode(.large)
        #endif
    }

    func export(_ statement: Statement) -> CSVExport {
        let name = "Finlynq income statement \(APIDate.string(bounds.start)) to \(APIDate.string(bounds.end)).csv"
        return CSVExport(name: name, text: StatementModel.csv(income: statement.income, expenses: statement.expenses,
                                                              columns: statement.columns))
    }

    var isCustom: Bool { range == .custom }

    var rangeText: String {
        let (start, end) = bounds
        let sameYear = Self.calendar.component(.year, from: start) == Self.calendar.component(.year, from: end)
        let first = start.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
        return "\(first) to \(end.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    var customPickers: some View {
        HStack {
            DatePicker("From", selection: $customStart, in: ...customEnd, displayedComponents: .date)
            DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
        }
        .font(.subheadline)
    }

    #if os(macOS)
    /// MacStatement's four totals and month columns need about 1100pt; narrower windows get the iPad layouts.
    private var macDesign: Bool { LayoutWidth.fitsMacDesign(width, column: column, needs: MacDesignWidth.statement) }

    @ToolbarContentBuilder
    private func macToolbar(_ statement: Statement) -> some ToolbarContent {
        // Narrower windows have the range and columns in the content.
        if macDesign {
            ToolbarItem(placement: .primaryAction) {
                Picker("Range", selection: $range) {
                    Text("This year").tag(Range.thisYear)
                    Text("Last year").tag(Range.lastYear)
                    Text("Custom").tag(Range.custom)
                }
                .labelsHidden().fixedSize()
            }
            ToolbarItem(placement: .primaryAction) {
                SegmentBar("Columns", options: [(false, "Month"), (true, "Quarter")], selection: $quarterly).fixedSize()
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Export CSV", systemImage: "square.and.arrow.down") { exporting = export(statement) }.macTitleAndIcon()
        }
    }
    #endif

    // MARK: iPhone and iPad, and narrower Mac windows

    @ViewBuilder
    private func narrow(_ statement: Statement) -> some View {
        if width == .medium {
            StatementCompare(view: self, statement: statement, quarterly: $quarterly, range: $range, compared: $compared)
        } else {
            list(statement)
        }
    }

    private func list(_ statement: Statement) -> some View {
        let wide = width != .compact
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    FilterChip(title: "This year", active: range == .thisYear) { range = .thisYear }
                    FilterChip(title: "Last year", active: range == .lastYear) { range = .lastYear }
                    FilterChip(title: "Custom", active: range == .custom) { range = .custom }
                }
                HStack {
                    Text(rangeText).font(.subheadline).foregroundStyle(Theme.secondary).monospacedDigit()
                    Spacer()
                    SegmentBar("Columns", options: [(false, "Month"), (true, "Quarter")], selection: $quarterly).fixedSize()
                }
                if range == .custom { Card(padding: 12) { customPickers } }
                StatementSummaryCard(view: self, statement: statement)
                if statement.income.isEmpty && statement.expenses.isEmpty {
                    EmptyState(title: "Nothing in this range", message: "No income or expenses between these dates.", symbol: "doc.text")
                } else {
                    section("Income", total: statement.totalIncome, sign: 1)
                    linesCard(statement.income.flatMap(\.lines), share: statement.totalIncome, of: "income", statement: statement,
                              color: { _ in Theme.positiveBar }, sign: 1)
                    section("Expenses", total: statement.totalExpenses, sign: -1).padding(.top, 8)
                    ForEach(Array(statement.expenses.enumerated()), id: \.element.id) { index, group in
                        let color = index < 4 ? Theme.categoryPalette[index] : Theme.categoryPalette[4]
                        HStack {
                            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
                            let share = statement.totalExpenses > 0 ? group.total / statement.totalExpenses : 0
                            Text("\(group.name) \u{00B7} \(share.formatted(.percent.precision(.fractionLength(0))))")
                            Spacer()
                            Text(MoneyText.format(-group.total, currency: currency, cents: false))
                        }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary).monospacedDigit()
                        .padding(.horizontal, 4).padding(.top, 4)
                        linesCard(group.lines, share: statement.totalExpenses, of: "expenses", statement: statement,
                                  color: { _ in color }, sign: -1)
                    }
                    Text("Transfers between your accounts are left out.").font(.footnote).foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, wide ? 28 : 20).padding(.bottom, 24)
            .frame(maxWidth: wide ? 720 : .infinity)
            .frame(maxWidth: .infinity)
        }
    }

    private func section(_ title: String, total: Double, sign: Double) -> some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(Theme.text)
            Spacer()
            Text(MoneyText.format(sign * total, currency: currency, signed: true, cents: false)).font(.headline).monospacedDigit()
                .foregroundStyle(sign > 0 ? Theme.positive : Theme.text)
        }
        .padding(.horizontal, 4)
    }

    // swiftlint:disable:next function_parameter_count
    private func linesCard(
        _ lines: [StatementLine], share total: Double, of kind: String, statement: Statement,
        color: @escaping (StatementLine) -> Color, sign: Double
    ) -> some View {
        Card(padding: 16) {
            DividedRows(items: lines) { line in
                VStack(spacing: 0) {
                    Button { withAnimation { expanded = expanded == line.id ? nil : line.id } } label: {
                        lineRow(line, total: total, kind: kind, statement: statement, color: color(line), sign: sign)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the amount by month")
                    if expanded == line.id {
                        StatementLineChart(line: line, columns: statement.columns, color: color(line), currency: currency, sign: sign)
                            .padding(.bottom, 12)
                    }
                }
            }
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func lineRow(
        _ line: StatementLine, total: Double, kind: String, statement: Statement, color: Color, sign: Double
    ) -> some View {
        let icon = Icons.category(line.name)
        let share = total > 0 ? line.total / total : 0
        let shareText = share < 0.01 ? "<1%" : share.formatted(.percent.precision(.fractionLength(0)))
        return HStack(spacing: 12) {
            IconTile(symbol: icon.0, tint: icon.1, background: icon.1.opacity(0.14), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text("\(shareText) of \(kind)").font(.subheadline).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Sparkline(values: statement.columns.map { line.value(in: $0) }, partial: statement.columns.map(\.isPartial), color: color)
                .frame(width: 44, height: 20)
            Text(MoneyText.format(sign * line.total, currency: currency, signed: sign > 0, cents: false))
                .font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(sign > 0 ? Theme.positive : Theme.text)
                .lineLimit(1).fixedSize()
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

/// Net savings, income, expenses and the savings rate, over a chart of income and expenses per column.
private struct StatementSummaryCard: View {
    let view: StatementView
    let statement: StatementView.Statement

    var body: some View {
        let currency = view.currency
        let net = statement.totalIncome - statement.totalExpenses
        let rate = StatementModel.savingsRate(income: statement.totalIncome, expenses: statement.totalExpenses)
        let partial = statement.columns.last { $0.isPartial }
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Net savings").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                        Text(MoneyText.format(net, currency: currency, cents: false)).font(.system(size: 32, weight: .bold))
                            .foregroundStyle(net >= 0 ? Theme.text : Theme.negative).monospacedDigit()
                    }
                    Spacer()
                    if let rate {
                        Chip(text: "Saved \(rate.formatted(.percent.precision(.fractionLength(0))))",
                             tint: rate >= 0 ? Theme.positive : Theme.negative,
                             background: rate >= 0 ? Theme.positiveTint : Theme.negativeTint)
                    }
                }
                HStack(alignment: .top) {
                    let income = MoneyText.format(statement.totalIncome, currency: currency, signed: true, cents: false)
                    figure("Income", income, Theme.positive)
                    figure("Expenses", MoneyText.format(-statement.totalExpenses, currency: currency, cents: false), Theme.text)
                    figure("Savings rate", rate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "\u{2013}", Theme.text)
                }
                Divider()
                HStack(spacing: 12) {
                    swatch(Theme.positiveBar, "Income")
                    swatch(Theme.spendBar, "Expenses")
                    Spacer()
                    if let partial, let month = partial.months.last {
                        Text("\(StatementModel.date(ofMonth: month).formatted(.dateTime.month(.wide))) so far")
                    }
                }
                .font(.footnote).foregroundStyle(Theme.secondary)
                Chart {
                    ForEach(statement.columns) { column in
                        let opacity = column.isPartial ? 0.45 : 1
                        BarMark(x: .value("Period", column.id), y: .value("Amount", statement.income(in: column)), width: .ratio(0.75))
                            .foregroundStyle(Theme.positiveBar.opacity(opacity)).position(by: .value("Kind", "Income"))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        BarMark(x: .value("Period", column.id), y: .value("Amount", statement.expenses(in: column)), width: .ratio(0.75))
                            .foregroundStyle(Theme.spendBar.opacity(opacity)).position(by: .value("Kind", "Expenses"))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: statement.columns.map(\.id)) { value in
                        AxisValueLabel {
                            let column = statement.columns.first { $0.id == value.as(String.self) }
                            Text(column.map { $0.label.hasPrefix("Q") ? $0.label : String($0.label.prefix(1)) } ?? "")
                        }
                    }
                }
                .barSelection(
                    labels: statement.columns.map(\.id),
                    tops: statement.columns.map { max(statement.income(in: $0), statement.expenses(in: $0)) }
                ) { index in
                    let column = statement.columns[index]
                    return [column.title, "Income \(statement.income(in: column).wholeMoney(currency))",
                            "Expenses \(statement.expenses(in: column).wholeMoney(currency))"]
                }
                .frame(height: 96)
                .accessibilityLabel("Income and expenses by period")
            }
        }
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
}

/// Tiny bars, one per column. A part month is lighter.
struct Sparkline: View {
    let values: [Double]
    let partial: [Bool]
    let color: Color

    var body: some View {
        let top = max(values.map(abs).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color.opacity(partial.indices.contains(index) && partial[index] ? 0.4 : 1))
                    .frame(height: max(1.5, 20 * abs(value) / top))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A line's amount per column, with its average and highest, shown when the line is tapped.
private struct StatementLineChart: View {
    let line: StatementLine
    let columns: [StatementModel.Column]
    let color: Color
    let currency: String
    /// 1 for income, -1 for expenses, as in the rows.
    let sign: Double

    var body: some View {
        let full = columns.filter { !$0.isPartial }
        let values = full.map { line.value(in: $0) }
        let average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let highest = zip(full, values).max { $0.1 < $1.1 }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(columns.first.map { $0.months.count > 1 } == true ? "By quarter" : "By month")
                Spacer()
                let avg = Text(average.wholeMoney(currency)).fontWeight(.semibold).foregroundStyle(Theme.text)
                Text("Avg \(avg) a \(columns.first.map { $0.months.count > 1 } == true ? "quarter" : "month")")
            }
            .font(.footnote).foregroundStyle(Theme.secondary)
            Chart {
                ForEach(columns) { column in
                    BarMark(x: .value("Period", column.id), y: .value("Amount", line.value(in: column)), width: .ratio(0.7))
                        .foregroundStyle(color.opacity(column.isPartial ? 0.4 : column.id == highest?.0.id ? 1 : 0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                if average > 0 {
                    RuleMark(y: .value("Average", average)).foregroundStyle(Theme.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: columns.map(\.id)) { value in
                    AxisValueLabel {
                        let column = columns.first { $0.id == value.as(String.self) }
                        Text(column.map { $0.label.hasPrefix("Q") ? $0.label : String($0.label.prefix(1)) } ?? "")
                    }
                }
            }
            .barSelection(labels: columns.map(\.id), tops: columns.map { line.value(in: $0) }) { index in
                [columns[index].title,
                 MoneyText.format(sign * line.value(in: columns[index]), currency: currency, signed: sign > 0, cents: false)]
            }
            .frame(height: 80)
            if let highest {
                Text("Highest: \(highest.0.label) at \(highest.1.wholeMoney(currency))").font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
        .padding(12)
        .background(Theme.page, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
