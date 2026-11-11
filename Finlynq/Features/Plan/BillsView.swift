import SwiftUI

/// Bills (Bills.dc.html): what tracked bills cost per month and year, what is due this week and later this month,
/// and recurring payments found in the ledger that can be tracked with one tap.
struct BillsView: View {
    var segment: Binding<PlanSegment>?
    @Environment(Session.self) private var session
    @Environment(\.layoutWidth) private var width
    @Environment(\.presentEditor) private var present
    @State private var tracking: Set<String> = []
    @State private var trackError: String?
    @State private var attempt = 0

    struct Data {
        let subscriptions: [Subscription]
        let budget: BudgetMonth?
        /// Nil when the request failed.
        let suggestions: [RecurringSuggestion]?
    }

    private var today: Date { Fixtures.today }
    private var currency: String { session.currency }
    private static let calendar = Calendar(identifier: .gregorian)

    var body: some View {
        Reloader(id: "\(session.revision)|\(attempt)", source: "bills") { try await load() } content: { data in
            content(data)
        }
        .background(Theme.page)
        .navigationTitle(segment == nil ? "Bills" : "Plan")
        #if os(iOS)
        .toolbarTitleDisplayMode(.large)
        #endif
        .routeDestinations(segment == nil)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add bill", systemImage: "calendar.badge.plus") { present(.addBill) }.macTitleAndIcon()
            }
        }
        .alert("Couldn't track this bill", isPresented: Binding { trackError != nil } set: { if !$0 { trackError = nil } }) {
            Button("OK") {}
        } message: {
            Text(trackError ?? "")
        }
    }

    private func load() async throws -> Data {
        let api = session.api
        async let subscriptions = api.subscriptions()
        async let budget = optionalLoad("bills budget") { try await api.budgetMonth(BudgetModel.monthKey(Fixtures.today)) }
        async let suggestions = optionalLoad("recurring") { try await api.recurringSuggestions() }
        return try await Data(subscriptions: subscriptions, budget: budget, suggestions: suggestions)
    }

    // MARK: Figures

    private func active(_ data: Data) -> [Subscription] { data.subscriptions.filter { $0.status == "active" } }

    private func amount(_ subscription: Subscription) -> Double { subscription.displayAmount ?? subscription.amount }

    private func perMonth(_ data: Data) -> Double {
        active(data).reduce(0) { $0 + BudgetModel.perMonth(amount($1), frequency: $1.frequency) }
    }

    private func next30Days(_ data: Data) -> Double {
        guard let end = Self.calendar.date(byAdding: .day, value: 30, to: today) else { return 0 }
        return active(data).reduce(0) { total, sub in
            let next = APIDate.parse(sub.nextDate ?? "")
            let count = next.map { BudgetModel.occurrences(next: $0, frequency: sub.frequency, from: today, through: end).count } ?? 0
            return total + Double(count) * amount(sub)
        }
    }

    /// Bills after this week through the end of the month: subscriptions and unpaid loan payments, soonest first.
    private func laterThisMonth(_ data: Data) -> [Bill] {
        let start = Self.calendar.startOfDay(for: today)
        guard let weekEnd = Self.calendar.date(byAdding: .day, value: 7, to: start),
              let monthEnd = Self.calendar.dateInterval(of: .month, for: today)?.end else { return [] }
        let subscriptions = active(data).flatMap { sub in
            BudgetModel.occurrences(
                next: APIDate.parse(sub.nextDate ?? "") ?? .distantPast, frequency: sub.frequency, from: weekEnd, through: monthEnd
            )
            .filter { $0 > weekEnd }
            .map {
                Bill(id: "s\(sub.id)-\(APIDate.string($0))", name: sub.displayName, date: $0, amount: amount(sub),
                     category: sub.categoryName, account: sub.accountName, accountId: sub.accountId)
            }
        }
        let loans = (data.budget?.debt ?? []).filter { $0.paid < $0.planned }.flatMap { debt in
            (debt.dueDates ?? []).compactMap(APIDate.parse).filter { $0 > weekEnd && $0 < monthEnd }.map {
                Bill(id: "l\(debt.accountId)-\(APIDate.string($0))", name: debt.name, date: $0, amount: debt.planned - debt.paid,
                     category: "Payment", account: nil, accountId: nil, isLoan: true)
            }
        }
        return (subscriptions + loans).filter { $0.date < monthEnd }.sorted { $0.date < $1.date }
    }

    private func untracked(_ data: Data) -> [RecurringSuggestion] {
        let transfers = Set(session.categories.filter { $0.type != "E" || $0.group == "Savings" }.map(\.id))
        let tracked = Set(data.subscriptions.map { $0.displayName.lowercased() })
        return BudgetModel.untracked(data.suggestions ?? [], tracked: tracked, transferCategories: transfers)
    }

    // MARK: Layout

    private func content(_ data: Data) -> some View {
        let week = HomeModel.billsThisWeek(data.subscriptions, budget: data.budget, today: today)
        let later = laterThisMonth(data)
        let wide = width == .wide
        return ScrollView {
            VStack(spacing: 12) {
                if let segment { SegmentBar("Plan page", options: PlanSegment.options, selection: segment) }
                if width == .medium { portraitSummary(data) } else { summary(data) }
                if wide {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 12) {
                            billsCard("Due this week", week, empty: "Nothing due in the next 7 days.")
                            billsCard("Later this month", later, empty: "Nothing else due this month.")
                        }
                        foundCard(data)
                    }
                } else {
                    billsCard("Due this week", week, empty: "Nothing due in the next 7 days.")
                    if !later.isEmpty { billsCard("Later this month", later, empty: "") }
                    foundCard(data)
                }
            }
            .padding(.horizontal, wide ? 28 : 20).padding(.top, 4).padding(.bottom, 12)
            .frame(maxWidth: wide ? 980 : .infinity)
            .frame(maxWidth: .infinity)
        }
    }

    private func summary(_ data: Data) -> some View {
        let monthly = perMonth(data)
        let count = active(data).count
        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    figure("Per month", monthly.wholeMoney(currency))
                    figure("Per year", (monthly * 12).wholeMoney(currency))
                }
                Divider()
                HStack {
                    Text("\(count) \(count == 1 ? "bill" : "bills") tracked")
                    Spacer()
                    let next = Text(next30Days(data).money(currency)).fontWeight(.semibold).foregroundStyle(Theme.text)
                    Text("Next 30 days \(next)")
                }
                .font(.subheadline).foregroundStyle(Theme.secondary).monospacedDigit()
            }
        }
    }

    /// iPadPBills: the monthly cost on its own line, the yearly cost and count below it.
    private func portraitSummary(_ data: Data) -> some View {
        let monthly = perMonth(data)
        let count = active(data).count
        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                figure("Per month", monthly.wholeMoney(currency))
                HStack {
                    let year = Text((monthly * 12).wholeMoney(currency)).fontWeight(.semibold).foregroundStyle(Theme.text)
                    Text("Per year \(year)")
                    Spacer()
                    Text("\(count) \(count == 1 ? "bill" : "bills") tracked")
                }
                Divider()
                HStack {
                    Text("Next 30 days")
                    Spacer()
                    Text(next30Days(data).money(currency)).fontWeight(.semibold).foregroundStyle(Theme.text)
                }
            }
            .font(.subheadline).foregroundStyle(Theme.secondary).monospacedDigit()
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
            Text(value).font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.text).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func billsCard(_ title: String, _ bills: [Bill], empty: String) -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HomeCardHeader(
                    title: title, detail: bills.isEmpty ? nil : bills.reduce(0) { $0 + $1.amount }.money(currency),
                    layout: width == .compact ? .phone : .pad  // iPadPBills titles its cards at 17pt
                )
                if bills.isEmpty {
                    Text(empty).font(.footnote).foregroundStyle(Theme.secondary).padding(.top, 4)
                } else {
                    DividedRows(items: bills) { bill in billRow(bill) }
                }
            }
        }
    }

    private func billRow(_ bill: Bill) -> some View {
        let icon = Icons.bill(name: bill.name, category: bill.category, isLoan: bill.isLoan)
        let date = bill.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return HStack(spacing: 14) {
            IconTile(symbol: icon.symbol, tint: icon.tint, background: icon.tint.opacity(0.14), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text([date, bill.account].compactMap { $0 }.joined(separator: " \u{00B7} "))
                    .font(.subheadline).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(bill.amount.money(currency)).font(.body.weight(.semibold)).foregroundStyle(Theme.text).monospacedDigit()
                Text(HomeModel.dueIn(bill.date, today: today)).font(.subheadline).foregroundStyle(Theme.secondary)
            }
            .fixedSize()
        }
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func foundCard(_ data: Data) -> some View {
        let found = untracked(data)
        if data.suggestions == nil || !found.isEmpty {
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Found in your transactions").font(.headline).foregroundStyle(Theme.text)
                    Text("Recurring payments you don't track yet").font(.subheadline).foregroundStyle(Theme.secondary)
                        .padding(.bottom, 4)
                    if data.suggestions == nil {
                        InlineError(message: "Couldn't load recurring payments") { attempt += 1 }
                    } else {
                        DividedRows(items: found) { suggestion in suggestionRow(suggestion) }
                    }
                }
            }
        }
    }

    private func suggestionRow(_ suggestion: RecurringSuggestion) -> some View {
        let category = session.categories.first { $0.id == suggestion.categoryId }?.displayName
        let icon = Icons.bill(name: suggestion.payee, category: category, isLoan: false)
        let amount = abs(suggestion.avgAmountDisplay ?? suggestion.avgAmount)
        let busy = tracking.contains(suggestion.id)
        return HStack(spacing: 14) {
            IconTile(symbol: icon.symbol, tint: icon.tint, background: icon.tint.opacity(0.14), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.payee).font(.body.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text("\(amount.money(suggestion.avgAmountDisplay == nil ? suggestion.currency : currency)) \(suggestion.frequency) "
                    + "\u{00B7} seen \(suggestion.count) times")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            Button { Task { await track(suggestion) } } label: {
                Group {
                    if busy { ProgressView().controlSize(.small) } else { Text("Track") }
                }
                .font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
                .padding(.horizontal, 16).frame(height: 34)
                .background(Theme.accentTint, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityLabel("Track \(suggestion.payee)")
        }
        .padding(.vertical, 9)
    }

    /// Adds the suggestion as a subscription with the payee's average amount, in its own currency.
    private func track(_ suggestion: RecurringSuggestion) async {
        tracking.insert(suggestion.id)
        defer { tracking.remove(suggestion.id) }
        let input = SubscriptionInput(
            name: suggestion.payee, amount: abs(suggestion.avgAmount), currency: suggestion.currency, frequency: suggestion.frequency,
            categoryId: suggestion.categoryId, accountId: suggestion.accountId, nextDate: suggestion.nextDate, notes: nil
        )
        do {
            try await session.api.createSubscription(input)
            await session.didSave()
        } catch {
            trackError = error.localizedDescription
        }
    }
}

/// "Add bill": a subscription with a name, amount, how often and the next payment date.
struct AddBillSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var frequency = "monthly"
    @State private var next = Fixtures.today
    @State private var accountId: Int?
    @State private var saving = false
    @State private var error: String?

    private static let frequencies = [
        ("weekly", "Weekly"), ("biweekly", "Every 2 weeks"), ("monthly", "Monthly"), ("quarterly", "Quarterly"),
        ("semi-annual", "Twice a year"), ("annual", "Yearly")
    ]

    private var value: Double? { BudgetModel.amount(amount).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name, prompt: Text("e.g. Netflix, car insurance"))
                TextField("Amount", text: $amount, prompt: Text("Amount per payment"))
                #if os(iOS)
                    .keyboardType(.decimalPad)
                #endif
                Picker("How often", selection: $frequency) {
                    ForEach(Self.frequencies, id: \.0) { Text($0.1).tag($0.0) }
                }
                DatePicker("Next payment", selection: $next, displayedComponents: .date)
                Picker("Paid from", selection: $accountId) {
                    Text("None").tag(Int?.none)
                    ForEach(session.accounts.filter { !$0.archived }) { Text($0.displayName).tag(Int?.some($0.id)) }
                }
                if let error { Text(error).foregroundStyle(Theme.negative) }
            }
            .formStyle(.grouped)
            .navigationTitle("Add bill")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || value == nil || saving)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 340)
        #endif
    }

    private func save() async {
        guard let value else { return }
        saving = true
        defer { saving = false }
        let account = session.accounts.first { $0.id == accountId }
        let input = SubscriptionInput(
            name: name.trimmingCharacters(in: .whitespaces), amount: value, currency: account?.currency ?? session.currency,
            frequency: frequency, categoryId: nil, accountId: accountId, nextDate: APIDate.string(next), notes: nil
        )
        do {
            try await session.api.createSubscription(input)
            await session.didSave()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
