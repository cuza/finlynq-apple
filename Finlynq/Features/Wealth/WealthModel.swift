import Foundation

/// What the Wealth screens show, as pure functions of the loaded data and a passed-in "today".
nonisolated enum WealthModel {
    private static let calendar = Calendar(identifier: .gregorian)

    /// Assets and debts in display currency. Debts are negative. Same split as Home.
    static func split(_ balances: [Dashboard.Balance]) -> (assets: Double, debts: Double) { HomeModel.split(balances) }

    /// Active asset accounts that aren't investment accounts, in server order.
    static func cash(_ balances: [Dashboard.Balance]) -> [Dashboard.Balance] {
        balances.filter { !$0.archived && !$0.isLiability && !$0.isInvestment }
    }

    static func investmentAccounts(_ balances: [Dashboard.Balance]) -> [Dashboard.Balance] {
        balances.filter { !$0.archived && $0.isInvestment }
    }

    /// Active liabilities, largest owed first.
    static func debts(_ balances: [Dashboard.Balance]) -> [Dashboard.Balance] {
        balances.filter { !$0.archived && $0.isLiability }.sorted { $0.convertedBalance < $1.convertedBalance }
    }

    // MARK: Accounts

    /// An account's balance per day: its own member of the history when present, else the series value
    /// (the server returns only that account when asked for one).
    /// `toNative` converts the history's display-currency values to the account's currency.
    static func accountSeries(_ points: [NetWorthHistory.Point], accountId: Int, toNative: Double = 1) -> [ValuePoint] {
        points.map { point in
            ValuePoint(day: point.day, value: (point.members?.first { $0.id == accountId }?.value ?? point.value) * toNative)
        }
    }

    /// Display currency to the account's currency, from the dashboard's two balances. 1 when either is zero.
    static func nativeRate(_ balance: Dashboard.Balance) -> Double {
        balance.convertedBalance != 0 && balance.balance != 0 ? balance.balance / balance.convertedBalance : 1
    }

    struct Flows: Equatable {
        var moneyIn = 0.0
        var deposits = 0
        /// Negative.
        var moneyOut = 0.0
        /// Negative: the part of `moneyOut` that went to other accounts.
        var transfersOut = 0.0
    }

    /// Money in and out of one account in today's month.
    static func monthFlows(_ rows: [Transaction], accountId: Int, today: Date) -> Flows {
        let month = APIDate.string(today).prefix(7)
        return rows.filter { $0.accountId == accountId && $0.date.prefix(7) == month }.reduce(into: Flows()) { flows, row in
            if row.amount > 0 {
                flows.moneyIn += row.amount
                flows.deposits += 1
            } else {
                flows.moneyOut += row.amount
                if row.isTransfer { flows.transfersOut += row.amount }
            }
        }
    }

    /// The balance at the end of each day that has rows, working back from the current balance. `rows` must be
    /// the account's newest rows with no gaps, as one page of `GET /api/transactions?accountId=` is.
    static func dayBalances(_ rows: [Transaction], current: Double) -> [Date: Double] {
        var balance = current
        var result: [Date: Double] = [:]
        for group in ActivityModel.groupByDay(rows) {
            result[group.day] = balance
            balance -= group.rows.reduce(0) { $0 + $1.amount }
        }
        return result
    }

    // MARK: Investments

    /// A share of the portfolio for allocation bars and their legends. `share` is a fraction.
    struct Slice: Identifiable, Equatable {
        let id: String
        let name: String
        let share: Double
    }

    /// Asset types with a value, largest first. Names follow the designs: ETFs, Stocks, Crypto, Cash, Metals.
    static func allocation(_ byType: [String: PortfolioOverview.TypeTotal]) -> [Slice] {
        let names = ["etf": "ETFs", "stock": "Stocks", "crypto": "Crypto", "cash": "Cash", "metal": "Metals"]
        let total = byType.values.reduce(0) { $0 + max($1.value, 0) }
        guard total > 0 else { return [] }
        return byType.filter { $0.value.value > 0 }
            .map { Slice(id: $0.key, name: names[$0.key] ?? $0.key.capitalized, share: $0.value.value / total) }
            .sorted { $0.share > $1.share }
    }

    /// The largest holdings by value, for the Wealth card. Holdings past `limit` are left out of the legend.
    static func topHoldings(_ holdings: [PortfolioOverview.Holding], limit: Int) -> [Slice] {
        let total = holdings.reduce(0) { $0 + max($1.marketValueDisplay, 0) }
        guard total > 0 else { return [] }
        return holdings.filter { $0.marketValueDisplay > 0 }.sorted { $0.marketValueDisplay > $1.marketValueDisplay }
            .prefix(limit).map { Slice(id: $0.key, name: $0.symbol ?? $0.name, share: $0.marketValueDisplay / total) }
    }

    /// The factor that turns a series in the server's currency into the display currency: today's display value over
    /// the series' last value. 1 when either is missing or zero.
    static func displayScale(_ seriesLast: Double?, display: Double?) -> Double {
        guard let seriesLast, let display, seriesLast != 0, display != 0 else { return 1 }
        return display / seriesLast
    }

    /// Points of a performance series inside the period ending at `today`: 1m, 6m, ytd, 1y or all.
    static func trim<Point>(_ points: [Point], period: String, today: Date, date: (Point) -> Date) -> [Point] {
        let start: Date? = switch period {
        case "1m": calendar.date(byAdding: .month, value: -1, to: today)
        case "6m": calendar.date(byAdding: .month, value: -6, to: today)
        case "ytd": calendar.dateInterval(of: .year, for: today)?.start
        case "1y": calendar.date(byAdding: .year, value: -1, to: today)
        default: nil
        }
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today)) ?? today
        return points.filter { point in date(point) < end && (start.map { date(point) >= $0 } ?? true) }
    }

    // MARK: Loans

    /// The loan's payment per month: what the server computed, else the saved payment.
    static func payment(_ loan: Loan) -> Double { loan.paymentPerPeriod ?? loan.monthlyPayment ?? loan.paymentAmount ?? 0 }

    /// "$1,240/mo" or "$1,240 / month" for a monthly loan; "$600 / payment" for any other frequency.
    static func paymentLabel(_ loan: Loan, short: Bool) -> String {
        let amount = payment(loan).wholeMoney(loan.currency)
        guard (loan.paymentFrequency ?? "monthly") == "monthly" else { return amount + " / payment" }
        return amount + (short ? "/mo" : " / month")
    }

    /// One line when the payoff at the current balance (the server's `payoffDate`) falls in a different month from
    /// the end of the server's schedule, which runs from the loan's original terms. Nil when they agree.
    static func payoffNote(payoff: Date?, scheduleEnd: Date?, frequency: String?) -> String? {
        guard let payoff, let scheduleEnd else { return nil }
        let months = calendar.dateComponents([.month], from: monthStart(scheduleEnd), to: monthStart(payoff)).month ?? 0
        guard months != 0 else { return nil }
        let perYear: Double = switch frequency ?? "monthly" {
        case "weekly": 52
        case "biweekly": 26
        case "semi_monthly": 24
        case "quarterly": 4
        case "annual": 1
        default: 12
        }
        let payments = max(Int((Double(abs(months)) * perYear / 12).rounded()), 1)
        let unit = payments == 1 ? "payment" : "payments"
        let direction = months > 0 ? "later" : "earlier"
        return "At your current balance you\u{2019}ll finish \(payoff.monthYear), \(payments) \(unit) \(direction) than scheduled"
    }

    private static func monthStart(_ date: Date) -> Date { calendar.dateInterval(of: .month, for: date)?.start ?? date }

    /// The editable fields of a holding row.
    struct HoldingFields: Equatable {
        var name: String
        var symbol: String
        var currency: String
        var isCrypto: Bool
        var note: String
    }

    /// The edit sheet's fields once the saved row arrives: each field the user hasn't changed from `shown` takes the
    /// saved value, and each one they changed keeps their text.
    static func prefill(_ fields: HoldingFields, shown: HoldingFields, saved: HoldingFields) -> HoldingFields {
        HoldingFields(
            name: fields.name == shown.name ? saved.name : fields.name,
            symbol: fields.symbol == shown.symbol ? saved.symbol : fields.symbol,
            currency: fields.currency == shown.currency ? saved.currency : fields.currency,
            isCrypto: fields.isCrypto == shown.isCrypto ? saved.isCrypto : fields.isCrypto,
            note: fields.note == shown.note ? saved.note : fields.note
        )
    }

    /// The holding to keep selected on iPad and Mac after a reload: `selected` while it still exists, else the
    /// holding now carrying `renamed` (a symbol change gives a holding a new key), else nil for the first holding.
    static func reselect(_ holdings: [PortfolioOverview.Holding], selected: String?, renamed: String?) -> String? {
        if let selected, holdings.contains(where: { $0.key == selected }) { return selected }
        return renamed.flatMap { symbol in holdings.first { $0.symbol == symbol }?.key }
    }

    /// The holding the iPhone page shows: the one carrying `renamed` once a reload has it, else the one it opened
    /// with, so the page keeps the old row until the renamed one arrives and keeps it if the reload fails.
    static func holding(in holdings: [PortfolioOverview.Holding], symbol: String, renamed: String?) -> PortfolioOverview.Holding? {
        let find = { (key: String) in holdings.first { $0.symbol == key || $0.key == key || $0.name == key } }
        return renamed.flatMap(find) ?? find(symbol)
    }

    /// The update for the fields that changed, or nil when nothing did.
    static func holdingUpdate(id: Int, original: HoldingFields, edited: HoldingFields) -> HoldingUpdate? {
        var update = HoldingUpdate(id: id)
        if edited.name != original.name { update.name = edited.name }
        if edited.symbol != original.symbol { update.symbol = edited.symbol }
        if edited.currency != original.currency { update.currency = edited.currency }
        if edited.isCrypto != original.isCrypto { update.isCrypto = edited.isCrypto ? 1 : 0 }
        if edited.note != original.note { update.note = edited.note }
        return update == HoldingUpdate(id: id) ? nil : update
    }

    /// "6.4%".
    static func rateText(_ loan: Loan) -> String { loan.annualRate.formatted(.number.precision(.fractionLength(0...2))) + "%" }

    static func remaining(_ loan: Loan) -> Double { loan.remainingBalance ?? loan.principal }

    /// Share of the original principal paid off, 0 to 1.
    static func percentPaid(_ loan: Loan) -> Double {
        guard loan.principal > 0 else { return 0 }
        return min(max(1 - remaining(loan) / loan.principal, 0), 1)
    }

    /// The first payment date on or after today. Payments fall monthly from one month after the start date.
    static func nextDue(_ loan: Loan, today: Date) -> Date? {
        guard let start = APIDate.parse(loan.startDate) else { return nil }
        let day = calendar.startOfDay(for: today)
        let months = max(calendar.dateComponents([.month], from: start, to: day).month ?? 0, 0)
        // Start a month early: whole months between the dates can overshoot by one around month ends.
        for offset in max(months - 1, 1)...(months + 2) {
            if let date = calendar.date(byAdding: .month, value: offset, to: start), date >= day { return date }
        }
        return nil
    }

    /// The remaining payments, from the remaining balance on the next due date, with the loan's saved extra plus
    /// `extra`. Empty for a paid-off loan or one whose payment doesn't cover its interest.
    static func plan(_ loan: Loan, today: Date, extra: Double = 0) -> [Amortization.Payment] {
        guard let next = nextDue(loan, today: today) else { return [] }
        return Amortization.schedule(
            principal: remaining(loan), annualRate: loan.annualRate, payment: payment(loan),
            extra: (loan.extraPayment ?? 0) + extra, start: next
        )
    }

    /// What-if only runs on loans the local engine models: monthly payments, interest from a yearly rate, and the
    /// server's calculated schedule (not one the user typed in).
    static func supportsWhatIf(_ loan: Loan) -> Bool {
        (loan.paymentFrequency ?? "monthly") == "monthly" && (loan.interestMethod ?? "rate") == "rate"
            && (loan.scheduleMode ?? "calculated") == "calculated"
    }

    /// The difference an extra monthly payment makes, from the local schedule with and without it. Dates shown to
    /// the user come from the server; `payoff(from:)` moves the server's payoff date back by the months saved.
    struct WhatIf: Equatable {
        let monthsSooner: Int
        let interestSaved: Double

        func payoff(from serverPayoff: Date) -> Date {
            Calendar(identifier: .gregorian).date(byAdding: .month, value: -monthsSooner, to: serverPayoff) ?? serverPayoff
        }
    }

    /// Paying `extra` more each month against the current plan. Nil when either plan never pays off.
    static func whatIf(_ loan: Loan, extra: Double, today: Date) -> WhatIf? {
        let base = plan(loan, today: today)
        let faster = plan(loan, today: today, extra: extra)
        guard !base.isEmpty, !faster.isEmpty else { return nil }
        return WhatIf(
            monthsSooner: base.count - faster.count,
            interestSaved: Amortization.totalInterest(base) - Amortization.totalInterest(faster)
        )
    }

    /// What the loan screens show, all from the server: payoff and payments left from `GET /api/loans`, the next
    /// payments and interest from its amortization schedule. Fields are nil when the server didn't send them.
    struct LoanFacts {
        let payoff: Date?
        let paymentsLeft: Int?
        /// Schedule rows due today or later.
        let upcoming: [Amortization.Row]
        let interestLeft: Double?
        var next: Amortization.Row? { upcoming.first }
    }

    static func facts(_ loan: Loan, schedule: Amortization?, today: Date) -> LoanFacts {
        let day = APIDate.string(today)
        let upcoming = schedule?.schedule.filter { $0.date >= day } ?? []
        return LoanFacts(
            payoff: (loan.payoffDate ?? schedule?.payoffDate).flatMap(APIDate.parse),
            paymentsLeft: loan.periodsRemaining ?? (schedule == nil ? nil : upcoming.count),
            upcoming: upcoming,
            interestLeft: schedule.map { _ in upcoming.reduce(0) { $0 + $1.interest } }
        )
    }

    /// Interest in a calendar year's rows of a server schedule.
    static func interest(_ rows: [Amortization.Row], year: Int) -> Double {
        rows.filter { $0.date.hasPrefix(String(year)) }.reduce(0) { $0 + $1.interest }
    }

    /// "Last paid $2,480 on Oct 22".
    static func lastPaidText(_ payment: Transaction) -> String {
        "Last paid \(payment.amount.wholeMoney(payment.currency)) on \(payment.day.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// The newest money into an account, such as the latest payment to a credit card.
    static func lastPayment(_ rows: [Transaction]) -> Transaction? {
        rows.filter { $0.amount > 0 }.max { $0.date < $1.date }
    }

    /// A server schedule split around today: rows already due, the next one, and the rest.
    struct ScheduleSplit {
        var paid: [Amortization.Row] = []
        var next: Amortization.Row?
        var rest: [Amortization.Row] = []
    }

    static func split(_ rows: [Amortization.Row], today: Date) -> ScheduleSplit {
        let day = APIDate.string(today)
        let upcoming = rows.filter { $0.date >= day }
        return ScheduleSplit(paid: rows.filter { $0.date < day }, next: upcoming.first, rest: Array(upcoming.dropFirst()))
    }

    /// Average principal and interest per payment in each calendar year, for the Loan payoff bars.
    struct YearBar: Identifiable {
        let year: Int
        let principal: Double
        let interest: Double
        var id: Int { year }
    }

    static func yearBars(_ rows: [Amortization.Row]) -> [YearBar] {
        let years = Dictionary(grouping: rows) { Int($0.date.prefix(4)) ?? 0 }
        return years.keys.sorted().map { year in
            let items = years[year] ?? []
            let count = Double(max(items.count, 1))
            return YearBar(year: year, principal: items.reduce(0) { $0 + $1.principal } / count,
                interest: items.reduce(0) { $0 + $1.interest } / count)
        }
    }

    // MARK: Debts

    /// The loan currency's rate to the display currency, from the server's converted remaining balance.
    static func displayRate(_ loan: Loan) -> Double {
        guard let display = loan.remainingBalanceDisplay, let native = loan.remainingBalance, native != 0 else { return 1 }
        return display / native
    }

    /// Total owed on all loans in the display currency: today, then after each remaining payment of each loan's
    /// server schedule.
    static func debtProjection(_ loans: [(loan: Loan, rows: [Amortization.Row])], today: Date) -> [ValuePoint] {
        let day = APIDate.string(today)
        let plans = loans.map { (loan: $0.loan, rows: $0.rows.filter { $0.date >= day }, rate: displayRate($0.loan)) }
            .filter { !$0.rows.isEmpty }
        guard !plans.isEmpty else { return [] }
        let start = plans.reduce(0) { $0 + remaining($1.loan) * $1.rate }
        let dates = Set(plans.flatMap { $0.rows.map(\.date) }).sorted()
        return [ValuePoint(day: calendar.startOfDay(for: today), value: start)] + dates.map { date in
            ValuePoint(day: APIDate.parse(date) ?? today, value: plans.reduce(0) { total, plan in
                total + (plan.rows.last { $0.date <= date }?.balance ?? remaining(plan.loan)) * plan.rate
            })
        }
    }

    // MARK: Tables

    /// The columns that fit beside a flexible first column at least `flexible` wide. Columns in `dropOrder` go first,
    /// in that order, until the rest fit. Returns the kept columns in their original order.
    static func fitColumns<ID: Hashable>(
        _ widths: [(ID, Double)], dropOrder: [ID], available: Double, flexible: Double, spacing: Double
    ) -> [ID] {
        var kept = widths.map(\.0)
        func needed() -> Double {
            flexible + kept.reduce(0) { total, id in total + (widths.first { $0.0 == id }?.1 ?? 0) + spacing }
        }
        var dropped: [ID] = []
        for id in dropOrder where needed() > available {
            kept.removeAll { $0 == id }
            dropped.append(id)
        }
        // A later drop can free enough room for an earlier, narrower column: try them again, most important first.
        for id in dropped.reversed() {
            let trial = widths.map(\.0).filter { kept.contains($0) || $0 == id }
            let saved = kept
            kept = trial
            if needed() > available { kept = saved }
        }
        return kept
    }

    // MARK: CSV

    private static func number(_ value: Double?, digits: Int = 2) -> String {
        value.map { CSV.number($0, digits: digits) } ?? ""
    }

    /// Amortization rows as CSV: #, Date, Payment, Principal, Interest, Balance.
    static func scheduleCSV(_ rows: [Amortization.Row]) -> String {
        let lines = rows.map { row in
            [String(row.period), String(row.date.prefix(10)), number(row.payment), number(row.principal), number(row.interest),
                number(row.balance)]
                .joined(separator: ",")
        }
        return (["#,Date,Payment,Principal,Interest,Balance"] + lines).joined(separator: "\n") + "\n"
    }

    /// Holdings as CSV in the display currency. Percents are in percent units (12.3 is 12.3%).
    static func holdingsCSV(_ holdings: [PortfolioOverview.Holding]) -> String {
        let header = "Symbol,Name,Shares,Avg cost,Price,Value,Day %,Unrealized,Realized,Dividends,Total return %,Of portfolio %"
        let lines = holdings.map { row in
            [
                CSV.text(row.symbol ?? ""), CSV.text(row.name), number(row.totalQty, digits: 4),
                number(row.avgCostDisplay), number(row.currentPriceDisplay), number(row.marketValueDisplay), number(row.dayChangePct),
                number(row.unrealizedGainDisplay), number(row.realizedGainDisplay), number(row.dividendsDisplay),
                number(row.totalReturnPct), number(row.pctOfPortfolio)
            ].joined(separator: ",")
        }
        return ([header] + lines).joined(separator: "\n") + "\n"
    }
}

