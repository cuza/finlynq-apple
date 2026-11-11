#if os(macOS)
import SwiftUI

// MARK: Rules editor

/// The rules as a table, in priority order, with add, remove and edit (double-click a row).
struct RulesEditor: View {
    @Environment(Session.self) private var session
    @State private var rules: [Rule]?
    @State private var failed = false
    @State private var selection: Rule.ID?
    @State private var editing: RuleDraft?
    @State private var error: String?
    @State private var attempt = 0
    @State private var removing: Rule?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let rules {
                VStack(spacing: 0) {
                    table(rules)
                    HStack(spacing: 0) {
                        barButton("plus", "Add rule") { editing = RuleDraft() }
                        barButton("minus", "Remove rule") { removing = rules.first { $0.id == selection } }
                            .disabled(selection == nil)
                        barButton("pencil", "Edit rule") {
                            if let rule = rules.first(where: { $0.id == selection }) { editing = RuleDraft(rule) }
                        }
                            .disabled(selection == nil)
                        Spacer()
                    }
                    .background(Theme.toolbar)
                    .overlay(alignment: .top) { Divider() }
                }
                .frame(width: 400, height: 220)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.badge))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if failed {
                InlineError(message: "Couldn't load your rules.") { attempt += 1 }.frame(width: 400)
            } else {
                ProgressView().controlSize(.small)
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(Theme.negative) }
            MacNote("The first rule that matches a new transaction wins. Higher numbers run first.")
        }
        .task(id: "\(session.revision)|\(attempt)") {
            let loaded = await optionalLoad("rules") { try await session.api.rules() }
            rules = loaded.map(RuleText.sorted)
            failed = loaded == nil
        }
        .sheet(item: $editing) { RuleEditorSheet(draft: $0) }
        .confirmationDialog(
            "Remove the rule \"\(removing?.name ?? "")\"?",
            isPresented: Binding { removing != nil } set: { if !$0 { removing = nil } }, titleVisibility: .visible
        ) {
            Button("Remove Rule", role: .destructive) { if let id = removing?.id { Task { await remove(id) } } }
        } message: {
            Text("New transactions won't be categorized by it anymore.")
        }
    }

    private func table(_ rules: [Rule]) -> some View {
        Table(rules, selection: $selection) {
            TableColumn("On") { rule in
                Toggle("On", isOn: Binding { rule.isActive } set: { value in Task { await setActive(rule, value) } }).labelsHidden()
            }
            .width(28)
            TableColumn("Name", value: \.name)
            TableColumn("When and then") { rule in
                Text(RuleText.summary(rule, categories: session.categories, accounts: session.accounts)).foregroundStyle(Theme.secondary)
            }
        }
        .contextMenu(forSelectionType: Rule.ID.self) { _ in } primaryAction: { ids in
            if let rule = rules.first(where: { ids.contains($0.id) }) { editing = RuleDraft(rule) }
        }
    }

    private func barButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 26, height: 22) }
            .buttonStyle(.borderless)
            .overlay(alignment: .trailing) { Divider() }
            .accessibilityLabel(label)
            .help(label)
    }

    private func setActive(_ rule: Rule, _ value: Bool) async {
        do {
            try await session.api.setRuleActive(id: rule.id, isActive: value)
            error = nil
            await session.didSave()
        } catch {
            self.error = "Couldn't change \(rule.name). \(error.localizedDescription)"
        }
    }

    private func remove(_ id: Int) async {
        do {
            try await session.api.deleteRule(id: id)
            selection = nil
            error = nil
            await session.didSave()
        } catch {
            self.error = "Couldn't remove the rule. \(error.localizedDescription)"
        }
    }
}

/// A rule being edited or created.
struct RuleDraft: Identifiable {
    let id: Int?
    var name = ""
    var priority = 100
    var isActive = true
    var conditions = [RuleCondition(field: "payee", op: "contains", value: .text(""))]
    var actions = [RuleAction(kind: "set_category")]

    init() { id = nil }

