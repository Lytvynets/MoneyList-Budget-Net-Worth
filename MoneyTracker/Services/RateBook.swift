import Foundation
import Observation

/// Exchange rates relative to USD, from free public sources (no API keys):
/// Frankfurter (central banks) first, then the open currency-api mirrors.
/// Rates are cached on device; a built-in table covers the very first offline launch.
@Observable
final class RateBook {

    private(set) var perUSD: [String: Decimal] = [:]
    private(set) var updatedAt: Date?
    private(set) var isRefreshing = false
    private(set) var usesFallbackTable = false

    private let cacheKey = "ml2.rates.perUSD"
    private let stampKey = "ml2.rates.stamp"
    /// How old cached rates may get (Remote Config: rates_stale_hours).
    private var staleAfter: TimeInterval { RemoteDials.shared.double(.ratesStaleHours) * 3600 }

    init() {
        restore()
        if perUSD.isEmpty {
            perUSD = RateBook.offlineTable
            usesFallbackTable = true
        }
    }

    var isStale: Bool {
        guard let updatedAt else { return true }
        return Date().timeIntervalSince(updatedAt) > staleAfter
    }

    func knows(_ code: String) -> Bool { code.isEmpty || perUSD[code.uppercased()] != nil }

    /// Converts between ISO codes. Unknown codes fall back to the plain amount.
    func convert(_ amount: Decimal, from: String, to: String) -> Decimal {
        let source = from.uppercased()
        let target = to.uppercased()
        if source == target || source.isEmpty || target.isEmpty || amount == 0 { return amount }
        guard let sourceRate = perUSD[source], let targetRate = perUSD[target], sourceRate > 0 else { return amount }
        return amount / sourceRate * targetRate
    }

    func rate(from: String, to: String) -> Decimal? {
        let source = from.uppercased()
        let target = to.uppercased()
        if source == target { return 1 }
        guard let sourceRate = perUSD[source], let targetRate = perUSD[target], sourceRate > 0 else { return nil }
        return targetRate / sourceRate
    }

    /// Price of one unit of a crypto coin in USD, when the rate feed carries it.
    func usdPrice(ofCoin symbol: String) -> Decimal? {
        guard let perDollar = cryptoPerUSD[symbol.lowercased()], perDollar > 0 else { return nil }
        return 1 / perDollar
    }

    private(set) var cryptoPerUSD: [String: Decimal] = [:]

    func refreshIfStale() async {
        if !isStale && !usesFallbackTable { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var merged: [String: Decimal] = [:]
        if let primary = await fetchFrankfurter() { merged = primary }
        if let open = await fetchCurrencyAPI() {
            for (code, value) in open.fiat where merged[code] == nil { merged[code] = value }
            cryptoPerUSD = open.crypto
        }
        guard merged.count > 5 else { return }
        merged["USD"] = 1
        perUSD = merged
        updatedAt = Date()
        usesFallbackTable = false
        persist()
    }

    // MARK: Sources

    private func fetchJSON(_ urlString: String) async -> Any? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
    }

    /// Frankfurter v2 returns rows like {"quote": "EUR", "rate": 0.86}; v1 returns {"rates": {...}}.
    /// Sources come from Remote Config (fx_primary_urls), tried in order.
    private func fetchFrankfurter() async -> [String: Decimal]? {
        for source in RemoteDials.shared.list(.fxPrimaryURLs) {
            if let json = await fetchJSON(source), let parsed = RateBook.parseRates(json, base: "usd") {
                return parsed
            }
        }
        return nil
    }

    private func fetchCurrencyAPI() async -> (fiat: [String: Decimal], crypto: [String: Decimal])? {
        for mirror in RemoteDials.shared.list(.fxMirrorURLs) {
            guard let json = await fetchJSON(mirror) as? [String: Any], let table = json["usd"] as? [String: Any] else { continue }
            var fiat: [String: Decimal] = [:]
            var crypto: [String: Decimal] = [:]
            for (key, value) in table {
                guard let number = RateBook.number(value), number > 0 else { continue }
                let upper = key.uppercased()
                if upper.count == 3, AmountReader.knownISO.contains(upper) {
                    fiat[upper] = number
                } else {
                    crypto[key.lowercased()] = number
                }
            }
            if fiat.count > 20 { return (fiat, crypto) }
        }
        return nil
    }

