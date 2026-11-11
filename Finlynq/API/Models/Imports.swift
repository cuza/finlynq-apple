import Foundation

// MARK: Review queue (GET /api/import/staged and /api/import/staged/[id])

/// One uploaded or emailed batch waiting for review.
nonisolated struct StagedImport: Decodable, Identifiable, Hashable {
    let id: String
    let source: String
    let fromAddress: String?
    let subject: String?
    let receivedAt: String?
    let totalRowCount: Int
    let duplicateCount: Int
    let expiresAt: String?
    let originalFilename: String?
    let fileFormat: String?
    let boundAccountId: Int?
}

/// A row waiting for review. Most come from `GET /api/import/staged/[id]`; `reviewQueue()` also builds rows for
/// bank-ledger entries that have no transaction yet (`bankId` set). Optional fields default to nil so the app and
/// tests can build rows directly.
nonisolated struct StagedRow: Decodable, Identifiable, Hashable {
    let id: String
    /// The batch this row belongs to. The server leaves it out of the row, `stagedImports()` fills it in.
    var importId: String?
    let date: String
    let amount: Double
    var currency: String?
    var payee: String?
    /// The category name a rule suggested, if any. It is a name, not an id.
    var category: String?
    var note: String?
    var tags: String?
    var txType: String?
    var rowIndex: Int?
    var isDuplicate: Bool?
    /// `new`, `existing` or `probable_duplicate`.
    var dedupStatus: String?
    /// `pending` until approve sends the row to the bank ledger, then `approved`.
    var rowStatus: String?
    /// `unmatched`, `auto_suggested`, `linked` or `skipped_duplicate`.
    var reconcileState: String?
    var peerStagedId: String?
    /// A transfer's destination account, not the account the row is in.
    var targetAccountId: Int?
    var linkedTransactionId: Int?
    /// The account name a CSV row names. Nil for rows of a batch bound to one account.
    var accountName: String?

    // Filled in by the app.
    /// The account the row is in: the batch's bound account, or the bank row's account.
    var accountId: Int?
    /// When the batch arrived (ISO timestamp).
    var importedAt: String?
    /// The batch's file name, such as "chequing-nov.csv".
    var importFile: String?
    /// Set for a row that is already in the bank ledger: the `bank_transactions` id.
    var bankId: String?
    /// The category to approve the row with: a rule's suggestion or the user's pick.
    var categoryId: Int?
    /// An existing transaction this row may be a copy of.
    var match: ReviewMatch?

    var isSkippedDuplicate: Bool { reconcileState == "skipped_duplicate" }
    /// Still waiting: not skipped as a duplicate and not yet sent to the bank ledger.
    var isPending: Bool { !isSkippedDuplicate && rowStatus != "approved" }
}

/// An existing ledger transaction that a row to review looks like.
nonisolated struct ReviewMatch: Decodable, Hashable {
    let transactionId: Int
    var payee: String?
    var amount: Double?
    var date: String?
}

nonisolated struct StagedDetail: Decodable {
    let staged: StagedImport
    let rows: [StagedRow]
    let suggestedMatches: [Match]

    /// A staged row that looks like a transaction already in the ledger.
    struct Match: Decodable, Hashable {
        let stagedRowId: String
        let transactionId: Int
        /// `exact` or `fuzzy`.
        let confidence: String
    }
}

nonisolated struct ApproveResult: Decodable {
    let approved: Int?
    let skippedDuplicates: Int?
    let redirectTo: String?
    /// Rows the server could not send, such as a CSV row naming an account that doesn't exist. They stay pending.
    let rowErrors: [RowError]?

    struct RowError: Decodable, Hashable {
        let rowIndex: Int
        let message: String
    }
}

/// Row edits `PATCH /api/import/staged/[id]/rows/[rowId]` accepts that the app uses.
nonisolated struct StagedRowPatch: Encodable {
    var txType: String?
    var payee: String?
    var category: String?
    var note: String?
    var tags: String?
    var reconcileState: String?
    var linkedTransactionId: Int?
}

// MARK: Bank ledger (GET /api/reconcile/summary, /api/reconcile/suggestions, /api/reconcile/balance-summary)

/// Per-account reconcile status. `pendingCount` is bank-ledger rows with no ledger transaction yet.
nonisolated struct ReconcileSummary: Decodable {
    let rows: [Row]

    struct Row: Decodable, Hashable {
        let accountId: Int
        let accountName: String?
        let currency: String?
        let pendingCount: Int
    }
}

/// One account's bank rows and ledger transactions, and how they pair up. Inside a `{ success, data }` envelope.
nonisolated struct ReconcileSnapshot: Decodable {
    let linked: [Link]
    let suggestions: [Suggestion]
    /// Keyed by the transaction id as a string.
    let transactions: [String: Ledger]
    /// Keyed by the bank row id.
    let bankTransactions: [String: Bank]

    struct Link: Decodable, Hashable {
        let transactionId: Int
        let bankTransactionId: String
    }

    /// A likely pair the server found but nobody confirmed.
    struct Suggestion: Decodable, Hashable {
        let transactionId: Int
        let bankTransactionId: String
        let reason: String?
    }

    struct Ledger: Decodable, Hashable {
        let id: Int
        let date: String
        let amount: Double
        let currency: String?
        let payee: String?
        let categoryName: String?
    }

    struct Bank: Decodable, Hashable {
        let id: String
        let date: String
        let amount: Double
        let currency: String?
        let payee: String?
        let accountId: Int
        let firstSeenAt: String?
        /// A rule's category for this row.
        let suggestedCategoryId: Int?
        /// An unlinked ledger transaction this row strictly matches: same import hash, or same amount within days.
        let duplicateOfTransactionId: Int?
    }

    /// Bank rows that no ledger transaction is linked to yet, by id so same-date rows keep one order between loads.
    var unlinked: [Bank] {
        let linkedIds = Set(linked.map(\.bankTransactionId))
        return bankTransactions.values.filter { !linkedIds.contains($0.id) }.sorted { $0.id < $1.id }
    }
}

