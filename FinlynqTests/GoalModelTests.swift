import Foundation
import Testing
@testable import Finlynq

struct GoalModelTests {
    private let calendar = Calendar(identifier: .gregorian)
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func monthlyNeededEmergencyFund() {
        // Nov 2026 to Dec 2027 is 13 calendar months.
        let needed = GoalModel.monthlyNeeded(current: 15252, target: 20000, targetDate: day(2027, 12, 1), today: day(2026, 11, 9))
        #expect(abs(needed - 365.23) < 0.01)
    }

    @Test func monthlyNeededWhenReachedOrDue() {
        #expect(GoalModel.monthlyNeeded(current: 20000, target: 20000, targetDate: day(2027, 12, 1), today: day(2026, 11, 9)) == 0)
        // A target this month or past asks for the whole remainder now.
        #expect(GoalModel.monthlyNeeded(current: 100, target: 400, targetDate: day(2026, 11, 30), today: day(2026, 11, 9)) == 300)
    }

    @Test func projectedDateNilWithoutPace() {
        #expect(GoalModel.projectedDate(current: 100, target: 200, monthlyPace: 0, today: day(2026, 11, 9)) == nil)
        #expect(GoalModel.projectedDate(current: 100, target: 200, monthlyPace: -5, today: day(2026, 11, 9)) == nil)
    }

    @Test func projectedDateRoundsUpToWholeMonths() throws {
        let date = try #require(GoalModel.projectedDate(current: 15252, target: 20000, monthlyPace: 640, today: day(2026, 11, 9)))
        // 4748 / 640 = 7.4, so 8 months: July 2027.
        #expect(calendar.dateComponents([.year, .month], from: date) == DateComponents(year: 2027, month: 7))
    }

    @Test func paceIsTheAverageMonthlyChange() {
        let series = [(day(2026, 5, 9), 100.0), (day(2026, 8, 1), 300), (day(2026, 11, 9), 700)]
        #expect(GoalModel.monthlyPace(series, today: day(2026, 11, 9)) == 100)
        #expect(GoalModel.monthlyPace([], today: day(2026, 11, 9)) == 0)
    }

    @Test func monthsBetweenCountsCalendarMonths() {
        #expect(GoalModel.months(from: day(2027, 7, 1), to: day(2027, 12, 1)) == 5)
    }

    @Test func payingDownADebtIsPositivePace() throws {
        // A linked liability carries its balance negative: owing 5000, then 4000, is 1000 paid down.
        let series = [(day(2026, 5, 9), -5000.0), (day(2026, 11, 9), -4000)]
        let pace = GoalModel.monthlyPace(series, today: day(2026, 11, 9))
        #expect(pace > 0)
        // The server reports a debt goal's current amount as target minus what is owed.
        let projected = GoalModel.projectedDate(current: 6000, target: 10000, monthlyPace: pace, today: day(2026, 11, 9))
        #expect(projected != nil)
        #expect(GoalModel.onTrack(projected: projected, deadline: day(2029, 12, 1), current: 6000, target: 10000))
    }

    @Test func onTrackComparesMonths() {
        #expect(GoalModel.onTrack(projected: day(2027, 3, 9), deadline: day(2027, 3, 1), current: 0, target: 1))
        #expect(!GoalModel.onTrack(projected: day(2027, 4, 1), deadline: day(2027, 3, 1), current: 0, target: 1))
        #expect(!GoalModel.onTrack(projected: nil, deadline: day(2027, 3, 1), current: 0, target: 1))
        #expect(GoalModel.onTrack(projected: nil, deadline: day(2027, 3, 1), current: 1, target: 1))
    }

    @Test func editorKeepsLinkedAccountsTheListDoesNotHave() {
        // 4100 and 4102 are in the account list, 9001 isn't (archived or not loaded): it stays linked, last.
        #expect(GoalEditor.ordered([9001, 4102, 4100], accounts: [4100, 4101, 4102]) == [4100, 4102, 9001])
        #expect(GoalEditor.ordered([9001], accounts: []) == [9001])
        #expect(GoalEditor.ordered([], accounts: [4100]).isEmpty)
    }
}
