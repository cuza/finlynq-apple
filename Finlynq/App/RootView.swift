import SwiftUI

/// iPhone (compact width): the system tab bar with five tabs; each tab's root screen has a + toolbar button.
/// iPad (regular width) and Mac: a system sidebar with the destinations. iPad puts search in the sidebar; the Mac
/// lists accounts with balances in the sidebar and has the search field in the toolbar. Every root screen's toolbar
/// ends with the prominent + button, which opens the add sheet (Command-N).
/// A width class change swaps tabs and sidebar (iPhone Duo opening or closing, iPad Split View). `ShellPlace` carries
/// the page, Plan's segment, the pushed pages and Settings across, and editor sheets open from the shell
/// (`ShellEditor`), so they and their drafts stay open.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @SceneStorage("tab") private var storedTab = Tab.home
    /// The tab a debug route opens. While set, the tab is neither restored from nor saved to scene storage.
    @State private var routeTab: Tab?
    @State private var place = ShellPlace()
    @State private var editor: ShellEditor?
    /// Editor sheets opened from inside the iPhone Settings sheet (Import on Activity after "Show transactions").
    /// The root host can't present while the Settings sheet is up, so that sheet has its own.
    @State private var settingsEditor: ShellEditor?
    /// Activity's search, filters and rows, shared by its tab and its sidebar page.
    @State private var activity = ActivityStore()
    @Environment(Session.self) private var session
    @State private var review = ReviewStatus()
    @State private var showAdd = false
    /// The shell on screen: tabs (true) or sidebar. It follows the size class only after the place is handed over,
    /// so the old shell's stacks are still there to read from.
    @State private var showsTabs: Bool?

    enum Tab: String, CaseIterable {
        case home = "Home", activity = "Activity", plan = "Plan", wealth = "Wealth", insights = "Insights"

        var symbol: String {
            switch self {
            case .home: "house"
            case .activity: "arrow.left.arrow.right"
            case .plan: "calendar.badge.checkmark"
            case .wealth: "building.columns"
            case .insights: "chart.bar"
            }
        }

        /// The tab that holds a sidebar page. iPhone opens Settings from Home.
        init(sidebar: SidebarItem) {
            switch sidebar {
            case .route(.activity): self = .activity
            case .route(.budget), .route(.bills), .route(.goals): self = .plan
            case .route(.accounts), .route(.investments), .route(.debts), .account: self = .wealth
            case .route(.insights): self = .insights
            default: self = .home
            }
        }
    }

    enum SidebarItem: Hashable {
        case route(AppRoute), settings, account(Int)

        /// A tab's page in the sidebar. Plan's is the page its segmented control shows.
        init(tab: Tab, segment: PlanSegment) {
            switch tab {
            case .home: self = .route(.home)
            case .activity: self = .route(.activity)
            case .plan: self = .route(segment == .bills ? .bills : segment == .goals ? .goals : .budget)
            case .wealth: self = .route(.accounts)
            case .insights: self = .route(.insights)
            }
        }
    }

    init() {
        #if DEBUG
        if let route = DebugRoute.current {
            _routeTab = State(initialValue: route.tab)
            var place = ShellPlace()
            place.sidebar = route.sidebar
            place.segment = PlanSegment(sidebar: route.sidebar) ?? .budget
            place.showsSettings = route.sheet == .settings
            _place = State(initialValue: place)
            let activity = ActivityStore()
            activity.showsCalendar = route.name == "calendar"
            _activity = State(initialValue: activity)
        }
        #endif
    }

    private var tab: Binding<Tab> {
        Binding { routeTab ?? storedTab } set: { if routeTab == nil { storedTab = $0 } else { routeTab = $0 } }
    }

    var body: some View {
        layout
            .task(id: session.revision) { await review.load(session.api) }
            .sheet(isPresented: $showAdd) { AddSheet() }
            .modifier(ShellEditorHost(editor: $editor, popPage: popPage))
            .environment(\.showSettings, ShellAction(host: "root") { place.showsSettings = true })
            #if DEBUG
            .debugSheet()
            #endif
            // After the sheets above, so their content inherits these too. `shellSizeClass` is the window's size
            // class: a sheet reports its own (compact for an iPad form sheet), so AddSheet seeds its layout from this.
            .environment(review)
            .environment(activity)
            .environment(\.shellSizeClass, sizeClass)
            #if os(iOS)
            .onChange(of: sizeClass) { _, new in
                var next = place
                next.tab = tab.wrappedValue
                if new == .compact { next.toCompact() } else { next.toRegular() }
                ShellEditor.handOff(root: &editor, settings: &settingsEditor, toCompact: new == .compact,
                                    showsSettings: next.showsSettings)
                place = next
                tab.wrappedValue = next.tab
                showsTabs = new == .compact
            }
            .onAppear { if showsTabs == nil { showsTabs = sizeClass == .compact } }
            #endif
    }

    /// Closes the page on top of the stack on screen.
    private func popPage() {
        #if os(iOS)
        if showsTabs ?? (sizeClass == .compact) {
            if place.tabPaths[tab.wrappedValue]?.isEmpty == false { place.tabPaths[tab.wrappedValue]?.removeLast() }
            return
        }
        #endif
        if !place.detailPath.isEmpty { place.detailPath.removeLast() }
    }

    @ViewBuilder
    private var layout: some View {
        #if os(iOS)
        if showsTabs ?? (sizeClass == .compact) { tabs } else { split }
        #else
        split
        #endif
    }

    #if os(iOS)
    private var tabs: some View {
        TabView(selection: tab) {
            ForEach(Tab.allCases, id: \.self) { item in
                SwiftUI.Tab(item.rawValue, systemImage: item.symbol, value: item) { page(item) }
                    .badge(item == .activity ? review.count : 0)
            }
        }
        .sheet(isPresented: $place.showsSettings) {
            NavigationStack {
                SettingsView().toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { place.showsSettings = false } }
                }
            }
            .modifier(ShellEditorHost(editor: $settingsEditor, popPage: {}))
            #if DEBUG
            .onAppear { DebugRoute.markReady() }
            #endif
        }
    }

    /// A tab's stack. The root screen gets the shell's + button; pushed screens don't.
    private func page(_ tab: Tab) -> some View {
        let path = Binding { place.tabPaths[tab] ?? NavigationPath() } set: { place.tabPaths[tab] = $0 }
        return NavigationStack(path: path) {
            Group {
                switch tab {
                case .home: HomeView()
                case .activity: ActivityView(store: activity)
                case .plan: PlanView(segment: $place.segment)
                case .wealth: WealthView()
                case .insights: InsightsView()
                }
            }
            .modifier(ShellToolbar(add: addButton))
            #if DEBUG
            .debugStack(tab: tab, path: path)
            #endif
        }
        .measuresLayoutWidth()
    }
    #endif

    private var split: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                row("Home", Tab.home.symbol, .route(.home))
                row("Activity", Tab.activity.symbol, .route(.activity), count: review.count)
                Section("Plan") {
                    row("Budget", "chart.bar.doc.horizontal", .route(.budget))
                    row("Bills", "calendar", .route(.bills))
                    row("Goals", "target", .route(.goals))
                }
                Section("Wealth") {
                    row("Accounts", "building.columns", .route(.accounts))
                    row("Investments", "chart.line.uptrend.xyaxis", .route(.investments))
                    row("Debts", "creditcard", .route(.debts))
                }
                row("Insights", Tab.insights.symbol, .route(.insights))
                #if os(macOS)
                SidebarAccounts()
                #else
                // The Mac has a Settings window (Command-comma) instead.
                Section { row("Settings", "gearshape", .settings) }
                #endif
            }
            #if os(macOS)
            .navigationSplitViewColumnWidth(Self.macSidebarWidth)
            #else
            .navigationTitle("Finlynq")
            .searchable(text: $activity.search, placement: .sidebar, prompt: "Search")
            .navigationSplitViewColumnWidth(280)
            #endif
        } detail: {
            NavigationStack(path: $place.detailPath) {
                Group {
                    switch place.sidebar {
                    case .route(.home): HomeView()
                    case .route(.activity): ActivityView(store: activity)
                    case .route(.accounts): WealthView()
                    case .route(.investments): InvestmentsView()
                    case .route(.debts): DebtsView()
                    case .route(.budget): BudgetView()
                    case .route(.bills): BillsView()
                    case .route(.goals): GoalsView()
                    case .route(.insights): InsightsView()
                    case .route(let route): PlaceholderView(title: route.title)
                    case .account(let id): AccountDetailView(id: id)
                    case .settings: SettingsView()
                    }
                }
                #if DEBUG
                .debugStack(tab: nil, path: $place.detailPath)
                #endif
            }
            .measuresLayoutWidth()
            // iPadPSettings has no + on Settings.
            .modifier(ShellToolbar(add: addButton, hidden: place.sidebar == .settings))
        }
        #if os(macOS)
        // The sidebar and a `.medium` column always fit. Screens lay out to the column, so the window doesn't grow
        // to fit them (FinlynqApp's `.contentMinSize`).
        .frame(minWidth: Self.macMinimumWidth, minHeight: 500)
        // Typing here filters Activity, and opens it from any other page.
        .searchable(
            text: $activity.search, placement: .toolbar,
            prompt: place.sidebar == .route(.activity) ? "Payee, note, tag or amount" : "Search"
        )
        #endif
        .onChange(of: activity.search) { if !activity.search.isEmpty { place.showSearch() } }
    }

    #if os(macOS)
    static let macSidebarWidth: CGFloat = 220
    /// The Mac sidebar beside the narrowest `.medium` column, with 12pt to spare for the divider and rounding, so the
    /// smallest window never measures just under `.medium`.
    static let macMinimumWidth = macSidebarWidth + LayoutWidth.mediumMinimum + 12
    #endif

    /// The sidebar's selection. Picking another page starts it without pushed pages.
    private var sidebarSelection: Binding<SidebarItem?> {
        Binding { place.sidebar } set: { item in
            guard let item, item != place.sidebar else { return }
            place.sidebar = item
            place.detailPath = NavigationPath()
        }
    }

    /// The prominent + button: an icon on iPhone and iPad, "+ Add" on the Mac.
    private var addButton: some View {
        Button("Add", systemImage: "plus") { showAdd = true }
            .macTitleAndIcon()
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n")
            .help("Add transaction (Command-N)")
            .accessibilityIdentifier("addButton")
    }

    /// A sidebar row. `count` shows as the row's badge (the Activity review count). The tag is the outermost
    /// modifier, so List selection finds it; a `.badge` after `.tag` hid the Activity row's selection.
    private func row(_ title: String, _ symbol: String, _ item: SidebarItem, count: Int = 0) -> some View {
        Label(title, systemImage: symbol).badge(count).tag(item)
    }
}

