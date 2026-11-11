import SwiftUI
import Testing
@testable import Finlynq

struct ThemeTests {
    /// Resolves a token in the light appearance and returns 0xRRGGBB.
    private func lightHex(_ color: Color) -> UInt32 {
        var rgb: [CGFloat] = [0, 0, 0]
        #if canImport(UIKit)
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var alpha: CGFloat = 0
        resolved.getRed(&rgb[0], green: &rgb[1], blue: &rgb[2], alpha: &alpha)
        #else
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            let resolved = NSColor(color).usingColorSpace(.sRGB)!
            rgb = [resolved.redComponent, resolved.greenComponent, resolved.blueComponent]
        }
        #endif
        return rgb.reduce(0) { ($0 << 8) | UInt32((($1 * 255).rounded())) }
    }

    @Test func lightPaletteMatchesSpec() {
        let spec: [(Color, UInt32)] = [
            (Theme.page, 0xF2F3F5), (Theme.card, 0xFFFFFF), (Theme.text, 0x111318), (Theme.secondary, 0x5F6672),
            (Theme.accent, 0x2F5BEA), (Theme.accentTint, 0xE8EEFF),
            (Theme.positive, 0x0B6B37), (Theme.positiveTint, 0xE3F5EA), (Theme.positiveBar, 0x1C9A55),
            (Theme.warning, 0xB4580A), (Theme.warningTint, 0xFFF1E3), (Theme.spendBar, 0xF29A4A),
            (Theme.negative, 0xB42318), (Theme.negativeTint, 0xFDEBEB), (Theme.overBar, 0xD9443A),
            (Theme.invest, 0x5B3CC4), (Theme.investTint, 0xF1ECFF)
        ]
        for (color, hex) in spec { #expect(lightHex(color) == hex, "expected \(String(hex, radix: 16))") }
    }
}
