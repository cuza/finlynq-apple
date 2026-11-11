import SwiftUI
import UniformTypeIdentifiers

/// ApplePay.dc.html: explains the Wallet automation, hands the bundled shortcut to iOS, lists the two steps in
/// Shortcuts' own words, shows whether a purchase has arrived, the purchases that wait for the user, and which
/// account each card logs to.
struct ApplePaySetupView: View {
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var fixing: CapturedPurchase?
    @AppStorage(ApplePayCapture.waitForUnlockKey) private var waitForUnlock = false
    private let store = ApplePayCapture.store

    private static let steps: [LocalizedStringKey] = [
        "**Add the shortcut.** Tap **Add shortcut** and choose **Shortcuts**.",
        "In Shortcuts, tap **Automation**, then **Transaction**, pick your cards, and choose **Log Apple Pay purchase**."
    ]

    /// Shortcuts/Log Apple Pay purchase.shortcut, signed for anyone, bundled with the app.
    private static let shortcut = Bundle.main.url(forResource: "Log Apple Pay purchase", withExtension: "shortcut")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    IconTile(symbol: "creditcard", tint: Theme.card, background: Theme.text, size: 52)
                    // A no-break space keeps "Apple Pay" on one line, as in the design.
                    Text("Log Apple\u{00A0}Pay purchases").font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                }
                Text("""
                Every time you pay with Apple Pay, the store and amount go straight to Finlynq. Purchases wait in \
                Review, so your bank import links to them instead of adding them twice.
                """)
                .font(.subheadline).foregroundStyle(Theme.secondary).lineSpacing(3)
                status
                if !store.items.isEmpty { waiting }
                steps
                VStack(alignment: .leading, spacing: 6) {
                    Card {
                        Toggle("Wait until I unlock Finlynq", isOn: $waitForUnlock).font(.subheadline).tint(Theme.accent)
                    }
                    Text("When off, Finlynq signs in in the background to save the purchase.")
                        .font(.footnote).foregroundStyle(Theme.secondary).padding(.horizontal, 4)
                }
                cards
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.page)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationTitle("Apple Pay")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { ToolbarItem(placement: .principal) { Color.clear } }
        .sheet(item: $fixing) { FixPurchaseSheet(purchase: $0) }
        .task { await ApplePayCapture.flush() }
    }

    /// Add shortcut hands the bundled file to the share sheet, where the user picks Shortcuts to import it.
    /// Kept to the content column on iPad, with the bar's background across the full width.
    private var bottomBar: some View {
        HStack(spacing: 10) {
            if let shortcut = Self.shortcut {
                ShareLink(item: ShortcutFile(url: shortcut), preview: SharePreview("Log Apple Pay purchase")) {
                    Label("Add shortcut", systemImage: "plus").bottomButton(primary: true)
                }
            }
            Button { openURL(URL(string: "shortcuts://")!) } label: {
                Text("Open Shortcuts").bottomButton(primary: Self.shortcut == nil)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 600)
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.page.opacity(0.96)).overlay(alignment: .top) { Divider() }
    }

    /// Orange until the first purchase arrives, then green with the last one.
    private var status: some View {
        let last = store.last
        let lead = last == nil ? "Not set up yet." : "Last captured:"
        let rest = last.map { last in
            let ago = RelativeDateTimeFormatter().localizedString(for: last.capturedAt, relativeTo: Fixtures.today)
            return "\(last.merchant), \(last.amount.money(last.currency)), \(ago)"
        } ?? "Takes about a minute in the Shortcuts app."
        return HStack(spacing: 12) {
            Circle().fill(last == nil ? Theme.spendBar : Theme.positiveBar).frame(width: 10, height: 10)
            Text("\(Text(lead).fontWeight(.bold)) \(rest)").font(.subheadline).foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(last == nil ? Theme.warningTint : Theme.positiveTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var waiting: some View {
        section("Waiting for you") {
            DividedRows(items: store.items) { purchase in
                Button { fixing = purchase } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(purchase.merchant).font(.subheadline).foregroundStyle(Theme.text)
                            Text(purchase.problem?.text ?? "").font(.footnote).foregroundStyle(Theme.warning)
                        }
                        Spacer()
                        if purchase.amount > 0 {
                            Text(purchase.amount.money(purchase.currency)).font(.subheadline).monospacedDigit().foregroundStyle(Theme.text)
                        }
                        chevron
                    }
                    .padding(.vertical, 11).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var steps: some View {
        section("Set it up") {
            VStack(spacing: 0) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 { Divider() }
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)").font(.footnote.weight(.bold)).foregroundStyle(Theme.accent)
                            .frame(width: 24, height: 24).background(Theme.accentTint, in: Circle())
                        Text(step).font(.subheadline).foregroundStyle(Theme.text).lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var cards: some View {
        let accounts = session.accounts.filter { !$0.archived && !$0.isInvestment }
        let names = store.mappings.keys.sorted()
        return section("Cards and accounts", detail: "Added after first purchase") {
            VStack(spacing: 0) {
                if names.isEmpty {
                    Text("No cards yet").font(.subheadline).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 11)
                }
                ForEach(Array(names.enumerated()), id: \.element) { index, card in
                    if index > 0 { Divider() }
                    Menu {
                        Picker("Account", selection: mapping(card)) {
                            ForEach(accounts) { Text($0.displayName).tag(Optional($0.id)) }
                        }
                        Button("Forget this card", role: .destructive) { store.mappings[card] = nil }
                    } label: {
                        HStack(spacing: 12) {
                            Text(card).font(.subheadline).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
                            let account = store.mappings[card].flatMap { id in accounts.first { $0.id == id } }
                            Text(account?.displayName ?? "Pick an account").font(.subheadline).foregroundStyle(Theme.secondary)
                            chevron
                        }
                        .padding(.vertical, 11).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary.opacity(0.7))
            .accessibilityHidden(true)
    }

    private func mapping(_ card: String) -> Binding<Int?> {
        Binding { store.mappings[card] } set: { store.mappings[card] = $0 }
    }

    /// A white card with a 15pt bold heading, as in the design's sections.
    private func section(_ title: String, detail: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
                    Spacer()
                    if let detail { Text(detail).font(.footnote).foregroundStyle(Theme.secondary) }
                }
                .padding(.top, 12).padding(.bottom, 4)
                content()
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
        }
    }
}

/// Fills in what a waiting purchase lacks (amount, account or category) and sends it.
private struct FixPurchaseSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var purchase: CapturedPurchase
    @State private var isSending = false
    @State private var confirmDelete = false
    @State private var error: String?

    init(purchase: CapturedPurchase) { _purchase = State(initialValue: purchase) }

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section { InlineError(message: error) { Task { await send() } } }
                }
                Section {
                    TextField("Merchant", text: $purchase.merchant)
                    TextField("Amount", value: $purchase.amount, format: .number)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
                    LabeledContent("Card", value: purchase.card)
                } footer: {
                    if error == nil, let problem = purchase.problem { Text(problem.text) }
                }
                Section {
                    Picker("Account", selection: $purchase.accountId) {
                        Text("Choose").tag(Int?.none)
                        ForEach(session.accounts.filter { !$0.archived && !$0.isInvestment }) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    Picker("Category", selection: $purchase.categoryId) {
                        Text("Choose").tag(Int?.none)
                        ForEach(session.categories.filter { $0.type == "E" }) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                }
                Section {
                    Button("Delete purchase", role: .destructive) { confirmDelete = true }
                        .confirmationDialog("Delete this purchase?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Delete purchase", role: .destructive) {
                                ApplePayCapture.store.remove(purchase)
                                dismiss()
                            }
                        } message: {
                            Text("It won't be added to Finlynq.")
                        }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Apple Pay purchase")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await send() } }.disabled(isSending || purchase.amount <= 0)
                }
            }
        }
    }

    /// Applies the edits to the stored purchase (keeping fields a send in progress may have set) and sends it.
    /// Stays open with the reason when it can't be sent.
    private func send() async {
        guard var stored = ApplePayCapture.store.item(purchase.id) else { dismiss(); return }
        isSending = true
        defer { isSending = false }
        stored.merchant = purchase.merchant
        stored.amount = purchase.amount
        stored.accountId = purchase.accountId
        stored.categoryId = purchase.categoryId
        ApplePayCapture.store.put(stored)
        // The account picked here becomes the card's mapping for later purchases.
        if let accountId = purchase.accountId { ApplePayCapture.store.mappings[purchase.card] = accountId }
        // A send already in flight (a flush) keeps the sheet in its sending state; then send again with these edits.
        while ApplePayCapture.isSending(stored.id) { try? await Task.sleep(for: .milliseconds(200)) }
        guard ApplePayCapture.store.item(stored.id) != nil else { dismiss(); return }
        if let problem = await ApplePayCapture.send(stored.id) {
            purchase.problem = problem
            error = problem == .notSent ? "Couldn't reach Finlynq. The purchase is saved and sent later." : problem.text
        } else {
            dismiss()
        }
    }
}

/// The bundled shortcut, typed as a shortcut file so the share sheet can offer the Shortcuts app.
private struct ShortcutFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: UTType(filenameExtension: "shortcut") ?? .data) { SentTransferredFile($0.url) }
    }
}

private extension View {
    /// BottomActions' look: the primary button filled with the accent, the other tinted.
    func bottomButton(primary: Bool) -> some View {
        font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(primary ? .white : Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(primary ? Theme.accent : Theme.accentTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
    }
}
