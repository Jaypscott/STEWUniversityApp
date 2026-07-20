import SwiftUI
import UIKit

struct BandAccentTheme: Equatable, Sendable {
    static let defaultHex = "#E6A817"

    let hex: String
    let red: Double
    let green: Double
    let blue: Double

    init(hex: String?) {
        let normalized = Self.normalize(hex) ?? Self.defaultHex
        self.hex = normalized
        let value = Int(normalized.dropFirst(), radix: 16) ?? 0xE6A817
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    var color: Color { Color(red: red, green: green, blue: blue) }
    var softColor: Color { color.opacity(0.16) }
    var usesDarkForeground: Bool { relativeLuminance > 0.179 }
    var onAccent: Color { usesDarkForeground ? .black : .white }

    static func hex(from color: Color) -> String? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return String(
            format: "#%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }

    private var relativeLuminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.uppercased()
        guard normalized.range(of: #"^#[0-9A-F]{6}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return normalized
    }
}

extension BandSummary {
    var accentTheme: BandAccentTheme { BandAccentTheme(hex: accentColorHex) }
}
