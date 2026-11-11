import SwiftUI

#if os(macOS)
struct ReconcileView: View {
    @Environment(Session.self) private var session
    @Environment(\.layoutWidth) private var width
    @Environment(\.layoutColumn) private var column
    /// The Mac toolbar's search field types into Activity's search, which filters these rows too.
    @Environment(ActivityStore.self) private var activity
    private var search: String { activity.search }
    @State private var model = ReconcileModel()
    @State private var picking = false
    private let today = Fixtures.today

    private var account: Account? { session.accounts.first { $0.id == model.accountId } }
    private var currency: String? { account?.currency }

    var body: some View {
        VStack(spacing: 0) {
            content
            footer
        }
        .background(Theme.page)
        .navigationTitle("Review imports")
        // The title is drawn in the toolbar item, before the popups, as in the design. A narrow window keeps the
        // system title and puts the popups above the panes.
        .toolbar(removing: popupsInBar ? .title : nil)
        .toolbar { toolbar }
        .task(id: "\(model.accountId ?? 0)|\(model.window.rawValue)") { await model.load(session, today: today) }
        .importsDroppedStatements()
        .sheet(isPresented: $picking) {
            ReviewCategoryPicker(amount: model.selectedBank.first?.amount ?? 0, selected: nil) { id in
                picking = false
                Task { await model.addAsNew(session, categoryId: id, today: today) }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // MacReview.dc.html: the account and date popups sit after the title; Approve all sits on the right.
        if popupsInBar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Text("Review imports").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text).padding(.trailing, 8)
                        .accessibilityAddTraits(.isHeader)
                    popups
                }
                .fixedSize()
            }
            .sharedBackgroundHidden()
        }
        if #available(macOS 26, *) { ToolbarSpacer(.flexible) }
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await model.approveAllSuggested(session, today: today) } } label: {
                Label("Approve all suggested (\(model.snapshot?.suggestions.count ?? 0))", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.hairline))
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .help("Link every suggested match (Shift-Command-A)")
            .disabled((model.snapshot?.suggestions.isEmpty ?? true) || model.isWorking)
        }
        .sharedBackgroundHidden()
    }

    /// The toolbar holds the title and popups from about 640pt; a narrower column hides that item.
    private var popupsInBar: Bool { (column ?? .infinity) >= MacDesignWidth.reviewToolbar }

    /// The account and date popups.
    @ViewBuilder
    private var popups: some View {
        Menu {
            Picker("Account", selection: $model.accountId) {
                ForEach(session.accounts.filter { !$0.archived && !$0.isInvestment }) { Text($0.displayName).tag(Optional($0.id)) }
            }
        } label: {
            ReconcilePopup(symbol: "building.columns", text: account?.displayName ?? "Account")
        }
        .menuStyle(.button).buttonStyle(.plain).fixedSize()
        .accessibilityLabel("Account: \(account?.displayName ?? "none")")
        Menu {
            Picker("Dates", selection: $model.window) {
                ForEach(ReconcileModel.Window.allCases, id: \.self) { Text($0.label).tag($0) }
            }
        } label: {
            ReconcilePopup(symbol: "calendar", text: rangeLabel.text, detail: rangeLabel.detail)
        }
        .menuStyle(.button).buttonStyle(.plain).fixedSize()
    }

    /// "Oct 10 to Nov 8" and "· 30 days".
    private var rangeLabel: (text: String, detail: String?) {
        guard let start = model.dateMin(today: today) else { return ("All dates", nil) }
        return ("\(reviewDay(start)) to \(reviewDay(APIDate.string(today)))", "· \(model.window.label)")
    }

    @ViewBuilder
    private var content: some View {
        if let message = model.loadError {
            ContentUnavailableView {
                Label("Couldn't load the bank rows", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load(session, today: today) } }
            }
        } else if model.snapshot == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                if !popupsInBar { HStack(spacing: 8) { popups; Spacer() } }
                if !model.staged.isEmpty { stagedBanner }
                // MacReview sets the panes side by side; a narrower window stacks them, as each needs about 550pt.
                if LayoutWidth.fitsMacDesign(width, column: column, needs: MacDesignWidth.review) {
                    HStack(alignment: .top, spacing: 16) { bankPane; ledgerPane }
                } else {
                    VStack(spacing: 12) { bankPane; ledgerPane }
                }
                if let message = model.error {
                    Text(message).foregroundStyle(Theme.negative).frame(maxWidth: .infinity, alignment: .leading)
                }
                if !model.bankSelection.isEmpty || !model.ledgerSelection.isEmpty { actionBar }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)
        }
    }

    private func matches(_ text: String?) -> Bool { search.isEmpty || (text ?? "").localizedCaseInsensitiveContains(search) }

    // MARK: Panes

    private var stagedBanner: some View {
        HStack(spacing: 12) {
            IconTile(symbol: "tray.and.arrow.down", size: 32)
            Text("\(model.staged.count) imported row\(model.staged.count == 1 ? " isn't" : "s aren't") in the bank ledger yet.")
                .fontWeight(.semibold)
            Spacer()
            Button("Load into bank rows") { Task { await model.loadStaged(session, today: today) } }
                .disabled(model.isWorking)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var bankPane: some View {
        let rows = model.bankRows.filter { matches($0.payee) }
        let uploaded = model.snapshot?.bankTransactions.values.compactMap(\.firstSeenAt).max().flatMap { APIDate.parse($0) }
        let statement = account.map { name in
            "\(name.displayName) statement" + (uploaded.map { ", uploaded \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "")
        }
        let subtitle = [statement, "\(rows.count) rows"].compactMap(\.self).joined(separator: " · ")
        let allSelected = !rows.isEmpty && rows.allSatisfy { model.bankSelection.contains($0.id) }
        return Pane(
            title: "Bank rows", symbol: "doc.text", subtitle: subtitle, selected: model.bankSelection.count,
            columns: ("Description", "Status"), allSelected: allSelected,
            onSelectAll: { model.bankSelection = $0 ? Set(rows.map(\.id)) : [] },
            rows: {
                ForEach(rows, id: \.id) { row in
                    let isSelected = model.bankSelection.contains(row.id)
                    PaneRow(
                        isSelected: isSelected, date: row.date, amount: row.amount, currency: row.currency,
                        status: model.status(bank: row.id), label: "Select \(row.payee ?? "row"), \(reviewDay(row.date))",
                        onToggle: { toggle(&model.bankSelection, row.id) },
                        description: {
                            Text(row.payee ?? "").font(.system(size: 12, design: .monospaced))
                                .fontWeight(isSelected ? .semibold : .regular).lineLimit(2)
                        }
                    )
                }
            }
        )
    }

    private var ledgerPane: some View {
        let rows = model.ledgerRows.filter { matches($0.payee) || matches($0.categoryName) }
        let subtitle = [account.map { "\($0.displayName), same dates" }, "\(rows.count) transactions"]
            .compactMap(\.self).joined(separator: " · ")
        let bankTotal = model.selectedBank.reduce(0) { $0 + $1.amount }
        let allSelected = !rows.isEmpty && rows.allSatisfy { model.ledgerSelection.contains($0.id) }
        return Pane(
            title: "Finlynq transactions", symbol: "arrow.left.arrow.right", subtitle: subtitle, selected: model.ledgerSelection.count,
            columns: ("Payee · category", "Status"), allSelected: allSelected,
            onSelectAll: { model.ledgerSelection = $0 ? Set(rows.map(\.id)) : [] },
            rows: {
                ForEach(rows, id: \.id) { row in
                    let isSelected = model.ledgerSelection.contains(row.id)
                    PaneRow(
                        isSelected: isSelected, date: row.date, amount: row.amount, currency: row.currency,
                        status: model.status(ledger: row.id), label: "Select \(row.payee ?? "transaction"), \(reviewDay(row.date))",
                        onToggle: { toggle(&model.ledgerSelection, row.id) },
                        description: {
                            VStack(alignment: .leading, spacing: 0) {
                                (Text(row.payee ?? "No payee").fontWeight(.medium)
                                    + Text(row.categoryName.map { " · \($0)" } ?? "").foregroundStyle(Theme.secondary))
                                    .lineLimit(2)
                                if isSelected, model.selectedBank.count > 1, abs(bankTotal - row.amount) < 0.005 {
                                    Text("Best match for the \(model.selectedBank.count) selected rows")
                                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    )
                }
            }
        )
    }

    /// "1 bank row", "2 bank rows".
    private func plural(_ count: Int, _ noun: String) -> String { "\(count) \(noun)\(count == 1 ? "" : "s")" }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    // MARK: Selection actions

    private var actionBar: some View {
        let banks = model.selectedBank
        let ledger = model.selectedLedger
        let bankTotal = banks.reduce(0) { $0 + $1.amount }
        let ledgerTotal = ledger.reduce(0) { $0 + $1.amount }
        let difference = ledgerTotal - bankTotal
        var summary = Text("\(plural(banks.count, "bank row")), \(reviewMoney(bankTotal, currency)) · ")
            + Text("\(plural(ledger.count, "transaction")), \(reviewMoney(ledgerTotal, currency))")
        if !banks.isEmpty, !ledger.isEmpty {
            summary = summary + Text(" · ") + (abs(difference) < 0.005
                ? Text("No difference").foregroundStyle(Theme.positive)
                : Text("\(reviewMoney(difference, currency)) difference").foregroundStyle(Theme.warning))
        }
        let addable = model.selectedUnlinked
        let needsCategory = addable.contains { $0.suggestedCategoryId == nil }
        return HStack(spacing: 12) {
            IconTile(symbol: "link", size: 32)
            VStack(alignment: .leading, spacing: 1) {
                summary.fontWeight(.semibold)
                if let reason = model.selectionReason { Text(reason).font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            }
            Spacer()
            Button { model.clearSelection() } label: {
                Image(systemName: "xmark").foregroundStyle(Theme.secondary).frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Clear selection (Esc)")
            .accessibilityLabel("Clear selection")
            barButton("Ignore") { model.ignoreSelection() }.disabled(banks.isEmpty)
            barButton("Add as new") {
                if needsCategory { picking = true } else { Task { await model.addAsNew(session, categoryId: nil, today: today) } }
            }
            .disabled(addable.isEmpty || !ledger.isEmpty)
            .help(addable.count < banks.count ? "Linked bank rows are left out" : "Book the selected bank rows as new transactions")
            Button { Task { await model.link(session, today: today) } } label: {
                Text("Link \(plural(banks.count, "bank row")) to \(plural(ledger.count, "transaction"))")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 30)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("l")
            .help("Link (Command-L)")
            .disabled(banks.isEmpty || ledger.isEmpty)
            .opacity(banks.isEmpty || ledger.isEmpty ? 0.45 : 1)
        }
        .disabled(model.isWorking)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.accent.opacity(0.2)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions for the selected rows")
    }

    private func barButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                .padding(.horizontal, 12).frame(height: 30)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.hairline))
        }
        .buttonStyle(.plain)
    }
}

extension ReconcileView {
    // MARK: Footer

    /// One line in a wide window. A narrower one moves the counts to a second line, then the date to a line of its
    /// own, so no amount is cut.
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                balanceLine(dated: true)
                Spacer()
                counts
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) { balanceLine(dated: true) }
                counts
            }
            VStack(alignment: .leading, spacing: 2) {
                balanceLines
                counts
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 20).padding(.vertical, 8).frame(minHeight: 36)
        .background(Theme.toolbar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var counts: some View {
        Text(model.countsLine).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize()
    }

    /// The balance check on two lines: the date, then the two sides and the badge.
    @ViewBuilder
    private var balanceLines: some View {
        if let balance = model.balance, let date = balance.latestAnchor?.statementDate ?? balance.latestAnchor?.date {
            Text("Balance on \(reviewDay(date))").foregroundStyle(Theme.secondary).fixedSize()
        }
        HStack(spacing: 10) { balanceLine(dated: false) }
    }

    @ViewBuilder
    private func balanceLine(dated: Bool) -> some View {
        Group {
            if let balance = model.balance {
                if dated, let date = balance.latestAnchor?.statementDate ?? balance.latestAnchor?.date {
                    Text("Balance on \(reviewDay(date))").foregroundStyle(Theme.secondary)
                }
                if let bank = balance.bankSideLatest {
                    Text("Bank ") + Text(bank.money(balance.currency ?? currency)).fontWeight(.bold)
                    Text("·").foregroundStyle(Theme.secondary.opacity(0.7))
                }
                if let ledger = balance.systemSideLatest {
                    Text("Finlynq ") + Text(ledger.money(balance.currency ?? currency)).fontWeight(.bold)
                }
                switch balance.status {
                case "balanced":
                    Text("·").foregroundStyle(Theme.secondary.opacity(0.7))
                    ReviewBadge(text: "Balanced", symbol: "checkmark", tint: Theme.positive, background: Theme.positiveTint)
                case "mismatch":
                    Text("·").foregroundStyle(Theme.secondary.opacity(0.7))
                    let delta = (balance.delta ?? 0).money(balance.currency ?? currency)
                    ReviewBadge(text: "Off by \(delta)", tint: Theme.warning, background: Theme.warningTint)
                default:
                    Text("· No bank balance yet").foregroundStyle(Theme.secondary)
                }
            }
        }
        .fixedSize()
    }
}

/// The date column: "Nov 8" fits in 48pt, which a narrow window gives to the description instead of 64.
private func reviewDateWidth(_ column: CGFloat?) -> CGFloat { (column ?? .infinity) < MacDesignWidth.reviewToolbar ? 48 : 64 }

/// Toolbar popup: icon, value, optional grey detail and a chevron, 26pt high.
private struct ReconcilePopup: View {
    let symbol: String
    let text: String
    var detail: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
            Text(text).font(.system(size: 13, weight: .medium))
            if let detail { Text(detail).font(.system(size: 13)).foregroundStyle(Theme.secondary) }
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary)
        }
        .foregroundStyle(Theme.text).lineLimit(1)
        .padding(.leading, 10).padding(.trailing, 8).frame(height: 26)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.hairline))
        .contentShape(Rectangle())
    }
}

