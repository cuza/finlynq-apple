import SwiftUI

/// The first-run steps and the starter budget. Skip and Continue both move on; only Continue saves the step.
struct SetupModel {
    enum Step: Int, CaseIterable {
        case currency, accounts, importData, budget

        var title: String {
            switch self {
            case .currency: "Currency"
            case .accounts: "Accounts"
            case .importData: "Import"
            case .budget: "Budget"
            }
        }
    }

    enum Start { case bank, sample, scratch }

    /// The web wizard's starter budget, a month.
    static let budgetPresets: [(name: String, amount: Double)] = [
        ("Groceries", 600), ("Dining Out", 300), ("Transportation", 200), ("Entertainment", 150), ("Utilities", 150)
    ]

    private(set) var step = Step.currency
    private(set) var isFinished = false
    var start = Start.bank
    var budget = Dictionary(uniqueKeysWithValues: budgetPresets.map { ($0.name, $0.amount) })

    var previous: Step? { Step(rawValue: step.rawValue - 1) }
    var progress: String { "Step \(step.rawValue + 1) of \(Step.allCases.count)" }

    mutating func advance() {
        if let next = Step(rawValue: step.rawValue + 1) { step = next } else { isFinished = true }
    }

    mutating func back() {
        if let previous { step = previous }
    }

    /// The amounts to seed, in preset order, leaving out zero.
    var budgetSeeds: [(name: String, amount: Double)] {
        Self.budgetPresets.compactMap { preset in
            let amount = budget[preset.name] ?? 0
            return amount > 0 ? (preset.name, amount) : nil
        }
    }
}

/// First run after a fresh registration (Setup.dc.html): display currency, accounts, import or sample data, and a
/// first budget. Finishing or skipping the last step tells the server setup is done, so it shows once.
struct SetupView: View {
    @Environment(Session.self) private var session
    @State private var model: SetupModel
    @State private var currency = ""
    @State private var addAccount: AccountPreset?
    @State private var importing = false
    @State private var busy = false
    @State private var error: String?
    /// Balances by account id, for the added accounts. Missing when the dashboard fails to load.
    @State private var balances: [Int: Double] = [:]

