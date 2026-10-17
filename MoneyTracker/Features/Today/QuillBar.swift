import SwiftUI
import SwiftData

/// One-line entry: type it like a note ("coffee 4.50", "taxi 120 вчора",
/// "+2000 salary", "netflix 9.99 monthly") and it is parsed, categorized and saved.
struct QuillBar: View {
    let categories: [TransactionCategory]
    let accounts: [Account]
    let entries: [Transaction]

    @Environment(\.modelContext) private var context
    @Environment(\.moneyPrefs) private var prefs
    @Environment(\.inkAccent) private var accent
    @Environment(RateBook.self) private var rates
    @Environment(ProPass.self) private var pro
    @Environment(AdPacer.self) private var ads
    @Environment(ToastCenter.self) private var toasts
    @Environment(Router.self) private var router

    @State private var text = ""
    @State private var line = QuickLine(amount: nil, currencyCode: nil, incomeHint: nil, note: "", date: nil, cadence: nil)
    @State private var pickedCategoryID: UUID?
    @State private var pickedAccountID: UUID?
    @State private var guesser: CategoryGuesser?
    @State private var guesserSize = -1
    @State private var nudge = false
    @FocusState private var focused: Bool

    private var liveAccounts: [Account] {
        accounts.filter { !$0.isArchived }.sorted { ($0.sortIndex ?? 0, $0.createdAt) < ($1.sortIndex ?? 0, $1.createdAt) }
    }

    private var account: Account? {
        if let id = pickedAccountID, let match = liveAccounts.first(where: { $0.id == id }) { return match }
        if let id = prefs.defaultAccountID, let match = liveAccounts.first(where: { $0.id == id }) { return match }
        return liveAccounts.first(where: { $0.isSpendable }) ?? liveAccounts.first
    }

