import Foundation
import Testing
@testable import Finlynq

struct NetWorthModelTests {
    private func point(_ date: String, asset: Double, debt: Double) -> NetWorthHistory.Point {
        NetWorthHistory.Point(date: date, value: asset + debt, members: [.init(id: 1, value: asset), .init(id: 2, value: debt)])
    }

    @Test func monthsRunFromThePreviousMonthsLastPoint() {
        let series = [
            point("2026-09-30", asset: 100, debt: -50),
            point("2026-10-15", asset: 120, debt: -45),
            point("2026-10-31", asset: 150, debt: -40),
            point("2026-11-09", asset: 160, debt: -42)
        ]
        let months = NetWorthModel.months(series, liabilities: [2], count: 2)
        #expect(months.map(\.key) == ["2026-11", "2026-10"])
        #expect(months[1] == NetWorthModel.Month(key: "2026-10", assets: 50, debts: -10))
        #expect(months[1].net == 60, "assets up 50 and 10 less owed")
        #expect(months[0].debts == 2)
    }

    @Test func splitCountsDebtsAsAmountOwed() {
        #expect(NetWorthModel.split(point("2026-11-09", asset: 10, debt: -4), liabilities: [2]) == .init(assets: 10, debts: 4))
    }

    @Test @MainActor func oneMonthFallsBackToSixOnTheIPhone() {
        #expect(NetWorthView.period("1m", compact: true) == "6m", "iPhone has no 1M chip")
        #expect(NetWorthView.period("1m", compact: false) == "1m")
        #expect(NetWorthView.period("1y", compact: true) == "1y")
    }
}
