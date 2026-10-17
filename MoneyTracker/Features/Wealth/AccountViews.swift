import SwiftUI
import SwiftData
import Charts

struct AccountEditor: View {
    let account: Account?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moneyPrefs) private var prefs
    @Environment(RateBook.self) private var rates
    @Query private var profiles: [UserProfile]
    @Query private var accounts: [Account]

    @State private var name = ""
    @State private var kind: WalletKind = .card
    @State private var currency = "USD"
    @State private var balanceText = ""
    @State private var hex = InkSwatch.cobalt
    @State private var spendable = true
    @State private var spendableTouched = false
    @State private var isDefault = false
    @State private var confirmDelete = false

    var body: some View {
        EditorChrome(account == nil ? Text("New account") : Text("Edit account"), canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty, onSave: save) {
            FieldRow("Name") {
                TextField("Main card, Cash, Savings…", text: $name)
                    .font(Typeface.body)
            }
            .paperCard()

            FieldRow("Kind") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(WalletKind.allCases) { item in
                        Button {
                            Haptic.tap()
                            kind = item
                            if !spendableTouched { spendable = item.isSpendableByDefault }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 18, weight: .medium))
                                Text(verbatim: item.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .foregroundStyle(kind == item ? Color.white : Ink.text)
                            .frame(maxWidth: .infinity, minHeight: 62)
                            .background(kind == item ? Color(hexString: hex) : Ink.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Ink.rule))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .paperCard()

            FieldRow(kind.isLiability ? "Amount owed" : (account == nil ? "Balance now" : "Current balance")) {
                HStack {
                    AmountField(title: "0", text: $balanceText, currency: currency, allowsNegative: !kind.isLiability)
                    CurrencyMenu(code: $currency)
                }
                if account != nil {
                    Text("Changing the balance doesn't create an entry; the starting point is adjusted.")
                        .font(Typeface.detail)
                        .foregroundStyle(Ink.soft)
                }
            }
            .paperCard()

            FieldRow("Color") {
                SwatchPicker(hex: $hex)
            }
            .paperCard()

            FieldRow("Options") {
                Toggle(isOn: Binding(get: { spendable }, set: { spendable = $0; spendableTouched = true })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Counts toward daily allowance")
                        Text("Everyday money. Usually off for savings and debts.")
                            .font(Typeface.detail)
                            .foregroundStyle(Ink.soft)
                    }
                }
                Toggle(isOn: $isDefault) { Text("Default for new entries") }
            }
            .paperCard()

            if let account {
                HStack(spacing: 10) {
                    Button {
                        let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
                        try? writer.setArchived(account, !account.isArchived)
                        Upkeep.afterChange(context: context, rates: rates)
                        dismiss()
                    } label: {
                        Text(account.isArchived ? "Bring back" : "Archive")
                    }
                    .buttonStyle(InkButtonStyle(kind: .outline))
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Text("Delete").foregroundStyle(Ink.loss)
                    }
                    .buttonStyle(InkButtonStyle(kind: .outline))
                    .disabled(accounts.count <= 1)
                }
                .confirmationDialog(Text("Delete \(account.name)?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete account and its entries", role: .destructive) {
                        let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
                        try? writer.deleteAccount(account)
                        Upkeep.afterChange(context: context, rates: rates)
                        dismiss()
                    }
                } message: {
                    Text("Archive keeps the history but hides the account. Deleting removes it and every entry in it, on all your devices.")
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        currency = prefs.home
        guard let account else {
            spendable = kind.isSpendableByDefault
            return
        }
        name = account.name
        kind = account.kind
        currency = account.currencyCode
        let value = account.kind.isLiability ? (account.amountOwed ?? 0) : account.balance
        balanceText = Decimals.editable(value)
        hex = account.colorHex
        spendable = account.isSpendable
        spendableTouched = account.spendableOverride != nil
        isDefault = profiles.first?.defaultAccountID == account.id
    }

    private func save() {
        let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
        let value = AmountField.value(balanceText) ?? 0
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        do {
            let saved: Account
            if let account {
                let override: Bool? = spendableTouched ? spendable : nil
                try writer.updateAccount(account, name: trimmed, kind: kind, currency: currency, currentBalance: value, colorHex: hex, spendable: override)
                saved = account
            } else {
                saved = try writer.createAccount(name: trimmed, kind: kind, currency: currency, balance: value, colorHex: hex)
                if spendableTouched { saved.spendableOverride = spendable }
            }
            if let profile = profiles.first {
                if isDefault {
                    profile.defaultAccountID = saved.id
                } else if profile.defaultAccountID == saved.id {
                    profile.defaultAccountID = nil
                }
            }
            try context.save()
            Upkeep.afterChange(context: context, rates: rates)
            Telemetry.event("account_saved", ["is_new": account == nil, "kind": kind.rawValue])
            Haptic.success()
            dismiss()
        } catch {
            print("Money List: account save failed — \(error)")
        }
    }
}

struct AccountDetail: View {
    let account: Account

    @Environment(RateBook.self) private var rates
    @Environment(\.inkAccent) private var accent
    @State private var editing = false
    @State private var focused: Transaction?

    private var entries: [Transaction] {
        let mine = (account.transactions ?? []) + (account.incomingTransfers ?? [])
        var seen = Set<UUID>()
        return mine.filter { seen.insert($0.id).inserted }.sorted { $0.date > $1.date }
    }

    var body: some View {
        let list = entries
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker(verbatim: account.kind.title)
                    if let owed = account.amountOwed {
                        MoneyText(value: owed, code: account.currencyCode, size: .large, tone: owed > 0 ? Ink.loss : Ink.text)
                        Text("owed").font(Typeface.label).foregroundStyle(Ink.soft)
                    } else {
                        MoneyText(value: account.balance, code: account.currencyCode, size: .large, tone: account.balance < 0 ? Ink.loss : Ink.text)
                    }
                    balanceChart(list)
                        .frame(height: 110)
                        .padding(.top, 6)
                }
                .paperCard(padding: 18)

                if list.isEmpty {
                    EmptyPage(symbol: "tray", title: "No entries here yet", message: "Entries you write to this account appear here.")
                        .paperCard(padding: 0)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(list.prefix(150))) { entry in
                            Button { focused = entry } label: {
                                EntryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(Ink.rule)
                        }
                    }
                    .paperCard(padding: 14)
                }
            }
            .padding(18)
        }
        .paperBackground()
        .navigationTitle(Text(verbatim: account.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) { AccountEditor(account: account) }
        .sheet(item: $focused) { entry in EntryDetailSheet(entry: entry) }
    }

    private func balanceChart(_ list: [Transaction]) -> some View {
        let now = Date()
        let start = Calendar.current.date(byAdding: .month, value: -3, to: now) ?? now
        let worth = WorthAccount(id: account.id, currency: account.currencyCode, balanceNow: account.balance, since: .distantPast)
        let points = WorthMath.series(
            accounts: [worth],
            holdings: [],
            lines: list.filter { $0.date >= start }.ledgerLines,
            samples: WorthMath.samples(from: start, to: now, maxPoints: 40),
            convert: { amount, _ in amount }
        )
        return Chart(points) { point in
            LineMark(x: .value("Date", point.date), y: .value("Balance", Decimals.double(point.value)))
                .foregroundStyle(Color(hexString: account.colorHex))
                .interpolationMethod(.stepEnd)
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
    }
}
