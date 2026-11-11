import Foundation
import Testing
@testable import Finlynq

/// The settings, sign-in and first-run calls. Nested in `APIClientTests` so it shares that suite's serialized run.
extension APIClientTests {
    struct SettingsEndpointsTests {
        private func client(statuses: [Int] = [], routes: [String: String] = [:]) -> APIClient {
            StubProtocol.statuses = statuses
            StubProtocol.requests = 0
            StubProtocol.sent = []
            StubProtocol.routes = routes.mapValues { Data($0.utf8) }
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [StubProtocol.self]
            return APIClient(baseURL: URL(string: "https://example.test")!, session: URLSession(configuration: config))
        }

        private var sent: StubProtocol.Sent? { StubProtocol.sent.first }

        private var body: [String: Any] {
            (sent?.body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        }

        @Test func deleteAccountDoesNotSignInAgainOnAWrongPassword() async throws {
            let api = client(statuses: [401])
            var relogins = 0
            api.reauthenticate = { relogins += 1; return true }
            await #expect(throws: APIError.self) { try await api.deleteAccount(password: "wrong", mfaCode: "123456") }
            #expect(relogins == 0)
            #expect(StubProtocol.requests == 1)
            #expect(body["mfaCode"] as? String == "123456")
        }

        @Test func updateRuleSendsTheIdWithTheRule() async throws {
            let api = client()
            let cafe = RuleCondition(field: "payee", op: "contains", value: .text("Cafe"))
            let input = RuleInput(name: "Coffee", conditions: .init(all: [cafe]),
                                  actions: [RuleAction(kind: "set_category", categoryId: 7)], priority: 10, isActive: true, id: 42)
            try await api.updateRule(input)
            #expect(sent?.method == "PUT")
            #expect(sent?.url == "https://example.test/api/rules")
            #expect(body["id"] as? Int == 42)
            #expect(body["name"] as? String == "Coffee")
            #expect((body["conditions"] as? [String: Any])?["all"] != nil)
        }

        @Test func setRuleActiveAndDelete() async throws {
            let api = client()
            try await api.setRuleActive(id: 5, isActive: false)
            #expect(body as NSDictionary == ["id": 5, "isActive": false])
            try await api.deleteRule(id: 5)
            #expect(StubProtocol.sent.last?.method == "DELETE")
            #expect(StubProtocol.sent.last?.url == "https://example.test/api/rules?id=5")
        }

        @Test func registerWithoutEmailAcknowledgesNoRecovery() async throws {
            let api = client()
            try await api.register(username: "sam", email: nil, password: "pw")
            #expect(sent?.url == "https://example.test/api/auth/register")
            #expect(body["acknowledgeNoRecovery"] as? Bool == true)
            #expect(body["email"] == nil)

            try await api.register(username: "sam", email: "sam@example.com", password: "pw")
            let second = StubProtocol.sent.last?.body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            #expect(second?["acknowledgeNoRecovery"] == nil)
            #expect(second?["email"] as? String == "sam@example.com")
        }

        @Test func seedBudgetAndOnboarding() async throws {
            let api = client()
            try await api.seedBudget(categoryName: "Groceries", amount: 600, month: "2026-11")
            #expect(sent?.url == "https://example.test/api/budgets/seed")
            #expect(body as NSDictionary == ["categoryName": "Groceries", "amount": 600, "month": "2026-11"])
            try await api.loadSampleData()
            try await api.completeOnboarding()
            #expect(StubProtocol.sent.map(\.url).suffix(2) == [
                "https://example.test/api/onboarding/sample-data", "https://example.test/api/onboarding/complete"
            ])
        }

        @Test func deleteAccountCarriesTheServerErrorCode() async throws {
            let api = client(statuses: [401], routes: [
                "POST /api/auth/delete-account": #"{"error":"MFA verification is required.","code":"mfa-required"}"#
            ])
            do {
                try await api.deleteAccount(password: "pw")
                Issue.record("expected an error")
            } catch APIError.server(let status, _, let code) {
                #expect(status == 401)
                #expect(code == "mfa-required")
            }
        }

