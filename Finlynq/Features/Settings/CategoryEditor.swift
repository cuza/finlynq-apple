import SwiftUI

/// The body of `POST` and `PUT /api/categories`. `id` is nil for a new category. `note` is always a string,
/// because the server takes a string but not null, so clearing a note sends "".
nonisolated struct CategoryInput: Encodable, Equatable {
    var id: Int?
    var name: String
    var type: String
    var group: String
    var note: String
}

/// A category being added or edited.
struct CategoryDraft: Identifiable {
    let id: Int?
    var name = ""
    /// The server's code: E expense, I income, R transfer.
    var type = "E"
    /// One of the existing groups, or nil for a new group typed into `newGroup`.
    var group: String?
    var newGroup = ""
    var note = ""

    /// A new expense category in the first group, or in a new group when there are none yet.
    init(groups: [String]) {
        id = nil
        group = groups.first
    }

    init(_ category: Category) {
        id = category.id
        name = category.name ?? ""
        type = category.type
        group = category.group
        note = category.note ?? ""
    }

    /// A name, and a name for the group when it's a new one.
    var isValid: Bool { !Self.trim(name).isEmpty && (group != nil || !Self.trim(newGroup).isEmpty) }

    var input: CategoryInput {
        CategoryInput(id: id, name: Self.trim(name), type: type, group: group ?? Self.trim(newGroup), note: Self.trim(note))
    }

    static let types = [("E", "Expense"), ("I", "Income"), ("R", "Transfer")]

    static func groups(_ categories: [Category]) -> [String] { Set(categories.map(\.group)).sorted() }

    /// The label for a group. Categories without one sit under "Other".
    static func groupName(_ group: String) -> String { group.isEmpty ? "Other" : group }

    /// "15 categories in 6 groups", under the list's title.
    static func summary(_ categories: [Category]) -> String {
        let groups = Set(categories.map(\.group)).count
        return "\(categories.count) \(categories.count == 1 ? "category" : "categories") in \(groups) \(groups == 1 ? "group" : "groups")"
    }

    /// A conflict's message as the server wrote it (a taken name, or what still uses the category); otherwise
    /// "Couldn't <action>." and the error.
    static func message(for error: Error, doing action: String) -> String {
        if case APIError.server(409, let message, _) = error { return message }
        return "Couldn't \(action). \(error.localizedDescription)"
    }

    static func isConflict(_ error: Error) -> Bool {
        if case APIError.server(409, _, _) = error { true } else { false }
    }

