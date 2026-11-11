import SwiftUI
import UniformTypeIdentifiers

/// One account (Account.dc.html): balance with its history, this month's money in and out, the account's import
/// settings, and its transactions in day groups with the end-of-day balance. Import statement uploads a file
/// into the review queue for this account.
struct AccountDetailView: View {
    let id: Int
    @Environment(Session.self) private var session
    @Environment(\.layoutWidth) private var width
    @State private var data: AccountData?
    @State private var error: String?
    @State private var period = "6m"
    @Environment(\.presentEditor) private var present
    @State private var importing = false
    @State private var notice: String?

    struct AccountData {
        let balance: Dashboard.Balance
        let account: Account?
        var history: [ValuePoint]
        var historyFailed = false
        let rows: [Transaction]
        var rowsFailed = false
        let today: Date
        /// Bank statement balance against Finlynq's. Nil when the request failed.
        var check: BalanceSummary?
    }

    var body: some View {
        LoadState(value: data, error: error, retry: reload) { data in
            ScrollView { content(data) }
            #if os(iOS)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    BottomActions(actions: [
                        .init(title: "Import statement") { importing = true }, .init(title: "Reconcile balance", route: .review)
                    ])
                }
            #endif
        }
        .background(Theme.page)
        .navigationTitle(data?.balance.name ?? "Account")
        #if os(iOS)
        .toolbarTitleDisplayMode(.large)
        #endif
        .navigationDestination(for: Transaction.self) { transaction in
            TransactionDetailView(transaction: transaction, embedded: false) { Task { await session.didSave() } }
                .measuresLayoutWidth()
        }
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .primaryAction) {
                Button("Import statement", systemImage: "square.and.arrow.down") { importing = true }
                    .macTitleAndIcon().disabled(data == nil)
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil") { edit() }.macTitleAndIcon().disabled(data == nil)
            }
        }
        .task(id: "\(session.revision)|\(period)") { await load() }
        .refreshable { await load() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .data]) { result in
            Task { await upload(result) }
        }
        .alert("Statement import", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK") { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    private func content(_ data: AccountData) -> some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text([data.balance.accountGroup, data.balance.currency].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                    .font(.subheadline).foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4).padding(.top, -10)
            balanceCard(data)
            flowsCard(data)
            if let check = data.check { BalanceCheckCard(check: check, currency: data.balance.currency) }
            if let account = data.account { settingsRow(account) }
            transactions(data)
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20).padding(.vertical, 8)
    }

    private func balanceCard(_ data: AccountData) -> some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Balance").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                    Spacer()
                    if width == .compact { periodPicker.frame(width: 150) }
                }
                HeadlineMoney(amount: data.balance.balance, currency: data.balance.currency, size: 36)
                if let first = data.history.first, let last = data.history.last, data.history.count > 1 {
                    let change = last.value - first.value
                    let label = period == "6m" ? "in 6 months" : period == "1y" ? "in a year" : "since \(first.day.monthYear)"
                    Text("\(MoneyText.format(change, currency: data.balance.currency, signed: true)) \(label)")
                        .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(change.gainColor)
                }
                if data.historyFailed {
                    InlineError(message: "Couldn't load the balance history") { Task { await load() } }
                } else if data.history.count > 1 {
                    TimeSeriesChart(points: data.history, color: Theme.accent, height: 150, currency: data.balance.currency)
                        .padding(.top, 8)
                        .accessibilityLabel("Balance over time")
                }
                // iPadPAccount.dc.html: the period gets its own row under the chart.
                if width != .compact { periodPicker.padding(.top, 8) }
            }
        }
    }

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            Text("6M").tag("6m")
            Text("1Y").tag("1y")
            Text("All").tag("all")
        }
        .pickerStyle(.segmented).labelsHidden()
    }

    /// One card split by a divider on iPhone; two tiles side by side on wider columns (iPadPAccount.dc.html).
    @ViewBuilder
    private func flowsCard(_ data: AccountData) -> some View {
        let flows = WealthModel.monthFlows(data.rows, accountId: id, today: data.today)
        let currency = data.balance.currency
        let moneyIn = Figure(
            label: "In this month", value: MoneyText.format(flows.moneyIn, currency: currency, signed: true),
            color: flows.moneyIn > 0 ? Theme.positive : Theme.text,
            detail: "\(flows.deposits) \(flows.deposits == 1 ? "deposit" : "deposits")", size: 22
        )
        let moneyOut = Figure(
            label: "Out this month", value: MoneyText.format(flows.moneyOut, currency: currency),
            detail: flows.transfersOut < 0 ? "Includes \(abs(flows.transfersOut).money(currency)) in transfers" : " ", size: 22
        )
        Group {
            if width == .compact {
                Card(padding: 16) {
                    HStack(alignment: .top, spacing: 16) { moneyIn; Divider(); moneyOut }
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Card(padding: 16) { moneyIn.frame(maxWidth: .infinity, alignment: .leading) }
                    Card(padding: 16) { moneyOut.frame(maxWidth: .infinity, alignment: .leading) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This month")
    }

    private func edit() {
        if let data { present(.editAccount(data.balance, data.account)) }
    }

    private func settingsRow(_ account: Account) -> some View {
        let mode = ["auto": "Auto-approve imports", "approve": "Approve each import", "manual": "Review imports by hand"]
        let csv = ["confirm": "Confirm CSV mapping", "auto": "Apply CSV mapping automatically"]
        let detail = [account.mode.flatMap { mode[$0] }, account.csvMappingMode.flatMap { csv[$0] }].compactMap { $0 }
        return Button { edit() } label: {
            Card(padding: 16) {
                HStack(spacing: 12) {
                    IconTile(symbol: "slider.horizontal.3", tint: Theme.text, background: Theme.fill, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Account settings").font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                        if !detail.isEmpty { Text(detail.joined(separator: " \u{00B7} ")).font(.subheadline)
                            .foregroundStyle(Theme.secondary) }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func transactions(_ data: AccountData) -> some View {
        let groups = ActivityModel.groupByDay(data.rows)
        let balances = WealthModel.dayBalances(data.rows, current: data.balance.balance)
        if data.rowsFailed {
            InlineError(message: "Couldn't load transactions") { Task { await load() } }
        } else if groups.isEmpty {
            EmptyState(title: "No transactions", message: "Transactions in this account appear here.", symbol: "tray")
        }
        ForEach(groups, id: \.day) { group in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(ActivityStore.dayTitle(group.day, today: data.today)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    if let balance = balances[group.day] { Text(MoneyText.format(balance, currency: data.balance.currency))
                        .monospacedDigit() }
                }
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                .padding(.horizontal, 4).padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, transaction in
                        if index > 0 { Divider() }
                        NavigationLink(value: transaction) {
                            ActivityRow(transaction: transaction).padding(.vertical, 11).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .listCard()
            }
        }
    }

    // MARK: Loading

    private func reload() { Task { await load() } }

    private func load() async {
        let api = session.api
        do {
            let dashboard = try await api.dashboard()
            guard let balance = dashboard.balances.first(where: { $0.accountId == id }) else {
                error = "This account no longer exists."
                return
            }
            async let history = try? api.netWorthHistory(period: period, accountId: id)
            async let page = try? api.transactions(TransactionQuery(accountId: id, limit: 100))
            async let summary = try? api.balanceSummary(accountId: id)
            var account = session.accounts.first { $0.id == id }
            if account == nil { account = (try? await api.accounts())?.first { $0.id == id } }
            let points = await history
            let rows = await page
            if points == nil { WealthView.log.error("account history failed for \(id)") }
            if rows == nil { WealthView.log.error("account transactions failed for \(id)") }
            let rate = WealthModel.nativeRate(balance)
            data = AccountData(
                balance: balance, account: account,
                history: points.map { WealthModel.accountSeries($0.series, accountId: id, toNative: rate) } ?? [],
                historyFailed: points == nil,
                rows: rows?.data.filter { $0.accountId == id } ?? [], rowsFailed: rows == nil, today: Fixtures.today,
                check: await summary
            )
            error = nil
        } catch is CancellationError {
        } catch {
            WealthView.log.error("account failed: \(String(describing: error), privacy: .public)")
            self.error = error.localizedDescription
        }
    }

    private func upload(_ result: Result<URL, Error>) async {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let file = UploadFile(filename: url.lastPathComponent, data: try Data(contentsOf: url))
            _ = try await session.api.uploadStatement(file: file, accountId: id)
            await session.didSave()
            notice = "The statement is in Review. Approve its rows there."
        } catch {
            WealthView.log.error("statement upload failed: \(String(describing: error), privacy: .public)")
            notice = "Couldn't import the statement: \(error.localizedDescription)"
        }
    }
}

/// "Bank balance check" (Account.dc.html): the latest statement balance the bank reported against Finlynq's balance.
private struct BalanceCheckCard: View {
    let check: BalanceSummary
    let currency: String

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Bank balance check").font(.headline)
                    Spacer()
                    status
                }
                if let bank = check.bankSideLatest {
                    Divider()
                    line(check.anchorDate.map { "Bank says, \($0.monthDay) statement" } ?? "Bank says", bank)
                } else {
                    Text("Import a statement with a closing balance to check this account against the bank.")
                        .font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let system = check.systemSideLatest {
                    Divider()
                    // The server compares both sides on the statement's date (iPadPAccount.dc.html).
                    line(check.anchorDate.map { "Finlynq on \($0.monthDay)" } ?? "Finlynq's balance", system)
                }
            }
        }
    }

    /// The server's `status` decides the chip. `no_anchor` means no statement balance yet; any other status with a
    /// zero difference is balanced, and with a difference shows it.
    @ViewBuilder
    private var status: some View {
        if check.status == "no_anchor" || check.bankSideLatest == nil {
            Chip(text: "No statement yet", tint: Theme.secondary, background: Theme.fill)
        } else if let delta = check.delta, abs(delta) >= 0.005 {
            Chip(text: "Off by \(abs(delta).money(check.currency ?? currency))", tint: Theme.warning, background: Theme.warningTint)
        } else if ["balanced", "matched", "ok", "reconciled"].contains(check.status) || check.delta != nil {
            Chip(text: "\u{2713} Balanced", tint: Theme.positive, background: Theme.positiveTint)
        } else {
            Chip(text: check.status.replacingOccurrences(of: "_", with: " ").capitalized, tint: Theme.secondary, background: Theme.fill)
        }
    }

    private func line(_ label: String, _ amount: Double) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.secondary)
            Spacer()
            Text(MoneyText.format(amount, currency: check.currency ?? currency)).fontWeight(.semibold).monospacedDigit()
        }
        .font(.subheadline)
    }
}

