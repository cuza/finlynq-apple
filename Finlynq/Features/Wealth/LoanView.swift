import Charts
import SwiftUI

/// One loan (Loan.dc.html, LoanPlan.dc.html, MacLoan.dc.html): what is left, the server's amortization schedule,
/// and a What-if for an extra monthly payment that the local `Amortization` computes as the slider moves.
/// Record payment books a transfer from a cash account to the loan's account; Apply saves the extra payment.
/// iPhone splits the page into Payoff, Schedule and What if tabs; wider columns show them on one page (iPadPLoan.dc.html).
struct LoanView: View {
    let id: Int
    /// Shown beside the Debts list (iPad and Mac) rather than pushed.
    var embedded = false
    @Environment(Session.self) private var session
    @Environment(\.layoutWidth) private var width
    @Environment(\.layoutColumn) private var column
    @State private var data: LoanData?
    @State private var error: String?
    @State private var tab = Tab.payoff
    @State private var extra = 200.0
    @Environment(\.presentEditor) private var present
    @State private var confirmPayment = false
    @State private var confirmExtra = false
    @State private var notice: String?

    enum Tab: String, CaseIterable { case payoff = "Payoff", schedule = "Schedule", whatIf = "What if" }

    struct LoanData {
        let loan: Loan
        /// The server's schedule from the loan's terms. Nil when the request failed.
        var schedule: Amortization?
        var scheduleFailed = false
        /// Cash accounts a payment can come from.
        let payers: [Dashboard.Balance]
        let today: Date

        /// Payoff, payments left, next payments and interest: all from the server.
        var facts: WealthModel.LoanFacts { WealthModel.facts(loan, schedule: schedule, today: today) }
        /// The local engine only runs What-if, and only for loans it models.
        var supportsWhatIf: Bool { WealthModel.supportsWhatIf(loan) }
        var currency: String { loan.currency }
        var paymentText: String { WealthModel.paymentLabel(loan, short: false) }
        /// Set when the payoff at the current balance differs from the end of the server's schedule.
        var payoffNote: String? {
            WealthModel.payoffNote(
                payoff: facts.payoff, scheduleEnd: schedule?.schedule.last.flatMap { APIDate.parse($0.date) },
                frequency: loan.paymentFrequency
            )
        }
        var rateText: String { loan.annualRate.formatted(.number.precision(.fractionLength(0...2))) + "%" }
        var paidText: String { "\(Int((WealthModel.percentPaid(loan) * 100).rounded()))% paid" }

        /// "Mar 2030 · 40 payments left", with the date bold.
        var payoffLine: Text {
            let facts = facts
            guard let payoff = facts.payoff else { return Text(WealthModel.remaining(loan) > 0 ? "No payoff date" : "Paid off") }
            let date = Text(payoff.monthYear).fontWeight(.semibold).foregroundStyle(Theme.text)
            guard let left = facts.paymentsLeft else { return date }
            return Text("\(date) \u{00B7} \(left) \(left == 1 ? "payment" : "payments") left")
        }

        var interestLeftText: String { facts.interestLeft.map { $0.wholeMoney(loan.currency) } ?? "\u{2014}" }

        /// The next payment's date from the server schedule, e.g. "Nov 15".
        var nextDay: String? { facts.next.flatMap { APIDate.parse($0.date)?.monthDay } }

        /// "Amortizing loan · Next payment Nov 15".
        var subtitle: String {
            let kind = loan.type == "lease" ? "Lease" : loan.type == "mortgage" ? "Mortgage" : "Amortizing loan"
            return [kind, nextDay.map { "Next payment \($0)" }].compactMap { $0 }.joined(separator: " \u{00B7} ")
        }
    }

