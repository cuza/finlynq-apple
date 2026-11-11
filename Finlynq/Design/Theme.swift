import SwiftUI

/// Design tokens. Light values come from the approved designs. Dark values come from system colors on iOS and
/// fixed greys on the Mac, where the system window and control backgrounds are the same grey and cards would vanish.
/// Accent and semantic hues stay the same in both modes.
enum Theme {
    private static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    #if canImport(UIKit)
    private static func adaptive(light: UInt32, dark: UIColor) -> Color { adaptive(light: UIColor(hex(light)), dark: dark) }
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        // @Sendable: SwiftUI's async render thread resolves these, so the closure must not be MainActor-isolated.
        Color(uiColor: UIColor { @Sendable traits in traits.userInterfaceStyle == .dark ? dark : light })
    }
    private static func platform(_ value: UInt32, alpha: Double = 1) -> UIColor { UIColor(hex(value)).withAlphaComponent(alpha) }
    private static let darkPage = UIColor.systemGroupedBackground
    private static let darkCard = UIColor.secondarySystemGroupedBackground
    private static let darkText = UIColor.label
    private static let darkSecondary = UIColor.secondaryLabel
    #else
    private static func adaptive(light: UInt32, dark: NSColor) -> Color { adaptive(light: NSColor(hex(light)), dark: dark) }
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { @Sendable appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    private static func platform(_ value: UInt32, alpha: Double = 1) -> NSColor { NSColor(hex(value)).withAlphaComponent(alpha) }
    private static let darkPage = platform(0x1B1C1F)
    private static let darkCard = platform(0x2B2D31)
    private static let darkText = NSColor.labelColor
    private static let darkSecondary = NSColor.secondaryLabelColor
    #endif

    /// Light hex is the spec value. Dark text hues are lighter (4.5:1 or better on the dark card);
    /// dark tints are the hue at 18% opacity.
    private static func pair(_ light: UInt32, darkText: UInt32) -> Color { adaptive(light: light, dark: platform(darkText)) }
    private static func tint(_ light: UInt32, hue: UInt32) -> Color { adaptive(light: light, dark: platform(hue, alpha: 0.18)) }

    static let page = adaptive(light: 0xF2F3F5, dark: darkPage)
    static let card = adaptive(light: 0xFFFFFF, dark: darkCard)
    static let text = adaptive(light: 0x111318, dark: darkText)
    static let secondary = adaptive(light: 0x5F6672, dark: darkSecondary)

    /// Card corner radius: 22 on iPhone and iPad, 14 on the Mac.
    #if os(macOS)
    static let cardRadius: CGFloat = 14
    #else
    static let cardRadius: CGFloat = 22
    #endif
    /// Light mode lifts cards with a soft shadow; dark mode outlines them with a hairline.
    static let cardShadow = adaptive(light: platform(0x111318, alpha: 0.05), dark: .clear)
    static let cardBorder = adaptive(light: .clear, dark: platform(0xFFFFFF, alpha: 0.08))
    #if os(macOS)
    /// Mac inspector and table header background.
    static let toolbar = adaptive(light: 0xFAFAFB, dark: platform(0x232427))
    #endif
    /// Outline of small Mac controls.
    static let badge = adaptive(light: 0xD3D6DD, dark: platform(0xFFFFFF, alpha: 0.16))
    /// Unselected tab in the iPhone tab bar.
    static let inactive = adaptive(light: 0x4A505B, dark: darkSecondary)
    /// Fill for search fields and segmented tracks.
    static let fill = adaptive(light: 0xE6E8EC, dark: platform(0xFFFFFF, alpha: 0.1))

    static let accent = hex(0x2F5BEA)
    static let accentTint = tint(0xE8EEFF, hue: 0x2F5BEA)
    static let positive = pair(0x0B6B37, darkText: 0x4BCB85)
    static let positiveTint = tint(0xE3F5EA, hue: 0x1C9A55)
    static let positiveBar = hex(0x1C9A55)
    static let warning = pair(0xB4580A, darkText: 0xF5A55F)
    static let warningTint = tint(0xFFF1E3, hue: 0xF29A4A)
    static let spendBar = hex(0xF29A4A)
    static let negative = pair(0xB42318, darkText: 0xFF7A6E)
    static let negativeTint = tint(0xFDEBEB, hue: 0xD9443A)
    static let overBar = hex(0xD9443A)
    static let invest = pair(0x5B3CC4, darkText: 0xAE97F7)
    static let investTint = tint(0xF1ECFF, hue: 0x9B7BF0)
    /// Segment colors for `CategoryBar`, in order. The last one is the grey "left" segment.
    static let categoryPalette = [hex(0x2F5BEA), hex(0x9B7BF0), hex(0xF29A4A), hex(0x1C9A55), hex(0xC9CDD4)]
}