// MARK: Edit

/// Renames, regroups or archives an account with `PUT /api/accounts`. Import settings are changed on the website.
struct EditAccountSheet: View {
    let balance: Dashboard.Balance
    let account: Account?
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var alias = ""
    @State private var group = ""
    @State private var archived = false
    @State private var isInvestment = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Short name (optional)", text: $alias)
                    TextField("Group", text: $group)
                    Toggle("Archived", isOn: $archived)
                }
                if balance.accountType == "A" {
                    Section {
                        Toggle("Investment account", isOn: $isInvestment)
                    } footer: {
                        Text("Investment accounts hold securities and show on Investments. "
                            + "Every transaction in one names a holding or cash.")
                    }
                }
                Section {
                    LabeledContent("Currency", value: balance.currency)
                    LabeledContent("Imports", value: account?.mode?.capitalized ?? "Not set")
                } footer: {
                    Text("Change the import mode, CSV mapping and cash sleeves on the Finlynq website.")
                }
                if let error { Text(error).foregroundStyle(Theme.negative) }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onAppear {
                name = account?.name ?? balance.accountName ?? ""
                alias = account?.alias ?? balance.alias ?? ""
                group = balance.accountGroup
                archived = balance.archived
                isInvestment = account?.isInvestment ?? balance.isInvestment
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let trimmedAlias = alias.trimmingCharacters(in: .whitespaces)
        do {
            try await session.api.updateAccount(AccountUpdate(
                id: balance.accountId, name: name.trimmingCharacters(in: .whitespaces),
                alias: trimmedAlias.isEmpty ? nil : trimmedAlias, group: group.trimmingCharacters(in: .whitespaces), archived: archived,
                isInvestment: isInvestment
            ))
            await session.didSave()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
