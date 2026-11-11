import OSLog
import SwiftUI

/// Mac review (MacReview.dc.html): one account's bank rows beside its Finlynq transactions. Select rows on both
/// sides and link them, add bank rows as new transactions, or link every suggested pair at once. The footer
/// compares the bank's balance with Finlynq's.
@Observable
final class ReconcileModel {
    enum Window: Int, CaseIterable {
        case days30 = 30, days60 = 60, days90 = 90, all = 0
        var label: String { self == .all ? "All dates" : "\(rawValue) days" }
    }

    var accountId: Int?
    var window = Window.days30
    private(set) var snapshot: ReconcileSnapshot?
    private(set) var balance: BalanceSummary?
    /// Staged rows for this account that are not in the bank ledger yet.
    private(set) var staged: [StagedRow] = []
    private(set) var loadError: String?
    var error: String?
    private(set) var isWorking = false
    var bankSelection: Set<String> = []
    var ledgerSelection: Set<Int> = []
    /// Bank rows hidden with Ignore until the next load.
    private(set) var ignored: Set<String> = []

    private static let log = Logger(subsystem: "dev.cuza.finlynq", category: "reconcile")

    func dateMin(today: Date) -> String? {
        guard window != .all else { return nil }
        return APIDate.string(Calendar.current.date(byAdding: .day, value: -window.rawValue, to: today) ?? today)
    }

    /// Picks the account with the most bank rows waiting when none is chosen, then loads its two panes.
    func load(_ session: Session, today: Date) async {
        do {
            if accountId == nil {
                let summary: ReconcileSummary? = try? await session.api.get("/api/reconcile/summary")
                accountId = summary?.rows.max { $0.pendingCount < $1.pendingCount }.flatMap { $0.pendingCount > 0 ? $0.accountId : nil }
                    ?? session.accounts.first { !$0.isInvestment && !$0.archived }?.id
            }
            guard let accountId else { return }
            async let snapshot = session.api.reconcileSnapshot(accountId: accountId, dateMin: dateMin(today: today))
            async let balance = try? session.api.balanceSummary(accountId: accountId)
            async let staged = try? session.api.stagedImports()
            self.snapshot = try await snapshot
            self.balance = await balance
            self.staged = (await staged ?? []).filter { $0.isPending && $0.accountId == accountId }
            bankSelection = []
            ledgerSelection = []
            ignored = []
            loadError = nil
        } catch is CancellationError {
        } catch {
            Self.log.error("reconcile failed to load: \(error.localizedDescription, privacy: .public)")
            loadError = error.localizedDescription
        }
    }

    // MARK: Rows

    enum Status { case linked, suggested, bankOnly, ledgerOnly }

    var bankRows: [ReconcileSnapshot.Bank] {
        (snapshot?.bankTransactions.values.filter { !ignored.contains($0.id) } ?? []).sorted { ($0.date, $0.id) > ($1.date, $1.id) }
    }

    var ledgerRows: [ReconcileSnapshot.Ledger] {
        (snapshot?.transactions.values.map(\.self) ?? []).sorted { ($0.date, $0.id) > ($1.date, $1.id) }
    }

    func status(bank id: String) -> Status {
        guard let snapshot else { return .bankOnly }
        if snapshot.linked.contains(where: { $0.bankTransactionId == id }) { return .linked }
        return snapshot.suggestions.contains { $0.bankTransactionId == id } ? .suggested : .bankOnly
    }

    func status(ledger id: Int) -> Status {
        guard let snapshot else { return .ledgerOnly }
        if snapshot.linked.contains(where: { $0.transactionId == id }) { return .linked }
        return snapshot.suggestions.contains { $0.transactionId == id } ? .suggested : .ledgerOnly
    }

