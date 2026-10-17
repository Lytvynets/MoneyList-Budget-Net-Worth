import Foundation

/// How often a bill, subscription or income repeats.
nonisolated struct Cadence: Equatable, Hashable, Codable {
    nonisolated enum Unit: String, Codable, CaseIterable {
        case day, week, month, year
    }

    var unit: Unit
    var every: Int

    init(unit: Unit, every: Int = 1) {
        self.unit = unit
        self.every = max(1, every)
    }

    static let weekly = Cadence(unit: .week)
    static let biweekly = Cadence(unit: .week, every: 2)
    static let monthly = Cadence(unit: .month)
    static let quarterly = Cadence(unit: .month, every: 3)
    static let yearly = Cadence(unit: .year)

    /// Storage format: "month:1", "week:2" …
    var storageKey: String { "\(unit.rawValue):\(every)" }

    init?(storageKey: String) {
        let parts = storageKey.split(separator: ":")
        guard let first = parts.first, let unit = Unit(rawValue: String(first)) else { return nil }
        let every = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
        self.init(unit: unit, every: every)
    }

    var component: Calendar.Component {
        switch unit {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    /// Approximate occurrences per year, used for "costs X a year" maths.
    var timesPerYear: Decimal {
        switch unit {
        case .day: return Decimal(365) / Decimal(every)
        case .week: return Decimal(52) / Decimal(every)
        case .month: return Decimal(12) / Decimal(every)
        case .year: return Decimal(1) / Decimal(every)
        }
    }

    /// Normalised monthly cost of one occurrence amount.
    func monthlyShare(of amount: Decimal) -> Decimal {
        amount * timesPerYear / 12
    }
}

/// Date maths for repeating items. Occurrences are always computed from the
/// anchor (n × step) so month-end anchors never drift (Jan 31 → Feb 28 → Mar 31).
nonisolated enum Recurrence {

    static func occurrence(_ index: Int, anchor: Date, cadence: Cadence, calendar: Calendar = .current) -> Date {
        guard index > 0 else { return anchor }
        return calendar.date(byAdding: cadence.component, value: index * cadence.every, to: anchor) ?? anchor
    }

    /// Index of the first occurrence that is on or after `date`.
    static func firstIndex(onOrAfter date: Date, anchor: Date, cadence: Cadence, calendar: Calendar = .current) -> Int {
        if date <= anchor { return 0 }
        // Estimate, then walk to the exact index.
        let seconds = date.timeIntervalSince(anchor)
        let approxStep: Double
        switch cadence.unit {
        case .day: approxStep = 86_400
        case .week: approxStep = 604_800
        case .month: approxStep = 2_629_746
        case .year: approxStep = 31_556_952
        }
        var index = max(0, Int(seconds / (approxStep * Double(cadence.every))) - 2)
        var guardCounter = 0
        while occurrence(index, anchor: anchor, cadence: cadence, calendar: calendar) < date && guardCounter < 10_000 {
            index += 1
            guardCounter += 1
        }
        while index > 0 && occurrence(index - 1, anchor: anchor, cadence: cadence, calendar: calendar) >= date {
            index -= 1
        }
        return index
    }

    /// All occurrences in [start, end).
    static func occurrences(from start: Date, to end: Date, anchor: Date, cadence: Cadence, until: Date? = nil, calendar: Calendar = .current, limit: Int = 400) -> [Date] {
        guard end > start else { return [] }
        var index = firstIndex(onOrAfter: start, anchor: anchor, cadence: cadence, calendar: calendar)
        var dates: [Date] = []
        while dates.count < limit {
            let date = occurrence(index, anchor: anchor, cadence: cadence, calendar: calendar)
            if date >= end { break }
            if let until, date > until { break }
            dates.append(date)
            index += 1
        }
        return dates
    }

    /// Next occurrence strictly after `date`.
    static func next(after date: Date, anchor: Date, cadence: Cadence, calendar: Calendar = .current) -> Date {
        let index = firstIndex(onOrAfter: date, anchor: anchor, cadence: cadence, calendar: calendar)
        let candidate = occurrence(index, anchor: anchor, cadence: cadence, calendar: calendar)
        if candidate > date { return candidate }
        return occurrence(index + 1, anchor: anchor, cadence: cadence, calendar: calendar)
    }

    /// Whole days from `from` (start of day) until `to` (start of day).
    static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: from)
        let b = calendar.startOfDay(for: to)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }
}