/// Adds the shell's + button after the screen's own toolbar items. The items are declared in an overlay, after the
/// screen, so the screen's `.primaryAction` items come first.
private struct ShellToolbar<Add: View>: ViewModifier {
    let add: Add
    var hidden = false

    func body(content: Content) -> some View {
        content.overlay {
            Color.clear.allowsHitTesting(false).accessibilityHidden(true)
                .toolbar { if !hidden { ToolbarItem(placement: .primaryAction) { add } } }
        }
    }
}

/// Maps a route to its screen. Routes whose screens are not built yet show a placeholder.
struct RouteDestination: View {
    let route: AppRoute

    /// A pushed page doesn't inherit the column's `layoutWidth` (screens register their destinations), so each page
    /// measures its own width.
    var body: some View {
        destination.measuresLayoutWidth()
        #if DEBUG
            .onAppear {
                if let current = DebugRoute.current, route == current.pushed || route == current.phonePush { DebugRoute.markReady() }
            }
        #endif
    }

    @ViewBuilder private var destination: some View {
        switch route {
        case .activity: ActivityView()
        case .transaction(let id): TransactionByID(id: id)
        case .calendar: CalendarView()
        case .review: ReviewView()
        case .accounts: WealthView()
        case .investments: InvestmentsView()
        case .debts: DebtsView()
        case .account(let id): AccountDetailView(id: id)
        case .holding(let symbol): HoldingDetailView(symbol: symbol)
        case .loan(let id): LoanView(id: id)
        case .budget: BudgetView()
        case .bills: BillsView()
        case .goals: GoalsView()
        case .insights: InsightsView()
        case .category(let id): CategoryDetailView(categoryId: id)
        case .goal(let id): GoalDetailView(goalId: id)
        case .statement: StatementView()
        case .netWorth: NetWorthView()
        case .tax: TaxView()
        case .applePay: ApplePaySetupView()
        case .categories: CategoriesListView()
        default: PlaceholderView(title: route.title)
        }
    }
}

