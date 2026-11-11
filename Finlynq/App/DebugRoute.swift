#if DEBUG
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// DEBUG-only launch options that `scripts/screens.sh` uses to screenshot one screen. Release builds compile none of this.
///
/// - `FINLYNQ_ROUTE`: the screen to open.
///   - Tab and sidebar roots: home, activity, budget, bills, goals, accounts, investments, debts, insights.
///     calendar is Activity with its calendar mode on.
///   - Pushed screens: review (on Activity), statement, netWorth, tax (on Insights), transaction:<id>,
///     loan:<id>, account:<id>, goal:<id>, category:<id>, holding:<symbol>, applepay (the Apple Pay setup screen),
///     categories (Settings > Categories), categories:<id> (that list with the category's editor open) and
///     categories-refused:<id> (the editor showing a refused delete). On the Mac, settings-categories[:<id>] also opens
///     the Settings window on its Categories tab.
///   - Sheets: add, add-invest, import (the statement import sheet, on Activity). settings opens the Settings sheet
///     on iPhone and the Settings sidebar item on iPad and Mac.
///   - Whole-window screens: signin (the sign-in form, even when signed in) and setup (first-run setup on its
///     Accounts step).
///   - Unknown values log a line and open Home.
///
///   Once the screen is up (after any push or sheet) the app writes `FINLYNQ_READY <route>` to stderr.
/// - `FINLYNQ_APPEARANCE`: `light` or `dark` forces the color scheme.
/// - `FINLYNQ_WINDOW` (Mac): a window size such as `1440x900`.
struct DebugRoute {
    enum Sheet: Equatable { case add(AddModel.Kind), settings, importStatement }

    let name: String
    var tab = RootView.Tab.home
    var sidebar = RootView.SidebarItem.route(.home)
    var pushed: AppRoute?
    var sheet: Sheet?
    /// The category whose editor opens over the categories list: `categories:<id>`, `categories-refused:<id>`
    /// (with the server's delete refusal shown) or, in the Mac Settings window, `settings-categories:<id>`.
    var editCategory: Int? { name.contains("categories") ? name.split(separator: ":").last.flatMap { Int($0) } : nil }
    var showsRefusal: Bool { name.hasPrefix("categories-refused:") }
    /// Sign-in and setup replace the whole window, so FinlynqApp draws them instead of RootView.
    var isStandalone: Bool { name == "signin" || name == "setup" }
    /// On iPhone, Investments and Debts are pushed from the Wealth tab; iPad and Mac have sidebar items for them.
    var phonePush: AppRoute? { ["investments": AppRoute.investments, "debts": .debts][name] }

    private static let env = ProcessInfo.processInfo.environment

    /// The route from `FINLYNQ_ROUTE`, or nil when it is unset.
    static let current: DebugRoute? = env["FINLYNQ_ROUTE"].map { DebugRoute($0) }

