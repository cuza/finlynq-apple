import SwiftUI

/// The Activity screen (Activity.dc.html, iPadActivity.dc.html, MacActivity.dc.html). iPhone and iPad portrait
/// (iPadPActivity) show day groups that push the detail; iPad landscape and iPhone Duo's open display
/// (DuoInnerActivity, DuoBookActivity) show the list beside the detail; the Mac shows a table with an inspector.
/// The calendar button swaps the list for the month calendar (Calendar.dc.html) in place.
struct ActivityView: View {
    @Environment(Session.self) private var session
    @Environment(\.layoutWidth) private var width
    @Environment(\.layoutColumn) private var column
    @State private var store: ActivityStore
    @State private var pendingDelete: Transaction?
    @Environment(\.presentEditor) private var present
    @Environment(ReviewStatus.self) private var review

    /// `store` is the shell's, for the Activity tab and sidebar page, so the search, filters and loaded rows survive a
    /// width class change. Other uses (Calendar, a category's "Show transactions") get their own. `categoryId` starts
    /// the list filtered to that category, on `month` when given.
    init(store: ActivityStore? = nil, showsCalendar: Bool = false, categoryId: Int? = nil, month: Date? = nil) {
        let store = store ?? ActivityStore()
        if showsCalendar { store.showsCalendar = true }
        if let categoryId { store.categoryId = categoryId }
        if let month { store.month = month }
        _store = State(initialValue: store)
    }

    var body: some View {
        content
            .background(Theme.page)
            .navigationTitle("Activity")
            #if os(iOS)
            .toolbarTitleDisplayMode(.large)
            #endif
            .navigationDestination(for: AppRoute.self) { RouteDestination(route: $0) }
            .navigationDestination(for: Transaction.self) { transaction in
                TransactionDetailView(transaction: transaction, embedded: false) { Task { await store.load(session) } }
                    .measuresLayoutWidth()
                    // Any way of opening it (tap, VoiceOver, keyboard) selects it, so a widening column (an iPhone
                    // Duo opening) shows the same transaction beside the list.
                    .onAppear { store.selected = transaction.id }
            }
            .task(id: "\(store.queryKey)|\(session.revision)") {
                if !store.search.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
                guard !Task.isCancelled else { return }
                await store.load(session)
            }
            .refreshable { await store.load(session) }
            // The Mac toolbar and iPad sidebar search fields share this store's search, so they filter this list.
            .toolbar { toolbar }
            .importsDroppedStatements()
            .confirmationDialog(
                "Delete this transaction?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let transaction = pendingDelete { Task { await store.remove(ids: [transaction.id], session: session) } }
                }
            } message: {
                Text("This cannot be undone.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.showsCalendar {
            CalendarContent(store: store)
        } else {
            switch width {
            case .compact: phoneList
            case .medium:
                // Side by side when both fit (iPhone Duo open, 669pt), else the list pushes the detail (iPad portrait).
                ViewThatFits(in: .horizontal) {
                    split.wideEnough(640)
                    phoneList
                }
            #if os(macOS)
            case .wide: if macTable { ActivityTable(store: store) } else { split }
            #else
            case .wide: split
            #endif
            }
        }
    }

