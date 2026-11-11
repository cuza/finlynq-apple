import Foundation
import OSLog

/// The review queue's state: which row is on screen, which rows are done, and what the user chose for each.
/// Server calls live in `ReviewModel`; this only moves through the rows.
struct ReviewQueue {
    enum Outcome { case approved, linked }

    /// Every row, done ones included (the iPad list keeps them, greyed).
    private(set) var rows: [StagedRow]
    private(set) var index = 0
    private var outcomes: [String: Outcome] = [:]
    /// Rows with a possible match where the user picked Keep separate.
    private var keptSeparate: Set<String> = []

    init(rows: [StagedRow]) { self.rows = rows }

    var current: StagedRow? { rows.indices.contains(index) && outcomes[rows[index].id] == nil ? rows[index] : nil }
    /// The row after the current one, wrapping around.
    var next: StagedRow? { nextIndex(after: index).map { rows[$0] } }
    var pending: [StagedRow] { rows.filter { outcomes[$0.id] == nil } }
    var isDone: Bool { current == nil }
    var doneCount: Int { outcomes.count }
    /// "3 of 12": the current row counts after the done ones.
    var position: Int { doneCount + 1 }

    /// Rows "Approve all" books: a category picked or suggested, and no possible match left open.
    var suggested: [StagedRow] { pending.filter { $0.categoryId != nil && !isBlocked($0) } }
    var suggestedCount: Int { suggested.count }
    var needsCategoryCount: Int { pending.filter { $0.categoryId == nil }.count }

    /// The current row may copy an existing transaction and the user hasn't picked Link or Keep separate.
    var needsChoice: Bool { current.map(isBlocked) ?? false }

    func isBlocked(_ row: StagedRow) -> Bool { row.match != nil && !keptSeparate.contains(row.id) }
    func outcome(of id: String) -> Outcome? { outcomes[id] }

    /// Marks the current row approved and moves on. Does nothing while a possible match is open.
    mutating func approve() {
        guard let current, !needsChoice else { return }
        finish(current.id, .approved)
    }

    /// Marks the current row as the same payment as its match and moves on.
    mutating func link() {
        guard let current, current.match != nil else { return }
        finish(current.id, .linked)
    }

    mutating func keepSeparate() {
        if let current { keptSeparate.insert(current.id) }
    }

    mutating func skip() {
        if let next = nextIndex(after: index) { index = next }
    }

    mutating func categorize(_ categoryId: Int) {
        guard current != nil else { return }
        rows[index].categoryId = categoryId
    }

    /// Drops the current row from the queue, as after Delete.
    mutating func remove() {
        if let current { remove(id: current.id) }
    }

    /// Drops a row from the queue. When it was the current row, the next row still waiting becomes current.
    mutating func remove(id: String) {
        guard let found = rows.firstIndex(where: { $0.id == id }) else { return }
        let currentId = current?.id
        rows.remove(at: found)
        if let currentId, currentId != id, let kept = rows.firstIndex(where: { $0.id == currentId }) {
            index = kept
            return
        }
        index = rows.isEmpty ? 0 : found % rows.count
        if current == nil, let next = nextIndex(after: index) { index = next }
    }

    mutating func select(_ id: String) {
        if let found = rows.firstIndex(where: { $0.id == id }), outcomes[id] == nil { index = found }
    }

    /// Records a row's outcome. When it is the current row, moves to the next one still waiting.
    mutating func finish(_ id: String, _ outcome: Outcome) {
        outcomes[id] = outcome
        // Another row for the same bank row is done too: booking a bank row twice makes two transactions.
        if let bankId = rows.first(where: { $0.id == id })?.bankId {
            for row in rows where row.bankId == bankId { outcomes[row.id] = outcome }
        }
        if rows.indices.contains(index), rows[index].id == id, let next = nextIndex(after: index) { index = next }
    }

    /// The next row still waiting after `start`, wrapping around, or nil when none is left besides `start`.
    private func nextIndex(after start: Int) -> Int? {
        guard rows.count > 1 else { return nil }
        return (1..<rows.count).lazy.map { (start + $0) % rows.count }.first { outcomes[self.rows[$0].id] == nil }
    }
}

/// An import whose rows aren't in the bank ledger yet. Review lists it with Send instead of its rows: rows are
/// booked only from the bank ledger, and sending writes bank rows, so the user decides when.
struct PendingImport: Identifiable, Hashable {
    let id: String
    let file: String?
    let rows: Int
    /// Rows the server couldn't send last time, with its reasons.
    var errors: [String] = []

    /// "6 rows from chequing-nov.csv aren't in your bank ledger yet", "1 row from ... isn't ...".
    var banner: String {
        let from = file ?? "an import"
        return rows == 1 ? "1 row from \(from) isn't in your bank ledger yet" : "\(rows) rows from \(from) aren't in your bank ledger yet"
    }
}

/// Loads the review queue and sends the user's choices to the server (Review.dc.html, iPadReview.dc.html).
/// Every change bumps `session.revision` so Home and Activity reload their counts.
@Observable
final class ReviewModel {
    private(set) var queue = ReviewQueue(rows: [])
    /// Imports waiting to be sent to the bank ledger, shown above the queue.
    private(set) var pendingImports: [PendingImport] = []
    private(set) var loaded = false
    /// A failed load; the screen shows it with Retry.
    private(set) var loadError: String?
    /// A failed action; shown above the buttons.
    var error: String?
    private(set) var isWorking = false
    /// Create a rule from the current row when approving it (iPad).
    var createsRule = false
    /// The server's row errors from the last send, by import id. Kept across reloads while the import is pending.
    private var sendErrors: [String: [String]] = [:]

