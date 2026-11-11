import Foundation

// MARK: Spotlight, subscriptions, recurring (GET /api/spotlight, /api/subscriptions, /api/recurring)

nonisolated struct SpotlightItem: Decodable, Identifiable, Hashable {
    let id: String
    let type: String
    let severity: String
    let title: String
    let description: String
    let actionUrl: String?
    let amount: Double?
    let currency: String?
}

nonisolated struct Subscription: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let amount: Double
    let currency: String
    let frequency: String
    let categoryId: Int?
    let categoryName: String?
    let accountId: Int?
    let accountName: String?
    let nextDate: String?
    let status: String
    let cancelReminderDate: String?
    let notes: String?
    let displayCurrency: String?
    let displayAmount: Double?
    var displayName: String { name ?? "Subscription \(id)" }
}

nonisolated struct SubscriptionInput: Encodable {
    var name: String
    var amount: Double
    var currency: String?
    var frequency: String?
    var categoryId: Int?
    var accountId: Int?
    var nextDate: String?
    var notes: String?
}

/// A repeating payee the server found in the ledger.
nonisolated struct RecurringSuggestion: Decodable, Identifiable, Hashable {
    let payee: String
    let avgAmount: Double
    let currency: String?
    let avgAmountDisplay: Double?
    let frequency: String
    let count: Int
    let lastDate: String?
    let nextDate: String?
    let accountId: Int?
    let categoryId: Int?
    var id: String { "\(payee)|\(accountId ?? 0)|\(frequency)" }
}

// MARK: Goals and loans

nonisolated struct Goal: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let type: String
    let targetAmount: Double
    let currency: String
    let deadline: String?
    let accountId: Int?
    let accountIds: [Int]?
    let accounts: [String]?
    let priority: Int?
    let status: String
    let note: String?
    let currentAmount: Double
    let percentComplete: Double?
    let remaining: Double?
    let monthlyNeeded: Double?
    let displayCurrency: String?
    let targetAmountDisplay: Double?
    let currentAmountDisplay: Double?
    var displayName: String { name ?? "Goal \(id)" }
}

/// `POST /api/goals`. The server picks the currency from the first linked account, else the display currency.
nonisolated struct GoalInput: Encodable, Equatable {
    var name: String
    var type: String
    var targetAmount: Double
    /// `YYYY-MM-DD`; omitted for a goal without a date.
    var deadline: String?
    var accountIds: [Int]?
    var note: String?
}

/// `PUT /api/goals`: only the fields that are set change. `deadline: ""` clears the date; `accountIds` replaces the links.
nonisolated struct GoalUpdate: Encodable, Equatable {
    let id: Int
    var name: String?
    var type: String?
    var targetAmount: Double?
    var deadline: String?
    var accountIds: [Int]?
    /// "active" or "completed".
    var status: String?
    var note: String?
}

nonisolated struct Loan: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let type: String
    let accountId: Int?
    let accountName: String?
    let currency: String
    let principal: Double
    let annualRate: Double
    let termMonths: Int?
    let startDate: String
    let paymentAmount: Double?
    let paymentFrequency: String?
    let extraPayment: Double?
    let residualValue: Double?
    let note: String?
    let interestMethod: String?
    let interestAmount: Double?
    let monthlyPayment: Double?
    let paymentPerPeriod: Double?
    let monthlyEquivalentPayment: Double?
    let totalInterest: Double?
    let payoffDate: String?
    let remainingBalance: Double?
    let principalPaid: Double?
    let interestPaid: Double?
    let periodsRemaining: Int?
    let scheduleMode: String?
    let effectiveAnnualRate: Double?
    let displayCurrency: String?
    let remainingBalanceDisplay: Double?
    let monthlyEquivalentPaymentDisplay: Double?
    let totalInterestDisplay: Double?
    var displayName: String { name ?? "Loan \(id)" }
}

/// `POST /api/loans`: a new loan. Give `termMonths` or `paymentAmount`; the server solves the other.
nonisolated struct LoanInput: Encodable {
    var name: String
    var type: String
    var accountId: Int?
    var currency: String
    var principal: Double
    var annualRate: Double
    var termMonths: Int?
    var startDate: String
    var paymentAmount: Double?
    var paymentFrequency: String
    var extraPayment: Double
}

/// `PUT /api/loans`: the loan's id and only the fields being changed. Nil fields are left out of the body.
nonisolated struct LoanUpdate: Encodable {
    let id: Int
    var name: String?
    var annualRate: Double?
    var termMonths: Int?
    var paymentAmount: Double?
    var extraPayment: Double?
}

/// `POST /api/loans` with `action: "amortization"`.
nonisolated struct Amortization: Decodable {
    let monthlyPayment: Double
    let paymentPerPeriod: Double?
    /// The sum of every payment, an amount (not a count).
    let totalPayments: Double?
    let totalInterest: Double
    let payoffDate: String
    let schedule: [Row]
    let monthlyAccrual: [Accrual]?

    struct Row: Decodable, Identifiable, Hashable {
        let period: Int
        let date: String
        let payment: Double
        let principal: Double
        let interest: Double
        let extraPayment: Double?
        let balance: Double
        var id: Int { period }
    }

    struct Accrual: Decodable, Hashable {
        let month: String
        let interest: Double
    }
}

// MARK: Reports (GET /api/reports?type=income-statement)

nonisolated struct IncomeStatement: Decodable {
    let displayCurrency: String
    let income: [Line]
    let expenses: [Line]
    let totalIncome: Double
    let totalExpenses: Double
    let netSavings: Double
    let savingsRate: Double
    let unrealized: Unrealized?

    struct Line: Decodable, Identifiable, Hashable {
        let categoryId: Int?
        let categoryGroup: String
        let categoryName: String
        let total: Double
        let count: Int
        var id: String { "\(categoryId ?? 0)|\(categoryName)" }
    }

    struct Unrealized: Decodable {
        let totals: Totals
    }

    struct Totals: Decodable {
        let costBasis: Double
        let marketValue: Double
        let valuationGL: Double
        let fxGL: Double
        let totalGL: Double
    }
}

// MARK: Trends (GET /api/reports/trends?period=monthly)

/// Income and expenses per category with a value for each month. Months without activity are missing from `periods`.
nonisolated struct Trends: Decodable {
    let displayCurrency: String
    let timeseries: [Period]
    let income: [Line]
    let expenses: [Line]

    struct Period: Decodable, Hashable {
        /// `YYYY-MM`.
        let period: String
        let income: Double
        let expenses: Double
    }

    struct Line: Decodable, Identifiable, Hashable {
        let name: String
        let group: String?
        let categoryId: Int?
        let total: Double
        let count: Int
        /// Amount per `YYYY-MM`, positive for both income and expenses.
        let periods: [String: Double]
        var id: String { "\(categoryId ?? 0)|\(name)" }
    }
}