/// Stand-in for a screen that a feature task replaces.
struct PlaceholderView: View {
    let title: String

    var body: some View {
        EmptyState(title: title, message: "This screen is coming soon.", symbol: "hammer")
            .background(Theme.page)
            .navigationTitle(title)
    }
}

#if os(macOS)
/// Account list with balances, shown in the Mac sidebar.
private struct SidebarAccounts: View {
    @Environment(Session.self) private var session
    @State private var balances: [Dashboard.Balance] = []

    var body: some View {
        Section("Accounts") {
            ForEach(balances.filter { !$0.archived }) { balance in
                HStack {
                    Text(balance.name).lineLimit(1)
                    Spacer()
                    MoneyText(amount: balance.balance, currency: balance.currency, cents: false).foregroundStyle(Theme.secondary)
                }
                .tag(RootView.SidebarItem.account(balance.id))
            }
        }
        .task {
            if let dashboard: Dashboard = try? await session.api.get("/api/dashboard") { balances = dashboard.balances }
        }
    }
}
#endif

extension EnvironmentValues {
    /// The window's size class, for sheets: a sheet reports its own, which is compact for an iPad form sheet.
    @Entry var shellSizeClass: UserInterfaceSizeClass?
}

extension View {
    /// Mac toolbar buttons show their title beside the symbol, as in the Mac designs. iOS shows the symbol alone in
    /// the bar, and the title in the overflow menu and to VoiceOver.
    func macTitleAndIcon() -> some View {
        #if os(macOS)
        labelStyle(.titleAndIcon)
        #else
        self
        #endif
    }
}

extension ToolbarContent {
    /// Drops the glass capsule that macOS 26 and iOS 26 draw behind toolbar items, for controls that draw their own background.
    @ToolbarContentBuilder
    func sharedBackgroundHidden() -> some ToolbarContent {
        if #available(iOS 26, macOS 26, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
