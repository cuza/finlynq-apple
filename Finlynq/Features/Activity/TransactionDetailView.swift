import SwiftUI

/// One transaction: amount, editable fields, split, rule shortcut and delete.
/// `.page` is the pushed iPhone screen (Transaction.dc.html), `.pane` the iPad detail column (iPadActivity.dc.html)
/// and `.inspector` the Mac inspector (MacActivity.dc.html).
struct TransactionDetailView: View {
    enum Layout { case page, pane, inspector }

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.layoutWidth) private var width

    let transaction: Transaction
    let layout: Layout
    /// True inside a host that lists the rows (iPad split, Mac inspector), which closes it itself. Anywhere else
    /// the screen was pushed, and Delete pops it.
    let embedded: Bool
    /// Called after a save, split change or delete so the list can reload.
    let onChange: () -> Void

    @State private var payee: String
    @State private var note: String
    @State private var tags: String
    @State private var categoryId: Int?
    @State private var accountId: Int?
    @State private var date: Date
    @State private var drafts: [SplitDraft] = []
    @State private var savedDrafts: [SplitDraft] = []
    @State private var similar: (count: Int, average: Double)?
    @State private var ruleCreated = false
    @State private var saving = false
    @State private var error: String?
    @State private var confirmDelete = false

    #if os(macOS)
    static let defaultLayout = Layout.inspector
    #else
    static let defaultLayout = Layout.page
    #endif

    init(
        transaction: Transaction, layout: Layout = Self.defaultLayout, embedded: Bool, onChange: @escaping () -> Void
    ) {
        self.transaction = transaction
        self.layout = layout
        self.embedded = embedded
        self.onChange = onChange
        _payee = State(initialValue: transaction.payee ?? "")
        _note = State(initialValue: transaction.note ?? "")
        _tags = State(initialValue: transaction.tags ?? "")
        _categoryId = State(initialValue: transaction.categoryId)
        _accountId = State(initialValue: transaction.accountId)
        _date = State(initialValue: transaction.day)
    }

    private var dirty: Bool {
        payee != (transaction.payee ?? "") || note != (transaction.note ?? "") || tags != (transaction.tags ?? "")
            || (transaction.isSimple
                && (categoryId != transaction.categoryId || accountId != transaction.accountId || date != transaction.day))
    }

    private var kind: String {
        if transaction.isTransfer { return "Transfer" }
        if transaction.portfolioHoldingId != nil { return "Investment" }
        return transaction.amount > 0 ? "Income" : "Expense"
    }

    // MARK: Metrics

    private var compact: Bool { layout == .inspector }
    private var radius: CGFloat { compact ? 10 : 18 }
    private var rowHeight: CGFloat { layout == .page ? 48 : compact ? 30 : 46 }
    private var labelWidth: CGFloat { layout == .pane ? 84 : compact ? 72 : 78 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 14 : 12) {
                header
                fieldsCard
                if transaction.isSimple {
                    SplitEditor(
                        drafts: $drafts, total: transaction.amount, currency: transaction.currency,
                        seedCategoryId: transaction.categoryId, compact: compact, dirty: splitsDirty, saving: saving,
                        onSave: { Task { await saveSplits() } }, onClear: { Task { await clearSplits() } }
                    )
                }
                suggestions
                if let error {
                    Text(error).font(DetailFont.small).foregroundStyle(Theme.negative).frame(maxWidth: .infinity, alignment: .leading)
                }
                if !compact { footer }
            }
            .font(DetailFont.body)
            .padding(.horizontal, layout == .page ? 20 : compact ? 18 : 0)
            .padding(.leading, layout == .pane ? 24 : 0).padding(.trailing, layout == .pane ? 28 : 0)
            .padding(.top, compact ? 18 : 4).padding(.bottom, compact ? 16 : 28)
            .frame(maxWidth: embedded ? .infinity : 680)
            .frame(maxWidth: .infinity)
        }
        // MacActivity.dc.html pins Delete to the bottom of the inspector.
        .safeAreaInset(edge: .bottom) {
            if compact { footer.frame(maxWidth: embedded ? .infinity : 644).padding(.horizontal, 18).padding(.vertical, 12)
                    .frame(maxWidth: .infinity).background(surface) }
        }
        .background(surface)
        .modifier(PageChrome(title: layout == .page ? transaction.title : nil, dirty: dirty, saving: saving) {
            Task { await save() }
        })
        .confirmationDialog("Delete this transaction?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: {
            Text("This cannot be undone.")
        }
        .task { await loadExtras() }
    }

    /// The inspector's grey (#FAFAFB) inside Activity; the page grey when pushed.
    private var surface: Color { compact && embedded ? Theme.toolbarBackground : Theme.page }

    private var footer: some View {
        DetailFooter(layout: layout, dirty: dirty, saving: saving, onSave: { Task { await save() } }, onDelete: { confirmDelete = true })
    }

    private var splitsDirty: Bool {
        drafts.map { [$0.categoryId ?? 0, $0.amount, $0.note] as [AnyHashable] }
            != savedDrafts.map { [$0.categoryId ?? 0, $0.amount, $0.note] as [AnyHashable] }
    }

    // MARK: Header

    private var subtitle: String { "\(kind) · \(transaction.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))" }

    private var amountText: Text { Text(MoneyText.format(transaction.amount, currency: transaction.currency)).bold() }

    @ViewBuilder
    private var header: some View {
        let icon = Icons.transaction(transaction)
        switch layout {
        case .page where width != .compact:
            stackedHeader(title: nil)
        case .page:
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    amountText.font(.system(size: 36, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Text(subtitle).font(.footnote).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 8)
                IconTile(symbol: icon.0, tint: icon.1, background: icon.1.opacity(0.15), size: 48)
            }
            .padding(18)
            .listCard(radius: Theme.cardRadius)
        case .pane:
            // Inline while the icon, the amount and about 140pt of the name fit; else the amount sits under the name
            // (iPhone Duo open), so a cramped header doesn't cut the name to a few letters.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    IconTile(symbol: icon.0, tint: icon.1, background: icon.1.opacity(0.15), size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(transaction.title).font(.title2.weight(.bold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(subtitle).font(.footnote).foregroundStyle(Theme.secondary).lineLimit(2)
                    }
                    .frame(minWidth: 100, idealWidth: 140, maxWidth: .infinity, alignment: .leading)
                    amountText.font(.system(size: 34, weight: .bold)).monospacedDigit().fixedSize()
                }
                .padding(18)
                .listCard(radius: Theme.cardRadius)
                stackedHeader(title: transaction.title)
            }
        case .inspector:
            HStack(spacing: 10) {
                IconTile(symbol: icon.0, tint: icon.1, background: icon.1.opacity(0.15), size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(transaction.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                amountText.font(.system(size: 20, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }

    /// The portrait and Duo boards' header: icon and kind on one line, the amount below at full width.
    private func stackedHeader(title: String?) -> some View {
        let icon = Icons.transaction(transaction)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconTile(symbol: icon.0, tint: icon.1, background: icon.1.opacity(0.15), size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    if let title {
                        Text(title).font(.title3.weight(.bold)).foregroundStyle(Theme.text).lineLimit(2)
                    }
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.secondary).lineLimit(2)
                }
            }
            amountText.font(.system(size: 40, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listCard(radius: Theme.cardRadius)
    }

    // MARK: Fields

    private var fieldsCard: some View {
        VStack(spacing: 0) {
            field("Payee") { TextField("Payee", text: $payee).textFieldStyle(.plain) }
            Divider()
            field("Category") {
                if transaction.isSimple {
                    Menu {
                        Picker("Category", selection: $categoryId) {
                            Text("No category").tag(Int?.none)
                            ForEach(session.categories) { Text($0.displayName).tag(Int?.some($0.id)) }
                        }
                    } label: {
                        Text(categoryText).foregroundStyle(categoryId == nil && drafts.count < 2 ? Theme.warning : Theme.text)
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .plainMenu()
                } else {
                    Text(transaction.isTransfer ? "Transfer" : (transaction.categoryName ?? "None")).foregroundStyle(Theme.text)
                }
                if drafts.count > 1 { Chip(text: "Split") }
            }
            Divider()
            field("Account") {
                if transaction.isSimple {
                    Menu {
                        Picker("Account", selection: $accountId) {
                            ForEach(session.accounts.filter { !$0.archived || $0.id == accountId }) {
                                Text($0.displayName).tag(Int?.some($0.id))
                            }
                        }
                    } label: {
                        Text(accountText).foregroundStyle(Theme.text).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .plainMenu()
                } else {
                    Text(transaction.account).foregroundStyle(Theme.text)
                }
            }
            Divider()
            field("Date") {
                let text = Text(date.formatted(.dateTime.month(.abbreviated).day().year())).foregroundStyle(Theme.text)
                if transaction.isSimple {
                    // The design shows the date as plain text; a nearly clear picker on top takes the taps.
                    text.frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .leading) {
                            DatePicker("Date", selection: $date, displayedComponents: .date).labelsHidden().opacity(0.011)
                        }
                } else {
                    text
                }
            }
            Divider()
            field("Note") { TextField("Add a note", text: $note, axis: .vertical).textFieldStyle(.plain).lineLimit(compact ? 1 : 4) }
            Divider()
            field("Tags") { TagsField(tags: $tags, compact: compact) }
        }
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 2 : 0)
        .modifier(DetailCard(radius: radius, bordered: compact))
    }

    private var categoryText: String {
        if drafts.count > 1 {
            return drafts.compactMap { draft in session.categories.first { $0.id == draft.categoryId }?.displayName }
                .joined(separator: ", ")
        }
        return session.categories.first { $0.id == categoryId }?.displayName ?? "Needs a category"
    }

    private var accountText: String { session.accounts.first { $0.id == accountId }?.displayName ?? transaction.account }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label).foregroundStyle(Theme.secondary).frame(width: labelWidth, alignment: .leading)
            HStack(spacing: 8) { content() }.fontWeight(.medium).frame(maxWidth: .infinity, alignment: .leading)
            if !compact {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary.opacity(0.6)).accessibilityHidden(true)
            }
        }
        .frame(minHeight: rowHeight)
    }

    // MARK: Rule and similar

    private var rule: (name: String, category: Category)? {
        guard transaction.isSimple, !payee.isEmpty else { return nil }
        guard let category = session.categories.first(where: { $0.id == categoryId }) else { return nil }
        return (payee, category)
    }

    @ViewBuilder
    private var suggestions: some View {
        let ruleRow = rule.map { rule in
            RuleRow(name: rule.name, category: rule.category.displayName, compact: compact, created: ruleCreated) {
                Task { await createRule(name: rule.name, categoryId: rule.category.id) }
            }
        }
        let similarRow = similar.map { SimilarRow(payee: payee, stats: $0, currency: transaction.currency, compact: compact) }
        if compact {
            if let ruleRow { ruleRow.padding(.horizontal, 12).padding(.vertical, 10).modifier(DetailCard(radius: radius, bordered: true)) }
            if let similarRow { similarRow.padding(.horizontal, 2) }
        } else if ruleRow != nil || similarRow != nil {
            VStack(spacing: 0) {
                if let ruleRow { ruleRow.padding(.vertical, 12) }
                if ruleRow != nil && similarRow != nil { Divider() }
                if let similarRow { similarRow.padding(.vertical, 13) }
            }
            .padding(.horizontal, 16)
            .modifier(DetailCard(radius: radius, bordered: false))
        }
    }

}

