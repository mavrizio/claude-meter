import SwiftUI

/// Same palette as the firmware (firmware/src/ui.cpp).
enum Palette {
    static let green = RGB(0x4F, 0xD1, 0x8B)
    static let amber = RGB(0xF2, 0xB3, 0x47)
    static let red = RGB(0xF2, 0x54, 0x5B)
    static let accent = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
    static let track = Color.primary.opacity(0.10)

    /// Smooth green -> amber (50-75%) -> red (75-92%), like level_color() on the device.
    static func level(_ pct: Double) -> Color {
        let v = pct * 10
        if v <= 500 { return green.color }
        if v <= 750 { return mix(amber, green, (v - 500) / 250).color }
        if v <= 920 { return mix(red, amber, (v - 750) / 170).color }
        return red.color
    }

    struct RGB {
        let r, g, b: Double
        init(_ r: Int, _ g: Int, _ b: Int) { self.r = Double(r) / 255; self.g = Double(g) / 255; self.b = Double(b) / 255 }
        init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
        var color: Color { Color(red: r, green: g, blue: b) }
    }

    /// `amount` of a + (1 - amount) of b.
    static func mix(_ a: RGB, _ b: RGB, _ amount: Double) -> RGB {
        let k = min(max(amount, 0), 1)
        return RGB(r: a.r * k + b.r * (1 - k), g: a.g * k + b.g * (1 - k), b: a.b * k + b.b * (1 - k))
    }
}
