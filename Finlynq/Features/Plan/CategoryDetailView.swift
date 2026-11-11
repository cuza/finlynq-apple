import Charts
import SwiftUI

/// One category's month (Category.dc.html, the right side of iPadPlan.dc.html, the inspector in MacPlan.dc.html):
/// what is left, the budget with an edit, a year of monthly spending, how this month compares, top payees and recent
/// transactions.
struct CategoryDetailView: View {
    enum Style { case page, pane, inspector }

    let categoryId: Int
    var month: Date = Calendar(identifier: .gregorian).dateInterval(of: .month, for: Fixtures.today)?.start ?? Fixtures.today
    var style = Style.page
    @Environment(\.layoutWidth) private var width
    @Environment(Session.self) private var session
    @State private var editing = false
    @State private var draft = ""
    /// This month's budget as last loaded, so the "…" menu's editor starts from it.
    @State private var budgeted: Double = 0
    @State private var saveError: String?
    /// Bumped by an inline Retry to load again.
    @State private var attempt = 0

    struct Data {
        let budget: BudgetMonth
        let trends: Trends
        /// The last 12 months of this category's transactions; nil when that request failed.
        let transactions: [Transaction]?
    }

    private static let calendar = Calendar(identifier: .gregorian)
    private var monthKey: String { BudgetModel.monthKey(month) }
    private var months: [String] {
        StatementModel.months(from: Self.calendar.date(byAdding: .month, value: -11, to: month) ?? month, to: month)
    }
    private var category: Category? { session.categories.first { $0.id == categoryId } }
    private var currency: String { session.currency }