    /// MacActivity's table and inspector, when the window has room for them (about 760pt of table beside the 320pt
    /// inspector). Narrower windows get the iPad layouts.
    private var macTable: Bool { LayoutWidth.fitsMacDesign(width, column: column, needs: MacDesignWidth.activity) }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        #if os(macOS)
        // MacActivity.dc.html: month, account and category popups, then Import, beside the shell's search and Add.
        // Narrower windows have the iPad and iPhone filter chips above the list.
        if macTable {
            ToolbarItem(placement: .primaryAction) { MacFilters(store: store).padding(.leading, 8) }
            .sharedBackgroundHidden()
        }
        ToolbarItem(placement: .primaryAction) {
            Toggle("Calendar", systemImage: "calendar", isOn: $store.showsCalendar)
                .help(store.showsCalendar ? "Show the list" : "Show the calendar")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Import", systemImage: "square.and.arrow.down") { present(.importStatement) }
                .macTitleAndIcon().help("Import a statement")
        }
        #else
        ToolbarItem(placement: .primaryAction) {
            Button("Import a statement", systemImage: "square.and.arrow.down") { present(.importStatement) }
        }
        ToolbarItem(placement: .primaryAction) { Toggle("Calendar", systemImage: "calendar", isOn: $store.showsCalendar) }
        #endif
    }

    // MARK: iPhone and iPad, and narrower Mac windows

    private var phoneList: some View {
        ScrollView {
            list(selectable: false).padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 12)
        }
    }

    /// List and detail share the width evenly, as the boards do (and around the fold of a half-open iPhone Duo).
    private var split: some View {
        HStack(spacing: 0) {
            ScrollView {
                list(selectable: true).padding(.leading, width == .wide ? 28 : 16).padding(.trailing, 16).padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity)
            Divider()
            Group {
                if let transaction = store.visible.first(where: { $0.id == store.selected }) {
                    TransactionDetailView(transaction: transaction, layout: .pane, embedded: true) { Task { await store.load(session) } }
                        .id(transaction.id)
                } else {
                    EmptyState(title: "Select a transaction", message: "Pick one from the list to see its details.", symbol: "list.bullet")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onChange(of: store.visible.first?.id, initial: true) { if store.selected == nil { store.selected = $1 } }
    }

    private func list(selectable: Bool) -> some View {
        let groups = ActivityModel.groupByDay(store.visible)
        return LazyVStack(alignment: .leading, spacing: 12) {
            #if os(iOS)
            // The Mac's toolbar search filters the same store.
            SearchField(text: Bindable(store).search)
            #endif
            ActivityFilters(store: store)
            if !review.isEmpty {
                ReviewBar(count: review.count, account: session.accounts.first { $0.id == review.accountId }?.displayName)
            }
            ActivitySummary(store: store).padding(.horizontal, 4)
            if let message = store.error {
                Text(message).foregroundStyle(Theme.negative)
            } else if !store.loaded {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
            } else if groups.isEmpty {
                EmptyState(
                    title: store.hasFilters ? "Nothing matches" : "No transactions this month",
                    message: store.hasFilters ? "Try a different search or clear a filter." : "Transactions you add or import appear here.",
                    symbol: "tray"
                )
            }
            ForEach(groups, id: \.day) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(ActivityStore.dayTitle(group.day)).accessibilityAddTraits(.isHeader)
                        Spacer()
                        // The portrait and Duo boards total each day.
                        let net = ActivityModel.monthTotals(group.rows, rates: store.rates).net
                        if width == .medium && net != 0 {
                            Text(MoneyText.format(net, currency: session.currency, signed: true)).monospacedDigit()
                        }
                    }
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 4).padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, transaction in
                            if index > 0 { Divider().padding(.horizontal, selectable ? 10 : 0) }
                            row(transaction, selectable: selectable)
                        }
                    }
                    .padding(selectable ? 6 : 0)
                    .padding(.horizontal, selectable ? 0 : 16)
                    .listCard()
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ transaction: Transaction, selectable: Bool) -> some View {
        if selectable {
            let isSelected = store.selected == transaction.id
            Button { store.selected = transaction.id } label: {
                ActivityRow(transaction: transaction, selected: isSelected)
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(isSelected ? Theme.accentTint : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .contextMenu { Button("Delete", role: .destructive) { pendingDelete = transaction } }
        } else {
            NavigationLink(value: transaction) {
                ActivityRow(transaction: transaction).padding(.vertical, 11).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { Button("Delete", role: .destructive) { pendingDelete = transaction } }
        }
    }
}

// MARK: Pieces

struct ActivityRow: View {
    let transaction: Transaction
    /// The iPad list's highlighted row: the icon sits on white.
    var selected = false

    var body: some View {
        let icon = Icons.transaction(transaction)
        HStack(spacing: 12) {
            IconTile(symbol: icon.0, tint: icon.1, background: selected ? Theme.card : icon.1.opacity(0.15))
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                subtitle
            }
            Spacer(minLength: 8)
            Text(MoneyText.format(transaction.amount, currency: transaction.currency))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(transaction.isTransfer ? Theme.secondary : transaction.amount > 0 ? Theme.positive : Theme.text)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var subtitle: some View {
        if transaction.categoryName == nil && !transaction.isTransfer && transaction.portfolioHoldingId == nil {
            Text("Needs a category").font(.footnote.weight(.medium)).foregroundStyle(Theme.warning)
        } else {
            Text([transaction.isTransfer ? "Transfer" : transaction.categoryName, transaction.account]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.footnote).foregroundStyle(Theme.secondary).lineLimit(1)
        }
    }
}

/// Grey rounded search field from the designs, always visible above the list.
struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.subheadline.weight(.medium)).accessibilityHidden(true)
            TextField("Search payee, note, tag or amount", text: $text)
                .foregroundStyle(Theme.text)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityIdentifier("activitySearch")
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Month, account, category and uncategorized chips (iPhone and iPad). The month chip is always dark; the
/// others turn dark while their filter is on.
struct ActivityFilters: View {
    @Environment(Session.self) private var session
    @Bindable var store: ActivityStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Month", selection: $store.month) {
                        ForEach(ActivityStore.recentMonths(), id: \.self) { Text($0.formatted(.dateTime.month(.wide).year())).tag($0) }
                    }
                } label: { chip(store.month.formatted(.dateTime.month(.wide)), active: true) }
                Menu {
                    Picker("Account", selection: $store.accountId) {
                        Text("All accounts").tag(Int?.none)
                        ForEach(session.accounts.filter { !$0.archived }) { Text($0.displayName).tag(Int?.some($0.id)) }
                    }
                } label: {
                    chip(session.accounts.first { $0.id == store.accountId }?.displayName ?? "Account", active: store.accountId != nil)
                }
                Menu {
                    Picker("Category", selection: $store.categoryId) {
                        Text("All categories").tag(Int?.none)
                        ForEach(session.categories) { Text($0.displayName).tag(Int?.some($0.id)) }
                    }
                } label: {
                    chip(session.categories.first { $0.id == store.categoryId }?.displayName ?? "Category", active: store.categoryId != nil)
                }
                Button { store.uncategorizedOnly.toggle() } label: { chip("Uncategorized", active: store.uncategorizedOnly) }
                    .accessibilityAddTraits(store.uncategorizedOnly ? .isSelected : [])
            }
            .buttonStyle(.plain)
            .menuStyle(.button)
            .menuIndicator(.hidden)
        }
    }

    private func chip(_ text: String, active: Bool) -> some View {
        Text(text).font(.footnote.weight(active ? .semibold : .medium)).lineLimit(1)
            .padding(.horizontal, 12).frame(height: 32)
            .foregroundStyle(active ? Theme.page : Theme.text)
            .background(active ? Theme.text : Theme.card, in: Capsule())
            .overlay { if !active { Capsule().strokeBorder(Theme.hairline) } }
            .contentShape(Capsule())
    }
}

