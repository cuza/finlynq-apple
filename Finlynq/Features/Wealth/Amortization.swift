import Foundation

/// A local monthly schedule, so the loan What-if slider updates without a round trip. `Amortization` itself is the
/// server's schedule (`POST /api/loans` with `action: "amortization"`). The server's first payment is one month after
/// the loan's start date; here `start` is the first payment's date. The server keeps full precision between periods
/// and ends with a short last payment; this rounds each period to cents and folds a small remainder into the payment
/// before it. For the same terms the first rows agree to the cent and the last ones drift by a few cents.
extension Amortization {
    nonisolated struct Payment: Hashable {
        let date: Date
        let payment: Double
        let principal: Double
        let interest: Double
        /// Owed after this payment.
        let balance: Double
    }

    /// One row per month from `start`. Interest is the balance times `annualRate / 12` percent, rounded to cents.
    /// A last remainder under a tenth of a payment is added to the payment before it instead of becoming its own
    /// payment. Empty when the payment never covers the interest (see `neverPaysOff`).
    nonisolated static func schedule(
        principal: Double, annualRate: Double, payment: Double, extra: Double = 0, start: Date
    ) -> [Payment] {
        guard principal > 0, !neverPaysOff(principal: principal, annualRate: annualRate, payment: payment, extra: extra) else {
            return []
        }
        let calendar = Calendar(identifier: .gregorian)
        let total = payment + extra
        var balance = cents(principal)
        var rows: [Payment] = []
        // ponytail: 1,200 months caps a near-zero amortization; no real loan runs past 100 years.
        while balance > 0, rows.count < 1200 {
            let interest = cents(balance * annualRate / 1200)
            var principalPaid = cents(min(total - interest, balance))
            var left = cents(balance - principalPaid)
            if left > 0, left < total / 10 {
                principalPaid = cents(principalPaid + left)
                left = 0
            }
            let date = calendar.date(byAdding: .month, value: rows.count, to: start) ?? start
            rows.append(Payment(
                date: date, payment: cents(principalPaid + interest), principal: principalPaid, interest: interest, balance: left
            ))
            balance = left
        }
        return rows
    }

    /// True when the first month's interest takes the whole payment, so the balance never goes down.
    nonisolated static func neverPaysOff(principal: Double, annualRate: Double, payment: Double, extra: Double = 0) -> Bool {
        principal > 0 && payment + extra <= cents(principal * annualRate / 1200)
    }

    nonisolated static func totalInterest(_ rows: [Payment]) -> Double { cents(rows.reduce(0) { $0 + $1.interest }) }

    private nonisolated static func cents(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}
