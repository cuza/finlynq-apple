import SwiftUI

/// One spending line with its group, for lists.
struct BudgetRow: Identifiable {
    let group: BudgetMonth.Group
    let line: BudgetMonth.Line
    var id: String { line.key }
}

/// Budget (Plan, iPadPBudget, DuoInnerBudget, iPadPlan, MacPlan boards). iPhone and iPad portrait push a category;
/// iPad landscape shows it beside the list; a wide Mac window's table edits budgets in place, with the detail as an
/// inspector, and narrower Mac windows use the iPad and iPhone layouts.
struct BudgetView: View {
    /// Set on iPhone, where the page sits under Plan's segmented control.
    var segment: Binding<PlanSegment>?
    @Environment(Session.self) private var session
    @Environment(\.layoutWidth) private var width
    @Environment(\.layoutColumn) private var column
    @State private var month = Calendar(identifier: .gregorian).dateInterval(of: .month, for: Fixtures.today)?.start ?? Fixtures.today
    @State private var filter = BudgetModel.Filter.all
    @State private var selected: String?
    @State private var saveError: String?
    /// The server's preview of "Fill from average", shown for confirmation before it is applied.
    @State private var fillPreview: BudgetFillResult?
    @State private var filling = false

    private var monthKey: String { BudgetModel.monthKey(month) }

