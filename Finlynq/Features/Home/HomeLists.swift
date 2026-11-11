import SwiftUI

// MARK: Budget

struct BudgetCard: View {
    let layout: HomeLayout
    /// iPad portrait and iPhone Duo: the amount left on its own line, the daily figure below it.
    var portrait = false
    let budget: BudgetMonth?
    let today: Date
    let currency: String?

    private struct Row: Identifiable {
        let slice: BudgetSlice
        let color: Color
        var id: String { slice.id }
    }

    /// A neutral grey for "Other", darker than the bar's unspent remainder.
    private static let otherColor = Color.gray.opacity(0.55)

    /// Up to three groups and "Other" on the phone, four on iPad and Mac: one palette color each.
    private var rows: [Row] {
        HomeModel.budgetSlices(budget?.spending ?? [], limit: layout == .phone ? 3 : 4).enumerated().map { index, slice in
            Row(slice: slice, color: slice.isOther ? Self.otherColor : Theme.categoryPalette[index])
        }
    }

    var body: some View {
        NavigationLink(value: AppRoute.budget) {
            Card(padding: layout == .phone ? 16 : 18) { content }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        let title = today.formatted(.dateTime.month(.wide)) + " budget"
        if let summary = budget?.summary, summary.plannedSpending > 0 {
            let planned = summary.plannedSpending
            let left = planned - summary.spent
            let groupRows = rows
            VStack(alignment: .leading, spacing: layout == .mac ? 12 : 10) {
                HomeCardHeader(
                    title: title, detail: "\(summary.spent.wholeMoney(currency)) of \(planned.wholeMoney(currency))", layout: layout
                )
                if portrait {
                    portraitHeadline(left: left)
                } else if layout == .pad {
                    padHeadline(left: left)
                }
                CategoryBar(
                    segments: groupRows.map { .init(id: $0.id, label: $0.slice.name, amount: $0.slice.spent, color: $0.color) },
                    total: planned, height: layout == .phone ? 8 : 10
                )
                switch layout {
                case .phone:
                    // The legend wraps to two lines when it doesn't fit beside "left".
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        legend(groupRows)
                        Spacer(minLength: 0)
                        leftText(left).font(.caption.weight(.semibold)).fixedSize()
                    }
                case .pad:
                    legend(groupRows)
                    Divider()
                    HStack {
                        let income = Text(summary.receivedIncome.wholeMoney(currency)).foregroundStyle(Theme.text).fontWeight(.semibold)
                        Text("Income \(income)")
                        Spacer()
                        let net = summary.receivedIncome - summary.spent
                        let netText = Text(HomeModel.signedChange(net, percent: nil, currency: currency))
                            .foregroundStyle(net >= 0 ? Theme.positive : Theme.negative).fontWeight(.semibold)
                        Text("Net \(netText) this month")
                    }
                    .font(.footnote).foregroundStyle(Theme.secondary).monospacedDigit()
                case .mac:
                    macRows(groupRows, left: left)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HomeCardHeader(title: title, layout: layout)
                Text("No spending budget set for this month.").font(layout.rowDetail).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func leftText(_ left: Double) -> Text {
        Text(left >= 0 ? "\(left.wholeMoney(currency)) left" : "\((-left).wholeMoney(currency)) over")
            .foregroundStyle(left >= 0 ? Theme.text : Theme.negative)
    }

    private func padHeadline(left: Double) -> some View {
        let perDay = HomeModel.perDay(left: left, today: today)
        return HStack(alignment: .firstTextBaseline) {
            let amount = Text(abs(left).wholeMoney(currency)).font(.system(size: 28, weight: .bold))
                .foregroundStyle(left >= 0 ? Theme.text : Theme.negative)
            Text("\(amount) \(left >= 0 ? "left" : "over")")
                .font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary).monospacedDigit()
            Spacer()
            if left > 0 {
                Text("\(perDay.days) \(perDay.days == 1 ? "day" : "days") \u{00B7} \(perDay.amount.wholeMoney(currency))/day")
                    .font(.footnote).foregroundStyle(Theme.secondary).monospacedDigit()
            }
        }
    }

    private func portraitHeadline(left: Double) -> some View {
        let perDay = HomeModel.perDay(left: left, today: today)
        return VStack(alignment: .leading, spacing: 4) {
            let amount = Text(abs(left).wholeMoney(currency)).font(.system(size: 34, weight: .bold))
                .foregroundStyle(left >= 0 ? Theme.text : Theme.negative)
            Text("\(amount) \(left >= 0 ? "left" : "over")")
                .font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary).monospacedDigit().fixedSize()
            if left > 0 {
                let days = "\(perDay.days) \(perDay.days == 1 ? "day" : "days") to go"
                Text("\(days) \u{00B7} about \(perDay.amount.wholeMoney(currency)) a day")
                    .font(.footnote).foregroundStyle(Theme.secondary).monospacedDigit()
            }
        }
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
    }

    /// Every slice's swatch and name, on one line when it fits, else on two.
    private func legend(_ rows: [Row]) -> some View {
        let half = (rows.count + 1) / 2
        return ViewThatFits(in: .horizontal) {
            legendLine(rows[...])
            VStack(alignment: .leading, spacing: 4) {
                legendLine(rows[..<half])
                legendLine(rows[half...])
            }
        }
        .font(.caption).foregroundStyle(Theme.secondary)
    }

    private func legendLine(_ rows: ArraySlice<Row>) -> some View {
        HStack(spacing: layout == .pad ? 14 : 10) {
            ForEach(rows) { row in
                HStack(spacing: 5) { swatch(row.color); Text(row.slice.name) }.fixedSize()
            }
        }
    }

    private func macRows(_ rows: [Row], left: Double) -> some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    swatch(row.color)
                    Text(row.slice.name).foregroundStyle(Theme.text)
                    Spacer()
                    if let flag = row.slice.flag {
                        Text(flag).font(.callout.weight(.semibold)).foregroundStyle(Theme.negative).padding(.trailing, 6)
                    }
                    Text(row.slice.spent.wholeMoney(currency) + (row.slice.budgeted.map { " / " + $0.wholeMoney(currency) } ?? ""))
                        .foregroundStyle(Theme.secondary)
                }
                .frame(height: 28)
                Divider()
            }
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.fill)
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.categoryPalette[4])).frame(width: 8, height: 8)
                Text(left >= 0 ? "Left to spend" : "Over budget").fontWeight(.semibold).foregroundStyle(Theme.text)
                Spacer()
                Text(abs(left).wholeMoney(currency)).fontWeight(.bold).foregroundStyle(left >= 0 ? Theme.text : Theme.negative)
            }
            .frame(height: 30)
        }
        .monospacedDigit()
    }
}

