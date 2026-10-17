import SwiftUI
import UIKit

// "Ledger" visual language: warm paper, ink, one bright accent and a
// highlighter yellow. Every colour adapts to dark mode ("night ledger").

nonisolated extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

nonisolated extension Color {
    /// Light/dark pair from hex literals.
    init(light: UInt32, dark: UInt32, opacity: Double = 1) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light, alpha: CGFloat(opacity))
        })
    }

    /// "D9573B" or "#D9573B" → colour (falls back to graphite).
    init(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let value = UInt32(cleaned, radix: 16) ?? 0x555A63
        self.init(uiColor: UIColor(hex: value))
    }
}

nonisolated enum Ink {
    static let paper = Color(light: 0xF2EEE5, dark: 0x0F1012)
    static let sheet = Color(light: 0xFBF9F4, dark: 0x181A1E)
    static let raised = Color(light: 0xFFFFFF, dark: 0x202328)
    static let text = Color(light: 0x17181C, dark: 0xF2EFE8)
    static let soft = Color(light: 0x5C5F66, dark: 0xA9ABB1)
    static let faint = Color(light: 0x9A9CA1, dark: 0x6E7178)
    static let rule = Color(light: 0x17181C, dark: 0xF2EFE8, opacity: 0.11)
    static let ruleStrong = Color(light: 0x17181C, dark: 0xF2EFE8, opacity: 0.22)
    static let gain = Color(light: 0x1E7D58, dark: 0x47C28F)
    static let loss = Color(light: 0xC2412D, dark: 0xFF7D66)
    static let caution = Color(light: 0xB7791F, dark: 0xE8B04B)
    static let marker = Color(light: 0xF6D46A, dark: 0x7A621F)
    static let markerText = Color(light: 0x17181C, dark: 0xFDF6E3)
}

/// The one bright colour the person can pick (Pro offers all of them).
nonisolated enum InkAccent: String, CaseIterable, Identifiable {
    case vermilion, cobalt, emerald, plum, ochre, graphite

    var id: String { rawValue }

    var hex: String {
        switch self {
        case .vermilion: return "E0532F"
        case .cobalt: return "2C5BE6"
        case .emerald: return "138A63"
        case .plum: return "7A4FD1"
        case .ochre: return "C2861A"
        case .graphite: return "3A3D44"
        }
    }

    var color: Color {
        switch self {
        case .vermilion: return Color(light: 0xE0532F, dark: 0xFF6B45)
        case .cobalt: return Color(light: 0x2C5BE6, dark: 0x7193FF)
        case .emerald: return Color(light: 0x138A63, dark: 0x3CC898)
        case .plum: return Color(light: 0x7A4FD1, dark: 0xA88BFF)
        case .ochre: return Color(light: 0xC2861A, dark: 0xEAB14C)
        case .graphite: return Color(light: 0x3A3D44, dark: 0xD3D5DA)
        }
    }

    var title: String {
        switch self {
        case .vermilion: return String(localized: "Vermilion")
        case .cobalt: return String(localized: "Cobalt")
        case .emerald: return String(localized: "Emerald")
        case .plum: return String(localized: "Plum")
        case .ochre: return String(localized: "Ochre")
        case .graphite: return String(localized: "Graphite")
        }
    }
}

/// Muted "ink" colours for categories, accounts and goals.
nonisolated enum InkSwatch {
    static let tomato = "D9573B"
    static let ochre = "C99A2E"
    static let olive = "7E8F3A"
    static let moss = "4F7A55"
    static let teal = "2F8F86"
    static let sky = "3E8EC2"
    static let cobalt = "3D63C9"
    static let plum = "8A55B8"
    static let rose = "C4577E"
    static let sienna = "A0522D"
    static let slate = "5D6B7A"
    static let graphite = "555A63"

    static let all = [tomato, ochre, olive, moss, teal, sky, cobalt, plum, rose, sienna, slate, graphite]
}

nonisolated enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var title: String {
        switch self {
        case .system: return String(localized: "Automatic")
        case .light: return String(localized: "Paper")
        case .dark: return String(localized: "Night")
        }
    }
}

// MARK: - Environment

private struct MaskAmountsKey: EnvironmentKey {
    nonisolated static let defaultValue = false
}

private struct AccentKey: EnvironmentKey {
    nonisolated static let defaultValue: Color = Color(red: 0.878, green: 0.325, blue: 0.184)
}

extension EnvironmentValues {
    /// Privacy mode: every amount renders as dots.
    var masksAmounts: Bool {
        get { self[MaskAmountsKey.self] }
        set { self[MaskAmountsKey.self] = newValue }
    }

    var inkAccent: Color {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}
