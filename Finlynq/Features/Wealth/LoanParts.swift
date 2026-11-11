import SwiftUI

/// $100 $200 $500 $1,000 capsules for the What-if extra payment; the selected one is filled black.
struct ExtraChips: View {
    @Binding var extra: Double
    let currency: String

    var body: some View {
        // Two rows of two when one row doesn't fit, as at accessibility text sizes.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { ForEach(Self.amounts, id: \.self, content: chip) }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow { chip(100); chip(200) }
                GridRow { chip(500); chip(1000) }
            }
        }
    }

    private static let amounts: [Double] = [100, 200, 500, 1000]

    private func chip(_ amount: Double) -> some View {
        let selected = extra == amount
        return Button { extra = amount } label: {
            // An amount never wraps ("US$1,00 / 0").
            Text(amount.wholeMoney(currency)).font(.subheadline.weight(.semibold)).fixedSize()
                .foregroundStyle(selected ? Theme.page : Theme.text)
                .frame(maxWidth: .infinity, minHeight: 32)
                .padding(.horizontal, 6)
                .background(selected ? Theme.text : Theme.card, in: Capsule())
                .overlay { if !selected { Capsule().strokeBorder(Theme.hairline) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The Schedule tab: the server's rows with paid ones collapsed, the next one marked.
struct LoanScheduleList: View {
    let data: LoanView.LoanData
    let retry: () -> Void
    @State private var showEarlier = false

    var body: some View {
        if let schedule = data.schedule {
            let split = WealthModel.split(schedule.schedule, today: data.today)
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    if !split.paid.isEmpty && !showEarlier {
                        Button("\(split.paid.count) earlier payments \u{00B7} Show") { showEarlier = true }
                            .font(.subheadline).foregroundStyle(Theme.accent).padding(.bottom, 8)
                    }
                    ForEach((showEarlier ? split.paid : []) + [split.next].compactMap { $0 } + split.rest) { row in
                        self.row(row, paid: split.paid.contains(row), next: row == split.next)
                        Divider()
                    }
                    if let note = data.payoffNote {
                        Text(note).font(.footnote).foregroundStyle(Theme.secondary).padding(.top, 10)
                    }
                }
            }
        } else if data.scheduleFailed {
            InlineError(message: "Couldn't load the schedule", retry: retry)
        } else {
            ProgressView()
        }
    }

    private func row(_ row: Amortization.Row, paid: Bool, next: Bool) -> some View {
        let currency = data.currency
        return HStack {
            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(paid ? Theme.positive : .clear).frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(APIDate.parse(row.date)?.formatted(date: .abbreviated, time: .omitted) ?? row.date)
                        .fontWeight(next ? .bold : .semibold)
                    if next { Chip(text: "Next", tint: .white, background: Theme.accent) }
                }
                Text("\(row.principal.money(currency)) principal \u{00B7} \(row.interest.money(currency)) interest")
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.payment.money(currency)).fontWeight(.semibold)
                Text(row.balance.money(currency)).font(.footnote).foregroundStyle(Theme.secondary)
            }
            .monospacedDigit()
        }
        .font(.subheadline)
        .padding(.vertical, 8)
        .background(next ? Theme.accentTint.opacity(0.6) : .clear)
    }
}

/// The What-if tab (LoanPlan.dc.html): a slider and presets for an extra monthly payment, the new payoff date and
/// interest saved, and the balance with and without the extra. With `apply` it is one card that ends in the button
/// that saves the extra payment (iPadPLoan.dc.html); without it, three cards over the page's bottom button.
struct LoanWhatIf: View {
    let data: LoanView.LoanData
    @Binding var extra: Double
    var apply: (() -> Void)?

