import SwiftUI

/// Settings on iPhone (a sheet from the Home avatar) and iPad (the sidebar's Settings row), per Settings.dc.html:
/// the profile, display currency, categories and rules, the import address, biometric unlock, export, feedback, sign out
/// and account deletion. Things only the web does (API keys, connected apps, backups) are a link to the server.
/// The Mac has its own Settings window (MacSettingsView).
struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(\.layoutWidth) private var layoutWidth
    @Environment(\.openURL) private var openURL
    @AppStorage("requireBiometrics") private var requireBiometrics = true
    @AppStorage("lockAfterMinutes") private var lockAfterMinutes = 5
    @State private var data = SettingsData()
    @State private var attempt = 0
    @State private var copied = false
    @State private var showFeedback = false
    @State private var showDelete = false
    @State private var confirmSignOut = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                profile
                general
                money
                security
                dataSection
                account
                footer
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 28)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.page)
        .navigationTitle("Settings")
        #if os(iOS)
        .toolbarTitleDisplayMode(layoutWidth == .compact ? .inline : .large)
        #endif
        .task(id: "\(session.revision)|\(attempt)") { data = await SettingsData.load(session.api) }
        .sheet(isPresented: $showFeedback) { FeedbackSheet() }
        .sheet(isPresented: $showDelete) { DeleteAccountSheet() }
    }

    // MARK: Sections

    private var profile: some View {
        let info = session.info
        let name = info?.displayName ?? info?.username ?? "Finlynq"
        return Button { open("/settings/account") } label: {
            HStack(spacing: 14) {
                Text(String(name.prefix(1)).uppercased())
                    .font(.title2.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 56, height: 56).background(Theme.accent, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.body.weight(.bold)).foregroundStyle(Theme.text)
                    if let email = info?.email ?? info?.username { Text(email).font(.footnote).foregroundStyle(Theme.secondary) }
                    Label(session.api.baseURL.host() ?? session.savedServer, systemImage: "server.rack")
                        .labelStyle(TightLabel())
                        .font(.footnote).foregroundStyle(Theme.secondary).padding(.top, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SettingsChevron()
            }
            .padding(14)
            .settingsCard()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your account page on the web")
    }

    private var general: some View {
        SettingsSection("General") {
            NavigationLink { CurrencyPickerView() } label: {
                SettingsRow("dollarsign", tint: Theme.accent, tile: Theme.accentTint, title: "Display currency", value: session.currency)
            }
            .disabled(session.isDemo)
            Divider()
            Button { open("/settings/general") } label: {
                SettingsRow("globe", tint: Theme.accent, tile: Theme.accentTint, title: "Currencies",
                            value: data.currencies?.joined(separator: ", "))
            }
        }
    }

    private var money: some View {
        SettingsSection("Money", footer: data.importAddress == nil ? nil : "Forward statement emails to this address to import them.") {
            NavigationLink { CategoriesListView() } label: {
                SettingsRow("square.grid.2x2", tint: Theme.invest, tile: Theme.investTint, title: "Categories")
            }
            Divider()
            NavigationLink { RulesListView() } label: {
                SettingsRow("slider.horizontal.3", tint: Theme.warning, tile: Theme.warningTint, title: "Auto-categorize rules",
                            value: data.rules.map { "\($0.filter(\.isActive).count) on" })
            }
            Divider()
            Button { open("/settings/bank-feeds") } label: {
                SettingsRow("arrow.triangle.2.circlepath", tint: Theme.positive, tile: Theme.positiveTint, title: "Bank feeds",
                            subtitle: data.bankFeedText)
            }
            Divider()
            #if os(iOS)
            NavigationLink { ApplePaySetupView() } label: {
                SettingsRow("creditcard", tint: .white, tile: .black, title: "Apple Pay purchases", subtitle: "Log them as you pay")
            }
            Divider()
            #endif
            importAddressRow
        }
    }

    @ViewBuilder
    private var importAddressRow: some View {
        if data.importAddressFailed {
            InlineError(message: "Couldn't load your import address.") { attempt += 1 }
        } else if let address = data.importAddress {
            HStack(spacing: 12) {
                SettingsTile("envelope", tint: Theme.accent, tile: Theme.accentTint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Import email address").font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                    Text(address).font(.footnote).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { copy(address) } label: {
                    Image(systemName: copied ? "checkmark" : "square.on.square").font(.system(size: 17)).foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(.trailing, -8)
                .accessibilityLabel(copied ? "Copied" : "Copy import email address")
            }
            .padding(.vertical, 5)
        } else {
            Button { open("/settings/import") } label: {
                SettingsRow("envelope", tint: Theme.accent, tile: Theme.accentTint, title: "Import email address",
                            subtitle: "Set it up on the web")
            }
        }
    }

    private var security: some View {
        SettingsSection("Security", footer: "Finlynq asks for \(Biometrics.name) or your password to open again.") {
            HStack(spacing: 12) {
                SettingsTile(Biometrics.symbol, tint: Theme.positive, tile: Theme.positiveTint)
                Toggle("\(Biometrics.name) unlock", isOn: $requireBiometrics)
                    .font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                    .tint(Theme.positiveBar)
            }
            .padding(.vertical, 9)
            Divider()
            Menu {
                Picker("Lock automatically", selection: $lockAfterMinutes) {
                    ForEach(Self.lockChoices, id: \.minutes) { Text($0.label).tag($0.minutes) }
                }
            } label: {
                SettingsRow("clock", tint: Theme.accent, tile: Theme.accentTint, title: "Lock automatically",
                            value: Self.lockChoices.first { $0.minutes == lockAfterMinutes }?.label)
            }
            .disabled(!requireBiometrics)
            Divider()
            Button { open("/settings/account") } label: {
                SettingsRow("lock", tint: Theme.secondary, tile: Theme.fill, title: "Change password")
            }
        }
    }

    private var dataSection: some View {
        SettingsSection("Data") {
            ShareLink(item: TransactionsExport(api: session.api), preview: SharePreview(TransactionsExport.name)) {
                SettingsRow("square.and.arrow.up", tint: Theme.accent, tile: Theme.accentTint, title: "Export data", value: "CSV")
            }
            Divider()
            Button { showFeedback = true } label: {
                SettingsRow("bubble.left", tint: Theme.invest, tile: Theme.investTint, title: "Send feedback")
            }
        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if ApplePayCapture.waitingCount > 0 { confirmSignOut = true } else { Task { await session.signOut() } }
            } label: {
                Text("Sign out").foregroundStyle(Theme.accent).frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            }
            .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await session.signOut() } }
            } message: {
                Text(ApplePayCapture.signOutWarning)
            }
            Divider()
            Button { showDelete = true } label: {
                Text("Delete account").foregroundStyle(session.isDemo ? Theme.secondary : Theme.negative)
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            }
            .disabled(session.isDemo)
        }
        .font(.subheadline.weight(.medium))
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .settingsCard()
    }

    /// The idle limits Mac Settings offers too (MacGeneralTab).
    private static let lockChoices: [(minutes: Int, label: String)] = [
        (1, "After 1 minute"), (5, "After 5 minutes"), (15, "After 15 minutes"), (60, "After 1 hour"), (0, "Never")
    ]

    private var footer: some View {
        let host = session.api.baseURL.host() ?? "the web"
        let demoNote = session.isDemo ? " The demo is shared, so its currency can't change and it can't be deleted." : ""
        let link = "[\(host)](\(session.api.baseURL.absoluteString))"
        let text = "Finlynq \(SettingsData.version). API keys, connected apps and backups are on \(link).\(demoNote)"
        // An interpolated String isn't parsed as Markdown, so parse it here to make the host a link.
        return Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
        .font(.footnote).foregroundStyle(Theme.secondary).tint(Theme.accent)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    // MARK: Actions

    private func open(_ path: String) { openURL(session.api.baseURL.appending(path: path)) }

    private func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

/// What Settings loads besides the session. Every source is optional: a failure leaves its row without a value
/// (or, for the import address, shows a retry), and is logged.
struct SettingsData {
    var currencies: [String]?
    var rules: [Rule]?
    var bankFeed: BankFeedStatus?
    var importAddress: String?
    var importAddressFailed = false

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    static func load(_ api: APIClient) async -> SettingsData {
        async let currencies = optionalLoad("active currencies") { try await api.activeCurrencies() }
        async let rules = optionalLoad("rules") { try await api.rules() }
        async let bankFeed = optionalLoad("bank feed status") { try await api.bankFeedStatus() }
        async let address = optionalLoad("import email address") { try await api.importEmailAddress() }
        let loaded = await address
        return await SettingsData(
            currencies: currencies, rules: rules, bankFeed: bankFeed,
            importAddress: loaded.flatMap { $0 }, importAddressFailed: loaded == nil
        )
    }

    var bankFeedText: String? {
        guard let bankFeed else { return nil }
        guard bankFeed.connected else { return "Not connected" }
        guard let date = bankFeed.lastSyncAt.flatMap({ try? Date($0, strategy: .iso8601) }) else { return "SimpleFIN" }
        return "SimpleFIN · Synced \(date.formatted(.relative(presentation: .named)))"
    }
}

/// Every transaction as CSV (Date, Payee, Category, Account, Amount, Currency), fetched when the share sheet
/// asks for the file, so opening Settings doesn't download them.
struct TransactionsExport: Transferable {
    static let name = "Finlynq transactions.csv"
    let api: APIClient

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = Session.exportURL
            try Data(await export.csv().utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }

    /// Pages through `/api/transactions` until it has them all.
    func csv() async throws -> String {
        var rows: [Transaction] = []
        while true {
            let page = try await api.transactions(TransactionQuery(limit: 500, offset: rows.count))
            rows += page.data
            if page.data.isEmpty || rows.count >= page.total { break }
        }
        return ActivityModel.csv(rows)
    }
}

// MARK: Building blocks (Settings.dc.html)

/// A titled group of rows in a white card.
struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary).padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .settingsCard()
            if let footer { Text(footer).font(.footnote).foregroundStyle(Theme.secondary).padding(.horizontal, 4) }
        }
    }
}

