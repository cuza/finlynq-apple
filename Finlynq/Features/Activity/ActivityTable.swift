#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// Mac Activity (MacActivity.dc.html): review banner, a table with a checkbox column for bulk actions, a dark
/// bulk bar while rows are checked, a footer with totals, and an inspector for the current row.
/// The checked set and the inspected row are separate, like Mail's selection and reading pane. The inspected row is
/// the store's selection, so a narrower window's list shows the same transaction.
struct ActivityTable: View {
    @Environment(Session.self) private var session
    @Environment(ReviewStatus.self) private var review
    let store: ActivityStore
    @State private var checked = Set<Int>()
    /// Rows the delete dialog asks about. Kept apart from `checked`, so cancelling leaves the checkboxes alone.
    @State private var deleteTargets = Set<Int>()
    @State private var export: CSVFile?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if !review.isEmpty { reviewBanner }
                content
                    .overlay(alignment: .bottom) { if !checked.isEmpty { bulkBar.padding(.bottom, 18) } }
                footer
            }
            .background(Theme.card)
            Divider()
            inspector.frame(width: 320).background(Theme.toolbar)
        }
        .onChange(of: store.visible.first?.id, initial: true) { if store.selected == nil { store.selected = $1 } }
        .confirmationDialog(
            deleteTargets.count == 1 ? "Delete this transaction?" : "Delete \(deleteTargets.count) transactions?",
            isPresented: Binding(get: { !deleteTargets.isEmpty }, set: { if !$0 { deleteTargets = [] } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let ids = deleteTargets
                checked.subtract(ids)
                deleteTargets = []
                Task { await store.remove(ids: Array(ids), session: session) }
            }
        } message: {
            Text("This cannot be undone.")
        }
        .fileExporter(
            isPresented: Binding(get: { export != nil }, set: { if !$0 { export = nil } }),
            document: export, contentType: .commaSeparatedText, defaultFilename: exportName
        ) { _ in export = nil }
    }

    private var exportName: String { ActivityModel.exportName(month: store.month) }

    private var reviewBanner: some View {
        let count = review.count
        let account = session.accounts.first { $0.id == review.accountId }?.displayName
        let from = account.map { "From the \($0) statement" } ?? "From your imports"
        let suggested = review.suggested > 0 ? " · \(review.suggested) have a suggested category" : ""
        return NavigationLink(value: AppRoute.review) {
            HStack(spacing: 10) {
                Text("\(count)").font(.system(size: 11, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                    .padding(.horizontal, 6).frame(minWidth: 22, minHeight: 20).background(Theme.accent, in: Capsule())
                Text("\(count) imported transaction\(count == 1 ? "" : "s") to review").fontWeight(.semibold).foregroundStyle(Theme.text)
                Text(from + suggested).foregroundStyle(Theme.secondary).lineLimit(1)
                Spacer()
                Text("Review").fontWeight(.semibold).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 24)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(Theme.accentTint)
            .overlay(alignment: .bottom) { Theme.accent.opacity(0.15).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if let message = store.error {
            EmptyState(title: "Couldn't load", message: message, symbol: "exclamationmark.triangle").frame(maxHeight: .infinity)
        } else if store.loaded && store.visible.isEmpty {
            EmptyState(
                title: store.hasFilters ? "Nothing matches" : "No transactions this month",
                message: store.hasFilters ? "Try a different search or clear a filter." : "Transactions you add or import appear here.",
                symbol: "tray"
            )
            .frame(maxHeight: .infinity)
        } else {
            table
        }
    }

    private var allChecked: Binding<Bool> {
        Binding(
            get: { !store.visible.isEmpty && store.visible.allSatisfy { checked.contains($0.id) } },
            set: { checked = $0 ? Set(store.visible.map(\.id)) : [] }
        )
    }

    private var table: some View {
        Table(store.visible, selection: Bindable(store).selected) {
            TableColumn(Text("")) { row in
                Toggle("Select \(row.title)", isOn: Binding(
                    get: { checked.contains(row.id) },
                    set: { if $0 { checked.insert(row.id) } else { checked.remove(row.id) } }
                ))
                .labelsHidden().toggleStyle(.checkbox)
            }
            .width(24)
            TableColumn("Date") { row in
                Text(ActivityStore.dayTitle(row.day, abbreviated: true)).foregroundStyle(.secondary)
            }
            .width(80)
            TableColumn("Payee") { row in Text(row.title).fontWeight(.medium).lineLimit(1) }
            TableColumn("Category") { row in
                CategoryPill(transaction: row)
            }
            .width(min: 120, ideal: 180)
            TableColumn("Account") { row in Text(row.account).foregroundStyle(.secondary).lineLimit(1) }
                .width(min: 100, ideal: 170)
            TableColumn("Amount") { row in
                Text(MoneyText.format(row.amount, currency: row.currency)).fontWeight(.medium).monospacedDigit()
                    .foregroundStyle(row.amount > 0 && !row.isTransfer ? AnyShapeStyle(Theme.positive) : AnyShapeStyle(.primary))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 90, ideal: 110)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .environment(\.defaultMinListRowHeight, 34)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .topLeading) {
            // The header's select-all box, over the empty first column title.
            Toggle("Select all transactions", isOn: allChecked).labelsHidden().toggleStyle(.checkbox)
                .padding(.leading, 14).frame(height: 28)
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            Button("Delete", role: .destructive) { deleteTargets = ids }
        }
        .onDeleteCommand {
            // Checked rows first, else the row in the inspector.
            deleteTargets = checked.isEmpty ? Set([store.selected].compactMap { $0 }) : checked
        }
    }

    /// Dark floating bar while rows are checked.
    private var bulkBar: some View {
        HStack(spacing: 6) {
            Text("\(checked.count) selected").fontWeight(.semibold).padding(.trailing, 8)
            Menu {
                ForEach(session.categories) { category in
                    Button(category.displayName) { apply(.init(categoryId: category.id)) }
                }
            } label: { barButton("Change category", color: .white) }
            Menu {
                ForEach(session.accounts.filter { !$0.archived }) { account in
                    Button(account.displayName) { apply(.init(accountId: account.id)) }
                }
            } label: { barButton("Change account", color: .white) }
            Button { deleteTargets = checked } label: { barButton("Delete", color: Color(red: 1, green: 0.61, blue: 0.58)) }
            Button { checked = [] } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .accessibilityLabel("Clear selection")
        }
        .buttonStyle(.plain)
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .foregroundStyle(.white)
        .padding(.leading, 14).padding(6)
        .background(Color(red: 0.067, green: 0.075, blue: 0.094), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 8)
        .fixedSize()
    }

    private func barButton(_ title: String, color: Color) -> some View {
        Text(title).fontWeight(.medium).foregroundStyle(color)
            .padding(.horizontal, 12).frame(height: 28)
            .background(Color(red: 0.165, green: 0.176, blue: 0.208), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func apply(_ changes: TransactionChanges) {
        let ids = Array(checked)
        checked = []
        Task { await store.change(ids: ids, changes, session: session) }
    }

    private var footer: some View {
        let shown = store.visible.count
        return HStack(spacing: 16) {
            Text(shown == store.rows.count ? "\(shown) transactions" : "\(shown) of \(store.rows.count) transactions")
                .foregroundStyle(Theme.secondary)
            ActivitySummary(store: store)
            Spacer()
            Button("Export CSV") { export = CSVFile(text: ActivityModel.csv(store.visible)) }
                .buttonStyle(.plain).fontWeight(.medium).foregroundStyle(Theme.accent)
                .disabled(store.visible.isEmpty)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16).frame(height: 34)
        .background(Theme.toolbar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var inspector: some View {
        if let transaction = store.visible.first(where: { $0.id == store.selected }) {
            TransactionDetailView(transaction: transaction, layout: .inspector, embedded: true) { Task { await store.load(session) } }
                .id(transaction.id)
        } else {
            EmptyState(title: "Select a transaction", message: "Click a row to see its details.", symbol: "list.bullet")
        }
    }
}

/// Month, account and category popups from MacActivity.dc.html: outlined buttons sized to their value. The category
/// popup also filters to rows that need a category.
struct MacFilters: View {
    @Environment(Session.self) private var session
    @Bindable var store: ActivityStore

    /// Category popup tag for "Needs a category".
    private static let uncategorized = -1

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Month", selection: $store.month) {
                    ForEach(ActivityStore.recentMonths(), id: \.self) { Text($0.formatted(.dateTime.month(.wide).year())).tag($0) }
                }
                .pickerStyle(.inline)
            } label: { MacPopupLabel(text: store.month.formatted(.dateTime.month(.wide).year())) }
            Menu {
                Picker("Account", selection: $store.accountId) {
                    Text("All accounts").tag(Int?.none)
                    Divider()
                    ForEach(session.accounts.filter { !$0.archived }) { Text($0.displayName).tag(Int?.some($0.id)) }
                }
                .pickerStyle(.inline)
            } label: { MacPopupLabel(text: session.accounts.first { $0.id == store.accountId }?.displayName ?? "All accounts") }
            Menu {
                Picker("Category", selection: category) {
                    Text("All categories").tag(Int?.none)
                    Text("Needs a category").tag(Int?.some(Self.uncategorized))
                    Divider()
                    ForEach(session.categories) { Text($0.displayName).tag(Int?.some($0.id)) }
                }
                .pickerStyle(.inline)
            } label: { MacPopupLabel(text: categoryTitle) }
        }
        .labelsHidden()
        .plainMenu()
        .fixedSize()
    }

    private var categoryTitle: String {
        if store.uncategorizedOnly { return "Needs a category" }
        return session.categories.first { $0.id == store.categoryId }?.displayName ?? "All categories"
    }

    private var category: Binding<Int?> {
        Binding(
            get: { store.uncategorizedOnly ? Self.uncategorized : store.categoryId },
            set: {
                store.uncategorizedOnly = $0 == Self.uncategorized
                store.categoryId = $0 == Self.uncategorized ? nil : $0
            }
        )
    }
}

/// Outlined white button face for the Mac toolbar: 26pt popups with a chevron, 28pt buttons with an icon.
struct MacPopupLabel: View {
    let text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .medium)) }
            Text(text).font(.system(size: 13, weight: .medium)).lineLimit(1)
            if symbol == nil {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
        }
        .foregroundStyle(Theme.text)
        .padding(.leading, 10).padding(.trailing, symbol == nil ? 8 : 10)
        .frame(height: symbol == nil ? 26 : 28)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: symbol == nil ? 6 : 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: symbol == nil ? 6 : 7, style: .continuous).strokeBorder(Theme.hairline))
        .contentShape(Rectangle())
    }
}
#endif
