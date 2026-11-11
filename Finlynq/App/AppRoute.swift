import Foundation

nonisolated enum AppRoute: Hashable, Codable {
    case home, activity, review, budget, bills, goals, accounts, investments, debts, insights
    case account(Int), transaction(Int), category(Int), goal(Int), holding(String), loan(Int)
    case statement, netWorth, tax, calendar, applePay, categories

    var title: String {
        switch self {
        case .home: "Home"
        case .activity: "Activity"
        case .review: "Review"
        case .budget: "Budget"
        case .bills: "Bills"
        case .goals: "Goals"
        case .accounts: "Accounts"
        case .investments: "Investments"
        case .debts: "Debts"
        case .insights: "Insights"
        case .account: "Account"
        case .transaction: "Transaction"
        case .category: "Category"
        case .goal: "Goal"
        case .holding: "Holding"
        case .loan: "Loan"
        case .statement: "Statement"
        case .netWorth: "Net worth"
        case .tax: "Tax"
        case .calendar: "Calendar"
        case .applePay: "Apple Pay"
        case .categories: "Categories"
        }
    }
}
