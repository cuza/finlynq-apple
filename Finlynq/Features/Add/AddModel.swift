import Foundation
import Observation

/// State and request building for the Add sheet.
@Observable
final class AddModel {
    enum Kind: String, CaseIterable, Identifiable {
        case expense, income, transfer, invest
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        /// Category type the server stores for this kind.
        var categoryType: String? { self == .expense ? "E" : self == .income ? "I" : nil }
    }

    enum InvestOperation: String, CaseIterable, Identifiable {
        case buy, sell, dividend, deposit, withdraw
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var usesShares: Bool { self == .buy || self == .sell }
    }

    struct InvestPrefill {
        let operation: InvestOperation
        let symbol: String?
        let accountId: Int?
    }

    var kind: Kind
    var operation: InvestOperation = .buy
    var amountText = ""
    var categoryId: Int?
    var accountId: Int?
    /// Transfer destination, or the brokerage account of a deposit.
    var toAccountId: Int?
    var holdingId: Int?
    var sharesText = ""
    var priceText = ""
    var feesText = ""
    var date = Date()
    var payee = ""
    var note = ""
    /// Symbol to pick once holdings load.
    var prefillSymbol: String?
    /// Decides whether "1,234" is a thousand or a decimal when typed.
    var locale = Locale.current
    private(set) var isSaving = false

    init(kind: Kind = .expense, invest: InvestPrefill? = nil) {
        self.kind = kind
        guard let invest else { return }
        self.kind = .invest
        operation = invest.operation
        prefillSymbol = invest.symbol
        // A deposit moves cash into the brokerage, so the prefilled account is the destination.
        if invest.operation == .deposit { toAccountId = invest.accountId } else { accountId = invest.accountId }
    }

    // MARK: Number pad

    func press(_ key: AmountPad.Key) {
        switch key {
        case .digit(let digit):
            if let dot = amountText.firstIndex(of: ".") {
                guard amountText.distance(from: dot, to: amountText.endIndex) <= 2 else { return }
            } else if amountText.count >= 9 {
                return
            }
            amountText = (amountText == "0" ? "" : amountText) + String(digit)
        case .dot:
            guard !amountText.contains(".") else { return }
            amountText += amountText.isEmpty ? "0." : "."
        case .backspace:
            amountText = String(amountText.dropLast())
        }
    }

    // MARK: Derived values

