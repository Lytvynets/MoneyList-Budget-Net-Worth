import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Budget

struct BudgetEditor: View {
    let category: TransactionCategory?
    let limit: Decimal?
    let month: MoneyMonth

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moneyPrefs) private var prefs
    @Environment(RateBook.self) private var rates
    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]

    @State private var pickedID: UUID?
    @State private var text = ""
    @State private var confirmRemove = false

    var body: some View {
        EditorChrome(category == nil ? Text("New budget") : Text("Edit budget"), canSave: pickedID != nil && (AmountField.value(text) ?? 0) > 0, onSave: save) {
            FieldRow("Category") {
                Menu {
                    Picker(selection: $pickedID) {
                        ForEach(categories.filter { !$0.isIncome && $0.visible }) { item in
                            Label(item.name, systemImage: item.iconName).tag(Optional(item.id))
                        }
                    } label: { Text("Category") }
                } label: {
                    HStack {
                        if let picked = categories.first(where: { $0.id == pickedID }) {
                            Glyph(symbol: picked.iconName, hex: picked.colorHex, size: 30)
                            Text(verbatim: picked.name).foregroundStyle(Ink.text)
                        } else {
                            Text("Choose a category").foregroundStyle(Ink.soft)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").foregroundStyle(Ink.faint)
                    }
                    .font(Typeface.body)
                }
                .disabled(category != nil)
            }
            .paperCard()

            FieldRow("Limit per month") {
                AmountField(title: "0", text: $text, currency: prefs.home)
            }
            .paperCard()

            Text("The limit repeats every month until you change it. Changing it now doesn't rewrite past months.")
                .font(Typeface.detail)
                .foregroundStyle(Ink.soft)

            if category != nil {
                Button(role: .destructive) {
                    confirmRemove = true
                } label: {
                    Text("Remove this budget")
                }
                .buttonStyle(InkButtonStyle(kind: .outline))
                .confirmationDialog(Text("Remove this budget?"), isPresented: $confirmRemove, titleVisibility: .visible) {
                    Button("Remove from this month on", role: .destructive, action: remove)
                }
            }
        }
        .onAppear {
            pickedID = category?.id
            if let limit { text = Decimals.editable(limit) }
        }
    }

    private func save() {
        guard let id = pickedID, let picked = categories.first(where: { $0.id == id }), let value = AmountField.value(text), value > 0 else { return }
        let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
        try? writer.setBudget(category: picked, limit: value, month: month)
        Upkeep.afterChange(context: context, rates: rates)
        Telemetry.event("budget_saved", ["is_new": category == nil])
        Haptic.success()
        dismiss()
    }

    private func remove() {
        guard let category else { return }
        let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
        try? writer.removeBudget(category: category, from: month)
        Upkeep.afterChange(context: context, rates: rates)
        dismiss()
    }
}

// MARK: - Monthly plan

struct SpendingPlanSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RateBook.self) private var rates
    @Query private var profiles: [UserProfile]

    @State private var text = ""
    @State private var startDay = 1

    var body: some View {
        EditorChrome(Text("Monthly plan"), canSave: true, onSave: save) {
            Text("How much do you want to spend in a month, bills included? Money List turns it into a daily allowance.")
                .font(Typeface.label)
                .foregroundStyle(Ink.soft)
            FieldRow("Spending plan") {
                AmountField(title: "Leave empty to use your balance", text: $text, currency: profiles.first?.defaultCurrencyCode ?? "USD")
            }
            .paperCard()
            if let value = AmountField.value(text), value > 0 {
                let periods = PeriodCalendar(startDay: startDay)
                let days = periods.dayCount(in: periods.month(containing: Date()))
                HStack(spacing: 4) {
                    Text("About")
                    MoneyText(value: value / Decimal(max(days, 1)), code: profiles.first?.defaultCurrencyCode ?? "USD", size: .tiny, cents: false)
                    Text("a day")
                }
                .font(Typeface.detail)
                .foregroundStyle(Ink.soft)
            }
            FieldRow("Your month starts on") {
                Picker(selection: $startDay) {
                    ForEach(1...28, id: \.self) { day in
                        Text(verbatim: "\(day)").tag(day)
                    }
                } label: {
                    Text("Day")
                }
                .pickerStyle(.wheel)
                .frame(height: 110)
            }
            .paperCard()
            Text("Paid on the 25th? Start your month on the 25th and every budget follows your payday.")
                .font(Typeface.detail)
                .foregroundStyle(Ink.soft)
        }
        .onAppear {
            if let plan = profiles.first?.monthlyPlan, plan > 0 { text = Decimals.editable(plan) }
            startDay = profiles.first?.periodStartDay ?? 1
        }
    }

    private func save() {
        let profile = profiles.first ?? {
            let created = UserProfile(currencyCode: Locale.current.currency?.identifier ?? "USD")
            context.insert(created)
            return created
        }()
        if let value = AmountField.value(text), value > 0 {
            profile.monthlyPlan = value
        } else {
            profile.monthlyPlan = nil
        }
        profile.periodStartDay = startDay == 1 ? nil : startDay
        try? context.save()
        Upkeep.afterChange(context: context, rates: rates)
        Haptic.success()
        dismiss()
    }
}

