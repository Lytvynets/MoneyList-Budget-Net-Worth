import Foundation
import SwiftData
import StoreKit
import UIKit

/// Side effects after an entry is saved: widgets, budget alerts, ad pacing, review prompt.
enum AfterSave {

    static func run(entry: Transaction, context: ModelContext, rates: RateBook, pro: ProPass?, ads: AdPacer?) {
        WidgetFeed.schedule(rates: rates)
        checkBudget(for: entry, context: context, rates: rates)
        ads?.entrySaved(isPro: pro?.isPro ?? false)
        ReviewNudge.entrySaved()
    }

    /// Alerts once at 80% and once at 100% of a category budget per month.
    static func checkBudget(for entry: Transaction, context: ModelContext, rates: RateBook) {
        guard entry.kind == .expense, let category = entry.category else { return }
        guard let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first, profile.notificationsEnabled else { return }
        let periods = PeriodCalendar(startDay: profile.periodStartDay ?? 1)
        let month = periods.month(containing: entry.date)
        guard month.contains(Date()) else { return }

        let budgets = (try? context.fetch(FetchDescriptor<Budget>())) ?? []
        let records = budgets.compactMap { budget -> BudgetRecord? in
            guard let id = budget.category?.id else { return nil }
            return BudgetRecord(recordID: budget.id, categoryID: id, month: budget.month, limit: budget.limitAmount)
        }
        guard let record = BudgetMath.effective(records: records, monthStart: month.start)[category.id] else { return }

        let home = profile.defaultCurrencyCode
        let spent = (category.transactions ?? [])
            .filter { $0.kind == .expense && month.contains($0.date) }
            .reduce(Decimal(0)) { $0 + rates.convert($1.amount, from: $1.currencyCode.isEmpty ? home : $1.currencyCode, to: home) }
        let percent = Int((Decimals.rawRatio(spent, of: record.limit) * 100).rounded(.down))
        guard percent >= 80 else { return }
        let bucket = percent >= 100 ? 100 : 80
        let key = "\(category.id.uuidString)-\(Int(month.start.timeIntervalSince1970))-\(bucket)"
        Reminders.budgetCrossed(categoryName: category.name, percent: percent, key: key)
    }
}

/// Asks for an App Store rating at a calm, earned moment (never more than every 4 months).
enum ReviewNudge {
    static func entrySaved() {
        let defaults = UserDefaults.standard
        let saved = defaults.integer(forKey: AppConfig.Keys.savedEntries) + 1
        defaults.set(saved, forKey: AppConfig.Keys.savedEntries)

        guard saved >= RemoteDials.shared.int(.reviewAfterEntries) else { return }
        let firstLaunch = defaults.object(forKey: AppConfig.Keys.firstLaunch) as? Date ?? Date()
        guard Date().timeIntervalSince(firstLaunch) > 3 * 86_400 else { return }
        let spacing = RemoteDials.shared.double(.reviewMinDaysBetween) * 86_400
        if let last = defaults.object(forKey: AppConfig.Keys.lastReviewAsk) as? Date, Date().timeIntervalSince(last) < spacing { return }
        defaults.set(Date(), forKey: AppConfig.Keys.lastReviewAsk)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) else { return }
            AppStore.requestReview(in: scene)
            Telemetry.event("review_prompt")
        }
    }
}