    /// Parses a typed number. Either "," or "." can be the decimal separator: the last one is, unless exactly three
    /// digits follow it and the locale groups with it ("1,234" in English). Earlier separators and spaces are
    /// grouping. Anything else, such as "inf" or a sign, returns nil.
    nonisolated static func number(_ text: String, locale: Locale = .current) -> Decimal? {
        let separators: Set<Character> = [",", "."]
        var digits = text.filter { !$0.isWhitespace }
        if let last = digits.lastIndex(where: separators.contains) {
            let tail = digits[digits.index(after: last)...]
            let grouping = tail.count == 3 && String(digits[last]) != (locale.decimalSeparator ?? ".")
            digits = digits[..<last].filter { !separators.contains($0) } + (grouping ? "" : ".") + tail
        }
        let isDigit = { (char: Character) in ("0"..."9").contains(char) }
        guard digits.contains(where: isDigit), digits.allSatisfy({ isDigit($0) || $0 == "." }) else { return nil }
        // Decimal(string:) returns nil past its range, so a long run of digits can't become infinity.
        return Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func value(_ text: String, cents: Bool = false) -> Double? {
        guard var number = Self.number(text, locale: locale) else { return nil }
        if cents {
            var exact = number
            NSDecimalRound(&number, &exact, 2, .plain)
        }
        return NSDecimalNumber(decimal: number).doubleValue
    }

    /// Rounded to cents.
    var amount: Double? { value(amountText, cents: true).flatMap { $0 > 0 ? $0 : nil } }
    private var shares: Double? { value(sharesText).flatMap { $0 > 0 ? $0 : nil } }
    private var price: Double? { value(priceText).flatMap { $0 >= 0 ? $0 : nil } }
    private var fees: Double { value(feesText) ?? 0 }

    /// Buy: price times shares plus fees. Sell: price times shares minus fees. Rounded to cents.
    var investTotal: Double {
        let gross = (shares ?? 0) * (price ?? 0)
        let total = operation == .sell ? gross - fees : gross + fees
        return (total * 100).rounded() / 100
    }

    var canSave: Bool {
        switch kind {
        case .expense, .income: return amount != nil && accountId != nil && categoryId != nil
        case .transfer: return amount != nil && accountId != nil && toAccountId != nil && accountId != toAccountId
        case .invest:
            switch operation {
            case .buy, .sell: return accountId != nil && holdingId != nil && shares != nil && price != nil && investTotal > 0
            case .dividend: return amount != nil && accountId != nil
            case .deposit, .withdraw: return amount != nil && accountId != nil && toAccountId != nil && accountId != toAccountId
            }
        }
    }

    /// Sheet title: "New expense", or "New buy" for an investment. Only the button says "Record buy".
    var title: String { "New \(kind == .invest ? operation.rawValue : kind.rawValue)" }

    /// "Add $12.50 to Coffee".
    func buttonTitle(currency: String?, categoryName: String?) -> String {
        guard kind == .expense || kind == .income, let amount else {
            return kind == .transfer ? "Add transfer" : "Add \(kind.rawValue)"
        }
        let text = "Add \(amount.money(currency))"
        return categoryName.map { "\(text) to \($0)" } ?? text
    }

    // MARK: Saving

    /// Sends the entry and returns true once the server accepted it. A call made while another is in flight,
    /// or before the entry is complete, sends nothing and returns false.
    @discardableResult
    func save(api: APIClient) async throws -> Bool {
        guard canSave, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        let day = APIDate.string(date)
        let payee = payee.isEmpty ? nil : payee
        let note = note.isEmpty ? nil : note
        switch kind {
        case .expense, .income:
            guard let amount else { return false }
            try await api.createTransaction(TransactionInput(
                date: day, accountId: accountId, categoryId: categoryId, amount: kind == .income ? amount : -amount,
                payee: payee, note: note
            ))
        case .transfer:
            guard let accountId, let toAccountId, let amount else { return false }
            try await api.createTransfer(TransferInput(
                fromAccountId: accountId, toAccountId: toAccountId, enteredAmount: amount, date: day, note: note
            ))
        case .invest:
            try await api.recordInvestment(investOperation(day: day, payee: payee, note: note))
        }
        return true
    }

    private func investOperation(day: String, payee: String?, note: String?) throws -> InvestmentOp {
        guard let accountId else { throw AddError.incomplete }
        switch operation {
        case .buy, .sell:
            guard let holdingId, let shares else { throw AddError.incomplete }
            if operation == .buy {
                return .buy(.init(accountId: accountId, holdingId: holdingId, qty: shares, totalCost: investTotal,
                                  date: day, payee: payee, note: note))
            }
            return .sell(.init(accountId: accountId, holdingId: holdingId, qty: shares, totalProceeds: investTotal,
                               date: day, payee: payee, note: note))
        case .dividend:
            guard let amount else { throw AddError.incomplete }
            return .income(.init(accountId: accountId, amount: amount, relatedHoldingId: holdingId, incomeType: "dividend",
                                 date: day, payee: payee, note: note))
        case .deposit, .withdraw:
            guard let amount, let toAccountId else { throw AddError.incomplete }
            let body = InvestmentOp.Transfer(sourceAccountId: accountId, destAccountId: toAccountId, amount: amount,
                                             date: day, payee: payee, note: note)
            return operation == .deposit ? .deposit(body) : .withdrawal(body)
        }
    }

    enum AddError: LocalizedError {
        case incomplete
        var errorDescription: String? { "Fill in every required field." }
    }

    // MARK: Quick categories

    /// The most used categories of this kind over the last 90 days, topped up alphabetically.
    static func quickCategories(
        recent: [Transaction], all: [Category], kind: Kind, limit: Int = 7, now: Date = .now
    ) -> [Category] {
        guard let type = kind.categoryType else { return [] }
        let candidates = all.filter { $0.type == type }
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now
        var counts: [Int: Int] = [:]
        for row in recent where row.day >= cutoff {
            if let id = row.categoryId { counts[id, default: 0] += 1 }
        }
        let byName = { (lhs: Category, rhs: Category) in lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending }
        let used = candidates.filter { counts[$0.id] != nil }
            .sorted { counts[$0.id]! != counts[$1.id]! ? counts[$0.id]! > counts[$1.id]! : byName($0, $1) }
        let rest = candidates.filter { counts[$0.id] == nil }.sorted(by: byName)
        return Array((used + rest).prefix(limit))
    }
}
