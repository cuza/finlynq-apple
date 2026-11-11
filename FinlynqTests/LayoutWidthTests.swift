import SwiftUI
#if os(macOS)
import AppKit
#endif
import Testing
@testable import Finlynq

struct LayoutWidthTests {
    @Test func defaultTextPicksTheClassFromTheColumnWidth() {
        #expect(LayoutWidth(width: 402, typeSize: .large) == .compact)  // iPhone 17
        #expect(LayoutWidth(width: 440, typeSize: .large) == .compact)  // iPhone 17 Pro Max
        #expect(LayoutWidth(width: 540, typeSize: .large) == .medium)  // iPad Air portrait, sidebar open
        #expect(LayoutWidth(width: 820, typeSize: .large) == .wide)  // iPad Air portrait, sidebar hidden
        #expect(LayoutWidth(width: 900, typeSize: .large) == .wide)  // iPad Air landscape, sidebar open
    }

    @Test func boundariesBelongToTheWiderClass() {
        #expect(LayoutWidth(width: 499.9, typeSize: .large) == .compact)
        #expect(LayoutWidth(width: 500, typeSize: .large) == .medium)
        #expect(LayoutWidth(width: 819.9, typeSize: .large) == .medium)
        #expect(LayoutWidth(width: 820, typeSize: .large) == .wide)
    }

    @Test func largerTextNeedsMoreRoom() {
        // The user's iPad Air portrait column with the sidebar open, 540pt.
        #expect(LayoutWidth(width: 540, typeSize: .xLarge) == .compact)
        // iPad Air landscape with the sidebar open, 900pt.
        #expect(LayoutWidth(width: 900, typeSize: .large) == .wide)
        #expect(LayoutWidth(width: 900, typeSize: .xLarge) == .medium)
        #expect(LayoutWidth(width: 900, typeSize: .xxxLarge) == .medium)
        #expect(LayoutWidth(width: 900, typeSize: .accessibility3) == .compact)
    }

    @Test func smallerTextNeverPromotesTheClass() {
        // The scale is held at 1 below the default size, so a phone column stays compact at xSmall.
        #expect(LayoutWidth(width: 470, typeSize: .xSmall) == .compact)
        #expect(LayoutWidth(width: 499, typeSize: .small) == .compact)
        #expect(LayoutWidth(width: 819, typeSize: .medium) == .medium)
    }

    @Test func anUnmeasuredColumnTakesItsClassFromTheSizeClass() {
        // Before the first measurement, and for the 20pt the first layout pass reports.
        #expect(LayoutWidth(measured: nil, typeSize: .large, sizeClass: .regular) == .wide)
        #expect(LayoutWidth(measured: nil, typeSize: .large, sizeClass: .compact) == .compact)
        #expect(LayoutWidth(measured: 20, typeSize: .large, sizeClass: .regular) == .wide)
        #expect(LayoutWidth(measured: 99, typeSize: .large, sizeClass: .compact) == .compact)
        // The Mac has no size class.
        #expect(LayoutWidth(measured: nil, typeSize: .large, sizeClass: nil) == .wide)
        // A real width wins over the size class.
        #expect(LayoutWidth(measured: 540, typeSize: .large, sizeClass: .regular) == .medium)
        #expect(LayoutWidth(measured: 100, typeSize: .large, sizeClass: .regular) == .compact)
    }

    @Test func textScaleGrowsWithEverySize() {
        let scales = DynamicTypeSize.allCases.map(LayoutWidth.textScale)
        #expect(scales == scales.sorted())
        #expect(Set(scales).count == scales.count)
        #expect(LayoutWidth.textScale(.large) == 1)
    }

    @Test func theAddSheetShowsItsNumberPadOnlyInAPhoneWidthSheet() {
        #expect(AddSheet.usesPad(width: 402, sizeClass: .compact))  // iPhone 17
        #expect(AddSheet.usesPad(width: 402, sizeClass: .regular))  // iPhone Duo closed, beside its rail
        #expect(!AddSheet.usesPad(width: 540, sizeClass: .compact))  // an iPad form sheet reports compact itself
        #expect(AddSheet.usesPad(width: nil, sizeClass: .compact))
        #expect(!AddSheet.usesPad(width: nil, sizeClass: .regular))
    }

