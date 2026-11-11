import Foundation

// MARK: Portfolio (GET /api/portfolio/overview)

nonisolated struct PortfolioOverview: Decodable {
    let displayCurrency: String
    let byHolding: [Holding]
    let summary: Summary
    let byType: [String: TypeTotal]
    /// One row per holding per account. `Buy` and `Sell` take this row's id.
    let holdings: [Position]?

    struct Position: Decodable, Identifiable, Hashable {
        let id: Int
        let accountId: Int?
        /// The server sends null for some holdings.
        let name: String?
        let symbol: String?
        let currency: String?
        let assetType: String?
        let quantity: Double?
        let price: Double?
        let accountName: String?
        let firstPurchaseDate: String?
        let marketValueDisplay: Double?
        let unrealizedGainPct: Double?
        let changePct: Double?
        var isCash: Bool { assetType == "cash" }
        var label: String { symbol ?? name ?? "Holding" }
    }

    struct Summary: Decodable {
        let totalValueDisplay: Double
        let dayChangeDisplay: Double
        let dayChangePct: Double
        let totalCostBasisDisplay: Double
        let totalUnrealizedGainDisplay: Double
        let totalUnrealizedGainPct: Double
        let totalRealizedGainDisplay: Double
        let totalDividendsDisplay: Double
        let totalReturnDisplay: Double
        let totalReturnPct: Double
    }

    struct TypeTotal: Decodable {
        let count: Int
        let value: Double
    }

    struct Holding: Decodable, Identifiable, Hashable {
        let key: String
        let symbol: String?
        let name: String
        let assetType: String
        let totalQty: Double
        let avgCostDisplay: Double?
        let currentPriceDisplay: Double?
        let costBasisDisplay: Double
        let marketValueDisplay: Double
        let unrealizedGainDisplay: Double
        let unrealizedGainPct: Double?
        let realizedGainDisplay: Double
        let dividendsDisplay: Double
        let totalReturnDisplay: Double
        let totalReturnPct: Double?
        let dayChangeDisplay: Double?
        let dayChangePct: Double?
        let pctOfPortfolio: Double?
        let accountCount: Int
        /// The security's long name, such as "Vanguard Total Stock Market ETF". Often null.
        let description: String?
        /// The holding's quote currency. Null when its accounts hold it in different currencies; then every
        /// `*Native` field is null too.
        let nativeCurrency: String?
        let avgCostNative: Double?
        let currentPriceNative: Double?
        let marketValueNative: Double?
        let unrealizedGainNative: Double?
        let dividendsNative: Double?
        let totalReturnNative: Double?
        /// The whole position's change today, not per share.
        let dayChangeNative: Double?
        var id: String { key }
    }
}

// MARK: Performance (GET /api/portfolio/performance, enveloped)

nonisolated struct PortfolioPerformance: Decodable {
    let currency: String
    let series: [Point]
    let twrr: Twrr?
    let mwrr: Mwrr?

    struct Point: Decodable, Identifiable {
        let date: String
        let marketValue: Double
        let costBasis: Double?
        var id: String { date }
        var day: Date { APIDate.parse(date) ?? .distantPast }
    }

    /// Time-weighted return as a fraction (0.142 is 14.2%).
    struct Twrr: Decodable {
        let period: Double?
        let annualized: Double?
    }

    /// Money-weighted return (XIRR) as a fraction. Only meaningful when `converged`.
    struct Mwrr: Decodable {
        let irr: Double?
        let converged: Bool?
    }
}

/// `GET /api/portfolio/performance/holdings` (enveloped): each holding's value per day.
nonisolated struct HoldingPerformance: Decodable {
    let currency: String
    let points: [Point]

    struct Point: Decodable {
        let date: String
        let members: [Member]
        var day: Date { APIDate.parse(date) ?? .distantPast }
    }

    struct Member: Decodable {
        let id: Int?
        let name: String?
        let value: Double
    }
}

// MARK: Editing a holding (PUT /api/portfolio)

/// One holding row (a position in one account). Nil fields are left out of the body; the server merges the rest
/// over the saved row. `isCrypto` is 0 or 1.
nonisolated struct HoldingUpdate: Encodable, Equatable {
    let id: Int
    var name: String?
    var symbol: String?
    var currency: String?
    var isCrypto: Int?
    var note: String?
}

/// `GET /api/portfolio`: the holding rows for pickers and editing, without prices.
nonisolated struct PortfolioHolding: Decodable, Identifiable, Hashable {
    let id: Int
    let accountId: Int?
    let accountName: String?
    let name: String?
    let symbol: String?
    let currency: String
    let isCrypto: Int?
    let isCash: Bool?
    let note: String?
}