/// A card with a title row, a table header and scrolling rows (one side of MacReview.dc.html).
private struct Pane<Rows: View>: View {
    @Environment(\.layoutColumn) private var column
    let title: String
    let symbol: String
    let subtitle: String
    let selected: Int
    let columns: (String, String)
    let allSelected: Bool
    let onSelectAll: (Bool) -> Void
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(Theme.secondary)
                Text(title).font(.system(size: 15, weight: .bold))
                Text(subtitle).foregroundStyle(Theme.secondary).lineLimit(1)
                Spacer()
                if selected > 0 {
                    Text("\(selected) selected").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(.horizontal, 16).frame(height: 48)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: 0) {
                Toggle("Select all", isOn: Binding(get: { allSelected }, set: { onSelectAll($0) })).toggleStyle(.checkbox).labelsHidden()
                    .frame(width: 36, alignment: .leading)
                HStack(spacing: 4) {
                    Text("Date").fontWeight(.semibold).foregroundStyle(Theme.text)
                    Image(systemName: "arrow.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.accent)
                }
                .frame(width: reviewDateWidth(column), alignment: .leading).padding(.horizontal, 8)
                Text(columns.0).padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading)
                Text("Amount").padding(.horizontal, 8).frame(width: 120, alignment: .trailing)
                Text(columns.1).padding(.leading, 8).frame(width: 100, alignment: .leading)
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
            .padding(.horizontal, 16).frame(height: 30)
            .background(Theme.toolbar)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.fill).frame(height: 1) }
            ScrollView {
                LazyVStack(spacing: 0) { rows }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Theme.cardShadow, radius: 1, y: 1)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardBorder))
    }
}

