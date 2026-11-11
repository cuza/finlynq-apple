import Foundation

/// Budget and bills figures, as pure functions of the loaded data and a passed-in "today".
nonisolated enum BudgetModel {
    enum LineStatus: Equatable {
        case ok // swiftlint:disable:this identifier_name
        case warn, over
    }

    /// The budget list's filter chips.
    enum Filter: Hashable { case all, over, notBudgeted }

    private static let calendar = Calendar(identifier: .gregorian)

    /// Days left in `month`, today included: 22 on November 9. A future month has all its days, a past one none.
    static func daysRemaining(today: Date, month: Date) -> Int {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return 0 }
        let start = calendar.startOfDay(for: today)
        if start < interval.start { return calendar.range(of: .day, in: .month, for: month)?.count ?? 30 }
        if start >= interval.end { return 0 }
        return (calendar.dateComponents([.day], from: start, to: interval.end).day ?? 0)
    }

    /// What can be spent per day for the rest of `month`, today included. Nothing when the month is over or overspent.
    static func leftPerDay(left: Double, today: Date, month: Date) -> Double {
        let days = daysRemaining(today: today, month: month)
        return days > 0 ? max(left, 0) / Double(days) : 0
    }

    /// `.warn` from 90% of the budget, `.over` past it. A budget spent exactly is paid, so `.ok`.
    static func lineStatus(spent: Double, budget: Double) -> LineStatus {
        guard budget > 0 else { return .ok }
        if spent > budget { return .over }
        if spent < budget && spent / budget >= HomeModel.warnAt { return .warn }
        return .ok
    }

    /// Spending lines to list: those with a budget or spending, filtered by a chip.
    static func lines(_ budget: BudgetMonth, filter: Filter) -> [(group: BudgetMonth.Group, line: BudgetMonth.Line)] {
        budget.spending.flatMap { group in group.lines.map { (group, $0) } }.filter { _, line in
            let budgeted = line.budgeted ?? 0
            switch filter {
            case .all: return budgeted > 0 || line.actual > 0
            case .over: return budgeted > 0 && line.actual > budgeted
            case .notBudgeted: return budgeted <= 0 && line.actual > 0
            }
        }
    }

    /// Lines split into those over budget, most overspent first, and the rest in list order: the two cards of iPhone
    /// Duo's open display (DuoInnerBudget), or one list with the over-budget lines first (iPadPBudget).
    static func overAndOnTrack<Row>(_ rows: [Row], line: (Row) -> BudgetMonth.Line) -> (over: [Row], onTrack: [Row]) {
        let lines = rows.map(line)
        let isOver = lines.map { lineStatus(spent: $0.actual, budget: $0.budgeted ?? 0) == .over }
        let over = zip(rows, lines).enumerated().filter { isOver[$0.offset] }
            .sorted { $0.element.1.actual - ($0.element.1.budgeted ?? 0) > $1.element.1.actual - ($1.element.1.budgeted ?? 0) }
            .map(\.element.0)
        return (over, zip(rows, isOver).filter { !$0.1 }.map(\.0))
    }

    /// `YYYY-MM` for a date.
    static func monthKey(_ date: Date) -> String { String(APIDate.string(date).prefix(7)) }

    // MARK: Bills

    /// A payment's cost per month: weekly is 52/12 a month, annual is 1/12.
    static func perMonth(_ amount: Double, frequency: String) -> Double {
        switch frequency {
        case "weekly": amount * 52 / 12
        case "biweekly": amount * 26 / 12
        case "quarterly": amount / 3
        case "semi-annual", "semiannual": amount / 6
        case "annual", "yearly": amount / 12
        default: amount
        }
    }

    /// Due dates from `next`, stepping by `frequency`, that fall from `start` through `end`.
    static func occurrences(next: Date, frequency: String, from start: Date, through end: Date) -> [Date] {
        let step: DateComponents = switch frequency {
        case "weekly": DateComponents(day: 7)
        case "biweekly": DateComponents(day: 14)
        case "quarterly": DateComponents(month: 3)
        case "semi-annual", "semiannual": DateComponents(month: 6)
        case "annual", "yearly": DateComponents(year: 1)
        default: DateComponents(month: 1)
        }
        var dates: [Date] = []
        var date = next
        while date <= end, dates.count < 60 {
            if date >= calendar.startOfDay(for: start) { dates.append(date) }
            guard let following = calendar.date(byAdding: step, to: date) else { break }
            date = following
        }
        return dates
    }

    /// Recurring payments the user doesn't track yet: outgoing, not a transfer, and no subscription of the same name.
    /// `tracked` holds lowercased subscription names.
    static func untracked(
        _ suggestions: [RecurringSuggestion], tracked: Set<String>, transferCategories: Set<Int>
    ) -> [RecurringSuggestion] {
        suggestions.filter { suggestion in
            let payee = suggestion.payee.lowercased()
            return suggestion.avgAmount < 0
                && !transferCategories.contains(suggestion.categoryId ?? -1)
                && !tracked.contains { $0.contains(payee) || payee.contains($0) }
        }
        .sorted { $0.count > $1.count }
    }

    struct Payee: Identifiable, Equatable {
        let name: String
        let total: Double
        let count: Int
        let currency: String
        var id: String { name }
    }

    /// The three payees with the most spending, transfers left out.
    static func topPayees(_ transactions: [Transaction]) -> [Payee] {
        // ponytail: sums in each transaction's own currency; add conversion if a payee spans currencies.
        Dictionary(grouping: transactions.filter { !$0.isTransfer }, by: \.title).map { name, rows in
            Payee(name: name, total: rows.reduce(0) { $0 - $1.amount }, count: rows.count, currency: rows[0].currency)
        }
        .sorted { $0.total > $1.total }
        .prefix(3).map { $0 }
    }

    /// A typed budget amount in the user's locale ("1,450.50", "1450,5", "1.450,50"), rounded to cents.
    /// Nil for text that isn't a number, so a typo never clears or rewrites a budget.
    static func amount(_ text: String, locale: Locale = .current) -> Double? {
        guard let number = AddModel.number(text, locale: locale) else { return nil }
        return (NSDecimalNumber(decimal: number).doubleValue * 100).rounded() / 100
    }

    /// An amount as the edit field shows it: the locale's decimal separator, no grouping.
    static func draft(_ amount: Double, locale: Locale = .current) -> String {
        amount.formatted(.number.grouping(.never).precision(.fractionLength(0...2)).locale(locale))
    }
}