// MARK: - Goal

struct GoalEditor: View {
    let goal: Goal?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moneyPrefs) private var prefs
    @Environment(RateBook.self) private var rates
    @Query private var accounts: [Account]
    @Query(sort: \Goal.sortOrder) private var goals: [Goal]

    @State private var name = ""
    @State private var targetText = ""
    @State private var currency = "USD"
    @State private var tracking: GoalTracking = .manual
    @State private var linked: Set<UUID> = []
    @State private var savedText = ""
    @State private var monthlyText = ""
    @State private var hasDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var symbol = "flag.fill"
    @State private var hex = InkSwatch.moss
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: Data?
    @State private var confirmDelete = false

    var body: some View {
        EditorChrome(goal == nil ? Text("New goal") : Text("Edit goal"), canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty && (AmountField.value(targetText) ?? 0) > 0, onSave: save) {
            FieldRow("Name") {
                TextField("A trip to Lisbon", text: $name)
                    .font(Typeface.body)
            }
            .paperCard()

            FieldRow("Target") {
                HStack {
                    AmountField(title: "0", text: $targetText, currency: currency)
                    CurrencyMenu(code: $currency)
                }
            }
            .paperCard()

            FieldRow("How progress is counted") {
                SegmentRail(items: [(GoalTracking.manual, "I add money"), (GoalTracking.wallets, "Account balance")], selection: $tracking)
                if tracking == .manual {
                    AmountField(title: "Already saved", text: $savedText, currency: currency)
                } else {
                    Text(linked.isEmpty ? "All accounts count. Pick some to narrow it down." : "Only the picked accounts count.")
                        .font(Typeface.detail)
                        .foregroundStyle(Ink.soft)
                    FlowChips(accounts: accounts.filter { !$0.isArchived && !$0.kind.isLiability }, selection: $linked)
                }
            }
            .paperCard()

            FieldRow("Plan") {
                AmountField(title: "Monthly contribution (optional)", text: $monthlyText, currency: currency)
                Toggle(isOn: $hasDate) { Text("Finish by a date") }
                    .tint(Color(hexString: hex))
                if hasDate {
                    DatePicker(selection: $targetDate, in: Date()..., displayedComponents: .date) { Text("Target date") }
                }
            }
            .paperCard()

            FieldRow("Look") {
                HStack(spacing: 14) {
                    // The picker's label closure is nonisolated, so the preview is decoded out here.
                    let preview = photo.flatMap { UIImage(data: $0) }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack {
                            if let preview {
                                Image(uiImage: preview).resizable().scaledToFill()
                            } else {
                                Image(systemName: "photo.badge.plus").font(.system(size: 20)).foregroundStyle(Ink.soft)
                            }
                        }
                        .frame(width: 56, height: 56)
                        .background(Ink.raised)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Ink.rule))
                    }
                    if photo != nil {
                        Button("Remove photo", role: .destructive) { photo = nil; photoItem = nil }
                            .font(Typeface.detail)
                    }
                }
                SwatchPicker(hex: $hex)
                if photo == nil {
                    SymbolPicker(symbol: $symbol, tintHex: hex)
                }
            }
            .paperCard()

            if goal != nil {
                Button(role: .destructive) { confirmDelete = true } label: { Text("Delete goal") }
                    .buttonStyle(InkButtonStyle(kind: .outline))
                    .confirmationDialog(Text("Delete this goal?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive, action: delete)
                    }
            }
        }
        .onAppear(perform: load)
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    photo = PhotoShrinker.jpeg(from: data, maxSide: 600, quality: 0.7)
                }
            }
        }
    }

    private func load() {
        currency = prefs.home
        guard let goal else { return }
        name = goal.name
        targetText = Decimals.editable(goal.targetAmount)
        currency = goal.currencyCode
        tracking = goal.tracking
        linked = Set(goal.linkedAccountIDs)
        if let saved = goal.manualSaved { savedText = Decimals.editable(saved) }
        if let monthly = goal.monthlyContribution { monthlyText = Decimals.editable(monthly) }
        if let date = goal.targetDate { hasDate = true; targetDate = date }
        symbol = goal.iconName ?? "flag.fill"
        hex = goal.colorHex ?? InkSwatch.moss
        photo = goal.customImageData
    }

    private func save() {
        guard let target = AmountField.value(targetText), target > 0 else { return }
        let item: Goal
        if let goal {
            item = goal
        } else {
            item = Goal(name: name, targetAmount: target, currencyCode: currency)
            item.sortOrder = (goals.map(\.sortOrder).max() ?? 0) + 1
            context.insert(item)
        }
        item.name = name.trimmingCharacters(in: .whitespaces)
        item.targetAmount = target
        item.currencyCode = currency
        item.tracking = tracking
        item.linkedAccountIDs = tracking == .wallets ? Array(linked) : []
        item.manualSaved = tracking == .manual ? max(AmountField.value(savedText) ?? 0, 0) : item.manualSaved
        item.monthlyContribution = AmountField.value(monthlyText).flatMap { $0 > 0 ? $0 : nil }
        item.targetDate = hasDate ? targetDate : nil
        item.iconName = symbol
        item.colorHex = hex
        item.customImageData = photo
        try? context.save()
        Telemetry.event("goal_saved", ["is_new": goal == nil, "tracking": tracking.rawValue, "has_date": hasDate])
        Haptic.success()
        dismiss()
    }

    private func delete() {
        guard let goal else { return }
        let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
        try? writer.deleteGoal(goal)
        dismiss()
    }
}

