import Foundation
import Observation
import os

/// A purchase from the Wallet automation. `amount` is what was spent, positive.
nonisolated struct CapturedPurchase: Codable, Identifiable, Equatable {
    /// Why a purchase is still waiting.
    enum Problem: Codable, Equatable {
        case amount, account, category, notSent
        /// The server turned the purchase down (a 4xx other than 401/423), with its message. Not retried on its own.
        case rejected(String)

        var text: String {
            switch self {
            case .amount: "Enter the amount"
            case .account: "Pick an account"
            case .category: "Pick a category"
            case .notSent: "Not sent yet"
            case .rejected(let message): "Not accepted: \(message)"
            }
        }

        /// Sent again on sign-in without the user: offline, or waiting on a mapping or category that may now exist.
        var retriesOnItsOwn: Bool { self == .notSent || self == .account || self == .category }
    }

    var id = UUID()
    var merchant: String
    var amount: Double
    var currency: String?
    var card: String
    /// The purchase day, YYYY-MM-DD.
    var date: String
    var capturedAt: Date
    /// Set when the user picks them while fixing a waiting purchase.
    var accountId: Int?
    var categoryId: Int?
    var problem: Problem?
    /// Set and saved just before the create request, so a retry first checks whether the server already has it.
    var attempted = false

    /// The tag sent with the transaction, which a retry looks up to avoid creating it twice.
    var tag: String { "applepay:" + id.uuidString.prefix(8).lowercased() }
}

extension CapturedPurchase {
    private enum CodingKeys: String, CodingKey {
        case id, merchant, amount, currency, card, date, capturedAt, accountId, categoryId, problem, attempted
    }

    /// Fields added after the first release decode with a default, so a saved queue never fails to load.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        merchant = try container.decode(String.self, forKey: .merchant)
        amount = try container.decode(Double.self, forKey: .amount)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        card = try container.decode(String.self, forKey: .card)
        date = try container.decode(String.self, forKey: .date)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        accountId = try container.decodeIfPresent(Int.self, forKey: .accountId)
        categoryId = try container.decodeIfPresent(Int.self, forKey: .categoryId)
        problem = try container.decodeIfPresent(Problem.self, forKey: .problem)
        attempted = try container.decodeIfPresent(Bool.self, forKey: .attempted) ?? false
    }
}

/// Apple Pay purchases that wait to be sent, the card-to-account mappings and the last purchase sent. Saved as one
/// JSON file in the app's own container, so a purchase captured offline or signed out survives until it is sent.
@Observable
final class PendingCaptures {
    private struct Saved: Codable {
        var items: [CapturedPurchase] = []
        var mappings: [String: Int] = [:]
        var last: CapturedPurchase?

        init(items: [CapturedPurchase], mappings: [String: Int], last: CapturedPurchase?) {
            self.items = items
            self.mappings = mappings
            self.last = last
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decodeIfPresent([CapturedPurchase].self, forKey: .items) ?? []
            mappings = try container.decodeIfPresent([String: Int].self, forKey: .mappings) ?? [:]
            last = try container.decodeIfPresent(CapturedPurchase.self, forKey: .last)
        }
    }

    /// Fixture mode keeps everything in memory, with two sample cards for screenshots.
    static let shared = Fixtures.isEnabled
        ? PendingCaptures(url: nil, mappings: ["Visa ••1234": 4103, "Debit ••5678": 4100])
        : PendingCaptures(url: URL.applicationSupportDirectory.appending(path: "apple-pay-captures.json"))

    private(set) var items: [CapturedPurchase] { didSet { write() } }
    /// Wallet card name to account id.
    var mappings: [String: Int] { didSet { write() } }
    private(set) var last: CapturedPurchase? { didSet { write() } }
    var count: Int { items.count }

    private let url: URL?
    private static let log = Logger(subsystem: "dev.cuza.finlynq", category: "applepay")

    /// `url` nil keeps the captures in memory only.
    init(url: URL?, mappings: [String: Int] = [:]) {
        self.url = url
        let saved = url.flatMap(Self.load)
        items = saved?.items ?? []
        self.mappings = saved?.mappings ?? mappings
        last = saved?.last
    }

    /// The saved queue. A file that doesn't decode is logged and moved aside as `<name>.corrupt-<time>`, so the next
    /// write can't overwrite purchases that might still be recovered from it.
    private static func load(_ url: URL) -> Saved? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(Saved.self, from: data)
        } catch {
            let aside = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            log.error("Apple Pay queue didn't decode, moved to \(aside.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            try? FileManager.default.moveItem(at: url, to: aside)
            return nil
        }
    }

    /// Changes a waiting purchase in place. Does nothing when it is gone.
    func update(_ id: UUID, _ change: (inout CapturedPurchase) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    /// Adds a waiting purchase, or replaces the one with the same id.
    func put(_ purchase: CapturedPurchase) {
        if let index = items.firstIndex(where: { $0.id == purchase.id }) { items[index] = purchase } else { items.append(purchase) }
    }

    func remove(_ purchase: CapturedPurchase) { items.removeAll { $0.id == purchase.id } }

    func item(_ id: UUID) -> CapturedPurchase? { items.first { $0.id == id } }

    /// Forgets the waiting purchases, the card mappings and the last purchase. Called on sign-out.
    func clear() {
        items = []
        mappings = [:]
        last = nil
    }

    /// Records a purchase the server accepted.
    func sent(_ purchase: CapturedPurchase) {
        remove(purchase)
        last = purchase
    }

    private func write() {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Saved(items: items, mappings: mappings, last: last)).write(to: url, options: .atomic)
        } catch {
            Self.log.error("Saving Apple Pay captures failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
