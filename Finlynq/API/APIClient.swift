import Foundation

enum APIError: LocalizedError {
    /// `code` is the server's machine-readable reason, such as "mfa-required", when it sends one.
    case server(status: Int, message: String, code: String? = nil)
    case locked
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .server(_, let message, _): message
        case .locked: "Your session is locked. Sign in again."
        case .network(let message): "Can't reach the server. \(message)"
        case .decoding(let message): "The server sent data this app doesn't understand. \(message)"
        }
    }
}

/// Talks to a Finlynq server's REST routes. The server returns bare JSON and
/// authenticates with the httpOnly `pf_session` cookie, which URLSession keeps for us.
final class APIClient {
    var baseURL: URL
    /// Called on 401/423. Signs in again and returns true if the request should be retried.
    var reauthenticate: (() async -> Bool)?

    private let session: URLSession
    let decoder = JSONDecoder()

    /// `session` is injectable so tests can stub the network.
    init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.httpCookieStorage = .shared
            config.httpShouldSetCookies = true
            config.timeoutIntervalForRequest = 30
            self.session = URLSession(configuration: config)
        }
    }

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        try await decode(send("GET", path, query: query))
    }

    @discardableResult
    func send<B: Encodable>(_ method: String, _ path: String, body: B) async throws -> Data {
        // `query:` forces the Data overload; without it Data (an Encodable) matches this generic again and recurses.
        try await send(method, path, query: [:], body: try JSONEncoder().encode(body))
    }

    @discardableResult
    func send(
        _ method: String,
        _ path: String,
        query: [String: String?] = [:],
        body: Data? = nil,
        contentType: String = "application/json",
        retry: Bool = true
    ) async throws -> Data {
        if Fixtures.isEnabled { return try Fixtures.respond(method: method, path: path) }
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        // Sorted so the same query always gives the same URL.
        let items = query.sorted { $0.key < $1.key }.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        if !items.isEmpty { components.queryItems = items }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Sending the session as a Bearer token skips the server's CSRF check, which rejects
        // cookie-only writes that carry no Origin header (URLSession never sends one).
        if let token = sessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401 || status == 423, retry, let reauthenticate, await reauthenticate() {
            return try await send(method, path, query: query, body: body, contentType: contentType, retry: false)
        }
        if status == 423 { throw APIError.locked }
        guard (200..<300).contains(status) else {
            let reply = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw APIError.server(status: status, message: reply?.error ?? "HTTP \(status)", code: reply?.code)
        }
        return data
    }

    func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: HTMLEntities.decode(json: data))
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Same as `get`, for the few routes that wrap their payload in `{ success, data }`.
    func getEnveloped<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        let envelope: Envelope<T> = try await get(path, query: query)
        guard let data = envelope.data else { throw APIError.server(status: 200, message: envelope.error ?? "Empty response") }
        return data
    }

    var sessionToken: String? {
        HTTPCookieStorage.shared.cookies(for: baseURL)?.first { $0.name == "pf_session" }?.value
    }

    func clearCookies() {
        for cookie in HTTPCookieStorage.shared.cookies(for: baseURL) ?? [] {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }
}

private struct ErrorBody: Decodable { let error: String?; let code: String? }
private struct Envelope<T: Decodable>: Decodable { let data: T?; let error: String? }

/// The server HTML-escapes user text, so a payee arrives as "AJ &amp; ASHLEY&#39;S". Entities can only sit inside
/// JSON strings, so `decode(json:)` replaces them in the raw body before any model sees it, and every
/// decoded string (payees, notes, names) comes out plain. Each entity is decoded once: "&amp;amp;" becomes "&amp;".
nonisolated enum HTMLEntities {
    static func decode(json data: Data) -> Data {
        guard data.contains(UInt8(ascii: "&")), let text = String(data: data, encoding: .utf8) else { return data }
        let entity = /&(amp|lt|gt|quot|apos|#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6});/
        let decoded = text.replacing(entity) { match -> String in
            let name = match.1
            let hex = name.hasPrefix("#x") || name.hasPrefix("#X")
            let named: [Substring: Unicode.Scalar] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'"]
            let scalar = named[name] ?? UInt32(name.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10).flatMap(Unicode.Scalar.init)
            guard let scalar else { return String(match.0) }
            // Quotes, backslashes and control characters must stay escaped inside a JSON string.
            if scalar == "\"" || scalar == "\\" || scalar.value < 0x20 { return String(format: "\\u%04X", scalar.value) }
            return String(scalar)
        }
        return Data(decoded.utf8)
    }
}
