import Foundation

// Settings, sign-in and first-run calls. Shapes are in docs/api-reference.md and the server's route files.

extension APIClient {
    /// Turns a rule on or off. `PUT /api/rules` leaves the fields it isn't sent unchanged.
    func setRuleActive(id: Int, isActive: Bool) async throws {
        struct Body: Encodable { let id: Int; let isActive: Bool }
        try await send("PUT", "/api/rules", body: Body(id: id, isActive: isActive))
    }

    /// Replaces a rule's name, conditions, actions, priority and active flag. `input.id` picks the rule.
    func updateRule(_ input: RuleInput) async throws {
        try await send("PUT", "/api/rules", body: input)
    }

    func deleteRule(id: Int) async throws {
        try await send("DELETE", "/api/rules", query: ["id": String(id)])
    }

    /// Adds a category. A taken name fails with 409 and a message to show as-is.
    func createCategory(_ input: CategoryInput) async throws {
        try await send("POST", "/api/categories", body: input)
    }

    /// Replaces a category's name, type, group and note. `input.id` picks the category.
    func updateCategory(_ input: CategoryInput) async throws {
        try await send("PUT", "/api/categories", body: input)
    }

    /// Fails with 409 and a message naming what still uses the category.
    func deleteCategory(id: Int) async throws {
        try await send("DELETE", "/api/categories", query: ["id": String(id)])
    }

    /// The first day of the month of the category's newest transaction, or nil when it has none. The server lists
    /// transactions newest first by default.
    func newestTransactionMonth(categoryId: Int) async throws -> Date? {
        let page = try await transactions(TransactionQuery(categoryId: categoryId, limit: 1))
        guard let date = page.data.first.flatMap({ APIDate.parse($0.date) }) else { return nil }
        return Calendar(identifier: .gregorian).dateInterval(of: .month, for: date)?.start
    }

    /// The currencies the user holds or picked, for the Currencies row.
    func activeCurrencies() async throws -> [String] {
        let list: ActiveCurrencies = try await get("/api/settings/active-currencies")
        return list.active
    }

    /// Saves the list of currencies the user holds. The server keeps at least one.
    @discardableResult
    func setActiveCurrencies(_ codes: [String]) async throws -> [String] {
        let list: ActiveCurrencies = try decode(await send("PUT", "/api/settings/active-currencies", body: ["active": codes]))
        return list.active
    }

    /// Whether rates show inverted ("1 USD = 1.39 CAD" instead of "1 CAD = 0.72 USD").
    func fxRatesInverted() async throws -> Bool {
        let view: FxRateView = try await getEnveloped("/api/settings/fx-rate-view")
        return view.inverted
    }

    func setFxRatesInverted(_ inverted: Bool) async throws {
        try await send("PUT", "/api/settings/fx-rate-view", body: ["inverted": inverted])
    }

    func bankFeedStatus() async throws -> BankFeedStatus { try await get("/api/settings/bank-feeds/simplefin/status") }

    /// `type` is bug, idea, question or other.
    func sendFeedback(type: String, message: String, appVersion: String) async throws {
        struct Body: Encodable { let type: String; let message: String; let appVersion: String }
        try await send("POST", "/api/feedback", body: Body(type: type, message: message, appVersion: appVersion))
    }

    // MARK: Sign-in and first run

    /// Creates an account; the caller signs in afterwards. Without an email the password can never be reset,
    /// which the server makes the caller acknowledge.
    func register(username: String, email: String?, password: String) async throws {
        struct Body: Encodable {
            let username: String
            let email: String?
            let password: String
            let acknowledgeNoRecovery: Bool?
        }
        let body = Body(username: username, email: email, password: password, acknowledgeNoRecovery: email == nil ? true : nil)
        try await send("POST", "/api/auth/register", body: try JSONEncoder().encode(body), retry: false)
    }

    func loadSampleData() async throws { try await send("POST", "/api/onboarding/sample-data") }

    /// Budgets `amount` a month for the category named `categoryName`, which the server creates when it is missing.
    func seedBudget(categoryName: String, amount: Double, month: String) async throws {
        struct Body: Encodable { let categoryName: String; let amount: Double; let month: String }
        try await send("POST", "/api/budgets/seed", body: Body(categoryName: categoryName, amount: amount, month: month))
    }

    func completeOnboarding() async throws { try await send("POST", "/api/onboarding/complete") }
}
