import SwiftUI
import SwiftData
import Foundation

/// First launch: a short, useful setup instead of a slideshow.
struct WelcomeFlow: View {
    var onFinish: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(RateBook.self) private var rates
    @Environment(LockKeeper.self) private var lock
    @Environment(\.inkAccent) private var accent

    @State private var step = 0
    @State private var currency = Locale.current.currency?.identifier ?? "USD"
    @State private var balanceText = ""
    @State private var walletKind: WalletKind = .card
    @State private var planText = ""
    @State private var startDay = 1
    @State private var remind = true
    @State private var lockOn = false
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? accent : Ink.rule)
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .opacity(step == 0 ? 0 : 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch step {
                    case 0: intro
                    case 1: currencyStep
                    case 2: balanceStep
                    case 3: planStep
                    default: finishStep
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 24)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 10) {
                Button(action: next) {
                    Text(primaryTitle)
                }
                .buttonStyle(InkButtonStyle(kind: .solid))
                .disabled(working)
                if step == 2 || step == 3 {
                    Button("Skip for now") { advance() }
                        .font(Typeface.labelStrong)
                        .foregroundStyle(Ink.soft)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .paperBackground()
        .trackScreen("onboarding")
    }

    private var primaryTitle: LocalizedStringKey {
        switch step {
        case 0: return "Start"
        case 4: return "Open my ledger"
        default: return "Continue"
        }
    }

    // MARK: Steps

    private var intro: some View {
        VStack(alignment: .leading, spacing: 26) {
            LedgerMark(size: 88, animated: true)
                .padding(.top, 30)
            VStack(alignment: .leading, spacing: 10) {
                Text("Your money,\nwritten down plainly.")
                    .font(Typeface.figure(34, weight: .semibold))
                    .foregroundStyle(Ink.text)
                Text("Write entries like notes, see what you can spend today, and watch your net worth — privately, on your iPhone.")
                    .font(Typeface.body)
                    .foregroundStyle(Ink.soft)
            }
            QuillDemo()
            VStack(alignment: .leading, spacing: 12) {
                promise("lock.shield", "No account, no bank login. Your data stays on your devices and private iCloud.")
                promise("sun.max", "A daily allowance that adjusts as you spend.")
                promise("calendar.badge.clock", "Bills and subscriptions recorded on time.")
            }
        }
    }

    private func promise(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 24)
            Text(text)
                .font(Typeface.label)
                .foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var currencyStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Which currency do you think in?", "Totals and your daily allowance use it. Accounts can still be in any currency.")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Array(CurrencyMenu.frequent.prefix(12)), id: \.self) { code in
                    Button {
                        Haptic.tap()
                        currency = code
                    } label: {
                        VStack(spacing: 4) {
                            Text(verbatim: MoneyFormat.symbol(for: code))
                                .font(Typeface.figure(22, weight: .medium))
                            Text(verbatim: code)
                                .font(Typeface.detail)
                        }
                        .foregroundStyle(currency == code ? Color.white : Ink.text)
                        .frame(maxWidth: .infinity, minHeight: 66)
                        .background(currency == code ? accent : Ink.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ink.rule))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Text("Something else?")
                    .font(Typeface.label)
                    .foregroundStyle(Ink.soft)
                Spacer()
                CurrencyMenu(code: $currency)
            }
        }
    }

    private var balanceStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("How much do you have right now?", "Roughly is fine — you can add more accounts later.")
            HStack(spacing: 10) {
                ForEach([WalletKind.card, .cash, .savings], id: \.self) { kind in
                    Button {
                        Haptic.tap()
                        walletKind = kind
                    } label: {
                        Chip(verbatim: kind.title, symbol: kind.symbol, selected: walletKind == kind)
                    }
                    .buttonStyle(.plain)
                }
            }
            AmountField(title: "0", text: $balanceText, currency: currency)
                .paperCard()
        }
    }

    private var planStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("A monthly spending plan", "Everything you expect to spend in a month, bills included. Money List turns it into a daily allowance.")
            AmountField(title: "0", text: $planText, currency: currency)
                .paperCard()
            if let plan = AmountField.value(planText), plan > 0 {
                let periods = PeriodCalendar(startDay: startDay)
                let days = periods.dayCount(in: periods.month(containing: Date()))
                HStack(spacing: 6) {
                    Text("That's about")
                    MoneyText(value: plan / Decimal(max(days, 1)), code: currency, size: .small, cents: false)
                        .highlighter()
                    Text("a day.")
                }
                .font(Typeface.label)
                .foregroundStyle(Ink.text)
            }
            Stepper(value: $startDay, in: 1...28) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("My month starts on day \(startDay)")
                        .font(Typeface.label)
                        .foregroundStyle(Ink.text)
                    Text("Handy if you're paid on a fixed day.")
                        .font(Typeface.detail)
                        .foregroundStyle(Ink.soft)
                }
            }
            .paperCard()
        }
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Two small helpers", "Both are optional and can be changed in Settings.")
            Toggle(isOn: $remind) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Evening reminder")
                    Text("A quiet nudge at 9 pm to note the day.")
                        .font(Typeface.detail)
                        .foregroundStyle(Ink.soft)
                }
            }
            .paperCard()
            if lock.canUseDeviceAuth {
                Toggle(isOn: $lockOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lock with \(lock.methodName)")
                        Text("Keeps your numbers away from curious eyes.")
                            .font(Typeface.detail)
                            .foregroundStyle(Ink.soft)
                    }
                }
                .paperCard()
            }
        }
    }

    private func stepTitle(_ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Typeface.title)
                .foregroundStyle(Ink.text)
            Text(detail)
                .font(Typeface.label)
                .foregroundStyle(Ink.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Flow

    private func next() {
        Haptic.tap()
        if step < 4 {
            advance()
        } else {
            Task { await finish() }
        }
    }

    private func advance() {
        withAnimation(.snappy(duration: 0.35)) { step = min(step + 1, 4) }
        Telemetry.event("onboarding_step", ["step": step])
    }

    private func finish() async {
        working = true
        Seeder.seedIfEmpty(context: context, currency: currency)
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        if let profile = profiles.first {
            profile.defaultCurrencyCode = currency
            if let plan = AmountField.value(planText), plan > 0 { profile.monthlyPlan = plan }
            profile.periodStartDay = startDay == 1 ? nil : startDay
        }
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let untouched = accounts.count == 1 && (accounts.first?.transactions?.isEmpty ?? true) && (accounts.first?.openingBalance ?? 0) == 0
        if untouched, let wallet = accounts.first {
            wallet.currencyCode = currency
            wallet.kind = walletKind
            wallet.name = walletKind == .card ? String(localized: "Card") : (walletKind == .cash ? String(localized: "Wallet") : String(localized: "Savings"))
            if let balance = AmountField.value(balanceText) {
                wallet.openingBalance = balance
                wallet.balance = balance
            }
        }
        try? context.save()

        if remind, await Reminders.requestPermission() {
            UserDefaults.standard.set(true, forKey: AppConfig.Keys.dailyReminder)
            UserDefaults.standard.set(21 * 60, forKey: AppConfig.Keys.dailyReminderMinutes)
            Reminders.scheduleDaily(minutesAfterMidnight: 21 * 60)
        }
        if lockOn { _ = await lock.confirmAndEnable() }
        Telemetry.event("onboarding_complete", [
            "currency": currency,
            "has_balance": AmountField.value(balanceText) != nil,
            "has_plan": (AmountField.value(planText) ?? 0) > 0,
            "month_start_day": startDay,
            "reminder": remind,
            "lock": lockOn
        ])
        working = false
        onFinish()
    }
}