    @Test func aMacDesignNeedsAWideColumnWithItsRoom() {
        // The 1440pt design window leaves 1220pt beside the sidebar.
        #expect(LayoutWidth.fitsMacDesign(.wide, column: 1220, needs: 1100))
        #expect(LayoutWidth.fitsMacDesign(.wide, column: 1100, needs: 1100))
        // A 1200pt window: wide, but too narrow for a table beside an inspector.
        #expect(!LayoutWidth.fitsMacDesign(.wide, column: 980, needs: 1100))
        // Never on a narrower class, however little the design needs.
        #expect(!LayoutWidth.fitsMacDesign(.medium, column: 780, needs: 500))
        #expect(!LayoutWidth.fitsMacDesign(.compact, column: 400, needs: 0))
        // Before the first measurement a wide seed counts as wide enough.
        #expect(LayoutWidth.fitsMacDesign(.wide, column: nil, needs: 1100))
    }

    @Test func homeTakesTheMacDesignOnlyWhenItFits() {
        #expect(HomeLayout(.compact, column: 400, macNeeds: 1040) == .phone)
        #expect(HomeLayout(.medium, column: 780, macNeeds: 1040) == .pad)
        #expect(HomeLayout(.wide, column: 980, macNeeds: 1040) == .pad)
        #if os(macOS)
        #expect(HomeLayout(.wide, column: 1220, macNeeds: 1040) == .mac)
        #else
        #expect(HomeLayout(.wide, column: 1220, macNeeds: 1040) == .pad)
        #endif
    }

    #if os(macOS)
    @Test func theSmallestMacWindowStillHasAMediumColumn() {
        let column = RootView.macMinimumWidth - RootView.macSidebarWidth
        #expect(column >= LayoutWidth.mediumMinimum + 12)
        #expect(LayoutWidth(width: column, typeSize: .large) == .medium)
        // The Mac's 1440pt design window leaves a wide column beside the sidebar.
        #expect(LayoutWidth(width: 1440 - RootView.macSidebarWidth, typeSize: .large) == .wide)
    }

    @Test func theColumnIsPublishedAtTheDefaultTextSize() {
        #expect(LayoutWidthReader.column(nil, typeSize: .large) == nil)
        #expect(LayoutWidthReader.column(20, typeSize: .large) == nil)
        #expect(LayoutWidthReader.column(1220.4, typeSize: .large) == 1220)
        // xLarge body text is 19pt over 17pt, so a 1220pt column has the room of 1092pt at the default size.
        #expect(LayoutWidthReader.column(1220, typeSize: .xLarge) == 1092)
        #expect(LayoutWidthReader.column(1220, typeSize: .xSmall) == 1220)
    }

    /// Content wider than its column doesn't count: the reader publishes the width it is offered.
    @MainActor @Test func theReaderMeasuresTheOfferedWidthNotTheContent() async {
        let probe = Probe()
        let window = await host(width: 500) {
            ZStack {
                Color.clear.frame(width: 1200)
                probe.view
            }
            .measuresLayoutWidth()
        }
        #expect(probe.width == .medium)
        #expect(probe.column == 500)
        window.close()
    }

    /// The smallest window, with the real sidebar, still gives the detail column `.medium`.
    @MainActor @Test func theSmallestWindowsDetailColumnIsMedium() async {
        let probe = Probe()
        let window = await host(width: RootView.macMinimumWidth) {
            NavigationSplitView {
                List { Text("Home") }.navigationSplitViewColumnWidth(RootView.macSidebarWidth)
            } detail: {
                NavigationStack { probe.view }.measuresLayoutWidth()
            }
        }
        #expect(probe.width == .medium)
        #expect((probe.column ?? 0) >= LayoutWidth.mediumMinimum)
        window.close()
    }

    /// Records the layout values a view inside the reader sees.
    @MainActor private final class Probe {
        var width: LayoutWidth?
        var column: CGFloat?

        var view: some View { ProbeView(probe: self) }
    }

    private struct ProbeView: View {
        let probe: Probe
        @Environment(\.layoutWidth) private var width
        @Environment(\.layoutColumn) private var column

        var body: some View {
            Color.clear.onChange(of: "\(width)|\(column ?? 0)", initial: true) {
                probe.width = width
                probe.column = column
            }
        }
    }

    /// Lays out `content` in a window `width` points wide and lets SwiftUI settle.
    @MainActor private func host(width: CGFloat, @ViewBuilder _ content: () -> some View) async -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 400), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content())
        window.setContentSize(NSSize(width: width, height: 400))
        for _ in 0..<10 {
            window.contentView?.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(50))
        }
        return window
    }
    #endif
}