    init(_ rule: Rule) {
        id = rule.id
        name = rule.name
        priority = rule.priority
        isActive = rule.isActive
        conditions = rule.conditions.all
        actions = rule.actions
    }

    var input: RuleInput {
        RuleInput(name: name.trimmingCharacters(in: .whitespaces), conditions: .init(all: conditions), actions: actions,
                  priority: priority, isActive: isActive, id: id)
    }

    /// The fields and actions this editor can change. Others (dates, tickers, investment actions) are kept as they are.
    static let editableFields = ["payee", "note", "tags", "amount", "currency", "account"]
    static let editableActions = ["set_category", "set_tags", "rename_payee", "set_account"]

    static func ops(for field: String) -> [(String, String)] {
        switch field {
        case "amount": [("gt", "is over"), ("lt", "is under"), ("eq", "is"), ("between", "is between")]
        case "currency", "account": [("is", "is"), ("is_not", "isn't")]
        default: [("contains", "contains"), ("exact", "is"), ("regex", "matches pattern")]
        }
    }

    /// A save the server would accept: a name, and every editable condition and action filled in.
    var isComplete: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, !conditions.isEmpty, !actions.isEmpty else { return false }
        let conditionsOK = conditions.allSatisfy { condition in
            switch (condition.field, condition.op) {
            case ("amount", "between"): condition.min != nil && condition.max != nil
            case ("amount", _): if case .number = condition.value { true } else { false }
            case ("account", _): condition.accountId != nil
            case ("payee", _), ("note", _), ("tags", _), ("currency", _):
                if case .text(let text) = condition.value { !text.isEmpty } else { false }
            default: true
            }
        }
        let actionsOK = actions.allSatisfy { action in
            switch action.kind {
            case "set_category": action.categoryId != nil
            case "set_tags": !(action.tags ?? "").isEmpty
            case "rename_payee": !(action.to ?? "").isEmpty
            case "set_account": action.accountId != nil
            default: true
            }
        }
        return conditionsOK && actionsOK
    }
}

