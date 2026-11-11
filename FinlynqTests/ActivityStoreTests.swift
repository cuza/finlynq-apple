import Foundation
import Testing
@testable import Finlynq

// swiftlint:disable static_over_final_class
/// Answers /api/transactions by month: the October request is slow, the November one is instant.
nonisolated final class MonthDelayProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let october = url.query?.contains("startDate=2026-10") == true
        let body: String
        switch url.path {
        case "/api/transactions":
            let date = october ? "2026-10-05" : "2026-11-05"
            body = #"{"data":[{"id":\#(october ? 1 : 2),"date":"\#(date)","currency":"USD","amount":-5}],"total":"1"}"#
        case "/api/fx": body = #"{"displayCurrency":"USD","rates":{}}"#
        default: body = "[]"
        }
        let send = { [self] in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        if october { DispatchQueue.global().asyncAfter(deadline: .now() + 0.4, execute: send) } else { send() }
    }
}
// swiftlint:enable static_over_final_class

struct ActivityStoreTests {
    @Test func aSlowOlderLoadDoesNotOverwriteANewerOne() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MonthDelayProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://example.test")!, session: URLSession(configuration: config))
        let calendar = Calendar(identifier: .gregorian)
        let store = ActivityStore()
        store.month = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        async let first: Void = store.load(api: api, currency: "USD")
        try? await Task.sleep(for: .milliseconds(50))
        store.month = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        await store.load(api: api, currency: "USD")
        await first
        #expect(store.rows.map(\.id) == [2])
    }
}