    var body: some View {
        Reloader(id: "\(categoryId)|\(monthKey)|\(session.revision)|\(attempt)", source: "category") { try await load() } content: { data in
            content(data).onChange(of: figures(data).budgeted, initial: true) { budgeted = figures(data).budgeted }
        }
        #if os(macOS)
        .background(style == .inspector ? Theme.toolbar : Theme.page)
        #else
        .background(Theme.page)
        #endif
        .modifier(PushedPageBar(enabled: style == .page, title: category?.displayName ?? "Category") { menu })
        .alert("Monthly budget", isPresented: $editing) {
            TextField("Amount", text: $draft)
            #if os(iOS)
                .keyboardType(.decimalPad)
            #endif
            // Text that isn't a number is ignored; "Clear budget" in the menu is the way to remove one.
            Button("Save") { if let amount = BudgetModel.amount(draft) { Task { await save(amount) } } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(category?.displayName ?? "This category") in \(month.formatted(.dateTime.month(.wide).year()))")
        }
        .alert("Couldn't save the budget", isPresented: Binding { saveError != nil } set: { if !$0 { saveError = nil } }) {
            Button("OK") {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private func load() async throws -> Data {
        let api = session.api
        let first = months.first.map { $0 + "-01" } ?? APIDate.string(month)
        let end = Self.calendar.dateInterval(of: .month, for: month).map { APIDate.string($0.end.addingTimeInterval(-1)) } ?? first
        async let budget = api.budgetMonth(monthKey)
        async let trends = api.trends(from: first, to: end)
        async let transactions = optionalLoad("category transactions") {
            try await api.transactions(TransactionQuery(categoryId: categoryId, startDate: first, endDate: end, limit: 500)).data
        }
        return try await Data(budget: budget, trends: trends, transactions: transactions)
    }

    private func save(_ amount: Double?) async {
        do {
            try await session.api.setBudget(categoryId: categoryId, month: monthKey, amount: amount)
            await session.didSave()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private var menu: some View {
        Menu {
            Button("Edit budget", systemImage: "pencil") { draftAndEdit(budgeted: budgeted) }
            Button("Clear budget", systemImage: "xmark.circle", role: .destructive) { Task { await save(nil) } }
        } label: {
            Label("Budget", systemImage: "slider.horizontal.3")
        }
        .labelStyle(.iconOnly)
    }

    // MARK: Figures
    private struct Figures {
        let line: BudgetMonth.Line?
        let group: String
        let spent: Double
        let budgeted: Double
        /// Spending per month key, months without spending left out.
        let byMonth: [String: Double]
        let average: Double?
        let averageMonths: Int
        let lastYear: Double?
    }

    private func figures(_ data: Data) -> Figures {
        let pair = data.budget.spending.flatMap { group in group.lines.map { (group, $0) } }
            .first { $0.1.categoryId == categoryId || $0.1.key == "c:\(categoryId)" }
        let trend = data.trends.expenses.first { $0.categoryId == categoryId }
        let byMonth = (trend?.periods ?? [:]).filter { months.contains($0.key) && $0.value != 0 }
        let previous = months.dropLast().compactMap { byMonth[$0] }
        let lastYearKey = Self.calendar.date(byAdding: .year, value: -1, to: month).map(BudgetModel.monthKey)
        return Figures(
            line: pair?.1, group: category?.group ?? pair?.0.name ?? "",
            spent: pair?.1.actual ?? byMonth[monthKey] ?? 0, budgeted: pair?.1.budgeted ?? 0,
            byMonth: byMonth,
            average: previous.isEmpty ? nil : previous.reduce(0, +) / Double(previous.count), averageMonths: previous.count,
            lastYear: lastYearKey.flatMap { trend?.periods[$0] }
        )
    }

    // MARK: Layout
    @ViewBuilder
    private func content(_ data: Data) -> some View {
        let figures = figures(data)
        switch style {
        case .page:
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    subtitle
                    leftCard(figures)
                    // iPadPCategory keeps the three figures inside the spending card.
                    spendingCard(figures, stats: width != .compact)
                    if width == .compact { statsCard(figures) }
                    payeesCard(data)
                    recentCard(data)
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        case .pane:
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) { header(size: 30); Spacer(); menu }
                    leftCard(figures)
                    spendingCard(figures, stats: true)
                    HStack(alignment: .top, spacing: 14) { payeesCard(data); recentCard(data) }
                }
                .padding(.leading, 24).padding(.trailing, 28).padding(.vertical, 12)
            }
        case .inspector:
            inspector(data, figures)
        }
    }

    private func header(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(category?.displayName ?? "Category").font(.system(size: size, weight: .bold)).foregroundStyle(Theme.text)
            subtitle
        }
    }

    /// "Food · November 2026", under the title.
    private var subtitle: some View {
        Text([category?.group, month.formatted(.dateTime.month(.wide).year())].compactMap { $0 }.joined(separator: " \u{00B7} "))
            .font(.subheadline).foregroundStyle(Theme.secondary)
    }

    private func status(_ figures: Figures) -> BudgetModel.LineStatus {
        BudgetModel.lineStatus(spent: figures.spent, budget: figures.budgeted)
    }

    private func statusColor(_ figures: Figures) -> Color {
        switch status(figures) {
        case .over: Theme.overBar
        case .warn: Theme.spendBar
        case .ok: Theme.accent
        }
    }

    private func usedLine(_ figures: Figures, font: Font) -> some View {
        let left = figures.budgeted - figures.spent
        let days = BudgetModel.daysRemaining(today: Fixtures.today, month: month)
        let perDay = BudgetModel.leftPerDay(left: left, today: Fixtures.today, month: month)
        let state = status(figures)
        return HStack {
            Text("\((figures.spent / figures.budgeted).formatted(.percent.precision(.fractionLength(0)))) used")
                .fontWeight(state == .ok ? .regular : .semibold)
                .foregroundStyle(state == .over ? Theme.negative : state == .warn ? Theme.warning : Theme.secondary)
            Spacer()
            if days > 0 {
                Text("\(days) \(days == 1 ? "day" : "days") left \u{00B7} \(perDay.money(currency))/day").foregroundStyle(Theme.secondary)
            }
        }
        .font(font).monospacedDigit()
    }

    private func leftCard(_ figures: Figures) -> some View {
        let left = figures.budgeted - figures.spent
        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                if figures.budgeted > 0 {
                    Text(left >= 0 ? "Left this month" : "Over this month").font(.footnote.weight(.medium)).foregroundStyle(Theme.secondary)
                    let hero = Text(abs(left).wholeMoney(currency)).font(.system(size: 36, weight: .bold)).monospacedDigit()
                        .foregroundStyle(left >= 0 ? Theme.text : Theme.negative)
                    let spent = Text("\(figures.spent.wholeMoney(currency)) of \(figures.budgeted.wholeMoney(currency)) spent")
                        .font(.subheadline).foregroundStyle(Theme.secondary).monospacedDigit()
                    // iPadPCategory puts the spent figure under the hero.
                    if width != .compact && style == .page { hero; spent } else {
                        HStack(alignment: .firstTextBaseline) { hero; Spacer(); spent }
                    }
                    ProgressLine(value: figures.spent / figures.budgeted, color: statusColor(figures), height: 8)
                    usedLine(figures, font: .subheadline)
                } else {
                    Text("Spent this month").font(.footnote.weight(.medium)).foregroundStyle(Theme.secondary)
                    Text(figures.spent.wholeMoney(currency)).font(.system(size: 36, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Theme.text)
                }
                Divider().padding(.vertical, 4)
                HStack {
                    Text("Budget").foregroundStyle(Theme.text)
                    Spacer()
                    Text(figures.budgeted > 0 ? "\(figures.budgeted.wholeMoney(currency)) / month" : "Not budgeted")
                        .fontWeight(figures.budgeted > 0 ? .semibold : .regular)
                        .foregroundStyle(figures.budgeted > 0 ? Theme.text : Theme.secondary)
                    Button(figures.budgeted > 0 ? "Edit" : "Set") { draftAndEdit(budgeted: figures.budgeted) }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent).padding(.leading, 14)
                }
                .font(.body).monospacedDigit()
                averageButton(figures)
            }
        }
    }

