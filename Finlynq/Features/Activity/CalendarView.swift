import SwiftUI

/// The `.calendar` route: Activity with its calendar mode on.
struct CalendarView: View {
    var body: some View { ActivityView(showsCalendar: true) }
}

/// Activity's calendar mode (Calendar.dc.html, iPadPCalendar.dc.html): month totals, a month grid with daily spending,
/// income and bills still due, and the selected day's transactions and bills. With room (iPad), the grid has taller
/// cells with whole amounts and weekday names, and the month's later bills follow the day.
struct CalendarContent: View {
    @Environment(Session.self) private var session
    @Environment(\.layoutWidth) private var width
    let store: ActivityStore
    @State private var selected: Date?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let calendar = Calendar(identifier: .gregorian)

    var body: some View {
        let days = CalendarModel.days(month: store.month, rows: store.rows, bills: store.bills, rates: store.rates)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                summary(days)
                grid(days, current: selected ?? days.first(where: \.isToday)?.date)
                if let day = days.first(where: { $0.date == (selected ?? days.first(where: \.isToday)?.date) }) {
                    dayList(day)
                    if roomy { comingUp(days, after: day.date) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transfers and trades are not counted as spending or income.")
                    let missing = ActivityModel.unconverted(store.rows, rates: store.rates)
                    if !missing.isEmpty { Text("Some amounts in \(missing.joined(separator: ", ")) aren't included") }
                }
                .font(.caption).foregroundStyle(Theme.secondary).padding(.horizontal, 4)
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: store.month) { selected = nil }
    }

    private var roomy: Bool { width != .compact }

    // MARK: Pieces

    private var header: some View {
        HStack {
            monthButton("chevron.left", by: -1, label: "Previous month")
            Spacer()
            Text(store.month.formatted(.dateTime.month(.wide).year())).font(.headline.weight(.bold)).foregroundStyle(Theme.text)
            Spacer()
            monthButton("chevron.right", by: 1, label: "Next month")
        }
    }

