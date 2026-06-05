import SwiftUI

/// Warm parchment + deep-green palette echoing a printed Mushaf, with a dark variant.
struct Palette {
    let appBackground: Color
    let window: Color
    let sidebar: Color
    let sidebarLine: Color
    let titlebar: Color
    let ink: Color
    let inkSoft: Color
    let inkFaint: Color
    let accent: Color
    let accentSoft: Color
    let gold: Color
    let readingBackground: Color
    let rowHover: Color
    let chip: Color

    static let light = Palette(
        appBackground: Color(hex: 0xE9E4D8),
        window:        Color(hex: 0xFBF8F1),
        sidebar:       Color(hex: 0xF3EFE6),
        sidebarLine:   Color(hex: 0xE3DDCE),
        titlebar:      Color(hex: 0xF0EBE0),
        ink:           Color(hex: 0x2B2620),
        inkSoft:       Color(hex: 0x7C7464),
        inkFaint:      Color(hex: 0xA89F8C),
        accent:        Color(hex: 0x1F6B4F),
        accentSoft:    Color(hex: 0xE3EFE7),
        gold:          Color(hex: 0xB08B3E),
        readingBackground: Color(hex: 0xDDD6C6),
        rowHover:      Color(hex: 0xECE6D8),
        chip:          Color(hex: 0xE7E1D2)
    )

    static let dark = Palette(
        appBackground: Color(hex: 0x15140F),
        window:        Color(hex: 0x1C1B16),
        sidebar:       Color(hex: 0x201F19),
        sidebarLine:   Color(hex: 0x2E2C23),
        titlebar:      Color(hex: 0x232219),
        ink:           Color(hex: 0xECE6D6),
        inkSoft:       Color(hex: 0xA59C87),
        inkFaint:      Color(hex: 0x6F6757),
        accent:        Color(hex: 0x5DB98E),
        accentSoft:    Color(hex: 0x1E2F27),
        gold:          Color(hex: 0xCFA84E),
        readingBackground: Color(hex: 0x100F0B),
        rowHover:      Color(hex: 0x2A281F),
        chip:          Color(hex: 0x2C2A20)
    )
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
