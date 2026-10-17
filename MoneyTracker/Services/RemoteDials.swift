import Foundation
import Observation
#if canImport(FirebaseRemoteConfig)
import FirebaseRemoteConfig
#endif

/// Everything that can change without an app update: API keys, data sources,
/// ads, free limits, the splash and messages. Values come from Firebase Remote
/// Config when Firebase is set up; until the first fetch — or without Firebase —
/// the defaults below are used, so the app always works.
///
/// The same names and defaults are in `Firebase/remote_config_template.json`
/// in the update archive (Remote Config ▸ ⋮ ▸ Publish from a file).
@Observable
final class RemoteDials {

    static let shared = RemoteDials()

    /// Bumped whenever new values are activated; views that read a dial re-render.
    private(set) var revision = 0

    @ObservationIgnored private var started = false
    #if canImport(FirebaseRemoteConfig)
    @ObservationIgnored private var listener: ConfigUpdateListenerRegistration?
    #endif

    enum Key: String, CaseIterable {
        // API keys and data sources
        case twelveDataKey = "twelvedata_api_key"
        case coinGeckoKey = "coingecko_api_key"
        case fxPrimaryURLs = "fx_primary_urls"
        case fxMirrorURLs = "fx_mirror_urls"
        case quoteYahooURL = "quote_yahoo_url"
        case quoteTwelveDataURL = "quote_twelvedata_url"
        case quoteStooqURL = "quote_stooq_url"
        case quoteCoinGeckoURL = "quote_coingecko_url"
        case ratesStaleHours = "rates_stale_hours"
        case quotesRefreshMinutes = "quotes_refresh_minutes"
        // Ads
        case adsEnabled = "ads_enabled"
        case adsBannerEnabled = "ads_banner_enabled"
        case adsInterstitialEnabled = "ads_interstitial_enabled"
        case adsBannerUnitID = "ads_banner_unit_id"
        case adsInterstitialUnitID = "ads_interstitial_unit_id"
        case adsInterstitialEveryEntries = "ads_interstitial_every_entries"
        case adsInterstitialMinSeconds = "ads_interstitial_min_seconds"
        case adsGraceDays = "ads_grace_days"
        // Pro and the free version
        case proProductID = "pro_product_id"
        case paywallAfterOnboarding = "paywall_after_onboarding"
        case paywallOnOpen = "paywall_on_open"
        case paywallReturnMinutes = "paywall_return_minutes"
        case freeAccounts = "free_accounts"
        case freeBudgets = "free_budgets"
        case freeGoals = "free_goals"
        case freeBills = "free_bills"
        case freeHoldings = "free_holdings"
        case freeCustomCategories = "free_custom_categories"
        case freeHistoryMonths = "free_history_months"
        // Experience
        case splashEnabled = "splash_enabled"
        case splashSeconds = "splash_seconds"
        case reviewAfterEntries = "review_after_entries"
        case reviewMinDaysBetween = "review_min_days_between"
        case analyticsEnabled = "analytics_enabled"
        // Messages
        case noticeTextEN = "notice_text_en"
        case noticeTextUK = "notice_text_uk"
        case noticeURL = "notice_url"
        case latestVersion = "latest_version"
        // Links
        case supportEmail = "support_email"
        case termsURL = "terms_url"
        case privacyURL = "privacy_url"
        case developerURL = "developer_url"
    }

    /// In-app default (as Remote Config text) and the accepted range for numbers.
    struct Spec {
        let value: String
        var range: ClosedRange<Double>? = nil
    }