    var body: some View {
        if !data.supportsWhatIf {
            Card(padding: 16) {
                Text("What if works for monthly loans with a yearly rate and a calculated schedule. Use the Finlynq website for this loan.")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
            }
        } else if let apply {
            Card(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("What if").font(.headline)
                    controls
                    Divider()
                    if let result = WealthModel.whatIf(data.loan, extra: extra, today: data.today) {
                        outcome(result, payoff: data.facts.payoff)
                        balanceComparison
                        Button(action: apply) {
                            Text("Pay \(extra.wholeMoney(data.currency)) extra each month").font(.headline).foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(extra <= 0)
                    } else {
                        neverPaysOff
                    }
                }
            }
        } else {
            Card(padding: 16) { controls }
            if let result = WealthModel.whatIf(data.loan, extra: extra, today: data.today) {
                Card(padding: 16) { outcome(result, payoff: data.facts.payoff) }
                Card(padding: 16) { balanceComparison }
            } else {
                Card(padding: 16) { neverPaysOff }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Extra each month").font(.headline)
                Spacer()
                Text(extra.wholeMoney(data.loan.currency)).font(.system(size: 30, weight: .bold)).monospacedDigit()
                Text("/ month").font(.subheadline).foregroundStyle(Theme.secondary)
            }
            Slider(value: $extra, in: 0...1000, step: 50).tint(Theme.accent).accessibilityLabel("Extra each month")
            ExtraChips(extra: $extra, currency: data.loan.currency)
        }
    }

    private var neverPaysOff: some View {
        Text("At this payment the loan never pays off: each payment only covers the interest.")
            .font(.subheadline).foregroundStyle(Theme.negative)
    }

    /// Without a server payoff date the dates read "No payoff date"; months sooner and interest saved still show.
    private func outcome(_ result: WealthModel.WhatIf, payoff: Date?) -> some View {
        let months = "\(result.monthsSooner) \(result.monthsSooner == 1 ? "month" : "months") sooner"
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Figure(label: "New payoff", value: payoff.map { result.payoff(from: $0).monthYear } ?? "No payoff date",
                       color: Theme.accent, size: 26)
                Figure(label: "Without extra", value: payoff?.monthYear ?? "No payoff date", color: Theme.secondary, size: 26)
            }
            HStack(spacing: 8) {
                Chip(text: "\(result.interestSaved.wholeMoney(data.currency)) less interest", tint: Theme.positive,
                    background: Theme.positiveTint)
                Chip(text: months, tint: Theme.positive, background: Theme.positiveTint)
                if apply != nil, let left = WealthModel.paymentsLeft(data.facts.paymentsLeft, with: result) {
                    Chip(text: "\(left) \(left == 1 ? "payment" : "payments") left", tint: Theme.secondary, background: Theme.fill)
                }
            }
        }
    }

    private var balanceComparison: some View {
        let base = WealthModel.plan(data.loan, today: data.today)
        let faster = WealthModel.plan(data.loan, today: data.today, extra: extra)
        let currency = data.currency
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Balance").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                HStack(spacing: 6) { Capsule().fill(Theme.accent)
                    .frame(width: 16, height: 3); Text("With \(extra.wholeMoney(currency))") }
                HStack(spacing: 6) { Text("- - -").font(.caption2.weight(.bold)); Text("Now") }
            }
            .font(.subheadline).foregroundStyle(Theme.secondary)
            TimeSeriesChart(
                points: faster.map { ValuePoint(day: $0.date, value: $0.balance) }, height: 130, xAxis: .nowAndYears,
                currency: currency, fillOpacity: 0.08, fromZero: true, dashed: base.map { ValuePoint(day: $0.date, value: $0.balance) },
                resting: .none
            )
            .accessibilityLabel("Balance with and without the extra payment")
            if apply == nil {
                Text("\(faster.count) payments, each with \(extra.wholeMoney(currency)) extra").font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
        }
    }
}