/// Blue bar that opens the review queue. Hidden by the caller when there is nothing to review.
struct ReviewBar: View {
    let count: Int
    let account: String?

    var body: some View {
        NavigationLink(value: AppRoute.review) {
            HStack(spacing: 12) {
                Text("\(count)").font(.subheadline.weight(.bold)).monospacedDigit()
                    .frame(width: 36, height: 36).background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text("To review").font(.subheadline.weight(.semibold))
                    Text(account.map { "Imported from \($0)" } ?? "From your imports").font(.footnote).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Text("Review").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Spent, income and net for the loaded month, in the display currency. iOS spreads them across the row;
/// the Mac footer packs them to the left.
struct ActivitySummary: View {
    @Environment(Session.self) private var session
    let store: ActivityStore

    var body: some View {
        let totals = ActivityModel.monthTotals(store.visible, rates: store.rates)
        let missing = ActivityModel.unconverted(store.visible, rates: store.rates)
        VStack(alignment: .leading, spacing: 2) {
            // Amounts never shrink or truncate: whole amounts when the cents don't fit (iPhone Duo closed).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { figures(totals, cents: true) }
                HStack(spacing: 16) { figures(totals, cents: false) }
                // Large text: one total per line.
                VStack(alignment: .leading, spacing: 2) { figures(totals, cents: false, spaced: false) }
            }
            .accessibilityElement(children: .combine)
            if !missing.isEmpty {
                Text("Some amounts in \(missing.joined(separator: ", ")) aren't included")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
        #if os(iOS)
        .font(.footnote)
        #endif
    }

    @ViewBuilder
    private var gap: some View {
        #if os(iOS)
        Spacer(minLength: 4)
        #endif
    }

    /// The three totals; `spaced` puts the gaps between them for a row.
    @ViewBuilder
    // swiftlint:disable:next large_tuple
    private func figures(_ totals: (spent: Double, income: Double, net: Double), cents: Bool, spaced: Bool = true) -> some View {
        item("Spent", MoneyText.format(totals.spent, currency: session.currency, cents: cents), Theme.text)
        if spaced { gap }
        item("Income", MoneyText.format(totals.income, currency: session.currency, cents: cents), Theme.positive)
        if spaced { gap }
        item(
            "Net", MoneyText.format(totals.net, currency: session.currency, signed: true, cents: cents),
            totals.net >= 0 ? Theme.positive : Theme.negative
        )
    }

    private func item(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(Theme.secondary)
            Text(value).fontWeight(.semibold).monospacedDigit().foregroundStyle(color)
        }
        .fixedSize()
    }
}

/// A category as a colored pill: the group's color, a dashed orange "Needs a category", or an outlined "Transfer".
struct CategoryPill: View {
    @Environment(Session.self) private var session
    let transaction: Transaction

    var body: some View {
        if transaction.isTransfer || transaction.categoryType == "R" {
            label(transaction.isTransfer ? "Transfer" : transaction.categoryName ?? "", Theme.secondary)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline))
        } else if let name = transaction.categoryName ?? transaction.portfolioHolding {
            let category = session.categories.first { $0.id == transaction.categoryId }
            let tone = ActivityModel.tone(
                group: category?.group, type: transaction.categoryType, groups: ActivityModel.expenseGroups(session.categories)
            )
            let colors = Self.colors(tone)
            label(name, colors.0).background(colors.1, in: RoundedRectangle(cornerRadius: 6))
        } else {
            label("Needs a category", Theme.warning)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.spendBar, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        }
    }

    private func label(_ text: String, _ color: Color) -> some View {
        Text(text).fontWeight(.medium).foregroundStyle(color).lineLimit(1).padding(.horizontal, 8).padding(.vertical, 2)
    }

    /// Text and fill for a tone.
    static func colors(_ tone: ActivityModel.Tone) -> (Color, Color) {
        switch tone {
        case .grey: (Theme.text, Theme.fill)
        case .purple: (Theme.invest, Theme.investTint)
        case .orange: (Theme.warning, Theme.warningTint)
        case .blue: (Theme.accent, Theme.accentTint)
        case .green: (Theme.positive, Theme.positiveTint)
        }
    }
}

extension Theme {
    /// Outline of chips, pills and popup buttons (#D9DCE1 in the designs).
    static let hairline = Theme.text.opacity(0.14)
}

extension View {
    /// White list card from the Activity designs: 18pt corners, and a hairline in dark mode.
    func listCard(radius: CGFloat = 18) -> some View {
        background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.cardBorder))
    }
}