/// Multi-select account chips.
struct FlowChips: View {
    let accounts: [Account]
    @Binding var selection: Set<UUID>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(accounts) { account in
                    Button {
                        Haptic.tap()
                        if selection.contains(account.id) { selection.remove(account.id) } else { selection.insert(account.id) }
                    } label: {
                        Chip(verbatim: account.name, symbol: account.displaySymbol, selected: selection.contains(account.id))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Compact currency picker (frequent currencies first, full list below).
struct CurrencyMenu: View {
    @Binding var code: String

    static let frequent = ["USD", "EUR", "UAH", "GBP", "PLN", "CHF", "CAD", "AUD", "JPY", "CZK", "SEK", "NOK", "TRY", "CNY", "INR", "GEL", "KZT", "MDL", "RON", "HUF"]

    var body: some View {
        Menu {
            Picker(selection: $code) {
                ForEach(CurrencyMenu.frequent, id: \.self) { item in
                    Text(verbatim: "\(item) — \(MoneyFormat.currencyName(item))").tag(item)
                }
            } label: { Text("Currency") }
            Menu {
                Picker(selection: $code) {
                    ForEach(Locale.commonISOCurrencyCodes.filter { !CurrencyMenu.frequent.contains($0) }, id: \.self) { item in
                        Text(verbatim: "\(item) — \(MoneyFormat.currencyName(item))").tag(item)
                    }
                } label: { Text("Currency") }
            } label: {
                Text("All currencies")
            }
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: code)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .font(Typeface.labelStrong)
            .foregroundStyle(Ink.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Ink.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(Ink.rule))
        }
    }
}
