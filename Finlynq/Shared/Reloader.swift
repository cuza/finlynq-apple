import OSLog
import SwiftUI

/// Like `Loader`, but loads again whenever `id` changes (a month, a period, `session.revision`) and keeps showing
/// the last value while it does, so a save doesn't flash a spinner. A failure is logged under `source`.
struct Reloader<T, Content: View>: View {
    private static var log: Logger { Logger(subsystem: "dev.cuza.finlynq", category: "load") }
    let id: String
    var source = "screen"
    let load: () async throws -> T
    @ViewBuilder let content: (T) -> Content

    @State private var value: T?
    @State private var error: String?

    var body: some View {
        LoadState(value: value, error: error, retry: { Task { await run() } }, content: content)
            .task(id: id) { await run() }
            .refreshable { await run() }
    }

    private func run() async {
        do {
            value = try await load()
            error = nil
        } catch is CancellationError {
        } catch {
            Self.log.error("\(source, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            self.error = error.localizedDescription
        }
    }
}

/// Runs an optional request: a failure is logged and gives nil, so the rest of the screen still shows.
func optionalLoad<T>(_ source: String, _ request: () async throws -> T) async -> T? {
    do {
        return try await request()
    } catch {
        if !(error is CancellationError) {
            Logger(subsystem: "dev.cuza.finlynq", category: "load")
                .error("\(source, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
        return nil
    }
}
