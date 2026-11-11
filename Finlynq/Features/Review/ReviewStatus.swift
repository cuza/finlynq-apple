import Foundation
import OSLog

/// How many rows wait in Review, for the sidebar and tab-bar badge, Home's attention row and Activity's review bar.
/// RootView loads it once per `session.revision` and shares it through the environment, so the queue is fetched once
/// per change instead of by every screen.
@Observable
final class ReviewStatus {
    private(set) var count = 0
    var isEmpty: Bool { count < 1 }
    /// Rows a rule already gave a category.
    private(set) var suggested = 0
    /// The account of the first row waiting, for "From the Chequing import".
    private(set) var accountId: Int?

    private static let log = Logger(subsystem: "dev.cuza.finlynq", category: "review")

    /// A failed load keeps the previous numbers.
    func load(_ api: APIClient) async {
        do {
            let rows = try await api.reviewQueue()
            count = rows.count
            suggested = rows.filter { $0.categoryId != nil || $0.category?.isEmpty == false }.count
            accountId = rows.first?.accountId
        } catch is CancellationError {
        } catch {
            Self.log.error("review count failed to load: \(error.localizedDescription, privacy: .public)")
        }
    }
}