    private var resolved: (category: TransactionCategory?, isIncome: Bool, guessed: Bool) {
        if let id = pickedCategoryID, let category = categories.first(where: { $0.id == id }) {
            return (category, category.isIncome, false)
        }
        let explicitIncome = line.incomeHint
        if let guess = guesser?.guess(note: line.note, isIncome: explicitIncome),
           let category = categories.first(where: { $0.id == guess.categoryID }) {
            return (category, category.isIncome, true)
        }
        let isIncome = explicitIncome ?? false
        let fallback = categories.first { $0.isIncome == isIncome && $0.iconName == "ellipsis.circle.fill" && $0.visible }
        return (fallback, isIncome, true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            field
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                suggestions
            } else {
                preview
            }
        }
        .onAppear(perform: rebuildGuesser)
        .onChange(of: entries.count) { _, _ in rebuildGuesser() }
        .onChange(of: text) { _, newValue in
            line = QuickLineParser.parse(newValue, homeCurrency: prefs.home)
            if newValue.isEmpty {
                pickedCategoryID = nil
            }
        }
    }

    // MARK: Field

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.line")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
            TextField(text: $text, prompt: Text("coffee 4.50 · taxi 120 yesterday")) {
                Text("Write an entry")
            }
            .font(Typeface.body)
            .focused($focused)
            .submitLabel(.done)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(commit)
            if text.isEmpty {
                Button {
                    router.composer = ComposerRequest()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Ink.soft)
                }
                .accessibilityLabel(Text("Open full entry form"))
            } else {
                Button(action: commit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(line.amount == nil ? Ink.faint : accent)
                }
                .accessibilityLabel(Text("Save entry"))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(minHeight: 54)
        .background(Ink.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(focused ? accent.opacity(0.6) : Ink.ruleStrong, lineWidth: focused ? 1.4 : 0.8)
        )
        .offset(x: nudge ? -6 : 0)
        .animation(.spring(response: 0.2, dampingFraction: 0.3), value: nudge)
    }

    // MARK: Preview

    private var preview: some View {
        let resolved = self.resolved
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let amount = line.amount {
                    let code = line.currencyCode ?? account?.currencyCode ?? prefs.home
                    Chip(verbatim: (resolved.isIncome ? "+" : "") + MoneyFormat.plain(amount, code: code), selected: true, tint: resolved.isIncome ? Ink.gain : Ink.text)
                } else {
                    Chip("Add an amount", symbol: "number", dashed: true)
                }

                Menu {
                    Picker(selection: categoryBinding) {
                        ForEach(categories.filter { $0.visible && $0.isIncome == resolved.isIncome }) { category in
                            Label(category.name, systemImage: category.iconName).tag(Optional(category.id))
                        }
                    } label: {
                        Text("Category")
                    }
                    Divider()
                    Button(resolved.isIncome ? String(localized: "Make it an expense") : String(localized: "Make it income")) {
                        pickedCategoryID = categories.first { $0.isIncome != resolved.isIncome && $0.visible }?.id
                    }
                } label: {
                    if let category = resolved.category {
                        Chip(verbatim: category.name, symbol: category.iconName, dashed: resolved.guessed)
                    } else {
                        Chip("Category", symbol: "tag", dashed: true)
                    }
                }

                if liveAccounts.count > 1 {
                    Menu {
                        Picker(selection: accountBinding) {
                            ForEach(liveAccounts) { item in
                                Text(verbatim: item.name).tag(Optional(item.id))
                            }
                        } label: {
                            Text("Account")
                        }
                    } label: {
                        Chip(verbatim: account?.name ?? "—", symbol: account?.displaySymbol ?? "wallet.pass")
                    }
                }

                if let date = line.date, !Calendar.current.isDateInToday(date) {
                    Chip(verbatim: date.formatted(.dateTime.day().month(.abbreviated)), symbol: "calendar")
                }
                if let cadence = line.cadence {
                    Chip(verbatim: CadenceText.title(cadence), symbol: "repeat")
                }
                Button {
                    openComposer()
                } label: {
                    Chip("More", symbol: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 1)
        }
    }

    private var categoryBinding: Binding<UUID?> {
        Binding(get: { pickedCategoryID ?? resolved.category?.id }, set: { pickedCategoryID = $0 })
    }

    private var accountBinding: Binding<UUID?> {
        Binding(get: { account?.id }, set: { pickedAccountID = $0 })
    }

    // MARK: Suggestions

    private var suggestions: some View {
        let picks = frequentLines()
        return Group {
            if !picks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(picks, id: \.self) { pick in
                            Button {
                                Haptic.tap()
                                text = pick
                                focused = true
                            } label: {
                                Chip(verbatim: pick, symbol: "arrow.uturn.backward")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func frequentLines() -> [String] {
        var counts: [String: (count: Int, amount: Decimal, note: String)] = [:]
        for entry in entries.prefix(120) where entry.kind == .expense {
            guard let note = entry.note?.trimmingCharacters(in: .whitespaces), !note.isEmpty, note.count <= 24 else { continue }
            let key = note.lowercased()
            if var current = counts[key] {
                current.count += 1
                counts[key] = current
            } else {
                counts[key] = (1, entry.amount, note)
            }
        }
        return counts.values
            .filter { $0.count >= 2 }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { "\($0.note) \(MoneyFormat.number($0.amount))" }
    }

    // MARK: Actions

    private func rebuildGuesser() {
        guard entries.count != guesserSize else { return }
        guesserSize = entries.count
        let candidates = categories.map { CategoryGuesser.Candidate(id: $0.id, isIncome: $0.isIncome, iconKey: $0.iconName, name: $0.name) }
        let memories = entries.prefix(600).compactMap { entry -> CategoryGuesser.Memory? in
            guard let note = entry.note, !note.isEmpty, let category = entry.category else { return nil }
            return CategoryGuesser.Memory(note: note, categoryID: category.id, date: entry.date)
        }
        guesser = CategoryGuesser(candidates: candidates, memories: memories)
    }

    private func openComposer() {
        let resolved = self.resolved
        router.composer = ComposerRequest(
            kind: resolved.isIncome ? .income : .expense,
            prefill: line,
            categoryID: resolved.category?.id,
            accountID: account?.id
        )
        text = ""
        focused = false
    }

    private func commit() {
        guard let amount = line.amount, amount > 0 else {
            Haptic.warning()
            nudge.toggle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { nudge.toggle() }
            return
        }
        guard let account else {
            toasts.show(String(localized: "Add an account first."))
            return
        }
        let resolved = self.resolved
        var draft = EntryDraft()
        draft.kind = resolved.isIncome ? .income : .expense
        draft.amount = amount
        draft.inputCurrency = line.currencyCode ?? account.currencyCode
        draft.accountID = account.id
        draft.categoryID = resolved.category?.id
        draft.note = line.note
        draft.date = line.date ?? Date()
        draft.repeatCadence = line.cadence

        let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
        do {
            let entry = try writer.save(draft)
            Telemetry.event("entry_saved", [
                "kind": draft.kind.rawValue,
                "source": "quick_line",
                "repeats": line.cadence != nil,
                "foreign_currency": draft.inputCurrency != account.currencyCode,
                "dated": line.date != nil,
                "category_guessed": resolved.category != nil
            ])
            let ruleID = line.cadence != nil ? entry.recurringRuleId : nil
            let summary = MoneyFormat.plain(amount, code: draft.inputCurrency) + (resolved.category.map { " · " + $0.name } ?? "")
            Haptic.success()
            toasts.show(String(localized: "Noted \(summary)")) {
                undo(entryID: entry.id, ruleID: ruleID)
            }
            AfterSave.run(entry: entry, context: context, rates: rates, pro: pro, ads: ads)
            text = ""
            pickedCategoryID = nil
            pickedAccountID = nil
        } catch {
            toasts.show(error.localizedDescription)
        }
    }

    private func undo(entryID: UUID, ruleID: UUID?) {
        let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
        if let entry = entries.first(where: { $0.id == entryID }) ?? (try? context.fetch(FetchDescriptor<Transaction>()))?.first(where: { $0.id == entryID }) {
            try? writer.delete(entry)
        }
        if let ruleID, let rule = (try? context.fetch(FetchDescriptor<RecurringRule>()))?.first(where: { $0.id == ruleID }) {
            try? writer.deleteRule(rule)
        }
        Upkeep.afterChange(context: context, rates: rates)
    }
}

/// Human wording for repeat schedules.
enum CadenceText {
    static func title(_ cadence: Cadence) -> String {
        switch (cadence.unit, cadence.every) {
        case (.day, 1): return String(localized: "Daily")
        case (.week, 1): return String(localized: "Weekly")
        case (.week, 2): return String(localized: "Every 2 weeks")
        case (.month, 1): return String(localized: "Monthly")
        case (.month, 3): return String(localized: "Every 3 months")
        case (.month, 6): return String(localized: "Every 6 months")
        case (.year, 1): return String(localized: "Yearly")
        case (.day, let n): return String(localized: "Every \(n) days")
        case (.week, let n): return String(localized: "Every \(n) weeks")
        case (.month, let n): return String(localized: "Every \(n) months")
        case (.year, let n): return String(localized: "Every \(n) years")
        }
    }

    static let presets: [Cadence] = [.weekly, .biweekly, .monthly, .quarterly, Cadence(unit: .month, every: 6), .yearly]
}
