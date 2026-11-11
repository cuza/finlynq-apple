import Foundation
import Testing
@testable import Finlynq

struct ReviewQueueTests {
    private func row(_ id: String, category: Int? = nil, match: Int? = nil) -> StagedRow {
        StagedRow(id: id, date: "2026-11-08", amount: -10, categoryId: category, match: match.map { ReviewMatch(transactionId: $0) })
    }

    @Test func approveAdvances() {
        var queue = ReviewQueue(rows: [row("a", category: 1), row("b", category: 2)])
        #expect(queue.current?.id == "a")
        #expect(queue.position == 1)
        queue.approve()
        #expect(queue.current?.id == "b")
        #expect(queue.position == 2)
        #expect(queue.outcome(of: "a") == .approved)
    }

    @Test func matchBlocksApprove() {
        var queue = ReviewQueue(rows: [row("a", category: 1, match: 55), row("b", category: 1, match: 56)])
        #expect(queue.needsChoice)
        queue.approve()
        #expect(queue.current?.id == "a", "a possible match blocks Approve")
        queue.keepSeparate()
        #expect(!queue.needsChoice)
        queue.approve()
        #expect(queue.outcome(of: "a") == .approved)
        queue.link()
        #expect(queue.outcome(of: "b") == .linked)
        #expect(queue.isDone)
    }

    @Test func approveAllSuggestedSkipsUnsuggested() {
        var queue = ReviewQueue(rows: [row("a", category: 1), row("b"), row("c", category: 3, match: 9), row("d", category: 4)])
        #expect(queue.suggested.map(\.id) == ["a", "d"], "rows without a category or with a possible match stay")
        #expect(queue.suggestedCount == 2)
        for row in queue.suggested { queue.finish(row.id, .approved) }
        #expect(queue.current?.id == "b")
        #expect(queue.pending.map(\.id) == ["b", "c"])
        #expect(queue.suggestedCount == 0)
    }

    @Test func emptyQueueShowsDone() {
        var queue = ReviewQueue(rows: [])
        #expect(queue.isDone)
        #expect(queue.current == nil)
        queue.approve()
        queue.skip()
        #expect(queue.isDone)
        var one = ReviewQueue(rows: [row("a", category: 1)])
        one.approve()
        #expect(one.isDone)
    }

    @Test func skipWrapsAndCategorizeSetsTheCategory() {
        var queue = ReviewQueue(rows: [row("a"), row("b")])
        queue.skip()
        #expect(queue.current?.id == "b")
        #expect(queue.next?.id == "a")
        queue.skip()
        #expect(queue.current?.id == "a")
        queue.categorize(8492)
        #expect(queue.current?.categoryId == 8492)
        #expect(queue.suggestedCount == 1)
    }

    @Test func removeDropsTheRowAndSelectPicksAnother() {
        var queue = ReviewQueue(rows: [row("a"), row("b"), row("c")])
        queue.select("b")
        queue.remove()
        #expect(queue.rows.map(\.id) == ["a", "c"])
        #expect(queue.current?.id == "c")
        queue.remove()
        #expect(queue.current?.id == "a")
    }

    @Test func finishingABankRowFinishesEveryRowForIt() {
        let first = StagedRow(id: "x1", date: "2026-11-08", amount: -1, bankId: "bk", categoryId: 1)
        let copy = StagedRow(id: "x2", date: "2026-11-08", amount: -1, bankId: "bk", categoryId: 1)
        var queue = ReviewQueue(rows: [first, copy, row("c", category: 1)])
        queue.approve()
        #expect(queue.outcome(of: "x2") == .approved, "booking the same bank row again makes a second transaction")
        #expect(queue.current?.id == "c")
    }

    @Test func removeByIdKeepsTheCurrentRow() {
        var queue = ReviewQueue(rows: [row("a"), row("b"), row("c")])
        queue.select("c")
        queue.remove(id: "a")
        #expect(queue.current?.id == "c")
        #expect(queue.rows.map(\.id) == ["b", "c"])
    }

    @Test func copyIsSingularForOneRow() {
        #expect(PendingImport(id: "i1", file: "cafe.csv", rows: 1).banner == "1 row from cafe.csv isn't in your bank ledger yet")
        #expect(PendingImport(id: "i1", file: nil, rows: 6).banner == "6 rows from an import aren't in your bank ledger yet")
        #expect(ReconcileModel.notSent(["Duplicate"]) == "1 row wasn't sent: Duplicate")
        #expect(ReconcileModel.notSent(["Duplicate", "Bad date"]) == "2 rows weren't sent: Duplicate")
        #expect(ReconcileModel.notSent([]) == nil)
    }

    @Test func unlinkedBankRowsKeepOneOrder() throws {
        let ids = ["b7", "b2", "b9", "b1", "b5", "b3"]
        let rows = ids.map { #""\#($0)":{"id":"\#($0)","date":"2026-11-08","amount":-10,"accountId":1}"# }
        let json = #"{"linked":[{"transactionId":1,"bankTransactionId":"b9"}],"suggestions":[],"transactions":{},"bankTransactions":{"#
            + rows.joined(separator: ",") + "}}"
        let snapshot = try JSONDecoder().decode(ReconcileSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.unlinked.map(\.id) == ["b1", "b2", "b3", "b5", "b7"])
    }
}
