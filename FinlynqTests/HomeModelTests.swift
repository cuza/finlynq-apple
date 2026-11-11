import Foundation
import Testing
@testable import Finlynq

struct HomeModelTests {
    /// Nov 9, 2026, passed in so the tests never depend on the clock.
    private let today = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 9))!

    private func budget(dining actual: Double) throws -> BudgetMonth {
        let json = """
        {"month":"2026-11","currency":"USD",
         "summary":{"plannedIncome":0,"receivedIncome":0,"plannedSpending":500,"spent":\(actual),
          "plannedDebt":0,"paidDebt":0,"leftToPlan":0,"netCashFlow":0},
         "income":[],"debt":[],
         "spending":[{"key":"g:Food","name":"Food","budgeted":500,"actual":\(actual),"left":null,"status":"ok","lines":[
           {"key":"c:1","name":"Dining","budgeted":400,"actual":\(actual),"left":\(400 - actual),"status":"ok"},
           {"key":"c:2","name":"Groceries","budgeted":100,"actual":10,"left":90,"status":"ok"}]}]}
        """
        return try JSONDecoder().decode(BudgetMonth.self, from: Data(json.utf8))
    }

    private func bill(_ name: String, day: Int, amount: Double = 10) throws -> Subscription {
        let json = """
        {"id":\(day),"name":"\(name)","amount":\(amount),"currency":"USD","frequency":"monthly",
         "nextDate":"2026-11-\(String(format: "%02d", day))","status":"active"}
        """
        return try JSONDecoder().decode(Subscription.self, from: Data(json.utf8))
    }

    /// Formatted with the test machine's locale, as the app formats them.
    private func usd(_ amount: Double) -> String { amount.wholeMoney("USD") }
    private func percent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(1))) }

    private func due(_ subscriptions: [Subscription], budget: BudgetMonth? = nil) -> [Bill] {
        HomeModel.billsThisWeek(subscriptions, budget: budget, today: today)
    }

    @Test func attentionOrdersReviewFirst() throws {
        let items = HomeModel.attention(
            stagedCount: 12, budget: try budget(dining: 368),
            bills: due([try bill("Car loan", day: 15), try bill("Netflix", day: 12), try bill("Hydro", day: 14)]), today: today
        )
        #expect(items.map(\.route) == [.review, .budget, .bills])
        #expect(items[0].kind == .review(count: 12))
        #expect(items[0].title == "Transactions to review")
        #expect(items[0].subtitle == "From your imports")
        #expect(items.map(\.id) == ["review", "budget:Dining", "bills"])
        guard case .budgetWarning(let name, let percent, _) = items[1].kind else { Issue.record("not a budget warning"); return }
        #expect(name == "Dining")
        #expect(percent == 92)
        guard case .billsThisWeek(let count, let total, _) = items[2].kind else { Issue.record("not bills"); return }
        #expect(count == 3)
        #expect(total == 30)
    }

    @Test func budgetWarningAt90Percent() throws {
        #expect(HomeModel.attention(stagedCount: 0, budget: try budget(dining: 360), bills: [], today: today).count == 1)
        #expect(HomeModel.attention(stagedCount: 0, budget: try budget(dining: 356), bills: [], today: today).isEmpty)
    }

    @Test func billsThisWeekUsesNext7Days() throws {
        let bills = try [bill("A", day: 12), bill("B", day: 14), bill("C", day: 15), bill("D", day: 20)]
        let items = HomeModel.attention(stagedCount: 0, budget: nil, bills: due(bills), today: today)
        guard case .billsThisWeek(let count, _, let names) = items.first?.kind else { Issue.record("no bills item"); return }
        #expect(count == 3)
        #expect(names == ["A", "B", "C"])
    }

    @Test func emptyDashboard() throws {
        #expect(HomeModel.attention(stagedCount: 0, budget: nil, bills: [], today: today).isEmpty)
    }

    @Test func monthChangeStartsAtFirstOfMonth() throws {
        let series = [("2026-10-30", 100.0), ("2026-11-01", 110), ("2026-11-09", 150)]
        #expect(HomeModel.monthChange(series.map { NetWorthHistory.Point(date: $0.0, value: $0.1) }, today: today) == 40)
    }

    @Test func reviewSubtitleNamesTheAccount() {
        let items = HomeModel.attention(stagedCount: 3, budget: nil, bills: [], today: today, reviewAccount: "Chequing")
        #expect(items.first?.subtitle == "From the Chequing import")
    }

    @Test func splitUsesAccountTypeNotSign() throws {
        func balance(_ id: Int, type: String, converted: Double) -> String {
            """
            {"accountId":\(id),"accountName":"A\(id)","accountType":"\(type)","accountGroup":"Banks","currency":"USD",
             "archived":false,"isInvestment":false,"aliasCt":null,"balance":0,"convertedBalance":\(converted)}
            """
        }
        let json = "[" + [balance(1, type: "A", converted: -500), balance(2, type: "A", converted: 2000),
                          balance(3, type: "L", converted: -3110)].joined(separator: ",") + "]"
        let balances = try JSONDecoder().decode([Dashboard.Balance].self, from: Data(json.utf8))
        let split = HomeModel.split(balances)
        #expect(split.assets == 1500)
        #expect(split.debts == -3110)
    }

    @Test func wideListsEveryBudgetWarningAndNoBills() throws {
        let json = """
        {"month":"2026-11","currency":"USD",
         "summary":{"plannedIncome":0,"receivedIncome":0,"plannedSpending":600,"spent":482,
          "plannedDebt":0,"paidDebt":0,"leftToPlan":0,"netCashFlow":0},
         "income":[],"debt":[],
         "spending":[{"key":"g:Food","name":"Food","budgeted":null,"actual":368,"left":null,"status":"ok","lines":[
           {"key":"c:1","name":"Dining","budgeted":400,"actual":368,"left":32,"status":"ok"}]},
          {"key":"g:Transport","name":"Transport","budgeted":null,"actual":114,"left":null,"status":"over","lines":[
           {"key":"c:2","name":"Fuel","budgeted":100,"actual":114,"left":-14,"status":"over"}]}]}
        """
        let budget = try JSONDecoder().decode(BudgetMonth.self, from: Data(json.utf8))
        let bills = due([try bill("Netflix", day: 12)])
        let wide = HomeModel.attention(stagedCount: 0, budget: budget, bills: bills, today: today, wide: true)
        #expect(wide.map(\.title) == ["Fuel is \(usd(14)) over", "Dining is at 92%"])
        #expect(wide[0].subtitle == "\(usd(114)) spent of \(usd(100))")
        #expect(wide[1].subtitle == "\(usd(32)) left with 22 days to go")
        let phone = HomeModel.attention(stagedCount: 0, budget: budget, bills: bills, today: today)
        #expect(phone.map(\.id) == ["budget:Fuel", "bills"])
        // iPad portrait and iPhone Duo: the category's name, what was spent, and the amount at the end.
        let trailing = HomeModel.attention(stagedCount: 0, budget: budget, bills: bills, today: today, wide: true, trailing: true)
        #expect(trailing.map(\.title) == ["Fuel", "Dining"])
        #expect(trailing.map(\.subtitle) == ["\(usd(114)) spent of \(usd(100))", "\(usd(368)) spent of \(usd(400))"])
        #expect(trailing.map(\.trailing) == ["\(usd(14)) over", "\(usd(32)) left"])
        #expect(trailing.map(\.id) == wide.map(\.id))
        #expect(wide.allSatisfy { $0.trailing == nil })
    }

    @Test func billsIncludeUnpaidLoanPaymentsFromTheBudget() throws {
        let json = """
        {"month":"2026-11","currency":"USD",
         "summary":{"plannedIncome":0,"receivedIncome":0,"plannedSpending":0,"spent":0,
          "plannedDebt":1240,"paidDebt":0,"leftToPlan":0,"netCashFlow":0},
         "income":[],"spending":[],
         "debt":[{"accountId":7,"name":"Car loan","planned":1240,"paid":0,"dueDates":["2026-11-15"]},
                 {"accountId":8,"name":"Paid loan","planned":100,"paid":100,"dueDates":["2026-11-13"]},
                 {"accountId":9,"name":"Later loan","planned":100,"paid":0,"dueDates":["2026-11-28"]}]}
        """
        let budget = try JSONDecoder().decode(BudgetMonth.self, from: Data(json.utf8))
        let bills = due([try bill("Netflix", day: 12, amount: 16.49)], budget: budget)
        #expect(bills.map(\.name) == ["Netflix", "Car loan"])
        #expect(bills.map(\.amount) == [16.49, 1240])
        #expect(bills[1].category == "Payment")
        #expect(bills[1].isLoan)
        #expect(HomeModel.dueIn(bills[0].date, today: today) == "in 3 days")
    }

    @Test func perDaySplitsWhatIsLeftOverTheRestOfTheMonth() {
        let perDay = HomeModel.perDay(left: 1282, today: today)
        // Today counts, as on Budget: November 9 leaves 22 days.
        #expect(perDay.days == 22)
        #expect(abs(perDay.amount - 58.27) < 0.01)
        let lastDay = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 30))!
        #expect(HomeModel.perDay(left: 50, today: lastDay) == (50, 1))
        #expect(HomeModel.perDay(left: -10, today: today).amount == 0)
    }

    @Test func periodChangeAndCopy() {
        let series = [("2025-11-10", 171_770.0), ("2026-11-09", 184_250)].map { NetWorthHistory.Point(date: $0.0, value: $0.1) }
        let change = HomeModel.change(series)
        #expect(change?.amount == 12_480)
        #expect(HomeModel.signedChange(12_480, percent: change?.percent, currency: "USD") == "+\(usd(12_480)) (\(percent(0.073)))")
        #expect(HomeModel.signedChange(-50, percent: nil, currency: "USD") == "\u{2212}\(usd(50))")
        #expect(HomeModel.periodLabel("1y") == "past year")
        let fromZero = [("2025-11-10", 0.0), ("2026-11-09", 100)].map { NetWorthHistory.Point(date: $0.0, value: $0.1) }
        #expect(HomeModel.change(fromZero)?.percent == nil)
    }

    @Test func oneMonthRequestsSixMonthsAndKeepsTheLastMonth() {
        #expect(HomeModel.requestPeriod("1m") == "6m")
        #expect(HomeModel.requestPeriod("all") == "all")
        let series = ["2026-05-14", "2026-10-08", "2026-10-09", "2026-11-09"].map { NetWorthHistory.Point(date: $0, value: 1) }
        #expect(HomeModel.trim(series, period: "1m", today: today).map(\.date) == ["2026-10-09", "2026-11-09"])
        #expect(HomeModel.trim(series, period: "6m", today: today).count == 4)
    }

    @Test func investedTodayUsesTheLastTwoDaysOfInvestmentAccounts() {
        func point(_ date: String, brokerage: Double) -> NetWorthHistory.Point {
            NetWorthHistory.Point(date: date, value: 0, members: [.init(id: 1, value: brokerage), .init(id: 2, value: 500)])
        }
        let daily = [point("2026-11-08", brokerage: 200_000), point("2026-11-09", brokerage: 201_184)]
        let change = HomeModel.investedToday(daily, investmentIds: [1])
        #expect(change?.amount == 1184)
        #expect(HomeModel.signedChange(1184, percent: change?.percent, currency: "USD") == "+\(usd(1184)) (\(percent(0.006)))")
        let monthly = [point("2026-10-01", brokerage: 1), point("2026-11-01", brokerage: 2)]
        #expect(HomeModel.investedToday(monthly, investmentIds: [1]) == nil)
    }

    /// With more than 10 non-zero accounts the server folds the rest of `breakdown` into an "Other" row that has
    /// no id; `members` still lists every account with its id. Account 12 is the smallest, so only `members` has it.
    @Test func historyWithMoreThanTenAccountsDecodes() throws {
        func point(_ date: String, small: Double) -> String {
            let values = (1...11).map { Double(1000 * $0) } + [small]
            let members = values.enumerated().map { "{\"id\":\($0.offset + 1),\"name\":\"A\($0.offset + 1)\",\"value\":\($0.element)}" }
            let top = members.reversed().prefix(10).joined(separator: ",")
            let other = "{\"name\":\"Other\",\"value\":\(1000 + small)}"
            return "{\"date\":\"\(date)\",\"value\":\(values.reduce(0, +)),\"breakdown\":[\(top),\(other)],"
                + "\"members\":[\(members.joined(separator: ","))]}"
        }
        let json = """
        {"displayCurrency":"CAD","period":"1y","accountId":null,"hasInvestmentData":false,"fxApproximation":false,
         "basisUsed":"reporting","seriesCurrency":"CAD",
         "series":[\(point("2026-11-08", small: 100)),\(point("2026-11-09", small: 150))]}
        """
        let history = try JSONDecoder().decode(NetWorthHistory.self, from: Data(json.utf8))
        #expect(history.series.count == 2)
        #expect(HomeModel.investedToday(history.series, investmentIds: [12])?.amount == 50)
    }

    private func debtBudget(_ debt: String) throws -> BudgetMonth {
        let json = """
        {"month":"2026-11","currency":"USD",
         "summary":{"plannedIncome":0,"receivedIncome":0,"plannedSpending":0,"spent":0,
          "plannedDebt":0,"paidDebt":0,"leftToPlan":0,"netCashFlow":0},
         "income":[],"spending":[],"debt":[\(debt)]}
        """
        return try JSONDecoder().decode(BudgetMonth.self, from: Data(json.utf8))
    }

    @Test func aLoanCountsOnceOnItsNextDueDate() throws {
        let budget = try debtBudget(
            #"{"accountId":7,"name":"Car loan","planned":600,"paid":0,"dueDates":["2026-11-01","2026-11-10","2026-11-15"]}"#
        )
        let bills = HomeModel.billsThisWeek([], budget: budget, loanPayers: [7: (id: 1, name: "Chequing")], today: today)
        #expect(bills.count == 1)
        #expect(bills.first.map { APIDate.string($0.date) } == "2026-11-10")
        #expect(bills.first?.account == "Chequing")
        #expect(bills.first?.accountId == 1)
    }

    /// A transaction in account `account`, named "A<account>".
    private func transaction(_ id: Int, account: Int, amount: Double, date: String, link: String?) throws -> Transaction {
        let json = """
        {"id":\(id),"date":"\(date)","accountId":\(account),"accountName":"A\(account)","currency":"USD","amount":\(amount),
         "linkId":\(link.map { "\"\($0)\"" } ?? "null")}
        """
        return try JSONDecoder().decode(Transaction.self, from: Data(json.utf8))
    }

    @Test func payingAccountIsTheOtherLegOfTheLatestLoanTransfer() throws {
        let legs = try [
            transaction(1, account: 7, amount: 351, date: "2026-09-15", link: "a"),
            transaction(2, account: 7, amount: 351, date: "2026-10-15", link: "b"),
            transaction(3, account: 7, amount: -20, date: "2026-10-20", link: nil)
        ]
        let sameDay = try [
            legs[1],
            transaction(4, account: 3, amount: -50, date: "2026-10-15", link: "c"),
            transaction(5, account: 1, amount: -351, date: "2026-10-15", link: "b")
        ]
        let payer = HomeModel.payingAccount(loanLegs: legs, sameDay: sameDay)
        #expect(payer?.id == 1)
        #expect(payer?.name == "A1")
        #expect(HomeModel.payingAccount(loanLegs: [legs[2]], sameDay: sameDay) == nil)
    }

    @Test func afterBillsUsesTheAccountWithTheMostBills() throws {
        func balance(_ id: Int, _ name: String, _ converted: Double) -> String {
            """
            {"accountId":\(id),"accountName":"\(name)","accountType":"A","accountGroup":"Banks","currency":"USD",
             "archived":false,"isInvestment":false,"balance":0,"convertedBalance":\(converted)}
            """
        }
        let balances = try JSONDecoder().decode(
            [Dashboard.Balance].self, from: Data(("[" + balance(1, "Chequing", 9000) + "," + balance(2, "Visa", -300) + "]").utf8)
        )
        func bill(_ id: String, _ amount: Double, account: Int?) -> Bill {
            Bill(id: id, name: id, date: today, amount: amount, category: nil, account: nil, accountId: account)
        }
        let bills = [bill("a", 100, account: 2), bill("b", 155, account: 1), bill("c", 1240, account: 1), bill("d", 5, account: nil)]
        let after = HomeModel.afterBills(bills, balances: balances)
        #expect(after?.name == "Chequing")
        #expect(after?.amount == 7605) // 9,000 - 155 - 1,240
        // A tie goes to the account of the earliest bill.
        #expect(HomeModel.afterBills([bill("a", 100, account: 2), bill("b", 1, account: 1)], balances: balances)?.name == "Visa")
        #expect(HomeModel.afterBills([bill("d", 5, account: nil)], balances: balances) == nil)
    }

    @Test func budgetSlicesFoldGroupsPastTheLimitIntoOther() throws {
        func group(_ name: String, budgeted: Double, actual: Double, overLine: Bool = false) -> String {
            let lineActual = overLine ? budgeted + 10 : actual
            return """
            {"key":"g:\(name)","name":"\(name)","budgeted":null,"actual":\(actual),"left":null,"status":"ok","lines":[
             {"key":"c:\(name)","name":"\(name) line","budgeted":\(budgeted),"actual":\(lineActual),"left":0,"status":"ok"}]}
            """
        }
        let groups = try JSONDecoder().decode([BudgetMonth.Group].self, from: Data(("[" + [
            group("Housing", budgeted: 100, actual: 50), group("Food", budgeted: 100, actual: 60),
            group("Transport", budgeted: 100, actual: 110, overLine: true), group("Lifestyle", budgeted: 50, actual: 20),
            group("Health", budgeted: 30, actual: 5), group("Unused", budgeted: 0, actual: 0)
        ].joined(separator: ",") + "]").utf8))
        let phone = HomeModel.budgetSlices(groups, limit: 3)
        #expect(phone.map(\.name) == ["Housing", "Food", "Transport", "Other"])
        #expect(phone[3].spent == 25)
        #expect(phone[3].budgeted == 80)
        #expect(phone[2].flag == "Transport line over")
        let wide = HomeModel.budgetSlices(groups, limit: 4)
        #expect(wide.map(\.name) == ["Housing", "Food", "Transport", "Lifestyle", "Other"])
        #expect(HomeModel.budgetSlices(Array(groups.prefix(4)), limit: 4).allSatisfy { !$0.isOther })
    }

    @Test func iconsBillFollowsTheDesign() {
        func bill(_ name: String, _ category: String?, loan: Bool = false) -> Bill {
            Bill(id: name, name: name, date: today, amount: 1, category: category, account: nil, accountId: nil, isLoan: loan)
        }
        func icon(_ bill: Bill) -> String { Icons.bill(name: bill.name, category: bill.category, isLoan: bill.isLoan).symbol }
        #expect(icon(bill("Netflix", "Subscriptions")) == "tv")
        #expect(icon(bill("Hydro", "Utilities")) == "bolt.fill")
        #expect(icon(bill("Car loan", "Payment", loan: true)) == "car.fill")
        #expect(icon(bill("Mortgage", "Payment", loan: true)) == "banknote.fill")
        #expect(icon(bill("Shell", "Gas")) == "fuelpump.fill")
    }
}
