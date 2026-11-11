import SwiftUI

/// Debts (Debts.dc.html, MacLoan.dc.html): what is owed, when it is paid off and the projected balance, then the
/// loans and credit cards. iPhone and iPad portrait (iPadPDebts.dc.html) push a loan; iPad landscape and a wide Mac
/// window show the selected loan beside the list.
struct DebtsView: View {
    @Environment(Session.self) private var session
    @Environment(\.layoutWidth) private var width
    @State private var data: DebtsData?
    @State private var error: String?
    @State private var selected: Int?
    @Environment(\.presentEditor) private var present

    struct DebtsData {
        let dashboard: Dashboard
        let loans: [Loan]
        let today: Date
        /// Each loan's server schedule by loan id. A loan whose schedule failed to load is missing.
        var schedules: [Int: Amortization] = [:]
        /// The latest payment into each card account, by account id.
        var cardPayments: [Int: Transaction] = [:]
        var schedulesFailed = false

        func facts(_ loan: Loan) -> WealthModel.LoanFacts { WealthModel.facts(loan, schedule: schedules[loan.id], today: today) }

        /// Liabilities with no loan linked to them, such as credit cards.
        var cards: [Dashboard.Balance] {
            WealthModel.debts(dashboard.balances).filter { balance in !loans.contains { $0.accountId == balance.accountId } }
        }
        /// Loans that still have a balance.
        var active: [Loan] { loans.filter { WealthModel.remaining($0) > 0.005 } }
    }

    /// iPad landscape and a wide Mac window show the loan beside the list; narrower columns push it.
    private var isWide: Bool { width == .wide }

