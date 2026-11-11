import Foundation
import Testing
@testable import Finlynq

struct StatementModelTests {
    private let calendar = Calendar(identifier: .gregorian)
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func trends() throws -> Trends {
        let json = """
        {"displayCurrency":"USD","timeseries":[],"income":[
          {"name":"Salary","group":"Income","categoryId":1,"total":200,"count":2,"periods":{"2026-10":100,"2026-11":100}}],
         "expenses":[
          {"name":"Rent","group":"Housing","categoryId":2,"total":100,"count":2,"periods":{"2026-10":50,"2026-11":50}},
          {"name":"Dining","group":"Food","categoryId":3,"total":30,"count":3,"periods":{"2026-09":5,"2026-10":10,"2026-11":15}},
          {"name":"Groceries","group":"Food","categoryId":4,"total":60,"count":4,"periods":{"2026-10":40,"2026-11":20}},
          {"name":"Transfer to Savings","group":"Savings","categoryId":5,"total":0,"count":6,"periods":{}}]}
        """
        return try JSONDecoder().decode(Trends.self, from: Data(json.utf8))
    }

    @Test func currentMonthIsMarkedPartial() {
        #expect(StatementModel.isPartial(month: day(2026, 11, 1), today: day(2026, 11, 9)))
        #expect(!StatementModel.isPartial(month: day(2026, 10, 1), today: day(2026, 11, 9)))
        #expect(!StatementModel.isPartial(month: day(2025, 11, 1), today: day(2026, 11, 9)))
    }

    @Test func monthsCoverTheRange() {
        #expect(StatementModel.months(from: day(2026, 1, 1), to: day(2026, 3, 9)) == ["2026-01", "2026-02", "2026-03"])
    }

    @Test func columnsGroupMonthsIntoQuarters() {
        let months = StatementModel.months(from: day(2026, 1, 1), to: day(2026, 11, 9))
        let quarters = StatementModel.columns(months, quarterly: true, today: day(2026, 11, 9))
        #expect(quarters.map(\.label) == ["Q1", "Q2", "Q3", "Q4"])
        #expect(quarters.map(\.isPartial) == [false, false, false, true])
        #expect(quarters[3].months == ["2026-10", "2026-11"])
        let monthly = StatementModel.columns(months, quarterly: false, today: day(2026, 11, 9))
        #expect(monthly.count == 11)
        #expect(monthly.last?.isPartial == true)
    }

    @Test func rowsGroupByCategoryGroupLargestFirst() throws {
        let months = ["2026-10", "2026-11"]
        let groups = StatementModel.rows(from: try trends().expenses, months: months)
        #expect(groups.map(\.name) == ["Housing", "Food"], "Food is 85 in range, Housing 100; the empty transfer group is left out")
        #expect(groups[1].lines.map(\.name) == ["Groceries", "Dining"])
        #expect(groups[1].total == 85, "September is outside the range")
        #expect(groups[1].lines[1].values == [10, 15])
    }

    @Test func savingsRateSkipsPartialAndEmptyMonths() {
        #expect(StatementModel.savingsRate(income: 100, expenses: 60) == 0.4)
        #expect(StatementModel.savingsRate(income: 0, expenses: 60) == nil)
    }

    @Test func usualComparesWithTheAverageOfEarlierMonths() {
        #expect(StatementModel.versusUsual(current: 118, previous: [100, 100, 100]) == 0.18)
        #expect(StatementModel.versusUsual(current: 50, previous: []) == nil)
        #expect(StatementModel.usualLabel(0.03) == "as usual")
        #expect(StatementModel.usualLabel(-0.06) == "6% under usual")
        #expect(StatementModel.usualLabel(0.18) == "18% over usual")
    }

    @Test func csvSignsExpensesAndGuardsFormulas() throws {
        let trends = try trends()
        let months = ["2026-10", "2026-11"]
        let columns = StatementModel.columns(months, quarterly: false, today: day(2026, 11, 9))
        let csv = StatementModel.csv(
            income: StatementModel.rows(from: trends.income, months: months),
            expenses: StatementModel.rows(from: trends.expenses, months: months), columns: columns
        )
        let lines = csv.split(separator: "\n")
        #expect(lines[0] == "Kind,Group,Category,2026-10,2026-11,Total")
        #expect(lines[1] == "Income,Income,Salary,100.00,100.00,200.00")
        #expect(lines[2] == "Expense,Housing,Rent,-50.00,-50.00,-100.00")
        #expect(CSV.text("=SUM(A1)") == "'=SUM(A1)")
        #expect(CSV.text("Food, drink") == "\"Food, drink\"")
    }

