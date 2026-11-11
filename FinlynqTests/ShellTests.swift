import SwiftUI
import Testing
@testable import Finlynq

/// The shell swaps the iPhone tabs for the sidebar when the width class changes (iPhone Duo opening or closing, iPad
/// Split View). `ShellPlace` hands the place across: the page, Plan's segment, the pushed pages and Settings.
struct ShellTests {
    @Test func eachTabOpensItsSidebarPage() {
        #expect(RootView.SidebarItem(tab: .home, segment: .budget) == .route(.home))
        #expect(RootView.SidebarItem(tab: .activity, segment: .budget) == .route(.activity))
        #expect(RootView.SidebarItem(tab: .plan, segment: .budget) == .route(.budget))
        #expect(RootView.SidebarItem(tab: .plan, segment: .bills) == .route(.bills))
        #expect(RootView.SidebarItem(tab: .plan, segment: .goals) == .route(.goals))
        #expect(RootView.SidebarItem(tab: .wealth, segment: .goals) == .route(.accounts))
        #expect(RootView.SidebarItem(tab: .insights, segment: .budget) == .route(.insights))
    }

    @Test func eachSidebarItemOpensTheTabThatHoldsIt() {
        #expect(RootView.Tab(sidebar: .route(.home)) == .home)
        #expect(RootView.Tab(sidebar: .route(.activity)) == .activity)
        #expect(RootView.Tab(sidebar: .route(.budget)) == .plan)
        #expect(RootView.Tab(sidebar: .route(.bills)) == .plan)
        #expect(RootView.Tab(sidebar: .route(.goals)) == .plan)
        #expect(RootView.Tab(sidebar: .route(.accounts)) == .wealth)
        #expect(RootView.Tab(sidebar: .route(.investments)) == .wealth)
        #expect(RootView.Tab(sidebar: .route(.debts)) == .wealth)
        #expect(RootView.Tab(sidebar: .account(4100)) == .wealth)
        #expect(RootView.Tab(sidebar: .route(.insights)) == .insights)
        #expect(RootView.Tab(sidebar: .settings) == .home)
    }

    @Test func planPagesBecomeTheSegment() {
        #expect(PlanSegment(sidebar: .route(.budget)) == .budget)
        #expect(PlanSegment(sidebar: .route(.bills)) == .bills)
        #expect(PlanSegment(sidebar: .route(.goals)) == .goals)
        #expect(PlanSegment(sidebar: .route(.home)) == nil)
        #expect(PlanSegment(sidebar: .settings) == nil)
    }

    @Test func pushedPagesMoveWithTheTab() {
        var place = ShellPlace()
        place.tab = .activity
        place.tabPaths[.activity] = NavigationPath([AppRoute.review])
        place.toRegular()
        #expect(place.sidebar == .route(.activity))
        #expect(place.detailPath == NavigationPath([AppRoute.review]))
        place.detailPath.append(AppRoute.transaction(291947))
        place.toCompact()
        #expect(place.tab == .activity)
        #expect(place.tabPaths[.activity] == NavigationPath([AppRoute.review, AppRoute.transaction(291947)]))
    }

    @Test func aPlanPageKeepsItsSegment() {
        var place = ShellPlace()
        place.sidebar = .route(.goals)
        place.detailPath = NavigationPath([AppRoute.goal(713)])
        place.toCompact()
        #expect(place.tab == .plan)
        #expect(place.segment == .goals)
        #expect(place.tabPaths[.plan] == NavigationPath([AppRoute.goal(713)]))
        place.toRegular()
        #expect(place.sidebar == .route(.goals))
        #expect(place.detailPath == NavigationPath([AppRoute.goal(713)]))
    }

    @Test func settingsReopensAsTheSheetOnCompact() {
        var place = ShellPlace()
        place.tabPaths[.home] = NavigationPath([AppRoute.netWorth])
        place.sidebar = .settings
        place.toCompact()
        #expect(place.tab == .home)
        #expect(place.showsSettings)
        #expect(place.tabPaths[.home] == NavigationPath([AppRoute.netWorth]), "Home keeps its own pages under the sheet")
        place.toRegular()
        #expect(place.sidebar == .settings)
        #expect(!place.showsSettings)
        #expect(place.detailPath.isEmpty)
    }

    @Test func investmentsAndDebtsOpenOnTheWealthTab() {
        var place = ShellPlace()
        place.sidebar = .route(.investments)
        place.detailPath = NavigationPath([AppRoute.holding("AAPL")])
        place.toCompact()
        #expect(place.tab == .wealth)
        #expect(samePages(place.tabPaths[.wealth], NavigationPath([AppRoute.investments, AppRoute.holding("AAPL")])))

        place.sidebar = .route(.debts)
        place.detailPath = NavigationPath()
        place.toCompact()
        #expect(place.tabPaths[.wealth] == NavigationPath([AppRoute.debts]))
    }

