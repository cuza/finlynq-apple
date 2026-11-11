import Foundation

nonisolated enum ActivityModel {
    /// Exchange rates to the display currency, keyed by currency code.
    /// The display currency maps to 1. Rows in a currency with no rate are left out, never added unconverted.
    typealias Rates = [String: Double]

    /// Days newest first. Rows inside a day keep the order they came in.
    static func groupByDay(_ rows: [Transaction]) -> [(day: Date, rows: [Transaction])] {
        Dictionary(grouping: rows, by: \.day).map { (day: $0.key, rows: $0.value) }.sorted { $0.day > $1.day }
    }

    // Spent, income and net in the display currency. Transfers and `categoryType == "R"` rows are left out.
    // swiftlint:disable:next large_tuple
    static func monthTotals(_ rows: [Transaction], rates: Rates) -> (spent: Double, income: Double, net: Double) {
        var spent = 0.0
        var income = 0.0
        for row in rows where counts(row) {
            guard let rate = rates[row.currency] else { continue }
            let value = row.amount * rate
            if value < 0 { spent -= value } else { income += value }
        }
        return (spent, income, income - spent)
    }

    /// Whether a row counts toward spending and income.
    static func counts(_ row: Transaction) -> Bool { row.linkId == nil && row.categoryType != "R" }

    /// Currencies of counted rows that have no rate, so the totals leave them out.
    static func unconverted(_ rows: [Transaction], rates: Rates) -> [String] {
        Set(rows.filter(counts).map(\.currency).filter { rates[$0] == nil }).sorted()
    }

    static func uncategorized(_ rows: [Transaction]) -> [Transaction] {
        rows.filter { $0.categoryId == nil && $0.categoryName == nil && counts($0) }
    }

    /// Color of a category pill. Income is green. Each expense group keeps one color, picked by the group's place
    /// in the sorted list of expense groups, so Food, Housing and Transport differ in the demo data.
    enum Tone: Equatable { case grey, purple, orange, blue, green }

    static func tone(group: String?, type: String?, groups: [String]) -> Tone {
        if type == "I" { return .green }
        guard let group, let index = groups.firstIndex(of: group) else { return .grey }
        let cycle: [Tone] = [.grey, .purple, .orange, .blue]
        return cycle[index % cycle.count]
    }

    /// Sorted names of the expense category groups, for `tone`.
    static func expenseGroups(_ categories: [Category]) -> [String] {
        Set(categories.filter { $0.type == "E" }.map(\.group)).sorted()
    }

    /// The rows as CSV with a header: Date, Payee, Category, Account, Amount, Currency. Amounts are signed, with a
    /// dot and two decimals. A field with a comma, quote or line break is quoted, with its quotes doubled. Payee,
    /// Category and Account get a leading `'` when they start with `=`, `+`, `-`, `@`, tab or carriage return, so a
    /// spreadsheet reads them as text instead of a formula.
    static func csv(_ rows: [Transaction]) -> String {
        let lines = rows.map { row in
            [
                CSV.field(String(row.date.prefix(10))), CSV.text(row.title), CSV.text(row.isTransfer ? "Transfer" : row.categoryName ?? ""),
                CSV.text(row.account), CSV.number(row.amount), CSV.field(row.currency)
            ].joined(separator: ",")
        }
        return (["Date,Payee,Category,Account,Amount,Currency"] + lines).joined(separator: "\n") + "\n"
    }

    /// Export file name for a month, "Finlynq YYYY-MM.csv", in a fixed format so no locale puts a slash in it.
    static func exportName(month: Date) -> String { "Finlynq \(APIDate.string(month).prefix(7)).csv" }

    /// First and last day of the month containing `date`, as `YYYY-MM-DD`.
    static func bounds(of date: Date) -> (start: String, end: String) {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let last = calendar.date(byAdding: .day, value: calendar.range(of: .day, in: .month, for: date)!.count - 1, to: start) ?? date
        return (APIDate.string(start), APIDate.string(last))
    }
}