    static func spec(_ key: Key) -> Spec {
        switch key {
        case .twelveDataKey: return Spec(value: "")
        case .coinGeckoKey: return Spec(value: "")
        case .fxPrimaryURLs:
            return Spec(value: #"["https://api.frankfurter.dev/v2/rates?base=USD","https://api.frankfurter.dev/v1/latest?base=USD"]"#)
        case .fxMirrorURLs:
            return Spec(value: #"["https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json","https://latest.currency-api.pages.dev/v1/currencies/usd.min.json"]"#)
        case .quoteYahooURL: return Spec(value: "https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?range=1d&interval=1d")
        case .quoteTwelveDataURL: return Spec(value: "https://api.twelvedata.com/price?symbol={symbol}&apikey={key}")
        case .quoteStooqURL: return Spec(value: "https://stooq.com/q/l/?s={symbol}&f=sd2t2ohlcv&h&e=csv")
        case .quoteCoinGeckoURL: return Spec(value: "https://api.coingecko.com/api/v3/simple/price?ids={id}&vs_currencies=usd")
        case .ratesStaleHours: return Spec(value: "6", range: 1...168)
        case .quotesRefreshMinutes: return Spec(value: "30", range: 5...1440)

        case .adsEnabled: return Spec(value: "true")
        case .adsBannerEnabled: return Spec(value: "true")
        case .adsInterstitialEnabled: return Spec(value: "true")
        case .adsBannerUnitID: return Spec(value: "ca-app-pub-4749079164629106/4857387575")
        case .adsInterstitialUnitID: return Spec(value: "ca-app-pub-4749079164629106/1221394895")
        case .adsInterstitialEveryEntries: return Spec(value: "6", range: 2...100)
        case .adsInterstitialMinSeconds: return Spec(value: "240", range: 60...86_400)
        case .adsGraceDays: return Spec(value: "2", range: 0...60)

        case .proProductID: return Spec(value: AppConfig.legacyProProductID)
        case .paywallAfterOnboarding: return Spec(value: "true")
        case .paywallOnOpen: return Spec(value: "true")
        case .paywallReturnMinutes: return Spec(value: "0", range: 0...1440)
        case .freeAccounts: return Spec(value: "3", range: 1...100)
        case .freeBudgets: return Spec(value: "3", range: 1...100)
        case .freeGoals: return Spec(value: "2", range: 1...100)
        case .freeBills: return Spec(value: "3", range: 1...100)
        case .freeHoldings: return Spec(value: "2", range: 1...100)
        case .freeCustomCategories: return Spec(value: "4", range: 0...100)
        case .freeHistoryMonths: return Spec(value: "3", range: 1...120)

        case .splashEnabled: return Spec(value: "true")
        case .splashSeconds: return Spec(value: "3", range: 0.8...6)
        case .reviewAfterEntries: return Spec(value: "12", range: 3...500)
        case .reviewMinDaysBetween: return Spec(value: "120", range: 30...365)
        case .analyticsEnabled: return Spec(value: "true")

        case .noticeTextEN: return Spec(value: "")
        case .noticeTextUK: return Spec(value: "")
        case .noticeURL: return Spec(value: "")
        case .latestVersion: return Spec(value: "")

        case .supportEmail: return Spec(value: "vladlytvynets7@gmail.com")
        case .termsURL:
            return Spec(value: "https://docs.google.com/document/d/19i5QZ8AGyji51fOho9YbVIFt3ETBVZtZ/edit?usp=share_link&ouid=114599015370342281433&rtpof=true&sd=true")
        case .privacyURL:
            return Spec(value: "https://docs.google.com/document/d/1I7YctWHf1yq1XbwMsQTIv-v4-3drWZeD/edit?usp=share_link&ouid=114599015370342281433&rtpof=true&sd=true")
        case .developerURL: return Spec(value: "https://apps.apple.com/developer/id1660079103")
        }
    }

    // MARK: Reading

    func string(_ key: Key) -> String {
        if let raw = remote(key) { return raw.trimmingCharacters(in: .whitespacesAndNewlines) }
        return Self.spec(key).value
    }

    func bool(_ key: Key) -> Bool {
        if let raw = remote(key), let flag = Self.flag(raw) { return flag }
        return Self.flag(Self.spec(key).value) ?? false
    }

    func int(_ key: Key) -> Int { Int(double(key).rounded()) }

    func double(_ key: Key) -> Double {
        let spec = Self.spec(key)
        let fallback = Double(spec.value) ?? 0
        guard let raw = remote(key), let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else {
            return fallback
        }
        guard let range = spec.range else { return value }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// A list given as a JSON array (or one item per line); invalid input falls back to the default.
    func list(_ key: Key) -> [String] {
        if let raw = remote(key) {
            let parsed = Self.parseList(raw)
            if !parsed.isEmpty { return parsed }
        }
        return Self.parseList(Self.spec(key).value)
    }

    func url(_ key: Key) -> URL? {
        if let candidate = URL(string: string(key)), candidate.scheme?.hasPrefix("http") == true { return candidate }
        return URL(string: Self.spec(key).value)
    }

    /// Fills `{symbol}`-style placeholders; falls back to the default template
    /// when the remote one is not a usable URL.
    func url(_ key: Key, filling values: [String: String]) -> URL? {
        func fill(_ template: String) -> URL? {
            var text = template
            for (name, value) in values { text = text.replacingOccurrences(of: "{\(name)}", with: value) }
            guard let url = URL(string: text), url.scheme?.hasPrefix("http") == true else { return nil }
            return url
        }
        return fill(string(key)) ?? fill(Self.spec(key).value)
    }

    private func remote(_ key: Key) -> String? {
        _ = revision
        #if canImport(FirebaseRemoteConfig)
        guard FirebaseBoot.isConfigured else { return nil }
        let value = RemoteConfig.remoteConfig().configValue(forKey: key.rawValue)
        guard value.source == .remote else { return nil }
        return value.stringValue
        #else
        return nil
        #endif
    }

    private static func flag(_ raw: String) -> Bool? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes", "on": return true
        case "false", "0", "no", "off": return false
        default: return nil
        }
    }

    private static func parseList(_ raw: String) -> [String] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("["), let data = text.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return array.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return text.split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: Fetching

    /// Activates the newest values and keeps listening for real-time changes.
    func start() async {
        #if canImport(FirebaseRemoteConfig)
        guard FirebaseBoot.isConfigured, !started else { return }
        started = true
        let config = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        #if DEBUG
        settings.minimumFetchInterval = 0
        #else
        settings.minimumFetchInterval = 3600
        #endif
        settings.fetchTimeout = 20
        config.configSettings = settings
        do {
            _ = try await config.fetchAndActivate()
        } catch {
            print("Money List: remote settings not fetched — \(error.localizedDescription)")
        }
        revision += 1
        Telemetry.applyPreferences()
        listener = Self.listen {
            Task { @MainActor in
                RemoteDials.shared.revision += 1
                Telemetry.applyPreferences()
            }
        }
        #endif
    }

    #if canImport(FirebaseRemoteConfig)
    /// Built outside the main actor: Firebase calls these handlers on its own queue.
    nonisolated private static func listen(onChange: @escaping @Sendable () -> Void) -> ConfigUpdateListenerRegistration {
        RemoteConfig.remoteConfig().addOnConfigUpdateListener { update, error in
            guard error == nil, update != nil else { return }
            RemoteConfig.remoteConfig().activate { _, _ in onChange() }
        }
    }
    #endif
}
