import SwiftUI

/// Plan's three pages. iPhone shows them under one "Plan" title with a segmented control; iPad and Mac list them
/// in the sidebar, so each page stands alone there.
enum PlanSegment: Hashable {
    case budget, bills, goals

    static let options: [(PlanSegment, String)] = [(.budget, "Budget"), (.bills, "Bills"), (.goals, "Goals")]
}

/// The iPhone Plan tab (Plan.dc.html, Bills.dc.html, Goals.dc.html).
struct PlanView: View {
    /// The shell keeps the segment, so it survives a width class change.
    @Binding var segment: PlanSegment

    var body: some View {
        Group {
            switch segment {
            case .budget: BudgetView(segment: $segment)
            case .bills: BillsView(segment: $segment)
            case .goals: GoalsView(segment: $segment)
            }
        }
        .routeDestinations()
    }
}

extension View {
    /// Registers the app's routes on a stack's root screen. Off for a page embedded in another root (iPhone Plan).
    @ViewBuilder
    func routeDestinations(_ enabled: Bool = true) -> some View {
        if enabled { navigationDestination(for: AppRoute.self) { RouteDestination(route: $0) } } else { self }
    }
}
