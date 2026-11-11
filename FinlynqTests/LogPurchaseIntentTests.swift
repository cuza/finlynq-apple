import AppIntents
import Foundation
import Testing
@testable import Finlynq

// swiftlint:disable static_over_final_class
/// Fails every request as if the device were offline.
nonisolated final class OfflineProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
}

/// A server that saves `POST /api/transactions` but whose reply never arrives. Once it holds the row,
/// `GET /api/transactions` returns it.
nonisolated final class LostReplyProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var creates = 0
    /// Answers the session route with the server's encryption key locked.
    nonisolated(unsafe) static var keyLocked = false
    nonisolated(unsafe) static var lookups = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let route = "\(request.httpMethod ?? "GET") \(url.path)"
        if route == "POST /api/transactions" {
            Self.creates += 1
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        if route == "GET /api/transactions" { Self.lookups += 1 }
        let body: Data? = switch route {
        case "GET /api/accounts": Fixtures.data(for: "/api/accounts")
        case "POST /api/transactions/suggest": Data(#"{"suggestion":{"id":8487}}"#.utf8)
        case "GET /api/auth/session": Data(#"{"authenticated":true,"encryptionLocked":\#(Self.keyLocked)}"#.utf8)
        case "GET /api/transactions" where Self.creates > 0: Fixtures.data(for: "/api/transactions")
        case "GET /api/transactions": Data(#"{"data":[],"total":0}"#.utf8)
        default: Data("{}".utf8)
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
}

// swiftlint:enable static_over_final_class

/// Apple Pay captures against a stubbed server. Nested in `APIClientTests` so it shares that suite's serialized
/// run (the URLProtocol stub and `ApplePayCapture`'s session and store are global). Each test puts the globals back.
extension APIClientTests {
    struct LogPurchaseIntentTests {
        private static let suggestion = #"{"suggestion":{"id":8487,"type":"E","group":"Food","name":"Dining"}}"#
        private static let defaultRoutes = ["POST /api/transactions/suggest": suggestion, "POST /api/transactions": #"{"id":901}"#]

        private static func restore() {
            ApplePayCapture.store = .shared
            ApplePayCapture.session = ApplePayCapture.signIn
            ApplePayCapture.live = nil
        }

        private func client(_ protocolClass: AnyClass) -> APIClient {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [protocolClass]
            return APIClient(baseURL: URL(string: "https://example.test")!, session: URLSession(configuration: config))
        }

        /// Points `ApplePayCapture` at a fresh in-memory store and a session on a stubbed network.
        private func setUp(
            routes: [String: String] = defaultRoutes, protocolClass: AnyClass = StubProtocol.self, mappings: [String: Int] = [:]
        ) -> PendingCaptures {
            StubProtocol.statuses = []
            StubProtocol.requests = 0
            StubProtocol.sent = []
            StubProtocol.routes = routes.mapValues { Data($0.utf8) }
            StubProtocol.routes["GET /api/accounts"] = Fixtures.data(for: "/api/accounts")
            let api = client(protocolClass)
            let store = PendingCaptures(url: nil, mappings: mappings)
            ApplePayCapture.store = store
            ApplePayCapture.session = {
                let session = Session(api: api)
                await session.refreshLookups()
                return session
            }
            return store
        }

        private var creates: [StubProtocol.Sent] { StubProtocol.sent.filter { $0.method == "POST" && $0.path == "/api/transactions" } }

        private var created: [String: Any]? {
            creates.first?.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }

        private func waiting(_ card: String = "Visa", problem: CapturedPurchase.Problem? = nil) -> CapturedPurchase {
            CapturedPurchase(
                merchant: "Pai", amount: 5, currency: "USD", card: card, date: "2026-11-09", capturedAt: .now, problem: problem
            )
        }

        @Test func intentCreatesTheTransaction() async throws {
            defer { Self.restore() }
            let store = setUp()
            var intent = LogPurchaseIntent()
            intent.merchant = "Pai Northern"
            intent.amount = IntentCurrencyAmount(amount: Decimal(string: "38.26")!, currencyCode: "USD")
            intent.card = "Visa Rewards ••1234"
            _ = try await intent.perform()

            let body = try #require(created)
            #expect(body["accountId"] as? Int == 4103, "matched by the account name Visa Rewards")
            #expect(body["categoryId"] as? Int == 8487, "the suggested category")
            #expect(body["enteredAmount"] as? Double == -38.26, "an expense is negative")
            #expect(body["enteredCurrency"] as? String == "USD")
            #expect(body["payee"] as? String == "Pai Northern")
            #expect(body["note"] as? String == "Apple Pay")
            #expect((body["tags"] as? String)?.hasPrefix("applepay:") == true)
            #expect(store.items.isEmpty)
            #expect(store.last?.merchant == "Pai Northern")
            #expect(store.mappings.isEmpty, "a name guess is used once, not saved")
        }

        @Test func lastFourMatchIsSavedForTheCard() async {
            defer { Self.restore() }
            let store = setUp(mappings: ["Interac ••1234": 4100])
            _ = await ApplePayCapture.capture(merchant: "Pai", amount: 5, currency: "USD", card: "Debit ••1234")
            #expect(created?["accountId"] as? Int == 4100)
            #expect(store.mappings["Debit ••1234"] == 4100)
        }

        @Test func intentFallsBackToThePlainAmount() async throws {
            defer { Self.restore() }
            _ = setUp()
            var intent = LogPurchaseIntent()
            intent.merchant = "Pai Northern"
            intent.number = 12.5
            intent.currencyCode = "CAD"
            intent.card = "Visa Rewards"
            _ = try await intent.perform()
            let body = try #require(created)
            #expect(body["enteredAmount"] as? Double == -12.5)
            #expect(body["enteredCurrency"] as? String == "CAD")
        }

        @Test func dialogNamesTheAmountAndMerchant() async {
            defer { Self.restore() }
            _ = setUp()
            let message = await ApplePayCapture.capture(merchant: "Pai Northern", amount: 38.26, currency: "USD", card: "Visa Rewards")
            // "$38.26" in the US; the formatter follows the device locale.
            #expect(message == "Added \(38.26.money("USD")) at Pai Northern")
        }

        @Test func purchaseIsSavedBeforeAnyNetworkCall() async {
            defer { Self.restore() }
            let store = setUp()
            var waitingWhenSessionAsked = -1
            ApplePayCapture.session = {
                waitingWhenSessionAsked = store.count
                return nil
            }
            _ = await ApplePayCapture.capture(merchant: "Pai", amount: 5, currency: "USD", card: "Visa Rewards")
            #expect(waitingWhenSessionAsked == 1)
            #expect(store.items.first?.problem == .notSent)
        }

        @Test func emptyMerchantFallsBackToCardName() async throws {
            defer { Self.restore() }
            _ = setUp()
            _ = await ApplePayCapture.capture(merchant: " ", amount: 12, currency: "USD", card: "Visa Rewards ••1234")
            #expect(try #require(created)["payee"] as? String == "Visa Rewards ••1234")
        }

        @Test func zeroAmountIsQueuedForReview() async {
            defer { Self.restore() }
            let store = setUp()
            _ = await ApplePayCapture.capture(merchant: "Pai Northern", amount: 0, currency: "USD", card: "Visa Rewards")
            #expect(created == nil, "never saved as a $0 expense")
            #expect(store.count == 1)
            #expect(store.items.first?.problem == .amount)
        }

        @Test func offlinePurchaseIsQueued() async {
            defer { Self.restore() }
            let store = setUp(protocolClass: OfflineProtocol.self, mappings: ["Visa ••1234": 4103])
            let message = await ApplePayCapture.capture(merchant: "Pai Northern", amount: 38.26, currency: "USD", card: "Visa ••1234")
            #expect(store.count == 1)
            #expect(store.items.first?.problem == .notSent)
            #expect(message.contains("next time you open"))
        }

        @Test func unknownCardWaitsForAnAccount() async {
            defer { Self.restore() }
            let store = setUp()
            _ = await ApplePayCapture.capture(merchant: "Pai Northern", amount: 9, currency: "USD", card: "Debit ••5678")
            #expect(created == nil)
            #expect(store.items.first?.problem == .account)
        }

        @Test func noSuggestedCategoryWaitsForOne() async {
            defer { Self.restore() }
            let store = setUp(routes: ["POST /api/transactions/suggest": #"{"suggestion":null}"#])
            _ = await ApplePayCapture.capture(merchant: "New Place", amount: 9, currency: "USD", card: "Visa Rewards")
            #expect(created == nil)
            #expect(store.items.first?.problem == .category)
        }

        @Test func serverRejectionIsShownAndNotRetried() async {
            defer { Self.restore() }
            let store = setUp(routes: [
                "POST /api/transactions/suggest": Self.suggestion, "POST /api/transactions": #"{"error":"Please pick a category"}"#
            ])
            // Accounts, categories and the suggestion answer 200, the create 400.
            StubProtocol.statuses = [200, 200, 200, 400]
            _ = await ApplePayCapture.capture(merchant: "Pai", amount: 5, currency: "USD", card: "Visa Rewards")
            #expect(store.items.first?.problem == .rejected("Please pick a category"))
            #expect(HomeModel.applePayItem(store.items)?.subtitle == "Pai: Not accepted: Please pick a category")
            let before = StubProtocol.sent.count
            await ApplePayCapture.flush()
            #expect(StubProtocol.sent.count == before, "a rejected purchase waits for the user")
        }

        @Test func serverErrorStaysNotSent() async {
            defer { Self.restore() }
            let store = setUp()
            StubProtocol.statuses = [200, 200, 200, 503]
            _ = await ApplePayCapture.capture(merchant: "Pai", amount: 5, currency: "USD", card: "Visa Rewards")
            #expect(store.items.first?.problem == .notSent)
        }

        @Test func timeoutAndRateLimitStayNotSent() async {
            defer { Self.restore() }
            for status in [408, 429] {
                let store = setUp()
                StubProtocol.statuses = [200, 200, 200, status]
                _ = await ApplePayCapture.capture(merchant: "Pai", amount: 5, currency: "USD", card: "Visa Rewards")
                #expect(store.items.first?.problem == .notSent, "HTTP \(status) is retried later")
            }
        }

        @Test func purchaseDeletedDuringTheSendIsNeitherPostedNorRestored() async {
            defer { Self.restore() }
            let store = setUp(mappings: ["Visa": 4103])
            let stubbed = ApplePayCapture.session
            ApplePayCapture.session = {
                // The user deletes it from the fix sheet while the send signs in.
                for item in store.items { store.remove(item) }
                return await stubbed()
            }
            _ = await ApplePayCapture.capture(merchant: "Pai", amount: 5, currency: "USD", card: "Visa")
            #expect(creates.isEmpty)
            #expect(store.items.isEmpty)
        }

        @Test func failedSendKeepsEditsMadeDuringIt() async {
            defer { Self.restore() }
            let store = setUp(mappings: ["Visa": 4103])
            StubProtocol.statuses = [200, 200, 200, 503]
            let stubbed = ApplePayCapture.session
            ApplePayCapture.session = {
                for item in store.items { store.update(item.id) { $0.merchant = "Pai Northern" } }
                return await stubbed()
            }
            _ = await ApplePayCapture.capture(merchant: "Pai", amount: 5, currency: "USD", card: "Visa")
            #expect(store.items.first?.merchant == "Pai Northern")
            #expect(store.items.first?.problem == .notSent)
            #expect(store.items.first?.attempted == true)
        }

        @Test func lockedKeyDefersTheTagLookup() async {
            defer {
                Self.restore()
                LostReplyProtocol.keyLocked = false
            }
            LostReplyProtocol.creates = 0
            LostReplyProtocol.lookups = 0
            let store = setUp(protocolClass: LostReplyProtocol.self, mappings: ["Visa": 4103])
            _ = await ApplePayCapture.capture(merchant: "Pai", amount: 5, currency: "USD", card: "Visa")
            LostReplyProtocol.keyLocked = true
            await ApplePayCapture.flush()
            #expect(LostReplyProtocol.lookups == 0, "tags read as null while the key is locked")
            #expect(LostReplyProtocol.creates == 1)
            #expect(store.items.first?.problem == .notSent)
            LostReplyProtocol.keyLocked = false
            await ApplePayCapture.flush()
            #expect(LostReplyProtocol.creates == 1)
            #expect(store.items.isEmpty)
        }

        @Test func flushSendsQueuedPurchasesOnceOnline() async {
            defer { Self.restore() }
            let store = setUp(protocolClass: OfflineProtocol.self, mappings: ["Visa ••1234": 4103])
            _ = await ApplePayCapture.capture(merchant: "Pai Northern", amount: 38.26, currency: "USD", card: "Visa ••1234")
            #expect(store.count == 1)
            let online = setUp(mappings: ["Visa ••1234": 4103])
            for item in store.items { online.put(item) }
            await ApplePayCapture.flush()
            #expect(online.items.isEmpty)
            #expect(created != nil)
        }

        @Test func concurrentFlushesPostOnce() async {
            defer { Self.restore() }
            let store = setUp(mappings: ["Visa": 4103])
            store.put(waiting(problem: .notSent))
            async let first: Void = ApplePayCapture.flush()
            async let second: Void = ApplePayCapture.flush()
            _ = await (first, second)
            #expect(creates.count == 1)
            #expect(store.items.isEmpty)
        }

        @Test func retryAfterALostReplyDoesNotCreateTwice() async {
            defer { Self.restore() }
            LostReplyProtocol.creates = 0
            let store = setUp(protocolClass: LostReplyProtocol.self, mappings: ["Visa": 4103])
            _ = await ApplePayCapture.capture(merchant: "Pai", amount: 5, currency: "USD", card: "Visa")
            #expect(LostReplyProtocol.creates == 1, "the server saved it")
            #expect(store.items.first?.attempted == true)
            #expect(store.items.first?.problem == .notSent, "the reply was lost")
            await ApplePayCapture.flush()
            #expect(LostReplyProtocol.creates == 1, "the retry found the tag and didn't post again")
            #expect(store.items.isEmpty)
        }

        @Test func liveSessionThatIsNotSignedInQueues() async {
            defer { Self.restore() }
            _ = setUp()
            let live = Session(api: client(StubProtocol.self))
            ApplePayCapture.live = live
            #expect(await ApplePayCapture.signIn() == nil, "a starting or locked live session never signs in a second one")
            #expect(StubProtocol.sent.isEmpty)
        }

        @Test func waitForUnlockNeverSignsInInTheBackground() async {
            defer {
                Self.restore()
                UserDefaults.standard.removeObject(forKey: ApplePayCapture.waitForUnlockKey)
            }
            UserDefaults.standard.set(true, forKey: ApplePayCapture.waitForUnlockKey)
            #expect(await ApplePayCapture.signIn() == nil)
        }

        @Test func signOutForgetsCapturesAndCards() async {
            let isOff = Keychain.isOff
            defer {
                Self.restore()
                Keychain.isOff = isOff
            }
            Keychain.isOff = { true }
            let store = setUp(mappings: ["Visa": 4103])
            store.put(waiting())
            await Session(api: client(StubProtocol.self)).signOut()
            #expect(store.items.isEmpty)
            #expect(store.mappings.isEmpty)
        }

        @Test func signOutWarningCountsWaitingPurchases() {
            defer { Self.restore() }
            let store = setUp()
            store.put(waiting())
            #expect(ApplePayCapture.signOutWarning == "1 waiting Apple Pay purchase will be removed from this device.")
            store.put(waiting("Amex"))
            #expect(ApplePayCapture.signOutWarning == "2 waiting Apple Pay purchases will be removed from this device.")
        }
    }
}

/// The queue file in the app container.
struct PendingCapturesTests {
    @Test func corruptQueueIsMovedAsideNotOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "captures-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "apple-pay-captures.json")
        try Data("not json".utf8).write(to: url)
        let store = PendingCaptures(url: url)
        #expect(store.items.isEmpty)
        store.mappings["Visa"] = 4103
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path())
        let aside = try #require(files.first { $0.contains(".corrupt-") })
        #expect(try String(contentsOf: folder.appending(path: aside), encoding: .utf8) == "not json")
    }

    @Test func queueSavedBeforeNewFieldsStillLoads() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "captures-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        // The first release's format: no `attempted`, no `last`.
        let old = #"{"items":[{"id":"5D1F0C2E-0000-4000-8000-000000000001","merchant":"Pai","amount":5,"card":"Visa","#
            + #""date":"2026-11-09","capturedAt":0,"problem":{"notSent":{}}}],"mappings":{"Visa":4103}}"#
        try Data(old.utf8).write(to: url)
        let store = PendingCaptures(url: url)
        #expect(store.count == 1)
        #expect(store.items.first?.attempted == false)
        #expect(store.mappings["Visa"] == 4103)
    }

    @Test func pendingCapturesSurviveARelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "captures-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PendingCaptures(url: url)
        store.put(CapturedPurchase(merchant: "Pai", amount: 5, currency: nil, card: "Visa", date: "2026-11-09", capturedAt: .now))
        store.mappings["Visa"] = 4103
        let reopened = PendingCaptures(url: url)
        #expect(reopened.count == 1)
        #expect(reopened.mappings["Visa"] == 4103)
    }
}
