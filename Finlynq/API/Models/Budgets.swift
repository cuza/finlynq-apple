import Foundation

// MARK: Budgets (GET /api/budgets/month, enveloped)

/// `POST /api/budgets/fill` for one month's spending lines from the average of the months before it.
/// `preview: true` returns the rows without saving them.
nonisolated struct BudgetFillRequest: Encodable, Equatable {
    struct Source: Encodable, Equatable {
        var kind = "average"
        var months: Int
    }

    var months: [String]
    var source: Source
    var overwrite: Bool
    var preview: Bool
}

nonisolated struct BudgetFillResult: Decodable {
    struct Row: Decodable {
        let key: String
        let name: String
        let month: String
        let amount: Double
        let previous: Double?
    }

    let rows: [Row]
    let applied: Bool
    let total: Double
    let currency: String
}

nonisolated struct BudgetMonth: Decodable {
    let month: String
    let currency: String
    let summary: Summary
    let income: [Group]
    let spending: [Group]
    let debt: [Debt]
    /// Server counts for the filter chips. Missing on older servers.
    let counts: Counts?

    struct Counts: Decodable {
        let notBudgeted: Int?
        let overspent: Int?
    }

    struct Summary: Decodable {
        let plannedIncome: Double
        let receivedIncome: Double
        let plannedSpending: Double
        let spent: Double
        let plannedDebt: Double
        let paidDebt: Double
        let leftToPlan: Double
        let netCashFlow: Double
    }

    struct Debt: Decodable, Identifiable {
        let accountId: Int
        let name: String
        let planned: Double
        let paid: Double
        let dueDates: [String]?
        var id: Int { accountId }
    }

    struct Group: Decodable, Identifiable {
        let key: String
        let name: String
        let budgeted: Double?
        let actual: Double
        let left: Double?
        let status: String
        let lines: [Line]
        var average3: Double?
        var id: String { key }
    }

    struct Line: Decodable, Identifiable {
        let key: String
        let name: String
        let budgeted: Double?
        let actual: Double
        let left: Double?
        let status: String
        var categoryId: Int?
        /// Average spending of the three months before this one.
        var average3: Double?
        var id: String { key }
    }
}
