import Foundation

// MARK: Transactions

nonisolated struct Transaction: Decodable, Identifiable, Hashable {
    let id: Int
    let date: String
    let accountId: Int?
    let accountName: String?
    let accountAlias: String?
    let categoryId: Int?
    let categoryName: String?
    let categoryType: String?
    let currency: String
    let amount: Double
    let quantity: Double?
    let portfolioHoldingId: Int?
    let portfolioHolding: String?
    let payee: String?
    let note: String?
    let tags: String?
    let linkId: String?
    let kind: String?

    var day: Date { APIDate.parse(date) ?? .distantPast }
    var account: String { accountAlias ?? accountName ?? "" }
    var title: String {
        if let payee, !payee.isEmpty { return payee }
        if let portfolioHolding { return portfolioHolding }
        if linkId != nil { return "Transfer" }
        return categoryName ?? "Transaction"
    }
    var isTransfer: Bool { linkId != nil }
    /// Transfers and investment rows have linked records, so only their text fields are editable here.
    var isSimple: Bool { linkId == nil && portfolioHoldingId == nil && kind == nil }
}

nonisolated struct TransactionPage: Decodable {
    let data: [Transaction]
    let total: Int

    enum CodingKeys: String, CodingKey { case data, total }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode([Transaction].self, forKey: .data)
        // `total` is a string when no text filter is active (Postgres count), a number otherwise.
        if let count = try? container.decode(Int.self, forKey: .total) {
            total = count
        } else {
            total = Int(try container.decode(String.self, forKey: .total)) ?? 0
        }
    }
}

nonisolated struct TransactionInput: Encodable {
    var id: Int?
    var date: String?
    var accountId: Int?
    var categoryId: Int?
    var amount: Double?
    var currency: String?
    var enteredAmount: Double?
    var enteredCurrency: String?
    var payee: String?
    var note: String?
    var tags: String?
    var quantity: Double?
    var portfolioHoldingId: Int?
}

nonisolated struct TransferInput: Encodable {
    var fromAccountId: Int
    var toAccountId: Int
    var enteredAmount: Double
    var date: String
    var receivedAmount: Double?
    var note: String?
    var tags: String?
}

/// Query for `GET /api/transactions`. Unset fields are left out of the URL.
nonisolated struct TransactionQuery: Equatable {
    var search: String?
    var accountId: Int?
    var categoryId: Int?
    var startDate: String?
    var endDate: String?
    var tag: String?
    var limit: Int?
    var offset: Int?
    var portfolioHoldingId: Int?

    var items: [String: String?] {
        [
            "search": search, "accountId": accountId.map(String.init), "categoryId": categoryId.map(String.init),
            "startDate": startDate, "endDate": endDate, "tag": tag,
            "limit": limit.map(String.init), "offset": offset.map(String.init),
            "portfolioHoldingId": portfolioHoldingId.map(String.init)
        ]
    }
}

/// The row a POST or PUT returns. Its text fields are ciphertext, so refetch to display it.
nonisolated struct TransactionWrite: Decodable {
    /// Nil in fixture mode, where writes return an empty object.
    let id: Int?
    let warning: String?
}

/// Fields `POST /api/transactions/bulk` can change on many rows. It takes one field per call.
nonisolated struct TransactionChanges {
    var categoryId: Int?
    var accountId: Int?
    var date: String?
    var note: String?
    var payee: String?
    var tags: String?

    /// One request body per field that is set.
    func bodies(ids: [Int]) -> [[String: Any]] {
        var list: [[String: Any]] = []
        if let categoryId { list.append(["action": "update_category", "ids": ids, "categoryId": categoryId]) }
        if let accountId { list.append(["action": "update_account", "ids": ids, "accountId": accountId]) }
        if let date { list.append(["action": "update_date", "ids": ids, "date": date]) }
        if let note { list.append(["action": "update_note", "ids": ids, "note": note]) }
        if let payee { list.append(["action": "update_payee", "ids": ids, "payee": payee]) }
        if let tags { list.append(["action": "update_tags", "ids": ids, "tags": tags]) }
        return list
    }
}

/// `GET /api/transactions/splits?transactionId=N`.
nonisolated struct Split: Decodable, Identifiable, Hashable {
    let id: Int
    let transactionId: Int?
    let categoryId: Int?
    let accountId: Int?
    let amount: Double
    let note: String?
    let description: String?
    let tags: String?
}

/// One part of `POST /api/transactions/splits`. Amounts carry the parent's sign.
nonisolated struct SplitInput: Encodable {
    var categoryId: Int?
    var amount: Double
    var note: String?

    private enum CodingKeys: String, CodingKey { case categoryId, amount, note }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // The server's schema accepts null for the category but not for the note, so a missing note is left out.
        try container.encode(categoryId, forKey: .categoryId)
        try container.encode(amount, forKey: .amount)
        try container.encodeIfPresent(note, forKey: .note)
    }
}

/// `GET /api/fx`: each rate is keyed by source and target code, e.g. `USDINR`.
nonisolated struct FxRates: Decodable {
    let displayCurrency: String
    let rates: [String: Double]

    /// Multiplier to the display currency, by source currency code. The display currency itself maps to 1.
    var byCurrency: [String: Double] {
        var result = [displayCurrency: 1.0]
        for (key, rate) in rates where key.hasSuffix(displayCurrency) {
            result[String(key.dropLast(displayCurrency.count))] = rate
        }
        return result
    }
}
