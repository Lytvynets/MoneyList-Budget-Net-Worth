import Foundation
import SwiftData
import WidgetKit

/// Prepares the widget snapshot after data changes (debounced).
enum WidgetFeed {

    private static var pending: Task<Void, Never>?

    static func schedule(rates: RateBook, delay: Double = 0.8) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            refresh(context: ModelContext(StoreHub.container), rates: rates)
        }
    }

    static func refresh(context: ModelContext, rates: RateBook, now: Date = Date()) {
        do {
            let entries = try context.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
            let accounts = try context.fetch(FetchDescriptor<Account>())
            let rules = try context.fetch(FetchDescriptor<RecurringRule>())
            let budgets = try context.fetch(FetchDescriptor<Budget>())
            let holdings = try context.fetch(FetchDescriptor<Asset>())
            let profile = try context.fetch(FetchDescriptor<UserProfile>()).first
            let home = profile?.defaultCurrencyCode ?? "USD"
            let convert: CurrencyConverter = { amount, from, to in rates.convert(amount, from: from, to: to) }

            let digest = DigestBuilder.build(entries: entries, accounts: accounts, rules: rules, budgets: budgets, holdings: holdings, profile: profile, home: home, convert: convert, now: now)

            // 30-day net worth sparkline.
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            let worthAccounts = accounts.filter { !$0.isArchived }.map {
                WorthAccount(id: $0.id, currency: $0.currencyCode, balanceNow: $0.balance, since: .distantPast)
            }
            let worthHoldings = holdings.map {
                WorthHolding(currency: $0.currencyCode, priceNow: $0.markPrice, changes: HoldingMath.quantityChanges($0.trades))
            }
            let recentEntries = entries.filter { $0.date >= start }
            let series = WorthMath.series(
                accounts: worthAccounts,
                holdings: worthHoldings,
                lines: recentEntries.ledgerLines,
                samples: WorthMath.samples(from: start, to: now, maxPoints: 16),
                convert: { amount, code in convert(amount, code.isEmpty ? home : code, home) }
            )
            let change = (series.last?.value ?? 0) - (series.first?.value ?? 0)

            let defaults = UserDefaults.standard
            let accent = InkAccent(rawValue: defaults.string(forKey: AppConfig.Keys.accent) ?? "") ?? .vermilion

            let snapshot = GlanceSnapshot(
                generatedAt: now,
                currency: home,
                masked: defaults.bool(forKey: AppConfig.Keys.maskAmounts),
                accentHex: accent.hex,
                hasPlan: digest.plan != nil,
                dailyAllowance: Decimals.double(digest.allowance.daily),
                spentToday: Decimals.double(digest.allowance.spentToday),
                paceDelta: Decimals.double(digest.allowance.paceDelta),
                daysLeft: digest.allowance.daysLeft,
                monthSpent: Decimals.double(digest.monthTally.expense),
                monthPlan: digest.plan.map(Decimals.double),
                dayBars: digest.dayBars.map(Decimals.double),
                todayIndex: digest.todayIndex ?? 0,
                netWorth: Decimals.double(digest.netWorth),
                netWorthChange: Decimals.double(change),
                worthSpark: series.map { Decimals.double($0.value) },
                upcoming: digest.upcoming.prefix(5).map { item in
                    let code = item.rule.accountID.flatMap { id in accounts.first { $0.id == id }?.currencyCode } ?? home
                    return GlanceSnapshot.Bill(
                        id: item.id,
                        title: item.rule.title,
                        amount: Decimals.double(item.rule.amount),
                        currency: code,
                        dueDate: item.date,
                        isIncome: item.rule.kind == .income,
                        colorHex: item.rule.colorHex ?? InkSwatch.graphite
                    )
                },
                recent: entries.prefix(4).map { entry in
                    GlanceSnapshot.Entry(
                        id: entry.id.uuidString,
                        title: entry.displayTitle,
                        amount: Decimals.double(entry.amount),
                        currency: entry.currencyCode.isEmpty ? home : entry.currencyCode,
                        isIncome: entry.kind == .income,
                        date: entry.date
                    )
                }
            )
            snapshot.store()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("Money List: widget refresh failed — \(error)")
        }
    }
}
