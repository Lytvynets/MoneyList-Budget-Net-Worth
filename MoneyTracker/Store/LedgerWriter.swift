import Foundation
import SwiftData

typealias CurrencyConverter = (_ amount: Decimal, _ from: String, _ to: String) -> Decimal

/// Everything the composer collects before saving an entry.
struct EntryDraft {
    var kind: EntryKind = .expense
    /// Amount as typed, in `inputCurrency`.
    var amount: Decimal = 0
    var inputCurrency: String = "USD"
    var accountID: UUID?
    var toAccountID: UUID?
    /// What arrives in the target account for cross-currency transfers.
    var receivedAmount: Decimal?
    var categoryID: UUID?
    var note: String = ""
    var date: Date = Date()
    var repeatCadence: Cadence?
    var attachment: Data?
    var removeAttachment: Bool = false
}

/// The only place that changes money data. Every write ends with a save and a
/// refresh of derived values (balances, widgets, reminders).
struct LedgerWriter {
    let context: ModelContext
    let convert: CurrencyConverter

    // MARK: Entries

    @discardableResult
    func save(_ draft: EntryDraft, editing existing: Transaction? = nil) throws -> Transaction {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        guard let account = accounts.first(where: { $0.id == draft.accountID }) ?? accounts.first(where: { !$0.isArchived }) else {
            throw WriterError.noAccount
        }

        let recorded: Decimal
        if draft.kind != .transfer, draft.inputCurrency != account.currencyCode, !draft.inputCurrency.isEmpty {
            recorded = Decimals.rounded(convert(draft.amount, draft.inputCurrency, account.currencyCode))
        } else {
            recorded = Decimals.rounded(draft.amount)
        }

        let entry: Transaction
        if let existing {
            entry = existing
            entry.kind = draft.kind
            entry.amount = recorded
            entry.date = draft.date
            entry.account = account
        } else {
            entry = Transaction(kind: draft.kind, amount: recorded, date: draft.date, note: nil, account: account)
            context.insert(entry)
        }
        let trimmed = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = trimmed.isEmpty ? nil : trimmed

        if draft.kind == .transfer {
            let target = accounts.first { $0.id == draft.toAccountID }
            entry.toAccount = target
            entry.category = nil
            if let target, target.currencyCode != account.currencyCode {
                entry.toAmount = draft.receivedAmount.map { Decimals.rounded($0) }
                    ?? Decimals.rounded(convert(recorded, account.currencyCode, target.currencyCode))
            } else {
                entry.toAmount = nil
            }
            entry.originalAmount = nil
            entry.originalCurrency = nil
        } else {
            entry.toAccount = nil
            entry.toAmount = nil
            let categories = try context.fetch(FetchDescriptor<TransactionCategory>())
            entry.category = categories.first { $0.id == draft.categoryID }
            if draft.inputCurrency != account.currencyCode, !draft.inputCurrency.isEmpty {
                entry.originalAmount = draft.amount
                entry.originalCurrency = draft.inputCurrency
            } else {
                entry.originalAmount = nil
                entry.originalCurrency = nil
            }
        }

        if draft.removeAttachment {
            removeAttachments(for: entry.id)
            entry.hasAttachment = false
            entry.receiptImageData = nil
        }
        if let data = draft.attachment {
            removeAttachments(for: entry.id)
            context.insert(Attachment(transactionID: entry.id, imageData: data))
            entry.hasAttachment = true
            entry.receiptImageData = nil
        }

        if let cadence = draft.repeatCadence, existing == nil {
            let next = Recurrence.occurrence(1, anchor: draft.date, cadence: cadence)
            let rule = RecurringRule(title: entry.note ?? entry.category?.name ?? String(localized: "Repeating entry"), amount: recorded, kind: draft.kind, cadence: cadence, firstDue: next)
            rule.accountID = account.id
            rule.toAccountID = entry.toAccount?.id
            rule.categoryID = entry.category?.id
            rule.isSubscription = (entry.category?.iconName == "repeat")
            rule.colorHex = entry.category?.colorHex
            rule.iconName = entry.category?.iconName
            context.insert(rule)
            entry.recurringRuleId = rule.id
        }

        try context.save()
        BalanceKeeper.recompute(context: context)
        return entry
    }

