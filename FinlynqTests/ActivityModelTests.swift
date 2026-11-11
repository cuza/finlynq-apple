// swiftlint:disable force_try
import Foundation
import Testing
@testable import Finlynq

struct ActivityModelTests {
    static func row(
        _ id: Int, _ date: String, _ amount: Double, currency: String = "USD", category: String? = "Dining",
        type: String? = "E", link: String? = nil
    ) -> Transaction {
        let json: [String: Any?] = [
            "id": id, "date": date, "currency": currency, "amount": amount, "categoryName": category,
            "categoryType": type, "linkId": link, "payee": "Payee \(id)"
        ]
        let data = try! JSONSerialization.data(withJSONObject: json.compactMapValues { $0 })
        return try! JSONDecoder().decode(Transaction.self, from: data)
    }

    @Test func groupByDayNewestFirst() {
        let rows = [
            Self.row(1, "2026-11-07", -5), Self.row(2, "2026-11-09", -6), Self.row(3, "2026-11-07", -7), Self.row(4, "2026-11-08", -8)
        ]
        let groups = ActivityModel.groupByDay(rows)
        #expect(groups.map { APIDate.string($0.day) } == ["2026-11-09", "2026-11-08", "2026-11-07"])
        #expect(groups.last?.rows.map(\.id) == [1, 3])
    }

    @Test func monthTotalsSkipTransfers() {
        let rows = [
            Self.row(1, "2026-11-01", -100), Self.row(2, "2026-11-02", 400, category: "Salary", type: "I"),
            Self.row(3, "2026-11-03", -500, category: "Transfer", type: "E", link: "abc"),
            Self.row(4, "2026-11-03", -50, category: "Reimbursed", type: "R")
        ]
        let totals = ActivityModel.monthTotals(rows, rates: ["USD": 1])
        #expect(totals.spent == 100)
        #expect(totals.income == 400)
        #expect(totals.net == 300)
    }

    @Test func rowUsesNativeCurrency() {
        let rows = [Self.row(1, "2026-11-01", -100, currency: "CAD"), Self.row(2, "2026-11-01", -10, currency: "USD")]
        // The row shows 100 CAD as entered; the totals convert it to the display currency (USD here).
        #expect(MoneyText.format(rows[0].amount, currency: rows[0].currency).contains("100.00"))
        #expect(MoneyText.format(rows[0].amount, currency: rows[0].currency).hasPrefix("\u{2212}"))
        #expect(MoneyText.format(rows[0].amount, currency: rows[0].currency) != MoneyText.format(rows[0].amount, currency: "USD"))
        #expect(ActivityModel.monthTotals(rows, rates: ["CAD": 0.75, "USD": 1]).spent == 85)
    }

    @Test func currencyWithoutARateIsLeftOutOfTotals() {
        // A currency whose accounts all have zero balance has no rate. Its rows must not be added as if 1:1.
        let rows = [Self.row(1, "2026-11-01", -100, currency: "EUR"), Self.row(2, "2026-11-01", -10, currency: "USD")]
        let rates = ["USD": 1.0]
        #expect(ActivityModel.monthTotals(rows, rates: rates).spent == 10)
        #expect(ActivityModel.unconverted(rows, rates: rates) == ["EUR"])
        #expect(ActivityModel.unconverted(rows, rates: ["USD": 1, "EUR": 1.1]).isEmpty)
    }

    @Test func filterUncategorized() {
        let rows = [Self.row(1, "2026-11-01", -5, category: nil), Self.row(2, "2026-11-01", -5)]
        #expect(ActivityModel.uncategorized(rows).map(\.id) == [1])
    }

    @Test func csvQuotesCommasQuotesAndLineBreaks() {
        let json = #"{"id":1,"date":"2026-11-04T00:00:00Z","currency":"USD","amount":-1234.5,"payee":"Joe's \"Diner\", Inc","#
            + #""categoryName":"Dining","accountName":"Visa\nRewards"}"#
        let row = try! JSONDecoder().decode(Transaction.self, from: Data(json.utf8))
        let transfer = Self.row(2, "2026-11-05", 500, category: nil, link: "abc")
        let lines = ActivityModel.csv([row, transfer]).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[0] == "Date,Payee,Category,Account,Amount,Currency")
        #expect(lines[1] == #"2026-11-04,"Joe's ""Diner"", Inc",Dining,"Visa"#)
        #expect(lines[2] == #"Rewards",-1234.50,USD"#)
        #expect(lines[3] == "2026-11-05,Payee 2,Transfer,,500.00,USD")
        #expect(lines.last == "")
    }

    @Test func csvMakesFormulaLikeTextLiteral() {
        let json = #"{"id":1,"date":"2026-11-04T00:00:00Z","currency":"USD","amount":-5,"payee":"=HYPERLINK(\"x\")","#
            + #""categoryName":"+Fees","accountName":"@Visa"}"#
        let row = try! JSONDecoder().decode(Transaction.self, from: Data(json.utf8))
        let minus = Self.row(2, "2026-11-05", -7, category: "-Misc")
        let lines = ActivityModel.csv([row, minus]).split(separator: "\n")
        #expect(lines[1] == #"2026-11-04,"'=HYPERLINK(""x"")",'+Fees,'@Visa,-5.00,USD"#)
        #expect(lines[2].hasPrefix("2026-11-05,Payee 2,'-Misc,"))
        #expect(lines[2].hasSuffix(",-7.00,USD"))
    }

    @Test func exportNameUsesAFixedYearMonth() {
        #expect(ActivityModel.exportName(month: APIDate.parse("2026-03-15")!) == "Finlynq 2026-03.csv")
    }

    @Test func pillTonesFollowTheCategoryGroup() {
        // The demo data's groups.
        let pairs = [
            ("E", "Food"), ("E", "Transport"), ("E", "Housing"), ("E", "Financial"), ("E", "Health"), ("E", "Lifestyle"),
            ("E", "Savings"), ("I", "Income"), ("R", "Transfer")
        ]
        let categories = pairs.enumerated().map { index, pair in
                let json = #"{"id":\#(index),"type":"\#(pair.0)","group":"\#(pair.1)","name":"C\#(index)"}"#
                return try! JSONDecoder().decode(Finlynq.Category.self, from: Data(json.utf8))
            }
        let groups = ActivityModel.expenseGroups(categories)
        #expect(groups == ["Financial", "Food", "Health", "Housing", "Lifestyle", "Savings", "Transport"])
        // MacActivity.dc.html: dining purple, transit orange, rent blue, salary green.
        #expect(ActivityModel.tone(group: "Food", type: "E", groups: groups) == .purple)
        #expect(ActivityModel.tone(group: "Transport", type: "E", groups: groups) == .orange)
        #expect(ActivityModel.tone(group: "Housing", type: "E", groups: groups) == .blue)
        #expect(ActivityModel.tone(group: "Income", type: "I", groups: groups) == .green)
        #expect(ActivityModel.tone(group: nil, type: "E", groups: groups) == .grey)
    }
}
// swiftlint:enable force_try
