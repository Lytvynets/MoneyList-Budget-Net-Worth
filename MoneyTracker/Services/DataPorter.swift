import Foundation
import SwiftData

/// CSV export (always free: your data is yours).
enum Exporter {
    static func makeCSV(context: ModelContext) -> URL? {
        guard let entries = try? context.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Decimals.posix
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        var rows: [[String]] = [["Date", "Type", "Amount", "Currency", "Account", "To account", "To amount", "Category", "Note", "Original amount", "Original currency"]]
        for entry in entries {
            rows.append([
                formatter.string(from: entry.date),
                entry.kind.rawValue,
                Decimals.editable(entry.amount),
                entry.currencyCode,
                entry.account?.name ?? "",
                entry.toAccount?.name ?? "",
                entry.toAmount.map(Decimals.editable) ?? "",
                entry.category?.name ?? "",
                entry.note ?? "",
                entry.originalAmount.map(Decimals.editable) ?? "",
                entry.originalCurrency ?? ""
            ])
        }
        let stamp = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MoneyList-\(stamp).csv")
        do {
            try CSVKit.write(rows: rows).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("Money List: export failed — \(error)")
            return nil
        }
    }
}

/// Applies rows recognised by `ImportMapper` to the store.
enum Importer {

    struct Outcome {
        var imported = 0
        var skipped = 0
        var newCategories = 0
    }

    static func readText(from url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .windowsCP1251) { return text }
        if let text = String(data: data, encoding: .utf16) { return text }
        return String(data: data, encoding: .isoLatin1)
    }

    static func apply(_ rows: [ImportedRow], defaultAccount: Account, keepBalances: Bool, skipDuplicates: Bool, context: ModelContext, convert: CurrencyConverter) -> Outcome {
        var outcome = Outcome()
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        var categories = (try? context.fetch(FetchDescriptor<TransactionCategory>())) ?? []
        let existing = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let calendar = Calendar.current

        func key(_ accountID: UUID, _ date: Date, _ amount: Decimal, _ note: String) -> String {
            "\(accountID.uuidString)|\(calendar.startOfDay(for: date).timeIntervalSince1970)|\(Decimals.rounded(amount))|\(note.lowercased())"
        }
        var seen = Set(existing.compactMap { entry -> String? in
            guard let id = entry.account?.id else { return nil }
            return key(id, entry.date, entry.amount, entry.note ?? "")
        })

        var effects: [UUID: Decimal] = [:]
        var palette = InkSwatch.all.makeIterator()

        for row in rows {
            let account = row.account.flatMap { name in
                accounts.first { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            } ?? defaultAccount

            var amount = row.amount
            var original: (Decimal, String)?
            if let code = row.currency, code != account.currencyCode {
                original = (row.amount, code)
                amount = Decimals.rounded(convert(row.amount, code, account.currencyCode))
            }

            let rowKey = key(account.id, row.date, amount, row.note)
            if skipDuplicates && seen.contains(rowKey) {
                outcome.skipped += 1
                continue
            }
            seen.insert(rowKey)

            var category: TransactionCategory?
            if let name = row.category?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                category = categories.first { $0.isIncome == row.isIncome && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
                if category == nil {
                    let color = palette.next() ?? InkSwatch.slate
                    let created = TransactionCategory(name: name, iconName: "tag.fill", colorHex: color, isIncome: row.isIncome, isCustom: true, sortOrder: categories.count + 1)
                    context.insert(created)
                    categories.append(created)
                    category = created
                    outcome.newCategories += 1
                }
            }

            let entry = Transaction(kind: row.isIncome ? .income : .expense, amount: amount, date: row.date, note: row.note.isEmpty ? nil : row.note, account: account)
            entry.category = category
            if let original {
                entry.originalAmount = original.0
                entry.originalCurrency = original.1
            }
            context.insert(entry)
            effects[account.id, default: 0] += row.isIncome ? amount : -amount
            outcome.imported += 1
        }

        if keepBalances {
            for account in accounts {
                if let effect = effects[account.id] { BalanceKeeper.absorbImportedEffect(effect, into: account) }
            }
        }
        try? context.save()
        BalanceKeeper.recompute(context: context)
        return outcome
    }
}