// MARK: Lots (GET /api/portfolio/holdings/[id]/lots)

nonisolated struct HoldingLots: Decodable {
    let lots: [Lot]
    let closures: [Closure]

    struct Lot: Decodable, Identifiable, Hashable {
        let id: Int
        let accountId: Int?
        let openTxId: Int?
        let openDate: String
        let side: String?
        let origin: String?
        let status: String
        let qtyOriginal: Double
        let qtyRemaining: Double
        let costPerShare: Double
        let currency: String
    }

    struct Closure: Decodable, Identifiable, Hashable {
        let id: Int
        let lotId: Int
        let closeTxId: Int?
        let closeDate: String
        let qtyClosed: Double
        let proceedsPerShare: Double
        let costPerShare: Double
        let realizedGain: Double
        let currency: String
        let closeKind: String?
    }
}

// MARK: Dividends and realized gains (enveloped)

nonisolated struct DividendIncome: Decodable {
    let rows: [Row]?
    let totals: Totals

    struct Row: Decodable, Identifiable, Hashable {
        let txId: Int
        let date: String
        let amount: Double
        let currency: String
        let isReinvested: Bool?
        let isWithholding: Bool?
        let holdingId: Int?
        let holdingName: String?
        let accountId: Int?
        let accountName: String?
        let payee: String?
        var id: Int { txId }
    }

    struct Totals: Decodable {
        let amount: Double
        let rowCount: Int
        let byCurrency: [String: Double]
    }
}

nonisolated struct RealizedGains: Decodable {
    let rows: [Row]
    let totals: Totals

    struct Row: Decodable, Identifiable, Hashable {
        let closureId: Int
        let closeDate: String
        let holdingId: Int?
        let holdingName: String?
        let accountId: Int?
        let accountName: String?
        let qtyClosed: Double
        let proceedsPerShare: Double
        let costPerShare: Double
        let realizedGain: Double
        let currency: String
        let openDate: String?
        let daysHeld: Int?
        let term: String?
        let closeKind: String?
        var id: Int { closureId }
    }

    struct Totals: Decodable {
        let realizedGain: Double
        let qtyClosed: Double
        let rowCount: Int
        let byCurrency: [String: Currency]
    }

    struct Currency: Decodable {
        let realizedGain: Double
        let qtyClosed: Double
    }
}

// MARK: Recording an investment (POST /api/portfolio/operations/<op>)

/// One brokerage operation. Each case maps to its own route and request body.
nonisolated enum InvestmentOp {
    case buy(Buy)
    case sell(Sell)
    /// Dividend, interest or a fee on the account. A fee is a negative amount.
    case income(Income)
    case deposit(Transfer)
    case withdrawal(Transfer)
    case swap(Swap)

    var path: String {
        switch self {
        case .buy: "/api/portfolio/operations/buy"
        case .sell: "/api/portfolio/operations/sell"
        case .income: "/api/portfolio/operations/income-expense"
        case .deposit: "/api/portfolio/operations/deposit"
        case .withdrawal: "/api/portfolio/operations/withdrawal"
        case .swap: "/api/portfolio/operations/swap"
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        return switch self {
        case .buy(let body): try encoder.encode(body)
        case .sell(let body): try encoder.encode(body)
        case .income(let body): try encoder.encode(body)
        case .deposit(let body), .withdrawal(let body): try encoder.encode(body)
        case .swap(let body): try encoder.encode(body)
        }
    }

    struct Buy: Encodable {
        var accountId: Int
        var holdingId: Int
        var qty: Double
        /// Price times shares plus fees, in the account currency.
        var totalCost: Double
        var date: String
        var payee: String?
        var note: String?
        var tags: String?
    }

    struct Sell: Encodable {
        var accountId: Int
        var holdingId: Int
        var qty: Double
        var totalProceeds: Double
        var date: String
        var payee: String?
        var note: String?
        var tags: String?
    }

    struct Income: Encodable {
        var accountId: Int
        var currency: String?
        var amount: Double
        var relatedHoldingId: Int?
        /// `dividend`, `interest`, `fee` or `other`.
        var incomeType: String?
        var date: String
        var payee: String?
        var note: String?
    }

    /// Cash moved between a bank account and a brokerage account.
    struct Transfer: Encodable {
        var sourceAccountId: Int
        var destAccountId: Int
        var amount: Double
        var date: String
        var payee: String?
        var note: String?
    }

    struct Swap: Encodable {
        var accountId: Int
        var sourceHoldingId: Int
        var sourceQty: Double
        var sourceProceeds: Double
        var destHoldingId: Int
        var destQty: Double
        var destCost: Double
        var date: String
        var note: String?
    }
}