private struct RuleEditorSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State var draft: RuleDraft
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                    TextField("Priority", value: $draft.priority, format: .number)
                    Toggle("On", isOn: $draft.isActive)
                } footer: {
                    Text("Higher numbers run first.").foregroundStyle(Theme.secondary)
                }
                Section("When all of these match") {
                    ForEach(draft.conditions.indices, id: \.self) { index in conditionRow(index) }
                    Button("Add Condition") { draft.conditions.append(RuleCondition(field: "payee", op: "contains", value: .text(""))) }
                        .disabled(draft.conditions.count >= 20)
                }
                Section("Then") {
                    ForEach(draft.actions.indices, id: \.self) { index in actionRow(index) }
                    Button("Add Action") { draft.actions.append(RuleAction(kind: "set_category")) }.disabled(draft.actions.count >= 10)
                }
                if let error { Text(error).foregroundStyle(Theme.negative) }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(draft.id == nil ? "Add Rule" : "Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isComplete || saving)
            }
            .padding(16)
        }
        .frame(width: 560, height: 520)
    }

    // MARK: Rows

    @ViewBuilder
    private func conditionRow(_ index: Int) -> some View {
        let condition = draft.conditions[index]
        HStack {
            if RuleDraft.editableFields.contains(condition.field) {
                Picker("Field", selection: fieldBinding(index)) {
                    Text("Payee").tag("payee")
                    Text("Note").tag("note")
                    Text("Tags").tag("tags")
                    Text("Amount").tag("amount")
                    Text("Currency").tag("currency")
                    Text("Account").tag("account")
                }
                .labelsHidden().frame(width: 100)
                Picker("Test", selection: $draft.conditions[index].op) {
                    ForEach(RuleDraft.ops(for: condition.field), id: \.0) { Text($0.1).tag($0.0) }
                }
                .labelsHidden().frame(width: 120)
                conditionValue(index)
            } else {
                Text(RuleText.condition(condition, accounts: session.accounts)).foregroundStyle(Theme.secondary)
                Spacer()
            }
            Button { draft.conditions.remove(at: index) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).disabled(draft.conditions.count == 1).accessibilityLabel("Remove condition")
        }
    }

    @ViewBuilder
    private func conditionValue(_ index: Int) -> some View {
        let condition = draft.conditions[index]
        switch (condition.field, condition.op) {
        case ("amount", "between"):
            TextField("Min", value: $draft.conditions[index].min, format: .number)
            TextField("Max", value: $draft.conditions[index].max, format: .number)
        case ("amount", _):
            TextField("Amount", value: numberBinding(index), format: .number)
        case ("account", _):
            Picker("Account", selection: $draft.conditions[index].accountId) {
                Text("Choose…").tag(Int?.none)
                ForEach(session.accounts) { Text($0.displayName).tag(Int?.some($0.id)) }
            }
            .labelsHidden()
        default:
            TextField(condition.field == "currency" ? "USD" : "Text", text: textBinding(index))
        }
    }

    @ViewBuilder
    private func actionRow(_ index: Int) -> some View {
        let action = draft.actions[index]
        HStack {
            if RuleDraft.editableActions.contains(action.kind) {
                Picker("Action", selection: $draft.actions[index].kind) {
                    Text("Set category").tag("set_category")
                    Text("Set tags").tag("set_tags")
                    Text("Rename payee").tag("rename_payee")
                    Text("Move to account").tag("set_account")
                }
                .labelsHidden().frame(width: 150)
                switch action.kind {
                case "set_category":
                    Picker("Category", selection: $draft.actions[index].categoryId) {
                        Text("Choose…").tag(Int?.none)
                        ForEach(session.categories) { Text($0.displayName).tag(Int?.some($0.id)) }
                    }
                    .labelsHidden()
                case "set_tags":
                    TextField("Tags, separated by commas", text: optionalText($draft.actions[index].tags))
                case "rename_payee":
                    TextField("New payee", text: optionalText($draft.actions[index].to))
                default:
                    Picker("Account", selection: $draft.actions[index].accountId) {
                        Text("Choose…").tag(Int?.none)
                        ForEach(session.accounts) { Text($0.displayName).tag(Int?.some($0.id)) }
                    }
                    .labelsHidden()
                }
            } else {
                Text(RuleText.action(action, categories: session.categories, accounts: session.accounts)).foregroundStyle(Theme.secondary)
                Spacer()
            }
            Button { draft.actions.remove(at: index) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).disabled(draft.actions.count == 1).accessibilityLabel("Remove action")
        }
    }

    // MARK: Bindings

    /// Changing the field resets the test and value to ones that field takes.
    private func fieldBinding(_ index: Int) -> Binding<String> {
        Binding { draft.conditions[index].field } set: { field in
            let test = RuleDraft.ops(for: field)[0].0
            let value: RuleValue? = field == "amount" || field == "account" ? nil : .text("")
            draft.conditions[index] = RuleCondition(field: field, op: test, value: value)
        }
    }

    private func textBinding(_ index: Int) -> Binding<String> {
        Binding {
            if case .text(let text) = draft.conditions[index].value { text } else { "" }
        } set: { text in
            let field = draft.conditions[index].field
            draft.conditions[index].value = .text(field == "currency" ? text.uppercased() : text)
        }
    }

    private func numberBinding(_ index: Int) -> Binding<Double?> {
        Binding {
            if case .number(let number) = draft.conditions[index].value { number } else { nil }
        } set: { number in
            draft.conditions[index].value = number.map(RuleValue.number)
        }
    }

    private func optionalText(_ binding: Binding<String?>) -> Binding<String> {
        Binding { binding.wrappedValue ?? "" } set: { binding.wrappedValue = $0 }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            if draft.id == nil { try await session.api.createRule(draft.input) } else { try await session.api.updateRule(draft.input) }
            await session.didSave()
            dismiss()
        } catch {
            self.error = "Couldn't save the rule. \(error.localizedDescription)"
        }
    }
}
#endif
