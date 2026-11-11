import Foundation
import Testing
@testable import Finlynq

/// Request shapes for the review queue, the bank ledger and statement upload. Nested in `APIClientTests` so it
/// shares that suite's serialized run (the URLProtocol stub is global). Nothing here reaches a real server.
extension APIClientTests {
    struct ReviewEndpointsTests {
        private func client(_ routes: [String: String] = [:]) -> APIClient {
            StubProtocol.statuses = []
            StubProtocol.requests = 0
            StubProtocol.sent = []
            StubProtocol.routes = routes.reduce(into: [:]) { result, route in
                result[route.key] = route.value.hasPrefix("fixture:")
                    ? Fixtures.data(for: String(route.value.dropFirst(8))) : Data(route.value.utf8)
            }
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [StubProtocol.self]
            return APIClient(baseURL: URL(string: "https://example.test")!, session: URLSession(configuration: config))
        }

        private func expect(
            _ sent: StubProtocol.Sent?, _ method: String, _ url: String, sourceLocation: SourceLocation = #_sourceLocation
        ) {
            #expect(sent?.method == method, sourceLocation: sourceLocation)
            #expect(sent?.url == "https://example.test" + url, sourceLocation: sourceLocation)
        }

        private func text(_ sent: StubProtocol.Sent?) -> String {
            sent?.body.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        }

