import SwiftUI

/// The Invest segment (Invest.dc.html): Buy, Sell, Dividend, Deposit and Withdraw, plus a link to the web form.
struct InvestForm: View {
    @Environment(Session.self) private var session
    @Bindable var model: AddModel
    let usesPad: Bool
    @State private var positions: [PortfolioOverview.Position] = []

    private var brokerages: [Account] { session.accounts.filter { $0.isInvestment && !$0.archived } }
    private var banks: [Account] { session.accounts.filter { !$0.isInvestment && !$0.archived } }
    private var account: Account? { session.accounts.first { $0.id == model.accountId } }
    private var held: [PortfolioOverview.Position] {
        positions.filter { $0.accountId == model.accountId && !$0.isCash }
    }
    private var position: PortfolioOverview.Position? { held.first { $0.id == model.holdingId } }
    private var currency: String { account?.currency ?? session.currency }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            operations
            AddGroup {
                accounts
                if model.operation.usesShares || model.operation == .dividend {
                    Divider()
                    holding
                }
                Divider()
                if model.operation.usesShares { shareFields } else { amountAndDate }
            }
            if model.operation.usesShares { totalCard }
            if usesPad {
                HStack { PayeeNoteChip(model: model) }
            } else {
                PayeeNoteRows(model: model)
            }
        }
        .task { await loadHoldings() }
        .onChange(of: session.accounts) { _, _ in defaultAccounts() }
        .onChange(of: model.accountId) { _, _ in
            if !held.contains(where: { $0.id == model.holdingId }) { model.holdingId = nil }
        }
        .onChange(of: model.operation) { _, _ in
            model.holdingId = nil
            model.accountId = nil
            model.toAccountId = nil
            defaultAccounts()
        }
    }

    /// Three by two: five operations and "More", which opens the web form for the rest.
    private var operations: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(AddModel.InvestOperation.allCases) { operation in
                let selected = model.operation == operation
                Button { model.operation = operation } label: {
                    Text(operation.title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Theme.card : Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(selected ? Theme.text : Theme.card, in: Capsule())
                        .overlay { if !selected { Capsule().strokeBorder(Theme.secondary.opacity(0.25)) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            if let url = URL(string: session.savedServer + "/portfolio/new") {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text("More")
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.secondary.opacity(0.25)))
                }
                .accessibilityLabel("More operations: swap, in-kind transfer, FX conversion")
            }
        }
    }

    @ViewBuilder private var accounts: some View {
        switch model.operation {
        case .deposit:
            AddAccountRow(title: "From", selection: $model.accountId, options: banks)
            Divider()
            AddAccountRow(title: "To brokerage", selection: $model.toAccountId, options: brokerages)
        case .withdraw:
            AddAccountRow(title: "From brokerage", selection: $model.accountId, options: brokerages)
            Divider()
            AddAccountRow(title: "To", selection: $model.toAccountId, options: banks)
        default:
            AddAccountRow(title: "Account", selection: $model.accountId, options: brokerages)
        }
    }

    private var holding: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Holding").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Menu {
                Picker("Holding", selection: $model.holdingId) {
                    Text(model.operation == .dividend ? "None" : "Choose").tag(Int?.none)
                    ForEach(held) { Text($0.label).tag(Optional($0.id)) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                    Text(position?.label ?? (model.operation == .dividend ? "None" : "Choose"))
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                    if let name = position?.name, name != position?.symbol {
                        Text(name).font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(Theme.page, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Holding: \(position?.label ?? "none")")
            if let position, let quantity = position.quantity, let account {
                Text("You hold \(quantity.formatted()) shares in \(account.displayName)")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(.top, 10).padding(.bottom, 11)
    }

    @ViewBuilder private var shareFields: some View {
        HStack(spacing: 0) {
            field("Shares", text: $model.sharesText, prompt: "0")
            Divider()
            field("Price per share", text: $model.priceText, prompt: marketPrice.map { $0.formatted() } ?? "0.00",
                  caption: marketPrice == nil ? nil : "Market price", right: true)
        }
        .fixedSize(horizontal: false, vertical: true)
        Divider()
        HStack(spacing: 0) {
            field("Fees", text: $model.feesText, prompt: "0.00")
            Divider()
            dateField
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var amountAndDate: some View {
        HStack(spacing: 0) {
            field("Amount", text: $model.amountText, prompt: "0.00").accessibilityIdentifier("addAmount")
            Divider()
            dateField
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// One half of a two column row: caption over a large field. The right half is inset from the divider.
    private func field(_ title: String, text: Binding<String>, prompt: String, caption: String? = nil,
                       right: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            TextField(title, text: text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            if let caption { Text(caption).font(.system(size: 12)).foregroundStyle(Theme.secondary) }
        }
        .padding(.vertical, 10)
        .padding(right ? .leading : .trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateField: some View {
        AddDateButton(date: $model.date) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Date").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Text(dayLabel(model.date, long: false)).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            .padding(.vertical, 10)
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    private var marketPrice: Double? { position?.price }

    private var totalCard: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.operation == .buy ? "Total cost" : "Total proceeds").font(.system(size: 15, weight: .semibold))
            Spacer()
            Text(model.investTotal.money(currency)).font(.system(size: 26, weight: .bold)).tracking(-0.5).monospacedDigit()
        }
        .foregroundStyle(Theme.text)
        .padding(14)
        .background(Theme.page, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func loadHoldings() async {
        positions = (try? await session.api.portfolioOverview())?.holdings ?? []
        defaultAccounts()
        if let symbol = model.prefillSymbol, model.holdingId == nil {
            model.holdingId = held.first { $0.symbol == symbol }?.id
        }
    }

    private func defaultAccounts() {
        switch model.operation {
        case .deposit:
            model.accountId = model.accountId ?? banks.first?.id
            model.toAccountId = model.toAccountId ?? brokerages.first?.id
        case .withdraw:
            model.accountId = model.accountId ?? brokerages.first?.id
            model.toAccountId = model.toAccountId ?? banks.first?.id
        default:
            model.accountId = model.accountId ?? brokerages.first?.id
        }
    }
}
