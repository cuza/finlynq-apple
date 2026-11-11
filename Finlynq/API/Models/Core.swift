import Foundation

// Shapes follow docs/api-reference.md. Only the fields the app uses are declared;
// most are optional because the REST routes are not a stable contract.

nonisolated struct SessionInfo: Decodable {
    let authenticated: Bool
    let encryptionLocked: Bool?
    let username: String?
    let email: String?
    let displayName: String?
    let displayCurrency: String?
    /// False for a fresh account that hasn't run first-run setup. Self-hosted servers always say true.
    let onboardingComplete: Bool?
    /// True when this session passed an MFA code, so deleting the account needs one too.
    let mfaVerified: Bool?
}

nonisolated struct LoginResponse: Decodable {
    let success: Bool?
    let mfaRequired: Bool?
    let mfaPendingToken: String?
}

// MARK: Dashboard

nonisolated struct Dashboard: Decodable {
    let displayCurrency: String
    let balances: [Balance]
    let incomeVsExpenses: [MonthTotal]
    let incomeExpenseBreakdown: [String: Breakdown]
    let spendingByCategory: [CategorySpend]

    struct Balance: Decodable, Identifiable {
        let accountId: Int
        let accountName: String?
        let alias: String?
        let accountType: String
        let accountGroup: String
        let currency: String
        let archived: Bool
        let isInvestment: Bool
        let balance: Double
        let convertedBalance: Double
        var id: Int { accountId }
        var name: String { alias ?? accountName ?? "Account \(accountId)" }
        var isLiability: Bool { accountType == "L" }
    }

    struct MonthTotal: Decodable, Identifiable {
        let month: String
        let type: String
        let total: Double
        var id: String { month + type }
    }

    struct Breakdown: Decodable {
        let income: [NameValue]
        let expenses: [NameValue]
    }

    struct NameValue: Decodable, Identifiable {
        let name: String
        let value: Double
        var id: String { name }
    }

    struct CategorySpend: Decodable {
        let categoryName: String
        let total: Double
    }

    /// Sum of every account converted to the display currency. Liabilities are already negative.
    var netWorth: Double { balances.reduce(0) { $0 + $1.convertedBalance } }
}

nonisolated struct NetWorthHistory: Decodable {
    let seriesCurrency: String
    let series: [Point]

    struct Point: Decodable, Identifiable {
        let date: String
        let value: Double
        /// Each account's value on that day, in the series currency. The server's `breakdown` is not used: past
        /// 10 accounts it folds the rest into an "Other" row without an id.
        var members: [Member]?
        var id: String { date }
        var day: Date { APIDate.parse(date) ?? .distantPast }
    }

    struct Member: Decodable {
        let id: Int
        let value: Double
    }
}

// MARK: Accounts and categories

nonisolated struct Account: Decodable, Identifiable, Hashable {
    let id: Int
    let type: String
    let group: String
    let currency: String
    let archived: Bool
    let isInvestment: Bool
    let name: String?
    let alias: String?
    /// Reconciliation policy: auto, approve or manual. Missing on older servers.
    let mode: String?
    /// How a CSV's column mapping is applied: confirm or auto.
    let csvMappingMode: String?
    let note: String?
    var displayName: String { alias ?? name ?? "Account \(id)" }
}

/// `POST /api/accounts`. `type` is A (asset) or L (liability).
nonisolated struct AccountInput: Encodable {
    var name: String
    var type: String
    var group: String
    var currency: String
    var isInvestment: Bool
}

/// `PUT /api/accounts`. Nil fields are left unchanged, except `alias`, which is always sent so it can be cleared.
nonisolated struct AccountUpdate: Encodable {
    let id: Int
    var name: String?
    var alias: String?
    var group: String?
    var archived: Bool?
    var isInvestment: Bool?

    private enum CodingKeys: String, CodingKey { case id, name, alias, group, archived, isInvestment }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(alias, forKey: .alias)
        try container.encodeIfPresent(group, forKey: .group)
        try container.encodeIfPresent(archived, forKey: .archived)
        try container.encodeIfPresent(isInvestment, forKey: .isInvestment)
    }
}

/// `GET /api/reconcile/balance-summary?accountId=` (enveloped): the latest statement balance the bank reported
/// against Finlynq's balance. `status` is `no_anchor` until a statement with a closing balance is imported.
nonisolated struct BalanceSummary: Decodable {
    let accountId: Int
    let currency: String?
    let latestAnchor: Anchor?
    let bankSideLatest: Double?
    let systemSideLatest: Double?
    let delta: Double?
    let status: String

    /// The statement the bank balance came from. Every field is optional: the demo has none to show the shape.
    struct Anchor: Decodable {
        let date: String?
        let statementDate: String?
        let balance: Double?
    }

    private enum CodingKeys: String, CodingKey {
        case accountId, currency, latestAnchor, bankSideLatest, systemSideLatest, delta, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try container.decode(Int.self, forKey: .accountId)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        // An anchor in an unexpected shape shouldn't hide the balances.
        latestAnchor = try? container.decodeIfPresent(Anchor.self, forKey: .latestAnchor)
        bankSideLatest = try container.decodeIfPresent(Double.self, forKey: .bankSideLatest)
        systemSideLatest = try container.decodeIfPresent(Double.self, forKey: .systemSideLatest)
        delta = try container.decodeIfPresent(Double.self, forKey: .delta)
        status = try container.decode(String.self, forKey: .status)
    }

    var anchorDate: Date? { (latestAnchor?.statementDate ?? latestAnchor?.date).flatMap(APIDate.parse) }
}

nonisolated struct Category: Decodable, Identifiable, Hashable {
    let id: Int
    let type: String
    let group: String
    let name: String?
    let note: String?
    var displayName: String { name ?? "Category \(id)" }
}
