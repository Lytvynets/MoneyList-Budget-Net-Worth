import Foundation

/// App-wide constants. Identifiers here are tied to App Store Connect, iCloud
/// and existing installs — change them only together with those systems.
enum AppConfig {
    static let appStoreID = "6814129229"

    /// The Pro product sold in version 1 — always counts as Pro, whatever
    /// `pro_product_id` says in Remote Config.
    static let legacyProProductID = "com.MoneyList.app.pro.lifetime"

    /// Shared with the widget. The SwiftData store also lives in this container,
    /// so this identifier must never change for existing users.
    static let appGroup = "group.com.finora.app"

    static let appStorePage = URL(string: "https://apps.apple.com/app/id6814129229")!
    static let writeReview = URL(string: "https://apps.apple.com/app/id6814129229?action=write-review")!
    static let urlScheme = "moneylist"

    // MARK: Values that can change without an update (Remote Config)

    static var proProductID: String {
        let id = RemoteDials.shared.string(.proProductID)
        return id.isEmpty ? legacyProProductID : id
    }

    /// Any "Money List Pro" product, including ones added later in App Store Connect.
    static func isProProduct(_ id: String) -> Bool {
        id == legacyProProductID || id == proProductID || id.hasPrefix("com.MoneyList.app.pro")
    }

    static var supportEmail: String { RemoteDials.shared.string(.supportEmail) }
    static var developerPage: URL { RemoteDials.shared.url(.developerURL) ?? appStorePage }
    static var termsURL: URL { RemoteDials.shared.url(.termsURL) ?? appStorePage }
    static var privacyURL: URL { RemoteDials.shared.url(.privacyURL) ?? appStorePage }

    /// Free Twelve Data key for the stock price fallback (kept in Remote Config, not in code).
    static var twelveDataKey: String { RemoteDials.shared.string(.twelveDataKey) }

    static var adsEnabled: Bool { RemoteDials.shared.bool(.adsEnabled) }
    static var bannersEnabled: Bool { adsEnabled && RemoteDials.shared.bool(.adsBannerEnabled) }
    static var interstitialsEnabled: Bool { adsEnabled && RemoteDials.shared.bool(.adsInterstitialEnabled) }

    /// Free users see the Pro screen each time they open the app.
    static var paywallOnOpen: Bool { RemoteDials.shared.bool(.paywallOnOpen) }
    /// Minutes in the background before it shows again on return; 0 = every time.
    static var paywallReturnMinutes: Double { RemoteDials.shared.double(.paywallReturnMinutes) }

    #if DEBUG
    // Google's public test units: clicking your own live ads during development
    // can get an AdMob account limited.
    static var bannerUnitID: String { "ca-app-pub-3940256099942544/2435281174" }
    static var interstitialUnitID: String { "ca-app-pub-3940256099942544/4411468910" }
    #else
    static var bannerUnitID: String { RemoteDials.shared.string(.adsBannerUnitID) }
    static var interstitialUnitID: String { RemoteDials.shared.string(.adsInterstitialUnitID) }
    #endif

    /// What the free version allows. Pro removes every limit.
    enum Free {
        static var accounts: Int { RemoteDials.shared.int(.freeAccounts) }
        static var budgets: Int { RemoteDials.shared.int(.freeBudgets) }
        static var goals: Int { RemoteDials.shared.int(.freeGoals) }
        static var bills: Int { RemoteDials.shared.int(.freeBills) }
        static var holdings: Int { RemoteDials.shared.int(.freeHoldings) }
        static var customCategories: Int { RemoteDials.shared.int(.freeCustomCategories) }
        /// Months of net-worth history visible without Pro.
        static var historyMonths: Int { RemoteDials.shared.int(.freeHistoryMonths) }
    }

    /// UserDefaults keys. The first three are shared with version 1.
    enum Keys {
        static let onboarded = "hasCompletedOnboarding"
        static let faceLock = "biometricLockEnabled"
        static let proCache = "isProUser"
        static let theme = "ml2.theme"
        static let accent = "ml2.accent"
        static let maskAmounts = "ml2.maskAmounts"
        static let maskOnLaunch = "ml2.maskOnLaunch"
        static let dailyReminder = "ml2.dailyReminder"
        static let dailyReminderMinutes = "ml2.dailyReminderMinutes"
        static let billReminders = "ml2.billReminders"
        static let whatsNewSeen = "ml2.whatsNew.2_0"
        static let firstLaunch = "ml2.firstLaunch"
        static let entriesSinceAd = "ml2.ads.entriesSince"
        static let lastAdAt = "ml2.ads.lastShown"
        static let savedEntries = "ml2.stats.savedEntries"
        static let lastReviewAsk = "ml2.review.lastAsk"
        static let paywallShownOnce = "ml2.paywall.shownOnce"
        static let lastUpkeep = "ml2.upkeep.last"
        static let analyticsAllowed = "ml2.analytics.allowed"
        static let noticeDismissed = "ml2.notice.dismissed"
    }
}
