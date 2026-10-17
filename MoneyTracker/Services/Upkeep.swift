import Foundation
import SwiftData
import UserNotifications

/// Housekeeping that keeps derived data honest: runs at launch and whenever
/// the app returns to the foreground (throttled).
enum Upkeep {

    private static var running = false

    static func run(context: ModelContext, rates: RateBook, force: Bool = false) async {
        guard !running else { return }
        let defaults = UserDefaults.standard
        if !force, let last = defaults.object(forKey: AppConfig.Keys.lastUpkeep) as? Date, Date().timeIntervalSince(last) < 120 {
            WidgetFeed.schedule(rates: rates)
            return
        }
        running = true
        defer { running = false }
        defaults.set(Date(), forKey: AppConfig.Keys.lastUpkeep)
        if defaults.object(forKey: AppConfig.Keys.firstLaunch) == nil {
            defaults.set(Date(), forKey: AppConfig.Keys.firstLaunch)
        }

        Seeder.removeDuplicates(context: context)
        BalanceKeeper.migrateOpeningBalances(context: context)
        RuleRunner.postDue(context: context)
        RuleRunner.removeDuplicates(context: context)
        BalanceKeeper.recompute(context: context)

        await rates.refreshIfStale()
        await refreshQuotes(context: context, rates: rates)
        BalanceKeeper.recompute(context: context)
        await rescheduleBillReminders(context: context, rates: rates)
        WidgetFeed.refresh(context: context, rates: rates)
    }

    /// Updates holdings with live prices at most every `quotes_refresh_minutes` (30 by default).
    static func refreshQuotes(context: ModelContext, rates: RateBook, force: Bool = false) async {
        guard let assets = try? context.fetch(FetchDescriptor<Asset>()) else { return }
        let interval = RemoteDials.shared.double(.quotesRefreshMinutes) * 60
        var changed = false
        for asset in assets where asset.autoUpdateEnabled && asset.kind.hasLiveQuotes {
            if !force, let stamp = asset.lastFetchedAt, Date().timeIntervalSince(stamp) < interval { continue }
            if let price = try? await QuoteDesk.price(kind: asset.kind, ticker: asset.ticker, currency: asset.currencyCode, rates: rates) {
                asset.lastFetchedPrice = price
                asset.lastFetchedAt = Date()
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    static func rescheduleBillReminders(context: ModelContext, rates: RateBook) async {
        guard UserDefaults.standard.object(forKey: AppConfig.Keys.billReminders) as? Bool ?? true else {
            await Reminders.cancelBills()
            return
        }
        let status = await Reminders.authorizationStatus()
        guard status == .authorized || status == .provisional else { return }
        let rules = (try? context.fetch(FetchDescriptor<RecurringRule>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let notices: [Reminders.BillNotice] = rules
            .filter { $0.isActive && $0.remindsBeforeDue }
            .map { rule in
                let code = accounts.first { $0.id == rule.accountID }?.currencyCode ?? "USD"
                return Reminders.BillNotice(
                    id: rule.id,
                    title: rule.title,
                    amountText: MoneyFormat.plain(rule.amount, code: code),
                    dueDate: rule.nextDueDate,
                    daysBefore: rule.remindDaysBefore,
                    isIncome: rule.kind == .income
                )
            }
        await Reminders.rescheduleBills(notices)
    }

    /// Light refresh after a local change (no network).
    static func afterChange(context: ModelContext, rates: RateBook) {
        BalanceKeeper.recompute(context: context)
        WidgetFeed.schedule(rates: rates)
    }
}
