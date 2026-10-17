import Foundation

/// Turns a one-line note such as "coffee 4.50", "taxi 120 грн вчора",
/// "+30000 зарплата" or "netflix 9.99 monthly" into a structured draft.
nonisolated struct QuickLine: Equatable {
    var amount: Decimal?
    var currencyCode: String?
    /// `true` = income, `false` = expense, `nil` = not stated.
    var incomeHint: Bool?
    var note: String
    /// `nil` means "now".
    var date: Date?
    var cadence: Cadence?

    var isEmpty: Bool { amount == nil && note.isEmpty }
}

nonisolated enum QuickLineParser {

    static func parse(_ raw: String, homeCurrency: String? = nil, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> QuickLine {
        var result = QuickLine(amount: nil, currencyCode: nil, incomeHint: nil, note: "", date: nil, cadence: nil)
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return result }

        var tokens = mergeThousandGroups(text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init))
        var consumed = Set<Int>()

        // 1. Amount: first numeric-looking token (with optional glued currency).
        for (index, token) in tokens.enumerated() where !consumed.contains(index) {
            if isDateToken(token) { continue }
            if let reading = AmountReader.read(token, homeCurrency: homeCurrency), reading.amount > 0 {
                result.amount = reading.amount
                if let code = reading.currencyCode { result.currencyCode = code }
                if let sign = reading.explicitSign { result.incomeHint = (sign == .plus) }
                consumed.insert(index)
                break
            }
        }

        // 2. Currency as a separate word ("120 uah", "€ 5").
        if result.currencyCode == nil {
            for (index, token) in tokens.enumerated() where !consumed.contains(index) {
                let cleaned = token.trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "$€£¥₴")))
                if cleaned.count <= 6, let code = AmountReader.currency(for: cleaned.isEmpty ? token : cleaned, homeCurrency: homeCurrency) {
                    // Avoid eating ordinary words that happen to be ISO codes ("try" as a verb) unless next to the amount.
                    if cleaned.count == 3, !isNearConsumed(index, consumed: consumed), cleaned != cleaned.uppercased() { continue }
                    result.currencyCode = code
                    consumed.insert(index)
                    break
                }
            }
        }

        // 3. Dates and cadence words.
        let lowered = tokens.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        for (index, word) in lowered.enumerated() where !consumed.contains(index) {
            if let date = relativeDate(word, now: now, calendar: calendar) {
                result.date = date
                consumed.insert(index)
                continue
            }
            if let date = numericDate(tokens[index], now: now, calendar: calendar, locale: locale) {
                result.date = date
                consumed.insert(index)
                continue
            }
            if let cadence = cadenceWord(word) {
                result.cadence = cadence
                consumed.insert(index)
                continue
            }
            if (word == "every" || word == "кожного" || word == "кожен" || word == "кожну" || word == "каждый" || word == "каждого"), index + 1 < lowered.count,
               let cadence = cadenceUnitWord(lowered[index + 1]) {
                result.cadence = cadence
                consumed.insert(index)
                consumed.insert(index + 1)
            }
        }

        // 4. Everything else is the note.
        let noteWords = tokens.enumerated().filter { !consumed.contains($0.offset) }.map(\.element)
        tokens = noteWords
        result.note = noteWords.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,;-–—"))

        if result.incomeHint == nil, looksLikeIncome(result.note) {
            result.incomeHint = true
        }
        return result
    }

    // MARK: Helpers

    /// "1 234,56" arrives as ["1", "234,56"] — glue them back.
    static func mergeThousandGroups(_ tokens: [String]) -> [String] {
        var output: [String] = []
        for token in tokens {
            if let previous = output.last,
               previous.count <= 3, previous.allSatisfy({ $0.isNumber }) || (previous.count <= 4 && previous.dropFirst().allSatisfy({ $0.isNumber }) && "+-−".contains(previous.first!)),
               token.count >= 3, token.prefix(3).allSatisfy({ $0.isNumber }),
               token.count == 3 || ",.".contains(token[token.index(token.startIndex, offsetBy: 3)]) {
                output[output.count - 1] = previous + token
            } else {
                output.append(token)
            }
        }
        return output
    }

    private static func isNearConsumed(_ index: Int, consumed: Set<Int>) -> Bool {
        consumed.contains(index - 1) || consumed.contains(index + 1)
    }

    private static func isDateToken(_ token: String) -> Bool {
        // 12.10 / 12.10.2026 / 2026-10-12 / 12/10
        let pattern = token.filter { $0.isNumber || $0 == "." || $0 == "/" || $0 == "-" }
        guard pattern.count == token.count else { return false }
        if token.contains("/") { return token.split(separator: "/").count >= 2 }
        if token.contains("-") && token.split(separator: "-").count == 3 { return true }
        let parts = token.split(separator: ".")
        // "12.10" could also be an amount (12.10). Treat it as a date only with a year part.
        return parts.count == 3
    }

    static let incomeWords: Set<String> = [
        "salary", "paycheck", "payday", "income", "bonus", "refund", "cashback", "dividend", "dividends", "wage", "wages", "payout", "tips",
        "зарплата", "зарплату", "зарплатня", "зп", "аванс", "премія", "премію", "бонус", "повернення", "кешбек", "дивіденди", "дохід", "чайові", "гонорар",
        "зарплата.", "зарплаты", "премия", "доход", "возврат", "кэшбэк"
    ]

    static func looksLikeIncome(_ note: String) -> Bool {
        let words = Tokenizer.words(note)
        return words.contains { incomeWords.contains($0) }
    }

    static func relativeDate(_ word: String, now: Date, calendar: Calendar) -> Date? {
        let startOfToday = calendar.startOfDay(for: now)
        func daysAgo(_ value: Int) -> Date? {
            guard let day = calendar.date(byAdding: .day, value: -value, to: startOfToday) else { return nil }
            return calendar.date(byAdding: .hour, value: 12, to: day)
        }
        switch word {
        case "today", "сьогодні", "сегодня", "dzisiaj": return now
        case "yesterday", "вчора", "учора", "вчера", "wczoraj": return daysAgo(1)
        case "позавчора", "позавчера", "przedwczoraj": return daysAgo(2)
        default: break
        }
        if let weekday = weekdayIndex(word) {
            let todayWeekday = calendar.component(.weekday, from: now)
            var delta = todayWeekday - weekday
            if delta < 0 { delta += 7 }
            return delta == 0 ? now : daysAgo(delta)
        }
        return nil
    }

    /// Gregorian weekday index (1 = Sunday).
    static func weekdayIndex(_ word: String) -> Int? {
        let map: [String: Int] = [
            "sunday": 1, "sun": 1, "monday": 2, "mon": 2, "tuesday": 3, "tue": 3, "tues": 3, "wednesday": 4, "wed": 4,
            "thursday": 5, "thu": 5, "thurs": 5, "friday": 6, "fri": 6, "saturday": 7, "sat": 7,
            "неділя": 1, "неділю": 1, "понеділок": 2, "вівторок": 3, "середа": 4, "середу": 4, "четвер": 5,
            "пʼятниця": 6, "п'ятниця": 6, "пʼятницю": 6, "п'ятницю": 6, "субота": 7, "суботу": 7,
            "воскресенье": 1, "понедельник": 2, "вторник": 3, "среда": 4, "среду": 4, "четверг": 5, "пятница": 6, "пятницу": 6, "суббота": 7, "субботу": 7
        ]
        return map[word.replacingOccurrences(of: "’", with: "'")]
    }

    static func numericDate(_ token: String, now: Date, calendar: Calendar, locale: Locale) -> Date? {
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
        let currentYear = calendar.component(.year, from: now)
        var day: Int?
        var month: Int?
        var year: Int?

        if trimmed.contains("-") {
            let parts = trimmed.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, parts[0] > 1900 else { return nil }
            (year, month, day) = (parts[0], parts[1], parts[2])
        } else if trimmed.contains(".") {
            let parts = trimmed.split(separator: ".").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            (day, month, year) = (parts[0], parts[1], parts[2])
        } else if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/").compactMap { Int($0) }
            guard parts.count >= 2 else { return nil }
            let monthFirst = prefersMonthFirst(locale)
            if monthFirst && parts[0] <= 12 {
                (month, day) = (parts[0], parts[1])
            } else {
                (day, month) = (parts[0], parts[1])
            }
            if parts.count >= 3 { year = parts[2] }
        } else {
            return nil
        }

        guard let d = day, let m = month, (1...31).contains(d), (1...12).contains(m) else { return nil }
        var y = year ?? currentYear
        if y < 100 { y += 2000 }
        var components = DateComponents()
        components.year = y
        components.month = m
        components.day = d
        components.hour = 12
        guard let date = calendar.date(from: components) else { return nil }
        // No year given and the date lands in the future: the user meant last year.
        if year == nil, date > now, let lastYear = calendar.date(byAdding: .year, value: -1, to: date) {
            return lastYear
        }
        return date
    }

    static func prefersMonthFirst(_ locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: locale) ?? "d/M"
        guard let mIndex = format.firstIndex(of: "M"), let dIndex = format.firstIndex(of: "d") else { return false }
        return mIndex < dIndex
    }

    static func cadenceWord(_ word: String) -> Cadence? {
        switch word {
        case "daily", "щодня", "щоденно", "ежедневно": return Cadence(unit: .day, every: 1)
        case "weekly", "щотижня", "щотижнево", "еженедельно": return Cadence(unit: .week, every: 1)
        case "biweekly", "fortnightly": return Cadence(unit: .week, every: 2)
        case "monthly", "щомісяця", "щомісячно", "ежемесячно", "mensual", "monatlich", "miesięcznie": return Cadence(unit: .month, every: 1)
        case "quarterly", "щокварталу", "щоквартально": return Cadence(unit: .month, every: 3)
        case "yearly", "annually", "annual", "щороку", "щорічно", "ежегодно": return Cadence(unit: .year, every: 1)
        default: return nil
        }
    }

    static func cadenceUnitWord(_ word: String) -> Cadence? {
        switch word {
        case "day", "дня", "день": return Cadence(unit: .day, every: 1)
        case "week", "тижня", "тиждень", "недели", "неделю": return Cadence(unit: .week, every: 1)
        case "month", "місяця", "місяць", "месяца", "месяц": return Cadence(unit: .month, every: 1)
        case "year", "року", "рік", "года", "год": return Cadence(unit: .year, every: 1)
        default: return nil
        }
    }
}

/// Shared word splitter for notes, search and category learning.
nonisolated enum Tokenizer {
    static let stopWords: Set<String> = [
        "the", "a", "an", "at", "for", "in", "on", "of", "to", "and", "with", "from", "my",
        "на", "в", "у", "за", "і", "й", "та", "з", "із", "зі", "до", "по", "для", "від",
        "и", "с", "со", "от", "к", "о"
    ]

    static func words(_ text: String) -> [String] {
        let folded = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "ʼ", with: "'")
        var words: [String] = []
        var current = ""
        for character in folded {
            if character.isLetter || character.isNumber || character == "'" || character == "&" {
                current.append(character)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'&")) }
            .filter { $0.count >= 2 && !stopWords.contains($0) && !$0.allSatisfy({ $0.isNumber }) }
    }
}
