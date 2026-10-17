import Foundation

/// RFC 4180-ish CSV reading/writing with delimiter detection.
nonisolated enum CSVKit {

    static func escape(_ field: String, delimiter: Character = ",") -> String {
        let needsQuotes = field.contains(delimiter) || field.contains("\"") || field.contains("\n") || field.contains("\r")
            || field.hasPrefix(" ") || field.hasSuffix(" ")
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func write(rows: [[String]], delimiter: Character = ",") -> String {
        rows.map { row in row.map { escape($0, delimiter: delimiter) }.joined(separator: String(delimiter)) }
            .joined(separator: "\r\n") + "\r\n"
    }

    static func detectDelimiter(_ text: String) -> Character {
        let candidates: [Character] = [",", ";", "\t", "|"]
        let sample = text.split(separator: "\n", maxSplits: 12, omittingEmptySubsequences: true).prefix(10)
        var best: Character = ","
        var bestScore = -1
        for candidate in candidates {
            let counts = sample.map { line -> Int in
                var inQuotes = false
                var count = 0
                for character in line {
                    if character == "\"" { inQuotes.toggle() }
                    else if character == candidate && !inQuotes { count += 1 }
                }
                return count
            }
            guard let first = counts.first, first > 0 else { continue }
            let consistent = counts.filter { $0 == first }.count
            let score = consistent * 100 + first
            if score > bestScore { bestScore = score; best = candidate }
        }
        return best
    }

    static func parse(_ rawText: String, delimiter: Character? = nil) -> [[String]] {
        var text = rawText
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let separator = delimiter ?? detectDelimiter(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if inQuotes {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex && text[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                if character == "\"" && field.isEmpty {
                    inQuotes = true
                } else if character == separator {
                    row.append(field)
                    field = ""
                } else if character == "\n" || character == "\r\n" {
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                } else if character == "\r" {
                    // Old Mac line endings or stray CR.
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                } else {
                    field.append(character)
                }
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
            .map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { !$0.allSatisfy { $0.isEmpty } }
    }
}

/// Figures out which column means what in a CSV exported by another app or bank.
nonisolated enum ImportRole: String, CaseIterable, Identifiable {
    case ignore, date, amount, outflow, inflow, kind, category, note, account, currency
    var id: String { rawValue }
}

nonisolated struct ImportPlan: Equatable {
    var hasHeader: Bool
    var roles: [ImportRole]
    var dateFormat: String?
}

nonisolated struct ImportedRow: Equatable {
    var date: Date
    var amount: Decimal
    var isIncome: Bool
    var category: String?
    var note: String
    var account: String?
    var currency: String?
}

nonisolated enum ImportMapper {

    static let synonyms: [ImportRole: [String]] = [
        .date: ["date", "datum", "fecha", "data", "дата", "day", "time", "booking date", "transaction date", "дата операції", "дата операции", "datetime", "created"],
        .amount: ["amount", "sum", "value", "betrag", "importe", "kwota", "сума", "сумма", "total", "amount (uah)", "сума в валюті картки", "сума в валюті операції", "price"],
        .outflow: ["debit", "expense", "expenses", "outflow", "withdrawal", "spent", "out", "витрата", "витрати", "расход", "списание", "списання"],
        .inflow: ["credit", "income", "inflow", "deposit", "in", "дохід", "доход", "надходження", "поступление", "зарахування"],
        .kind: ["type", "kind", "тип", "transaction type", "direction", "вид"],
        .category: ["category", "kategorie", "categoría", "categoria", "kategoria", "категорія", "категория", "group", "tag"],
        .note: ["note", "notes", "description", "memo", "payee", "merchant", "details", "title", "name", "comment", "коментар", "опис", "примітка", "назва", "описание", "комментарий", "деталі операції", "детали"],
        .account: ["account", "wallet", "konto", "cuenta", "рахунок", "гаманець", "счет", "счёт", "card", "картка"],
        .currency: ["currency", "curr", "ccy", "валюта", "währung", "moneda", "waluta", "currency code"]
    ]

    static let dateFormats: [String] = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd",
        "dd.MM.yyyy HH:mm:ss", "dd.MM.yyyy HH:mm", "dd.MM.yyyy", "d.M.yyyy", "dd.MM.yy", "d.M.yy",
        "dd/MM/yyyy HH:mm", "dd/MM/yyyy", "MM/dd/yyyy HH:mm", "MM/dd/yyyy", "M/d/yyyy", "d/M/yyyy", "M/d/yy", "d/M/yy",
        "yyyy/MM/dd", "dd-MM-yyyy", "MMM d, yyyy", "d MMM yyyy", "yyyyMMdd"
    ]

    static func normalizedHeader(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'*:")))
    }

    static func role(forHeader header: String) -> ImportRole? {
        let key = normalizedHeader(header)
        guard !key.isEmpty else { return nil }
        for (role, names) in synonyms where names.contains(key) { return role }
        // Looser contains-match for long bank headers ("Сума в валюті картки (UAH)").
        for (role, names) in synonyms {
            if names.contains(where: { $0.count >= 4 && key.contains($0) }) { return role }
        }
        return nil
    }

    static func plan(for rows: [[String]], locale: Locale = .current) -> ImportPlan {
        guard let first = rows.first else { return ImportPlan(hasHeader: false, roles: [], dateFormat: nil) }
        let width = rows.prefix(20).map(\.count).max() ?? first.count
        var roles = Array(repeating: ImportRole.ignore, count: width)

        let headerRoles = first.map { role(forHeader: $0) }
        let recognised = headerRoles.compactMap { $0 }.count
        let numericCells = first.filter { AmountReader.read($0) != nil }.count
        let hasHeader = recognised >= 2 || (recognised >= 1 && numericCells == 0)

        if hasHeader {
            var used = Set<ImportRole>()
            for (index, role) in headerRoles.enumerated() {
                guard let role, index < width, !used.contains(role) else { continue }
                roles[index] = role
                used.insert(role)
            }
        }

        let body = Array(rows.dropFirst(hasHeader ? 1 : 0).prefix(60))
        // Fill missing roles by looking at the data itself.
        if !roles.contains(.date) {
            for column in 0..<width where roles[column] == .ignore {
                let values = body.compactMap { column < $0.count ? $0[column] : nil }.filter { !$0.isEmpty }
                if !values.isEmpty, bestDateFormat(values) != nil { roles[column] = .date; break }
            }
        }
        if !roles.contains(.amount) && !roles.contains(.outflow) && !roles.contains(.inflow) {
            for column in 0..<width where roles[column] == .ignore {
                let values = body.compactMap { column < $0.count ? $0[column] : nil }.filter { !$0.isEmpty }
                if !values.isEmpty, values.filter({ AmountReader.read($0) != nil }).count * 10 >= values.count * 9 {
                    roles[column] = .amount
                    break
                }
            }
        }
        if !roles.contains(.note) {
            var bestColumn: Int?
            var bestLength = 0
            for column in 0..<width where roles[column] == .ignore {
                let values = body.compactMap { column < $0.count ? $0[column] : nil }
                let textual = values.filter { !$0.isEmpty && AmountReader.read($0) == nil }
                let length = textual.reduce(0) { $0 + $1.count }
                if textual.count * 2 >= values.count, length > bestLength { bestLength = length; bestColumn = column }
            }
            if let bestColumn { roles[bestColumn] = .note }
        }

        var format: String?
        if let dateColumn = roles.firstIndex(of: .date) {
            let values = body.compactMap { dateColumn < $0.count ? $0[dateColumn] : nil }.filter { !$0.isEmpty }
            format = bestDateFormat(values, locale: locale)
        }
        return ImportPlan(hasHeader: hasHeader, roles: roles, dateFormat: format)
    }

    static func bestDateFormat(_ values: [String], locale: Locale = .current) -> String? {
        let sample = Array(values.prefix(40))
        guard !sample.isEmpty else { return nil }
        var best: String?
        var bestHits = 0
        let formatter = DateFormatter()
        formatter.locale = Decimals.posix
        formatter.timeZone = TimeZone.current
        let monthFirst = QuickLineParser.prefersMonthFirst(locale)
        for format in dateFormats {
            formatter.dateFormat = format
            let hits = sample.filter { formatter.date(from: $0) != nil }.count
            let isMonthFirst = format.hasPrefix("M")
            let tieBreak = (isMonthFirst == monthFirst) ? 1 : 0
            if hits > bestHits || (hits == bestHits && hits > 0 && tieBreak == 1 && best.map({ $0.hasPrefix("M") != monthFirst }) == true) {
                bestHits = hits
                best = format
            }
        }
        return bestHits * 10 >= sample.count * 8 ? best : nil
    }

    static func rows(from table: [[String]], plan: ImportPlan, fallbackIncomeWords: Set<String> = ["income", "дохід", "доход", "credit", "надходження", "deposit"]) -> [ImportedRow] {
        let formatter = DateFormatter()
        formatter.locale = Decimals.posix
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = plan.dateFormat ?? "yyyy-MM-dd"

        func value(_ row: [String], _ role: ImportRole) -> String? {
            guard let index = plan.roles.firstIndex(of: role), index < row.count else { return nil }
            let text = row[index].trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }

        func signedReading(_ text: String) -> AmountReader.Reading? {
            var cleaned = text
            var forcedMinus = false
            if cleaned.hasPrefix("(") && cleaned.hasSuffix(")") {
                cleaned = String(cleaned.dropFirst().dropLast())
                forcedMinus = true
            }
            if cleaned.hasSuffix("-"), cleaned.count > 1 {
                cleaned = "-" + cleaned.dropLast()
            }
            guard var reading = AmountReader.read(cleaned) else { return nil }
            if forcedMinus { reading.explicitSign = .minus }
            return reading
        }

        let body = table.dropFirst(plan.hasHeader ? 1 : 0)
        // Bank exports write expenses as negatives and income unsigned; expense
        // trackers write everything unsigned. Look at the column to tell which.
        let amountColumnHasNegatives = body.contains { row in
            guard let text = value(row, .amount) else { return false }
            return signedReading(text)?.explicitSign == .minus
        }

        var output: [ImportedRow] = []
        for row in body {
            guard let dateText = value(row, .date), let date = formatter.date(from: dateText) else { continue }

            var amount: Decimal?
            var isIncome = false
            if let text = value(row, .amount), let reading = signedReading(text) {
                amount = reading.amount
                switch reading.explicitSign {
                case .plus?: isIncome = true
                case .minus?: isIncome = false
                case nil: isIncome = amountColumnHasNegatives
                }
            }
            if amount == nil || amount == 0 {
                if let text = value(row, .inflow), let reading = AmountReader.read(text), reading.amount > 0 {
                    amount = reading.amount
                    isIncome = true
                } else if let text = value(row, .outflow), let reading = AmountReader.read(text), reading.amount > 0 {
                    amount = reading.amount
                    isIncome = false
                }
            }
            guard let finalAmount = amount, finalAmount > 0 else { continue }

            if let kindText = value(row, .kind)?.lowercased() {
                if fallbackIncomeWords.contains(where: { kindText.contains($0) }) { isIncome = true }
                else if kindText.contains("transfer") || kindText.contains("переказ") || kindText.contains("перевод") { continue }
                else if ["expense", "витрата", "расход", "debit", "списання"].contains(where: { kindText.contains($0) }) { isIncome = false }
            }

            output.append(ImportedRow(
                date: date,
                amount: finalAmount,
                isIncome: isIncome,
                category: value(row, .category),
                note: value(row, .note) ?? "",
                account: value(row, .account),
                currency: value(row, .currency).flatMap { AmountReader.currency(for: $0) }
            ))
        }
        return output
    }
}