/// A looping demo of the quick line: typing, then the parsed chips.
struct QuillDemo: View {
    @State private var typed = ""
    @State private var showChips = false
    @Environment(\.inkAccent) private var accent

    private let sample = String(localized: "coffee 4.50")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "pencil.line").foregroundStyle(accent)
                Text(verbatim: typed.isEmpty ? " " : typed)
                    .font(Typeface.body)
                    .foregroundStyle(Ink.text)
                Rectangle().fill(accent).frame(width: 2, height: 20).opacity(showChips ? 0 : 1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Ink.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ink.ruleStrong, lineWidth: 0.8))
            HStack(spacing: 8) {
                // Must match the number in the localized "coffee 4.50" sample.
                Chip("4.50", selected: true, tint: Ink.text)
                Chip("Food & Drinks", symbol: "fork.knife", dashed: true)
                Chip("Today", symbol: "calendar")
            }
            .opacity(showChips ? 1 : 0)
            .offset(y: showChips ? 0 : 6)
        }
        .task { await loop() }
        .accessibilityHidden(true)
    }

    private func loop() async {
        while !Task.isCancelled {
            typed = ""
            showChips = false
            try? await Task.sleep(nanoseconds: 500_000_000)
            for character in sample {
                typed.append(character)
                try? await Task.sleep(nanoseconds: 110_000_000)
            }
            withAnimation(.snappy) { showChips = true }
            try? await Task.sleep(nanoseconds: 2_600_000_000)
        }
    }
}

/// Shown once to people updating from version 1.
struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let items: [(String, LocalizedStringKey, LocalizedStringKey)] = [
        ("pencil.line", "Write it like a note", "“coffee 4.50”, “taxi 120 yesterday” — saved and categorized in one line."),
        ("sun.max", "Daily allowance", "What you can spend today, adjusted as you go."),
        ("calendar.badge.clock", "Bills & subscriptions", "Recorded on the day, with reminders beforehand."),
        ("chart.xyaxis.line", "Net worth over time", "History, debts and investments in one picture."),
        ("square.and.arrow.down", "Import from any app", "Bring your history over from a CSV file."),
        ("wave.3.right", "Apple Pay auto-log", "Let Shortcuts record Wallet payments for you."),
        ("arrow.uturn.forward", "Budgets that repeat", "Set a limit once; it carries into every month.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LedgerMark(size: 60)
                        .padding(.top, 30)
                    VStack(alignment: .leading, spacing: 6) {
                        Kicker("Money List 2.0")
                        Text("A fresh page")
                            .font(Typeface.display)
                            .foregroundStyle(Ink.text)
                        Text("Your data is all here. Everything around it was rebuilt.")
                            .font(Typeface.label)
                            .foregroundStyle(Ink.soft)
                    }
                    ForEach(items.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: items[index].0)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Ink.text)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(items[index].1)
                                    .font(Typeface.labelStrong)
                                    .foregroundStyle(Ink.text)
                                Text(items[index].2)
                                    .font(Typeface.detail)
                                    .foregroundStyle(Ink.soft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            Button { dismiss() } label: { Text("Let's go") }
                .buttonStyle(InkButtonStyle(kind: .solid))
                .padding(24)
        }
        .paperBackground()
    }
}
