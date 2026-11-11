import SwiftUI

/// The display currencies the app offers: the server's built-in list, most used first. The server accepts
/// more (any reportable code), so a currency set on the web that isn't here still shows as the current one.
enum CurrencyList {
    static let codes = [
        "USD", "CAD", "EUR", "GBP", "JPY", "AUD", "CHF", "NZD", "CNY", "HKD", "SGD",
        "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "RON", "TRY", "ILS", "ZAR",
        "INR", "KRW", "THB", "IDR", "MYR", "PHP", "MXN", "BRL", "ARS", "COP", "CLP"
    ]

    static func name(_ code: String) -> String { Locale.current.localizedString(forCurrencyCode: code) ?? code }

    /// The list with `current` first when the list lacks it.
    static func including(_ current: String) -> [String] { codes.contains(current) ? codes : [current] + codes }
}

/// Plain-language summaries of a rule's conditions and actions, for the rule lists.
enum RuleText {
    /// The order the server tries rules in: the highest priority first, then the oldest.
    static func sorted(_ rules: [Rule]) -> [Rule] {
        rules.sorted { ($1.priority, $0.id) < ($0.priority, $1.id) }
    }

    static func summary(_ rule: Rule, categories: [Category], accounts: [Account]) -> String {
        let when = rule.conditions.all.map { condition($0, accounts: accounts) }.joined(separator: " and ")
        let then = rule.actions.map { action($0, categories: categories, accounts: accounts) }.joined(separator: ", ")
        return "When \(when), \(then)"
    }

    static func condition(_ condition: RuleCondition, accounts: [Account]) -> String {
        let field = condition.field.replacingOccurrences(of: "_", with: " ")
        let value = condition.value.map(text) ?? ""
        if condition.field == "account" {
            let name = accounts.first { $0.id == condition.accountId }?.displayName ?? "an account"
            return "account \(condition.op == "is_not" ? "isn't" : "is") \(name)"
        }
        if condition.op == "between" {
            return "\(field) is between \(condition.min.map(number) ?? "?") and \(condition.max.map(number) ?? "?")"
        }
        let tests = [
            "contains": "contains \"\(value)\"", "exact": "is \"\(value)\"", "regex": "matches \(value)",
            "gt": "is over \(value)", "lt": "is under \(value)", "eq": "is \(value)", "is": "is \(value)", "is_not": "isn't \(value)"
        ]
        return "\(field) \(tests[condition.op] ?? "\(condition.op.replacingOccurrences(of: "_", with: " ")) \(value)")"
    }