    static func parseRates(_ json: Any, base: String) -> [String: Decimal]? {
        var result: [String: Decimal] = [:]
        if let rows = json as? [[String: Any]] {
            for row in rows {
                let rawRate: Any = row["rate"] ?? row["value"] ?? NSNull()
                guard let quote = (row["quote"] as? String) ?? (row["currency"] as? String),
                      let rate = number(rawRate), rate > 0 else { continue }
                result[quote.uppercased()] = rate
            }
        } else if let object = json as? [String: Any] {
            if let rates = object["rates"] as? [String: Any] {
                for (code, value) in rates { if let rate = number(value), rate > 0 { result[code.uppercased()] = rate } }
            } else if let rows = object["rates"] as? [[String: Any]] {
                return parseRates(rows, base: base)
            } else if let table = object[base] as? [String: Any] {
                for (code, value) in table { if let rate = number(value), rate > 0 { result[code.uppercased()] = rate } }
            }
        }
        return result.count > 5 ? result : nil
    }

    static func number(_ value: Any) -> Decimal? {
        if let double = value as? Double { return Decimals.fromDouble(double) }
        if let int = value as? Int { return Decimal(int) }
        if let string = value as? String { return Decimal(string: string, locale: Decimals.posix) }
        if let number = value as? NSNumber { return Decimals.fromDouble(number.doubleValue) }
        return nil
    }

    // MARK: Cache

    private func persist() {
        let flat = perUSD.mapValues { NSDecimalNumber(decimal: $0).stringValue }
        let crypto = cryptoPerUSD.mapValues { NSDecimalNumber(decimal: $0).stringValue }
        UserDefaults.standard.set(flat, forKey: cacheKey)
        UserDefaults.standard.set(crypto, forKey: cacheKey + ".crypto")
        UserDefaults.standard.set(updatedAt, forKey: stampKey)
    }

    private func restore() {
        if let flat = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] {
            perUSD = flat.compactMapValues { Decimal(string: $0, locale: Decimals.posix) }
        }
        if let crypto = UserDefaults.standard.dictionary(forKey: cacheKey + ".crypto") as? [String: String] {
            cryptoPerUSD = crypto.compactMapValues { Decimal(string: $0, locale: Decimals.posix) }
        }
        updatedAt = UserDefaults.standard.object(forKey: stampKey) as? Date
    }

    /// Approximate mid-2026 rates, used only until the first successful download.
    static let offlineTable: [String: Decimal] = {
        let table: [String: String] = [
            "USD": "1", "EUR": "0.86", "GBP": "0.74", "UAH": "41.5", "PLN": "3.66", "CZK": "21.2", "CHF": "0.80",
            "JPY": "147", "CAD": "1.37", "AUD": "1.53", "NZD": "1.67", "CNY": "7.18", "INR": "86.5", "TRY": "40.5",
            "SEK": "9.6", "NOK": "10.1", "DKK": "6.42", "HUF": "343", "RON": "4.37", "BGN": "1.68", "MXN": "18.8",
            "BRL": "5.5", "KRW": "1385", "SGD": "1.28", "HKD": "7.85", "ZAR": "17.8", "ILS": "3.38", "AED": "3.6725",
            "SAR": "3.75", "KZT": "520", "GEL": "2.71", "MDL": "17.1", "THB": "32.6", "IDR": "16300", "PHP": "57",
            "VND": "26100", "EGP": "49", "NGN": "1530", "CLP": "950", "COP": "4000", "ARS": "1250", "RUB": "80",
            "TWD": "29.5", "MYR": "4.25", "ISK": "122", "RSD": "100.5", "AZN": "1.7", "AMD": "387", "UZS": "12600"
        ]
        return table.compactMapValues { Decimal(string: $0, locale: Decimals.posix) }
    }()
}