        private func json(_ sent: StubProtocol.Sent?) -> [String: Any] {
            (sent?.body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        }

        @Test func uploadStatementSendsTheEndingBalance() async throws {
            let api = client(["POST /api/import/staging/upload": #"{"stagedImportId":"b9","counts":{"new":4,"skippedDuplicate":2}}"#])
            let file = UploadFile(filename: "chequing.csv", data: Data("Date,Description,Amount\n".utf8))
            let result = try await api.uploadStatement(file: file, accountId: 4100, statementBalance: 9058.05)
            let text = text(StubProtocol.sent.first)
            #expect(text.contains("name=\"statementBalance\"\r\n\r\n9058.05"))
            #expect(text.contains("name=\"confirmedMapping\"\r\n\r\n1"))
            #expect(result.counts?.new == 4)
            #expect(result.counts?.skippedDuplicate == 2)
        }

        @Test func importMapCSVSendsTheColumnsAndAccount() async throws {
            let api = client(["POST /api/import/csv-map": #"{"type":"csv-mapped","valid":[],"duplicates":[]}"#])
            let file = UploadFile(filename: "chequing.csv", data: Data("Date,Description,Amount\n".utf8))
            let mapping = ColumnMapping(date: "Date", amount: "Amount", payee: "Description")
            let preview = try await api.importMapCSV(file: file, mapping: mapping, defaultAccount: "Chequing")
            expect(StubProtocol.sent.first, "POST", "/api/import/csv-map")
            let text = text(StubProtocol.sent.first)
            #expect(text.contains("name=\"defaultAccount\"\r\n\r\nChequing"))
            #expect(text.contains(#""date":"Date""#) && text.contains(#""payee":"Description""#))
            #expect(preview.type == "csv-mapped")
        }

        // MARK: Bank ledger

        /// Bank rows for account 4100: b1 is waiting with a suggested category, b2 may copy transaction 291947,
        /// b3 is already linked.
        private static let snapshot = #"""
        {"success":true,"data":{"linked":[{"transactionId":5,"bankTransactionId":"b3"}],"suggestions":[],
        "transactions":{"291947":{"id":291947,"date":"2026-11-04","amount":-38.26,"currency":"USD","payee":"Pai Northern"}},
        "bankTransactions":{
        "b1":{"id":"b1","date":"2026-11-08","amount":-27.99,"currency":"USD","payee":"AMZN Mktp CA","accountId":4100,
              "suggestedCategoryId":8492,"duplicateOfTransactionId":null},
        "b2":{"id":"b2","date":"2026-11-04","amount":-38.26,"currency":"USD","payee":"PAI NORTHERN","accountId":4100,
              "suggestedCategoryId":null,"duplicateOfTransactionId":291947},
        "b3":{"id":"b3","date":"2026-11-01","amount":3200,"currency":"USD","payee":"Acme","accountId":4100,
              "suggestedCategoryId":8481,"duplicateOfTransactionId":null}}}}
        """#

        @Test func reviewQueueAddsUnlinkedBankRows() async throws {
            let list = try #require(Fixtures.data(for: "/api/import/staged"))
            let batch = try #require((try JSONSerialization.jsonObject(with: list) as? [[String: Any]])?.first?["id"] as? String)
            let api = client([
                "GET /api/import/staged": "fixture:/api/import/staged",
                "GET /api/import/staged/\(batch)": "fixture:/api/import/staged/\(batch)",
                "GET /api/reconcile/summary": #"{"rows":[{"accountId":4100,"pendingCount":2},{"accountId":4101,"pendingCount":0}]}"#,
                "GET /api/reconcile/suggestions": Self.snapshot
            ])
            let rows = try await api.reviewQueue()
            let snapshots = StubProtocol.sent.filter { $0.path == "/api/reconcile/suggestions" }
            #expect(snapshots.map(\.url) == ["https://example.test/api/reconcile/suggestions?accountId=4100"])
            let staged = rows.filter { $0.bankId == nil }
            #expect(!staged.isEmpty)
            #expect(staged.allSatisfy { $0.isPending && $0.importId == batch && $0.accountId != nil && $0.importedAt != nil })
            let bank = rows.filter { $0.bankId != nil }
            #expect(Set(bank.map(\.id)) == ["b1", "b2"])
            let first = try #require(bank.first { $0.id == "b1" })
            #expect(first.categoryId == 8492)
            #expect(first.accountId == 4100)
            let copy = try #require(bank.first { $0.id == "b2" }?.match)
            #expect(copy == ReviewMatch(transactionId: 291947, payee: "Pai Northern", amount: -38.26, date: "2026-11-04"))
        }

        @Test func approvingABankRowBooksIt() async throws {
            let api = client(["POST /api/bank-transactions/b1/approve": #"{"success":true,"data":{"transactionId":77}}"#])
            let row = StagedRow(id: "b1", date: "2026-11-08", amount: -27.99, accountId: 4100, bankId: "b1")
            let id = try await api.approveReviewRow(row, categoryId: 8492)
            #expect(StubProtocol.sent.count == 1)
            expect(StubProtocol.sent.first, "POST", "/api/bank-transactions/b1/approve")
            #expect(json(StubProtocol.sent.first)["categoryId"] as? Int == 8492)
            #expect(id == 77)
        }

        /// A staged row has no bank row to book yet; booking by date and amount could pick the wrong one.
        @Test func approvingOrLinkingAStagedRowIsRefused() async throws {
            let api = client()
            let row = StagedRow(id: "r1", importId: "i1", date: "2026-11-08", amount: -27.99, match: ReviewMatch(transactionId: 55))
            await #expect(throws: APIError.self) { try await api.approveReviewRow(row, categoryId: 8492) }
            await #expect(throws: APIError.self) { try await api.linkReviewRow(row) }
            #expect(StubProtocol.sent.isEmpty)
        }

        /// Rows the server couldn't send come back in `rowErrors`.
        @Test func approveStagedReadsRowErrors() async throws {
            let api = client([
                "POST /api/import/staged/i1/approve":
                    #"{"success":true,"approved":1,"rowErrors":[{"rowIndex":1,"message":"Row 2: unknown account \"Chq\""}]}"#
            ])
            let result = try await api.approveStaged(importId: "i1")
            #expect(json(StubProtocol.sent.first).isEmpty, "no rowIds: the whole import")
            #expect(result.rowErrors == [ApproveResult.RowError(rowIndex: 1, message: #"Row 2: unknown account "Chq""#)])
        }

        @Test func reviewQueueSkipsAnAccountThatFails() async throws {
            let api = client([
                "GET /api/import/staged": "[]",
                "GET /api/reconcile/summary": #"{"rows":[{"accountId":4100,"pendingCount":2},{"accountId":4101,"pendingCount":2}]}"#,
                "GET /api/reconcile/suggestions": Self.snapshot
            ])
            StubProtocol.statuses = [200, 200, 500, 200]
            let rows = try await api.reviewQueue()
            #expect(StubProtocol.sent.count == 4)
            #expect(Set(rows.map(\.id)) == ["b1", "b2"], "the second account's rows still arrive")
        }

        @Test func linkingABankRow() async throws {
            let api = client()
            let row = StagedRow(id: "b2", date: "2026-11-04", amount: -38.26, bankId: "b2", match: ReviewMatch(transactionId: 291947))
            try await api.linkReviewRow(row)
            expect(StubProtocol.sent.first, "POST", "/api/reconcile/links")
            #expect(json(StubProtocol.sent.first)["transactionId"] as? Int == 291947)
            #expect(json(StubProtocol.sent.first)["bankTransactionId"] as? String == "b2")
        }

        @Test func removingRows() async throws {
            let api = client()
            await #expect(throws: APIError.self) {
                try await api.removeReviewRow(StagedRow(id: "r1", importId: "i1", date: "2026-11-08", amount: -1))
            }
            try await api.removeReviewRow(StagedRow(id: "b1", date: "2026-11-08", amount: -1, bankId: "b1"))
            #expect(StubProtocol.sent.count == 1)
            expect(StubProtocol.sent.first, "DELETE", "/api/bank-transactions/b1")
        }

        @Test func linkBankRowsInBulk() async throws {
            let api = client()
            try await api.linkBankRows(bankIds: ["b1", "b2"], transactionIds: [9])
            expect(StubProtocol.sent.first, "POST", "/api/reconcile/links/bulk")
            #expect(json(StubProtocol.sent.first)["bankTransactionIds"] as? [String] == ["b1", "b2"])
            #expect(json(StubProtocol.sent.first)["transactionIds"] as? [Int] == [9])
        }

        @Test func reconcileSnapshotAndBalance() async throws {
            let api = client([
                "GET /api/reconcile/suggestions": Self.snapshot,
                "GET /api/reconcile/balance-summary": #"""
                {"success":true,"data":{"accountId":4100,"currency":"USD","latestAnchor":{"date":"2026-11-08","balance":9200.85},
                "bankSideLatest":9200.85,"systemSideLatest":9200.85,"delta":0,"status":"balanced"}}
                """#
            ])
            let snapshot = try await api.reconcileSnapshot(accountId: 4100, dateMin: "2026-10-10")
            let balance = try await api.balanceSummary(accountId: 4100)
            expect(StubProtocol.sent.first, "GET", "/api/reconcile/suggestions?accountId=4100&dateMin=2026-10-10")
            expect(StubProtocol.sent.last, "GET", "/api/reconcile/balance-summary?accountId=4100")
            #expect(snapshot.unlinked.count == 2)
            #expect(balance.latestAnchor?.balance == 9200.85)
        }
    }
}