    private static func trim(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Session {
    /// Adds or updates the category, then reloads the categories every picker uses.
    func save(_ draft: CategoryDraft) async throws {
        guard !isDemo else { return }
        if draft.id == nil { try await api.createCategory(draft.input) } else { try await api.updateCategory(draft.input) }
        await didSave()
    }

    func deleteCategory(id: Int) async throws {
        guard !isDemo else { return }
        try await api.deleteCategory(id: id)
        await didSave()
    }
}

/// A delete the server refused or that failed. `blocked` is the server's 409: records still use the category.
struct CategoryRefusal {
    let id: Int
    let message: String
    let blocked: Bool
}

/// Activity filtered to a category, opened on `month`.
struct CategoryTransactions: Hashable {
    let id: Int
    let month: Date?
}

/// A category's icon in a tinted tile.
struct CategoryIconTile: View {
    let name: String?
    let type: String
    var size: CGFloat = 36

    var body: some View {
        let icon = Icons.category(name, type: type)
        IconTile(symbol: icon.0, tint: icon.1, background: icon.1.opacity(0.14), size: size)
    }
}

// MARK: List (iPhone and iPad)

/// The categories by group. Tap one to edit it, swipe to delete it, or add one from the toolbar.
struct CategoriesListView: View {
    @Environment(Session.self) private var session
    @State private var reloading = false
    @State private var editing: CategoryDraft?
    @State private var deleting: Category?
    @State private var refusal: CategoryRefusal?
    /// The category whose transactions to push once the editor sheet has closed.
    @State private var pendingTransactions: Int?
    @State private var transactionsFor: CategoryTransactions?
    #if DEBUG
    @State private var debugOpened = false
    #endif

    var body: some View {
        let groups = Dictionary(grouping: session.categories, by: \.group).sorted { $0.key < $1.key }
        Group {
            if groups.isEmpty {
                ContentUnavailableView {
                    Label("No categories", systemImage: "square.grid.2x2")
                } description: {
                    Text("Add categories to sort your spending and income.")
                } actions: {
                    Button("Reload") { Task { reloading = true; await session.refreshLookups(); reloading = false } }
                        .disabled(reloading)
                }
            } else {
                List {
                    Text(CategoryDraft.summary(session.categories))
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                    ForEach(groups, id: \.key) { group, categories in
                        Section {
                            ForEach(categories) { row($0) }
                        } header: {
                            HStack {
                                Text(CategoryDraft.groupName(group))
                                Spacer()
                                Text("\(categories.count)").monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add category", systemImage: "plus") {
                    editing = CategoryDraft(groups: CategoryDraft.groups(session.categories))
                }
                .macTitleAndIcon()
                .disabled(session.isDemo)
            }
        }
        .refreshable { await session.refreshLookups() }
        .sheet(item: $editing, onDismiss: showPendingTransactions) { draft in
            CategoryEditorSheet(draft: draft, refusal: debugRefusal(draft)) { pendingTransactions = $0 }
        }
        .navigationDestination(item: $transactionsFor) {
            ActivityView(categoryId: $0.id, month: $0.month).measuresLayoutWidth()
        }
        .confirmationDialog(
            "Delete \(deleting?.displayName ?? "the category")?",
            isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } }, titleVisibility: .visible, presenting: deleting
        ) { category in
            Button("Delete category", role: .destructive) { Task { await delete(category) } }
        } message: { _ in
            Text("A category that transactions, budgets or rules still use can't be deleted.")
        }
        .alert(
            "Category not deleted", isPresented: Binding { refusal != nil } set: { if !$0 { refusal = nil } }, presenting: refusal
        ) { refusal in
            if refusal.blocked { Button("Show transactions") { Task { await showTransactions(refusal.id) } } }
            Button("OK", role: .cancel) {}
        } message: { refusal in
            Text(refusal.message)
        }
        #if DEBUG
        .onChange(of: session.categories, initial: true) {
            // Opens the editor for the screenshot route once, not again after a save reloads the categories.
            guard !debugOpened, DebugRoute.current?.name.hasPrefix("settings-") == false, let id = DebugRoute.current?.editCategory,
                  let category = session.categories.first(where: { $0.id == id }) else { return }
            debugOpened = true
            editing = CategoryDraft(category)
        }
        #endif
    }

    private func row(_ category: Category) -> some View {
        Button { editing = CategoryDraft(category) } label: {
            HStack(spacing: 12) {
                CategoryIconTile(name: category.name, type: category.type)
                Text(category.displayName).foregroundStyle(Theme.text).lineLimit(1)
                Spacer(minLength: 8)
                switch category.type {
                case "I": Chip(text: "Income", tint: Theme.positive, background: Theme.positiveTint)
                case "R": Chip(text: "Transfer", tint: Theme.secondary, background: Theme.fill)
                default: EmptyView()
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary.opacity(0.6))
            }
        }
        .swipeActions {
            if !session.isDemo {
                Button("Delete", systemImage: "trash") { deleting = category }.tint(Theme.negative)
            }
        }
    }

    private func showPendingTransactions() {
        guard let id = pendingTransactions else { return }
        pendingTransactions = nil
        Task { await showTransactions(id) }
    }

    /// Opens Activity filtered to the category, on the month of its newest transaction (this month if that fails).
    private func showTransactions(_ id: Int) async {
        let month = try? await session.api.newestTransactionMonth(categoryId: id)
        transactionsFor = CategoryTransactions(id: id, month: month)
    }

    private func delete(_ category: Category) async {
        do {
            try await session.deleteCategory(id: category.id)
        } catch {
            refusal = CategoryRefusal(id: category.id, message: CategoryDraft.message(for: error, doing: "delete \(category.displayName)"),
                                      blocked: CategoryDraft.isConflict(error))
        }
    }

    /// The screenshot route `categories-refused:<id>` opens the editor as if the server had refused the delete.
    private func debugRefusal(_ draft: CategoryDraft) -> CategoryRefusal? {
        #if DEBUG
        if let id = draft.id, DebugRoute.current?.showsRefusal == true {
            return CategoryRefusal(id: id, message: Fixtures.categoryInUse, blocked: true)
        }
        #endif
        return nil
    }

    static func kind(_ type: String) -> String {
        CategoryDraft.types.first { $0.0 == type }?.1 ?? type
    }
}

// MARK: Editor

/// Adds or edits one category: name, group (an existing one or a new one), type and note. Editing also offers
/// Delete. A refused delete shows the server's reason above Delete, with a link to the category's transactions.
struct CategoryEditorSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CategoryDraft
    @State private var saving = false
    @State private var confirmingDelete = false
    @State private var error: String?
    @State private var refusal: CategoryRefusal?
    /// Closes the editor and shows the category's transactions. Nil where that can't be shown (Mac Settings).
    let showTransactions: ((Int) -> Void)?

    init(draft: CategoryDraft, refusal: CategoryRefusal? = nil, showTransactions: ((Int) -> Void)? = nil) {
        _draft = State(initialValue: draft)
        _refusal = State(initialValue: refusal)
        self.showTransactions = showTransactions
    }

    private var title: String { draft.id == nil ? "New category" : "Edit category" }

    /// The name the category is saved under, for the delete confirmation.
    private var storedName: String {
        session.categories.first { $0.id == draft.id }?.displayName ?? "this category"
    }

    var body: some View {
        content
            .confirmationDialog("Delete \(storedName)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete category", role: .destructive) { Task { await delete() } }
            } message: {
                Text("A category that transactions, budgets or rules still use can't be deleted.")
            }
            .interactiveDismissDisabled(saving)
    }

    #if os(macOS)
    // Per MacCategories.dc.html: labels beside the fields, "New group…" at the bottom of the Group menu,
    // Delete on the left of the buttons.
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            Form {
                LabeledContent("Name:") {
                    HStack(spacing: 8) {
                        CategoryIconTile(name: draft.name, type: draft.type, size: 26)
                        TextField("Name", text: $draft.name).labelsHidden()
                    }
                }
                Picker("Type:", selection: $draft.type) {
                    ForEach(CategoryDraft.types, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented).fixedSize()
                Picker("Group:", selection: $draft.group) {
                    ForEach(CategoryDraft.groups(session.categories), id: \.self) {
                        Text(CategoryDraft.groupName($0)).tag(String?.some($0))
                    }
                    Divider()
                    Text("New group…").tag(String?.none)
                }
                .fixedSize()
                .tint(Theme.text)
                if draft.group == nil { TextField("New group:", text: $draft.newGroup, prompt: Text("Group name")) }
                MacNote("Pick \"New group…\" at the bottom of the menu to add one.")
                LabeledContent("Note:") {
                    TextField("Note", text: $draft.note, axis: .vertical).labelsHidden().lineLimit(2...4)
                }
            }
            .formStyle(.columns)
            if let refusal {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(refusal.message)
                        if refusal.blocked { Text("Find them in Activity by filtering on this category.").foregroundStyle(Theme.secondary) }
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.negative)
                }
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.negative).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if draft.id != nil {
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Text("Delete category…").foregroundStyle(Theme.negative)
                    }
                    .disabled(saving || session.isDemo)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isValid || saving || session.isDemo)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
    #else
    private var content: some View {
        let groups = CategoryDraft.groups(session.categories)
        return NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        CategoryIconTile(name: draft.name, type: draft.type)
                        Text("Name").fontWeight(.semibold)
                        TextField("Category name", text: $draft.name)
                    }
                    if draft.group == nil {
                        LabeledContent("Group") {
                            TextField("New group name", text: $draft.newGroup).multilineTextAlignment(.trailing)
                        }
                        if let first = groups.first {
                            Button("Choose an existing group", systemImage: "list.bullet") { draft.group = first }
                        }
                    } else {
                        Picker("Group", selection: $draft.group) {
                            ForEach(groups, id: \.self) { Text(CategoryDraft.groupName($0)).tag(String?.some($0)) }
                        }
                        .tint(Theme.secondary)
                        Button("New group…", systemImage: "plus") { draft.group = nil }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let error { Text(error).foregroundStyle(Theme.negative) }
                        if session.isDemo { Text("The shared demo's categories can't change.") }
                        Text("Icon comes from the name.")
                    }
                }
                Section("Type") {
                    Picker("Type", selection: $draft.type) {
                        ForEach(CategoryDraft.types, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section("Note") {
                    TextField("Note", text: $draft.note, axis: .vertical).lineLimit(2...4)
                }
                if draft.id != nil { deleteSection }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(!draft.isValid || saving || session.isDemo)
                }
            }
        }
    }

    /// Delete, and above it the reason the server refused the last try.
    private var deleteSection: some View {
        Section {
            if let refusal {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.negative)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Category not deleted").fontWeight(.semibold).foregroundStyle(Theme.negative)
                        Text(refusal.message).foregroundStyle(Theme.text)
                    }
                }
                if refusal.blocked, let showTransactions {
                    Button {
                        showTransactions(refusal.id)
                        dismiss()
                    } label: {
                        HStack {
                            Label("Show transactions", systemImage: "line.3.horizontal")
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.secondary.opacity(0.6))
                        }
                    }
                }
            }
            Button(role: .destructive) { confirmingDelete = true } label: {
                Text("Delete category").foregroundStyle(Theme.negative).frame(maxWidth: .infinity)
            }
            .disabled(saving || session.isDemo)
        }
    }
    #endif

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await session.save(draft)
            dismiss()
        } catch {
            self.error = CategoryDraft.message(for: error, doing: "save the category")
        }
    }

    private func delete() async {
        guard let id = draft.id else { return }
        saving = true
        defer { saving = false }
        do {
            try await session.deleteCategory(id: id)
            dismiss()
        } catch {
            refusal = CategoryRefusal(id: id, message: CategoryDraft.message(for: error, doing: "delete the category"),
                                      blocked: CategoryDraft.isConflict(error))
        }
    }
}
