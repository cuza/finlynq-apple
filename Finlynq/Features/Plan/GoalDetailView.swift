import SwiftUI

/// One goal (Goal.dc.html): progress ring, what is left, the monthly need against the recent pace, when that pace
/// reaches the target, a year of the linked accounts' balance, and the linked accounts.
struct GoalDetailView: View {
    let goalId: Int
    @Environment(Session.self) private var session
    @Environment(\.layoutWidth) private var width
    @Environment(\.presentEditor) private var present
    @State private var attempt = 0
    /// The loaded goal, for the Edit button in the bar.
    @State private var loaded: Goal?
    @State private var writing = false
    @State private var writeError: String?

    struct Data {
        let goal: Goal?
        /// The linked accounts' summed balance per day over the last year; nil when history failed to load.
        let balance: [(Date, Double)]?
        /// Each linked account's latest balance, by account id.
        let accountBalances: [Int: Double]
    }

    private var today: Date { Fixtures.today }

    var body: some View {
        Reloader(id: "\(goalId)|\(session.revision)|\(attempt)", source: "goal") { try await load() } content: { data in
            if let goal = data.goal {
                content(goal, data)
                    .onChange(of: goal, initial: true) { loaded = goal }
                    .safeAreaInset(edge: .bottom, spacing: 0) { statusBar(goal) }
            } else {
                EmptyState(title: "Goal not found", message: "It may have been deleted.", symbol: "target")
            }
        }
        .background(Theme.page)
        .modifier(PushedPageBar(enabled: true, title: loaded?.displayName ?? "Goal") {
            if let loaded { Button("Edit", systemImage: "pencil") { present(.editGoal(loaded)) } }
        })
        .alert("Couldn't save the goal", isPresented: Binding { writeError != nil } set: { if !$0 { writeError = nil } }) {
            Button("OK") {}
        } message: {
            Text(writeError ?? "")
        }
    }

    /// Saves a change to the goal, then reloads every screen keyed on the session's revision.
    private func update(_ change: GoalUpdate) async {
        writing = true
        defer { writing = false }
        do {
            try await session.api.updateGoal(change)
            await session.didSave()
        } catch {
            writeError = error.localizedDescription
        }
    }