// MARK: Actions

extension TransactionDetailView {

    private func loadExtras() async {
        let api = session.api
        if transaction.isSimple, let parts = try? await api.splits(transactionId: transaction.id) {
            drafts = parts.map { SplitDraft(categoryId: $0.categoryId, amount: abs($0.amount), note: $0.note ?? $0.description ?? "") }
            savedDrafts = drafts
        }
        if let name = transaction.payee, !name.isEmpty {
            let year = String(transaction.date.prefix(4))
            let query = TransactionQuery(search: name, startDate: "\(year)-01-01", endDate: "\(year)-12-31", limit: 500)
            if let page = try? await api.transactions(query) {
                let same = page.data.filter { $0.payee == name && $0.currency == transaction.currency && $0.isSimple }
                if same.count > 1 { similar = (same.count, same.map { abs($0.amount) }.reduce(0, +) / Double(same.count)) }
            }
        }
    }

    private func save() async {
        var input = TransactionInput(id: transaction.id)
        if payee != (transaction.payee ?? "") { input.payee = payee }
        if note != (transaction.note ?? "") { input.note = note }
        if tags != (transaction.tags ?? "") { input.tags = tags }
        if transaction.isSimple {
            if categoryId != transaction.categoryId { input.categoryId = categoryId }
            if accountId != transaction.accountId { input.accountId = accountId }
            if date != transaction.day { input.date = APIDate.string(date) }
        }
        await run { try await session.api.updateTransaction(input) }
    }

    private func saveSplits() async {
        let parts = SplitDraft.inputs(drafts, total: transaction.amount)
        await run { try await session.api.saveSplits(transactionId: transaction.id, splits: parts) }
        if error == nil { savedDrafts = drafts }
    }

    private func clearSplits() async {
        await run { try await session.api.deleteSplits(transactionId: transaction.id) }
        if error == nil {
            drafts = []
            savedDrafts = []
        }
    }

    private func createRule(name: String, categoryId: Int) async {
        let rule = RuleInput(
            name: name, conditions: .init(all: [.init(field: "payee", op: "contains", value: .text(name))]),
            actions: [.init(kind: "set_category", categoryId: categoryId)]
        )
        do {
            try await session.api.createRule(rule)
            ruleCreated = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete() async {
        await run { try await session.api.deleteTransaction(id: transaction.id) }
        if error == nil && !embedded { dismiss() }
    }

    private func run(_ work: () async throws -> some Any) async {
        saving = true
        defer { saving = false }
        do {
            _ = try await work()
            error = nil
            onChange()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
