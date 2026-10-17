import Foundation
import SwiftData

// IMPORTANT — data compatibility
// These classes back data that already lives on people's devices and in their
// private iCloud database. Class names, stored property names, types and
// defaults of the original release must stay exactly as they are. New
// information is only ever added as optional properties (or new models), which
// SwiftData migrates automatically and CloudKit accepts.

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String = "cash"
    var currencyCode: String = "USD"
    /// Cached current balance (opening balance + every entry). Recomputed by `BalanceKeeper`.
    var balance: Decimal = 0
    var colorHex: String = "34B27F"
    var createdAt: Date = Date.now
    var isArchived: Bool = false
    var overviewVisibilityRaw: String = "automatic"

    @Relationship(inverse: \Transaction.account) var transactions: [Transaction]?
    @Relationship(inverse: \Transaction.toAccount) var incomingTransfers: [Transaction]?

    // Added in 2.0
    var openingBalance: Decimal?
    var sortIndex: Int?
    var note: String?
    var iconName: String?
    var spendableOverride: Bool?
    var creditLimit: Decimal?

    init(name: String, kind: WalletKind, currencyCode: String, openingBalance: Decimal, colorHex: String) {
        self.id = UUID()
        self.name = name
        self.typeRaw = kind.rawValue
        self.currencyCode = currencyCode
        self.balance = openingBalance
        self.openingBalance = openingBalance
        self.colorHex = colorHex
        self.createdAt = .now
        self.isArchived = false
        self.overviewVisibilityRaw = "automatic"
    }
}

@Model
final class TransactionCategory {
    var id: UUID = UUID()
    var name: String = ""
    var iconName: String = "questionmark.circle"
    var colorHex: String = "8FA398"
    var kindRaw: String = "expense"
    var isCustom: Bool = true
    var sortOrder: Int = 0

    @Relationship(inverse: \Transaction.category) var transactions: [Transaction]?
    @Relationship(inverse: \Budget.category) var budgets: [Budget]?

    // Added in 2.0
    var isHidden: Bool?

    init(name: String, iconName: String, colorHex: String, isIncome: Bool, isCustom: Bool, sortOrder: Int) {
        self.id = UUID()
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.kindRaw = isIncome ? "income" : "expense"
        self.isCustom = isCustom
        self.sortOrder = sortOrder
    }
}

@Model
final class Transaction {
    var id: UUID = UUID()
    /// Positive amount in the (source) account's currency.
    var amount: Decimal = 0
    var typeRaw: String = "expense"
    var date: Date = Date.now
    var note: String?
    /// Legacy field, never written. Receipts live in `Attachment`.
    var receiptImageData: Data?
    @Relationship var account: Account?
    @Relationship var toAccount: Account?
    var toAmount: Decimal?
    @Relationship var category: TransactionCategory?
    var recurringRuleId: UUID?

    // Added in 2.0
    var originalAmount: Decimal?
    var originalCurrency: String?
    var createdAt: Date?
    var hasAttachment: Bool?

    init(kind: EntryKind, amount: Decimal, date: Date, note: String?, account: Account?) {
        self.id = UUID()
        self.typeRaw = kind.rawValue
        self.amount = amount
        self.date = date
        self.note = note
        self.account = account
        self.createdAt = .now
    }
}

@Model
final class Budget {
    var id: UUID = UUID()
    @Relationship var category: TransactionCategory?
    var limitAmount: Decimal = 0
    /// First money-month this limit applies to. Limits roll forward automatically.
    var month: Date = Date.now

    init(category: TransactionCategory?, limitAmount: Decimal, month: Date) {
        self.id = UUID()
        self.category = category
        self.limitAmount = limitAmount
        self.month = month
    }
}

@Model
final class Asset {
    var id: UUID = UUID()
    var typeRaw: String = "stock"
    var name: String = ""
    var ticker: String?
    var currencyCode: String = "USD"
    var note: String?
    var createdAt: Date = Date.now
    var autoUpdateEnabled: Bool = false
    /// Latest unit price in `currencyCode` (fetched or entered by hand).
    var lastFetchedPrice: Decimal?
    var lastFetchedAt: Date?