/// The schedule as a card on one page (iPadPLoan.dc.html): the last paid row, the next one and three after it,
/// then "See all", which lists every payment, and Export CSV.
struct LoanScheduleCard: View {
    let data: LoanView.LoanData
    let retry: () -> Void
    @State private var showAll = false

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Schedule").font(.headline)
                    Spacer()
                    Text("Calculated at \(data.rateText)").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                .padding(.bottom, 8)
                if let schedule = data.schedule {
                    let rows = schedule.schedule
                    let split = WealthModel.split(rows, today: data.today)
                    let shown = showAll ? rows : WealthModel.scheduleWindow(split)
                    let paid = Set(split.paid.map(\.period))
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(shown) { row in
                            Divider()
                            self.row(row, paid: paid.contains(row.period), next: row == split.next)
                        }
                    }
                    if let note = data.payoffNote {
                        Text(note).font(.footnote).foregroundStyle(Theme.secondary).padding(.top, 10)
                    }
                    HStack(spacing: 10) {
                        if !showAll && shown.count < rows.count {
                            Button("See all \(rows.count) payments") { withAnimation { showAll = true } }
                                .buttonStyle(.bordered)
                        }
                        Spacer()
                        ShareLink(item: CSVExport(name: "\(data.loan.displayName) schedule.csv", text: WealthModel.scheduleCSV(rows)),
                                  preview: SharePreview("\(data.loan.displayName) schedule.csv")) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 12)
                } else if data.scheduleFailed {
                    InlineError(message: "Couldn't load the schedule", retry: retry)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func row(_ row: Amortization.Row, paid: Bool, next: Bool) -> some View {
        let currency = data.currency
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(APIDate.parse(row.date)?.formatted(date: .abbreviated, time: .omitted) ?? row.date).font(.body.weight(.semibold))
                    if next { Chip(text: "Next", tint: .white, background: Theme.accent) }
                    if paid { Chip(text: "\u{2713} Paid", tint: Theme.positive, background: Theme.positiveTint) }
                }
                Text("#\(row.period) \u{00B7} \(row.principal.money(currency)) principal \u{00B7} \(row.interest.money(currency)) interest")
                    .font(.footnote).foregroundStyle(Theme.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.payment.money(currency)).font(.body.weight(.semibold))
                Text("\(row.balance.money(currency)) left").font(.footnote).foregroundStyle(Theme.secondary)
            }
            .monospacedDigit().fixedSize()
        }
        .padding(.vertical, 10)
        .background(next ? Theme.accentTint.opacity(0.6) : .clear)
    }
}

#if os(macOS)
/// The Mac loan detail (MacLoan.dc.html): title row with Edit and Record payment, the summary, the What-if strip
/// and the full schedule table with Export CSV.
struct LoanMacDetail: View {
    let data: LoanView.LoanData
    @Binding var extra: Double
    let edit: () -> Void
    let record: () -> Void
    let apply: () -> Void
    let retry: () -> Void
    @State private var showEarlier = false
    @State private var export: CSVFile?