    private static let log = Logger(subsystem: "dev.cuza.finlynq", category: "review")

    /// Lists bank rows to review and the imports still waiting to be sent. Sends nothing.
    func load(_ session: Session) async {
        do {
            let rows = try await session.api.reviewQueue()
            let bank = rows.filter { $0.bankId != nil }
            // Newest first; the original order breaks ties so the list doesn't shuffle between loads.
            let sorted = bank.enumerated().sorted { ($0.element.date, $1.offset) > ($1.element.date, $0.offset) }.map(\.element)
            queue = ReviewQueue(rows: sorted)
            let staged = Dictionary(grouping: rows.filter { $0.bankId == nil && $0.importId != nil }) { $0.importId ?? "" }
            pendingImports = staged.map { id, rows in
                PendingImport(id: id, file: rows.first?.importFile, rows: rows.count, errors: sendErrors[id] ?? [])
            }
            .sorted { $0.id < $1.id }
            loadError = nil
            loaded = true
        } catch is CancellationError {
        } catch {
            Self.log.error("review queue failed to load: \(error.localizedDescription, privacy: .public)")
            loadError = error.localizedDescription
        }
    }

    /// The error line's Reload: clears the failed action's message, then lists the queue again. `load` keeps the
    /// message, so the reload after a failed action still shows it.
    func reload(_ session: Session) async {
        error = nil
        await load(session)
    }

    /// Sends one import's rows to the bank ledger in one call (no row ids, so the server numbers identical rows),
    /// then reloads so its rows show up for review. Rows the server refused stay pending with its reasons.
    func send(_ importId: String, session: Session) async {
        await perform(session, reload: true) {
            do {
                let result = try await session.api.approveStaged(importId: importId)
                let errors = result.rowErrors?.map(\.message) ?? []
                self.sendErrors[importId] = errors.isEmpty ? nil : errors
            } catch APIError.server(400, "No rows selected", _) {
                // Every row was a duplicate; the server resolved the import.
                self.sendErrors[importId] = nil
            }
        }
    }

    func skip() { queue.skip() }
    func keepSeparate() { queue.keepSeparate() }
    func select(_ id: String) { queue.select(id) }
    func categorize(_ categoryId: Int) { queue.categorize(categoryId) }

    /// Books the current row in its category. The caller asks for a category first when the row has none.
    /// The row is done as soon as the server books it; a rule that then fails is reported on its own, so the row
    /// can't be booked twice.
    func approve(_ session: Session) async {
        guard let row = queue.current, let categoryId = row.categoryId, !queue.needsChoice else { return }
        let rule = createsRule ? Self.rule(for: row, categoryId: categoryId) : nil
        await perform(session) {
            try await session.api.approveReviewRow(row, categoryId: categoryId)
            self.queue.finish(row.id, .approved)
            guard let rule else { return }
            do {
                try await session.api.createRule(rule)
            } catch {
                Self.log.error("rule failed after booking: \(error.localizedDescription, privacy: .public)")
                throw RuleFailed(message: "Approved. The rule wasn't saved: \(error.localizedDescription)")
            }
        }
    }

    func link(_ session: Session) async {
        guard let row = queue.current, row.match != nil else { return }
        await perform(session) {
            try await session.api.linkReviewRow(row)
            self.queue.finish(row.id, .linked)
        }
    }

    func delete(_ session: Session) async {
        guard let row = queue.current else { return }
        await perform(session) {
            try await session.api.removeReviewRow(row)
            self.queue.remove(id: row.id)
        }
    }

    /// Books every row with a category and no open match, one at a time. Stops at the first failure.
    func approveAllSuggested(_ session: Session) async {
        let rows = queue.suggested
        await perform(session) {
            for row in rows where self.queue.outcome(of: row.id) == nil {
                guard let categoryId = row.categoryId else { continue }
                try await session.api.approveReviewRow(row, categoryId: categoryId)
                self.queue.finish(row.id, .approved)
            }
        }
    }

    private struct RuleFailed: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// "Payee contains <first two words>, set <category>".
    static func rule(for row: StagedRow, categoryId: Int) -> RuleInput? {
        guard let text = rulePayee(row) else { return nil }
        return RuleInput(
            name: text, conditions: .init(all: [.init(field: "payee", op: "contains", value: .text(text))]),
            actions: [.init(kind: "set_category", categoryId: categoryId)]
        )
    }

    static func rulePayee(_ row: StagedRow) -> String? {
        let words = (row.payee ?? "").split(separator: " ").prefix(2)
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// Runs an action, then bumps the revision. After a failure, or with `reload`, the queue is listed again from the
    /// server: a timeout can hide a booking that happened, and the reload keeps that row from being booked twice.
    private func perform(_ session: Session, reload: Bool = false, _ work: () async throws -> Void) async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        var failed = false
        do {
            try await work()
        } catch is CancellationError {
            return
        } catch let ruleError as RuleFailed {
            // The booking went through; only the rule is missing, so the queue is right as it is.
            self.error = ruleError.message
        } catch {
            Self.log.error("review action failed: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
            failed = true
        }
        await session.didSave()
        if failed || reload { await load(session) }
    }
}