    @Test func aWealthTabPathOpensInvestmentsOrDebtsInTheSidebar() {
        var place = ShellPlace()
        place.tab = .wealth
        place.tabPaths[.wealth] = NavigationPath([AppRoute.debts, AppRoute.loan(267)])
        place.toRegular()
        #expect(place.sidebar == .route(.debts))
        #expect(samePages(place.detailPath, NavigationPath([AppRoute.loan(267)])))

        place.tabPaths[.wealth] = NavigationPath([AppRoute.investments])
        place.toRegular()
        #expect(place.sidebar == .route(.investments))
        #expect(place.detailPath.isEmpty)

        // An account stays on Accounts with its pages.
        place.tabPaths[.wealth] = NavigationPath([AppRoute.account(4100)])
        place.toRegular()
        #expect(place.sidebar == .route(.accounts))
        #expect(place.detailPath == NavigationPath([AppRoute.account(4100)]))
    }

    @Test func movingToRegularEmptiesTheTabPath() {
        var place = ShellPlace()
        place.tab = .activity
        place.tabPaths[.activity] = NavigationPath([AppRoute.review])
        place.toRegular()
        #expect(place.tabPaths[.activity] == nil, "pages popped in the sidebar don't come back on a later compact visit")
    }

    @Test func pagesThatCantBeEncodedFallBackToTheRoute() {
        struct Plain: Hashable {}
        var place = ShellPlace()
        place.sidebar = .route(.investments)
        place.detailPath = NavigationPath([Plain()])
        place.toCompact()
        #expect(place.tabPaths[.wealth] == NavigationPath([AppRoute.investments]))
    }

    @Test func searchOpensActivityWithoutTheOldPagesButKeepsReview() {
        var place = ShellPlace()
        place.sidebar = .route(.accounts)
        place.detailPath = NavigationPath([AppRoute.account(4100), AppRoute.transaction(291947)])
        place.showSearch()
        #expect(place.sidebar == .route(.activity))
        #expect(place.detailPath.isEmpty)

        // The Mac's Reconcile page filters by the same search, so it stays.
        place.detailPath = NavigationPath([AppRoute.review])
        place.showSearch()
        #expect(place.detailPath == NavigationPath([AppRoute.review]))
        place.detailPath.append(AppRoute.transaction(291947))
        place.showSearch()
        #expect(place.detailPath.isEmpty, "only a Review page on top stays")
    }

    /// Paths rebuilt from their encoded pages don't compare equal to paths built from values, so compare the pages.
    @Test func anOpenEditorMovesToTheHostThatStaysOnScreen() {
        // Regular: the Settings sheet becomes a sidebar page, so its editor moves to the root.
        var root: ShellEditor?
        var settings: ShellEditor? = .importStatement
        ShellEditor.handOff(root: &root, settings: &settings, toCompact: false, showsSettings: false)
        #expect(root?.id == "importStatement" && settings == nil)

        // Compact with Settings reopening as the sheet: the root's editor moves into that sheet.
        ShellEditor.handOff(root: &root, settings: &settings, toCompact: true, showsSettings: true)
        #expect(root == nil && settings?.id == "importStatement")

        // Compact without Settings: the root keeps its editor.
        root = .addBill
        settings = nil
        ShellEditor.handOff(root: &root, settings: &settings, toCompact: true, showsSettings: false)
        #expect(root?.id == "addBill" && settings == nil)
    }

    /// Shell actions in the environment compare by their host, so a host's new action doesn't redraw the screens that
    /// read it. The bare closures they replace counted as changed on every update, and the Mac spun at 100% CPU with an
    /// account pushed over Accounts. Another host's action does count as a change: the Settings sheet presents its own.
    @MainActor @Test func shellActionsCompareByHostAndStillRun() {
        var opened: [String] = []
        var settingsShown = 0
        let first = ShellAction<ShellEditor>(host: "root") { opened.append($0.id) }
        #expect(first == ShellAction<ShellEditor>(host: "root") { _ in })
        #expect(first != ShellAction<ShellEditor>(host: "settings") { opened.append($0.id) })
        first(.addAccount)
        #expect(opened == ["addAccount"])

        let showSettings = ShellAction<Void>(host: "root") { settingsShown += 1 }
        #expect(showSettings == ShellAction<Void>(host: "root") {})
        showSettings()
        #expect(settingsShown == 1)
    }

    private func samePages(_ path: NavigationPath?, _ expected: NavigationPath) -> Bool {
        func json(_ path: NavigationPath?) -> Data? { path?.codable.flatMap { try? JSONEncoder().encode($0) } }
        return json(path) != nil && json(path) == json(expected)
    }
}
