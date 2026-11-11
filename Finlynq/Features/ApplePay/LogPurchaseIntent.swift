import AppIntents
import Foundation
import os

/// The Shortcuts action a Wallet automation runs after each Apple Pay purchase. It runs in the app's process
/// without opening the app. Every parameter is optional so a blank Wallet field never stops the automation to ask.
struct LogPurchaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Apple Pay purchase"
    static let description = IntentDescription(
        "Adds an Apple Pay purchase to Finlynq. In a Wallet automation, set Merchant, Amount and Card from Shortcut Input."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Merchant") var merchant: String?
    @Parameter(title: "Amount") var amount: IntentCurrencyAmount?
    @Parameter(title: "Card") var card: String?
    /// Used when Amount is empty, in case the Wallet trigger's amount only binds as a plain number.
    @Parameter(title: "Amount as a number") var number: Double?
    @Parameter(title: "Currency code") var currencyCode: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) at \(\.$merchant) paid with \(\.$card)") {
            \.$number
            \.$currencyCode
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Through the decimal's text: NSDecimalNumber.doubleValue turns 38.26 into 38.260000000000005.
        let value = amount.flatMap { Double($0.amount.description) } ?? number
        let message = await ApplePayCapture.capture(
            merchant: merchant, amount: value, currency: amount?.currencyCode ?? currencyCode, card: card
        )
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// Sends Apple Pay purchases to Finlynq as ordinary transactions, or keeps them in `PendingCaptures` until they
/// can be sent. When the bank import brings the same purchase, Review offers to link the two.
enum ApplePayCapture {
    /// AppStorage key for "Wait until I unlock Finlynq": when on, a purchase never signs in in the background.
    static let waitForUnlockKey = "applePayWaitForUnlock"

    /// The app's session once its window is up. FinlynqApp sets it.
    static weak var live: Session?
    static var store = PendingCaptures.shared

    /// The session that sends a purchase, or nil to queue it. With a window up, only a signed-in live session
    /// sends; a starting or Face ID-locked one queues, and the flush on sign-in sends it. With no window (the
    /// Wallet automation launched the app in the background) a separate session signs in with the saved password
    /// and only writes the purchase, unless the user turned on "Wait until I unlock Finlynq".
    static let signIn: @MainActor () async -> Session? = {
        if let live { return live.state == .signedIn ? live : nil }
        guard !UserDefaults.standard.bool(forKey: waitForUnlockKey) else { return nil }
        let session = Session()
        await session.start(requireBiometrics: false)
        return session.state == .signedIn ? session : nil
    }

    /// Tests swap in a session on a stubbed network.
    static var session = signIn

    private static let log = Logger(subsystem: "dev.cuza.finlynq", category: "applepay")
    /// Purchases being sent now, so a flush, a capture and a manual retry never post the same one twice.
    private static var sending: Set<UUID> = []

    /// Saves one purchase from the Wallet automation, then tries to send it. Returns what Shortcuts shows.
    static func capture(merchant: String?, amount: Double?, currency: String?, card: String?) async -> String {
        let card = card?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cardName = card.isEmpty ? "Apple Pay" : card
        let merchant = merchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let now = Fixtures.today
        let purchase = CapturedPurchase(
            merchant: merchant.isEmpty ? cardName : merchant, amount: amount ?? 0, currency: currency?.nilIfEmpty,
            card: cardName, date: APIDate.string(now), capturedAt: now, problem: .notSent
        )
        // Written to disk before any network call, so iOS ending the background launch mid-send loses nothing.
        store.put(purchase)
        return message(purchase, problem: await send(purchase.id))
    }

    /// Sends the stored purchase with this id. Returns nil when the server has it (or it is no longer waiting),
    /// else the problem it now waits with. A purchase already being sent is left alone.
    @discardableResult
    static func send(_ id: UUID) async -> CapturedPurchase.Problem? {
        guard var purchase = store.item(id) else { return nil }
        guard sending.insert(id).inserted else { return purchase.problem }
        defer { sending.remove(id) }
        let problem = await post(&purchase)
        if problem == nil {
            store.sent(purchase)
            if let live, live.state == .signedIn { await live.didSave() }
        } else {
            // Change only the status, so edits the user made in the fix sheet during the send are kept. A purchase
            // deleted meanwhile stays deleted.
            store.update(id) { stored in
                stored.problem = problem
                stored.attempted = stored.attempted || purchase.attempted
                if stored.accountId == nil { stored.accountId = purchase.accountId }
                if stored.categoryId == nil { stored.categoryId = purchase.categoryId }
            }
        }
        return problem
    }

    /// Purchases waiting on this device, which sign-out removes. Settings warns with it.
    static var waitingCount: Int { store.items.count }

    /// The sign-out confirmation's message when purchases are waiting.
    static var signOutWarning: String {
        let count = waitingCount
        return "\(count) waiting Apple Pay \(count == 1 ? "purchase" : "purchases") will be removed from this device."
    }

