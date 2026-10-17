import AppIntents
import Foundation
import SwiftData

// Siri, Shortcuts, Spotlight and Wallet automations.
// The system creates intents off the main thread, so everything it reads before
// `perform()` is nonisolated; the work itself runs on the main actor.

/// "Write in Money List" — one line, parsed like the quick line on Today.
struct WriteLineIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Write an Entry"
    nonisolated static let description = IntentDescription("Adds an entry from one line of text, such as “coffee 4.50” or “+2000 salary”.")
    nonisolated static let openAppWhenRun: Bool = false

    nonisolated init() {}

    @Parameter(title: "Entry")
    var line: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        Telemetry.event("shortcut_run", ["action": "write_entry"])
        let context = StoreHub.container.mainContext
        let home = IntentSupport.homeCurrency(context: context)
        let parsed = QuickLineParser.parse(line, homeCurrency: home)
        guard let amount = parsed.amount, amount > 0 else {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "I couldn't find an amount. Try “lunch 12”.")))
        }
        let summary = try IntentSupport.save(amount: amount, currency: parsed.currencyCode, note: parsed.note, incomeHint: parsed.incomeHint, date: parsed.date, context: context)
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "Noted \(summary)")))
    }
}

/// Built for the Wallet "Transaction" automation: amount + merchant.
struct LogPurchaseIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Log Purchase"
    nonisolated static let description = IntentDescription("Records a purchase. Use it with the Transaction automation in Shortcuts to log card payments automatically.")
    nonisolated static let openAppWhenRun: Bool = false

    nonisolated init() {}

    @Parameter(title: "Amount")
    var amount: String

    @Parameter(title: "Merchant")
    var merchant: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        Telemetry.event("shortcut_run", ["action": "log_purchase"])
        let context = StoreHub.container.mainContext
        let home = IntentSupport.homeCurrency(context: context)
        guard let reading = AmountReader.read(amount, homeCurrency: home), reading.amount > 0 else {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "That amount didn't look right.")))
        }
        let summary = try IntentSupport.save(amount: reading.amount, currency: reading.currencyCode, note: merchant ?? "", incomeHint: false, date: nil, context: context)
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "Noted \(summary)")))
    }
}

/// "What can I spend today?"
struct AllowanceIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Today's Allowance"
    nonisolated static let description = IntentDescription("Tells you how much you can still spend today.")
    nonisolated static let openAppWhenRun: Bool = false

    nonisolated init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        Telemetry.event("shortcut_run", ["action": "allowance"])
        let context = StoreHub.container.mainContext
        let rates = RateBook()
        let entries = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let rules = (try? context.fetch(FetchDescriptor<RecurringRule>())) ?? []
        let budgets = (try? context.fetch(FetchDescriptor<Budget>())) ?? []
        let holdings = (try? context.fetch(FetchDescriptor<Asset>())) ?? []
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        let home = profile?.defaultCurrencyCode ?? "USD"
        let digest = DigestBuilder.build(entries: entries, accounts: accounts, rules: rules, budgets: budgets, holdings: holdings, profile: profile, home: home, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
        let left = digest.allowance.leftToday
        let text = MoneyFormat.plain(Decimals.abs(left), code: home, cents: false)
        if left >= 0 {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "You can spend \(text) today.")))
        }
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "You're \(text) over today's allowance.")))
    }
}

struct MoneyListShortcuts: AppShortcutsProvider {
    nonisolated static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WriteLineIntent(),
            phrases: [
                "Write in \(.applicationName)",
                "Note an expense in \(.applicationName)"
            ],
            shortTitle: "Write an Entry",
            systemImageName: "pencil.line"
        )
        AppShortcut(
            intent: LogPurchaseIntent(),
            phrases: [
                "Log a purchase in \(.applicationName)",
                "Log an expense in \(.applicationName)"
            ],
            shortTitle: "Log Purchase",
            systemImageName: "creditcard"
        )
        AppShortcut(
            intent: AllowanceIntent(),
            phrases: [
                "What can I spend today in \(.applicationName)",
                "My allowance in \(.applicationName)"
            ],
            shortTitle: "Today's Allowance",
            systemImageName: "sun.max"
        )
    }
}

@MainActor
enum IntentSupport {
    static func homeCurrency(context: ModelContext) -> String {
        (try? context.fetch(FetchDescriptor<UserProfile>()))?.first?.defaultCurrencyCode ?? Locale.current.currency?.identifier ?? "USD"
    }

    /// Saves an expense/income with a guessed category; returns "₴4.50 · Food".
    static func save(amount: Decimal, currency: String?, note: String, incomeHint: Bool?, date: Date?, context: ModelContext) throws -> String {
        let rates = RateBook()
        let categories = (try? context.fetch(FetchDescriptor<TransactionCategory>())) ?? []
        let entries = (try? context.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let accounts = ((try? context.fetch(FetchDescriptor<Account>())) ?? []).filter { !$0.isArchived }
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first

        let guesser = CategoryGuesser(
            candidates: categories.filter(\.visible).map { CategoryGuesser.Candidate(id: $0.id, isIncome: $0.isIncome, iconKey: $0.iconName, name: $0.name) },
            memories: entries.prefix(600).compactMap { entry in
                guard let text = entry.note, !text.isEmpty, let category = entry.category else { return nil }
                return CategoryGuesser.Memory(note: text, categoryID: category.id, date: entry.date)
            }
        )
        let guess = guesser.guess(note: note, isIncome: incomeHint)
        let category = guess.flatMap { found in categories.first { $0.id == found.categoryID } }
        let isIncome = category?.isIncome ?? (incomeHint ?? false)
        let account = accounts.first { $0.id == profile?.defaultAccountID } ?? accounts.first { $0.isSpendable } ?? accounts.first

        var draft = EntryDraft()
        draft.kind = isIncome ? .income : .expense
        draft.amount = amount
        draft.inputCurrency = currency ?? account?.currencyCode ?? homeCurrency(context: context)
        draft.accountID = account?.id
        draft.categoryID = category?.id ?? categories.first { $0.isIncome == isIncome && $0.iconName == "ellipsis.circle.fill" }?.id
        draft.note = note
        draft.date = date ?? Date()

        let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
        let entry = try writer.save(draft)
        WidgetFeed.refresh(context: context, rates: rates)
        AfterSave.checkBudget(for: entry, context: context, rates: rates)
        let label = category?.name ?? note
        return MoneyFormat.plain(amount, code: draft.inputCurrency) + (label.isEmpty ? "" : " · " + label)
    }
}
