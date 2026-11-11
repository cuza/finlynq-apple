import Foundation
import Testing
@testable import Finlynq

// swiftlint:disable static_over_final_class
/// Replays queued status codes and records each request. Tests in this suite run serially, so shared static state is safe.
nonisolated final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Sent {
        let method: String
        let url: String
        let path: String
        let body: Data?
        let contentType: String?
    }

    nonisolated(unsafe) static var statuses: [Int] = []
    nonisolated(unsafe) static var requests = 0
    /// Response bodies keyed by "METHOD /path". Anything else gets `{"ready":true}`.
    nonisolated(unsafe) static var routes: [String: Data] = [:]
    nonisolated(unsafe) static var sent: [Sent] = []
    private static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let method = request.httpMethod ?? "GET"
        Self.lock.lock()
        let status = Self.statuses.isEmpty ? 200 : Self.statuses.removeFirst()
        Self.requests += 1
        Self.sent.append(Sent(
            method: method, url: url.absoluteString, path: url.path,
            body: request.httpBody ?? request.httpBodyStream.map(Self.read),
            contentType: request.value(forHTTPHeaderField: "Content-Type")
        ))
        let reply = Self.routes["\(method) \(url.path)"] ?? Data(#"{"ready":true}"#.utf8)
        Self.lock.unlock()
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

// swiftlint:enable static_over_final_class

@Suite(.serialized) struct APIClientTests {
    private struct Reply: Decodable { let ready: Bool }

    private func client(statuses: [Int]) -> APIClient {
        StubProtocol.statuses = statuses
        StubProtocol.requests = 0
        StubProtocol.routes = [:]
        StubProtocol.sent = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return APIClient(baseURL: URL(string: "https://example.test")!, session: URLSession(configuration: config))
    }

    @Test func retriesOnceAfterReauth() async throws {
        let api = client(statuses: [423, 200])
        var calls = 0
        api.reauthenticate = { calls += 1; return true }
        let reply: Reply = try await api.get("/api/x")
        #expect(reply.ready)
        #expect(calls == 1)
        #expect(StubProtocol.requests == 2)
    }

    @Test func stopsAfterSecondFailure() async {
        let api = client(statuses: [423, 423])
        var calls = 0
        api.reauthenticate = { calls += 1; return true }
        do {
            let _: Reply = try await api.get("/api/x")
            Issue.record("expected APIError.locked")
        } catch let error as APIError {
            if case .locked = error {} else { Issue.record("got \(error)") }
        } catch {
            Issue.record("got \(error)")
        }
        #expect(calls == 1)
        #expect(StubProtocol.requests == 2)
    }
}

struct HTMLEntitiesTests {
    private struct Row: Decodable { let payee: String; let note: String }

    @Test func decodesEntitiesInServerText() throws {
        let body = #"{"payee":"AJ &amp; ASHLEY&#39;S","note":"&quot;a&quot; &lt;b&gt; &#x1F600; &#92; &amp;amp; &bogus; &#xD800;"}"#
        let row = try JSONDecoder().decode(Row.self, from: HTMLEntities.decode(json: Data(body.utf8)))
        #expect(row.payee == "AJ & ASHLEY'S")
        #expect(row.note == #""a" <b> 😀 \ &amp; &bogus; &#xD800;"#)
    }
}