    var body: some View {
        Reloader(id: "\(monthKey)|\(session.revision)", source: "budget") {
            try await session.api.budgetMonth(monthKey)
        } content: { budget in
            content(budget)
        }
        .background(Theme.page)
        .navigationTitle(title)
        #if os(iOS)
        .toolbarTitleDisplayMode(.large)
        #endif
        .routeDestinations(segment == nil)
        .toolbar { toolbar }
        .alert("Couldn't save the budget", isPresented: Binding { saveError != nil } set: { if !$0 { saveError = nil } }) {
            Button("OK") {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private var title: String {
        #if os(macOS)
        "Budget"
        #else
        segment == nil ? "Budget" : "Plan"
        #endif
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        #if os(macOS)
        // MacPlan has the month in the toolbar; the iPad pages have it in the content.
        if macDesign { MonthStepperItems(month: $month, format: .dateTime.month(.wide).year()) }
        if width == .compact { MonthStepperItems(month: $month) }
        ToolbarItem(placement: .primaryAction) {
            Button("Fill from average", systemImage: "waveform.path.ecg") { Task { await previewFill() } }
                .macTitleAndIcon()
                .disabled(filling)
                .help("Set every budget to its 3-month average")
        }
        #else
        if width == .compact { MonthStepperItems(month: $month) }
        #endif
    }

    @ViewBuilder
    private func content(_ budget: BudgetMonth) -> some View {
        switch width {
        case .compact: phone(budget)
        case .medium: portrait(budget)
        #if os(macOS)
        // Below MacPlan's width the iPad portrait page, whose list pushes the category: the iPad landscape pane is
        // too narrow there for the category's amounts.
        case .wide: if macDesign { mac(budget) } else { portrait(budget) }
        #else
        case .wide: pad(budget)
        #endif
        }
    }

    /// MacPlan's table and inspector need about 880pt of table beside the 320pt inspector.
    private var macDesign: Bool {
        #if os(macOS)
        LayoutWidth.fitsMacDesign(width, column: column, needs: MacDesignWidth.budget)
        #else
        false
        #endif
    }

    // MARK: Shared parts

    private var currency: String { session.currency }

    /// "Other" in the bar and legend, darker than the unspent remainder (as on Home).
    static let otherColor = Color.gray.opacity(0.55)

    private func slices(_ budget: BudgetMonth, limit: Int) -> [BudgetSlice] {
        HomeModel.budgetSlices(budget.spending, limit: limit)
    }

    /// A group's color: its slice's palette color, else grey.
    private func color(of group: String, _ budget: BudgetMonth) -> Color {
        let names = slices(budget, limit: 3).filter { !$0.isOther }.map(\.name)
        return names.firstIndex(of: group).map { Theme.categoryPalette[$0] } ?? Theme.categoryPalette[4]
    }

    private func barColor(_ row: BudgetRow, _ budget: BudgetMonth) -> Color {
        switch BudgetModel.lineStatus(spent: row.line.actual, budget: row.line.budgeted ?? 0) {
        case .over: Theme.overBar
        case .warn: Theme.spendBar
        case .ok: color(of: row.group.name, budget)
        }
    }

    private func rows(_ budget: BudgetMonth) -> [BudgetRow] {
        BudgetModel.lines(budget, filter: filter).map { BudgetRow(group: $0.group, line: $0.line) }
    }

    /// "Paid", "$188 left" or "$14 over", in the status color. Warnings are semibold.
    private func leftLabel(_ line: BudgetMonth.Line) -> Text {
        let budgeted = line.budgeted ?? 0
        guard budgeted > 0 else { return Text("\(line.actual.wholeMoney(currency)) spent").foregroundStyle(Theme.secondary) }
        let left = budgeted - line.actual
        switch BudgetModel.lineStatus(spent: line.actual, budget: budgeted) {
        case .over: return Text("\((-left).wholeMoney(currency)) over").fontWeight(.semibold).foregroundStyle(Theme.negative)
        case .warn: return Text("\(left.wholeMoney(currency)) left").fontWeight(.semibold).foregroundStyle(Theme.warning)
        case .ok: return Text(left == 0 ? "Paid" : "\(left.wholeMoney(currency)) left").foregroundStyle(Theme.secondary)
        }
    }

    private func perDay(_ left: Double) -> String {
        let days = BudgetModel.daysRemaining(today: Fixtures.today, month: month)
        let amount = BudgetModel.leftPerDay(left: left, today: Fixtures.today, month: month)
        return "\(days) \(days == 1 ? "day" : "days") \u{00B7} \(amount.wholeMoney(currency))/day"
    }

    private func legend(_ budget: BudgetMonth, limit: Int) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(slices(budget, limit: limit).enumerated()), id: \.element.id) { index, slice in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(slice.isOther ? Self.otherColor : Theme.categoryPalette[index]).frame(width: 9, height: 9)
                    Text(slice.name).lineLimit(1)
                }
                .fixedSize()
            }
        }
    }

    private func bar(_ budget: BudgetMonth, limit: Int, height: CGFloat) -> some View {
        let parts = slices(budget, limit: limit)
        return CategoryBar(
            segments: parts.enumerated().map { index, slice in
                .init(id: slice.id, label: slice.name, amount: slice.spent,
                      color: slice.isOther ? Self.otherColor : Theme.categoryPalette[index])
            },
            total: budget.summary.plannedSpending, height: height
        )
    }

    @discardableResult
    private func save(_ line: BudgetMonth.Line, amount: Double?) async -> Bool {
        guard let id = line.categoryId ?? Int(line.key.dropFirst(2)) else { return false }
        do {
            try await session.api.setBudget(categoryId: id, month: monthKey, amount: amount)
            await session.didSave()
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

}

extension BudgetView {
    // MARK: iPhone and iPad

    private func summaryCard(_ budget: BudgetMonth) -> some View {
        let summary = budget.summary
        let left = summary.plannedSpending - summary.spent
        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(left >= 0 ? "Left to spend" : "Over budget").font(.footnote.weight(.medium)).foregroundStyle(Theme.secondary)
                if summary.plannedSpending > 0 {
                    HStack(alignment: .firstTextBaseline) {
                        Text(abs(left).wholeMoney(currency)).font(.system(size: 36, weight: .bold)).monospacedDigit()
                            .foregroundStyle(left >= 0 ? Theme.text : Theme.negative).lineLimit(1).minimumScaleFactor(0.6)
                        Spacer(minLength: 8)
                        Text("\(summary.spent.wholeMoney(currency)) of \(summary.plannedSpending.wholeMoney(currency)) spent")
                            .font(.footnote).foregroundStyle(Theme.secondary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    }
                    bar(budget, limit: 3, height: 10)
                    // The days figure moves under the legend when both don't fit on one line.
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            legend(budget, limit: 3)
                            Spacer(minLength: 6)
                            Text(perDay(left)).fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            legend(budget, limit: 3)
                            Text(perDay(left))
                        }
                    }
                    .font(.footnote).foregroundStyle(Theme.secondary).monospacedDigit()
                    .padding(.top, 2)
                } else {
                    Text("No spending budget for \(month.formatted(.dateTime.month(.wide))).").font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }
                Divider().padding(.vertical, 4)
                incomeLine(budget, soFar: false).font(.footnote).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    /// "Income $6,400 of $6,400" (or "$0 so far" in portrait) and what is left to plan.
    private func incomeLine(_ budget: BudgetMonth, soFar: Bool) -> some View {
        let summary = budget.summary
        return HStack {
            let received = Text(summary.receivedIncome.wholeMoney(currency)).fontWeight(.semibold).foregroundStyle(Theme.text)
            if summary.plannedIncome > 0 {
                let planned = Text(summary.plannedIncome.wholeMoney(currency)).fontWeight(.semibold).foregroundStyle(Theme.text)
                Text("Income \(received)\(Text(" of ").fontWeight(.semibold).foregroundStyle(Theme.text))\(planned)")
            } else {
                Text("Income \(received)\(soFar ? " so far" : "")")
            }
            Spacer()
            let leftToPlan = Text(summary.leftToPlan.wholeMoney(currency)).fontWeight(.semibold)
                .foregroundStyle(summary.leftToPlan < 0 ? Theme.negative : Theme.text)
            Text("Left to plan \(leftToPlan)")
        }
        .foregroundStyle(Theme.secondary).monospacedDigit()
    }

    private func chips(_ budget: BudgetMonth) -> some View {
        let over = BudgetModel.lines(budget, filter: .over).count
        let unbudgeted = BudgetModel.lines(budget, filter: .notBudgeted).count
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", active: filter == .all) { filter = .all }
                FilterChip(title: "Over \u{00B7} \(over)", active: filter == .over) { filter = .over }
                FilterChip(title: "Not budgeted \u{00B7} \(unbudgeted)", active: filter == .notBudgeted) { filter = .notBudgeted }
            }
        }
        .scrollClipDisabled()
    }

    /// `detail` (iPad portrait, iPhone Duo) adds "$1,030 spent of $250" under the name and keeps the status at its
    /// full size; the name wraps to two lines instead.
    private func lineRow(_ row: BudgetRow, _ budget: BudgetMonth, highlighted: Bool = false, detail: Bool = false) -> some View {
        let icon = Icons.category(row.line.name)
        let label = leftLabel(row.line)
        let budgeted = row.line.budgeted ?? 0
        return HStack(alignment: detail ? .top : .center, spacing: 14) {
            IconTile(symbol: icon.0, tint: icon.1, background: highlighted ? Theme.card : icon.1.opacity(0.14), size: detail ? 36 : 34)
            VStack(spacing: detail ? 8 : 9) {
                HStack(alignment: detail ? .center : .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.line.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(detail ? 2 : 1)
                        if detail && budgeted > 0 {
                            Text("\(row.line.actual.wholeMoney(currency)) spent of \(budgeted.wholeMoney(currency))")
                                .font(.footnote).foregroundStyle(Theme.secondary).monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                    label.font(.body).monospacedDigit().fixedSize()
                }
                ProgressLine(value: budgeted > 0 ? row.line.actual / budgeted : 0, color: barColor(row, budget), height: 6)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// The lines in a card. `list` defaults to the filtered lines; `title` heads a card of iPhone Duo's split.
    private func linesCard(
        _ budget: BudgetMonth, list: [BudgetRow]? = nil, select: Bool, title: String? = nil, detail: Bool = false
    ) -> some View {
        let list = list ?? rows(budget)
        return Card(padding: 16) {
            VStack(alignment: .leading, spacing: 4) {
                if let title { Text(title).font(.headline).foregroundStyle(Theme.text).padding(.bottom, 2) }
                if list.isEmpty {
                    Text(filter == .all ? "No spending budgets or spending this month." : "Nothing here this month.")
                        .font(.subheadline).foregroundStyle(Theme.secondary).padding(.vertical, 8)
                } else {
                    DividedRows(items: list) { row in
                        if select {
                            Button { selected = row.id } label: {
                                lineRow(row, budget, highlighted: selected == row.id)
                                    .padding(.horizontal, 8)
                                    .background(selected == row.id ? Theme.accentTint : .clear, in: RoundedRectangle(cornerRadius: 14))
                                    .padding(.horizontal, -8)
                            }
                            .buttonStyle(.plain)
                        } else if let id = row.line.categoryId {
                            NavigationLink(value: AppRoute.category(id)) { lineRow(row, budget, detail: detail) }.buttonStyle(.plain)
                        } else {
                            lineRow(row, budget, detail: detail)
                        }
                    }
                }
            }
        }
    }

    private func phone(_ budget: BudgetMonth) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                if let segment { SegmentBar("Plan page", options: PlanSegment.options, selection: segment) }
                summaryCard(budget)
                chips(budget)
                linesCard(budget, select: false)
            }
            .padding(.horizontal, 20).padding(.top, 4)
        }
    }

    private func pad(_ budget: BudgetMonth) -> some View {
        let list = rows(budget)
        let current = list.first { $0.id == selected } ?? list.first
        return HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    MonthStepper(month: $month)
                    summaryCard(budget)
                    chips(budget)
                    linesCard(budget, select: true)
                }
                .padding(.leading, 28).padding(.trailing, 14).padding(.vertical, 12)
            }
            .containerRelativeFrame(.horizontal) { length, _ in length * 0.41 }
            Divider().padding(.vertical, 12)
            if let id = current?.line.categoryId {
                CategoryDetailView(categoryId: id, month: month, style: .pane).id(id)
            } else {
                EmptyState(title: "No category", message: "Pick a category to see its spending.", symbol: "chart.bar")
            }
        }
    }

    private func portrait(_ budget: BudgetMonth) -> some View {
        let split = BudgetModel.overAndOnTrack(rows(budget)) { $0.line }
        let single = linesCard(budget, list: split.over + split.onTrack, select: false, detail: true)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let segment { SegmentBar("Plan page", options: PlanSegment.options, selection: segment) }
                HStack {
                    MonthStepper(month: $month, format: .dateTime.month(.wide).year())
                    Spacer()
                    let days = BudgetModel.daysRemaining(today: Fixtures.today, month: month)
                    Text("\(days) \(days == 1 ? "day" : "days") left").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                portraitSummary(budget)
                chips(budget)
                // Over budget and on track side by side when both fit and both have rows (DuoInnerBudget), else one
                // list with the over-budget rows first (iPadPBudget).
                if split.over.isEmpty || split.onTrack.isEmpty { single } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            linesCard(budget, list: split.over, select: false, title: "Over budget · \(split.over.count)", detail: true)
                            linesCard(budget, list: split.onTrack, select: false, title: "On track · \(split.onTrack.count)", detail: true)
                        }
                        .wideEnough(600)
                        single
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 12)
        }
    }

    /// Left to spend on its own line; spent and the daily figure below it.
    private func portraitSummary(_ budget: BudgetMonth) -> some View {
        let summary = budget.summary
        let left = summary.plannedSpending - summary.spent
        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(left >= 0 ? "Left to spend" : "Over budget").font(.footnote.weight(.medium)).foregroundStyle(Theme.secondary)
                if summary.plannedSpending > 0 {
                    Text(abs(left).wholeMoney(currency)).font(.system(size: 40, weight: .bold)).monospacedDigit()
                        .foregroundStyle(left >= 0 ? Theme.text : Theme.negative).lineLimit(1).minimumScaleFactor(0.6)
                    HStack {
                        let spent = Text(summary.spent.wholeMoney(currency)).fontWeight(.semibold).foregroundStyle(Theme.text)
                        Text("\(spent) of \(summary.plannedSpending.wholeMoney(currency)) spent")
                        Spacer()
                        let perDay = BudgetModel.leftPerDay(left: left, today: Fixtures.today, month: month)
                        if perDay > 0 { Text("\(perDay.wholeMoney(currency))/day") }
                    }
                    .font(.subheadline).foregroundStyle(Theme.secondary).monospacedDigit()
                    bar(budget, limit: 4, height: 10)
                    legend(budget, limit: 4).font(.footnote).foregroundStyle(Theme.secondary)
                } else {
                    Text("No spending budget for \(month.formatted(.dateTime.month(.wide))).").font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }
                Divider().padding(.vertical, 4)
                incomeLine(budget, soFar: true).font(.subheadline)
            }
        }
    }

    // MARK: Mac

    #if os(macOS)
    private func mac(_ budget: BudgetMonth) -> some View {
        let list = BudgetModel.lines(budget, filter: .all).map { BudgetRow(group: $0.group, line: $0.line) }
        let current = list.first { $0.id == selected } ?? list.first
        return HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    MacBudgetSummary(budget: budget, currency: currency, perDay: perDay)
                    MacBudgetTable(
                        budget: budget, currency: currency, selected: current?.id,
                        color: { color(of: $0, budget) },
                        select: { selected = $0 },
                        save: { line, amount in await save(line, amount: amount) },
                        footer: perDay
                    )
                }
                .padding(20)
            }
            Divider()
            Group {
                if let id = current?.line.categoryId {
                    CategoryDetailView(categoryId: id, month: month, style: .inspector).id(id)
                } else {
                    EmptyState(title: "No category", message: "Select a category.", symbol: "chart.bar")
                }
            }
            .frame(width: 320)
            .background(Theme.toolbar)
        }
        .confirmationDialog(
            "Fill budgets from the 3-month average?", isPresented: Binding { fillPreview != nil } set: { if !$0 { fillPreview = nil } },
            titleVisibility: .visible, presenting: fillPreview
        ) { preview in
            if !preview.rows.isEmpty { Button("Fill \(preview.rows.count) budgets") { Task { await applyFill() } } }
        } message: { preview in
            Text(preview.rows.isEmpty
                ? "No category has spending in the last three months to average."
                : "\(preview.rows.count) budgets in \(month.formatted(.dateTime.month(.wide))) change, "
                    + "\(preview.total.wholeMoney(preview.currency)) in all.")
        }
    }

    private var fillRequest: BudgetFillRequest {
        BudgetFillRequest(months: [monthKey], source: .init(months: 3), overwrite: true, preview: true)
    }

    /// Asks the server what the fill would write; nothing is saved until the preview is confirmed.
    private func previewFill() async {
        filling = true
        defer { filling = false }
        do {
            fillPreview = try await session.api.fillBudgets(fillRequest)
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func applyFill() async {
        filling = true
        defer { filling = false }
        var request = fillRequest
        request.preview = false
        do {
            _ = try await session.api.fillBudgets(request)
            await session.didSave()
        } catch {
            saveError = error.localizedDescription
        }
    }
    #endif
}
