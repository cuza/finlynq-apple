import SwiftUI

/// Where the app is in each shell: the iPhone tab with its pushed pages and Plan segment, and the sidebar page with
/// the detail column's pushed pages. When the width class changes (iPhone Duo opening or closing, iPad Split View)
/// the shell swaps tabs for the sidebar, and these hand the place across so the same page stays on screen.
struct ShellPlace {
    var tab = RootView.Tab.home
    var tabPaths: [RootView.Tab: NavigationPath] = [:]
    /// Plan's page on iPhone, under its segmented control.
    var segment = PlanSegment.budget
    var sidebar = RootView.SidebarItem.route(.home)
    var detailPath = NavigationPath()
    /// The Settings sheet, open over Home on iPhone. On iPad Settings is a sidebar page.
    var showsSettings = false

    /// Compact to regular: the tab's page becomes the sidebar page, with its pushed pages.
    mutating func toRegular() {
        if showsSettings {
            sidebar = .settings
            detailPath = NavigationPath()
        } else {
            sidebar = RootView.SidebarItem(tab: tab, segment: segment)
            detailPath = tabPaths[tab] ?? NavigationPath()
            // Investments and Debts are pages pushed on iPhone's Wealth tab, and sidebar rows on iPad.
            if tab == .wealth, let (first, rest) = detailPath.splittingFirstRoute(), first == .investments || first == .debts {
                sidebar = .route(first)
                detailPath = rest
            }
            // The path lives in the detail column now; a later compact visit gets it back from there.
            tabPaths[tab] = nil
        }
        showsSettings = false
    }

    /// Regular to compact: the sidebar page opens in the tab that holds it, with its pushed pages. Settings reopens
    /// as the sheet over Home, which keeps its own pages.
    mutating func toCompact() {
        tab = RootView.Tab(sidebar: sidebar)
        if let segment = PlanSegment(sidebar: sidebar) { self.segment = segment }
        showsSettings = sidebar == .settings
        guard !showsSettings else { return }
        if case .route(let route) = sidebar, route == .investments || route == .debts {
            tabPaths[tab] = detailPath.prepending(route)
        } else {
            tabPaths[tab] = detailPath
        }
    }

    /// Typing in the sidebar or toolbar search opens Activity with the results on top. Review stays, because the
    /// Mac's Reconcile page filters by the same search.
    mutating func showSearch() {
        sidebar = .route(.activity)
        if detailPath.lastRoute != .review { detailPath = NavigationPath() }
    }
}

extension NavigationPath {
    /// The path with `route` under its pages. When a page can't be encoded (a pushed Transaction), `route` alone.
    func prepending(_ route: AppRoute) -> NavigationPath {
        guard !isEmpty, let pages = encoded, let under = NavigationPath([route]).encoded,
              let path = NavigationPath(encoded: pages + under) else { return NavigationPath([route]) }
        return path
    }

    /// The first page when it is an `AppRoute`, and the path above it. Nil for an empty path or one that can't be
    /// encoded.
    func splittingFirstRoute() -> (AppRoute, NavigationPath)? {
        guard let pages = encoded, pages.count >= 2, let route = Self.route(type: pages[pages.count - 2], value: pages[pages.count - 1]),
              let rest = NavigationPath(encoded: Array(pages.dropLast(2))) else { return nil }
        return (route, rest)
    }

    /// The top page when it is an `AppRoute`. Nil for an empty path, another page type, or one that can't be encoded.
    var lastRoute: AppRoute? {
        guard let pages = encoded, pages.count >= 2 else { return nil }
        return Self.route(type: pages[0], value: pages[1])
    }

    private static func route(type: String, value: String) -> AppRoute? {
        guard type == NavigationPath([AppRoute.home]).encoded?.first else { return nil }
        return try? JSONDecoder().decode(AppRoute.self, from: Data(value.utf8))
    }

    /// `CodableRepresentation` as strings: a type name and a JSON value per page, last page first. A path decoded from
    /// it pushes the same pages, though it doesn't compare equal to one built from the values.
    /// ponytail: relies on CodableRepresentation encoding as that flat string array, which Apple doesn't document. If
    /// the layout changes, this returns nil and the callers fall back: `prepending` keeps the route alone,
    /// `splittingFirstRoute` leaves the path on Accounts, and `lastRoute` reads nil (search clears the path). The
    /// ShellTests round trips fail first. Upgrade path: keep the shell's paths as `[AppRoute]` arrays once every
    /// pushed page is an `AppRoute`.
    private var encoded: [String]? {
        guard let codable, let data = try? JSONEncoder().encode(codable) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    private init?(encoded: [String]) {
        if encoded.isEmpty {
            self.init()
            return
        }
        guard let data = try? JSONEncoder().encode(encoded),
              let representation = try? JSONDecoder().decode(CodableRepresentation.self, from: data) else { return nil }
        self.init(representation)
    }
}

extension PlanSegment {
    /// The segment for a Plan page in the sidebar, or nil for any other page.
    init?(sidebar: RootView.SidebarItem) {
        switch sidebar {
        case .route(.budget): self = .budget
        case .route(.bills): self = .bills
        case .route(.goals): self = .goals
        default: return nil
        }
    }
}
