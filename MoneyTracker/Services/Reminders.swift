import Foundation
import UserNotifications

/// Local notifications only — nothing leaves the device.
enum Reminders {

    private static let center = UNUserNotificationCenter.current()
    private static let dailyID = "ml.daily"
    private static let billPrefix = "ml.bill."
    private static let budgetPrefix = "ml.budget."

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Asks once; returns whether notifications are allowed.
    @discardableResult
    static func requestPermission() async -> Bool {
        let status = await authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    // MARK: Daily nudge

    static func scheduleDaily(minutesAfterMidnight: Int) {
        center.removePendingNotificationRequests(withIdentifiers: [dailyID])
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Anything to note today?")
        content.body = String(localized: "A few seconds now keeps your daily allowance honest.")
        content.sound = .default
        var components = DateComponents()
        components.hour = minutesAfterMidnight / 60
        components.minute = minutesAfterMidnight % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: dailyID, content: content, trigger: trigger))
    }

    static func cancelDaily() {
        center.removePendingNotificationRequests(withIdentifiers: [dailyID])
    }

    // MARK: Bills

    struct BillNotice {
        let id: UUID
        let title: String
        let amountText: String
        let dueDate: Date
        let daysBefore: Int
        let isIncome: Bool
    }

    /// Replaces all bill reminders with the next occurrence of each bill.
    static func rescheduleBills(_ notices: [BillNotice], now: Date = Date(), calendar: Calendar = .current) async {
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(billPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        for notice in notices.prefix(40) {
            guard notice.daysBefore >= 0,
                  let day = calendar.date(byAdding: .day, value: -notice.daysBefore, to: calendar.startOfDay(for: notice.dueDate)),
                  let fireDate = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day),
                  fireDate > now else { continue }
            let content = UNMutableNotificationContent()
            if notice.isIncome {
                content.title = String(localized: "Money coming: \(notice.title)")
            } else {
                content.title = String(localized: "Bill due: \(notice.title)")
            }
            if notice.daysBefore == 0 {
                content.body = String(localized: "\(notice.amountText) is due today.")
            } else {
                let date = notice.dueDate.formatted(.dateTime.weekday(.wide).day().month(.wide))
                content.body = String(localized: "\(notice.amountText) on \(date).")
            }
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: billPrefix + notice.id.uuidString, content: content, trigger: trigger))
        }
    }

    static func cancelBills() async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(billPrefix) })
    }

    // MARK: Budgets

    static func budgetCrossed(categoryName: String, percent: Int, key: String) {
        let flag = "ml2.notified." + key
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        let content = UNMutableNotificationContent()
        if percent >= 100 {
            content.title = String(localized: "\(categoryName) is over budget")
            content.body = String(localized: "You've used \(percent)% of this month's limit.")
        } else {
            content.title = String(localized: "\(categoryName) is at \(percent)%")
            content.body = String(localized: "Most of this month's \(categoryName) budget is used.")
        }
        content.sound = .default
        center.add(UNNotificationRequest(identifier: budgetPrefix + key, content: content, trigger: nil))
    }
}
