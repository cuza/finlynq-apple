// swiftlint:disable force_try
import Foundation
import Testing
@testable import Finlynq

struct CalendarModelTests {
    private let calendar = Calendar(identifier: .gregorian)
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 9))! }

    private func bill(_ name: String, date: String, amount: Double) -> Subscription {
        let json = """
        {"id":1,"name":"\(name)","amount":\(amount),"currency":"USD","frequency":"monthly","nextDate":"\(date)","status":"active"}
        """
        return try! JSONDecoder().decode(Subscription.self, from: Data(json.utf8))
    }

    @Test func calendarMarksFutureBills() {
        let rows = [ActivityModelTests.row(1, "2026-11-08", -92), ActivityModelTests.row(2, "2026-11-08", 3200, type: "I")]
        let hydroBill = bill("Hydro", date: "2026-11-14", amount: 155)
        let days = CalendarModel.days(month: today, rows: rows, bills: [hydroBill], today: today, rates: ["USD": 1])
        #expect(days.count == 30)
        let hydro = days[13]
        #expect(hydro.bills.map(\.displayName) == ["Hydro"])
        #expect(hydro.spent == 0)
        #expect(hydro.isFuture)
        #expect(days[7].spent == 92)
        #expect(days[7].income == 3200)
        #expect(days[8].isToday)
        #expect(!days[7].isFuture)
    }

    @Test func calendarEmptyMonth() {
        let days = CalendarModel.days(month: today, rows: [], bills: [], today: today, rates: ["USD": 1])
        #expect(days.count == 30)
        #expect(days.allSatisfy { $0.spent == 0 && $0.income == 0 && $0.bills.isEmpty })
    }

    @Test func calendarIgnoresOtherMonthsAndTransfers() {
        let rows = [ActivityModelTests.row(1, "2026-10-31", -10), ActivityModelTests.row(2, "2026-11-02", -20, link: "x")]
        let old = bill("Old", date: "2026-12-01", amount: 5)
        let days = CalendarModel.days(month: today, rows: rows, bills: [old], today: today, rates: ["USD": 1])
        #expect(days.allSatisfy { $0.spent == 0 && $0.bills.isEmpty })
    }

    @Test func billsAfterADayAreTheMonthsLaterOnesSoonestFirst() {
        let bills = [
            bill("Rogers", date: "2026-11-25", amount: 85), bill("Hydro", date: "2026-11-14", amount: 155),
            bill("Car loan", date: "2026-11-15", amount: 540), bill("Past", date: "2026-11-02", amount: 9)
        ]
        let days = CalendarModel.days(month: today, rows: [], bills: bills, today: today, rates: ["USD": 1])
        let afterToday = CalendarModel.billsAfter(today, in: days)
        #expect(afterToday.map(\.bill.displayName) == ["Hydro", "Car loan", "Rogers"])
        #expect(afterToday.first?.date == days[13].date)
        // The selected day's own bills are listed above, so they are left out here.
        #expect(CalendarModel.billsAfter(days[13].date, in: days).map(\.bill.displayName) == ["Car loan", "Rogers"])
    }

    @Test func billsAfterAPastDayStartWithTodaysBills() {
        let bills = [bill("Netflix", date: "2026-11-09", amount: 16.49), bill("Hydro", date: "2026-11-14", amount: 155)]
        let days = CalendarModel.days(month: today, rows: [], bills: bills, today: today, rates: ["USD": 1])
        // Nov 3 is picked: today's bill is still due, so it leads the list.
        #expect(CalendarModel.billsAfter(days[2].date, in: days).map(\.bill.displayName) == ["Netflix", "Hydro"])
    }

    @Test func leadingBlanksStartOnSunday() {
        // Nov 1, 2026 is a Sunday.
        #expect(CalendarModel.leadingBlanks(month: today) == 0)
        let december = calendar.date(from: DateComponents(year: 2026, month: 12, day: 1))!
        #expect(CalendarModel.leadingBlanks(month: december) == 2)
    }
}
// swiftlint:enable force_try
