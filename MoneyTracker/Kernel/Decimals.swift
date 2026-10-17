import Foundation

/// Small, dependency-free helpers for working with money as `Decimal`.
/// Everything money-related in the kernel stays in `Decimal`; `Double`
/// only appears at the drawing layer (charts, gauges).
nonisolated enum Decimals {
    static let posix = Locale(identifier: "en_US_POSIX")

    /// Banker-free rounding to `scale` fraction digits.
    static func rounded(_ value: Decimal, scale: Int = 2) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }

    static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    /// Converts a `Double` coming from JSON into a clean `Decimal`
    /// (avoids binary artefacts like 0.1000000000000000055).
    static func fromDouble(_ value: Double) -> Decimal {
        guard value.isFinite else { return 0 }
        if let parsed = Decimal(string: String(value), locale: posix) { return parsed }
        return Decimal(value)
    }

    static func clamp01(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    /// `part / whole` as a 0...1 ratio, safe for zero and negatives.
    static func ratio(_ part: Decimal, of whole: Decimal) -> Double {
        guard whole > 0 else { return 0 }
        return clamp01(double(part / whole))
    }

    /// Unclamped ratio (can exceed 1, useful for "over budget" maths).
    static func rawRatio(_ part: Decimal, of whole: Decimal) -> Double {
        guard whole != 0 else { return 0 }
        let value = double(part / whole)
        return value.isFinite ? value : 0
    }

    static func abs(_ value: Decimal) -> Decimal { value < 0 ? -value : value }

    /// Plain string for editing fields ("1234.5"), never localized.
    static func editable(_ value: Decimal) -> String {
        let trimmed = rounded(value, scale: 8)
        return NSDecimalNumber(decimal: trimmed).stringValue
    }
}
