import Foundation

// Compiled into both the app and the widget extension.
// Keep it Foundation-only and free of app types.

/// What the widgets show, prepared by the app and stored in the shared App Group.
nonisolated struct GlanceSnapshot: Codable, Equatable {

    nonisolated struct Bill: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var amount: Double
        var currency: String
        var dueDate: Date
        var isIncome: Bool
        var colorHex: String
    }

    nonisolated struct Entry: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var amount: Double
        var currency: String
        var isIncome: Bool
        var date: Date
    }

    var generatedAt: Date
    var currency: String
    var masked: Bool
    var accentHex: String

    // Allowance
    var hasPlan: Bool
    var dailyAllowance: Double
    var spentToday: Double
    var paceDelta: Double
    var daysLeft: Int

    // Month
    var monthSpent: Double
    var monthPlan: Double?
    var dayBars: [Double]
    var todayIndex: Int

    // Worth
    var netWorth: Double
    var netWorthChange: Double
    var worthSpark: [Double]

    var upcoming: [Bill]
    var recent: [Entry]

    var leftToday: Double { dailyAllowance - spentToday }

    static let suiteName = "group.com.finora.app"
    private static let storageKey = "ml2.glance"

    static func load() -> GlanceSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: storageKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(GlanceSnapshot.self, from: data)
    }

    func store() {
        guard let defaults = UserDefaults(suiteName: GlanceSnapshot.suiteName) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(self) {
            defaults.set(data, forKey: GlanceSnapshot.storageKey)
        }
    }

    static var sample: GlanceSnapshot {
        let now = Date()
        return GlanceSnapshot(
            generatedAt: now,
            currency: Locale.current.currency?.identifier ?? "USD",
            masked: false,
            accentHex: "E0532F",
            hasPlan: true,
            dailyAllowance: 42,
            spentToday: 14.5,
            paceDelta: 36,
            daysLeft: 16,
            monthSpent: 812,
            monthPlan: 1500,
            dayBars: [32, 18, 0, 64, 41, 12, 90, 25, 30, 0, 55, 47, 22, 38, 14.5],
            todayIndex: 14,
            netWorth: 18_420,
            netWorthChange: 640,
            worthSpark: [17_100, 17_350, 17_200, 17_600, 17_900, 17_780, 18_100, 18_420],
            upcoming: [
                Bill(id: "a", title: "Rent", amount: 650, currency: "USD", dueDate: now.addingTimeInterval(3 * 86_400), isIncome: false, colorHex: "6E8B3D"),
                Bill(id: "b", title: "Music", amount: 10.99, currency: "USD", dueDate: now.addingTimeInterval(6 * 86_400), isIncome: false, colorHex: "3E8EC2")
            ],
            recent: [
                Entry(id: "1", title: "Coffee", amount: 4.5, currency: "USD", isIncome: false, date: now),
                Entry(id: "2", title: "Groceries", amount: 38.2, currency: "USD", isIncome: false, date: now.addingTimeInterval(-3600))
            ]
        )
    }
}