/// Icon tile, title, optional subtitle and value, and a chevron.
struct SettingsRow: View {
    let symbol: String
    let tint: Color
    let tile: Color
    let title: String
    var subtitle: String?
    var value: String?

    init(_ symbol: String, tint: Color, tile: Color, title: String, subtitle: String? = nil, value: String? = nil) {
        self.symbol = symbol
        self.tint = tint
        self.tile = tile
        self.title = title
        self.subtitle = subtitle
        self.value = value
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsTile(symbol, tint: tint, tile: tile)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(Theme.secondary).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let value { Text(value).font(.subheadline).foregroundStyle(Theme.secondary).lineLimit(1) }
            SettingsChevron()
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

struct SettingsTile: View {
    let symbol: String
    let tint: Color
    let tile: Color

    init(_ symbol: String, tint: Color, tile: Color) {
        self.symbol = symbol
        self.tint = tint
        self.tile = tile
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(tile, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary.opacity(0.7))
            .accessibilityHidden(true)
    }
}

/// An icon and title 4pt apart, for the server line under the profile name.
private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon.imageScale(.small); configuration.title }
    }
}

extension View {
    /// Settings.dc.html's card: white, 18pt corners, a hairline in dark mode.
    func settingsCard() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.cardBorder))
    }
}
