import Foundation
import SwiftData

/// Kinds of accounts. Raw values are shared with version 1 ("cash", "card", "savings", "other").
enum WalletKind: String, CaseIterable, Identifiable {
    case cash, card, savings, credit, loan, other

    var id: String { rawValue }

    var isLiability: Bool { self == .credit || self == .loan }

    /// Counted in the daily allowance by default.
    var isSpendableByDefault: Bool { self == .cash || self == .card || self == .other }

    var symbol: String {
        switch self {
        case .cash: return "banknote"
        case .card: return "creditcard"
        case .savings: return "building.columns"
        case .credit: return "creditcard.trianglebadge.exclamationmark"
        case .loan: return "doc.text"
        case .other: return "square.stack.3d.up"
        }
    }

    var title: String {
        switch self {
        case .cash: return String(localized: "Cash")
        case .card: return String(localized: "Card")
        case .savings: return String(localized: "Savings")
        case .credit: return String(localized: "Credit card")
        case .loan: return String(localized: "Loan")
        case .other: return String(localized: "Other")
        }
    }

    var groupTitle: String {
        switch self {
        case .cash: return String(localized: "Cash")
        case .card: return String(localized: "Cards")
        case .savings: return String(localized: "Savings")
        case .credit: return String(localized: "Credit cards")
        case .loan: return String(localized: "Loans")
        case .other: return String(localized: "Other")
        }
    }
}

/// Kinds of investments. Raw values are shared with version 1.
enum HoldingKind: String, CaseIterable, Identifiable {
    case stock, crypto, collectible

    var id: String { rawValue }

    var hasLiveQuotes: Bool { self != .collectible }

    var title: String {
        switch self {
        case .stock: return String(localized: "Stocks & ETFs")
        case .crypto: return String(localized: "Crypto")
        case .collectible: return String(localized: "Property & other")
        }
    }

    var symbol: String {
        switch self {
        case .stock: return "chart.line.uptrend.xyaxis"
        case .crypto: return "bitcoinsign.circle"
        case .collectible: return "house.lodge"
        }
    }
}

enum GoalTracking: String, CaseIterable, Identifiable {
    /// Progress follows the balance of linked accounts (version 1 behavior).
    case wallets
    /// Progress is what the person sets aside by hand.
    case manual

    var id: String { rawValue }
}

// MARK: - Account

extension Account {
    var kind: WalletKind {
        get { WalletKind(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    var isSpendable: Bool {
        guard !isArchived else { return false }
        return spendableOverride ?? kind.isSpendableByDefault
    }

    var displaySymbol: String { iconName ?? kind.symbol }

    /// Amount owed on a liability (positive), or nil for asset accounts.
    var amountOwed: Decimal? {
        guard kind.isLiability else { return nil }
        return balance < 0 ? -balance : 0
    }
}

// MARK: - Category

extension TransactionCategory {
    var isIncome: Bool { kindRaw == "income" }
    var visible: Bool { !(isHidden ?? false) }
}

// MARK: - Transaction

extension Transaction {
    var kind: EntryKind {
        get { EntryKind(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    var currencyCode: String { account?.currencyCode ?? originalCurrency ?? "" }

    var displayTitle: String {
        if let note, !note.trimmingCharacters(in: .whitespaces).isEmpty { return note }
        if kind == .transfer { return String(localized: "Transfer") }
        return category?.name ?? (kind == .income ? String(localized: "Income") : String(localized: "Expense"))
    }

    /// Signed amount from the point of view of `account`.
    var signedAmount: Decimal {
        switch kind {
        case .expense: return -amount
        case .income: return amount
        case .transfer: return -amount
        }
    }
}

extension Transaction {
    /// Value snapshot for the ledger maths (read once, then iterated cheaply).
    var ledgerLine: LineValue {
        let kind = self.kind
        return LineValue(
            lineID: id,
            lineKind: kind,
            lineAmount: amount,
            lineDate: date,
            lineSource: account?.id,
            lineTarget: kind == .transfer ? toAccount?.id : nil,
            lineTargetAmount: toAmount,
            lineCategory: kind == .transfer ? nil : category?.id,
            lineCurrency: currencyCode,
            lineNote: note ?? "",
            lineRuleID: recurringRuleId
        )
    }
}

extension Sequence where Element == Transaction {
    var ledgerLines: [LineValue] { map(\.ledgerLine) }
}

// MARK: - Assets

extension Asset {
    var kind: HoldingKind {
        get { HoldingKind(rawValue: typeRaw) ?? .collectible }
        set { typeRaw = newValue.rawValue }
    }

    var trades: [HoldingTrade] {
        (transactions ?? []).map { HoldingTrade(date: $0.date, isBuy: $0.isBuy, quantity: $0.quantity, price: $0.pricePerUnit) }
    }

    var position: HoldingPosition { HoldingMath.position(trades) }

    /// Price used for valuation: last quote, otherwise average cost.
    var markPrice: Decimal { lastFetchedPrice ?? position.averageCost }

    var marketValue: Decimal { markPrice * position.quantity }

    var unrealized: Decimal { (markPrice - position.averageCost) * position.quantity }
}

extension AssetTransaction {
    var isBuy: Bool { kindRaw.lowercased() != "sell" }
}

// MARK: - Goal

extension Goal {
    var tracking: GoalTracking {
        get {
            if let raw = trackingModeRaw, let mode = GoalTracking(rawValue: raw) { return mode }
            return .wallets
        }
        set { trackingModeRaw = newValue.rawValue }
    }
}

// MARK: - Rule

extension RecurringRule {
    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var cadence: Cadence {
        get { Cadence(storageKey: cadenceKey) ?? .monthly }
        set { cadenceKey = newValue.storageKey }
    }

    var remindsBeforeDue: Bool { remindDaysBefore >= 0 }

    func occurrence(_ index: Int, calendar: Calendar = .current) -> Date {
        Recurrence.occurrence(index, anchor: anchorDate, cadence: cadence, calendar: calendar)
    }

    var hasEnded: Bool {
        if let endDate { return nextDueDate > endDate }
        return false
    }
}
