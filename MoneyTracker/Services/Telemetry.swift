import SwiftUI
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

/// Anonymous usage statistics (Google Analytics for Firebase).
///
/// Only *which* features are used is recorded — never amounts, notes, names,
/// categories or anything the person typed. People can turn it off in
/// Settings ▸ Privacy, and `analytics_enabled` in Remote Config switches it
/// off for everyone.
enum Telemetry {

    static var isAllowedByUser: Bool {
        UserDefaults.standard.object(forKey: AppConfig.Keys.analyticsAllowed) as? Bool ?? true
    }

    static var isActive: Bool {
        FirebaseBoot.isConfigured && isAllowedByUser && RemoteDials.shared.bool(.analyticsEnabled)
    }

    static func setAllowed(_ allowed: Bool) {
        UserDefaults.standard.set(allowed, forKey: AppConfig.Keys.analyticsAllowed)
        applyPreferences()
    }

    /// Pushes the current on/off state to the SDK. Advertising-related consent
    /// stays denied: statistics are used for product decisions only.
    static func applyPreferences() {
        #if canImport(FirebaseAnalytics)
        guard FirebaseBoot.isConfigured else { return }
        let active = isActive
        Analytics.setAnalyticsCollectionEnabled(active)
        Analytics.setConsent([
            .analyticsStorage: active ? .granted : .denied,
            .adStorage: .denied,
            .adUserData: .denied,
            .adPersonalization: .denied
        ])
        #endif
    }

    /// Logs one event. Parameter values must be short strings, numbers or booleans.
    static func event(_ name: String, _ parameters: [String: Any] = [:]) {
        #if canImport(FirebaseAnalytics)
        guard isActive else { return }
        Analytics.logEvent(name, parameters: parameters.isEmpty ? nil : parameters)
        #endif
    }

    static func screen(_ name: String) {
        #if canImport(FirebaseAnalytics)
        guard isActive else { return }
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: name,
            AnalyticsParameterScreenClass: name
        ])
        #endif
    }

    static func property(_ name: String, _ value: String?) {
        #if canImport(FirebaseAnalytics)
        guard FirebaseBoot.isConfigured else { return }
        Analytics.setUserProperty(value, forName: name)
        #endif
    }

    /// Coarse profile of how the app is set up (no personal data).
    static func describe(isPro: Bool, home: String, hasPlan: Bool, accounts: Int) {
        property("is_pro", isPro ? "yes" : "no")
        property("home_currency", home)
        property("has_plan", hasPlan ? "yes" : "no")
        property("accounts", bucket(accounts))
        property("lock_on", UserDefaults.standard.bool(forKey: AppConfig.Keys.faceLock) ? "yes" : "no")
        property("theme", UserDefaults.standard.string(forKey: AppConfig.Keys.theme) ?? AppTheme.system.rawValue)
    }

    /// 0, 1, 2–3, 4–9, 10+ — counts are reported as ranges only.
    static func bucket(_ count: Int) -> String {
        switch count {
        case ..<1: return "0"
        case 1: return "1"
        case 2...3: return "2-3"
        case 4...9: return "4-9"
        default: return "10+"
        }
    }
}

extension View {
    /// Records a screen view when the screen appears.
    func trackScreen(_ name: String) -> some View {
        onAppear { Telemetry.screen(name) }
    }
}