    static func action(_ action: RuleAction, categories: [Category], accounts: [Account]) -> String {
        switch action.kind {
        case "set_category":
            return "categorize as \(categories.first { $0.id == action.categoryId }?.displayName ?? "a category")"
        case "set_tags": return "tag \(action.tags ?? "")"
        case "rename_payee": return "rename to \"\(action.to ?? "")\""
        case "set_account": return "move to \(accounts.first { $0.id == action.accountId }?.displayName ?? "an account")"
        case "set_entered_currency": return "set currency to \(action.currency ?? "")"
        case "create_transfer": return "make a transfer"
        default: return action.kind.replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func text(_ value: RuleValue) -> String {
        switch value {
        case .text(let text): text
        case .number(let number): Self.number(number)
        }
    }

    private static func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
}

// MARK: Display currency

/// Picks the display currency. Saving reloads every screen in the new currency.
struct CurrencyPickerView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var saving: String?
    @State private var error: String?

    var body: some View {
        let codes = CurrencyList.including(session.currency)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Totals, budgets and reports use this currency.").font(.footnote).foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 4)
                if let error { InlineError(message: error) { self.error = nil } }
                VStack(spacing: 0) {
                    ForEach(codes, id: \.self) { code in
                        Button { Task { await pick(code) } } label: { row(code) }
                        if code != codes.last { Divider() }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .settingsCard()
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Theme.page)
        .navigationTitle("Display currency")
        .disabled(saving != nil)
    }

    private func row(_ code: String) -> some View {
        HStack {
            Text(code).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).frame(width: 48, alignment: .leading)
            Text(CurrencyList.name(code)).font(.subheadline).foregroundStyle(Theme.secondary)
            Spacer()
            if saving == code {
                ProgressView().controlSize(.small)
            } else if code == session.currency {
                Image(systemName: "checkmark").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityAddTraits(code == session.currency ? .isSelected : [])
    }

    private func pick(_ code: String) async {
        guard code != session.currency, !session.isDemo else { return dismiss() }
        saving = code
        defer { saving = nil }
        do {
            try await session.setDisplayCurrency(code)
            dismiss()
        } catch {
            self.error = "Couldn't change the currency. \(error.localizedDescription)"
        }
    }
}

// MARK: Rules

/// The auto-categorize rules with an on/off switch each (iPhone and iPad). The Mac edits them in full.
struct RulesListView: View {
    @Environment(Session.self) private var session
    @State private var attempt = 0
    /// Switches the user flipped, shown before the reload confirms them.
    @State private var active: [Int: Bool] = [:]
    @State private var error: String?

    var body: some View {
        Reloader(id: "\(session.revision)|\(attempt)", source: "rules") {
            RuleText.sorted(try await session.api.rules())
        } content: { rules in
            if rules.isEmpty {
                EmptyState(
                    title: "No rules yet",
                    message: "Rules categorize new transactions as they come in. Make one from a transaction's category.",
                    symbol: "slider.horizontal.3"
                )
            } else {
                list(rules)
            }
        }
        .background(Theme.page)
        .navigationTitle("Auto-categorize rules")
    }

    private func list(_ rules: [Rule]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("The first rule that matches a new transaction wins. Higher numbers run first.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 4)
                if let error { InlineError(message: error) { self.error = nil; attempt += 1 } }
                VStack(spacing: 0) {
                    ForEach(rules) { rule in
                        row(rule)
                        if rule.id != rules.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 14)
                .settingsCard()
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    private func row(_ rule: Rule) -> some View {
        let isOn = Binding { active[rule.id] ?? rule.isActive } set: { value in Task { await setActive(rule, value) } }
        return Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                Text(RuleText.summary(rule, categories: session.categories, accounts: session.accounts))
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
        .tint(Theme.positiveBar)
        .padding(.vertical, 10)
    }

    private func setActive(_ rule: Rule, _ value: Bool) async {
        active[rule.id] = value
        do {
            try await session.api.setRuleActive(id: rule.id, isActive: value)
            error = nil
            await session.didSave()
        } catch {
            active[rule.id] = !value
            self.error = "Couldn't change \(rule.name). \(error.localizedDescription)"
        }
    }
}

// MARK: Feedback

/// Sends a bug report, idea or question to the Finlynq team (`POST /api/feedback`). Replies show on the web.
struct FeedbackSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var type = "idea"
    @State private var message = ""
    @State private var sending = false
    @State private var error: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Kind", selection: $type) {
                    Text("Bug").tag("bug")
                    Text("Idea").tag("idea")
                    Text("Question").tag("question")
                    Text("Other").tag("other")
                }
                .pickerStyle(.segmented)
                Section {
                    TextField("What's on your mind?", text: $message, axis: .vertical).lineLimit(5...12)
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(Theme.negative)
                    } else {
                        Text("Replies show under Feedback on \(session.api.baseURL.host() ?? "the web").")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Send feedback")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { Task { await send() } }
                        .disabled(sending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Thanks for the feedback", isPresented: $sent) { Button("Done") { dismiss() } }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 300)
        #endif
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
            try await session.api.sendFeedback(type: type, message: String(text.prefix(4000)), appVersion: SettingsData.version)
            error = nil
            sent = true
        } catch {
            self.error = "Couldn't send. \(error.localizedDescription)"
        }
    }
}

// MARK: Delete account

/// Deletes the account for good after the password (and the MFA code, when the account has MFA) and a second
/// confirmation. On success the app signs out and forgets the saved password. Never offered for the shared demo.
struct DeleteAccountSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var code = ""
    @State private var needsCode = false
    @State private var confirming = false
    @State private var deleting = false
    @State private var error: String?

    private var ready: Bool { !password.isEmpty && (!needsCode || code.count == 6) && !deleting }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        let host = session.api.baseURL.host() ?? "the server"
                        Text("This deletes your account on \(host) and every account, transaction, budget and file in it. "
                             + "It can't be undone.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.negative)
                    }
                }
                Section {
                    SecureField("Password", text: $password).textContentType(.password)
                    if needsCode {
                        TextField("6-digit code from your authenticator", text: $code)
                            .textContentType(.oneTimeCode)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                } footer: {
                    if let error { Text(error).foregroundStyle(Theme.negative) }
                }
                Section {
                    Button(role: .destructive) { confirming = true } label: {
                        HStack {
                            Text("Delete account").fontWeight(.semibold)
                            if deleting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(!ready)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Delete account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .confirmationDialog("Delete your account and all its data?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Delete permanently", role: .destructive) { Task { await delete() } }
            }
            .onAppear { needsCode = session.info?.mfaVerified == true }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 320)
        #endif
    }

    private func delete() async {
        deleting = true
        defer { deleting = false }
        do {
            try await session.deleteAccount(password: password, mfaCode: needsCode ? code : nil)
            dismiss()
        } catch {
            // The server asks for a code when the account has MFA, even if this session didn't need one.
            if case APIError.server(_, _, "mfa-required") = error { needsCode = true }
            self.error = error.localizedDescription
        }
    }
}
