import Foundation
import Testing
@testable import Finlynq

struct BudgetModelTests {
    private let calendar = Calendar(identifier: .gregorian)
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func leftPerDayNov9() {
        let perDay = BudgetModel.leftPerDay(left: 1282, today: day(2026, 11, 9), month: day(2026, 11, 1))
        #expect(BudgetModel.daysRemaining(today: day(2026, 11, 9), month: day(2026, 11, 1)) == 22)
        #expect(abs(perDay - 58.27) < 0.01)
    }

    @Test func leftPerDayOtherMonths() {
        // A future month has all its days left; a past month has none, so nothing is left per day.
        #expect(BudgetModel.daysRemaining(today: day(2026, 11, 9), month: day(2026, 12, 1)) == 31)
        #expect(BudgetModel.leftPerDay(left: 100, today: day(2026, 11, 9), month: day(2026, 10, 1)) == 0)
        #expect(BudgetModel.leftPerDay(left: -50, today: day(2026, 11, 9), month: day(2026, 11, 1)) == 0)
    }

    @Test func lineStatusThresholds() {
        #expect(BudgetModel.lineStatus(spent: 384, budget: 416) == .warn)
        #expect(BudgetModel.lineStatus(spent: 114, budget: 100) == .over)
        #expect(BudgetModel.lineStatus(spent: 0, budget: 0) == .ok)
        #expect(BudgetModel.lineStatus(spent: 300, budget: 416) == .ok)
        #expect(BudgetModel.lineStatus(spent: 1450, budget: 1450) == .ok, "a budget spent exactly is paid, not a warning")
    }

    @Test func perMonthByFrequency() {
        #expect(BudgetModel.perMonth(12, frequency: "monthly") == 12)
        #expect(BudgetModel.perMonth(120, frequency: "annual") == 10)
        #expect(BudgetModel.perMonth(30, frequency: "quarterly") == 10)
        #expect(abs(BudgetModel.perMonth(10, frequency: "weekly") - 43.33) < 0.01)
        #expect(abs(BudgetModel.perMonth(10, frequency: "biweekly") - 21.67) < 0.01)
    }

    @Test func occurrencesStepByFrequency() {
        let dates = BudgetModel.occurrences(
            next: day(2026, 11, 12), frequency: "weekly", from: day(2026, 11, 9), through: day(2026, 12, 9)
        )
        #expect(dates.count == 4)
        let start = day(2026, 11, 9), end = day(2026, 12, 9)
        let monthly = BudgetModel.occurrences(next: day(2026, 12, 1), frequency: "monthly", from: start, through: end)
        #expect(monthly.count == 1)
    }

    @Test func untrackedSuggestionsSkipTrackedPayeesIncomeAndTransfers() throws {
        let json = """
        [{"payee":"Spotify","avgAmount":-11.99,"frequency":"monthly","count":14,"categoryId":1},
         {"payee":"Netflix","avgAmount":-16.49,"frequency":"monthly","count":10,"categoryId":1},
         {"payee":"Acme Corp","avgAmount":3200,"frequency":"biweekly","count":12,"categoryId":2},
         {"payee":"Transfer","avgAmount":-500,"frequency":"monthly","count":6,"categoryId":3}]
        """
        let suggestions = try JSONDecoder().decode([RecurringSuggestion].self, from: Data(json.utf8))
        let found = BudgetModel.untracked(suggestions, tracked: ["netflix"], transferCategories: [3])
        #expect(found.map(\.payee) == ["Spotify"])
    }

    @Test func amountParsesTheLocalesNumbers() {
        #expect(BudgetModel.amount("1,450.50", locale: Locale(identifier: "en_US")) == 1450.5)
        #expect(BudgetModel.amount("1450,5", locale: Locale(identifier: "fr_CA")) == 1450.5)
        #expect(BudgetModel.amount("1\u{202F}450,5", locale: Locale(identifier: "fr_CA")) == 1450.5)
        #expect(BudgetModel.amount("1.450,50", locale: Locale(identifier: "de_DE")) == 1450.5)
        #expect(BudgetModel.amount("416", locale: Locale(identifier: "de_DE")) == 416)
    }

    @Test func amountRejectsTextThatIsNotANumber() {
        // The category editor and the Mac cell ignore these instead of clearing the budget.
        #expect(BudgetModel.amount("") == nil)
        #expect(BudgetModel.amount("abc") == nil)
        #expect(BudgetModel.amount("-5") == nil)
    }

    @Test func draftRoundTripsInEachLocale() {
        for identifier in ["en_US", "fr_CA", "de_DE"] {
            let locale = Locale(identifier: identifier)
            #expect(BudgetModel.amount(BudgetModel.draft(1450.5, locale: locale), locale: locale) == 1450.5, "\(identifier)")
        }
    }

    @Test func overAndOnTrackPutsTheMostOverspentFirst() throws {
        let json = """
        {"key":"x","name":"x","budgeted":null,"actual":0,"left":null,"status":"ok","lines":[
          {"key":"c:1","name":"Health","budgeted":250,"actual":1030,"left":-780,"status":"over"},
          {"key":"c:2","name":"Dining","budgeted":416,"actual":384,"left":32,"status":"ok"},
          {"key":"c:3","name":"Shopping","budgeted":400,"actual":547,"left":-147,"status":"over"},
          {"key":"c:6","name":"Childcare","budgeted":466,"actual":715,"left":-249,"status":"over"},
          {"key":"c:4","name":"Rent","budgeted":1450,"actual":1450,"left":0,"status":"ok"},
          {"key":"c:5","name":"Gifts","budgeted":null,"actual":40,"left":null,"status":"ok"}]}
        """
        let lines = try JSONDecoder().decode(BudgetMonth.Group.self, from: Data(json.utf8)).lines
        let split = BudgetModel.overAndOnTrack(lines) { $0 }
        #expect(split.over.map(\.name) == ["Health", "Childcare", "Shopping"])
        // Spent exactly is paid, and a line without a budget can't be over it.
        #expect(split.onTrack.map(\.name) == ["Dining", "Rent", "Gifts"])
    }
}
