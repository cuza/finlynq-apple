import Foundation

/// Goal figures, as pure functions of the loaded data and a passed-in "today".
nonisolated enum GoalModel {
    private static let calendar = Calendar(identifier: .gregorian)

    /// Calendar months from `start`'s month to `end`'s month: November 2026 to December 2027 is 13.
    static func months(from start: Date, to end: Date) -> Int {
        let first = calendar.dateComponents([.year, .month], from: start)
        let last = calendar.dateComponents([.year, .month], from: end)
        return ((last.year ?? 0) - (first.year ?? 0)) * 12 + (last.month ?? 0) - (first.month ?? 0)
    }

    /// What must be saved each month to reach `target` by `targetDate`, counting calendar months from this month.
    /// A target this month or earlier asks for the whole remainder.
    static func monthlyNeeded(current: Double, target: Double, targetDate: Date, today: Date) -> Double {
        let remaining = max(target - current, 0)
        return remaining / Double(max(months(from: today, to: targetDate), 1))
    }

    /// When the goal is reached at `monthlyPace`, in whole months from today. Nil when the pace is not positive.
    static func projectedDate(current: Double, target: Double, monthlyPace: Double, today: Date) -> Date? {
        guard monthlyPace > 0 else { return nil }
        let months = Int((max(target - current, 0) / monthlyPace).rounded(.up))
        return calendar.date(byAdding: .month, value: months, to: today)
    }

    /// Average change per month over the last six months of a balance series (or since its first point).
    static func monthlyPace(_ series: [(Date, Double)], today: Date) -> Double {
        guard let last = series.last, let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: today) else { return 0 }
        guard let base = series.last(where: { $0.0 <= sixMonthsAgo }) ?? series.first else { return 0 }
        let span = months(from: base.0, to: last.0)
        return span > 0 ? (last.1 - base.1) / Double(span) : 0
    }

    /// The goal's display name for its type, e.g. "Emergency fund" for `emergency_fund`.
    static func typeName(_ type: String) -> String {
        switch type {
        case "emergency_fund", "emergency": "Emergency fund"
        case "debt_payoff", "debt": "Debt payoff"
        case "investment": "Investment"
        default: "Savings"
        }
    }

    static func isDebt(_ goal: Goal) -> Bool { goal.type.hasPrefix("debt") }

    /// Current and target in the display currency when the server sends them, else in the goal's currency.
    struct Amounts {
        let current: Double
        let target: Double
        let currency: String
    }

    static func amounts(_ goal: Goal) -> Amounts {
        if let current = goal.currentAmountDisplay, let target = goal.targetAmountDisplay, let currency = goal.displayCurrency {
            return Amounts(current: current, target: target, currency: currency)
        }
        return Amounts(current: goal.currentAmount, target: goal.targetAmount, currency: goal.currency)
    }

    /// On track when the pace reaches the target by the target month, or the target is already reached.
    static func onTrack(projected: Date?, deadline: Date, current: Double, target: Double) -> Bool {
        if current >= target { return true }
        return projected.map { months(from: $0, to: deadline) >= 0 } ?? false
    }
}
