import Foundation

/// Canned API responses for UI tests and offline runs. Set `FINLYNQ_FIXTURES=1` in the environment
/// and `APIClient.send` answers from the `Fixtures` folder in the app bundle instead of the network.
/// A path maps to a file name without the query: `/api/dashboard` is `dashboard.json`,
/// `/api/budgets/month` is `budgets-month.json`, `/api/auth/session` is `session.json`.
/// The top-level files are demo responses saved by `scripts/check-api.sh --save`. A file of the same name in
/// `Fixtures/overlays` is hand-made data that replaces the saved one, for screens the demo leaves empty;
/// `--save` never writes there.
nonisolated enum Fixtures {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["FINLYNQ_FIXTURES"] == "1" }

    /// "Today" for date logic such as the bills week: `FINLYNQ_TODAY` (YYYY-MM-DD) in fixture mode, 2026-11-09
    /// when it is unset, so screenshots don't change with the calendar. The wall clock otherwise.
    static var today: Date {
        guard isEnabled else { return Date() }
        return APIDate.parse(ProcessInfo.processInfo.environment["FINLYNQ_TODAY"] ?? "2026-11-09") ?? Date()
    }

    static func data(for path: String) -> Data? {
        var name = path.hasPrefix("/api/") ? String(path.dropFirst(5)) : path
        if name.hasPrefix("auth/") { name.removeFirst(5) }
        name = name.replacingOccurrences(of: "/", with: "-")
        let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/overlays")
            ?? Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        return url.flatMap { try? Data(contentsOf: $0) }
    }

    /// GET returns the fixture or a 404. Writes succeed with an empty object so save flows can run, except deleting a
    /// category: the fixture transactions use every category, so the server refuses it as it would.
    static func respond(method: String, path: String) throws -> Data {
        if method == "DELETE", path == "/api/categories" { throw APIError.server(status: 409, message: categoryInUse) }
        if method != "GET" { return Data("{}".utf8) }
        guard let data = data(for: path) else { throw APIError.server(status: 404, message: "No fixture for \(path)") }
        return data
    }

    static let categoryInUse = "This category is still used by 23 transactions and 1 budget, so it cannot be deleted. "
        + "Move those records to a different category first."
}
