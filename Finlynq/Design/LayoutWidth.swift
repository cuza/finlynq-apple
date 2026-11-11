import SwiftUI

/// The room a screen has, from the width of the column it sits in. Screens pick their layout from this, not from
/// `horizontalSizeClass`: an iPad detail column is `.regular` even in portrait with the sidebar open, where it is
/// about 540pt wide, so a layout chosen by size class gets the landscape design in two thirds of its room.
/// Larger Dynamic Type needs more room for the same layout, so the class steps down sooner as text grows.
enum LayoutWidth: Comparable {
    /// iPhone, and any column too narrow for more than the iPhone layout.
    case compact
    /// iPad portrait with the sidebar open (540pt on an iPad Air, 554pt on an iPad Pro 11-inch).
    case medium
    /// iPad landscape with the sidebar open (900pt on an iPad Air), or a full-width iPad in portrait.
    case wide

    /// The narrowest column for each class at the default text size (large). Larger text raises both.
    static let mediumMinimum: CGFloat = 500
    static let wideMinimum: CGFloat = 820

    /// Narrower than this is not a real column: the first layout pass reports about 20pt.
    static let measuredMinimum: CGFloat = 100

    /// Text smaller than the default doesn't promote the class: a phone column at xSmall is still a phone column.
    init(width: CGFloat, typeSize: DynamicTypeSize) {
        let room = width / max(1, Self.textScale(typeSize))
        self = room >= Self.wideMinimum ? .wide : room >= Self.mediumMinimum ? .medium : .compact
    }

    /// The class from a measured width, or from the size class until there is one: regular (and the Mac, which has
    /// none) is wide, compact is compact.
    init(measured width: CGFloat?, typeSize: DynamicTypeSize, sizeClass: UserInterfaceSizeClass?) {
        if let width, width >= Self.measuredMinimum {
            self.init(width: width, typeSize: typeSize)
        } else {
            self = sizeClass == .compact ? .compact : .wide
        }
    }

    /// Body text size at `size` over its size at the default (17pt), from Apple's Dynamic Type size table.
    static func textScale(_ size: DynamicTypeSize) -> CGFloat { (bodySizes[size] ?? 17) / 17 }

    private static let bodySizes: [DynamicTypeSize: CGFloat] = [
        .xSmall: 14, .small: 15, .medium: 16, .large: 17, .xLarge: 19, .xxLarge: 21, .xxxLarge: 23,
        .accessibility1: 28, .accessibility2: 33, .accessibility3: 40, .accessibility4: 47, .accessibility5: 53
    ]
}

extension LayoutWidth {
    /// Whether a Mac design fits: a `.wide` column at least `needs` points wide (`MacDesignWidth`). The Mac designs
    /// are drawn for a 1440pt window, a 1220pt column beside the sidebar, and their tables and inspectors need more than
    /// the 820pt that starts `.wide`. A narrower wide column gets one of the iPad layouts. A column not measured yet
    /// counts as wide enough, as a `.wide` seed on the Mac is. `column` is `layoutColumn`, already scaled for text size.
    static func fitsMacDesign(_ width: LayoutWidth, column: CGFloat?, needs: CGFloat) -> Bool {
        width == .wide && (column ?? .infinity) >= needs
    }
}

/// The narrowest column, at the default text size, where each Mac design fits. Measured with the fixtures (INR and
/// USD amounts) by narrowing the window until the design clipped, wrapped mid-word or truncated an amount.
enum MacDesignWidth {
    /// MacHome: the four-up KPI row and Recent activity's Payee column.
    static let home: CGFloat = 1040
    /// MacInvestments: the KPI values beside the 280pt holding inspector.
    static let investments: CGFloat = 1150
    /// Investments' iPad landscape layout: four returns in one row, as on iPad landscape's 900pt column.
    static let investmentsReturns: CGFloat = 900
    /// MacActivity: the table's Amount column beside the 320pt inspector.
    static let activity: CGFloat = 1100
    /// MacPlan: the 205 + 100 + 100 + 100 + 170 + 110 category table beside the 320pt inspector.
    static let budget: CGFloat = 1200
    /// MacStatement: the month table's KPI labels on one line.
    static let statement: CGFloat = 1100
    /// MacInsights: the Category column and the month labels.
    static let insights: CGFloat = 960
    /// MacLoan: the stats row, the What-if row and the 120/120/110/140 schedule columns.
    static let loan: CGFloat = 900
    /// Review side by side: the bank's descriptions and the Payee column in both panes.
    static let review: CGFloat = 1160
    /// Review's account and date popups fit in the toolbar, and the date column is 64pt, not 48pt.
    static let reviewToolbar: CGFloat = 640
}

extension EnvironmentValues {
    /// The room the current screen has. The shell sets it on each column that shows screens (`measuresLayoutWidth`).
    @Entry var layoutWidth: LayoutWidth = .compact
    /// The measured width behind `layoutWidth` on the Mac, divided by the text scale as `layoutWidth` is, so it
    /// compares with `MacDesignWidth` at any text size. Nil until there is one. iOS leaves it nil.
    @Entry var layoutColumn: CGFloat?
}

extension View {
    /// Measures the width this view is offered and sets `layoutWidth` for everything inside it, sheets included.
    func measuresLayoutWidth() -> some View { modifier(LayoutWidthReader()) }
}

struct LayoutWidthReader: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var width: CGFloat?

    func body(content: Content) -> some View {
        content
            // The frame takes exactly the offered width, so content wider than its column can't report its own width
            // and keep a layout that needs that width.
            .frame(minWidth: 0, maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .environment(\.layoutWidth, LayoutWidth(measured: width, typeSize: typeSize, sizeClass: sizeClass))
            #if os(macOS)
            // Only the Mac designs need the width itself. Whole points, so a fraction of a point doesn't redraw every
            // screen that reads it.
            .environment(\.layoutColumn, Self.column(width, typeSize: typeSize))
            #endif
    }

    /// `layoutColumn` for a measured width: nil until it is a real column, else whole points at the default text size.
    static func column(_ width: CGFloat?, typeSize: DynamicTypeSize) -> CGFloat? {
        guard let width, width >= LayoutWidth.measuredMinimum else { return nil }
        return (width / max(1, LayoutWidth.textScale(typeSize))).rounded()
    }
}
