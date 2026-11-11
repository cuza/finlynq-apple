import Foundation
import Testing
@testable import Finlynq

struct WealthModelTests {
    private let today = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 9))!

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func balances() throws -> [Dashboard.Balance] {
        func row(_ id: Int, _ type: String, _ group: String, investment: Bool = false, archived: Bool = false, _ value: Double) -> String {
            """
            {"accountId":\(id),"accountName":"A\(id)","accountType":"\(type)","accountGroup":"\(group)","currency":"USD",
             "archived":\(archived),"isInvestment":\(investment),"balance":\(value),"convertedBalance":\(value)}
            """
        }
        let rows = [
            row(1, "A", "Banks", 9000), row(2, "A", "Investments", investment: true, 20000), row(3, "L", "Credit Cards", -3000),
            row(4, "L", "Loans", -45000), row(5, "A", "Banks", archived: true, 500)
        ]
        return try JSONDecoder().decode([Dashboard.Balance].self, from: Data(("[" + rows.joined(separator: ",") + "]").utf8))
    }

    private func carLoan(remaining: Double = 45590, start: String = "2023-10-15", extra: Double = 0) throws -> Loan {
        let json = """
        {"id":1,"name":"Car loan","type":"loan","accountId":4,"currency":"USD","principal":73500,"annualRate":6.4,
         "termMonths":76,"startDate":"\(start)","paymentFrequency":"monthly","paymentPerPeriod":1240,"monthlyPayment":1240,
         "extraPayment":\(extra),"remainingBalance":\(remaining),"interestPaid":6112}
        """
        return try JSONDecoder().decode(Loan.self, from: Data(json.utf8))
    }

    @Test func splitAssetsDebts() throws {
        let split = WealthModel.split(try balances())
        #expect(split.assets == 29000) // the archived account is left out
        #expect(split.debts == -48000)
    }

    @Test func groupsCashInvestmentsAndDebts() throws {
        let rows = try balances()
        #expect(WealthModel.cash(rows).map(\.accountId) == [1])
        #expect(WealthModel.investmentAccounts(rows).map(\.accountId) == [2])
        // Largest owed first.
        #expect(WealthModel.debts(rows).map(\.accountId) == [4, 3])
    }

    @Test func nextDueIsTheFirstPaymentDateOnOrAfterToday() throws {
        // Payments fall one month after the start and on the same day of the month after that.
        #expect(WealthModel.nextDue(try carLoan(), today: today) == day(2026, 11, 15))
        #expect(WealthModel.nextDue(try carLoan(), today: day(2026, 11, 15)) == day(2026, 11, 15))
        #expect(WealthModel.nextDue(try carLoan(start: "2026-11-01"), today: today) == day(2026, 12, 1))
    }

    @Test func planRunsFromTheRemainingBalance() throws {
        let plan = WealthModel.plan(try carLoan(), today: today)
        #expect(plan.count == 41)
        #expect(plan.first?.date == day(2026, 11, 15))
        #expect(plan.last?.date == day(2030, 3, 15))
    }

    @Test func whatIfComparesPayoffAndInterest() throws {
        let result = try #require(WealthModel.whatIf(try carLoan(), extra: 200, today: today))
        #expect(result.monthsSooner == 6)
        #expect(abs(result.interestSaved - 811.76) < 0.005)
        // The new payoff moves the server's payoff date back by the months saved.
        #expect(result.payoff(from: day(2030, 3, 15)) == day(2029, 9, 15))
        #expect(WealthModel.whatIf(try carLoan(), extra: 0, today: today)?.monthsSooner == 0)
    }

    @Test func savedExtraIsPartOfTheBasePlan() throws {
        // A loan that already pays 200 extra: the base plan includes it, and the what-if adds to it.
        let plan = WealthModel.plan(try carLoan(extra: 200), today: today)
        #expect(plan.count == 35)
    }

    @Test func percentPaid() throws {
        #expect(abs(WealthModel.percentPaid(try carLoan()) - 0.3797) < 0.0001)
        #expect(WealthModel.percentPaid(try carLoan(remaining: 0)) == 1)
    }

    private func transaction(_ id: Int, _ date: String, _ amount: Double, account: Int = 1, link: String? = nil) throws -> Transaction {
        let json = """
        {"id":\(id),"date":"\(date)","accountId":\(account),"currency":"USD","amount":\(amount),
         "linkId":\(link.map { "\"\($0)\"" } ?? "null")}
        """
        return try JSONDecoder().decode(Transaction.self, from: Data(json.utf8))
    }

    @Test func monthFlowsCountsThisMonthForTheAccount() throws {
        let rows = [
            try transaction(1, "2026-11-01", 3200), try transaction(2, "2026-11-03", -1450),
            try transaction(3, "2026-11-07", -500, link: "x"), try transaction(4, "2026-10-30", 99),
            try transaction(5, "2026-11-02", -10, account: 2)
        ]
        let flows = WealthModel.monthFlows(rows, accountId: 1, today: today)
        #expect(flows == WealthModel.Flows(moneyIn: 3200, deposits: 1, moneyOut: -1950, transfersOut: -500))
    }

    @Test func dayBalancesWorkBackFromTheCurrentBalance() throws {
        let rows = [try transaction(1, "2026-11-09", -142.8), try transaction(2, "2026-11-07", -500), try transaction(3, "2026-11-07", 100)]
        let balances = WealthModel.dayBalances(rows, current: 9058.05)
        #expect(balances[day(2026, 11, 9)] == 9058.05)
        #expect(abs((balances[day(2026, 11, 7)] ?? 0) - 9200.85) < 0.001)
    }

    @Test func accountSeriesPicksTheAccountsMember() throws {
        let json = """
        [{"date":"2026-11-08","value":100,"members":[{"id":1,"value":40},{"id":2,"value":60}]},{"date":"2026-11-09","value":7}]
        """
        let points = try JSONDecoder().decode([NetWorthHistory.Point].self, from: Data(json.utf8))
        #expect(WealthModel.accountSeries(points, accountId: 1).map(\.value) == [40, 7])
    }

    @Test func csvGuardsFormulasAndQuotes() throws {
        #expect(CSV.text("=HYPERLINK(1)") == "'=HYPERLINK(1)")
        #expect(CSV.field("-5") == "-5")
        #expect(CSV.text("Vanguard, \"Total\"") == "\"Vanguard, \"\"Total\"\"\"")
        let data = try #require(Fixtures.data(for: "/api/portfolio/overview"))
        let overview = try JSONDecoder().decode(PortfolioOverview.self, from: data)
        let csv = WealthModel.holdingsCSV(overview.byHolding)
        #expect(csv.hasPrefix("Symbol,Name,Shares"))
        #expect(csv.split(separator: "\n").count == overview.byHolding.count + 1)
        let schedule = try JSONDecoder().decode(Amortization.self, from: try #require(Fixtures.data(for: "/api/loans/amortization")))
        let lines = WealthModel.scheduleCSV(schedule.schedule).split(separator: "\n")
        #expect(lines[1] == "1,2026-06-15,351.59,277.84,73.75,14722.16")
    }

    private func fixtureLoan() throws -> (Loan, Amortization) {
        let loans = try JSONDecoder().decode([Loan].self, from: try #require(Fixtures.data(for: "/api/loans")))
        let schedule = try JSONDecoder().decode(Amortization.self, from: try #require(Fixtures.data(for: "/api/loans/amortization")))
        return (try #require(loans.first), schedule)
    }

    /// The loan screens show the server's facts: payoff and payments left from GET /api/loans, the next payment and
    /// interest from the captured server schedule.
    @Test func loanFactsComeFromTheServer() throws {
        let (loan, schedule) = try fixtureLoan()
        let facts = WealthModel.facts(loan, schedule: schedule, today: today)
        #expect(facts.payoff == day(2030, 6, 10))
        #expect(facts.paymentsLeft == 43)
        #expect(facts.next?.date == "2026-11-15")
        #expect(facts.next?.payment == 351.59)
        #expect(facts.next?.principal == 284.74)
        #expect(facts.upcoming.count == 43)
        let left = schedule.schedule.filter { $0.date >= "2026-11-09" }.reduce(0) { $0 + $1.interest }
        #expect(abs((facts.interestLeft ?? 0) - left) < 0.001)
        #expect(abs(WealthModel.interest(schedule.schedule, year: 2026) - (73.75 + 72.38 + 71.01 + 69.63 + 68.25 + 66.85 + 65.45)) < 0.01)
        // Without a schedule the facts still come from the loan, and nothing is computed locally.
        let bare = WealthModel.facts(loan, schedule: nil, today: today)
        #expect(bare.next == nil && bare.interestLeft == nil && bare.paymentsLeft == 43)
    }

    @Test func whatIfOnlyForMonthlyCalculatedRateLoans() throws {
        func loan(_ extra: String) throws -> Loan {
            let json = """
            {"id":1,"type":"loan","currency":"USD","principal":1000,"annualRate":5,"startDate":"2026-01-01",\(extra)}
            """
            return try JSONDecoder().decode(Loan.self, from: Data(json.utf8))
        }
        #expect(WealthModel.supportsWhatIf(try loan(#""paymentFrequency":"monthly","interestMethod":"rate","scheduleMode":"calculated""#)))
        #expect(WealthModel.supportsWhatIf(try loan(#""paymentFrequency":"monthly""#)))
        #expect(!WealthModel.supportsWhatIf(try loan(#""paymentFrequency":"biweekly""#)))
        #expect(!WealthModel.supportsWhatIf(try loan(#""paymentFrequency":"monthly","interestMethod":"flat""#)))
        #expect(!WealthModel.supportsWhatIf(try loan(#""paymentFrequency":"monthly","scheduleMode":"manual""#)))
    }

    @Test func debtProjectionFollowsTheServerSchedule() throws {
        let (loan, schedule) = try fixtureLoan()
        let projection = WealthModel.debtProjection([(loan, schedule.schedule)], today: today)
        let rate = WealthModel.displayRate(loan)
        #expect(abs((projection.first?.value ?? 0) - WealthModel.remaining(loan) * rate) < 0.01)
        #expect(projection.first?.day == today)
        #expect(projection.last?.value == 0)
        #expect(projection.last?.day == day(2030, 5, 15))
        #expect(projection.count == 44) // today plus 43 payments
    }

    /// The local engine is only used for What-if deltas. Against the captured server schedule its first year agrees
    /// within a cent per row; the server keeps full precision between periods, so the totals drift by cents.
    @Test func localScheduleAgreesWithTheServerOnTheFirstRows() throws {
        let (_, schedule) = try fixtureLoan()
        let local = Amortization.schedule(principal: 15000, annualRate: 5.9, payment: 351.59, start: day(2026, 6, 15))
        for (mine, theirs) in zip(local.prefix(12), schedule.schedule) {
            #expect(abs(mine.interest - theirs.interest) < 0.0101, "period \(theirs.period)")
            #expect(abs(mine.principal - theirs.principal) < 0.0101, "period \(theirs.period)")
        }
        #expect(abs(Amortization.totalInterest(local) - schedule.totalInterest) < 0.05)
    }

    @Test func lastPaymentIsTheNewestMoneyIntoTheCard() throws {
        let rows = [
            try transaction(1, "2026-11-05", -80, account: 3), try transaction(2, "2026-10-22", 2480, account: 3, link: "a"),
            try transaction(3, "2026-09-22", 1900, account: 3, link: "b")
        ]
        #expect(WealthModel.lastPayment(rows)?.id == 2)
        #expect(WealthModel.lastPayment([try transaction(1, "2026-11-05", -80)]) == nil)
    }

    @Test func scheduleSplitsAroundToday() throws {
        let schedule = try JSONDecoder().decode(Amortization.self, from: try #require(Fixtures.data(for: "/api/loans/amortization")))
        let split = WealthModel.split(schedule.schedule, today: today)
        #expect(split.paid.count == 5) // Jun to Oct 2026
        #expect(split.next?.date == "2026-11-15")
        #expect(split.rest.count == 42)
        let bars = WealthModel.yearBars(schedule.schedule)
        #expect(bars.map(\.year) == [2026, 2027, 2028, 2029, 2030])
        #expect(abs((bars.first?.interest ?? 0) - (73.75 + 72.38 + 71.01 + 69.63 + 68.25 + 66.85 + 65.45) / 7) < 0.01)
    }

    @Test func fitColumnsDropsLowPriorityColumnsFirst() {
        let widths: [(String, Double)] = [("shares", 40), ("price", 80), ("value", 90), ("day", 50)]
        let all = WealthModel.fitColumns(widths, dropOrder: ["shares", "price"], available: 500, flexible: 100, spacing: 8)
        #expect(all == ["shares", "price", "value", "day"])
        // 100 + 90 + 50 + 2 gaps of 8 = 256 fits; adding price (80 + 8) does not fit in 300.
        let narrow = WealthModel.fitColumns(widths, dropOrder: ["shares", "price"], available: 300, flexible: 100, spacing: 8)
        #expect(narrow == ["value", "day"])
        let middle = WealthModel.fitColumns(widths, dropOrder: ["shares", "price"], available: 350, flexible: 100, spacing: 8)
        #expect(middle == ["price", "value", "day"])
    }

    @Test func displayScaleMatchesTheLastPointToTodaysValue() {
        #expect(WealthModel.displayScale(20000, display: 1_880_000) == 94)
        #expect(WealthModel.displayScale(nil, display: 5) == 1)
        #expect(WealthModel.displayScale(0, display: 5) == 1)
    }

    @Test func fitColumnsAddsBackAColumnThatFitsAfterALaterDrop() {
        let widths: [(String, Double)] = [("shares", 40), ("price", 80), ("value", 90), ("day", 50)]
        // Dropping shares (40) isn't enough at 310, so price goes too; that frees room for shares to come back.
        let kept = WealthModel.fitColumns(widths, dropOrder: ["shares", "price"], available: 310, flexible: 100, spacing: 8)
        #expect(kept == ["shares", "value", "day"])
    }

    @Test func payoffNoteExplainsAPayoffThatDiffersFromTheSchedule() {
        let note = WealthModel.payoffNote(payoff: day(2030, 6, 10), scheduleEnd: day(2030, 5, 15), frequency: "monthly")
        #expect(note == "At your current balance you\u{2019}ll finish Jun 2030, 1 payment later than scheduled")
        let early = WealthModel.payoffNote(payoff: day(2030, 1, 15), scheduleEnd: day(2030, 5, 15), frequency: "monthly")
        #expect(early == "At your current balance you\u{2019}ll finish Jan 2030, 4 payments earlier than scheduled")
        let biweekly = WealthModel.payoffNote(payoff: day(2030, 7, 15), scheduleEnd: day(2030, 5, 15), frequency: "biweekly")
        #expect(biweekly == "At your current balance you\u{2019}ll finish Jul 2030, 4 payments later than scheduled")
        #expect(WealthModel.payoffNote(payoff: day(2030, 5, 30), scheduleEnd: day(2030, 5, 15), frequency: "monthly") == nil)
        #expect(WealthModel.payoffNote(payoff: nil, scheduleEnd: day(2030, 5, 15), frequency: "monthly") == nil)
    }

    @Test func paymentLabelNamesThePeriod() throws {
        func loan(_ frequency: String) throws -> Loan {
            let json = """
            {"id":1,"type":"loan","currency":"USD","principal":1000,"annualRate":5,"startDate":"2026-01-01",
             "paymentFrequency":"\(frequency)","paymentPerPeriod":600}
            """
            return try JSONDecoder().decode(Loan.self, from: Data(json.utf8))
        }
        let usd = 600.0.wholeMoney("USD")
        #expect(WealthModel.paymentLabel(try loan("monthly"), short: true) == "\(usd)/mo")
        #expect(WealthModel.paymentLabel(try loan("monthly"), short: false) == "\(usd) / month")
        #expect(WealthModel.paymentLabel(try loan("biweekly"), short: true) == "\(usd) / payment")
        #expect(WealthModel.paymentLabel(try loan("biweekly"), short: false) == "\(usd) / payment")
    }

    @Test func holdingUpdateHasOnlyTheChangedFields() {
        let original = WealthModel.HoldingFields(name: "VTI", symbol: "VTI", currency: "USD", isCrypto: false, note: "")
        var edited = original
        #expect(WealthModel.holdingUpdate(id: 7, original: original, edited: edited) == nil)
        edited.name = "Total market"
        edited.isCrypto = true
        let update = WealthModel.holdingUpdate(id: 7, original: original, edited: edited)
        #expect(update == HoldingUpdate(id: 7, name: "Total market", isCrypto: 1))
    }

    @Test func prefillKeepsWhatTheUserTyped() {
        let shown = WealthModel.HoldingFields(name: "VTI", symbol: "VTI", currency: "USD", isCrypto: false, note: "")
        let saved = WealthModel.HoldingFields(name: "Vanguard Total", symbol: "VTI", currency: "USD", isCrypto: false, note: "Core")
        var typed = shown
        typed.name = "Total market"
        let filled = WealthModel.prefill(typed, shown: shown, saved: saved)
        #expect(filled.name == "Total market", "typed before the row arrived")
        #expect(filled.note == "Core", "untouched, so the saved value fills it")
    }

    @Test func reselectFollowsARenamedHolding() throws {
        let data = try #require(Fixtures.data(for: "/api/portfolio/overview"))
        let holdings = try JSONDecoder().decode(PortfolioOverview.self, from: data).byHolding
        let first = try #require(holdings.first)
        let other = try #require(holdings.last)
        #expect(WealthModel.reselect(holdings, selected: first.key, renamed: nil) == first.key)
        #expect(WealthModel.reselect(holdings, selected: "eq:OLD", renamed: other.symbol) == other.key, "renamed to an existing symbol")
        #expect(WealthModel.reselect(holdings, selected: "eq:OLD", renamed: nil) == nil, "stale: back to the first holding")
    }

    @Test func holdingPageKeepsTheOldRowUntilTheRenameArrives() throws {
        let data = try #require(Fixtures.data(for: "/api/portfolio/overview"))
        let holdings = try JSONDecoder().decode(PortfolioOverview.self, from: data).byHolding
        let first = try #require(holdings.first { $0.symbol != nil })
        let other = try #require(holdings.last { $0.symbol != nil && $0.key != first.key })
        let symbol = try #require(first.symbol)
        #expect(WealthModel.holding(in: holdings, symbol: symbol, renamed: nil)?.key == first.key)
        #expect(WealthModel.holding(in: holdings, symbol: symbol, renamed: "NEW")?.key == first.key, "reload pending or failed")
        #expect(WealthModel.holding(in: holdings, symbol: symbol, renamed: other.symbol)?.key == other.key, "reload has the new row")
        #expect(WealthModel.holding(in: holdings, symbol: "GONE", renamed: nil) == nil)
    }

    @Test func investmentsShowTheHoldingBesideTheListOnlyWhenThereIsRoom() {
        #expect(!InvestmentsView.showsPane(.compact, column: 900))
        #expect(!InvestmentsView.showsPane(.medium, column: 554), "iPad portrait pushes the holding")
        #expect(InvestmentsView.showsPane(.medium, column: 669), "the Duo's open display shows it beside the list")
        #expect(InvestmentsView.showsPane(.wide, column: 900))
        #expect(!InvestmentsView.showsPane(.wide, column: 0), "nothing beside the list before the screen is measured")
    }

    @Test @MainActor func loanScheduleCardShowsTheLastPaidRowTheNextAndThreeMore() {
        let rows = (1...8).map {
            Amortization.Row(period: $0, date: "2026-\(String(format: "%02d", $0 + 3))-15", payment: 540, principal: 430, interest: 110,
                             extraPayment: nil, balance: Double(20_000 - $0 * 430))
        }
        let split = WealthModel.split(rows, today: APIDate.parse("2026-07-01")!)
        #expect(WealthModel.scheduleWindow(split).map(\.period) == [3, 4, 5, 6, 7])
    }

    @Test func largerTextNeedsAWiderPaneBeforeTheHoldingSitsBesideTheList() {
        #expect(InvestmentsView.showsPane(.medium, column: 669, typeSize: .large))
        #expect(!InvestmentsView.showsPane(.medium, column: 669, typeSize: .xxLarge), "669 / (21/17) is under 640")
        #expect(InvestmentsView.showsPane(.medium, column: 669, typeSize: .xSmall), "smaller text never needs less room")
    }

    @Test @MainActor func whatIfPaymentsLeftComeFromTheServerCount() {
        let result = WealthModel.WhatIf(monthsSooner: 7, interestSaved: 394)
        #expect(WealthModel.paymentsLeft(41, with: result) == 34)
        #expect(WealthModel.paymentsLeft(nil, with: result) == nil, "no chip without the server's count")
        #expect(WealthModel.paymentsLeft(5, with: result) == 0)
    }

    @Test @MainActor func cashNoteSaysBalancedOrTheLatestMoneyIn() throws {
        let balanced = try JSONDecoder().decode(BalanceSummary.self, from: Data("""
        {"accountId":1,"currency":"CAD","latestAnchor":{"statementDate":"2026-11-08"},"bankSideLatest":9200.85,
         "systemSideLatest":9200.85,"delta":0,"status":"balanced"}
        """.utf8))
        #expect(WealthModel.cashNote(check: balanced, latestIn: nil) == "Balanced with the bank on Nov 8")
        let noDelta = try JSONDecoder().decode(BalanceSummary.self, from: Data("""
        {"accountId":1,"currency":"CAD","latestAnchor":{"statementDate":"2026-11-08"},"bankSideLatest":9200.85,
         "status":"balanced"}
        """.utf8))
        #expect(WealthModel.cashNote(check: noDelta, latestIn: nil) == "Balanced with the bank on Nov 8")
        let transfer = try JSONDecoder().decode(Transaction.self, from: Data("""
        {"id":5,"date":"2026-11-07","accountId":2,"currency":"CAD","amount":500,"payee":"Transfer","linkId":"abc"}
        """.utf8))
        let note = try #require(WealthModel.cashNote(check: nil, latestIn: transfer))
        #expect(note.hasSuffix("transfer in on Nov 7") && note.contains("500.00"))
        #expect(WealthModel.cashNote(check: nil, latestIn: nil) == nil)
    }
}
