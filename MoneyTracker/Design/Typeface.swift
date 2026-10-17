import SwiftUI

/// Serif (New York) for figures and headings, SF for everything you read quickly.
nonisolated enum Typeface {
    static func figure(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static let display = Font.system(.largeTitle, design: .serif, weight: .semibold)
    static let title = Font.system(.title2, design: .serif, weight: .semibold)
    static let heading = Font.system(.title3, design: .serif, weight: .semibold)
    static let rowFigure = Font.system(.body, design: .serif, weight: .medium)
    static let smallFigure = Font.system(.subheadline, design: .serif, weight: .medium)
    static let body = Font.body
    static let label = Font.subheadline
    static let labelStrong = Font.subheadline.weight(.semibold)
    static let detail = Font.footnote
    static let micro = Font.caption2
    static let kicker = Font.system(size: 11, weight: .semibold)
    static let mono = Font.system(.caption, design: .monospaced)
}

/// Money formatting in the person's locale.
nonisolated enum MoneyFormat {

    static func plain(_ value: Decimal, code: String, cents: Bool = true) -> String {
        let currency = code.isEmpty ? "USD" : code
        if cents {
            return value.formatted(.currency(code: currency).precision(.fractionLength(0...2)))
        }
        return value.formatted(.currency(code: currency).precision(.fractionLength(0)))
    }

    static func signed(_ value: Decimal, code: String) -> String {
        let text = plain(Decimals.abs(value), code: code)
        if value > 0 { return "+" + text }
        if value < 0 { return "−" + text }
        return text
    }

    static func compact(_ value: Decimal, code: String) -> String {
        let currency = code.isEmpty ? "USD" : code
        if Decimals.abs(value) < 10_000 { return plain(value, code: currency, cents: false) }
        // Currency + compact notation needs iOS 18, so the symbol is placed by hand.
        let number = value.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
        let symbol = self.symbol(for: currency)
        let sample = plain(1, code: currency, cents: false)
        return sample.hasPrefix(symbol) ? symbol + number : number + "\u{00A0}" + symbol
    }

    static func number(_ value: Decimal, maxFraction: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxFraction)))
    }

    static func symbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = Locale.current
        let symbol = formatter.currencySymbol ?? code
        return symbol.isEmpty ? code : symbol
    }

    static func currencyName(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }

    static let masked = "••••"
}
