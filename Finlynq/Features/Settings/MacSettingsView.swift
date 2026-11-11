#if os(macOS)
import SwiftUI

/// The Mac Settings window (Command-comma), per MacSettings.dc.html: General, Accounts & Data, Categories
/// (MacCategories.dc.html), Import and Security tabs with labels right-aligned beside their controls. The Import tab
/// has the full rules editor.
struct MacSettingsView: View {
    @Environment(Session.self) private var session
    @State private var tab = MacSettingsView.firstTab

    private static var firstTab: String {
        #if DEBUG
        if DebugRoute.current?.name.hasPrefix("settings-categories") == true { return "categories" }
        #endif
        return "general"
    }

    var body: some View {
        // Signed out, the tabs (and the loads they start) don't exist.
        if session.state == .signedIn {
            TabView(selection: $tab) {
                Tab("General", systemImage: "gearshape", value: "general") { MacGeneralTab() }
                Tab("Accounts & Data", systemImage: "tray.full", value: "data") { MacDataTab() }
                Tab("Categories", systemImage: "square.grid.2x2", value: "categories") { MacCategoriesTab() }
                Tab("Import", systemImage: "square.and.arrow.down", value: "import") { MacImportTab() }
                Tab("Security", systemImage: "lock", value: "security") { MacSecurityTab() }
            }
            .frame(width: 720)
            .safeAreaInset(edge: .bottom, spacing: 0) { webFooter }
        } else {
            let locked = session.state == .locked
            ContentUnavailableView(locked ? "Unlock Finlynq to change settings" : "Sign in to change settings", systemImage: "lock",
                                   description: Text(locked ? "Settings open once you unlock Finlynq."
                                                            : "Settings open once you're signed in to Finlynq."))
                .frame(width: 720, height: 300)
        }
    }

    private var webFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe").foregroundStyle(Theme.secondary)
            let host = session.api.baseURL.host() ?? "the web"
            Text("API keys, connected apps and backups are on [\(host)](\(session.api.baseURL.absoluteString)).")
                .foregroundStyle(Theme.secondary)
            Spacer()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 20).padding(.vertical, 12)
        .overlay(alignment: .top) { Divider() }
    }
}

/// A caption under a control, like the design's grey 12pt notes.
struct MacNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
}

// MARK: General

private struct MacGeneralTab: View {
    @Environment(Session.self) private var session
    @AppStorage("requireBiometrics") private var requireBiometrics = true
    @AppStorage("lockAfterMinutes") private var lockAfterMinutes = 5
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Form {
            LabeledContent("Display currency:") {
                VStack(alignment: .leading, spacing: 5) {
                    Picker("Display currency", selection: Binding { session.currency } set: { code in Task { await pick(code) } }) {
                        ForEach(CurrencyList.including(session.currency), id: \.self) { Text("\($0), \(CurrencyList.name($0))").tag($0) }
                    }
                    .labelsHidden().frame(width: 200)
                    .disabled(saving || session.isDemo)
                    if let error { Text(error).font(.system(size: 12)).foregroundStyle(Theme.negative) }
                    MacNote(session.isDemo ? "The shared demo keeps its currency." : "Totals, budgets and reports use this currency.")
                }
            }
            MacCurrencies()
            Divider()
            LabeledContent("Server:") {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        TextField("Server", text: .constant(session.savedServer)).disabled(true).frame(width: 220)
                        HStack(spacing: 5) {
                            Circle().fill(Theme.positiveBar).frame(width: 7, height: 7)
                            Text("Connected").fontWeight(.medium).foregroundStyle(Theme.positive)
                        }
                    }
                    MacNote("Signed in as \(session.info?.email ?? session.info?.username ?? "you"). Sign out to use a self-hosted server.")
                }
            }
            Divider()
            LabeledContent("Unlock:") {
                Toggle("Use \(Biometrics.name) to unlock Finlynq", isOn: $requireBiometrics)
            }
            LabeledContent("Lock automatically:") {
                VStack(alignment: .leading, spacing: 5) {
                    Picker("Lock automatically", selection: $lockAfterMinutes) {
                        Text("After 1 minute idle").tag(1)
                        Text("After 5 minutes idle").tag(5)
                        Text("After 15 minutes idle").tag(15)
                        Text("After 1 hour idle").tag(60)
                        Text("Never").tag(0)
                    }
                    .labelsHidden().frame(width: 200)
                    .disabled(!requireBiometrics)
                    MacNote("Finlynq asks for \(Biometrics.name) or your password to open again.")
                }
            }
        }
        .formStyle(.columns)
        .padding(.horizontal, 40).padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pick(_ code: String) async {
        guard code != session.currency, !session.isDemo else { return }
        saving = true
        defer { saving = false }
        do {
            try await session.setDisplayCurrency(code)
            error = nil
        } catch {
            self.error = "Couldn't change the currency. \(error.localizedDescription)"
        }
    }
}

