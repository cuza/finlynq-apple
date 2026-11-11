import Foundation

/// One category in the income statement, with its amount for each month in range.
nonisolated struct StatementLine: Identifiable, Hashable {
    let id: String
    let categoryId: Int?
    let name: String
    /// Amount per `YYYY-MM`, in range only.
    let byMonth: [String: Double]
    /// Amounts in month order, aligned with the statement's months.
    let values: [Double]
    var total: Double { values.reduce(0, +) }

    func value(in column: StatementModel.Column) -> Double { column.months.reduce(0) { $0 + (byMonth[$1] ?? 0) } }
}

/// A category group ("Housing", "Food") and its lines, largest first.
nonisolated struct StatementGroup: Identifiable, Hashable {
    let name: String
    let lines: [StatementLine]
    var id: String { name }
    var total: Double { lines.reduce(0) { $0 + $1.total } }

    func value(in column: StatementModel.Column) -> Double { lines.reduce(0) { $0 + $1.value(in: column) } }
}

/// Income statement figures. The server's trends route gives a value per category per month; quarters and
/// ranges are built here from those months.
nonisolated enum StatementModel {
    /// A table column: one month, or a quarter of up to three months.
    struct Column: Identifiable, Hashable {
        let label: String
        let months: [String]
        /// Holds today, so the figures are "so far".
        let isPartial: Bool
        var id: String { months.first ?? label }
        /// "November 2026", or "Q3 2026" for a quarter: the chart tooltip's title.
        var title: String {
            let date = StatementModel.date(ofMonth: id)
            return months.count > 1 || label.hasPrefix("Q")
                ? "\(label) \(date.formatted(.dateTime.year()))" : StatementModel.monthTitle(id)
        }
    }

    private static let calendar = Calendar(identifier: .gregorian)

    /// True when `month` is today's month, which is still running.
    static func isPartial(month: Date, today: Date) -> Bool {
        calendar.isDate(month, equalTo: today, toGranularity: .month)
    }

    /// `YYYY-MM` keys from `start`'s month through `end`'s month.
    static func months(from start: Date, to end: Date) -> [String] {
        guard var month = calendar.dateInterval(of: .month, for: start)?.start else { return [] }
        var keys: [String] = []
        while month <= end, keys.count < 240 {
            keys.append(BudgetModel.monthKey(month))
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return keys
    }

    static func date(ofMonth key: String) -> Date { APIDate.parse(key + "-01") ?? .distantPast }
    /// "November 2026" for "2026-11".
    static func monthTitle(_ key: String) -> String { date(ofMonth: key).formatted(.dateTime.month(.wide).year()) }

    /// One column per month ("Jan"), or per calendar quarter ("Q1") when `quarterly`.
    static func columns(_ months: [String], quarterly: Bool, today: Date) -> [Column] {
        let partial = BudgetModel.monthKey(today)
        guard quarterly else {
            return months.map { key in
                Column(label: date(ofMonth: key).formatted(.dateTime.month(.abbreviated)), months: [key], isPartial: key == partial)
            }
        }
        var columns: [Column] = []
        for key in months {
            let month = calendar.component(.month, from: date(ofMonth: key))
            let label = "Q\((month - 1) / 3 + 1)"
            if let last = columns.last, last.label == label, last.months.count < 3,
               let first = last.months.first, first.prefix(4) == key.prefix(4) {
                columns[columns.count - 1] = Column(label: label, months: last.months + [key], isPartial: last.isPartial || key == partial)
            } else {
                columns.append(Column(label: label, months: [key], isPartial: key == partial))
            }
        }
        return columns
    }

    /// Lines grouped by category group, groups and lines largest first. Lines with nothing in range are left out.
    static func rows(from lines: [Trends.Line], months: [String]) -> [StatementGroup] {
        let inRange = Set(months)
        let statementLines = lines.compactMap { line -> (String, StatementLine)? in
            let byMonth = line.periods.filter { inRange.contains($0.key) }
            let row = StatementLine(
                id: line.id, categoryId: line.categoryId, name: line.name, byMonth: byMonth, values: months.map { byMonth[$0] ?? 0 }
            )
            return abs(row.total) > 0.005 ? (line.group ?? "Other", row) : nil
        }
        return Dictionary(grouping: statementLines, by: \.0)
            .map { StatementGroup(name: $0.key, lines: $0.value.map(\.1).sorted { $0.total > $1.total }) }
            .sorted { $0.total > $1.total }
    }

    /// One row of the table that sets a month or quarter against the whole range (iPadPStatement.dc.html).
    /// Amounts are signed: income positive, expenses negative.
    enum CompareKind { case section, group, line }

    struct CompareRow: Identifiable, Hashable {
        let id: String
        let kind: CompareKind
        let name: String
        let value: Double
        let total: Double
    }

    /// Income, then its categories; Expenses, then each group and its categories. Groups and lines keep their order.
    static func compareRows(income: [StatementGroup], expenses: [StatementGroup], column: Column) -> [CompareRow] {
        var rows: [CompareRow] = []
        if !income.isEmpty {
            rows.append(CompareRow(id: "income", kind: .section, name: "Income", value: income.reduce(0) { $0 + $1.value(in: column) },
                                   total: income.reduce(0) { $0 + $1.total }))
            let lines = income.flatMap(\.lines).sorted { $0.total > $1.total }
            rows += lines.map { CompareRow(id: "i-\($0.id)", kind: .line, name: $0.name, value: $0.value(in: column), total: $0.total) }
        }
        if !expenses.isEmpty {
            rows.append(CompareRow(id: "expenses", kind: .section, name: "Expenses",
                                   value: -expenses.reduce(0) { $0 + $1.value(in: column) }, total: -expenses.reduce(0) { $0 + $1.total }))
            for group in expenses {
                rows.append(CompareRow(id: "g-\(group.id)", kind: .group, name: group.name, value: -group.value(in: column),
                                       total: -group.total))
                rows += group.lines.map {
                    CompareRow(id: "e-\($0.id)", kind: .line, name: $0.name, value: -$0.value(in: column), total: -$0.total)
                }
            }
        }
        return rows
    }

    /// How a table amount reads: nothing (under half a unit, shown as "0" in grey), money in (green, with a plus), or
    /// money out (plain, with a minus). A refund in Income comes out negative and reads as money out.
    enum CompareTone: Equatable { case zero, moneyIn, moneyOut }

    static func compareTone(_ amount: Double) -> CompareTone {
        abs(amount) < 0.5 ? .zero : amount > 0 ? .moneyIn : .moneyOut
    }

    /// The total column's title: "2026 total" for a calendar year, "Total" for a custom range.
    static func totalTitle(custom: Bool, start: Date) -> String {
        custom ? "Total" : "\(calendar.component(.year, from: start)) total"
    }

    /// The column the table opens on: the latest full one, since the running month is only "so far".
    static func defaultColumn(_ columns: [Column]) -> Column? {
        columns.last { !$0.isPartial } ?? columns.last
    }

    /// Share of income kept. Nil without income.
    static func savingsRate(income: Double, expenses: Double) -> Double? {
        income > 0 ? (income - expenses) / income : nil
    }

    /// How `current` compares with the average of `previous`, as a fraction rounded to whole percent: 0.18 is 18% more.
    static func versusUsual(current: Double, previous: [Double]) -> Double? {
        guard !previous.isEmpty else { return nil }
        let average = previous.reduce(0, +) / Double(previous.count)
        guard average > 0 else { return nil }
        return ((current / average - 1) * 100).rounded() / 100
    }

    /// "as usual" within 5%, else "18% over usual" or "6% under usual".
    static func usualLabel(_ change: Double) -> String {
        if abs(change) < 0.05 { return "as usual" }
        let percent = abs(change).formatted(.percent.precision(.fractionLength(0)))
        return "\(percent) \(change > 0 ? "over" : "under") usual"
    }

    // MARK: CSV

    /// The statement as CSV: a row per category with its group and kind, a value per column, and the total.
    /// Expenses are negative so a column sums to its net.
    static func csv(income: [StatementGroup], expenses: [StatementGroup], columns: [Column]) -> String {
        let header = (["Kind", "Group", "Category"] + columns.map { $0.months.joined(separator: " ") } + ["Total"])
            .map(CSV.text).joined(separator: ",")
        func rows(_ groups: [StatementGroup], kind: String, sign: Double) -> [String] {
            groups.flatMap { group in
                group.lines.map { line in
                    let amounts = (columns.map { line.value(in: $0) } + [line.total]).map { CSV.number(sign * $0) }
                    return ([kind, group.name, line.name].map(CSV.text) + amounts).joined(separator: ",")
                }
            }
        }
        return ([header] + rows(income, kind: "Income", sign: 1) + rows(expenses, kind: "Expense", sign: -1)).joined(separator: "\n") + "\n"
    }
}

extension StatementModel {
    /// "0", "+$6,444" or "−$1,658", in whole units.
    static func compareText(_ amount: Double, currency: String) -> String {
        switch compareTone(amount) {
        case .zero: "0"
        case .moneyIn: "+" + amount.money(currency, cents: false)
        case .moneyOut: "\u{2212}" + abs(amount).money(currency, cents: false)
        }
    }
}