    func delete(_ entry: Transaction) throws {
        removeAttachments(for: entry.id)
        context.delete(entry)
        try context.save()
        BalanceKeeper.recompute(context: context)
    }

    func delete(_ entries: [Transaction]) throws {
        for entry in entries {
            removeAttachments(for: entry.id)
            context.delete(entry)
        }
        try context.save()
        BalanceKeeper.recompute(context: context)
    }

    @discardableResult
    func duplicate(_ entry: Transaction, on date: Date = Date()) throws -> Transaction {
        let copy = Transaction(kind: entry.kind, amount: entry.amount, date: date, note: entry.note, account: entry.account)
        copy.toAccount = entry.toAccount
        copy.toAmount = entry.toAmount
        copy.category = entry.category
        copy.originalAmount = entry.originalAmount
        copy.originalCurrency = entry.originalCurrency
        context.insert(copy)
        try context.save()
        BalanceKeeper.recompute(context: context)
        return copy
    }

    func attachment(for entryID: UUID) -> Data? {
        let all = (try? context.fetch(FetchDescriptor<Attachment>())) ?? []
        return all.first { $0.transactionID == entryID }?.imageData
    }

    /// The entry's receipt: a version 2 attachment, or the photo version 1
    /// stored inline on the entry.
    func receipt(for entry: Transaction) -> Data? {
        if entry.hasAttachment == true, let data = attachment(for: entry.id) { return data }
        return entry.receiptImageData
    }

    private func removeAttachments(for entryID: UUID) {
        let all = (try? context.fetch(FetchDescriptor<Attachment>())) ?? []
        for item in all where item.transactionID == entryID { context.delete(item) }
    }

    // MARK: Accounts

    @discardableResult
    func createAccount(name: String, kind: WalletKind, currency: String, balance: Decimal, colorHex: String) throws -> Account {
        let existing = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let opening = kind.isLiability ? -Decimals.abs(balance) : balance
        let account = Account(name: name, kind: kind, currencyCode: currency, openingBalance: opening, colorHex: colorHex)
        account.sortIndex = (existing.compactMap(\.sortIndex).max() ?? existing.count) + 1
        context.insert(account)
        try context.save()
        return account
    }

    func updateAccount(_ account: Account, name: String, kind: WalletKind, currency: String, currentBalance: Decimal, colorHex: String, spendable: Bool?) throws {
        account.name = name
        account.kind = kind
        account.currencyCode = currency
        account.colorHex = colorHex
        account.spendableOverride = spendable
        let target = kind.isLiability ? -Decimals.abs(currentBalance) : currentBalance
        BalanceKeeper.setCurrentBalance(target, for: account, context: context)
        try context.save()
        BalanceKeeper.recompute(context: context)
    }

    func setArchived(_ account: Account, _ archived: Bool) throws {
        account.isArchived = archived
        try context.save()
    }

    /// Deletes an account together with its entries.
    func deleteAccount(_ account: Account) throws {
        let entries = (account.transactions ?? []) + (account.incomingTransfers ?? [])
        var seen = Set<UUID>()
        for entry in entries where seen.insert(entry.id).inserted {
            removeAttachments(for: entry.id)
            context.delete(entry)
        }
        let rules = (try? context.fetch(FetchDescriptor<RecurringRule>())) ?? []
        for rule in rules where rule.accountID == account.id || rule.toAccountID == account.id {
            rule.isActive = false
        }
        context.delete(account)
        try context.save()
        BalanceKeeper.recompute(context: context)
    }

    func reorderAccounts(_ ordered: [Account]) throws {
        for (index, account) in ordered.enumerated() { account.sortIndex = index }
        try context.save()
    }