// MARK: Accounts & Data

private struct MacDataTab: View {
    @Environment(Session.self) private var session
    @State private var exporting: CSVExport?
    @State private var preparing = false
    @State private var error: String?
    @State private var showFeedback = false

    var body: some View {
        Form {
            LabeledContent("Export:") {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Button("Export Transactions as CSV…") { Task { await export() } }.disabled(preparing)
                        if preparing { ProgressView().controlSize(.small) }
                    }
                    if let error { Text(error).font(.system(size: 12)).foregroundStyle(Theme.negative) }
                    MacNote("Every transaction: date, payee, category, account, amount and currency.")
                }
            }
            LabeledContent("Feedback:") {
                Button("Send Feedback…") { showFeedback = true }
            }
        }
        .formStyle(.columns)
        .padding(.horizontal, 40).padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fileExporter(
            isPresented: Binding { exporting != nil } set: { if !$0 { exporting = nil } },
            document: exporting.map { CSVFile(text: $0.text) }, contentType: .commaSeparatedText,
            defaultFilename: exporting?.name
        ) { _ in exporting = nil }
        .sheet(isPresented: $showFeedback) { FeedbackSheet() }
    }

    private func export() async {
        preparing = true
        defer { preparing = false }
        do {
            exporting = CSVExport(name: TransactionsExport.name, text: try await TransactionsExport(api: session.api).csv())
            error = nil
        } catch {
            self.error = "Couldn't export. \(error.localizedDescription)"
        }
    }
}

// MARK: Import

private struct MacImportTab: View {
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL
    /// nil while loading. A failed load is `failed`, which differs from an account with no address yet.
    @State private var address: String??
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        Form {
            LabeledContent("Import email address:") {
                VStack(alignment: .leading, spacing: 5) {
                    switch address {
                    case .none where failed:
                        InlineError(message: "Couldn't load your import address.") { failed = false; attempt += 1 }.frame(width: 400)
                    case .none: ProgressView().controlSize(.small)
                    case .some(.none):
                        Button("Set Up on the Web…") { openURL(session.api.baseURL.appending(path: "/settings/import")) }
                    case .some(.some(let address)):
                        HStack {
                            Text(address).textSelection(.enabled)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(address, forType: .string)
                            }
                        }
                    }
                    MacNote("Forward statement emails to this address to import them.")
                }
            }
            LabeledContent("Auto-categorize rules:") { RulesEditor() }
        }
        .formStyle(.columns)
        .padding(.horizontal, 40).padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(session.revision)|\(attempt)") {
            address = await optionalLoad("import email address") { try await session.api.importEmailAddress() }
            failed = address == nil
        }
    }
}

// MARK: Security

private struct MacSecurityTab: View {
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var showDelete = false
    @State private var confirmSignOut = false

    var body: some View {
        Form {
            LabeledContent("Password:") {
                VStack(alignment: .leading, spacing: 5) {
                    Button("Change Password…") { openURL(session.api.baseURL.appending(path: "/settings/account")) }
                    MacNote("Opens your account page on the web.")
                }
            }
            LabeledContent("Account:") {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Signed in as \(session.info?.email ?? session.info?.username ?? "you") on \(session.api.baseURL.host() ?? "")")
                    Button("Sign Out") {
                        if ApplePayCapture.waitingCount > 0 { confirmSignOut = true } else { Task { await session.signOut() } }
                    }
                    .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                        Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
                    } message: {
                        Text(ApplePayCapture.signOutWarning)
                    }
                }
            }
            Divider()
            LabeledContent("Delete account:") {
                VStack(alignment: .leading, spacing: 5) {
                    Button("Delete Account…", role: .destructive) { showDelete = true }.disabled(session.isDemo)
                    MacNote(session.isDemo
                         ? "The shared demo can't be deleted."
                         : "Deletes your account and all its data for good. You'll need your password.")
                }
            }
        }
        .formStyle(.columns)
        .padding(.horizontal, 40).padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showDelete) { DeleteAccountSheet() }
    }
}
#endif
