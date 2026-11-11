import SwiftUI

/// "New goal" and "Edit goal": name, type, target, an optional target month, linked accounts and a note.
/// The server picks a new goal's currency from its first linked account, else the display currency.
struct GoalEditor: View {
    /// Nil for a new goal.
    let goal: Goal?
    /// Runs after a delete, before the sheet closes. A goal's own page sets a flag here and closes itself once the sheet
    /// is gone, instead of showing "Goal not found". Popping while the sheet is still dismissing can be dropped.
    let onDelete: () -> Void
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var type: String
    @State private var target: String
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var accountIds: Set<Int>
    @State private var note: String
    @State private var saving = false
    @State private var error: String?
    @State private var confirmDelete = false

    static let types = [("savings", "Savings"), ("emergency_fund", "Emergency fund"), ("debt_payoff", "Debt payoff"),
                        ("investment", "Investment")]

    init(goal: Goal? = nil, onDelete: @escaping () -> Void = {}) {
        self.goal = goal
        self.onDelete = onDelete
        let date = goal.flatMap(GoalStyle.deadline)
        _name = State(initialValue: goal?.name ?? "")
        _type = State(initialValue: goal?.type ?? "savings")
        _target = State(initialValue: goal.map { BudgetModel.draft($0.targetAmount) } ?? "")
        _hasDeadline = State(initialValue: date != nil)
        _deadline = State(initialValue: date ?? Calendar(identifier: .gregorian).date(byAdding: .year, value: 1, to: Fixtures.today)
            ?? Fixtures.today)
        _accountIds = State(initialValue: Set(goal?.accountIds ?? goal?.accountId.map { [$0] } ?? []))
        _note = State(initialValue: goal?.note ?? "")
    }

    private var amount: Double? { BudgetModel.amount(target).flatMap { $0 > 0 ? $0 : nil } }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("e.g. Emergency fund"))
                    Picker("Type", selection: $type) { ForEach(Self.types, id: \.0) { Text($0.1).tag($0.0) } }
                    TextField("Target", text: $target, prompt: Text("Target amount"))
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
                    Toggle("Target date", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("By", selection: $deadline, displayedComponents: .date) }
                }
                Section("Linked accounts") {
                    ForEach(session.accounts.filter { !$0.archived }) { account in
                        Toggle(account.displayName, isOn: Binding {
                            accountIds.contains(account.id)
                        } set: { linked in
                            if linked { accountIds.insert(account.id) } else { accountIds.remove(account.id) }
                        })
                    }
                }
                Section { TextField("Note", text: $note, axis: .vertical) }
                if let error { Text(error).foregroundStyle(Theme.negative) }
                if goal != nil {
                    Button("Delete goal", role: .destructive) { confirmDelete = true }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(goal == nil ? "New goal" : "Edit goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(trimmedName.isEmpty || amount == nil || saving)
                }
            }
            .confirmationDialog("Delete this goal?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await delete() } }
            } message: {
                Text("Your accounts and transactions are not affected.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 480)
        #endif
    }

    private var orderedIds: [Int] { Self.ordered(accountIds, accounts: session.accounts.map(\.id)) }

    /// Linked accounts in the order the account list shows them, so the first (which sets a new goal's currency) is
    /// predictable. Ids the list doesn't have (archived, or not loaded yet) come last and are kept, so saving never
    /// unlinks an account the editor didn't show.
    static func ordered(_ ids: Set<Int>, accounts: [Int]) -> [Int] {
        accounts.filter(ids.contains) + ids.subtracting(accounts).sorted()
    }

    private func save() async {
        guard let amount else { return }
        saving = true
        defer { saving = false }
        let date = hasDeadline ? APIDate.string(deadline) : nil
        do {
            if let goal {
                try await session.api.updateGoal(GoalUpdate(
                    id: goal.id, name: trimmedName, type: type, targetAmount: amount, deadline: date ?? "", accountIds: orderedIds,
                    note: note
                ))
            } else {
                try await session.api.createGoal(GoalInput(
                    name: trimmedName, type: type, targetAmount: amount, deadline: date,
                    accountIds: orderedIds.isEmpty ? nil : orderedIds, note: note.isEmpty ? nil : note
                ))
            }
            await session.didSave()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete() async {
        guard let goal else { return }
        do {
            try await session.api.deleteGoal(id: goal.id)
            onDelete()
            dismiss()
            await session.didSave()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
