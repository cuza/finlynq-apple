import Foundation

nonisolated struct CalendarDay: Identifiable {
    let date: Date
    let spent: Double
    let income: Double
    let bills: [Subscription]
    let isToday: Bool
    let isFuture: Bool
    var id: Date { date }
    var number: Int { Calendar(identifier: .gregorian).component(.day, from: date) }
}

nonisolated enum CalendarModel {
    private static var calendar: Calendar { Calendar(identifier: .gregorian) }

    /// One entry per day of the month. Spent and income are in the display currency. Bills land on their next due date.
    static func days(
        month: Date, rows: [Transaction], bills: [Subscription], today: Date = Fixtures.today, rates: ActivityModel.Rates
    ) -> [CalendarDay] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let todayKey = APIDate.string(today)
        let counted = rows.filter(ActivityModel.counts)
        let byDay = Dictionary(grouping: counted, by: { String($0.date.prefix(10)) })
        let billsByDay = Dictionary(grouping: bills.filter { $0.status == "active" }, by: { String(($0.nextDate ?? "").prefix(10)) })
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 0
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            let key = APIDate.string(date)
            let totals = ActivityModel.monthTotals(byDay[key] ?? [], rates: rates)
            return CalendarDay(
                date: date, spent: totals.spent, income: totals.income, bills: billsByDay[key] ?? [],
                isToday: key == todayKey, isFuture: key > todayKey
            )
        }
    }

    /// Bills still due (today or later) on days after `day`, soonest first, with their dates.
    static func billsAfter(_ day: Date, in days: [CalendarDay]) -> [(date: Date, bill: Subscription)] {
        days.filter { ($0.isFuture || $0.isToday) && $0.date > day }.flatMap { entry in entry.bills.map { (entry.date, $0) } }
    }

    /// Empty cells before the 1st so the grid starts on Sunday.
    static func leadingBlanks(month: Date) -> Int {
        guard let start = calendar.dateInterval(of: .month, for: month)?.start else { return 0 }
        return calendar.component(.weekday, from: start) - 1
    }
}