    @Relationship(inverse: \AssetTransaction.asset) var transactions: [AssetTransaction]?

    init(kind: HoldingKind, name: String, ticker: String?, currencyCode: String, autoUpdate: Bool, note: String?) {
        self.id = UUID()
        self.typeRaw = kind.rawValue
        self.name = name
        self.ticker = ticker
        self.currencyCode = currencyCode
        self.autoUpdateEnabled = autoUpdate
        self.note = note
        self.createdAt = .now
    }
}

@Model
final class AssetTransaction {
    var id: UUID = UUID()
    @Relationship var asset: Asset?
    /// "Buy" or "Sell" (capitalized, as written by version 1). The declared
    /// default stays "buy" exactly as in version 1 so the schema is unchanged.
    var kindRaw: String = "buy"
    var quantity: Decimal = 0
    var pricePerUnit: Decimal = 0
    var date: Date = Date.now
    var note: String?

    init(asset: Asset?, isBuy: Bool, quantity: Decimal, pricePerUnit: Decimal, date: Date, note: String?) {
        self.id = UUID()
        self.asset = asset
        self.kindRaw = isBuy ? "Buy" : "Sell"
        self.quantity = quantity
        self.pricePerUnit = pricePerUnit
        self.date = date
        self.note = note
    }
}

@Model
final class Goal {
    var id: UUID = UUID()
    var name: String = ""
    var targetAmount: Decimal = 0
    var currencyCode: String = "USD"
    var iconName: String?
    var customImageData: Data?
    var startDate: Date = Date.now
    var targetDate: Date?
    var monthlyContribution: Decimal?
    var sortOrder: Int = 0
    var linkedAccountIDs: [UUID] = []

    // Added in 2.0
    var trackingModeRaw: String?
    var manualSaved: Decimal?
    var achievedAt: Date?
    var colorHex: String?

    init(name: String, targetAmount: Decimal, currencyCode: String) {
        self.id = UUID()
        self.name = name
        self.targetAmount = targetAmount
        self.currencyCode = currencyCode
        self.startDate = .now
    }
}

@Model
final class UserProfile {
    var id: UUID = UUID()
    var name: String = "You"
    var email: String?
    var avatarImageData: Data?
    var defaultCurrencyCode: String = "USD"
    var biometricLockEnabled: Bool = false
    /// Budget alerts on/off (name kept from version 1).
    var notificationsEnabled: Bool = false
    var showCapitalOnOverview: Bool = true

    // Added in 2.0
    var monthlyPlan: Decimal?
    var periodStartDay: Int?
    var defaultAccountID: UUID?

    init(currencyCode: String) {
        self.id = UUID()
        self.defaultCurrencyCode = currencyCode
    }
}

// MARK: - New in 2.0

/// A repeating bill, subscription or income.
@Model
final class RecurringRule {
    var id: UUID = UUID()
    var title: String = ""
    var amount: Decimal = 0
    var kindRaw: String = "expense"
    var cadenceKey: String = "month:1"
    var anchorDate: Date = Date.now
    var nextDueDate: Date = Date.now
    var cycleIndex: Int = 0
    var endDate: Date?
    var accountID: UUID?
    var toAccountID: UUID?
    var categoryID: UUID?
    var autoPost: Bool = true
    /// Days before the due date to remind; negative means no reminder.
    var remindDaysBefore: Int = 1
    var isActive: Bool = true
    var isSubscription: Bool = false
    var note: String?
    var iconName: String?
    var colorHex: String?
    var createdAt: Date = Date.now

    init(title: String, amount: Decimal, kind: EntryKind, cadence: Cadence, firstDue: Date) {
        self.id = UUID()
        self.title = title
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.cadenceKey = cadence.storageKey
        self.anchorDate = firstDue
        self.nextDueDate = firstDue
        self.cycleIndex = 0
        self.createdAt = .now
    }
}

/// Receipt photo for an entry, stored outside the main database file.
@Model
final class Attachment {
    var id: UUID = UUID()
    var transactionID: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data?
    var createdAt: Date = Date.now

    init(transactionID: UUID, imageData: Data) {
        self.id = UUID()
        self.transactionID = transactionID
        self.imageData = imageData
        self.createdAt = .now
    }
}
