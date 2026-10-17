import Foundation

/// Live prices for holdings from free sources. Stocks: Yahoo chart feed, then
/// Twelve Data, then Stooq. Crypto: the currency feed RateBook already
/// downloads, then CoinGecko.
enum QuoteDesk {

    nonisolated struct Quote: Equatable {
        let price: Decimal
        let currency: String
    }

    nonisolated enum QuoteError: LocalizedError {
        case noSymbol, notFound

        var errorDescription: String? {
            switch self {
            case .noSymbol: return String(localized: "Add a ticker symbol to get live prices.")
            case .notFound: return String(localized: "No price found for this symbol. Check the ticker (for example AAPL, VWCE.DE or BTC).")
            }
        }
    }

    /// Unit price converted into the holding's currency.
    static func price(kind: HoldingKind, ticker: String?, currency: String, rates: RateBook) async throws -> Decimal {
        guard let raw = ticker?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { throw QuoteError.noSymbol }
        let quote: Quote?
        switch kind {
        case .crypto: quote = await crypto(raw, rates: rates)
        case .stock: quote = await stock(raw)
        case .collectible: quote = nil
        }
        guard let quote, quote.price > 0 else { throw QuoteError.notFound }
        return Decimals.rounded(rates.convert(quote.price, from: quote.currency, to: currency), scale: 6)
    }

    // MARK: Stocks

    static func stock(_ ticker: String) async -> Quote? {
        let symbol = ticker.uppercased()
        if let quote = await yahoo(symbol) { return quote }
        if let quote = await twelveData(symbol) { return quote }
        return await stooq(symbol)
    }

    private static func yahoo(_ symbol: String) async -> Quote? {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = RemoteDials.shared.url(.quoteYahooURL, filling: ["symbol": encoded]) else { return nil }
        guard let json = await fetch(url) as? [String: Any],
              let chart = json["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let meta = results.first?["meta"] as? [String: Any],
              let price = RateBook.number(meta["regularMarketPrice"] ?? NSNull()) else { return nil }
        let rawCurrency = (meta["currency"] as? String) ?? "USD"
        // London lines are quoted in pence ("GBp"/"GBX").
        if rawCurrency == "GBp" || rawCurrency.uppercased() == "GBX" {
            return Quote(price: price / 100, currency: "GBP")
        }
        return Quote(price: price, currency: rawCurrency.uppercased())
    }

    private static func twelveData(_ symbol: String) async -> Quote? {
        let key = AppConfig.twelveDataKey
        guard !key.isEmpty,
              let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let safeKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = RemoteDials.shared.url(.quoteTwelveDataURL, filling: ["symbol": encoded, "key": safeKey]) else { return nil }
        guard let json = await fetch(url) as? [String: Any], let price = RateBook.number(json["price"] ?? NSNull()), price > 0 else { return nil }
        return Quote(price: price, currency: "USD")
    }

    private static func stooq(_ symbol: String) async -> Quote? {
        let local = symbol.contains(".") ? symbol.lowercased() : symbol.lowercased() + ".us"
        guard let encoded = local.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = RemoteDials.shared.url(.quoteStooqURL, filling: ["symbol": encoded]) else { return nil }
        guard let data = await fetchData(url), let text = String(data: data, encoding: .utf8) else { return nil }
        let rows = CSVKit.parse(text, delimiter: ",")
        guard rows.count >= 2, let header = rows.first, let closeIndex = header.firstIndex(where: { $0.lowercased() == "close" }),
              closeIndex < rows[1].count, let price = Decimal(string: rows[1][closeIndex], locale: Decimals.posix), price > 0 else { return nil }
        let suffix = local.split(separator: ".").last.map(String.init) ?? "us"
        switch suffix {
        case "uk": return Quote(price: price / 100, currency: "GBP")
        case "de", "fr", "nl", "es", "it": return Quote(price: price, currency: "EUR")
        case "pl": return Quote(price: price, currency: "PLN")
        case "jp": return Quote(price: price, currency: "JPY")
        case "hu": return Quote(price: price, currency: "HUF")
        default: return Quote(price: price, currency: "USD")
        }
    }

    // MARK: Crypto

    static let coinIDs: [String: String] = [
        "BTC": "bitcoin", "ETH": "ethereum", "SOL": "solana", "XRP": "ripple", "ADA": "cardano", "DOGE": "dogecoin",
        "DOT": "polkadot", "MATIC": "matic-network", "POL": "polygon-ecosystem-token", "LTC": "litecoin", "BNB": "binancecoin",
        "AVAX": "avalanche-2", "LINK": "chainlink", "USDT": "tether", "USDC": "usd-coin", "TRX": "tron", "TON": "the-open-network",
        "SHIB": "shiba-inu", "ATOM": "cosmos", "XLM": "stellar", "NEAR": "near", "SUI": "sui", "APT": "aptos", "ARB": "arbitrum",
        "OP": "optimism", "PEPE": "pepe", "XMR": "monero", "BCH": "bitcoin-cash", "ETC": "ethereum-classic", "UNI": "uniswap"
    ]

    static func crypto(_ symbol: String, rates: RateBook) async -> Quote? {
        let upper = symbol.uppercased()
        if let usd = rates.usdPrice(ofCoin: upper) { return Quote(price: usd, currency: "USD") }
        let id = coinIDs[upper] ?? symbol.lowercased()
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = RemoteDials.shared.url(.quoteCoinGeckoURL, filling: ["id": encoded]) else { return nil }
        let demoKey = RemoteDials.shared.string(.coinGeckoKey)
        guard let json = await fetch(url, headers: demoKey.isEmpty ? [:] : ["x-cg-demo-api-key": demoKey]) as? [String: Any],
              let entry = json[id] as? [String: Any],
              let price = RateBook.number(entry["usd"] ?? NSNull()) else { return nil }
        return Quote(price: price, currency: "USD")
    }

    // MARK: Networking

    private static func fetchData(_ url: URL, headers: [String: String] = [:]) async -> Data? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private static func fetch(_ url: URL, headers: [String: String] = [:]) async -> Any? {
        guard let data = await fetchData(url, headers: headers) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
