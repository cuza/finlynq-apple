import SwiftUI

#if os(macOS)
/// The Categories tab of Mac Settings, per MacCategories.dc.html: the categories as a table with + and − below it.
/// Double-click a row to edit it.
struct MacCategoriesTab: View {
    @Environment(Session.self) private var session
    @State private var selection: Category.ID?
    @State private var editing: CategoryDraft?
    @State private var removing: Category?
    @State private var error: String?
    #if DEBUG
    @State private var debugOpened = false
    #endif

    var body: some View {
        let selected = session.categories.first { $0.id == selection }
        let categories = session.categories.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                Table(categories, selection: $selection) {
                    TableColumn("Name") { category in
                        HStack(spacing: 8) {
                            CategoryIconTile(name: category.name, type: category.type, size: 20)
                            Text(category.displayName)
                        }
                    }
                    TableColumn("Group") { Text(CategoryDraft.groupName($0.group)) }.width(min: 90, ideal: 150)
                    TableColumn("Type") { Text(CategoriesListView.kind($0.type)) }.width(min: 70, ideal: 110)
                }
                .contextMenu(forSelectionType: Category.ID.self) { ids in
                    if let category = session.categories.first(where: { ids.contains($0.id) }) {
                        Button("Edit…") { open(CategoryDraft(category)) }
                    }
                } primaryAction: { ids in
                    if let category = session.categories.first(where: { ids.contains($0.id) }) { open(CategoryDraft(category)) }
                }
                HStack(spacing: 0) {
                    Button("Add category", systemImage: "plus") { open(CategoryDraft(groups: CategoryDraft.groups(session.categories))) }
                        .frame(width: 26, height: 22)
                        .disabled(session.isDemo)
                    Divider().frame(height: 22)
                    Button("Remove category", systemImage: "minus") { error = nil; removing = selected }
                        .frame(width: 26, height: 22)
                        .disabled(selected == nil || session.isDemo)
                    Divider().frame(height: 22)
                    Spacer()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .background(Theme.toolbar)
                .overlay(alignment: .top) { Divider() }
            }
            .frame(height: 340)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.badge))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.negative).fixedSize(horizontal: false, vertical: true)
            }
            MacNote(session.isDemo ? "The shared demo's categories can't change."
                                   : "Double-click a category to edit it. Icons come from category names.")
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .onChange(of: selection) { error = nil }
        .sheet(item: $editing) { CategoryEditorSheet(draft: $0) }
        .confirmationDialog(
            "Remove the category \"\(removing?.displayName ?? "")\"?",
            isPresented: Binding { removing != nil } set: { if !$0 { removing = nil } }, titleVisibility: .visible, presenting: removing
        ) { category in
            Button("Remove category", role: .destructive) { Task { await remove(category) } }
        } message: { _ in
            Text("A category that transactions, budgets or rules still use can't be removed.")
        }
        #if DEBUG
        .onChange(of: session.categories, initial: true) {
            guard !debugOpened, let id = DebugRoute.current?.editCategory,
                  let category = session.categories.first(where: { $0.id == id }) else { return }
            debugOpened = true
            selection = id
            open(CategoryDraft(category))
        }
        #endif
    }

    private func open(_ draft: CategoryDraft) {
        error = nil
        editing = draft
    }

    private func remove(_ category: Category) async {
        do {
            try await session.deleteCategory(id: category.id)
            selection = nil
            error = nil
        } catch {
            self.error = CategoryDraft.message(for: error, doing: "remove \(category.displayName)")
        }
    }
}
#endif