// MARK: File import (POST /api/import/preview, /api/import/execute, /api/import/staging/upload)

nonisolated struct UploadFile {
    let filename: String
    let data: Data
}

/// A parsed statement row. `hash` and `rowIndex` come back from the preview and are not needed to import.
nonisolated struct ImportRow: Codable, Hashable {
    var date: String
    var account: String
    var amount: Double
    var payee: String
    var category: String?
    var currency: String?
    var note: String?
    var tags: String?
    var hash: String?
    var rowIndex: Int?
}

/// The preview shape depends on the file type. CSV and PDF fill `valid`; OFX and QFX fill `transactions`.
nonisolated struct ImportPreview: Decodable {
    let type: String
    let valid: [ImportRow]?
    let duplicates: [ImportRow]?
    let errors: [RowError]?
    let headers: [String]?
    let currency: String?
    let transactions: [OfxRow]?
    /// Set when the server could not map a CSV's columns itself (`type` is `csv-needs-mapping`).
    let suggestedMapping: ColumnMapping?

    struct RowError: Decodable, Hashable {
        let rowIndex: Int
        let message: String
    }

    struct OfxRow: Decodable, Hashable {
        let date: String
        let amount: Double
        let payee: String
        let fitId: String?
        let memo: String?
    }
}

/// Which CSV header holds each field. `date` and `amount` are required.
nonisolated struct ColumnMapping: Codable, Hashable {
    var date: String
    var amount: String
    var payee: String?
    var account: String?
    var note: String?
}

nonisolated struct ImportResult: Decodable {
    let total: Int?
    let imported: Int?
    let skippedDuplicates: Int?
    let errors: [String]?
}

nonisolated struct StagingUploadResult: Decodable {
    let stagedImportId: String?
    let format: String?
    let counts: Counts?

    /// `skippedDuplicate` rows were already in the bank ledger and were left out.
    struct Counts: Decodable {
        let new: Int?
        let existing: Int?
        let probableDuplicate: Int?
        let skippedDuplicate: Int?
        let errors: Int?
    }
}

// MARK: Rules (GET /api/rules)

nonisolated enum RuleValue: Codable, Hashable {
    case text(String)
    case number(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .number(let number): try container.encode(number)
        }
    }
}

/// `field` is payee, note, tags, amount, account, currency or date. The other keys depend on `field` and `op`.
nonisolated struct RuleCondition: Codable, Hashable {
    var field: String
    // swiftlint:disable:next identifier_name
    var op: String
    var value: RuleValue?
    var min: Double?
    var max: Double?
    var accountId: Int?
}

/// `kind` is set_category, set_tags, rename_payee, set_account, set_entered_currency,
/// set_portfolio_holding or create_transfer. The other keys depend on `kind`.
nonisolated struct RuleAction: Codable, Hashable {
    var kind: String
    var categoryId: Int?
    var tags: String?
    // swiftlint:disable:next identifier_name
    var to: String?
    var accountId: Int?
    var currency: String?
    var holdingId: Int?
    var destAccountId: Int?
}

nonisolated struct Rule: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let conditions: Conditions
    let actions: [RuleAction]
    let isActive: Bool
    let priority: Int

    struct Conditions: Codable, Hashable {
        var all: [RuleCondition]
    }
}

nonisolated struct RuleInput: Encodable {
    var name: String
    var conditions: Rule.Conditions
    var actions: [RuleAction]
    var priority: Int?
    var isActive: Bool?
    /// Set for `PUT /api/rules` (an edit), nil for `POST` (a new rule).
    var id: Int?
}

// MARK: Settings

/// `GET /api/settings/active-currencies`: the user's saved list, or one derived from their accounts.
nonisolated struct ActiveCurrencies: Decodable {
    let active: [String]
}

/// `GET /api/settings/fx-rate-view`, inside `{ success, data }`.
nonisolated struct FxRateView: Decodable {
    let inverted: Bool
}

/// `GET /api/settings/bank-feeds/simplefin/status`.
nonisolated struct BankFeedStatus: Decodable {
    let connected: Bool
    let lastSyncAt: String?
}

/// What the Settings screen reads: `GET /api/user/me` and `GET /api/settings/display-currency`.
nonisolated struct AppSettings {
    let userId: String
    let username: String?
    let email: String?
    let displayName: String?
    let displayCurrency: String
}

nonisolated struct UserMe: Decodable {
    let userId: String
    let username: String?
    let email: String?
    let displayName: String?
}

nonisolated struct DisplayCurrencySetting: Decodable {
    let displayCurrency: String
}

/// A staged transaction the app builds itself, for example from an Apple Pay payment.
nonisolated struct StageInput {
    var date: String
    var accountId: Int
    var accountName: String
    var amount: Double
    var payee: String
    var currency: String?
    var note: String?
}