    var body: some View {
        LoadState(value: data, error: error, retry: reload) { data in
            if data.active.isEmpty && data.cards.isEmpty {
                EmptyState(title: "No debts", message: "Loans and credit cards you track in Finlynq show here.", symbol: "checkmark.seal")
            } else if isWide {
                wide(data)
            } else {
                ScrollView { phone(data) }
            }
        }
        .background(Theme.page)
        .navigationTitle("Debts")
        #if os(iOS)
        .toolbarTitleDisplayMode(.large)
        #endif
        .navigationDestination(for: AppRoute.self) { RouteDestination(route: $0) }
        .task(id: session.revision) { await load() }
        .refreshable { await load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add loan", systemImage: "creditcard.badge.plus") { present(.addLoan) }.macTitleAndIcon().help("Add a loan")
            }
        }
    }

    // MARK: iPhone

    private func phone(_ data: DebtsData) -> some View {
        VStack(spacing: 12) {
            summaryCard(data)
            if !data.active.isEmpty {
                WealthSectionHeader(title: "Loans") { EmptyView() }
                ForEach(data.active) { loan in
                    NavigationLink(value: AppRoute.loan(loan.id)) { Card(padding: 16) { loanRow(loan, data: data) } }.buttonStyle(.plain)
                }
            }
            if !data.cards.isEmpty {
                WealthSectionHeader(title: "Credit cards") { EmptyView() }
                Card(padding: 16) {
                    DividedRows(items: data.cards) { card in
                        NavigationLink(value: AppRoute.account(card.accountId)) {
                            cardRow(card, payment: data.cardPayments[card.accountId])
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            tip(data)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }

    private func summaryCard(_ data: DebtsData) -> some View {
        let currency = data.dashboard.displayCurrency
        let owed = abs(WealthModel.debts(data.dashboard.balances).reduce(0) { $0 + $1.convertedBalance })
        let projection = WealthModel.debtProjection(data.active.map { ($0, data.schedules[$0.id]?.schedule ?? []) }, today: data.today)
        let year = Calendar(identifier: .gregorian).component(.year, from: data.today)
        let monthly = data.active.reduce(0) {
            $0 + ($1.monthlyEquivalentPaymentDisplay ?? WealthModel.payment($1) * WealthModel.displayRate($1))
        }
        let thisYear = data.active.reduce(0) {
            $0 + WealthModel.interest(data.schedules[$1.id]?.schedule ?? [], year: year) * WealthModel.displayRate($1)
        }
        let left = data.active.reduce(0) { $0 + (data.facts($1).interestLeft ?? 0) * WealthModel.displayRate($1) }
        let debtFree = data.active.compactMap { data.facts($0).payoff }.max()
        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total owed").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                        Text(owed.wholeMoney(currency)).font(.system(size: 36, weight: .bold)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Spacer()
                    if let end = debtFree, width == .compact {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Debt-free").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                            Text(end.monthYear).font(.title3.weight(.bold)).foregroundStyle(Theme.positive)
                        }
                    }
                }
                // iPadPDebts.dc.html: the hero keeps its line and the payoff goes under it.
                if let end = debtFree, width != .compact {
                    Chip(text: "Debt-free in \(end.monthYear)", tint: Theme.positive, background: Theme.positiveTint)
                }
                if projection.count > 1 {
                    TimeSeriesChart(points: projection, color: Theme.spendBar, height: 110, xAxis: .nowAndYears,
                                    currency: currency, fromZero: true)
                        .accessibilityLabel("Projected total debt falling to zero by \(projection.last?.day.monthYear ?? "")")
                }
                if data.schedulesFailed { InlineError(message: "Couldn't load every loan's schedule", retry: reload) }
                let frequency = data.active.count == 1 ? data.active[0].paymentFrequency : "monthly"
                if let note = WealthModel.payoffNote(payoff: debtFree, scheduleEnd: projection.last?.day, frequency: frequency) {
                    Text(note).font(.footnote).foregroundStyle(Theme.secondary)
                }
                Divider()
                HStack(alignment: .top) {
                    Figure(label: "Monthly", value: monthly.wholeMoney(currency))
                    Figure(label: "Interest \(String(year))", value: thisYear.wholeMoney(currency))
                    Figure(label: "Interest left", value: left.wholeMoney(currency))
                }
            }
        }
    }

    private func loanRow(_ loan: Loan, data: DebtsData) -> some View {
        let facts = data.facts(loan)
        let parts = [
            WealthModel.rateText(loan), WealthModel.paymentLabel(loan, short: true),
            facts.next.flatMap { APIDate.parse($0.date) }.map { "next \($0.monthDay)" }
        ].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconTile(symbol: Self.symbol(loan), tint: Theme.warning, background: Theme.warningTint, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loan.displayName).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(parts.joined(separator: " \u{00B7} ")).font(.subheadline).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text(WealthModel.remaining(loan).wholeMoney(loan.currency)).font(.body.weight(.semibold)).monospacedDigit()
            }
            ProgressLine(value: WealthModel.percentPaid(loan), color: Theme.spendBar, height: 6)
            HStack {
                Text("\(Int((WealthModel.percentPaid(loan) * 100).rounded()))% paid")
                Spacer()
                Text(facts.payoff.map { "Paid off \($0.monthYear)" } ?? "No payoff date")
            }
            .font(.footnote).foregroundStyle(Theme.secondary)
        }
        .contentShape(Rectangle())
    }

    private func cardRow(_ card: Dashboard.Balance, payment: Transaction?) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: "creditcard", size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                if let payment { Text(WealthModel.lastPaidText(payment)).font(.subheadline).foregroundStyle(Theme.secondary) }
            }
            Spacer()
            Text(abs(card.balance).wholeMoney(card.currency)).font(.body.weight(.semibold)).monospacedDigit()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// "Pay $200 more a month on the car loan…" for the largest loan, when it would finish sooner.
    @ViewBuilder
    private func tip(_ data: DebtsData) -> some View {
        let owed = { (loan: Loan) in WealthModel.remaining(loan) * WealthModel.displayRate(loan) }
        if let loan = data.active.filter(WealthModel.supportsWhatIf).max(by: { owed($0) < owed($1) }),
           let result = WealthModel.whatIf(loan, extra: 200, today: data.today), result.monthsSooner > 0 {
            let extra = 200.0.wholeMoney(loan.currency)
            let months = "\(result.monthsSooner) \(result.monthsSooner == 1 ? "month" : "months")"
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "lightbulb").font(.title3.weight(.semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40).background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                let lead = Text("Pay \(extra) more a month").fontWeight(.bold)
                let saved = result.interestSaved.wholeMoney(loan.currency)
                Text("\(lead) on the \(loan.displayName.lowercased()) to finish \(months) sooner and save \(saved) in interest.")
                    .font(.subheadline).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    static func symbol(_ loan: Loan) -> String {
        let text = "\(loan.type) \(loan.displayName)".lowercased()
        if text.contains("car") || text.contains("auto") || text.contains("lease") { return "car.fill" }
        if text.contains("mortgage") || text.contains("home") { return "house.fill" }
        if text.contains("student") { return "graduationcap.fill" }
        return "doc.text.fill"
    }
}

extension DebtsView {
    // MARK: iPad and Mac

    private func wide(_ data: DebtsData) -> some View {
        let current = selected ?? data.active.first?.id
        return HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    sideSummary(data)
                    if !data.active.isEmpty {
                        sideHeader("Loans")
                        ForEach(data.active) { loan in
                            Button { selected = loan.id } label: { sideLoan(loan, selected: loan.id == current) }.buttonStyle(.plain)
                        }
                    }
                    if !data.cards.isEmpty {
                        sideHeader("Credit cards")
                        ForEach(data.cards) { card in
                            NavigationLink(value: AppRoute.account(card.accountId)) {
                                sideCard(card, payment: data.cardPayments[card.accountId])
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxWidth: 300)
            Divider()
            Group {
                if let current {
                    // The loan picks its layout from the pane's width, not the whole column's.
                    LoanView(id: current, embedded: true).id(current).measuresLayoutWidth()
                } else {
                    EmptyState(title: "No loans", message: "Credit cards are listed on the left.", symbol: "creditcard")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func sideSummary(_ data: DebtsData) -> some View {
        let currency = data.dashboard.displayCurrency
        let owed = abs(WealthModel.debts(data.dashboard.balances).reduce(0) { $0 + $1.convertedBalance })
        let end = data.active.compactMap { data.facts($0).payoff }.max()
        return VStack(spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total owed").font(.subheadline).foregroundStyle(Theme.secondary)
                    Text(owed.wholeMoney(currency)).font(.title2.weight(.bold)).monospacedDigit()
                }
                Spacer()
                if let end {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Debt-free").font(.subheadline).foregroundStyle(Theme.secondary)
                        Text(end.monthYear).font(.subheadline.weight(.semibold))
                    }
                }
            }
            Divider()
        }
        .padding(.horizontal, 12).padding(.top, 8)
    }

    private func sideHeader(_ title: String) -> some View {
        Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary).padding(.horizontal, 12).padding(.top, 6)
    }

    private func sideLoan(_ loan: Loan, selected: Bool) -> some View {
        let tint: Color = selected ? .white : Theme.text
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                IconTile(symbol: Self.symbol(loan), tint: selected ? .white : Theme.accent,
                         background: selected ? .white.opacity(0.2) : Theme.accentTint, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(loan.displayName).font(.subheadline.weight(.semibold))
                    Text("\(WealthModel.rateText(loan)) \u{00B7} \(WealthModel.paymentLabel(loan, short: true))")
                        .font(.footnote.weight(.medium)).opacity(0.85)
                }
                Spacer()
                Text(WealthModel.remaining(loan).wholeMoney(loan.currency)).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            ProgressLine(value: WealthModel.percentPaid(loan), color: selected ? .white : Theme.spendBar, height: 4)
                .padding(.leading, 38)
        }
        .foregroundStyle(tint)
        .padding(12)
        .background(selected ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }

    private func sideCard(_ card: Dashboard.Balance, payment: Transaction?) -> some View {
        HStack(spacing: 10) {
            IconTile(symbol: "creditcard", size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(card.name).font(.subheadline.weight(.semibold))
                if let payment { Text(WealthModel.lastPaidText(payment)).font(.footnote).foregroundStyle(Theme.secondary) }
            }
            Spacer()
            Text(abs(card.balance).wholeMoney(card.currency)).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .padding(12)
        .contentShape(Rectangle())
    }

    // MARK: Loading

    private func reload() { Task { await load() } }

    private func load() async {
        let api = session.api
        do {
            async let dashboard = api.dashboard()
            async let loans = api.loans()
            var next = DebtsData(dashboard: try await dashboard, loans: try await loans, today: Fixtures.today)
            for loan in next.active {
                do {
                    next.schedules[loan.id] = try await api.loanAmortization(id: loan.id)
                } catch is CancellationError {
                    return
                } catch {
                    WealthView.log.error("amortization failed for \(loan.id): \(String(describing: error), privacy: .public)")
                    next.schedulesFailed = true
                }
            }
            next.cardPayments = await api.lastPayments(accountIds: next.cards.map(\.accountId))
            data = next
            error = nil
        } catch is CancellationError {
        } catch {
            WealthView.log.error("debts failed: \(String(describing: error), privacy: .public)")
            self.error = error.localizedDescription
        }
    }
}