private struct PaneRow<Description: View>: View {
    @Environment(\.layoutColumn) private var column
    let isSelected: Bool
    let date: String
    let amount: Double
    let currency: String?
    let status: ReconcileModel.Status
    let label: String
    let onToggle: () -> Void
    @ViewBuilder let description: Description

    var body: some View {
        HStack(spacing: 0) {
            Toggle(label, isOn: Binding(get: { isSelected }, set: { _ in onToggle() })).toggleStyle(.checkbox).labelsHidden()
                .frame(width: 36, alignment: .leading)
            Text(reviewDay(date)).foregroundStyle(Theme.secondary).frame(width: reviewDateWidth(column), alignment: .leading)
                .padding(.horizontal, 8)
            description.padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading)
            Text(reviewMoney(amount, currency)).fontWeight(.semibold).monospacedDigit()
                .foregroundStyle(amount > 0 ? Theme.positive : Theme.text)
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 8).frame(width: 120, alignment: .trailing)
            badge.padding(.leading, 8).frame(width: 100, alignment: .leading)
        }
        .padding(.horizontal, 16).frame(minHeight: 34).padding(.vertical, 1)
        .background(isSelected ? Theme.accentTint : .clear)
        .overlay(alignment: .leading) { if isSelected { Rectangle().fill(Theme.accent).frame(width: 3) } }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.fill.opacity(0.7)).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }

    @ViewBuilder
    private var badge: some View {
        switch status {
        case .linked: ReviewBadge(text: "Linked", tint: Theme.positive, background: Theme.positiveTint)
        case .suggested: ReviewBadge(text: "Suggested", tint: Theme.accent, background: Theme.accentTint)
        case .bankOnly: ReviewBadge(text: "Bank only", tint: Theme.warning, background: Theme.warningTint)
        case .ledgerOnly: ReviewBadge(text: "Finlynq only", tint: Theme.warning, background: Theme.warningTint)
        }
    }
}
#endif