    init(model: SetupModel = SetupModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            page
                .navigationDestination(for: AppRoute.self) { RouteDestination(route: $0) }
                #if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
                #endif
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                topBar
                progress
                heading.padding(.top, 4)
                stepContent
            }
            // A centered column 500pt wide at most (iPadPSetup.dc.html).
            .frame(maxWidth: 500)
            .padding(.horizontal, 20).padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.page)
        .safeAreaInset(edge: .bottom, spacing: 0) { continueBar }
        .disabled(busy)
        .onAppear { if currency.isEmpty { currency = session.currency } }
        // The Accounts step's "Change" link goes back to the currency step.
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "finlynq-setup" { model.back(); return .handled }
            return .systemAction
        })
        .sheet(item: $addAccount) { AddAccountSheet(preset: $0) }
        .sheet(isPresented: $importing, onDismiss: { if model.step == .importData { next() } }, content: { ImportSheet() })
        .task(id: session.revision) {
            let rows = await optionalLoad("setup balances") { try await session.api.dashboard().balances }
            balances = Dictionary((rows ?? []).map { ($0.accountId, $0.balance) }, uniquingKeysWith: { first, _ in first })
        }
        .onChange(of: model.isFinished) { if model.isFinished { Task { await session.finishSetup() } } }
    }

    // MARK: Header

    private var topBar: some View {
        HStack {
            if let previous = model.previous {
                Button { model.back() } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").fontWeight(.semibold)
                        Text(previous.title)
                    }
                }
                .accessibilityLabel("Back to \(previous.title)")
            }
            Spacer()
            Button("Skip") { next() }
        }
        .font(.body).foregroundStyle(Theme.accent).buttonStyle(.plain)
        .frame(height: 44)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.progress).font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
            HStack(spacing: 4) {
                ForEach(SetupModel.Step.allCases, id: \.self) { step in
                    Capsule().fill(step.rawValue <= model.step.rawValue ? Theme.accent : Theme.fill).frame(height: 4)
                }
            }
            HStack(spacing: 4) {
                ForEach(SetupModel.Step.allCases, id: \.self) { step in
                    Text(step.title)
                        .font(.caption.weight(step == model.step ? .semibold : .regular))
                        .foregroundStyle(step == model.step ? Theme.accent : Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.progress), \(model.step.title)")
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.largeTitle.weight(.bold)).foregroundStyle(Theme.text)
            subtitle.font(.subheadline).foregroundStyle(Theme.secondary)
        }
    }

    private var title: String {
        switch model.step {
        case .currency: "Pick your currency"
        case .accounts: "Add your accounts"
        case .importData: "Bring in your history"
        case .budget: "Set a first budget"
        }
    }

    private var subtitle: Text {
        switch model.step {
        case .currency: Text("Totals, budgets and reports use it. You can change it later in Settings.")
        case .accounts:
            Text("""
            Start with the ones you use most. You can add more later. Amounts in \(session.currency). \
            **[Change](finlynq-setup://currency)**
            """)
        case .importData: Text("Import a statement from your bank, or look around with sample data first.")
        case .budget: Text("Monthly amounts in \(session.currency). Fine-tune them any time in Plan.")
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .currency: currencyList
        case .accounts: accounts
        case .importData: startChoices
        case .budget: budgetCard
        }
    }

    private var currencyList: some View {
        VStack(spacing: 0) {
            ForEach(CurrencyList.codes, id: \.self) { code in
                Button { currency = code } label: {
                    HStack {
                        Text(code).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).frame(width: 48, alignment: .leading)
                        Text(CurrencyList.name(code)).font(.subheadline).foregroundStyle(Theme.secondary)
                        Spacer()
                        if code == currency { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Theme.accent) }
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityAddTraits(code == currency ? .isSelected : [])
                if code != CurrencyList.codes.last { Divider() }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .settingsCard()
    }

    private var accounts: some View {
        let added = session.accounts.filter { !$0.archived }
        return VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(AccountPreset.all) { preset in
                    Button { addAccount = preset } label: { PresetTile(preset: preset) }.buttonStyle(.plain)
                }
            }
            if !added.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Added · \(added.count)").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 4).padding(.top, 4)
                    VStack(spacing: 0) {
                        ForEach(added) { account in
                            NavigationLink(value: AppRoute.account(account.id)) { accountRow(account) }.buttonStyle(.plain)
                            if account.id != added.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 16)
                    .settingsCard()
                }
            }
            Button { importing = true } label: {
                Label("Import a statement instead", systemImage: "doc")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }

    private func accountRow(_ account: Account) -> some View {
        let symbol = Icons.account(group: account.group, isLiability: account.type == "L", isInvestment: account.isInvestment)
        return HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: account.type == "L" ? Theme.warning : Theme.accent,
                     background: account.type == "L" ? Theme.warningTint : Theme.accentTint, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text([account.group, account.currency].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer()
            if let balance = balances[account.id] {
                MoneyText(amount: balance, currency: account.currency).font(.subheadline.weight(.semibold))
            }
            SettingsChevron()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 10)
    }

    private var startChoices: some View {
        VStack(spacing: 8) {
            choice(.bank, "Import from my bank", "A CSV, OFX or QFX statement. You review the rows before they're added.", "doc.text")
            choice(.sample, "Load sample data", "Made-up accounts and transactions to try things with.", "sparkles")
            choice(.scratch, "Start from scratch", "Add transactions yourself as you go.", "square.and.pencil")
        }
    }

    private func choice(_ start: SetupModel.Start, _ title: String, _ detail: String, _ symbol: String) -> some View {
        let selected = model.start == start
        return Button { model.start = start } label: {
            HStack(spacing: 12) {
                IconTile(symbol: symbol, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(detail).font(.footnote).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected ? Theme.accent : Theme.secondary.opacity(0.5))
            }
            .padding(14)
            .settingsCard()
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? Theme.accent : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var budgetCard: some View {
        VStack(spacing: 0) {
            ForEach(SetupModel.budgetPresets, id: \.name) { preset in
                HStack {
                    Text(preset.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                    Spacer()
                    TextField("0", value: Binding { model.budget[preset.name] ?? 0 } set: { model.budget[preset.name] = $0 },
                              format: .number.precision(.fractionLength(0...2)))
                        .multilineTextAlignment(.trailing).monospacedDigit()
                        .frame(width: 110)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityLabel("\(preset.name) a month")
                }
                .frame(minHeight: 48)
                if preset.name != SetupModel.budgetPresets.last?.name { Divider() }
            }
        }
        .padding(.horizontal, 16)
        .settingsCard()
    }

    // MARK: Continue

    private var continueBar: some View {
        VStack(spacing: 8) {
            if let error { Text(error).font(.footnote).foregroundStyle(Theme.negative).frame(maxWidth: .infinity, alignment: .leading) }
            Button { Task { await save() } } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white) }
                    Text(model.step == .budget ? "Finish" : "Continue")
                }
                .font(.body.weight(.semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 500)
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.page.opacity(0.94))
        .overlay(alignment: .top) { Divider() }
    }

    private func next() {
        error = nil
        model.advance()
    }

    /// Saves the step, then moves on. A failure stays on the step with the message.
    private func save() async {
        busy = true
        defer { busy = false }
        do {
            switch model.step {
            case .currency:
                if currency != session.currency { try await session.setDisplayCurrency(currency) }
            case .accounts:
                break
            case .importData:
                switch model.start {
                case .bank:
                    importing = true
                    return
                case .sample:
                    try await session.api.loadSampleData()
                    await session.didSave()
                case .scratch:
                    break
                }
            case .budget:
                let month = String(APIDate.string(Fixtures.today).prefix(7))
                for seed in model.budgetSeeds {
                    try await session.api.seedBudget(categoryName: seed.name, amount: seed.amount, month: month)
                }
            }
            next()
        } catch {
            self.error = "Couldn't save this step. \(error.localizedDescription)"
        }
    }
}

/// A tile in the Accounts step's grid. "Other" is dashed.
private struct PresetTile: View {
    let preset: AccountPreset

    var body: some View {
        VStack(spacing: 8) {
            if preset.isOther {
                Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).frame(width: 36, height: 36)
            } else {
                IconTile(symbol: preset.symbol, tint: preset.tint, background: preset.tile, size: 36)
            }
            Text(preset.title).font(.footnote.weight(.semibold))
        }
        .foregroundStyle(preset.isOther ? Theme.inactive : Theme.text)
        .frame(maxWidth: .infinity).frame(height: 88)
        .background(preset.isOther ? Color.clear : Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.fill, style: StrokeStyle(lineWidth: 1, dash: preset.isOther ? [4, 3] : []))
        }
        .contentShape(Rectangle())
        .accessibilityLabel("Add \(preset.title.lowercased()) account")
    }
}

