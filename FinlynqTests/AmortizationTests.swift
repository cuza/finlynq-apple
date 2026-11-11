import Foundation
import Testing
@testable import Finlynq

struct AmortizationTests {
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func carLoanSchedule() throws {
        let rows = Amortization.schedule(principal: 45590, annualRate: 6.4, payment: 1240, start: day(2026, 11, 15))
        #expect(rows.count == 41)
        let first = try #require(rows.first)
        #expect(first.date == day(2026, 11, 15))
        #expect(first.interest == 243.15)
        #expect(first.principal == 996.85)
        #expect(first.balance == 44593.15)
        let last = try #require(rows.last)
        // The 41.23 left after the 41st regular payment is added to it instead of becoming a 42nd payment.
        #expect(abs(last.payment - 1281.23) < 0.005)
        #expect(last.balance == 0)
        #expect(last.date == day(2030, 3, 15))
    }

    @Test func extraShortensSchedule() {
        let start = day(2026, 11, 15)
        let base = Amortization.schedule(principal: 45590, annualRate: 6.4, payment: 1240, start: start)
        let faster = Amortization.schedule(principal: 45590, annualRate: 6.4, payment: 1240, extra: 200, start: start)
        #expect(faster.count == 35)
        #expect(faster.count < base.count)
        #expect(Amortization.totalInterest(faster) < Amortization.totalInterest(base))
        #expect(abs(Amortization.totalInterest(base) - 5291.23) < 0.005)
        #expect(abs(Amortization.totalInterest(faster) - 4479.47) < 0.005)
    }

    @Test func paymentBelowInterestStops() {
        // 45,590 at 6.4% accrues 243.15 a month, so 200 never pays it down.
        let rows = Amortization.schedule(principal: 45590, annualRate: 6.4, payment: 200, start: day(2026, 11, 15))
        #expect(rows.isEmpty)
        #expect(Amortization.neverPaysOff(principal: 45590, annualRate: 6.4, payment: 200))
        #expect(!Amortization.neverPaysOff(principal: 45590, annualRate: 6.4, payment: 1240))
        #expect(Amortization.neverPaysOff(principal: 45590, annualRate: 6.4, payment: 243.15))
    }

    @Test func zeroRateSplitsPrincipalEvenly() {
        let rows = Amortization.schedule(principal: 1000, annualRate: 0, payment: 250, start: day(2026, 1, 31))
        #expect(rows.map(\.principal) == [250, 250, 250, 250])
        #expect(rows.allSatisfy { $0.interest == 0 })
        // Month ends clamp and then come back to the 31st: Feb 28, Mar 31.
        #expect(rows[1].date == day(2026, 2, 28))
        #expect(rows[2].date == day(2026, 3, 31))
    }
}