// MARK: Bills

struct BillsCard: View {
    let layout: HomeLayout
    let bills: [Bill]
    let today: Date
    let currency: String?
    /// iPad footer: the account most bills are charged to and its balance after them.
    var afterBills: (name: String, amount: Double)?

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 4) {
                HomeCardHeader(title: "Bills this week", link: (layout == .mac ? "All bills" : "See all", .bills), layout: layout)
                    .padding(.bottom, 4)
                if bills.isEmpty {
                    Text("Nothing due in the next 7 days.").font(layout.rowDetail).foregroundStyle(Theme.secondary)
                } else {
                    DividedRows(items: bills) { bill in
                        NavigationLink(value: AppRoute.bills) { row(bill) }.buttonStyle(.plain)
                    }
                    Divider()
                    footer
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ bill: Bill) -> some View {
        if layout == .mac {
            HStack(spacing: 10) {
                VStack(spacing: 0) {
                    Text(bill.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                    Text(bill.date.formatted(.dateTime.day())).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                }
                .frame(width: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bill.name).font(layout.rowTitle).foregroundStyle(Theme.text)
                    Text([bill.category, bill.account].compactMap { $0 }.joined(separator: " \u{00B7} "))
                        .font(layout.rowDetail).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text(bill.amount.money(currency)).fontWeight(.semibold).monospacedDigit().foregroundStyle(Theme.text)
            }
            .frame(height: 40)
            .contentShape(Rectangle())
        } else {
            let icon = Icons.bill(name: bill.name, category: bill.category, isLoan: bill.isLoan)
            HStack(spacing: 12) {
                IconTile(symbol: icon.symbol, tint: icon.tint, background: icon.tint.opacity(0.15), size: layout.tileSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bill.name).font(layout.rowTitle).foregroundStyle(Theme.text)
                    Text([bill.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()), bill.account].compactMap { $0 }
                        .joined(separator: " \u{00B7} "))
                        .font(layout.rowDetail).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 8)
                // Amounts never wrap; the name side takes what's left.
                VStack(alignment: .trailing, spacing: 2) {
                    Text(bill.amount.money(currency)).font(layout.rowTitle).monospacedDigit().foregroundStyle(Theme.text)
                    Text(HomeModel.dueIn(bill.date, today: today)).font(layout.rowDetail).foregroundStyle(Theme.secondary)
                }
                .fixedSize()
            }
            .padding(.vertical, layout.rowPadding)
            .contentShape(Rectangle())
        }
    }

    private var footer: some View {
        let total = bills.reduce(0) { $0 + $1.amount }
        let last = bills.last.map { $0.date.formatted(.dateTime.weekday(.wide)) } ?? ""
        return HStack {
            if layout == .pad, let afterBills {
                let amount = Text(afterBills.amount.wholeMoney(currency)).fontWeight(.semibold).foregroundStyle(Theme.text)
                Text("\(afterBills.name) after bills \(amount)")
            } else {
                Text("\(bills.count) \(bills.count == 1 ? "bill" : "bills") due by \(last)")
            }
            Spacer()
            let amount = Text(total.money(currency)).fontWeight(layout == .mac ? .bold : .semibold).foregroundStyle(Theme.text)
            Text("\(layout == .mac ? "" : "Total ")\(amount)")
        }
        .font(layout.rowDetail).foregroundStyle(Theme.secondary).monospacedDigit()
        .padding(.vertical, 8)
    }
}

