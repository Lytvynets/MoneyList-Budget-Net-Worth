import Foundation
import SwiftData

/// Posts repeating bills/incomes when they fall due and answers "what's coming".
enum RuleRunner {

    struct Upcoming: Identifiable {
        let id: String
        let rule: RecurringRule
        let date: Date
    }

    /// Creates entries for every auto-posting rule that is due by the end of today.
    @discardableResult
    static func postDue(context: ModelContext, now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let rules = try? context.fetch(FetchDescriptor<RecurringRule>()) else { return 0 }
        let active = rules.filter { $0.isActive && $0.autoPost }
        guard !active.isEmpty else { return 0 }

        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let categories = (try? context.fetch(FetchDescriptor<TransactionCategory>())) ?? []
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return 0 }

        var posted = 0
        for rule in active {
            var guardCounter = 0
            while rule.nextDueDate < endOfToday && guardCounter < 36 {
                if let end = rule.endDate, rule.nextDueDate > end {
                    rule.isActive = false
                    break
                }
                makeEntry(for: rule, date: rule.nextDueDate, accounts: accounts, categories: categories, profile: profile, context: context)
                advance(rule, calendar: calendar)
                posted += 1
                guardCounter += 1
            }
        }
        if posted > 0 { try? context.save() }
        return posted
    }

    /// Records the next occurrence now (for rules that ask before posting).
    @discardableResult
    static func markPaid(_ rule: RecurringRule, context: ModelContext, calendar: Calendar = .current) -> Transaction? {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let categories = (try? context.fetch(FetchDescriptor<TransactionCategory>())) ?? []
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        let entry = makeEntry(for: rule, date: min(rule.nextDueDate, Date()), accounts: accounts, categories: categories, profile: profile, context: context)
        advance(rule, calendar: calendar)
        try? context.save()
        return entry
    }

    static func skip(_ rule: RecurringRule, context: ModelContext, calendar: Calendar = .current) {
        advance(rule, calendar: calendar)
        try? context.save()
    }

    static func advance(_ rule: RecurringRule, calendar: Calendar = .current) {
        rule.cycleIndex += 1
        rule.nextDueDate = rule.occurrence(rule.cycleIndex, calendar: calendar)
        if let end = rule.endDate, rule.nextDueDate > end { rule.isActive = false }
    }

    /// Re-anchors a rule after its schedule was edited.
    static func reschedule(_ rule: RecurringRule, firstDue: Date) {
        rule.anchorDate = firstDue
        rule.cycleIndex = 0
        rule.nextDueDate = firstDue
    }

    @discardableResult
    private static func makeEntry(for rule: RecurringRule, date: Date, accounts: [Account], categories: [TransactionCategory], profile: UserProfile?, context: ModelContext) -> Transaction? {
        let live = accounts.filter { !$0.isArchived }
        let account = accounts.first { $0.id == rule.accountID }
            ?? live.first { $0.id == profile?.defaultAccountID }
            ?? live.first(where: { $0.isSpendable })
            ?? live.first
        guard let account else { return nil }
        let entry = Transaction(kind: rule.kind, amount: rule.amount, date: date, note: rule.title, account: account)
        entry.recurringRuleId = rule.id
        if rule.kind == .transfer {
            entry.toAccount = accounts.first { $0.id == rule.toAccountID }
        } else {
            entry.category = categories.first { $0.id == rule.categoryID }
        }
        context.insert(entry)
        return entry
    }

    /// Two devices may post the same occurrence before syncing; keep one.
    static func removeDuplicates(context: ModelContext, calendar: Calendar = .current) {
        guard let entries = try? context.fetch(FetchDescriptor<Transaction>()) else { return }
        let generated = entries.filter { $0.recurringRuleId != nil }
        let groups = Dictionary(grouping: generated) { entry in
            "\(entry.recurringRuleId!.uuidString)|\(calendar.startOfDay(for: entry.date).timeIntervalSince1970)|\(entry.amount)"
        }
        var changed = false
        for (_, group) in groups where group.count > 1 {
            let sorted = group.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            for duplicate in sorted.dropFirst() {
                context.delete(duplicate)
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    /// Occurrences that have not been posted yet in [from, to).
    static func upcoming(rules: [RecurringRule], from: Date, to: Date, calendar: Calendar = .current) -> [Upcoming] {
        var items: [Upcoming] = []
        for rule in rules where rule.isActive {
            var index = rule.cycleIndex
            for _ in 0..<60 {
                let date = rule.occurrence(index, calendar: calendar)
                if date >= to { break }
                if let end = rule.endDate, date > end { break }
                // The first unposted occurrence is shown even when overdue.
                if date >= from || index == rule.cycleIndex {
                    let key = rule.id.uuidString + "-\(Int(date.timeIntervalSince1970))"
                    items.append(Upcoming(id: key, rule: rule, date: date))
                }
                index += 1
            }
        }
        return items.sorted { $0.date < $1.date }
    }

    /// Overdue occurrences for rules that wait for confirmation.
    static func overdue(rules: [RecurringRule], now: Date = Date()) -> [RecurringRule] {
        rules.filter { $0.isActive && !$0.autoPost && $0.nextDueDate < now }
            .sorted { $0.nextDueDate < $1.nextDueDate }
    }
}