    // MARK: Categories

    @discardableResult
    func createCategory(name: String, icon: String, colorHex: String, isIncome: Bool) throws -> TransactionCategory {
        let existing = (try? context.fetch(FetchDescriptor<TransactionCategory>())) ?? []
        let order = (existing.filter { $0.isIncome == isIncome }.map(\.sortOrder).max() ?? 0) + 1
        let category = TransactionCategory(name: name, iconName: icon, colorHex: colorHex, isIncome: isIncome, isCustom: true, sortOrder: order)
        context.insert(category)
        try context.save()
        return category
    }

    func updateCategory(_ category: TransactionCategory, name: String, icon: String, colorHex: String) throws {
        category.name = name
        category.iconName = icon
        category.colorHex = colorHex
        try context.save()
    }

    func setHidden(_ category: TransactionCategory, _ hidden: Bool) throws {
        category.isHidden = hidden
        try context.save()
    }

    /// Deletes a category; its entries move to `replacement` (or become uncategorized).
    func deleteCategory(_ category: TransactionCategory, movingTo replacement: TransactionCategory?) throws {
        for entry in category.transactions ?? [] { entry.category = replacement }
        for budget in category.budgets ?? [] { context.delete(budget) }
        let rules = (try? context.fetch(FetchDescriptor<RecurringRule>())) ?? []
        for rule in rules where rule.categoryID == category.id { rule.categoryID = replacement?.id }
        context.delete(category)
        try context.save()
    }

    func reorderCategories(_ ordered: [TransactionCategory]) throws {
        for (index, category) in ordered.enumerated() { category.sortOrder = index }
        try context.save()
    }

    // MARK: Budgets

    /// Sets the limit for a category from `month` on (older months keep their history).
    func setBudget(category: TransactionCategory, limit: Decimal, month: MoneyMonth) throws {
        let all = (try? context.fetch(FetchDescriptor<Budget>())) ?? []
        let mine = all.filter { $0.category?.id == category.id }
        if let sameMonth = mine.first(where: { abs($0.month.timeIntervalSince(month.start)) < 43_200 }) {
            sameMonth.limitAmount = limit
        } else {
            context.insert(Budget(category: category, limitAmount: limit, month: month.start))
        }
        // Later months that had their own limit follow the new value too.
        for later in mine where later.month > month.start.addingTimeInterval(43_200) {
            context.delete(later)
        }
        try context.save()
    }

    /// Removes a category budget from `month` on.
    func removeBudget(category: TransactionCategory, from month: MoneyMonth) throws {
        let all = (try? context.fetch(FetchDescriptor<Budget>())) ?? []
        let mine = all.filter { $0.category?.id == category.id }
        let earlier = mine.filter { $0.month < month.start.addingTimeInterval(-43_200) }
        for record in mine where !earlier.contains(where: { $0.id == record.id }) {
            context.delete(record)
        }
        if !earlier.isEmpty {
            // Stop the rollover from this month on.
            context.insert(Budget(category: category, limitAmount: 0, month: month.start))
        }
        try context.save()
    }

    // MARK: Goals

    func addToGoal(_ goal: Goal, amount: Decimal) throws {
        goal.manualSaved = max((goal.manualSaved ?? 0) + amount, 0)
        try context.save()
    }

    func deleteGoal(_ goal: Goal) throws {
        context.delete(goal)
        try context.save()
    }

    // MARK: Rules

    func deleteRule(_ rule: RecurringRule) throws {
        context.delete(rule)
        try context.save()
    }

    // MARK: Holdings

    func deleteHolding(_ asset: Asset) throws {
        for trade in asset.transactions ?? [] { context.delete(trade) }
        context.delete(asset)
        try context.save()
    }

    nonisolated enum WriterError: LocalizedError {
        case noAccount

        var errorDescription: String? {
            switch self {
            case .noAccount: return String(localized: "Add an account first.")
            }
        }
    }
}
