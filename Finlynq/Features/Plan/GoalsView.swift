import SwiftUI

/// Goals (Goals.dc.html): each active goal's progress, what is left, what it needs a month and its target month.
/// Completed goals fold into one row.
struct GoalsView: View {
    var segment: Binding<PlanSegment>?
    @Environment(Session.self) private var session
    @Environment(\.layoutWidth) private var width
    @State private var showCompleted = false
    @Environment(\.presentEditor) private var present

    var body: some View {
        Reloader(id: "\(session.revision)", source: "goals") { try await session.api.goals() } content: { goals in
            content(goals)
        }
        .background(Theme.page)
        .navigationTitle(segment == nil ? "Goals" : "Plan")
        #if os(iOS)
        .toolbarTitleDisplayMode(.large)
        #endif
        .routeDestinations(segment == nil)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New goal", systemImage: "target") { present(.newGoal) }.macTitleAndIcon()
            }
        }
    }

    private func content(_ goals: [Goal]) -> some View {
        let active = goals.filter { $0.status != "completed" }
        let completed = goals.filter { $0.status == "completed" }
        let wide = width == .wide
        return ScrollView {
            VStack(spacing: 12) {
                if let segment { SegmentBar("Plan page", options: PlanSegment.options, selection: segment) }
                if goals.isEmpty {
                    EmptyState(title: "No goals yet", message: "Add a goal to track saving toward it.", symbol: "target")
                        .padding(.top, 40)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: wide ? 360 : 300), spacing: 14, alignment: .top)], spacing: 12) {
                    ForEach(active) { goal in
                        NavigationLink(value: AppRoute.goal(goal.id)) { GoalCard(goal: goal) }.buttonStyle(.plain)
                    }
                }
                if !completed.isEmpty { completedCard(completed) }
            }
            .padding(.horizontal, wide ? 28 : 20).padding(.top, 4).padding(.bottom, 12)
        }
    }

    private func completedCard(_ completed: [Goal]) -> some View {
        Card(padding: 16) {
            VStack(spacing: 0) {
                Button { withAnimation { showCompleted.toggle() } } label: {
                    HStack {
                        Text("Completed").font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                        Spacer()
                        Text("\(completed.count)").foregroundStyle(Theme.secondary)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                            .rotationEffect(.degrees(showCompleted ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if showCompleted {
                    ForEach(completed) { goal in
                        Divider().padding(.vertical, 8)
                        NavigationLink(value: AppRoute.goal(goal.id)) {
                            HStack {
                                Text(goal.displayName).foregroundStyle(Theme.text)
                                Spacer()
                                let amounts = GoalModel.amounts(goal)
                                Text(amounts.target.wholeMoney(amounts.currency)).foregroundStyle(Theme.secondary).monospacedDigit()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// A goal's tile symbol and color: the name's subject (house, car) when it has one, else its type's.
enum GoalStyle {
    struct Icon {
        let symbol: String
        let color: Color
        let tint: Color
    }

    static func icon(_ goal: Goal) -> Icon {
        let name = goal.displayName.lowercased()
        let color = color(goal)
        let tint: Color = switch goal.type {
        case "emergency_fund", "emergency": Theme.positiveTint
        case "debt_payoff", "debt": Theme.warningTint
        case "investment": Theme.investTint
        default: Theme.accentTint
        }
        let symbol = if name.contains("house") || name.contains("home") {
            "house"
        } else if name.contains("car") {
            "car"
        } else {
            switch goal.type {
            case "emergency_fund", "emergency": "shield"
            case "debt_payoff", "debt": "creditcard"
            case "investment": "chart.line.uptrend.xyaxis"
            default: "banknote"
            }
        }
        return Icon(symbol: symbol, color: color, tint: tint)
    }

    static func color(_ goal: Goal) -> Color {
        switch goal.type {
        case "emergency_fund", "emergency": Theme.positiveBar
        case "debt_payoff", "debt": Theme.spendBar
        case "investment": Theme.categoryPalette[1]
        default: Theme.accent
        }
    }

    /// "Emergency fund · Savings": the type and the linked accounts.
    static func subtitle(_ goal: Goal) -> String {
        ([GoalModel.typeName(goal.type)] + (goal.accounts ?? [])).joined(separator: " \u{00B7} ")
    }

    static func deadline(_ goal: Goal) -> Date? { goal.deadline.flatMap(APIDate.parse) }
}

struct GoalCard: View {
    let goal: Goal

    var body: some View {
        let amounts = GoalModel.amounts(goal)
        let icon = GoalStyle.icon(goal)
        let fraction = amounts.target > 0 ? amounts.current / amounts.target : 0
        let remaining = max(amounts.target - amounts.current, 0)
        let deadline = GoalStyle.deadline(goal)
        let needed = deadline.map {
            GoalModel.monthlyNeeded(current: amounts.current, target: amounts.target, targetDate: $0, today: Fixtures.today)
        }
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    IconTile(symbol: icon.symbol, tint: icon.color, background: icon.tint, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.displayName).font(.body.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(GoalStyle.subtitle(goal)).font(.subheadline).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(amounts.current.wholeMoney(amounts.currency)).font(.title2.weight(.bold)).foregroundStyle(Theme.text)
                    Text("\(GoalModel.isDebt(goal) ? "paid of" : "of") \(amounts.target.wholeMoney(amounts.currency))")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text(fraction.formatted(.percent.precision(.fractionLength(0)))).font(.body.weight(.bold)).foregroundStyle(Theme.text)
                }
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                ProgressLine(value: fraction, color: icon.color, height: 8)
                Divider().padding(.vertical, 2)
                let remainingStat = stat("Remaining", remaining.wholeMoney(amounts.currency))
                let neededStat = stat("Needed", needed.map { "\($0.wholeMoney(amounts.currency))/mo" } ?? "No date")
                let targetStat = stat("Target", deadline.map { $0.formatted(.dateTime.month(.abbreviated).year()) } ?? "No date")
                // Three in a row when they fit at full size, else the target moves to a second row.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) { remainingStat; neededStat; targetStat }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) { remainingStat; neededStat }
                        targetStat
                    }
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote).foregroundStyle(Theme.secondary)
            Text(value).font(.body.weight(.bold)).foregroundStyle(Theme.text).monospacedDigit().fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
