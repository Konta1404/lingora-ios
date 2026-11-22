import SwiftUI
import UIKit
import CoreText

// MARK: - OKLCH → sRGB

extension Color {
    /// Builds a colour from OKLCH (L 0…1, C, H degrees) — the recipe used throughout the design handoff.
    static func oklch(_ l: Double, _ c: Double, _ h: Double) -> Color {
        let hr = h * .pi / 180
        let a = c * cos(hr), b = c * sin(hr)
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        let r = 4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S
        let g = -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S
        let bl = -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S
        func gamma(_ x: Double) -> Double {
            let v = max(0, min(1, x))
            return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        }
        return Color(.sRGB, red: gamma(r), green: gamma(g), blue: gamma(bl), opacity: 1)
    }

    /// A colour that follows light / dark mode.
    static func dynamic(_ light: Color, _ dark: Color) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: opacity)
    }
}

/// The three-step colour recipe (base / deep / tint) used for the accent, every language and every avatar.
struct Hue: Hashable {
    let h: Double
    var base: Color { .dynamic(.oklch(0.58, 0.07, h), .oklch(0.62, 0.08, h)) }
    /// Text on a tint: dark in light mode, light in dark mode.
    var deep: Color { .dynamic(.oklch(0.40, 0.06, h), .oklch(0.86, 0.05, h)) }
    var tint: Color { .dynamic(.oklch(0.94, 0.03, h), .oklch(0.32, 0.04, h)) }
}

// MARK: - Theme

enum Accent: String, CaseIterable, Codable, Identifiable {
    case sage, blue, terracotta, lavender
    var id: String { rawValue }
    var hue: Double {
        switch self {
        case .sage: 150
        case .blue: 240
        case .terracotta: 45
        case .lavender: 300
        }
    }
    var label: String {
        switch self {
        case .sage: L("Sage")
        case .blue: L("Dusty blue")
        case .terracotta: L("Soft terracotta")
        case .lavender: L("Muted lavender")
        }
    }
}

/// Light, dark, or follow the iPhone.
enum Appearance: String, CaseIterable, Codable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: L("Automatic")
        case .light: L("Light")
        case .dark: L("Dark")
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum Direction: String, CaseIterable, Codable, Identifiable {
    case cards, open
    var id: String { rawValue }
    var label: String { self == .cards ? L("Soft cards") : L("Open") }
}

struct Theme {
    var accent: Accent = .sage
    var direction: Direction = .cards
    var languageTints: Bool = true

    var isOpen: Bool { direction == .open }

    // Text
    let text = Color.dynamic(Color(hex: 0x2b2a28), Color(hex: 0xedebe7))
    let muted = Color.dynamic(Color(hex: 0x6b6864), Color(hex: 0xa29e98))
    /// Text on an inverted (text-coloured) surface.
    let onDark = Color.dynamic(Color(hex: 0xfbfaf8), Color(hex: 0x1c1b1a))

    // Accent
    var a: Color { Hue(h: accent.hue).base }
    var ad: Color { Hue(h: accent.hue).deep }
    var at: Color { Hue(h: accent.hue).tint }

    // Neutrals
    var ground: Color { isOpen ? .dynamic(Color(hex: 0xfbfaf8), Color(hex: 0x161514)) : .dynamic(Color(hex: 0xf6f5f2), Color(hex: 0x151413)) }
    var card: Color { isOpen ? .dynamic(Color(hex: 0xfbfaf8), Color(hex: 0x161514)) : .dynamic(Color(hex: 0xfdfcfa), Color(hex: 0x22211f)) }
    var chip: Color { isOpen ? .dynamic(Color(hex: 0xf0efeb), Color(hex: 0x262523)) : .dynamic(Color(hex: 0xecebe7), Color(hex: 0x2c2b29)) }
    let chip2 = Color.dynamic(Color(hex: 0xe2e0db), Color(hex: 0x3a3936))
    let line = Color.dynamic(Color(hex: 0x2b2a28, opacity: 0.09), Color(hex: 0xffffff, opacity: 0.10))
    var cardBorder: Color { isOpen ? .dynamic(Color(hex: 0x2b2a28, opacity: 0.11), Color(hex: 0xffffff, opacity: 0.12)) : .clear }
    /// Soft shadow colour (barely visible in dark mode, where cards are lighter than the ground).
    let shadow = Color.dynamic(Color(hex: 0x2b2a28), Color.black)
    /// Plain white surfaces (Google button, toggles) — a raised card in dark mode.
    let paper = Color.dynamic(.white, Color(hex: 0x2c2b29))
    var radius: CGFloat { isOpen ? 16 : 22 }
    var titleSize: CGFloat { isOpen ? 34 : 30 }

    // Errors
    let errorText = Color.dynamic(Color(hex: 0xa6533f), Color(hex: 0xe39a86))
    let errorBorder = Color.dynamic(Color(hex: 0xc98a78), Color(hex: 0x9a5a48))
    let errorTint = Color.dynamic(Color(hex: 0xf6e9e4), Color(hex: 0x3a2520))

    /// Colours for a language (or the accent, when per-language tints are off).
    func colors(for hue: Double) -> Hue { Hue(h: languageTints ? hue : accent.hue) }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = Theme() }
extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Typography (Figtree, bundled)

enum FontRegistrar {
    static func registerAll() {
        for name in ["Figtree-Regular", "Figtree-Medium", "Figtree-SemiBold", "Figtree-Bold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// Figtree at a base size that scales with Dynamic Type.
    static func fig(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Figtree-Bold"
        case .semibold: name = "Figtree-SemiBold"
        case .medium: name = "Figtree-Medium"
        default: name = "Figtree-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }
}
