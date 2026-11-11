import Foundation
import Observation

/// What the Activity and Calendar screens show: one month of transactions plus the filters that chose them.
@Observable
final class ActivityStore {
    var month = ActivityStore.recentMonths()[0]
    var search = ""
    /// The month calendar in place of the list.
    var showsCalendar = false
    var accountId: Int?
    var categoryId: Int?
    var uncategorizedOnly = false
    /// The row shown beside the list when there is room for both (iPad landscape, iPhone Duo open). Kept here so
    /// it survives a width change.
    var selected: Int?

    private(set) var rows: [Transaction] = []
    private(set) var bills: [Subscription] = []
    private(set) var rates: ActivityModel.Rates = [:]
    private(set) var loaded = false
    private(set) var error: String?

    private let pageSize = 500

    var visible: [Transaction] { uncategorizedOnly ? ActivityModel.uncategorized(rows) : rows }
    var hasFilters: Bool { !search.isEmpty || accountId != nil || categoryId != nil || uncategorizedOnly }

    /// Changes whenever the server query changes. Search is debounced by the caller.
    var queryKey: String { "\(APIDate.string(month).prefix(7))|\(search)|\(accountId ?? 0)|\(categoryId ?? 0)" }

    /// Bumped by every load. A load that finds a newer number when it finishes drops its result.
    private var generation = 0

    func load(_ session: Session) async { await load(api: session.api, currency: session.currency) }

    func load(api: APIClient, currency: String) async {
        generation += 1
        let mine = generation
        let bounds = ActivityModel.bounds(of: month)
        var query = TransactionQuery(
            search: search.isEmpty ? nil : search, accountId: accountId, categoryId: categoryId,
            startDate: bounds.start, endDate: bounds.end, limit: pageSize
        )
        var all: [Transaction] = []
        do {
            // ponytail: loads the whole month so the totals are exact; page the list if a month passes a few thousand rows.
            while all.count < 5000 {
                query.offset = all.count
                let page = try await api.transactions(query)
                all += page.data
                if page.data.count < pageSize || all.count >= page.total { break }
            }
        } catch is CancellationError {
            return
        } catch let failure as URLError where failure.code == .cancelled {
            return
        } catch {
            if mine == generation { self.error = error.localizedDescription }
            return
        }
        async let subscriptions = try? api.subscriptions()
        async let fxRates = try? api.fxRates(target: currency)
        let loadedBills = await subscriptions
        let loadedRates = await fxRates
        guard mine == generation, !Task.isCancelled else { return }
        rows = all.filter { $0.date.prefix(10) >= bounds.start && $0.date.prefix(10) <= bounds.end }
        error = nil
        loaded = true
        bills = loadedBills ?? bills
        rates = loadedRates ?? (rates.isEmpty ? [currency: 1] : rates)
    }

    func remove(ids: [Int], session: Session) async {
        do {
            for id in ids { try await session.api.deleteTransaction(id: id) }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        await load(session)
    }

    func change(ids: [Int], _ changes: TransactionChanges, session: Session) async {
        do {
            try await session.api.bulkUpdateTransactions(ids: ids, changes: changes)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        await load(session)
    }

    /// The last 12 months, newest first, for the month menu.
    static func recentMonths(from today: Date = Fixtures.today) -> [Date] {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.dateInterval(of: .month, for: today)?.start ?? today
        return (0..<12).compactMap { calendar.date(byAdding: .month, value: -$0, to: start) }
    }

    /// "Today", or "Saturday, Nov 8"; the short form is "Nov 8".
    static func dayTitle(_ day: Date, today: Date = Fixtures.today, abbreviated: Bool = false) -> String {
        if Calendar(identifier: .gregorian).isDate(day, inSameDayAs: today) { return "Today" }
        if abbreviated { return day.formatted(.dateTime.month(.abbreviated).day()) }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
