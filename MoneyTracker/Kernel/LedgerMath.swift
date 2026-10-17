import Foundation

nonisolated enum EntryKind: String, CaseIterable, Codable {
    case expense, income, transfer
}

/// The kernel's read-only view of a money movement. SwiftData models adopt it
/// in the app layer; tests use plain structs.
nonisolated protocol LedgerLine {
    var lineID: UUID { get }
    var lineKind: EntryKind { get }
    /// Positive amount in the source account's currency.
    var lineAmount: Decimal { get }
    var lineDate: Date { get }
    var lineSource: UUID? { get }
    var lineTarget: UUID? { get }
    /// Amount credited to the target account (cross-currency transfers).
    var lineTargetAmount: Decimal? { get }
    var lineCategory: UUID? { get }
    /// Currency of `lineAmount`.
    var lineCurrency: String { get }
    var lineNote: String { get }
    /// Set when the entry was produced by a repeating bill/income.
    var lineRuleID: UUID? { get }
}

/// Plain value form of a line. The app snapshots its entries into these before
/// running the maths, so the kernel never touches SwiftData objects.
nonisolated struct LineValue: LedgerLine, Hashable, Sendable {
    var lineID: UUID
    var lineKind: EntryKind
    var lineAmount: Decimal
    var lineDate: Date
    var lineSource: UUID?
    var lineTarget: UUID?
    var lineTargetAmount: Decimal?
    var lineCategory: UUID?
    var lineCurrency: String
    var lineNote: String
    var lineRuleID: UUID?
}

/// Converts `amount` from a currency code into the home currency.
typealias HomeConverter = (_ amount: Decimal, _ from: String) -> Decimal

nonisolated enum LedgerMath {

    /// Net effect of every entry per account (opening balances excluded).
    static func netEffects<L: LedgerLine>(_ lines: [L]) -> [UUID: Decimal] {
        var effects: [UUID: Decimal] = [:]
        for line in lines {
            switch line.lineKind {
            case .expense:
                if let source = line.lineSource { effects[source, default: 0] -= line.lineAmount }
            case .income:
                if let source = line.lineSource { effects[source, default: 0] += line.lineAmount }
            case .transfer:
                if let source = line.lineSource { effects[source, default: 0] -= line.lineAmount }
                if let target = line.lineTarget { effects[target, default: 0] += line.lineTargetAmount ?? line.lineAmount }
            }
        }
        return effects
    }

    /// Balance = opening + Σ effects.
    static func balances<L: LedgerLine>(openings: [UUID: Decimal], lines: [L]) -> [UUID: Decimal] {
        var result = openings
        for (account, effect) in netEffects(lines) where openings[account] != nil {
            result[account, default: 0] += effect
        }
        return result
    }

    /// Effect of a single line on one account (used for history replay).
    static func effect<L: LedgerLine>(of line: L, on account: UUID) -> Decimal {
        var value: Decimal = 0
        switch line.lineKind {
        case .expense:
            if line.lineSource == account { value -= line.lineAmount }
        case .income:
            if line.lineSource == account { value += line.lineAmount }
        case .transfer:
            if line.lineSource == account { value -= line.lineAmount }
            if line.lineTarget == account { value += line.lineTargetAmount ?? line.lineAmount }
        }
        return value
    }
}

/// Income/expense totals for a window, converted into the home currency.
nonisolated struct Tally: Equatable {
    var income: Decimal = 0
    var expense: Decimal = 0
    var expenseByCategory: [UUID: Decimal] = [:]
    var incomeByCategory: [UUID: Decimal] = [:]
    var uncategorizedExpense: Decimal = 0
    var uncategorizedIncome: Decimal = 0
    var expenseByDay: [Date: Decimal] = [:]
    var count: Int = 0

    var net: Decimal { income - expense }

    static func make<L: LedgerLine>(_ lines: [L], from start: Date? = nil, to end: Date? = nil, calendar: Calendar = .current, convert: HomeConverter) -> Tally {
        var tally = Tally()
        for line in lines {
            if let start, line.lineDate < start { continue }
            if let end, line.lineDate >= end { continue }
            switch line.lineKind {
            case .transfer:
                continue
            case .expense:
                let value = convert(line.lineAmount, line.lineCurrency)
                tally.expense += value
                if let category = line.lineCategory {
                    tally.expenseByCategory[category, default: 0] += value
                } else {
                    tally.uncategorizedExpense += value
                }
                tally.expenseByDay[calendar.startOfDay(for: line.lineDate), default: 0] += value
            case .income:
                let value = convert(line.lineAmount, line.lineCurrency)
                tally.income += value
                if let category = line.lineCategory {
                    tally.incomeByCategory[category, default: 0] += value
                } else {
                    tally.uncategorizedIncome += value
                }
            }
            tally.count += 1
        }
        return tally
    }
}

/// A row of a breakdown list.
nonisolated struct Share: Equatable, Identifiable {
    let id: UUID?
    let amount: Decimal
    let fraction: Double
}

nonisolated extension Tally {
    func expenseShares() -> [Share] {
        shares(from: expenseByCategory, extra: uncategorizedExpense, total: expense)
    }

    func incomeShares() -> [Share] {
        shares(from: incomeByCategory, extra: uncategorizedIncome, total: income)
    }

    private func shares(from map: [UUID: Decimal], extra: Decimal, total: Decimal) -> [Share] {
        var rows = map.map { Share(id: $0.key, amount: $0.value, fraction: Decimals.ratio($0.value, of: total)) }
        if extra > 0 { rows.append(Share(id: nil, amount: extra, fraction: Decimals.ratio(extra, of: total))) }
        return rows.sorted { lhs, rhs in
            if lhs.amount == rhs.amount { return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "") }
            return lhs.amount > rhs.amount
        }
    }
}