        @Test func activeCurrenciesSaveTheWholeList() async throws {
            let api = client(routes: ["PUT /api/settings/active-currencies": #"{"active":["USD","CAD"]}"#])
            let saved = try await api.setActiveCurrencies(["USD", "CAD"])
            #expect(sent?.method == "PUT")
            #expect(body as NSDictionary == ["active": ["USD", "CAD"]])
            #expect(saved == ["USD", "CAD"])
        }

        @Test func fxRateView() async throws {
            let api = client(routes: ["GET /api/settings/fx-rate-view": #"{"success":true,"data":{"inverted":true}}"#])
            #expect(try await api.fxRatesInverted())
            try await api.setFxRatesInverted(false)
            let put = StubProtocol.sent.last
            #expect(put?.method == "PUT")
            #expect(put?.url == "https://example.test/api/settings/fx-rate-view")
            #expect((put?.body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? NSDictionary) == ["inverted": false])
        }

        // MARK: Sign-in safety

        @Test func reloginSendsThePasswordOnlyToItsOwnServer() async throws {
            let realOff = Keychain.isOff
            defer { Keychain.isOff = realOff }
            Keychain.isOff = { true }
            let api = client(routes: ["POST /api/auth/login": #"{"success":true}"#, "GET /api/auth/session": #"{"authenticated":true}"#])
            let session = Session(api: api)
            #expect(await session.signIn(server: "https://a.test", username: "sam", password: "pw") == nil)
            #expect(session.state == .signedIn)

            api.baseURL = URL(string: "https://b.test")!
            StubProtocol.sent = []
            StubProtocol.statuses = [401]
            _ = try? await api.send("GET", "/api/dashboard")
            let logins = StubProtocol.sent.filter { $0.path == "/api/auth/login" }
            #expect(logins.count == 1)
            #expect(logins.allSatisfy { $0.url.hasPrefix("https://a.test/") }, "never b.test")
        }

        @Test func noReloginFromTheSignInForm() async throws {
            let realOff = Keychain.isOff
            defer { Keychain.isOff = realOff }
            Keychain.isOff = { true }
            let api = client(routes: ["POST /api/auth/login": #"{"mfaRequired":true,"mfaPendingToken":"token"}"#])
            let session = Session(api: api)
            #expect(await session.signIn(server: "https://a.test", username: "sam", password: "pw") == nil)
            #expect(session.state == .needsCode)

            StubProtocol.sent = []
            StubProtocol.statuses = [401]
            _ = try? await api.send("GET", "/api/dashboard")
            #expect(StubProtocol.sent.filter { $0.path == "/api/auth/login" }.isEmpty)
            #expect(await session.signInAgain() == false)
        }

        @Test func sendFeedback() async throws {
            let api = client()
            try await api.sendFeedback(type: "bug", message: "Crash", appVersion: "1.0")
            #expect(sent?.url == "https://example.test/api/feedback")
            #expect(body as NSDictionary == ["type": "bug", "message": "Crash", "appVersion": "1.0"])
        }
        // MARK: Categories

        @Test func createCategorySendsTheTypeCode() async throws {
            let api = client()
            try await api.createCategory(CategoryInput(name: "Pets", type: "E", group: "Home", note: ""))
            #expect(sent?.method == "POST")
            #expect(sent?.url == "https://example.test/api/categories")
            #expect(body as NSDictionary == ["name": "Pets", "type": "E", "group": "Home", "note": ""])
        }

        @Test func updateCategorySendsTheId() async throws {
            let api = client()
            try await api.updateCategory(CategoryInput(id: 8486, name: "Food", type: "I", group: "Daily", note: "Weekly shop"))
            #expect(sent?.method == "PUT")
            #expect(sent?.url == "https://example.test/api/categories")
            #expect(body as NSDictionary == ["id": 8486, "name": "Food", "type": "I", "group": "Daily", "note": "Weekly shop"])
        }

        @Test func deleteCategory() async throws {
            let api = client()
            try await api.deleteCategory(id: 8486)
            #expect(sent?.method == "DELETE")
            #expect(sent?.url == "https://example.test/api/categories?id=8486")
        }

        @Test func categoryConflictShowsTheServerMessageAsIs() async throws {
            let blocked = "This category is still used by 12 transactions, so it cannot be deleted. "
                + "Move those records to a different category first."
            let api = client(statuses: [409, 409], routes: [
                "DELETE /api/categories": #"{"error":"\#(blocked)"}"#,
                "POST /api/categories": #"{"error":"You already have a category with that name. Pick a different name."}"#
            ])
            do {
                try await api.deleteCategory(id: 8486)
                Issue.record("expected a conflict")
            } catch {
                #expect(CategoryDraft.message(for: error, doing: "delete the category") == blocked)
            }
            do {
                try await api.createCategory(CategoryInput(name: "Food", type: "E", group: "", note: ""))
                Issue.record("expected a conflict")
            } catch {
                #expect(CategoryDraft.message(for: error, doing: "save the category")
                        == "You already have a category with that name. Pick a different name.")
            }
            #expect(CategoryDraft.message(for: APIError.network("Offline."), doing: "save the category")
                    == "Couldn't save the category. Can't reach the server. Offline.")
        }
        @Test func renameOntoATakenNameShowsTheServerMessage() async throws {
            let taken = "You already have a category with that name. Pick a different name."
            let api = client(statuses: [409], routes: ["PUT /api/categories": #"{"error":"\#(taken)"}"#])
            do {
                try await api.updateCategory(CategoryInput(id: 8486, name: "Dining", type: "E", group: "Food", note: ""))
                Issue.record("expected a conflict")
            } catch {
                #expect(CategoryDraft.message(for: error, doing: "save the category") == taken)
            }
        }

        @Test func theDemoNeverWritesCategories() async throws {
            let realOff = Keychain.isOff
            defer { Keychain.isOff = realOff }
            Keychain.isOff = { true }
            let api = client(routes: [
                "POST /api/auth/login": #"{"success":true}"#,
                "GET /api/auth/session": #"{"authenticated":true,"username":"demo"}"#
            ])
            let session = Session(api: api)
            #expect(await session.tryDemo() == nil)
            #expect(session.isDemo)
            StubProtocol.sent = []
            var draft = CategoryDraft(groups: ["Food"])
            draft.name = "Pets"
            try await session.save(draft)
            try await session.deleteCategory(id: 8486)
            #expect(StubProtocol.sent.filter { $0.path == "/api/categories" }.isEmpty)
        }
    }
}