    var body: some View {
        let loan = data.loan
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loan.displayName).font(.title2.weight(.bold))
                        Text(subtitle).font(.body).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button(action: edit) { MacPopupLabel(text: "Edit", symbol: "pencil") }.buttonStyle(.plain)
                    if loan.accountId != nil, let day = data.nextDay {
                        Button(action: record) {
                            Text("Record \(day) payment").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 12).frame(height: 28)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                summary
                if data.supportsWhatIf { whatIf }
                schedule
            }
            .padding(24)
        }
        .fileExporter(isPresented: Binding(get: { export != nil }, set: { if !$0 { export = nil } }), document: export,
                      contentType: .commaSeparatedText, defaultFilename: "\(loan.displayName) schedule.csv") { _ in export = nil }
    }

    private var subtitle: String {
        let kind = data.loan.type == "lease" ? "Lease" : data.loan.type == "mortgage" ? "Mortgage" : "Amortizing loan"
        return [kind, data.nextDay.map { "Next payment \($0)" }].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    private var summary: some View {
        let loan = data.loan
        return Card(padding: 20) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Left to pay").font(.body).foregroundStyle(Theme.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(WealthModel.remaining(loan).wholeMoney(loan.currency)).font(.system(size: 30, weight: .bold)).monospacedDigit()
                        Text("of \(loan.principal.wholeMoney(loan.currency))").foregroundStyle(Theme.secondary)
                    }
                    ProgressLine(value: WealthModel.percentPaid(loan), color: Theme.accent, height: 8)
                    HStack {
                        Text(data.paidText)
                        Spacer()
                        Text("Payoff ") + data.payoffLine
                    }
                    .foregroundStyle(Theme.secondary)
                }
                .frame(width: 320)
                Divider()
                Figure(label: "Rate", value: data.rateText, size: 15)
                Figure(label: "Payment", value: data.paymentText, size: 15)
                Figure(label: "Interest paid", value: (loan.interestPaid ?? 0).wholeMoney(loan.currency), size: 15)
                Figure(label: "Interest left", value: data.interestLeftText, size: 15)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityLabel("Summary")
    }

    private var whatIf: some View {
        let currency = data.currency
        let result = WealthModel.whatIf(data.loan, extra: extra, today: data.today)
        let payoff = data.facts.payoff
        return HStack(spacing: 12) {
            Text("What if").fontWeight(.semibold).foregroundStyle(Theme.accent)
            Text("Extra a month").foregroundStyle(Theme.secondary)
            ExtraChips(extra: $extra, currency: currency).fixedSize()
            Spacer(minLength: 8)
            if let result {
                let saves = Text("saves \(result.interestSaved.wholeMoney(currency)) interest").foregroundStyle(Theme.positive)
                let pays = Text(payoff.map { "Pays off \(result.payoff(from: $0).monthYear)" } ?? "No payoff date").fontWeight(.semibold)
                Text("\(pays) \u{00B7} \(result.monthsSooner) months sooner \u{00B7} \(saves)")
                    .multilineTextAlignment(.trailing)
            }
            Button("Apply", action: apply).disabled(extra <= 0 || result == nil)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What if")
    }

    private static let widths: [CGFloat?] = [70, nil, 120, 120, 110, 140]

    private var schedule: some View {
        let split = WealthModel.split(data.schedule?.schedule ?? [], today: data.today)
        let shownPaid = showEarlier ? split.paid : Array(split.paid.suffix(4))
        let hidden = split.paid.count - shownPaid.count
        return Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Amortization schedule").font(.title3.weight(.bold))
                    Text("Calculated at \(data.rateText)").foregroundStyle(Theme.secondary)
                    Spacer()
                    Button { export = CSVFile(text: WealthModel.scheduleCSV(data.schedule?.schedule ?? [])) } label: {
                        MacPopupLabel(text: "Export CSV", symbol: "square.and.arrow.down")
                    }
                    .buttonStyle(.plain)
                    .disabled(data.schedule == nil)
                }
                .padding(20)
                if data.scheduleFailed { InlineError(message: "Couldn't load the schedule", retry: retry).padding(.horizontal, 20) }
                if let note = data.payoffNote {
                    Text(note).foregroundStyle(Theme.secondary).padding(.horizontal, 20).padding(.bottom, 10)
                }
                header
                Divider()
                if hidden > 0, let first = split.paid.first, let last = split.paid.dropLast(shownPaid.count).last {
                    HStack(spacing: 8) {
                        Text("\(hidden) earlier payments, \(monthYear(first.date)) to \(monthYear(last.date))")
                            .foregroundStyle(Theme.secondary)
                        Button("Show") { showEarlier = true }.buttonStyle(.plain).foregroundStyle(Theme.accent).fontWeight(.semibold)
                    }
                    .padding(.horizontal, 20).frame(height: 31, alignment: .leading)
                    Divider()
                }
                ForEach(shownPaid + [split.next].compactMap { $0 } + split.rest) { row in
                    self.row(row, paid: split.paid.contains(row), next: row == split.next)
                    Divider()
                }
            }
            .padding(.bottom, 8)
        }
        .accessibilityLabel("Amortization schedule")
    }

    private var header: some View {
        HStack(spacing: 0) {
            ForEach(Array(["#", "Date", "Payment", "Principal", "Interest", "Balance"].enumerated()), id: \.offset) { index, title in
                Text(title).frame(width: Self.widths[index], alignment: index < 2 ? .leading : .trailing)
                    .frame(maxWidth: Self.widths[index] == nil ? .infinity : nil, alignment: .leading)
            }
        }
        .foregroundStyle(Theme.secondary).padding(.horizontal, 20).padding(.bottom, 8)
    }

    private func row(_ row: Amortization.Row, paid: Bool, next: Bool) -> some View {
        let currency = data.currency
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                if paid { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Theme.positive) }
                Text(String(row.period))
            }
            .frame(width: 70, alignment: .leading)
            HStack(spacing: 6) {
                Text(APIDate.parse(row.date)?.formatted(date: .abbreviated, time: .omitted) ?? row.date)
                if next { Chip(text: "Next", tint: .white, background: Theme.accent).font(.caption2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.payment.money(currency)).frame(width: 120, alignment: .trailing)
            Text(row.principal.money(currency)).frame(width: 120, alignment: .trailing)
            Text(row.interest.money(currency)).frame(width: 110, alignment: .trailing)
            Text(row.balance.money(currency)).frame(width: 140, alignment: .trailing)
        }
        .fontWeight(next ? .semibold : .regular)
        .foregroundStyle(paid ? Theme.secondary : Theme.text)
        .monospacedDigit()
        .padding(.horizontal, 20).frame(height: 31)
        .background(next ? Theme.accentTint : .clear)
    }

    private func monthYear(_ date: String) -> String { APIDate.parse(date)?.monthYear ?? date }
}
#endif