    /// True while a send for this purchase is in flight.
    static func isSending(_ id: UUID) -> Bool { sending.contains(id) }

    /// Sends every waiting purchase that doesn't need the user. Runs on sign-in and unlock. Reads the store again
    /// on each pass, so a purchase sent or deleted meanwhile is skipped.
    static func flush() async {
        var tried: Set<UUID> = []
        while let next = store.items.first(where: { !tried.contains($0.id) && $0.problem?.retriesOnItsOwn != false }) {
            tried.insert(next.id)
            await send(next.id)
        }
    }

    private static func post(_ purchase: inout CapturedPurchase) async -> CapturedPurchase.Problem? {
        // The Wallet trigger sometimes passes 0; never save a $0 expense.
        guard purchase.amount > 0 else { return .amount }
        guard let session = await session() else { return .notSent }
        if let problem = pickAccount(&purchase, accounts: session.accounts) { return problem }
        do {
            if purchase.categoryId == nil { purchase.categoryId = try await session.api.suggestCategory(payee: purchase.merchant) }
            guard purchase.categoryId != nil else { return .category }
            return try await create(&purchase, api: session.api)
        } catch APIError.server(let status, let message, _) where (400..<500).contains(status) && ![401, 408, 423, 429].contains(status) {
            log.error("Apple Pay purchase rejected (\(status)): \(message, privacy: .public)")
            return .rejected(message)
        } catch {
            log.error("Apple Pay purchase not sent: \(error.localizedDescription, privacy: .public)")
            return .notSent
        }
    }

    /// Sets the purchase's account from the card, saving a sure match for the card. Returns why it can't.
    private static func pickAccount(_ purchase: inout CapturedPurchase, accounts: [Account]) -> CapturedPurchase.Problem? {
        let match = CardMapping.match(for: purchase.card, mappings: store.mappings, accounts: accounts)
        guard let accountId = purchase.accountId ?? match?.id else {
            // No accounts means they didn't load, so the card can't be judged yet.
            return accounts.isEmpty ? .notSent : .account
        }
        purchase.accountId = accountId
        if let match, match.permanent, store.mappings[purchase.card] == nil { store.mappings[purchase.card] = match.id }
        return nil
    }

    /// Creates the transaction, unless an earlier attempt already did.
    private static func create(_ purchase: inout CapturedPurchase, api: APIClient) async throws -> CapturedPurchase.Problem? {
        // An earlier try may have reached the server and lost its reply: look for its tag before posting again.
        // Tags read as null while the server's encryption key is locked, so the lookup would miss; wait instead.
        if purchase.attempted {
            let info: SessionInfo = try await api.get("/api/auth/session")
            if info.encryptionLocked == true { return .notSent }
            if try await isOnServer(purchase, api: api) { return nil }
        }
        // Deleted while we waited on the network: never bring it back or post it. Otherwise post the stored copy,
        // which has any edits made meanwhile, and save the attempt first.
        guard var current = store.item(purchase.id) else { return .notSent }
        if current.accountId == nil { current.accountId = purchase.accountId }
        if current.categoryId == nil { current.categoryId = purchase.categoryId }
        current.attempted = true
        store.put(current)
        purchase = current
        guard let accountId = purchase.accountId, let categoryId = purchase.categoryId, purchase.amount > 0 else { return .amount }
        let spent = -purchase.amount
        try await api.createTransaction(TransactionInput(
            date: purchase.date, accountId: accountId, categoryId: categoryId,
            amount: purchase.currency == nil ? spent : nil,
            enteredAmount: purchase.currency == nil ? nil : spent, enteredCurrency: purchase.currency,
            payee: purchase.merchant, note: "Apple Pay", tags: purchase.tag
        ))
        return nil
    }

    private static func isOnServer(_ purchase: CapturedPurchase, api: APIClient) async throws -> Bool {
        let query = TransactionQuery(startDate: purchase.date, endDate: purchase.date, tag: purchase.tag, limit: 5)
        let page = try await api.transactions(query)
        return !page.data.isEmpty
    }

    static func message(_ purchase: CapturedPurchase, problem: CapturedPurchase.Problem?) -> String {
        let spent = "\(purchase.amount.money(purchase.currency)) at \(purchase.merchant)"
        switch problem {
        case nil: return "Added \(spent)"
        case .amount: return "Saved \(purchase.merchant) without an amount. Open Finlynq to enter it."
        case .account: return "Saved \(spent). Open Finlynq to pick the account for \(purchase.card)."
        case .category: return "Saved \(spent). Open Finlynq to pick a category."
        case .notSent: return "Saved \(spent). Finlynq sends it next time you open the app."
        case .rejected(let message): return "Saved \(spent), but Finlynq didn't accept it: \(message)"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