    var body: some View {
        LoadState(value: data, error: error, retry: reload) { data in
            #if os(macOS)
            if macDesign {
                LoanMacDetail(data: data, extra: $extra, edit: edit, record: askPayment, apply: askExtra, retry: reload)
            } else if width == .compact { phone(data) } else { page(data) }
            #else
            if width == .compact { phone(data) } else { page(data) }
            #endif
        }
        .background(Theme.page)
        .navigationTitle(embedded ? "Debts" : data?.loan.displayName ?? "Loan")
        #if os(iOS)
        .toolbarTitleDisplayMode(embedded ? .inlineLarge : .large)
        #endif
        .toolbar {
            // MacLoan has Edit beside the loan's name. Embedded in Debts, the toolbar is the Debts page's, so it names
            // the loan.
            if !macDesign {
                ToolbarItem(placement: .primaryAction) { Button(embedded ? "Edit loan" : "Edit", action: edit).disabled(data == nil) }
            }
        }
        .task(id: session.revision) { await load() }
        .confirmationDialog(paymentTitle, isPresented: $confirmPayment, titleVisibility: .visible) {
            ForEach(data?.payers ?? []) { payer in
                Button("From \(payer.name)") { Task { await recordPayment(from: payer.accountId) } }
            }
        } message: {
            Text("Records a transfer to \(data?.loan.accountName ?? "the loan account").")
        }
        .confirmationDialog("Pay \(extra.wholeMoney(data?.currency)) extra each month?", isPresented: $confirmExtra,
            titleVisibility: .visible) {
            Button("Save extra payment") { Task { await applyExtra() } }
        } message: {
            Text("Saves the extra payment on the loan, so its schedule and payoff date change.")
        }
        .alert("Loan", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK") { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    /// MacLoan's stats row, What if row and schedule table need about 900pt.
    private var macDesign: Bool {
        #if os(macOS)
        LayoutWidth.fitsMacDesign(width, column: column, needs: MacDesignWidth.loan)
        #else
        false
        #endif
    }

    private func reload() { Task { await load() } }
    private func edit() { if let data { present(.editLoan(data.loan)) } }
    private func askPayment() { confirmPayment = true }
    private func askExtra() { confirmExtra = true }

    private var paymentTitle: String {
        guard let data, let next = data.facts.next, let day = data.nextDay else { return "Record payment" }
        return "Record the \(day) payment of \(next.payment.money(data.currency))"
    }

    // MARK: iPhone and iPad, and narrower Mac windows

    private func phone(_ data: LoanData) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                summaryCard(data, compact: tab == .whatIf)
                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                switch tab {
                case .payoff: payoff(data)
                case .schedule: LoanScheduleList(data: data, retry: reload)
                case .whatIf: LoanWhatIf(data: data, extra: $extra)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomAction(data) }
    }

    @ViewBuilder
    private func bottomAction(_ data: LoanData) -> some View {
        if tab == .whatIf {
            if extra > 0 && data.supportsWhatIf {
                BottomActions(actions: [.init(title: "Pay \(extra.wholeMoney(data.currency)) extra each month", run: askExtra)])
            }
        } else if data.loan.accountId != nil, let day = data.nextDay {
            BottomActions(actions: [.init(title: "Record \(day) payment", run: askPayment)])
        }
    }

    private func summaryCard(_ data: LoanData, compact: Bool) -> some View {
        let loan = data.loan
        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Left to pay").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                if width == .compact {
                    HStack(alignment: .firstTextBaseline) {
                        Text(WealthModel.remaining(loan).wholeMoney(loan.currency)).font(.system(size: 36, weight: .bold)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Spacer()
                        Text("of \(loan.principal.wholeMoney(loan.currency))").font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                } else {
                    HeadlineMoney(amount: WealthModel.remaining(loan), currency: loan.currency, size: 36)
                    Text("of \(loan.principal.wholeMoney(loan.currency)) borrowed").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                ProgressLine(value: WealthModel.percentPaid(loan), color: Theme.spendBar, height: 8)
                HStack(alignment: .top) {
                    Text(compact ? "\(data.rateText) \u{00B7} \(data.paymentText)" : data.paidText)
                    Spacer()
                    if width != .compact && data.facts.payoff != nil { Text("Payoff ") + data.payoffLine } else { data.payoffLine }
                }
                .font(.subheadline).foregroundStyle(Theme.secondary)
                if !compact {
                    Divider().padding(.vertical, 4)
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Figure(label: "Rate", value: data.rateText)
                            Figure(label: "Payment", value: data.paymentText)
                        }
                        GridRow {
                            Figure(label: "Interest paid", value: (loan.interestPaid ?? 0).wholeMoney(loan.currency))
                            Figure(label: "Interest left", value: data.interestLeftText)
                        }
                    }
                }
            }
        }
    }

    private func eachPaymentCard(_ data: LoanData) -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Each payment").font(.headline)
                    Spacer()
                    LegendItem(color: Theme.accent, name: "Principal")
                    LegendItem(color: Theme.spendBar, name: "Interest")
                }
                .font(.subheadline)
                if let schedule = data.schedule {
                    yearBars(schedule.schedule, today: data.today, currency: data.currency)
                } else if data.scheduleFailed {
                    InlineError(message: "Couldn't load the schedule", retry: reload)
                }
            }
        }
    }

    private func payoff(_ data: LoanData) -> some View {
        VStack(spacing: 12) {
            eachPaymentCard(data)
            let next = Array(data.facts.upcoming.prefix(3))
            if !next.isEmpty {
                Card(padding: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Next payments").font(.headline)
                        ForEach(Array(next.enumerated()), id: \.offset) { index, row in
                            if index > 0 { Divider() }
                            nextRow(row, currency: data.currency)
                        }
                    }
                }
            }
        }
    }

    private func nextRow(_ row: Amortization.Row, currency: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(APIDate.parse(row.date)?.monthDay ?? row.date).font(.body.weight(.semibold))
                Text("\(row.principal.wholeMoney(currency)) principal \u{00B7} \(row.interest.wholeMoney(currency)) interest")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text(row.payment.wholeMoney(currency)).font(.body.weight(.semibold)).monospacedDigit()
        }
    }

    /// Average principal and interest per payment for each year. Past years are faded.
    private func yearBars(_ rows: [Amortization.Row], today: Date, currency: String) -> some View {
        let thisYear = Calendar(identifier: .gregorian).component(.year, from: today)
        let bars = WealthModel.yearBars(rows)
        return Chart {
            ForEach(bars) { bar in
                let past = bar.year < thisYear
                BarMark(x: .value("Year", String(bar.year)), y: .value("Interest", bar.interest))
                    .foregroundStyle(Theme.spendBar.opacity(past ? 0.4 : 1)).cornerRadius(4)
                BarMark(x: .value("Year", String(bar.year)), y: .value("Principal", bar.principal))
                    .foregroundStyle(Theme.accent.opacity(past ? 0.45 : 1)).cornerRadius(4)
            }
            if bars.contains(where: { $0.year == thisYear }) {
                RuleMark(x: .value("Year", String(thisYear)))
                    .foregroundStyle(Theme.text.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 2) {
                        Text("Now").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                    }
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.subheadline).foregroundStyle(Theme.secondary) } }
        .barSelection(labels: bars.map { String($0.year) }, tops: bars.map { $0.interest + $0.principal }) { index in
            let bar = bars[index]
            return ["\(String(bar.year)), each payment", "Principal \(bar.principal.wholeMoney(currency))",
                    "Interest \(bar.interest.wholeMoney(currency))"]
        }
        .padding(.top, 10)
        .frame(height: 150)
        .accessibilityLabel("Each payment shifts from interest toward principal")
    }

    // MARK: Loading and saving

    private func load() async {
        let api = session.api
        do {
            async let loans = api.loans()
            async let dashboard = try? api.dashboard()
            guard let loan = try await loans.first(where: { $0.id == id }) else {
                error = "This loan no longer exists."
                return
            }
            let payers = await dashboard.map(\.balances).map(WealthModel.cash) ?? []
            data = LoanData(loan: loan, payers: payers, today: Fixtures.today)
            error = nil
            do {
                data?.schedule = try await api.loanAmortization(id: id)
            } catch is CancellationError {
            } catch {
                WealthView.log.error("amortization failed for \(id): \(String(describing: error), privacy: .public)")
                data?.scheduleFailed = true
            }
        } catch is CancellationError {
        } catch {
            WealthView.log.error("loan failed: \(String(describing: error), privacy: .public)")
            self.error = error.localizedDescription
        }
    }

    private func recordPayment(from accountId: Int) async {
        guard let data, let loanAccount = data.loan.accountId, let next = data.facts.next else { return }
        do {
            try await session.api.createTransfer(TransferInput(
                fromAccountId: accountId, toAccountId: loanAccount, enteredAmount: next.payment, date: next.date,
                note: "\(data.loan.displayName) payment"
            ))
            await session.didSave()
        } catch {
            WealthView.log.error("loan payment failed: \(String(describing: error), privacy: .public)")
            notice = "Couldn't record the payment: \(error.localizedDescription)"
        }
    }

    private func applyExtra() async {
        guard let loan = data?.loan else { return }
        do {
            try await session.api.updateLoan(LoanUpdate(id: loan.id, extraPayment: (loan.extraPayment ?? 0) + extra))
            await session.didSave()
            extra = 0
        } catch {
            WealthView.log.error("loan update failed: \(String(describing: error), privacy: .public)")
            notice = "Couldn't save the extra payment: \(error.localizedDescription)"
        }
    }
}

extension LoanView {
    /// iPadPLoan.dc.html: the summary, What if, the schedule and each payment's split on one page.
    private func page(_ data: LoanData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Beside the Debts list the bar says "Debts", so the loan's name heads the pane.
                VStack(alignment: .leading, spacing: 2) {
                    if embedded { Text(data.loan.displayName).font(.title2.weight(.bold)).foregroundStyle(Theme.text) }
                    Text(data.subtitle).font(.subheadline).foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 4)
                summaryCard(data, compact: false)
                LoanWhatIf(data: data, extra: $extra, apply: askExtra)
                LoanScheduleCard(data: data, retry: reload)
                eachPaymentCard(data)
            }
            .padding(.horizontal, 20).padding(.top, embedded ? 8 : 0).padding(.bottom, 8)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if data.loan.accountId != nil, let day = data.nextDay {
                BottomActions(actions: [.init(title: "Record \(day) payment", run: askPayment)])
            }
        }
    }
}