    static var colorScheme: ColorScheme? {
        switch env["FINLYNQ_APPEARANCE"] {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    private static var isReady = false

    /// Tells `scripts/screens.sh` that the route's screen is on screen. Writes once per launch.
    static func markReady() {
        guard let current, !isReady else { return }
        isReady = true
        FileHandle.standardError.write(Data("FINLYNQ_READY \(current.name)\n".utf8))
    }

    init(_ value: String) {
        name = value
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        let key = parts.first ?? ""
        let arg = parts.count == 2 ? parts[1] : nil
        let roots: [String: (RootView.Tab, AppRoute)] = [
            "home": (.home, .home), "activity": (.activity, .activity), "calendar": (.activity, .activity),
            "budget": (.plan, .budget), "bills": (.plan, .bills), "goals": (.plan, .goals),
            "accounts": (.wealth, .accounts), "investments": (.wealth, .investments), "debts": (.wealth, .debts),
            "insights": (.insights, .insights)
        ]
        // Pushed screens and the root they are pushed from.
        let pushes: [String: (String, AppRoute)] = [
            "review": ("activity", .review),
            "statement": ("insights", .statement), "netWorth": ("insights", .netWorth), "tax": ("insights", .tax),
            "applepay": ("home", .applePay), "categories": ("home", .categories), "settings-categories": ("home", .categories)
        ]
        let details: [String: (String, (Int) -> AppRoute)] = [
            "transaction": ("activity", AppRoute.transaction), "loan": ("debts", AppRoute.loan),
            "account": ("accounts", AppRoute.account), "goal": ("goals", AppRoute.goal), "category": ("budget", AppRoute.category),
            "categories": ("home", { _ in .categories }), "categories-refused": ("home", { _ in .categories }),
            "settings-categories": ("home", { _ in .categories })
        ]
        var root = "home"
        if roots[key] != nil, arg == nil {
            root = key
        } else if let push = pushes[key], arg == nil {
            root = push.0
            pushed = push.1
        } else if let detail = details[key], let id = arg.flatMap({ Int($0) }) {
            root = detail.0
            pushed = detail.1(id)
        } else if key == "holding", let arg, !arg.isEmpty {
            root = "investments"
            pushed = .holding(arg)
        } else if value == "add" || value == "add-invest" {
            sheet = .add(value == "add" ? .expense : .invest)
        } else if value == "import" {
            root = "activity"
            sheet = .importStatement
        } else if value == "settings" {
            sheet = .settings
        } else if isStandalone {
            root = "home"
        } else {
            FileHandle.standardError.write(Data("FINLYNQ_ROUTE \(value) is unknown, opening Home\n".utf8))
        }
        if let entry = roots[root] {
            tab = entry.0
            sidebar = sheet == .settings ? .settings : .route(entry.1)
        }
        // Apple Pay and Categories open from Settings, but a debug push lands on Home's stack: the iPad Settings
        // detail drops a debug push, which left the applepay route on Settings.
    }
}

extension View {
    /// Pushes the debug route's screen onto a navigation stack and reports when the route is ready.
    /// `tab` is the stack's iPhone tab, or nil for the iPad and Mac detail stack. `path` is the stack's bound path: the
    /// push goes through it, as a tap on a row does.
    func debugStack(tab: RootView.Tab?, path: Binding<NavigationPath>) -> some View {
        modifier(DebugStack(tab: tab, path: path))
    }

    /// Presents the debug route's add sheet.
    func debugSheet() -> some View { modifier(DebugSheet()) }

    /// Applies `FINLYNQ_APPEARANCE` and, on the Mac, `FINLYNQ_WINDOW`.
    func debugWindow() -> some View {
        preferredColorScheme(DebugRoute.colorScheme)
        #if os(macOS)
            .modifier(DebugOpenSettings())
            .task {
                let size = ProcessInfo.processInfo.environment["FINLYNQ_WINDOW"]?.split(separator: "x").compactMap { Double($0) }
                guard let size, size.count == 2 else { return }
                // AppKit shrinks a window to fit above the Dock. Turn that off so the window gets the exact size.
                if let method = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.constrainFrameRect(_:to:))) {
                    let keep: @convention(block) (NSWindow, NSRect, NSScreen?) -> NSRect = { _, rect, _ in rect }
                    method_setImplementation(method, imp_implementationWithBlock(keep))
                }
                // SwiftUI may still place or restore the window after launch, so hold the frame for a few seconds.
                let frame = NSRect(x: 0, y: 0, width: size[0], height: size[1])
                for _ in 0..<20 {
                    if let window = NSApp.windows.first(where: { $0.isVisible }), window.frame != frame {
                        window.setFrame(frame, display: true)
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        #endif
    }
}

#if os(macOS)
/// Opens the Settings window for the `settings-…` routes.
private struct DebugOpenSettings: ViewModifier {
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.task { if DebugRoute.current?.name.hasPrefix("settings-") == true { openSettings() } }
    }
}
#endif

private struct DebugStack: ViewModifier {
    let tab: RootView.Tab?
    @Binding var path: NavigationPath
    @State private var pushed = false

    func body(content: Content) -> some View {
        if let route = DebugRoute.current, tab == nil || tab == route.tab {
            let push = route.pushed ?? (tab == nil ? nil : route.phonePush)
            // On iPad and Mac the settings route is a sidebar item, so the detail stack is the screen.
            let isScreen = route.sheet == nil || (tab == nil && route.sheet == .settings)
            content
                .onAppear {
                    // Pushing during the first layout pass loops in NavigationState updates and leaves a blank
                    // window, so push once the root is on screen. Once: popping back shows the root.
                    // The root screen's own destination shows the page, and `RouteDestination` reports ready.
                    if let push, !pushed {
                        pushed = true
                        DispatchQueue.main.async { path.append(push) }
                    } else if push == nil, isScreen {
                        DebugRoute.markReady()
                    }
                }
        } else {
            content
        }
    }
}

private struct DebugSheet: ViewModifier {
    @State private var kind: AddModel.Kind?
    @State private var importing = false

    func body(content: Content) -> some View {
        content
            .sheet(item: $kind) { AddSheet(kind: $0).onAppear { DebugRoute.markReady() } }
            .sheet(isPresented: $importing) {
                // Fixture mode answers the preview with Fixtures/import-preview.json, whatever the file holds.
                ImportSheet(sample: UploadFile(filename: "chequing-nov.csv", data: Data())).onAppear { DebugRoute.markReady() }
            }
            .onAppear {
                if case .add(let kind) = DebugRoute.current?.sheet { self.kind = kind }
                importing = DebugRoute.current?.sheet == .importStatement
            }
    }
}
#endif