/// An account kind the Accounts step offers. "Other" opens a blank form.
struct AccountPreset: Identifiable {
    let title: String
    let symbol: String
    let tint: Color
    let tile: Color
    let type: String
    let group: String
    var isInvestment = false

    var id: String { title }
    var isOther: Bool { group.isEmpty }

    static let all = [
        AccountPreset(title: "Chequing", symbol: "banknote", tint: Theme.accent, tile: Theme.accentTint, type: "A", group: "Chequing"),
        AccountPreset(title: "Savings", symbol: "dollarsign.bank.building", tint: Theme.positive, tile: Theme.positiveTint,
                      type: "A", group: "Savings"),
        AccountPreset(title: "Credit card", symbol: "creditcard", tint: Theme.warning, tile: Theme.warningTint,
                      type: "L", group: "Credit Card"),
        AccountPreset(title: "Investment", symbol: "chart.line.uptrend.xyaxis", tint: Theme.invest, tile: Theme.investTint,
                      type: "A", group: "Investments", isInvestment: true),
        AccountPreset(title: "Loan", symbol: "percent", tint: Theme.negative, tile: Theme.negativeTint, type: "L", group: "Loan"),
        AccountPreset(title: "Other", symbol: "plus", tint: Theme.inactive, tile: .clear, type: "A", group: "")
    ]
}

#if DEBUG
extension SetupModel {
    /// The step Setup.dc.html draws, for the `setup` debug route.
    static var debugAccountsStep: SetupModel {
        var model = SetupModel()
        model.advance()
        return model
    }
}
#endif