    func draftAndEdit(budgeted: Double) {
        draft = budgeted > 0 ? BudgetModel.draft(budgeted) : ""
        editing = true
    }

    /// "Use 3-month average": sets the budget to the server's average of the three months before this one.
    @ViewBuilder
    private func averageButton(_ figures: Figures) -> some View {
        if let average = figures.line?.average3, average > 0, average.rounded() != figures.budgeted.rounded() {
            Button { Task { await save(average.rounded()) } } label: {
                HStack {
                    Text("Use 3-month average")
                    Spacer()
                    Text(average.wholeMoney(currency)).monospacedDigit()
                }
                .font(style == .inspector ? .body.weight(.medium) : .body.weight(.semibold)).foregroundStyle(Theme.accent)
                .padding(.horizontal, style == .inspector ? 12 : 16)
                .frame(height: style == .inspector ? 30 : 44)
                .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: style == .inspector ? 8 : 14, style: .continuous))
                .overlay {
                    if style == .inspector { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

}

extension CategoryDetailView {
    // MARK: Monthly spending

    private func spendingCard(_ figures: Figures, stats: Bool) -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HomeCardHeader(title: "Monthly spending", detail: "12 months", layout: .phone)
                chart(figures, height: style == .inspector ? 100 : 170, wideLabels: style == .pane)
                legend(figures)
                if stats {
                    Divider()
                    statsRow(figures)
                }
            }
        }
    }

    private func chart(_ figures: Figures, height: CGFloat, wideLabels: Bool) -> some View {
        Chart {
            ForEach(months, id: \.self) { key in
                BarMark(x: .value("Month", key), y: .value("Spent", figures.byMonth[key] ?? 0), width: .ratio(0.7))
                    .foregroundStyle(key == monthKey ? Theme.spendBar : Theme.spendBar.opacity(0.42))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            if figures.budgeted > 0 {
                RuleMark(y: .value("Budget", figures.budgeted)).foregroundStyle(Theme.warning).lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            if let average = figures.average {
                RuleMark(y: .value("Average", average)).foregroundStyle(Theme.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: months) { value in
                AxisValueLabel {
                    let key = value.as(String.self) ?? ""
                    let date = StatementModel.date(ofMonth: key)
                    Text(wideLabels ? date.formatted(.dateTime.month(.abbreviated)) : String(date.formatted(.dateTime.month(.narrow))))
                        .font(.caption.weight(key == monthKey ? .bold : .regular))
                        .foregroundStyle(key == monthKey ? Theme.text : Theme.secondary)
                }
            }
        }
        .barSelection(labels: months, tops: months.map { figures.byMonth[$0] ?? 0 }) { index in
            [StatementModel.monthTitle(months[index]), "Spent \((figures.byMonth[months[index]] ?? 0).wholeMoney(currency))"]
        }
        .frame(height: height)
        .accessibilityLabel("Spending by month")
    }

    private func legend(_ figures: Figures) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(Theme.spendBar).frame(width: 9, height: 9); Text("Spent") }
            if figures.budgeted > 0 {
                HStack(spacing: 5) {
                    Capsule().fill(Theme.warning).frame(width: 14, height: 2)
                    Text("Budget \(figures.budgeted.wholeMoney(currency))")
                }
            }
            if let average = figures.average {
                HStack(spacing: 5) {
                    Text("- -").fontWeight(.bold)
                    Text("Average \(average.wholeMoney(currency))")
                }
            }
        }
        .font(style == .inspector ? .caption : .footnote).foregroundStyle(Theme.secondary).monospacedDigit().lineLimit(1)
    }

    // MARK: Stats

    private struct Stat {
        let label: String
        let value: String
        let detail: String?
        let color: Color
    }

    private func statItems(_ figures: Figures) -> [Stat] {
        var items: [Stat] = []
        let change = figures.average.flatMap { StatementModel.versusUsual(current: figures.spent, previous: [$0]) }
        let changeColor = (change ?? 0) > 0.05 ? Theme.warning : (change ?? 0) < -0.05 ? Theme.positive : Theme.secondary
        items.append(Stat(label: "This month", value: figures.spent.wholeMoney(currency), detail: change.map(StatementModel.usualLabel),
                          color: changeColor))
        if let average = figures.average {
            let span = "last \(figures.averageMonths) \(figures.averageMonths == 1 ? "month" : "months")"
            items.append(Stat(label: "Monthly average", value: average.wholeMoney(currency), detail: span, color: Theme.secondary))
        }
        if let lastYear = figures.lastYear, let date = Self.calendar.date(byAdding: .year, value: -1, to: month) {
            items.append(Stat(
                label: date.formatted(.dateTime.month(.abbreviated).year()), value: lastYear.wholeMoney(currency),
                detail: "same month", color: Theme.secondary
            ))
        }
        return items
    }