    /// "7 linked · 3 suggested · 2 bank only · 1 Finlynq only".
    var countsLine: String {
        let bank = bankRows.map { status(bank: $0.id) }
        let ledger = ledgerRows.map { status(ledger: $0.id) }
        let linked = bank.filter { $0 == .linked }.count
        let bankOnly = bank.filter { $0 == .bankOnly }.count
        let ledgerOnly = ledger.filter { $0 == .ledgerOnly }.count
        return "\(linked) linked · \(snapshot?.suggestions.count ?? 0) suggested · \(bankOnly) bank only · \(ledgerOnly) Finlynq only"
    }

    var selectedBank: [ReconcileSnapshot.Bank] { bankRows.filter { bankSelection.contains($0.id) } }
    var selectedLedger: [ReconcileSnapshot.Ledger] { ledgerRows.filter { ledgerSelection.contains($0.id) } }

    /// The server's reason when exactly one suggested pair is selected.
    var selectionReason: String? {
        guard selectedBank.count == 1, selectedLedger.count == 1 else { return nil }
        return snapshot?.suggestions.first {
            $0.bankTransactionId == selectedBank[0].id && $0.transactionId == selectedLedger[0].id
        }?.reason
    }

    func clearSelection() {
        bankSelection = []
        ledgerSelection = []
    }

    // MARK: Actions

    func link(_ session: Session, today: Date) async {
        let banks = Array(bankSelection)
        let ledger = Array(ledgerSelection)
        guard !banks.isEmpty, !ledger.isEmpty else { return }
        await perform(session, today: today) { try await session.api.linkBankRows(bankIds: banks, transactionIds: ledger) }
    }

    /// Selected bank rows that no transaction is linked to. Only these can be added as new: booking a linked bank
    /// row would make a second transaction, and the server doesn't refuse it.
    var selectedUnlinked: [ReconcileSnapshot.Bank] { selectedBank.filter { status(bank: $0.id) != .linked } }

    /// Books each selected unlinked bank row as a new transaction, in its suggested category or else `categoryId`.
    func addAsNew(_ session: Session, categoryId: Int?, today: Date) async {
        let rows = selectedUnlinked
        await perform(session, today: today) {
            for bank in rows {
                guard let category = bank.suggestedCategoryId ?? categoryId else { continue }
                let row = StagedRow(id: bank.id, date: bank.date, amount: bank.amount, accountId: bank.accountId, bankId: bank.id)
                try await session.api.approveReviewRow(row, categoryId: category)
            }
        }
    }

    func approveAllSuggested(_ session: Session, today: Date) async {
        let pairs = snapshot?.suggestions ?? []
        await perform(session, today: today) {
            for pair in pairs {
                try await session.api.linkBankRows(bankIds: [pair.bankTransactionId], transactionIds: [pair.transactionId])
            }
        }
    }

    func ignoreSelection() {
        ignored.formUnion(bankSelection)
        clearSelection()
    }

    /// Sends this account's staged rows to the bank ledger, so they show as bank rows.
    func loadStaged(_ session: Session, today: Date) async {
        let batches = Set(staged.compactMap(\.importId))
        await perform(session, today: today) {
            var failures: [String] = []
            for batch in batches {
                // One call per import, so the server numbers identical rows within it.
                failures += try await session.api.approveStaged(importId: batch).rowErrors?.map(\.message) ?? []
            }
            if let message = Self.notSent(failures) { self.error = message }
        }
    }

    /// "1 row wasn't sent: <reason>" or "3 rows weren't sent: <first reason>"; nil when every row was sent.
    static func notSent(_ failures: [String]) -> String? {
        guard let first = failures.first else { return nil }
        return failures.count == 1 ? "1 row wasn't sent: \(first)" : "\(failures.count) rows weren't sent: \(first)"
    }

    private func perform(_ session: Session, today: Date, _ work: () async throws -> Void) async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            try await work()
        } catch is CancellationError {
        } catch {
            Self.log.error("reconcile action failed: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
        }
        await session.didSave()
        await load(session, today: today)
    }
}
