import Foundation
import Testing
@testable import Finlynq

/// The review screens' server flows, against the URLProtocol stub. Nested in `APIClientTests` so they share that
/// suite's serialized run (the stub is global).
extension APIClientTests {
    struct ReviewModelTests {
        private func session(_ routes: [String: String], statuses: [Int] = []) -> Session {
            StubProtocol.statuses = statuses
            StubProtocol.requests = 0
            StubProtocol.sent = []
            StubProtocol.routes = routes.mapValues { Data($0.utf8) }
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [StubProtocol.self]
            return Session(api: APIClient(baseURL: URL(string: "https://example.test")!, session: URLSession(configuration: config)))
        }

        private var booked: [String] {
            StubProtocol.sent.map(\.path).filter { $0.hasPrefix("/api/bank-transactions/") }
        }

        private static func bank(_ id: String, category: Int? = 8487) -> String {
            let categoryJSON = category.map(String.init) ?? "null"
            return #""\#(id)":{"id":"\#(id)","date":"2026-11-08","amount":-4.5,"payee":"Cafe","accountId":4100,"#
                + #""suggestedCategoryId":\#(categoryJSON),"duplicateOfTransactionId":null}"#
        }

        private static func snapshot(_ banks: [String], linked: [String] = []) -> String {
            let links = linked.map { #"{"transactionId":9,"bankTransactionId":"\#($0)"}"# }.joined(separator: ",")
            return #"{"success":true,"data":{"linked":[\#(links)],"suggestions":[],"transactions":{},"#
                + #""bankTransactions":{\#(banks.joined(separator: ","))}}}"#
        }

        private static let pendingRow =
            #"{"id":"%@","date":"2026-11-08","amount":-4.5,"payee":"Cafe","rowStatus":"%@","reconcileState":"unmatched"}"#

        private static func detail(_ status: String) -> String {
            #"{"staged":{"id":"i1","source":"upload","totalRowCount":2,"duplicateCount":0},"rows":["#
                + String(format: pendingRow, "r1", status) + "," + String(format: pendingRow, "r2", status)
                + #"],"suggestedMatches":[]}"#
        }

        private static let batches =
            #"[{"id":"i1","source":"upload","totalRowCount":2,"duplicateCount":0,"boundAccountId":4100,"originalFilename":"cafe.csv"}]"#

        /// Opening Review writes nothing: an import waiting to be sent shows as a banner, not as rows.
        @Test func loadingReviewSendsNothing() async {
            let session = session([
                "GET /api/import/staged": Self.batches,
                "GET /api/import/staged/i1": Self.detail("pending"),
                "GET /api/reconcile/summary": #"{"rows":[]}"#
            ])
            let model = ReviewModel()
            await model.load(session)
            #expect(StubProtocol.sent.allSatisfy { $0.method == "GET" })
            #expect(model.pendingImports == [PendingImport(id: "i1", file: "cafe.csv", rows: 2)])
            #expect(model.queue.rows.isEmpty, "staged rows are never booked from the queue")
        }

        /// Two identical coffees in one import: Send posts the whole import once (no row ids) so the server numbers
        /// the repeat, they come back as two bank rows, and each is booked by its own id.
        @Test func sendingAnImportPostsOnceThenBooksBothIdenticalRows() async throws {
            let session = session([
                "GET /api/import/staged": Self.batches,
                "GET /api/import/staged/i1": Self.detail("pending"),
                "GET /api/reconcile/summary": #"{"rows":[]}"#
            ])
            let model = ReviewModel()
            await model.load(session)
            // What the server answers once the import is in the bank ledger.
            StubProtocol.routes["POST /api/import/staged/i1/approve"] = Data(#"{"approved":2}"#.utf8)
            StubProtocol.routes["GET /api/import/staged/i1"] = Data(Self.detail("approved").utf8)
            StubProtocol.routes["GET /api/reconcile/summary"] = Data(#"{"rows":[{"accountId":4100,"pendingCount":2}]}"#.utf8)
            StubProtocol.routes["GET /api/reconcile/suggestions"] = Data(Self.snapshot([Self.bank("bk1"), Self.bank("bk2")]).utf8)
            let revision = session.revision
            await model.send("i1", session: session)
            let sends = StubProtocol.sent.filter { $0.method == "POST" && $0.path == "/api/import/staged/i1/approve" }
            #expect(sends.count == 1)
            let body = try JSONSerialization.jsonObject(with: sends.first?.body ?? Data()) as? [String: Any]
            #expect(body?["rowIds"] == nil, "the whole import in one call")
            #expect(session.revision == revision + 1, "badges and Home reload")
            #expect(model.pendingImports.isEmpty)
            #expect(Set(model.queue.rows.map(\.id)) == ["bk1", "bk2"])
            await model.approve(session)
            await model.approve(session)
            #expect(Set(booked) == ["/api/bank-transactions/bk1/approve", "/api/bank-transactions/bk2/approve"])
        }

        /// Rows the server refused stay pending, and the banner says why.
        @Test func sendKeepsTheImportAndShowsRowErrors() async {
            let session = session([
                "GET /api/import/staged": Self.batches,
                "GET /api/import/staged/i1": Self.detail("pending"),
                "GET /api/reconcile/summary": #"{"rows":[]}"#,
                "POST /api/import/staged/i1/approve": #"{"approved":0,"rowErrors":[{"rowIndex":0,"message":"Row 1: unknown account"}]}"#
            ])
            let model = ReviewModel()
            await model.load(session)
            await model.send("i1", session: session)
            #expect(model.pendingImports.map(\.errors) == [["Row 1: unknown account"]])
            await model.load(session)
            #expect(model.pendingImports.first?.errors == ["Row 1: unknown account"], "kept across reloads")
        }

        /// The rule fails after the server booked the row: the row is done and can't be booked a second time.
        @Test func ruleFailureAfterBookingStillFinishesTheRow() async {
            let session = session([
                "GET /api/import/staged": "[]",
                "GET /api/reconcile/summary": #"{"rows":[{"accountId":4100,"pendingCount":1}]}"#,
                "GET /api/reconcile/suggestions": Self.snapshot([Self.bank("bk1")])
            ], statuses: [200, 200, 200, 200, 500])
            let model = ReviewModel()
            await model.load(session)
            model.createsRule = true
            await model.approve(session)
            #expect(model.queue.outcome(of: "bk1") == .approved)
            #expect(model.error?.contains("rule wasn't saved") == true)
            await model.approve(session)
            #expect(booked == ["/api/bank-transactions/bk1/approve"], "booked once")
        }

        /// A failed booking lists the queue again from the server, which says whether the row was booked.
        @Test func failedApproveReloadsTheQueue() async {
            let session = session([
                "GET /api/import/staged": "[]",
                "GET /api/reconcile/summary": #"{"rows":[{"accountId":4100,"pendingCount":1}]}"#,
                "GET /api/reconcile/suggestions": Self.snapshot([Self.bank("bk1")])
            ], statuses: [200, 200, 200, 500])
            let model = ReviewModel()
            await model.load(session)
            await model.approve(session)
            let summaries = StubProtocol.sent.filter { $0.path == "/api/reconcile/summary" }
            #expect(summaries.count == 2, "loaded, then reloaded after the failure")
            #expect(model.error != nil, "the reload after a failure keeps its message")
            await model.reload(session)
            #expect(model.error == nil, "Reload clears it")
        }

        /// Add as new leaves out a bank row that a transaction is already linked to.
        @Test func addAsNewSkipsLinkedBankRows() async {
            let session = session([
                "GET /api/import/staged": "[]",
                "GET /api/reconcile/suggestions": Self.snapshot([Self.bank("b1"), Self.bank("b3")], linked: ["b3"])
            ])
            let model = ReconcileModel()
            model.accountId = 4100
            await model.load(session, today: Fixtures.today)
            model.bankSelection = ["b1", "b3"]
            #expect(model.selectedUnlinked.map(\.id) == ["b1"])
            await model.addAsNew(session, categoryId: nil, today: Fixtures.today)
            #expect(booked == ["/api/bank-transactions/b1/approve"])
        }
    }
}
