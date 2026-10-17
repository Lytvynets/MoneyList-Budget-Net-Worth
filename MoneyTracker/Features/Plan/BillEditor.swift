import SwiftUI
import SwiftData

struct BillEditor: View {
    let rule: RecurringRule?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moneyPrefs) private var prefs
    @Environment(RateBook.self) private var rates
    @Query private var accounts: [Account]
    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]

    @State private var title = ""
    @State private var kind: EntryKind = .expense
    @State private var amountText = ""
    @State private var accountID: UUID?
    @State private var toAccountID: UUID?
    @State private var categoryID: UUID?
    @State private var cadence: Cadence = .monthly
    @State private var customEvery = 1
    @State private var customUnit: Cadence.Unit = .month
    @State private var useCustom = false
    @State private var dueDate = Date()
    @State private var hasEnd = false
    @State private var endDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var autoPost = true
    @State private var remindDays = 1
    @State private var isSubscription = false
    @State private var symbol = "calendar"
    @State private var hex = InkSwatch.ochre
    @State private var confirmDelete = false

    private var liveAccounts: [Account] { accounts.filter { !$0.isArchived } }
    private var account: Account? { liveAccounts.first { $0.id == accountID } ?? liveAccounts.first }

    private var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty, (AmountField.value(amountText) ?? 0) > 0, account != nil else { return false }
        if kind == .transfer { return toAccountID != nil && toAccountID != account?.id }
        return true
    }

    var body: some View {
        EditorChrome(rule == nil ? Text("New bill") : Text("Edit bill"), canSave: canSave, onSave: save) {
            SegmentRail(items: [(EntryKind.expense, "Bill"), (EntryKind.income, "Income"), (EntryKind.transfer, "Transfer")], selection: $kind)

            FieldRow("What is it") {
                TextField(kind == .income ? "Salary" : "Rent, phone, streaming…", text: $title)
                    .font(Typeface.body)
                AmountField(title: "Amount", text: $amountText, currency: account?.currencyCode ?? prefs.home)
            }
            .paperCard()

            FieldRow("When") {
                if useCustom {
                    HStack {
                        Stepper(value: $customEvery, in: 1...36) {
                            Text(verbatim: CadenceText.title(Cadence(unit: customUnit, every: customEvery)))
                                .font(Typeface.body)
                        }
                    }
                    Picker(selection: $customUnit) {
                        Text("Days").tag(Cadence.Unit.day)
                        Text("Weeks").tag(Cadence.Unit.week)
                        Text("Months").tag(Cadence.Unit.month)
                        Text("Years").tag(Cadence.Unit.year)
                    } label: { Text("Unit") }
                    .pickerStyle(.segmented)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CadenceText.presets, id: \.self) { item in
                                Button {
                                    Haptic.tap()
                                    cadence = item
                                } label: {
                                    Chip(verbatim: CadenceText.title(item), selected: cadence == item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Toggle(isOn: $useCustom) { Text("Custom schedule") }
                DatePicker(selection: $dueDate, displayedComponents: .date) {
                    Text(rule == nil ? "First time" : "Next time")
                }
                Toggle(isOn: $hasEnd) { Text("Ends") }
                if hasEnd {
                    DatePicker(selection: $endDate, in: dueDate..., displayedComponents: .date) { Text("Last time") }
                }
            }
            .paperCard()

            FieldRow("Account") {
                accountPicker(selection: $accountID, title: kind == .transfer ? "From" : "Account")
                if kind == .transfer {
                    accountPicker(selection: $toAccountID, title: "To")
                }
            }
            .paperCard()

            if kind != .transfer {
                FieldRow("Category") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categories.filter { $0.visible && $0.isIncome == (kind == .income) }) { category in
                                Button {
                                    Haptic.tap()
                                    categoryID = category.id
                                    hex = category.colorHex
                                    symbol = category.iconName
                                    if category.iconName == "repeat" { isSubscription = true }
                                } label: {
                                    Chip(verbatim: category.name, symbol: category.iconName, selected: categoryID == category.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .paperCard()
            }

            FieldRow("Behavior") {
                Toggle(isOn: $autoPost) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Record automatically")
                        Text(autoPost ? "Added to your ledger on the day." : "Waits on Today until you tap Paid.")
                            .font(Typeface.detail)
                            .foregroundStyle(Ink.soft)
                    }
                }
                Picker(selection: $remindDays) {
                    Text("No reminder").tag(-1)
                    Text("On the day").tag(0)
                    Text("1 day before").tag(1)
                    Text("2 days before").tag(2)
                    Text("3 days before").tag(3)
                    Text("A week before").tag(7)
                } label: {
                    Text("Reminder")
                }
                if kind == .expense {
                    Toggle(isOn: $isSubscription) { Text("It's a subscription") }
                }
            }
            .paperCard()

            if let rule {
                Button(role: .destructive) { confirmDelete = true } label: { Text("Delete") }
                    .buttonStyle(InkButtonStyle(kind: .outline))
                    .confirmationDialog(Text("Delete \(rule.title)?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
                            try? writer.deleteRule(rule)
                            Upkeep.afterChange(context: context, rates: rates)
                            dismiss()
                        }
                    } message: {
                        Text("Entries it already recorded stay in your ledger.")
                    }
            }
        }
        .onAppear(perform: load)
    }

    private func accountPicker(selection: Binding<UUID?>, title: LocalizedStringKey) -> some View {
        Menu {
            Picker(selection: selection) {
                ForEach(liveAccounts) { item in
                    Text(verbatim: item.name).tag(Optional(item.id))
                }
            } label: { Text(title) }
        } label: {
            HStack {
                Text(title).foregroundStyle(Ink.soft)
                Spacer()
                Text(verbatim: liveAccounts.first(where: { $0.id == selection.wrappedValue })?.name ?? String(localized: "Choose"))
                    .foregroundStyle(Ink.text)
                Image(systemName: "chevron.up.chevron.down").foregroundStyle(Ink.faint)
            }
            .font(Typeface.body)
        }
    }

    private func load() {
        guard let rule else {
            accountID = prefs.defaultAccountID ?? liveAccounts.first(where: { $0.isSpendable })?.id ?? liveAccounts.first?.id
            dueDate = Date()
            return
        }
        title = rule.title
        kind = rule.kind
        amountText = Decimals.editable(rule.amount)
        accountID = rule.accountID
        toAccountID = rule.toAccountID
        categoryID = rule.categoryID
        let stored = rule.cadence
        if CadenceText.presets.contains(stored) {
            cadence = stored
        } else {
            useCustom = true
            customEvery = stored.every
            customUnit = stored.unit
        }
        dueDate = rule.nextDueDate
        if let end = rule.endDate { hasEnd = true; endDate = end }
        autoPost = rule.autoPost
        remindDays = rule.remindDaysBefore
        isSubscription = rule.isSubscription
        symbol = rule.iconName ?? "calendar"
        hex = rule.colorHex ?? InkSwatch.ochre
    }

    private func save() {
        guard let amount = AmountField.value(amountText), amount > 0, let account else { return }
        let schedule = useCustom ? Cadence(unit: customUnit, every: customEvery) : cadence
        let calendar = Calendar.current
        let due = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dueDate) ?? dueDate

        let item: RecurringRule
        if let rule {
            item = rule
            let scheduleChanged = rule.cadence != schedule || !calendar.isDate(rule.nextDueDate, inSameDayAs: due)
            item.cadence = schedule
            if scheduleChanged { RuleRunner.reschedule(item, firstDue: due) }
        } else {
            item = RecurringRule(title: title, amount: amount, kind: kind, cadence: schedule, firstDue: due)
            context.insert(item)
        }
        item.title = title.trimmingCharacters(in: .whitespaces)
        item.amount = amount
        item.kind = kind
        item.accountID = account.id
        item.toAccountID = kind == .transfer ? toAccountID : nil
        item.categoryID = kind == .transfer ? nil : categoryID
        item.endDate = hasEnd ? endDate : nil
        item.autoPost = autoPost
        item.remindDaysBefore = remindDays
        item.isSubscription = kind == .expense && isSubscription
        item.iconName = symbol
        item.colorHex = hex
        item.isActive = true
        // Dates in the past only set the rhythm; nothing is back-filled.
        let startOfToday = calendar.startOfDay(for: Date())
        if item.nextDueDate < startOfToday {
            item.cycleIndex = Recurrence.firstIndex(onOrAfter: startOfToday, anchor: item.anchorDate, cadence: schedule, calendar: calendar)
            item.nextDueDate = item.occurrence(item.cycleIndex, calendar: calendar)
        }
        try? context.save()

        Telemetry.event("bill_saved", ["is_new": rule == nil, "kind": kind.rawValue, "auto_post": autoPost, "subscription": item.isSubscription])

        // A bill whose first date is today or earlier is recorded right away.
        RuleRunner.postDue(context: context)
        Upkeep.afterChange(context: context, rates: rates)
        Task {
            if remindDays >= 0 { await Reminders.requestPermission() }
            await Upkeep.rescheduleBillReminders(context: context, rates: rates)
        }
        Haptic.success()
        dismiss()
    }
}