// MARK: Recent

struct RecentCard: View {
    let layout: HomeLayout
    /// iPad portrait and iPhone Duo: the day joins the detail line, so the amount keeps its room.
    var portrait = false
    let transactions: [Transaction]
    let today: Date

    var body: some View {
        Card(padding: layout == .phone ? 16 : 18) {
            VStack(alignment: .leading, spacing: 4) {
                HomeCardHeader(
                    title: layout == .phone ? "Recent" : "Recent activity",
                    link: (layout == .mac ? "Show all" : "See all", .activity), layout: layout
                )
                .padding(.bottom, 4)
                if transactions.isEmpty {
                    Text("No transactions yet.").font(layout.rowDetail).foregroundStyle(Theme.secondary)
                } else if layout == .mac {
                    table
                } else {
                    DividedRows(items: transactions) { transaction in
                        NavigationLink(value: AppRoute.transaction(transaction.id)) { row(transaction) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func dayText(_ transaction: Transaction) -> String {
        Calendar.current.isDate(transaction.day, inSameDayAs: today)
            ? "Today" : transaction.day.formatted(.dateTime.month(.abbreviated).day())
    }

    private func row(_ transaction: Transaction) -> some View {
        let icon = Icons.transaction(transaction)
        let category = transaction.categoryName ?? "Needs a category"
        let detail = [category, layout == .pad ? transaction.account : nil, portrait ? dayText(transaction) : nil]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        return HStack(spacing: 12) {
            IconTile(symbol: icon.0, tint: icon.1, background: icon.1.opacity(0.15), size: layout == .phone ? 34 : 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.title).font(layout.rowTitle).foregroundStyle(Theme.text).lineLimit(1)
                Text(detail).font(layout.rowDetail).foregroundStyle(transaction.categoryName == nil ? Theme.warning : Theme.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if layout == .pad && !portrait {
                Text(dayText(transaction)).font(layout.rowDetail).foregroundStyle(Theme.secondary).frame(width: 52, alignment: .trailing)
            }
            MoneyText(amount: transaction.amount, currency: transaction.currency).font(layout.rowTitle).fixedSize()
                .frame(minWidth: layout == .pad ? 84 : nil, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // Mac: Date, Payee, Category, Account, Amount.
    private var table: some View {
        VStack(spacing: 0) {
            columns(Text("Date"), Text("Payee"), Text("Category"), Text("Account"), Text("Amount"))
                .font(.callout.weight(.medium)).foregroundStyle(Theme.secondary).padding(.vertical, 6)
            Divider()
            DividedRows(items: transactions) { transaction in
                NavigationLink(value: AppRoute.transaction(transaction.id)) {
                    columns(
                        Text(dayText(transaction)).foregroundStyle(Theme.secondary),
                        Text(transaction.title).fontWeight(.medium).foregroundStyle(Theme.text),
                        CategoryPill(transaction: transaction),
                        Text(transaction.account).foregroundStyle(Theme.secondary),
                        MoneyText(amount: transaction.amount, currency: transaction.currency).fontWeight(.medium)
                    )
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func columns(
        _ date: some View, _ payee: some View, _ category: some View, _ account: some View, _ amount: some View
    ) -> some View {
        HStack(spacing: 8) {
            date.frame(width: 64, alignment: .leading)
            payee.frame(maxWidth: .infinity, alignment: .leading)
            category.frame(width: 162, alignment: .leading)
            account.frame(width: 162, alignment: .leading)
            amount.frame(width: 110, alignment: .trailing)
        }
        .lineLimit(1)
    }
}
