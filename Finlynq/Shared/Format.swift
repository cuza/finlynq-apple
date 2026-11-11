import SwiftUI

extension Double {
    /// `cents: false` rounds to whole units, as in sidebar balances.
    func money(_ currency: String?, cents: Bool = true) -> String {
        formatted(.currency(code: currency ?? "USD").precision(.fractionLength(cents ? 2 : 0)))
    }

    /// Short form for chart axes and tiles, e.g. "$12.3K".
    func compactMoney(_ currency: String?) -> String {
        formatted(.currency(code: currency ?? "USD").notation(.compactName).precision(.significantDigits(1...3)))
    }

    var percent: String {
        (self / 100).formatted(.percent.precision(.fractionLength(1)))
    }
}

extension Color {
    static func gain(_ value: Double) -> Color {
        value > 0 ? .green : value < 0 ? .red : .secondary
    }
}

nonisolated enum APIDate {
    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parse(_ text: String) -> Date? { day.date(from: String(text.prefix(10))) }
    static func string(_ date: Date) -> String { day.string(from: date) }
}

/// Full-screen loading, error and content states for a screen whose main source is required.
struct LoadState<Value, Content: View>: View {
    let value: Value?
    let error: String?
    let retry: () -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        if let value {
            content(value)
        } else if let error {
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try again", action: retry)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Loads data for a screen and shows a spinner, an error with a retry button, or the content.
struct Loader<T, Content: View>: View {
    let load: () async throws -> T
    @ViewBuilder let content: (T) -> Content

    @State private var value: T?
    @State private var error: String?

    var body: some View {
        LoadState(value: value, error: error, retry: { Task { await run() } }, content: content)
            .task { await run() }
            .refreshable { await run() }
    }

    private func run() async {
        do {
            value = try await load()
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