    private func statsRow(_ figures: Figures) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(statItems(figures), id: \.label) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label).font(.footnote).foregroundStyle(Theme.secondary)
                    Text(item.value).font(.title3.weight(.bold)).foregroundStyle(Theme.text).monospacedDigit()
                    if let detail = item.detail {
                        Text(detail).font(.footnote.weight(item.color == Theme.secondary ? .regular : .semibold))
                            .foregroundStyle(item.color)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func statsCard(_ figures: Figures) -> some View {
        Card(padding: 16) { statsRow(figures) }
    }

}

extension CategoryDetailView {
    // MARK: Payees and recent

    @ViewBuilder
    private func payeesCard(_ data: Data) -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HomeCardHeader(title: "Top payees", detail: "12 months", layout: .phone).padding(.bottom, 4)
                if let transactions = data.transactions {
                    let list = BudgetModel.topPayees(transactions)
                    if list.isEmpty {
                        Text("No payments in the last 12 months.").font(.footnote).foregroundStyle(Theme.secondary)
                    } else {
                        DividedRows(items: list) { payee in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(payee.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                                    Text("\(payee.count) \(payee.count == 1 ? "transaction" : "transactions")")
                                        .font(.footnote).foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                Text(payee.total.wholeMoney(payee.currency)).font(.subheadline.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(Theme.text)
                            }
                            .padding(.vertical, style == .inspector ? 4 : 9)
                        }
                    }
                } else {
                    InlineError(message: "Couldn't load payees") { attempt += 1 }
                }
            }
        }
    }

    @ViewBuilder
    private func recentCard(_ data: Data) -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HomeCardHeader(title: "Recent", layout: .phone).padding(.bottom, 4)
                if let transactions = data.transactions {
                    let recent = transactions.sorted { $0.date > $1.date }.prefix(style == .pane ? 2 : 3).map { $0 }
                    if recent.isEmpty {
                        Text("No transactions yet.").font(.footnote).foregroundStyle(Theme.secondary)
                    } else {
                        DividedRows(items: recent) { transaction in
                            NavigationLink(value: AppRoute.transaction(transaction.id)) {
                                ActivityRow(transaction: transaction).padding(.vertical, 8).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    InlineError(message: "Couldn't load transactions") { attempt += 1 }
                }
            }
        }
    }

    // MARK: Mac inspector

    private func inspector(_ data: Data, _ figures: Figures) -> some View {
        let left = figures.budgeted - figures.spent
        return VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(category?.displayName ?? "Category").font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                        Text([category?.group, month.formatted(.dateTime.month(.wide).year())].compactMap { $0 }
                            .joined(separator: " \u{00B7} "))
                            .font(.callout).foregroundStyle(Theme.secondary)
                    }
                    if figures.budgeted > 0 {
                        HStack(alignment: .firstTextBaseline) {
                            Text(abs(left).wholeMoney(currency)).font(.system(size: 24, weight: .bold))
                                .foregroundStyle(left >= 0 ? Theme.text : Theme.negative)
                            Text(left >= 0 ? "left" : "over").foregroundStyle(Theme.secondary)
                            Spacer()
                            Text("\(figures.spent.wholeMoney(currency)) of \(figures.budgeted.wholeMoney(currency))")
                                .foregroundStyle(Theme.secondary)
                        }
                        .monospacedDigit()
                        ProgressLine(value: figures.spent / figures.budgeted, color: statusColor(figures), height: 6)
                        usedLine(figures, font: .callout)
                    }
                    Card(padding: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            HomeCardHeader(title: "Monthly spending", detail: "12 months", layout: .phone)
                            chart(figures, height: 100, wideLabels: false)
                            legend(figures)
                        }
                    }
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(statItems(figures), id: \.label) { item in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.label).font(.caption).foregroundStyle(Theme.secondary)
                                Text(item.value).font(.body.weight(.bold)).foregroundStyle(Theme.text).monospacedDigit()
                                if let detail = item.detail { Text(detail).font(.caption.weight(.medium)).foregroundStyle(item.color) }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline))
                        }
                    }
                    payeesCard(data)
                }
                .padding(18)
            }
            averageButton(figures).padding(.horizontal, 18).padding(.bottom, 18)
        }
    }
}