    @Test func compareRowsSetAMonthAgainstTheRange() throws {
        let data = try trends()
        let months = ["2026-09", "2026-10", "2026-11"]
        let columns = StatementModel.columns(months, quarterly: false, today: day(2026, 11, 9))
        let october = try #require(StatementModel.defaultColumn(columns))
        #expect(october.months == ["2026-10"])
        let rows = StatementModel.compareRows(income: StatementModel.rows(from: data.income, months: months),
                                              expenses: StatementModel.rows(from: data.expenses, months: months), column: october)
        #expect(rows.map(\.name) == ["Income", "Salary", "Expenses", "Housing", "Rent", "Food", "Groceries", "Dining"])
        #expect(rows.map(\.kind) == [.section, .line, .section, .group, .line, .group, .line, .line])
        #expect(rows[0].value == 100 && rows[0].total == 200)
        #expect(rows[2].value == -100 && rows[2].total == -190)
        #expect(rows[5].value == -50 && rows[5].total == -90)
    }

    @Test func defaultColumnFallsBackToThePartialOne() {
        let only = StatementModel.columns(["2026-11"], quarterly: false, today: day(2026, 11, 9))
        #expect(StatementModel.defaultColumn(only)?.months == ["2026-11"])
        #expect(StatementModel.defaultColumn([]) == nil)
    }

    @Test @MainActor func compareRowsHandleAnEmptyColumnARefundAndQuarters() throws {
        let json = """
        {"displayCurrency":"USD","timeseries":[],"income":[
          {"name":"Salary","group":"Income","categoryId":1,"total":300,"count":3,"periods":{"2026-07":100,"2026-08":100,"2026-10":100}},
          {"name":"Refunds","group":"Income","categoryId":9,"total":-20,"count":1,"periods":{"2026-08":-20}}],
         "expenses":[
          {"name":"Rent","group":"Housing","categoryId":2,"total":150,"count":3,"periods":{"2026-07":50,"2026-08":50,"2026-10":50}}]}
        """
        let data = try JSONDecoder().decode(Trends.self, from: Data(json.utf8))
        let months = ["2026-07", "2026-08", "2026-09", "2026-10"]
        let income = StatementModel.rows(from: data.income, months: months)
        let expenses = StatementModel.rows(from: data.expenses, months: months)
        let monthly = StatementModel.columns(months, quarterly: false, today: day(2026, 11, 9))

        let september = try #require(monthly.first { $0.months == ["2026-09"] })
        let empty = StatementModel.compareRows(income: income, expenses: expenses, column: september)
        #expect(empty.allSatisfy { StatementModel.compareTone($0.value) == .zero })
        #expect(StatementModel.compareText(empty[0].value, currency: "USD") == "0")

        let august = try #require(monthly.first { $0.months == ["2026-08"] })
        let refund = try #require(StatementModel.compareRows(income: income, expenses: expenses, column: august)
            .first { $0.name == "Refunds" })
        #expect(refund.value == -20 && StatementModel.compareTone(refund.value) == .moneyOut)
        #expect(StatementModel.compareText(refund.value, currency: "USD").hasPrefix("\u{2212}"))
        #expect(StatementModel.compareTone(100) == .moneyIn && StatementModel.compareText(100, currency: "USD").hasPrefix("+"))

        let quarters = StatementModel.columns(months, quarterly: true, today: day(2026, 11, 9))
        let third = try #require(quarters.first { $0.label == "Q3" })
        let rows = StatementModel.compareRows(income: income, expenses: expenses, column: third)
        #expect(rows[0].name == "Income" && rows[0].value == 180, "Q3 sums July to September, refund included")
        #expect(rows.first { $0.name == "Expenses" }?.value == -100)
    }

    @Test func totalHeaderNamesTheYearOrTheRange() {
        #expect(StatementModel.totalTitle(custom: false, start: day(2026, 1, 1)) == "2026 total")
        #expect(StatementModel.totalTitle(custom: true, start: day(2025, 6, 1)) == "Total")
    }
}
