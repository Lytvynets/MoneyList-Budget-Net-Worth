import Foundation
import SwiftData

/// Balances are derived: opening balance + every entry. The stored
/// `Account.balance` is only a cache, so sync conflicts between devices can
/// never make a balance drift away from its entries.
enum BalanceKeeper {

    /// One-time move from version 1 (running balance) to derived balances.
    /// The opening balance absorbs whatever the old running total was, so the
    /// balance people see does not change.
    static func migrateOpeningBalances(context: ModelContext) {
        guard let accounts = try? context.fetch(FetchDescriptor<Account>()) else { return }
        let pending = accounts.filter { $0.openingBalance == nil }
        guard !pending.isEmpty else { return }
        let entries = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let effects = LedgerMath.netEffects(entries.ledgerLines)
        for account in pending {
            account.openingBalance = account.balance - (effects[account.id] ?? 0)
        }
        try? context.save()
    }

    /// Recomputes every cached balance. Returns true when something changed.
    @discardableResult
    static func recompute(context: ModelContext) -> Bool {
        guard let accounts = try? context.fetch(FetchDescriptor<Account>()) else { return false }
        let entries = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        var openings: [UUID: Decimal] = [:]
        for account in accounts {
            if account.openingBalance == nil { account.openingBalance = account.balance }
            openings[account.id] = account.openingBalance ?? 0
        }
        let balances = LedgerMath.balances(openings: openings, lines: entries.ledgerLines)
        var changed = false
        for account in accounts {
            let value = balances[account.id] ?? 0
            if account.balance != value {
                account.balance = value
                changed = true
            }
        }
        if changed { try? context.save() }
        return changed
    }

    /// Sets a new current balance by moving the opening balance (no fake entries).
    static func setCurrentBalance(_ value: Decimal, for account: Account, context: ModelContext) {
        let entries = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let effect = LedgerMath.netEffects(entries.ledgerLines)[account.id] ?? 0
        account.openingBalance = value - effect
        account.balance = value
    }

    /// Keeps the current balance unchanged after importing past entries.
    static func absorbImportedEffect(_ effect: Decimal, into account: Account) {
        account.openingBalance = (account.openingBalance ?? account.balance) - effect
    }
}
