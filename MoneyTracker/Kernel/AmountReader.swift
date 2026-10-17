import Foundation

/// Reads money amounts the way people actually type them:
/// "1 234,56", "1,234.56", "12,5", "₴120", "4.99$", "120 uah", "12+8*2".
nonisolated enum AmountReader {

    // MARK: Currency hints

    /// Symbols and words that identify a currency inside free text.
    static let currencyAliases: [String: String] = [
        "$": "USD", "us$": "USD", "usd": "USD", "дол": "USD", "долар": "USD", "доларів": "USD", "бакс": "USD", "баксів": "USD",
        "€": "EUR", "eur": "EUR", "euro": "EUR", "євро": "EUR", "евро": "EUR",
        "₴": "UAH", "uah": "UAH", "грн": "UAH", "грн.": "UAH", "гривень": "UAH", "гривні": "UAH", "гривня": "UAH",
        "£": "GBP", "gbp": "GBP",
        "zł": "PLN", "zl": "PLN", "pln": "PLN", "злотих": "PLN",
        "¥": "JPY", "jpy": "JPY", "cny": "CNY", "rmb": "CNY", "元": "CNY",
        "₽": "RUB", "rub": "RUB",
        "₸": "KZT", "kzt": "KZT",
        "₹": "INR", "inr": "INR",
        "₺": "TRY", "try": "TRY",
        "kč": "CZK", "czk": "CZK",
        "chf": "CHF", "cad": "CAD", "c$": "CAD", "aud": "AUD", "a$": "AUD",
        "sek": "SEK", "nok": "NOK", "dkk": "DKK", "huf": "HUF", "ft": "HUF",
        "ron": "RON", "lei": "RON", "bgn": "BGN", "лв": "BGN", "gel": "GEL", "₾": "GEL",
        "mdl": "MDL", "ils": "ILS", "₪": "ILS", "aed": "AED", "sar": "SAR",
        "₩": "KRW", "krw": "KRW", "brl": "BRL", "r$": "BRL", "mxn": "MXN",
        "sgd": "SGD", "hkd": "HKD", "nzd": "NZD", "zar": "ZAR", "thb": "THB", "฿": "THB",
        "₫": "VND", "vnd": "VND", "₦": "NGN", "ngn": "NGN", "egp": "EGP", "idr": "IDR", "php": "PHP", "₱": "PHP"
    ]

    /// Symbols that may be glued to a number ("₴120", "4.99$").
    static let attachedSymbols: [String] = ["us$", "c$", "a$", "r$", "zł", "kč", "$", "€", "₴", "£", "¥", "₽", "₸", "₹", "₺", "₾", "₪", "₩", "฿", "₫", "₦", "₱"]

    /// Returns an ISO code for a currency word/symbol, if recognised.
    /// `homeCurrency` resolves ambiguous symbols ($ for CAD users, ¥ for CNY users).
    static func currency(for token: String, homeCurrency: String? = nil) -> String? {
        let key = token.lowercased()
        guard let code = currencyAliases[key] else {
            let upper = token.uppercased()
            if upper.count == 3, upper.allSatisfy({ $0.isASCII && $0.isLetter }), knownISO.contains(upper) {
                return upper
            }
            return nil
        }
        if let home = homeCurrency {
            if key == "$", dollarFamily.contains(home) { return home }
            if key == "¥", home == "CNY" { return "CNY" }
        }
        return code
    }

    static let dollarFamily: Set<String> = ["USD", "CAD", "AUD", "NZD", "SGD", "HKD", "MXN", "TWD"]

    static let knownISO: Set<String> = {
        var codes = Set(Locale.commonISOCurrencyCodes)
        codes.formUnion(["UAH", "USD", "EUR", "GBP", "PLN"])
        return codes
    }()

    // MARK: Plain numbers

    /// Parses a single number written with any common grouping/decimal style.
    static func number(_ raw: String) -> Decimal? {
        var ascii = ""
        for character in raw {
            if let digit = character.wholeNumberValue, character.isNumber {
                ascii.append(String(digit))
            } else if character == "." || character == "," {
                ascii.append(character)
            } else if character == " " || character == "\u{00A0}" || character == "\u{202F}" || character == "'" || character == "’" || character == "_" {
                continue
            } else {
                return nil
            }
        }
        guard ascii.contains(where: { $0.isNumber }) else { return nil }

        let dotCount = ascii.filter { $0 == "." }.count
        let commaCount = ascii.filter { $0 == "," }.count
        var normalized: String

        if dotCount == 0 && commaCount == 0 {
            normalized = ascii
        } else if dotCount > 0 && commaCount > 0 {
            let lastDot = ascii.lastIndex(of: ".")!
            let lastComma = ascii.lastIndex(of: ",")!
            let decimalMark: Character = lastDot > lastComma ? "." : ","
            let groupMark: Character = decimalMark == "." ? "," : "."
            normalized = ascii.filter { $0 != groupMark }
            normalized = normalized.replacingOccurrences(of: String(decimalMark), with: ".")
            if normalized.filter({ $0 == "." }).count > 1 { return nil }
        } else {
            let mark: Character = dotCount > 0 ? "." : ","
            let pieces = ascii.split(separator: mark, omittingEmptySubsequences: false).map(String.init)
            if pieces.count > 2 {
                let tail = pieces.last ?? ""
                if tail.count == 3 {
                    normalized = pieces.joined()
                } else {
                    normalized = pieces.dropLast().joined() + "." + tail
                }
            } else {
                let head = pieces[0]
                let tail = pieces[1]
                if tail.count == 3 && !head.isEmpty && head != "0" && head.count <= 3 {
                    normalized = head + tail
                } else {
                    normalized = head + "." + tail
                }
            }
        }

        if normalized.hasPrefix(".") { normalized = "0" + normalized }
        if normalized.hasSuffix(".") { normalized.removeLast() }
        guard !normalized.isEmpty, normalized.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return nil }
        return Decimal(string: normalized, locale: Decimals.posix)
    }

    // MARK: Calculator

    nonisolated enum Operator: Character {
        case plus = "+", minus = "-", times = "*", divide = "/"

        var precedence: Int { self == .plus || self == .minus ? 1 : 2 }

        static func from(_ character: Character) -> Operator? {
            switch character {
            case "+": return .plus
            case "-", "−", "–": return .minus
            case "*", "×", "·": return .times
            case "/", "÷", ":": return .divide
            default: return nil
            }
        }
    }

    private nonisolated enum Piece {
        case value(Decimal)
        case op(Operator)
    }

    /// Evaluates "12+8", "3×4.5", "100-15%"... (percent is not supported, kept simple).
    /// A leading sign is ignored here; callers interpret it as income/expense.
    static func evaluate(_ expression: String) -> Decimal? {
        var text = expression.trimmingCharacters(in: .whitespaces)
        while let first = text.first, first == "+" || Operator.from(first) == .minus {
            text.removeFirst()
        }
        guard !text.isEmpty else { return nil }

        var pieces: [Piece] = []
        var buffer = ""
        for character in text {
            if let op = Operator.from(character) {
                // "1,5" uses ',' as decimal mark; ':' only counts as divide between numbers.
                guard let value = number(buffer) else { return nil }
                pieces.append(.value(value))
                pieces.append(.op(op))
                buffer = ""
            } else {
                buffer.append(character)
            }
        }
        guard let last = number(buffer) else {
            // Allow a trailing operator while typing ("12+") by dropping it.
            if case .op = pieces.last { pieces.removeLast() }
            return reduce(pieces)
        }
        pieces.append(.value(last))
        return reduce(pieces)
    }

    private static func reduce(_ pieces: [Piece]) -> Decimal? {
        guard !pieces.isEmpty else { return nil }
        // Shunting-yard over the flat list.
        var output: [Decimal] = []
        var operators: [Operator] = []

        func apply(_ op: Operator) -> Bool {
            guard output.count >= 2 else { return false }
            let rhs = output.removeLast()
            let lhs = output.removeLast()
            switch op {
            case .plus: output.append(lhs + rhs)
            case .minus: output.append(lhs - rhs)
            case .times: output.append(lhs * rhs)
            case .divide:
                guard rhs != 0 else { return false }
                output.append(lhs / rhs)
            }
            return true
        }

        for piece in pieces {
            switch piece {
            case .value(let value):
                output.append(value)
            case .op(let op):
                while let top = operators.last, top.precedence >= op.precedence {
                    operators.removeLast()
                    guard apply(top) else { return nil }
                }
                operators.append(op)
            }
        }
        while let top = operators.popLast() {
            guard apply(top) else { return nil }
        }
        guard output.count == 1, let result = output.first else { return nil }
        return Decimals.rounded(result, scale: 8)
    }

    /// True when a string looks like a number or a small arithmetic expression.
    static func looksNumeric(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        let allowed: (Character) -> Bool = { c in
            c.isNumber || ".,'’ +-−–*×·/÷".contains(c)
        }
        guard text.allSatisfy(allowed) else { return false }
        return first.isNumber || first == "+" || first == "-" || first == "−" || text.contains(where: { $0.isNumber })
    }

    // MARK: Free-form amount with currency

    nonisolated struct Reading: Equatable {
        var amount: Decimal
        var currencyCode: String?
        var explicitSign: Sign?

        nonisolated enum Sign: Equatable { case plus, minus }
    }

    /// Reads something like "₴120", "120 грн", "+2 000,50", "$4.99", "12+8".
    static func read(_ raw: String, homeCurrency: String? = nil) -> Reading? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        var sign: Reading.Sign?
        if let first = text.first {
            if first == "+" { sign = .plus; text.removeFirst() }
            else if first == "-" || first == "−" || first == "–" { sign = .minus; text.removeFirst() }
        }
        text = text.trimmingCharacters(in: .whitespaces)

        var currency: String?
        let lower = text.lowercased()
        for symbol in attachedSymbols {
            if lower.hasPrefix(symbol) {
                currency = AmountReader.currency(for: symbol, homeCurrency: homeCurrency)
                text = String(text.dropFirst(symbol.count)).trimmingCharacters(in: .whitespaces)
                break
            }
            if lower.hasSuffix(symbol) {
                currency = AmountReader.currency(for: symbol, homeCurrency: homeCurrency)
                text = String(text.dropLast(symbol.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        if currency == nil {
            // Trailing or leading word: "120 uah", "uah 120", "120грн"
            let parts = text.split(whereSeparator: { $0 == " " }).map(String.init)
            if parts.count >= 2 {
                if let code = AmountReader.currency(for: parts.last!, homeCurrency: homeCurrency) {
                    currency = code
                    text = parts.dropLast().joined(separator: " ")
                } else if let code = AmountReader.currency(for: parts.first!, homeCurrency: homeCurrency) {
                    currency = code
                    text = parts.dropFirst().joined(separator: " ")
                }
            } else {
                // glued letters: "120uah", "120грн"
                let digitsEnd = text.lastIndex(where: { $0.isNumber })
                if let end = digitsEnd, end < text.index(before: text.endIndex) {
                    let suffix = String(text[text.index(after: end)...])
                    if let code = AmountReader.currency(for: suffix, homeCurrency: homeCurrency) {
                        currency = code
                        text = String(text[...end])
                    }
                }
            }
        }

        // A trailing "+" ("salary 2000+") marks income too.
        if text.hasSuffix("+"), sign == nil, text.dropLast().allSatisfy({ $0.isNumber || ".,' ".contains($0) }) {
            sign = .plus
            text.removeLast()
        }

        guard looksNumeric(text), let value = evaluate(text) else { return nil }
        return Reading(amount: Decimals.abs(value), currencyCode: currency, explicitSign: sign)
    }
}