extension WealthModel {
    /// The line under a cash account on wider columns: "Balanced with the bank on Nov 8", "Off by $12.40 from the bank
    /// on Nov 8", or the latest money in: "$500.00 transfer in on Nov 7", "$3,200.00 from Acme on Nov 1".
    static func cashNote(check: BalanceSummary?, latestIn: Transaction?) -> String? {
        let day = Date.FormatStyle.dateTime.month(.abbreviated).day()
        if let check, check.bankSideLatest != nil, let date = check.anchorDate {
            // The server's "balanced" status counts even when it sends no delta.
            if check.status == "balanced" || check.delta.map({ abs($0) < 0.005 }) == true {
                return "Balanced with the bank on \(date.formatted(day))"
            }
            if let delta = check.delta {
                return "Off by \(abs(delta).money(check.currency)) from the bank on \(date.formatted(day))"
            }
        }
        guard let money = latestIn else { return nil }
        let amount = money.amount.money(money.currency), date = money.day.formatted(day)
        if money.isTransfer { return "\(amount) transfer in on \(date)" }
        if let payee = money.payee, !payee.isEmpty { return "\(amount) from \(payee) on \(date)" }
        return "\(amount) in on \(date)"
    }

    /// Payments left with the extra payment: the server's count less the months the extra saves (R30). Nil without
    /// a server count.
    static func paymentsLeft(_ serverCount: Int?, with result: WhatIf) -> Int? {
        serverCount.map { max(0, $0 - result.monthsSooner) }
    }

    /// The schedule card's rows on wider screens: the last paid row, the next one and the three after it.
    static func scheduleWindow(_ split: ScheduleSplit) -> [Amortization.Row] {
        Array(split.paid.suffix(1)) + [split.next].compactMap { $0 } + Array(split.rest.prefix(3))
    }
}