    /// "Mark complete", or "Mark active" on a completed goal (Goal.dc.html bottom bar).
    private func statusBar(_ goal: Goal) -> some View {
        let completed = goal.status == "completed"
        return VStack(spacing: 0) {
            Divider()
            Button { Task { await update(GoalUpdate(id: goal.id, status: completed ? "active" : "completed")) } } label: {
                Label(completed ? "Mark active" : "Mark complete", systemImage: completed ? "arrow.uturn.backward" : "checkmark")
                    .font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(writing)
            .frame(maxWidth: 680)
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Theme.page)
    }

    private func load() async throws -> Data {
        async let goals = session.api.goals()
        async let history = optionalLoad("goal balance") { try await session.api.netWorthHistory(period: "1y") }
        let goal = try await goals.first { $0.id == goalId }
        let ids = Set(goal?.accountIds ?? goal?.accountId.map { [$0] } ?? [])
        let series = await history?.series
        let balance = series?.compactMap { point -> (Date, Double)? in
            guard let members = point.members else { return nil }
            return (point.day, members.filter { ids.contains($0.id) }.reduce(0) { $0 + $1.value })
        }
        let latest = series?.last?.members?.filter { ids.contains($0.id) } ?? []
        return Data(goal: goal, balance: balance, accountBalances: Dictionary(latest.map { ($0.id, $0.value) }) { first, _ in first })
    }

    private func content(_ goal: Goal, _ data: Data) -> some View {
        let wide = width == .wide
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(subtitle(goal)).font(.subheadline).foregroundStyle(Theme.secondary)
                progressCard(goal, data)
                balanceCard(goal, data)
                accountsCard(goal, data)
            }
            .padding(.horizontal, wide ? 28 : 20).padding(.bottom, 24)
            .frame(maxWidth: wide ? 720 : .infinity, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func subtitle(_ goal: Goal) -> String {
        let deadline = GoalStyle.deadline(goal).map { "by " + $0.formatted(.dateTime.month(.abbreviated).year()) }
        return ["\(GoalModel.typeName(goal.type)) goal", deadline].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    // MARK: Progress

    private func progressCard(_ goal: Goal, _ data: Data) -> some View {
        let amounts = GoalModel.amounts(goal)
        let color = GoalStyle.color(goal)
        let fraction = amounts.target > 0 ? min(amounts.current / amounts.target, 1) : 0
        let deadline = GoalStyle.deadline(goal)
        let needed = deadline.map {
            GoalModel.monthlyNeeded(current: amounts.current, target: amounts.target, targetDate: $0, today: today)
        }
        // A linked debt's balance is negative and rises toward zero as it is paid, so its pace is positive as it is.
        let pace = data.balance.map { GoalModel.monthlyPace($0, today: today) }
        let projected = pace.flatMap {
            GoalModel.projectedDate(current: amounts.current, target: amounts.target, monthlyPace: $0, today: today)
        }
        let onTrack: Bool? = deadline.map {
            GoalModel.onTrack(projected: projected, deadline: $0, current: amounts.current, target: amounts.target)
        }
        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 22) {
                    ZStack {
                        Circle().stroke(Theme.fill, lineWidth: 13)
                        Circle().trim(from: 0, to: fraction).stroke(color, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(fraction.formatted(.percent.precision(.fractionLength(0)))).font(.title.weight(.bold))
                            .foregroundStyle(Theme.text).monospacedDigit()
                    }
                    .frame(width: 104, height: 104)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("To go").font(.subheadline).foregroundStyle(Theme.secondary)
                        Text(max(amounts.target - amounts.current, 0).wholeMoney(amounts.currency))
                            .font(.system(size: 32, weight: .bold)).foregroundStyle(Theme.text).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("\(amounts.current.wholeMoney(amounts.currency)) of \(amounts.target.wholeMoney(amounts.currency))")
                            .font(.subheadline).foregroundStyle(Theme.secondary).monospacedDigit()
                        if let onTrack {
                            Label(onTrack ? "On track" : "Behind", systemImage: onTrack ? "checkmark" : "exclamationmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(onTrack ? Theme.positive : Theme.warning)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(onTrack ? Theme.positiveTint : Theme.warningTint, in: Capsule())
                                .padding(.top, 2)
                        }
                    }
                }
                Divider()
                figures(currency: amounts.currency, needed: needed, pace: pace, deadline: deadline, projected: projected)
            }
        }
    }

    private func figures(currency: String, needed: Double?, pace: Double?, deadline: Date?, projected: Date?) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
            GridRow {
                stat("Needed", needed.map { "\($0.wholeMoney(currency)) / month" } ?? "No target date")
                stat("Your pace", pace.map { "\($0.wholeMoney(currency)) / month" } ?? "\u{2013}", detail: "last 6 months")
            }
            GridRow {
                stat("Target date", deadline.map { $0.formatted(.dateTime.month(.abbreviated).year()) } ?? "None")
                stat("At this pace", projected.map { $0.formatted(.dateTime.month(.abbreviated).year()) } ?? "Not moving",
                     detail: projection(projected, deadline).text, detailColor: projection(projected, deadline).color)
            }
        }
    }

    /// "5 months early" or "2 months late", against the target date.
    private func projection(_ projected: Date?, _ deadline: Date?) -> (text: String?, color: Color) {
        guard let projected, let deadline else { return (nil, Theme.secondary) }
        let months = GoalModel.months(from: projected, to: deadline)
        if months == 0 { return ("right on time", Theme.positive) }
        let count = "\(abs(months)) \(abs(months) == 1 ? "month" : "months")"
        return months > 0 ? ("\(count) early", Theme.positive) : ("\(count) late", Theme.warning)
    }

    private func stat(_ label: String, _ value: String, detail: String? = nil, detailColor: Color = Theme.secondary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline).foregroundStyle(Theme.secondary)
            Text(value).font(.title3.weight(.bold)).foregroundStyle(Theme.text).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if let detail {
                Text(detail).font(.subheadline.weight(detailColor == Theme.secondary ? .regular : .semibold)).foregroundStyle(detailColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Balance

    @ViewBuilder
    private func balanceCard(_ goal: Goal, _ data: Data) -> some View {
        let amounts = GoalModel.amounts(goal)
        let color = GoalStyle.color(goal)
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                if let balance = data.balance, balance.count > 1, let first = balance.first, let last = balance.last {
                    let change = last.1 - first.1
                    let months = max(GoalModel.months(from: first.0, to: last.0), 1)
                    HStack {
                        Text("Balance").font(.headline).foregroundStyle(Theme.text)
                        Spacer()
                        Text("\(HomeModel.signedChange(change, percent: nil, currency: amounts.currency)) in \(months) months")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(change >= 0 ? Theme.positive : Theme.negative)
                    }
                    TimeSeriesChart(
                        points: balance.map { ValuePoint(day: $0.0, value: $0.1) }, color: color, height: 140, xAxis: .months(5),
                        currency: amounts.currency, fillOpacity: 0.12,
                        target: GoalModel.isDebt(goal) ? nil : (amounts.target, "\(amounts.target.wholeMoney(amounts.currency)) target")
                    )
                    .accessibilityLabel("Balance over the last year")
                } else {
                    Text("Balance").font(.headline).foregroundStyle(Theme.text)
                    if data.balance == nil {
                        InlineError(message: "Couldn't load the balance history") { attempt += 1 }
                    } else {
                        Text("No balance history for the linked accounts yet.").font(.footnote).foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }

    // MARK: Accounts

    private func accountsCard(_ goal: Goal, _ data: Data) -> some View {
        let ids = goal.accountIds ?? goal.accountId.map { [$0] } ?? []
        let accounts = ids.compactMap { id in session.accounts.first { $0.id == id } }
        return Card(padding: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Linked accounts").font(.headline).foregroundStyle(Theme.text).padding(.bottom, 4)
                if accounts.isEmpty {
                    Text("No accounts linked yet. Link one to track progress.").font(.footnote).foregroundStyle(Theme.secondary)
                } else {
                    DividedRows(items: accounts) { account in
                        NavigationLink(value: AppRoute.account(account.id)) {
                            HStack(spacing: 14) {
                                let symbol = Icons.account(
                                    group: account.group, isLiability: account.type == "L", isInvestment: account.isInvestment
                                )
                                IconTile(symbol: symbol, tint: Theme.positive, background: Theme.positiveTint, size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.displayName).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                                    Text(account.group).font(.subheadline).foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                if let balance = data.accountBalances[account.id] {
                                    Text(balance.money(GoalModel.amounts(goal).currency)).font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.text).monospacedDigit().fixedSize()
                                }
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                            }
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                linkMenu(goal, linked: ids)
            }
        }
    }

    /// "+ Link an account": adds one of the other open accounts to the goal's links.
    @ViewBuilder
    private func linkMenu(_ goal: Goal, linked: [Int]) -> some View {
        let others = session.accounts.filter { !$0.archived && !linked.contains($0.id) }
        if !others.isEmpty {
            Divider()
            Menu {
                ForEach(others) { account in
                    Button(account.displayName) { Task { await update(GoalUpdate(id: goal.id, accountIds: linked + [account.id])) } }
                }
            } label: {
                Label("Link an account", systemImage: "plus").font(.body.weight(.medium)).foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10).contentShape(Rectangle())
            }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain)
            .disabled(writing)
        }
    }
}
