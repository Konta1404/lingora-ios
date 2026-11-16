import SwiftUI
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
    var base: Color { .oklch(0.58, 0.07, h) }
    var deep: Color { .oklch(0.40, 0.06, h) }
    var tint: Color { .oklch(0.94, 0.03, h) }
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
        case .sage: "Sage"
        case .blue: "Dusty blue"
        case .terracotta: "Soft terracotta"
        case .lavender: "Muted lavender"
        }
    }
}

enum Direction: String, CaseIterable, Codable, Identifiable {
    case cards, open
    var id: String { rawValue }
    var label: String { self == .cards ? "Soft cards" : "Open" }
}

struct Theme {
    var accent: Accent = .sage
    var direction: Direction = .cards
    var languageTints: Bool = true

    var isOpen: Bool { direction == .open }

    // Text
    let text = Color(hex: 0x2b2a28)
    let muted = Color(hex: 0x6b6864)
    let onDark = Color(hex: 0xfbfaf8)

    // Accent
    var a: Color { Hue(h: accent.hue).base }
    var ad: Color { Hue(h: accent.hue).deep }
    var at: Color { Hue(h: accent.hue).tint }

    // Neutrals
    var ground: Color { isOpen ? Color(hex: 0xfbfaf8) : Color(hex: 0xf6f5f2) }
    var card: Color { isOpen ? Color(hex: 0xfbfaf8) : Color(hex: 0xfdfcfa) }
    var chip: Color { isOpen ? Color(hex: 0xf0efeb) : Color(hex: 0xecebe7) }
    let chip2 = Color(hex: 0xe2e0db)
    let line = Color(hex: 0x2b2a28, opacity: 0.09)
    var cardBorder: Color { isOpen ? Color(hex: 0x2b2a28, opacity: 0.11) : .clear }
    var radius: CGFloat { isOpen ? 16 : 22 }
    var titleSize: CGFloat { isOpen ? 34 : 30 }

    // Errors
    let errorText = Color(hex: 0xa6533f)
    let errorBorder = Color(hex: 0xc98a78)

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
