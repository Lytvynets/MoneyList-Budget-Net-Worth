import Foundation
import SwiftData

/// Default data for first launch, plus clean-up of duplicates that iCloud can
/// create when two devices seed defaults before their first sync.
enum Seeder {

    struct DefaultCategory {
        let name: String
        let icon: String
        let colorHex: String
        let isIncome: Bool
    }

    static var defaultCategories: [DefaultCategory] {
        [
            DefaultCategory(name: String(localized: "Food & Drinks"), icon: "fork.knife", colorHex: InkSwatch.tomato, isIncome: false),
            DefaultCategory(name: String(localized: "Transport"), icon: "car.fill", colorHex: InkSwatch.cobalt, isIncome: false),
            DefaultCategory(name: String(localized: "Shopping"), icon: "bag.fill", colorHex: InkSwatch.plum, isIncome: false),
            DefaultCategory(name: String(localized: "Home"), icon: "house.fill", colorHex: InkSwatch.moss, isIncome: false),
            DefaultCategory(name: String(localized: "Bills & Utilities"), icon: "bolt.fill", colorHex: InkSwatch.ochre, isIncome: false),
            DefaultCategory(name: String(localized: "Subscriptions"), icon: "repeat", colorHex: InkSwatch.sky, isIncome: false),
            DefaultCategory(name: String(localized: "Entertainment"), icon: "gamecontroller.fill", colorHex: InkSwatch.rose, isIncome: false),
            DefaultCategory(name: String(localized: "Health"), icon: "heart.fill", colorHex: InkSwatch.teal, isIncome: false),
            DefaultCategory(name: String(localized: "Education"), icon: "graduationcap.fill", colorHex: InkSwatch.olive, isIncome: false),
            DefaultCategory(name: String(localized: "Travel"), icon: "airplane", colorHex: InkSwatch.sienna, isIncome: false),
            DefaultCategory(name: String(localized: "Other"), icon: "ellipsis.circle.fill", colorHex: InkSwatch.graphite, isIncome: false),
            DefaultCategory(name: String(localized: "Salary"), icon: "banknote.fill", colorHex: InkSwatch.moss, isIncome: true),
            DefaultCategory(name: String(localized: "Freelance"), icon: "laptopcomputer", colorHex: InkSwatch.cobalt, isIncome: true),
            DefaultCategory(name: String(localized: "Gifts"), icon: "gift.fill", colorHex: InkSwatch.rose, isIncome: true),
            DefaultCategory(name: String(localized: "Other income"), icon: "ellipsis.circle.fill", colorHex: InkSwatch.graphite, isIncome: true)
        ]
    }

    /// Creates categories, a first account and a profile when the store is empty.
    @discardableResult
    static func seedIfEmpty(context: ModelContext, currency: String) -> Bool {
        let categoryCount = (try? context.fetchCount(FetchDescriptor<TransactionCategory>())) ?? 0
        let profileCount = (try? context.fetchCount(FetchDescriptor<UserProfile>())) ?? 0
        let accountCount = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        var changed = false

        if categoryCount == 0 {
            var expenseOrder = 0
            var incomeOrder = 0
            for item in defaultCategories {
                let order: Int
                if item.isIncome { order = incomeOrder; incomeOrder += 1 } else { order = expenseOrder; expenseOrder += 1 }
                context.insert(TransactionCategory(name: item.name, iconName: item.icon, colorHex: item.colorHex, isIncome: item.isIncome, isCustom: false, sortOrder: order))
            }
            changed = true
        }
        if accountCount == 0 {
            let wallet = Account(name: String(localized: "Wallet"), kind: .cash, currencyCode: currency, openingBalance: 0, colorHex: InkSwatch.moss)
            wallet.sortIndex = 0
            context.insert(wallet)
            changed = true
        }
        if profileCount == 0 {
            context.insert(UserProfile(currencyCode: currency))
            changed = true
        }
        if changed { try? context.save() }
        return changed
    }

    /// Merges duplicates created by parallel seeding on several devices.
    static func removeDuplicates(context: ModelContext) {
        var changed = false

        // Profiles: keep the one that carries the most personal settings.
        if let profiles = try? context.fetch(FetchDescriptor<UserProfile>()), profiles.count > 1 {
            let keeper = profiles.max { score($0) < score($1) } ?? profiles[0]
            for profile in profiles where profile.id != keeper.id {
                context.delete(profile)
            }
            changed = true
        }

        // Categories with the same name and kind.
        if let categories = try? context.fetch(FetchDescriptor<TransactionCategory>()) {
            let groups = Dictionary(grouping: categories) { category in
                category.kindRaw + "|" + category.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            }
            for (_, group) in groups where group.count > 1 {
                let keeper = group.max { ($0.transactions?.count ?? 0, -$0.sortOrder) < ($1.transactions?.count ?? 0, -$1.sortOrder) } ?? group[0]
                for duplicate in group where duplicate.id != keeper.id {
                    for entry in duplicate.transactions ?? [] { entry.category = keeper }
                    for budget in duplicate.budgets ?? [] { budget.category = keeper }
                    retargetRules(from: duplicate.id, to: keeper.id, context: context)
                    context.delete(duplicate)
                }
                changed = true
            }
        }

        // Untouched starter accounts that got created twice.
        if let accounts = try? context.fetch(FetchDescriptor<Account>()) {
            let starters = accounts.filter { account in
                (account.transactions?.isEmpty ?? true) && (account.incomingTransfers?.isEmpty ?? true)
                    && (account.openingBalance ?? account.balance) == 0 && account.kind == .cash
            }
            let groups = Dictionary(grouping: starters) { $0.name.lowercased() + "|" + $0.currencyCode }
            for (_, group) in groups where group.count > 1 {
                let sorted = group.sorted { $0.createdAt < $1.createdAt }
                for duplicate in sorted.dropFirst() where accounts.count > 1 {
                    context.delete(duplicate)
                    changed = true
                }
            }
        }

        if changed { try? context.save() }
    }

    private static func score(_ profile: UserProfile) -> Int {
        var value = 0
        if profile.monthlyPlan != nil { value += 4 }
        if profile.periodStartDay != nil { value += 2 }
        if profile.name != "You" { value += 1 }
        if profile.defaultCurrencyCode != "USD" { value += 1 }
        return value
    }

    private static func retargetRules(from old: UUID, to new: UUID, context: ModelContext) {
        guard let rules = try? context.fetch(FetchDescriptor<RecurringRule>()) else { return }
        for rule in rules where rule.categoryID == old { rule.categoryID = new }
    }
}
