import Foundation

nonisolated struct AttentionItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case review(count: Int)
        case budgetWarning(categoryName: String, percent: Int, left: Double)
        case billsThisWeek(count: Int, total: Double, names: [String])
        case applePay(count: Int)
    }

    let kind: Kind
    let title: String
    let subtitle: String
    let route: AppRoute
    /// The amount at the row's end on iPad portrait and iPhone Duo: "$780 over" or "$32 left".
    var trailing: String?

    /// Stable per row so rows keep their identity when counts and text change.
    var id: String {
        switch kind {
        case .review: "review"
        case .budgetWarning(let name, _, _): "budget:" + name
        case .billsThisWeek: "bills"
        case .applePay: "applepay"
        }
    }
}

/// A payment due soon: an active subscription, or a scheduled loan payment from the month's budget.
nonisolated struct Bill: Identifiable, Equatable {
    let id: String
    let name: String
    let date: Date
    /// In display currency.
    let amount: Double
    /// The category for a subscription, "Loan payment" for a loan.
    let category: String?
    /// The account the bill is charged to. For a loan, the account that paid its latest payment.
    let account: String?
    let accountId: Int?
    var isLoan = false
}

/// One segment of the budget bar and its legend entry: a spending group, or "Other" for the groups past the limit.
nonisolated struct BudgetSlice: Identifiable, Equatable {
    let id: String
    let name: String
    let spent: Double
    let budgeted: Double?
    /// "Fuel over" when a category in the slice is over its budget.
    let flag: String?
    let isOther: Bool
}

extension Double {
    /// Whole units for tiles and sentences, e.g. "$1,282". Negatives use U+2212.
    nonisolated func wholeMoney(_ currency: String?) -> String {
        let text = abs(self).formatted(.currency(code: currency ?? "USD").precision(.fractionLength(0)))
        return self < 0 ? "\u{2212}" + text : text
    }
}