    private func monthButton(_ symbol: String, by months: Int, label: String) -> some View {
        Button {
            if let next = calendar.date(byAdding: .month, value: months, to: store.month) { store.month = next }
        } label: {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                .frame(width: 40, height: 40).background(Theme.card, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func summary(_ days: [CalendarDay]) -> some View {
        let spent = days.reduce(0) { $0 + $1.spent }
        let income = days.reduce(0) { $0 + $1.income }
        let due = days.filter(\.isFuture).flatMap(\.bills).reduce(0) { $0 + ($1.displayAmount ?? $1.amount) }
        return HStack(alignment: .top, spacing: 8) {
            stat("Spent", MoneyText.format(spent, currency: session.currency, cents: false), Theme.text)
            stat("Income", MoneyText.format(income, currency: session.currency, signed: true, cents: false), Theme.positive)
            stat("Bills still due", MoneyText.format(due, currency: session.currency, cents: false), Theme.warning)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .listCard()
        .accessibilityElement(children: .combine)
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Theme.secondary)
            Text(value).font(roomy ? .title3.weight(.bold) : .headline.weight(.bold)).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `current` is the highlighted day: the picked one, else today when it is in this month.
    private func grid(_ days: [CalendarDay], current: Date?) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                let names = roomy ? calendar.shortWeekdaySymbols : calendar.veryShortWeekdaySymbols
                ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                    Text(name).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)
            .accessibilityHidden(true)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<CalendarModel.leadingBlanks(month: store.month), id: \.self) { _ in Color.clear.frame(height: cellHeight) }
                ForEach(days) { day in cell(day, selected: day.date == current) }
            }
            legend.padding(.top, 8)
        }
        .padding(.horizontal, 10).padding(.vertical, 12)
        .listCard(radius: 20)
    }

    private func cell(_ day: CalendarDay, selected isSelected: Bool) -> some View {
        let bills = day.isFuture || day.isToday ? day.bills.reduce(0) { $0 + ($1.displayAmount ?? $1.amount) } : 0
        let dueOutline = bills > 0 && !isSelected
        return Button { selected = day.date } label: {
            VStack(spacing: 1) {
                number(day, selected: isSelected)
                if day.spent > 0 {
                    amount(cellMoney(day.spent), isSelected ? .white : Theme.secondary)
                }
                if day.income > 0 {
                    amount("+" + cellMoney(day.income), isSelected ? .white : Theme.positive)
                }
                if bills > 0 { amount(cellMoney(bills, cents: true), isSelected ? .white : Theme.warning) }
            }
            .lineLimit(1).minimumScaleFactor(0.6).monospacedDigit()
            .padding(.top, 6)
            .frame(maxWidth: .infinity, minHeight: cellHeight, maxHeight: cellHeight, alignment: .top)
            .background(
                isSelected ? Theme.accent : dueOutline ? Theme.card : .clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                if dueOutline {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.spendBar, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(day))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var cellHeight: CGFloat { roomy ? 64 : 52 }

    /// "₹8.88K" in a phone cell; "$1,450" (or a bill's "$11.29") where the cells are wider.
    private func cellMoney(_ amount: Double, cents: Bool = false) -> String {
        guard roomy else { return amount.compactMoney(session.currency) }
        return amount.money(session.currency, cents: cents && amount.rounded() != amount)
    }

    @ViewBuilder
    private func number(_ day: CalendarDay, selected: Bool) -> some View {
        let text = Text("\(day.number)").font(.subheadline.weight(day.isToday || selected ? .bold : .medium))
        if day.isToday && !selected {
            text.foregroundStyle(Theme.accent).frame(width: 22, height: 22).background(Theme.accentTint, in: Circle()).padding(.top, -2)
        } else {
            text.foregroundStyle(selected ? .white : Theme.text)
        }
    }

    private func amount(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: roomy ? 11 : 10, weight: .semibold)).foregroundStyle(color)
    }

    private func accessibilityLabel(_ day: CalendarDay) -> String {
        var parts = [day.date.formatted(.dateTime.month(.wide).day())]
        if day.spent > 0 { parts.append("spent " + MoneyText.format(day.spent, currency: session.currency)) }
        if day.income > 0 { parts.append("income " + MoneyText.format(day.income, currency: session.currency)) }
        for bill in day.bills { parts.append("bill due: \(bill.displayName) " + MoneyText.format(bill.amount, currency: bill.currency)) }
        if day.isToday { parts.append("today") }
        return parts.joined(separator: ", ")
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("Spent") { RoundedRectangle(cornerRadius: 3).fill(Theme.secondary).frame(width: 10, height: 10) }
            legendItem("Income") { RoundedRectangle(cornerRadius: 3).fill(Theme.positiveBar).frame(width: 10, height: 10) }
            legendItem("Bill due") {
                RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.spendBar, style: StrokeStyle(lineWidth: 1.5, dash: [2, 1.5]))
                    .frame(width: 10, height: 10)
            }
        }
        .font(.caption).foregroundStyle(Theme.secondary)
        .frame(maxWidth: .infinity)
    }

    private func legendItem(_ title: String, @ViewBuilder swatch: () -> some View) -> some View {
        HStack(spacing: 5) { swatch(); Text(title) }
    }

    private func dayList(_ day: CalendarDay) -> some View {
        let items = store.rows.filter { $0.date.prefix(10) == APIDate.string(day.date) }
        let distance = calendar.dateComponents([.day], from: calendar.startOfDay(for: Fixtures.today), to: day.date).day ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            Text(
                day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                    + (distance > 0 ? " · in \(distance) day\(distance == 1 ? "" : "s")" : "")
            )
            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
            .padding(.horizontal, 4).padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(day.bills.enumerated()), id: \.element.id) { index, bill in
                    if index > 0 { Divider() }
                    NavigationLink(value: AppRoute.bills) { billRow(bill) }.buttonStyle(.plain)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, transaction in
                    if index > 0 || !day.bills.isEmpty { Divider() }
                    NavigationLink(value: transaction) {
                        ActivityRow(transaction: transaction).padding(.vertical, 11).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if items.isEmpty && day.bills.isEmpty {
                    Text("Nothing on this day.").font(.subheadline).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                }
            }
            .padding(.horizontal, 16)
            .listCard()
        }
    }

    /// Bills due later this month than `day`, soonest first (iPadPCalendar).
    @ViewBuilder
    private func comingUp(_ days: [CalendarDay], after day: Date) -> some View {
        let later = CalendarModel.billsAfter(day, in: days)
        if !later.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Coming up this month").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 4).padding(.top, 4).accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(Array(later.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Divider() }
                        NavigationLink(value: AppRoute.bills) { laterRow(item.bill, date: item.date) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .listCard()
            }
        }
    }

    private func laterRow(_ bill: Subscription, date: Date) -> some View {
        let icon = Icons.bill(name: bill.displayName, category: bill.categoryName, isLoan: false)
        let day = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return HStack(spacing: 12) {
            IconTile(symbol: icon.symbol, tint: icon.tint, background: icon.tint.opacity(0.15))
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text([day, bill.accountName].compactMap { $0 }.joined(separator: " · ")).font(.footnote).foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(MoneyText.format(bill.amount, currency: bill.currency)).font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(HomeModel.dueIn(date, today: Fixtures.today)).font(.footnote).foregroundStyle(Theme.secondary)
            }
            .monospacedDigit().fixedSize()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func billRow(_ bill: Subscription) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: Icons.bill(name: bill.displayName, category: bill.categoryName, isLoan: false).symbol,
                     tint: Theme.warning, background: Theme.warningTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(["Bill", bill.accountName].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(MoneyText.format(bill.amount, currency: bill.currency)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Theme.text)
                Text("Upcoming").font(.caption.weight(.semibold)).foregroundStyle(Theme.warning)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary.opacity(0.7))
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