/// What Home shows, as pure functions of the loaded data and a passed-in "today".
nonisolated struct HomeModel {
    /// A category is flagged from this share of its budget.
    static let warnAt = 0.9
    private static let calendar = Calendar(identifier: .gregorian)

    /// Review first, then budget warnings worst first, then bills. `wide` layouts list every budget warning and
    /// leave bills out (they have their own card); the phone shows the worst warning and a bills row.
    /// `trailing` (iPad portrait, iPhone Duo) titles a warning with the category's name, says what was spent of the
    /// budget below it, and moves "$780 over" or "$32 left" to the row's end.
    static func attention(
        stagedCount: Int, budget: BudgetMonth?, bills: [Bill], today: Date, currency: String? = nil,
        reviewAccount: String? = nil, wide: Bool = false, trailing: Bool = false
    ) -> [AttentionItem] {
        var items: [AttentionItem] = []
        if stagedCount > 0 {
            items.append(AttentionItem(
                kind: .review(count: stagedCount), title: "Transactions to review",
                subtitle: reviewAccount.map { "From the \($0) import" } ?? "From your imports", route: .review
            ))
        }
        let warnings = budget.map { budgetWarnings($0, today: today, currency: currency, trailing: trailing) } ?? []
        items += wide ? warnings : Array(warnings.prefix(1))
        if !wide, let item = billsItem(bills, currency: currency) { items.append(item) }
        return items
    }

    /// Apple Pay purchases that need the user (an amount, account or category, or a fix after the server refused one).
    static func applePayItem(_ waiting: [CapturedPurchase]) -> AttentionItem? {
        let stuck = waiting.filter { $0.problem != nil && $0.problem != .notSent }
        guard let first = stuck.first, let problem = first.problem else { return nil }
        let title = stuck.count == 1 ? "Apple Pay purchase waiting" : "\(stuck.count) Apple Pay purchases waiting"
        return AttentionItem(
            kind: .applePay(count: stuck.count), title: title, subtitle: "\(first.merchant): \(problem.text)", route: .applePay
        )
    }

    private static func budgetWarnings(_ budget: BudgetMonth, today: Date, currency: String?, trailing: Bool) -> [AttentionItem] {
        budget.spending.flatMap(\.lines)
            .filter { ($0.budgeted ?? 0) > 0 && ratio($0) >= warnAt }
            .sorted { ratio($0) > ratio($1) }
            .map { line in
                let budgeted = line.budgeted ?? 0
                let left = budgeted - line.actual
                let percent = Int(ratio(line) * 100)
                let title: String
                let subtitle: String
                if left < 0 {
                    title = "\(line.name) is \((-left).wholeMoney(currency)) over"
                    subtitle = "\(line.actual.wholeMoney(currency)) spent of \(budgeted.wholeMoney(currency))"
                } else {
                    let days = daysLeft(in: today)
                    title = "\(line.name) is at \(percent)%"
                    subtitle = "\(left.wholeMoney(currency)) left with \(days) \(days == 1 ? "day" : "days") to go"
                }
                let kind = AttentionItem.Kind.budgetWarning(categoryName: line.name, percent: percent, left: left)
                if trailing {
                    return AttentionItem(
                        kind: kind, title: line.name,
                        subtitle: "\(line.actual.wholeMoney(currency)) spent of \(budgeted.wholeMoney(currency))", route: .budget,
                        trailing: "\(abs(left).wholeMoney(currency)) \(left < 0 ? "over" : "left")"
                    )
                }
                return AttentionItem(kind: kind, title: title, subtitle: subtitle, route: .budget)
            }
    }

    private static func ratio(_ line: BudgetMonth.Line) -> Double { abs(line.actual) / (line.budgeted ?? 1) }

    /// Days left in today's month, today included, as Budget counts them: 22 on November 9.
    static func daysLeft(in today: Date) -> Int { BudgetModel.daysRemaining(today: today, month: today) }

    /// What can be spent per day for the rest of the month, today included.
    static func perDay(left: Double, today: Date) -> (amount: Double, days: Int) {
        let days = max(daysLeft(in: today), 1)
        return (max(left, 0) / Double(days), days)
    }

    /// Active subscriptions and unpaid loan payments due from today through the next 7 days, soonest first.
    /// A loan counts once, on its next due date. `loanPayers` maps a loan's account id to the account that pays it.
    static func billsThisWeek(
        _ subscriptions: [Subscription], budget: BudgetMonth?, loanPayers: [Int: (id: Int, name: String)] = [:], today: Date
    ) -> [Bill] {
        let start = calendar.startOfDay(for: today)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return [] }
        let fromSubscriptions = subscriptions.filter { $0.status == "active" }.compactMap { sub in
            APIDate.parse(sub.nextDate ?? "").map {
                Bill(
                    id: "s\(sub.id)", name: sub.displayName, date: $0, amount: sub.displayAmount ?? sub.amount,
                    category: sub.categoryName, account: sub.accountName, accountId: sub.accountId
                )
            }
        }
        let fromLoans = (budget?.debt ?? []).filter { $0.paid < $0.planned }.compactMap { debt -> Bill? in
            guard let next = (debt.dueDates ?? []).compactMap(APIDate.parse).filter({ $0 >= start }).min() else { return nil }
            let payer = loanPayers[debt.accountId]
            return Bill(
                id: "l\(debt.accountId)", name: debt.name, date: next, amount: debt.planned - debt.paid,
                category: "Payment", account: payer?.name, accountId: payer?.id, isLoan: true
            )
        }
        return (fromSubscriptions + fromLoans).filter { $0.date >= start && $0.date <= end }.sorted { $0.date < $1.date }
    }

    /// The account that paid a loan's latest payment: the other leg of the newest transfer in `loanLegs`
    /// (the loan account's transactions), found among `sameDay` (transactions on that transfer's date).
    static func payingAccount(loanLegs: [Transaction], sameDay: [Transaction]) -> (id: Int, name: String)? {
        guard let leg = loanLegs.filter(\.isTransfer).max(by: { $0.date < $1.date }),
              let other = sameDay.first(where: { $0.linkId == leg.linkId && $0.id != leg.id && $0.accountId != leg.accountId }),
              let id = other.accountId else { return nil }
        return (id, other.account)
    }

    /// The account most of this week's bills are charged to (the earliest bill's account on a tie), with its
    /// balance after those bills. Nil when no bill names an account or the account isn't in `balances`.
    static func afterBills(_ bills: [Bill], balances: [Dashboard.Balance]) -> (name: String, amount: Double)? {
        let byAccount = Dictionary(grouping: bills.filter { $0.accountId != nil }, by: { $0.accountId ?? 0 })
        let order = bills.compactMap(\.accountId)
        guard let top = byAccount.max(by: { lhs, rhs in
            lhs.value.count != rhs.value.count
                ? lhs.value.count < rhs.value.count
                : (order.firstIndex(of: lhs.key) ?? 0) > (order.firstIndex(of: rhs.key) ?? 0)
        }), let balance = balances.first(where: { $0.accountId == top.key }) else { return nil }
        return (balance.name, balance.convertedBalance - top.value.reduce(0) { $0 + $1.amount })
    }

    /// The budget bar's segments: spending groups with a budget or spending, in order, with the groups past
    /// `limit` folded into one "Other" slice so every colored segment has a legend entry.
    static func budgetSlices(_ groups: [BudgetMonth.Group], limit: Int) -> [BudgetSlice] {
        let slices = groups.filter { group in
            (group.budgeted ?? 0) > 0 || group.actual > 0 || group.lines.contains { ($0.budgeted ?? 0) > 0 }
        }.map { group in
            let lineBudgets = group.lines.compactMap(\.budgeted)
            let over = group.lines.first { ($0.budgeted ?? 0) > 0 && $0.actual > ($0.budgeted ?? 0) }
            return BudgetSlice(
                id: group.key, name: group.name, spent: group.actual,
                budgeted: group.budgeted ?? (lineBudgets.isEmpty ? nil : lineBudgets.reduce(0, +)),
                flag: over.map { "\($0.name) over" }, isOther: false
            )
        }
        guard slices.count > limit else { return slices }
        let rest = slices[limit...]
        let budgets = rest.compactMap(\.budgeted)
        let other = BudgetSlice(
            id: "other", name: "Other", spent: rest.reduce(0) { $0 + $1.spent },
            budgeted: budgets.isEmpty ? nil : budgets.reduce(0, +), flag: rest.compactMap(\.flag).first, isOther: true
        )
        return Array(slices[..<limit]) + [other]
    }

    private static func billsItem(_ due: [Bill], currency: String?) -> AttentionItem? {
        guard !due.isEmpty else { return nil }
        let total = due.reduce(0) { $0 + $1.amount }
        let names = due.map(\.name)
        return AttentionItem(
            kind: .billsThisWeek(count: due.count, total: total, names: names),
            title: "\(due.count) \(due.count == 1 ? "bill" : "bills") this week",
            subtitle: names.joined(separator: ", ") + " \u{00B7} " + total.wholeMoney(currency), route: .bills
        )
    }

    /// "in 3 days" from today to a bill's date.
    static func dueIn(_ date: Date, today: Date) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: date).day ?? 0
        switch days {
        case ...0: return "today"
        case 1: return "tomorrow"
        default: return "in \(days) days"
        }
    }

    /// The period to request: the server knows 6m, 1y and all, and answers anything else with 6m.
    static func requestPeriod(_ period: String) -> String { period == "1m" ? "6m" : period }

    /// The points the chart shows: for 1M, the last month of the 6m series.
    static func trim(_ series: [NetWorthHistory.Point], period: String, today: Date) -> [NetWorthHistory.Point] {
        guard period == "1m", let start = calendar.date(byAdding: .month, value: -1, to: calendar.startOfDay(for: today)) else {
            return series
        }
        return series.filter { $0.day >= start }
    }

    /// Change in net worth since the first of the month (or the start of the series if it begins later).
    static func monthChange(_ series: [NetWorthHistory.Point], today: Date) -> Double? {
        guard let last = series.last else { return nil }
        let first = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let base = series.last { $0.day <= first } ?? series[0]
        return last.value - base.value
    }

    /// Change from the first to the last point of the loaded series. The percent is nil when the start is not positive.
    static func change(_ series: [NetWorthHistory.Point]) -> (amount: Double, percent: Double?)? {
        guard series.count > 1, let first = series.first, let last = series.last else { return nil }
        let amount = last.value - first.value
        return (amount, first.value > 0 ? amount / first.value : nil)
    }

    /// The period's change in words, e.g. "past year" for "1y".
    static func periodLabel(_ period: String) -> String {
        switch period {
        case "1m": "past month"
        case "6m": "past 6 months"
        case "1y": "past year"
        default: "all time"
        }
    }

    /// Change in the investment accounts between the last two points of the series, when they are a day apart.
    static func investedToday(_ series: [NetWorthHistory.Point], investmentIds: Set<Int>) -> (amount: Double, percent: Double?)? {
        guard series.count > 1, !investmentIds.isEmpty else { return nil }
        let last = series[series.count - 1]
        let previous = series[series.count - 2]
        guard calendar.dateComponents([.day], from: previous.day, to: last.day).day == 1,
              let now = last.members, let before = previous.members else { return nil }
        func total(_ members: [NetWorthHistory.Member]) -> Double {
            members.filter { investmentIds.contains($0.id) }.reduce(0) { $0 + $1.value }
        }
        let base = total(before)
        let amount = total(now) - base
        return (amount, base > 0 ? amount / base : nil)
    }

    /// "+$12,480 (7.3%)": a signed whole amount with an optional percent.
    static func signedChange(_ amount: Double, percent: Double?, currency: String?) -> String {
        let money = (amount > 0 ? "+" : "") + amount.wholeMoney(currency)
        guard let percent else { return money }
        return money + " (" + abs(percent).formatted(.percent.precision(.fractionLength(1))) + ")"
    }

    /// Assets and debts in display currency, split by account type so Home agrees with Accounts.
    /// Debts are the sum of liability balances, so they are negative.
    static func split(_ balances: [Dashboard.Balance]) -> (assets: Double, debts: Double) {
        let active = balances.filter { !$0.archived }
        return (
            active.filter { !$0.isLiability }.reduce(0) { $0 + $1.convertedBalance },
            active.filter(\.isLiability).reduce(0) { $0 + $1.convertedBalance }
        )
    }
}
