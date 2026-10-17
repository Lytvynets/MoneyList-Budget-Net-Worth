import SwiftUI
import SwiftData

struct TodayScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.moneyPrefs) private var prefs
    @Environment(RateBook.self) private var rates
    @Environment(ProPass.self) private var pro
    @Environment(Router.self) private var router

    @Query(sort: \Transaction.date, order: .reverse) private var entries: [Transaction]
    @Query private var accounts: [Account]
    @Query private var rules: [RecurringRule]
    @Query private var budgets: [Budget]
    @Query private var holdings: [Asset]
    @Query private var profiles: [UserProfile]
    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]

    @AppStorage(AppConfig.Keys.maskAmounts) private var maskAmounts = false
    @State private var showPlanEditor = false
    @State private var showAllowanceInfo = false
    @State private var focusedEntry: Transaction?

    var body: some View {
        let digest = DigestBuilder.build(
            entries: entries,
            accounts: accounts,
            rules: rules,
            budgets: budgets,
            holdings: holdings,
            profile: profiles.first,
            home: prefs.home,
            convert: { amount, from, to in rates.convert(amount, from: from, to: to) }
        )
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    NoticeCard()
                    AllowanceCard(digest: digest, onSetPlan: { showPlanEditor = true }, onInfo: { showAllowanceInfo = true })
                    QuillBar(categories: categories, accounts: accounts, entries: entries)
                    if !digest.overdue.isEmpty {
                        OverdueCard(rules: digest.overdue, accounts: accounts)
                    }
                    MonthStrip(digest: digest)
                    if !digest.upcoming.isEmpty {
                        UpcomingCard(items: Array(digest.upcoming.prefix(5)), accounts: accounts)
                    }
                    todayEntries(digest: digest)
                    InsightsCard(entries: entries, digest: digest, categories: categories)
                    if !pro.isPro {
                        InlineBanner()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 36)
            }
            .scrollDismissesKeyboard(.interactively)
            .paperBackground()
            .trackScreen("today")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPlanEditor) {
                SpendingPlanSheet()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showAllowanceInfo) {
                AllowanceExplainer(digest: digest)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $focusedEntry) { entry in
                EntryDetailSheet(entry: entry)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Kicker(verbatim: Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                Text("Today")
                    .font(Typeface.display)
                    .foregroundStyle(Ink.text)
            }
            Spacer()
            Button {
                Haptic.tap()
                withAnimation(.snappy) { maskAmounts.toggle() }
            } label: {
                Image(systemName: maskAmounts ? "eye.slash" : "eye")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(Ink.sheet, in: Circle())
                    .overlay(Circle().strokeBorder(Ink.rule, lineWidth: 0.8))
            }
            .accessibilityLabel(maskAmounts ? Text("Show amounts") : Text("Hide amounts"))
            Button {
                router.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(Ink.sheet, in: Circle())
                    .overlay(Circle().strokeBorder(Ink.rule, lineWidth: 0.8))
            }
            .accessibilityLabel(Text("Settings"))
        }
        .foregroundStyle(Ink.text)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func todayEntries(digest: MoneyDigest) -> some View {
        let start = Calendar.current.startOfDay(for: Date())
        let todays = entries.prefix(while: { $0.date >= start || $0.date > Date() }).filter { $0.date >= start }
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading("Noted today") {
                Button {
                    router.tab = .ledger
                } label: {
                    Text("Ledger")
                        .font(Typeface.labelStrong)
                }
            }
            if todays.isEmpty {
                Text("Nothing noted yet. Write your first entry above — for example “lunch 12”.")
                    .font(Typeface.label)
                    .foregroundStyle(Ink.soft)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(todays.prefix(8))) { entry in
                        Button {
                            focusedEntry = entry
                        } label: {
                            EntryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        if entry.id != todays.prefix(8).last?.id {
                            Divider().overlay(Ink.rule)
                        }
                    }
                }
                .paperCard(padding: 14)
            }
        }
    }
}

/// Bills that wait for a tap before they are recorded.
struct OverdueCard: View {
    let rules: [RecurringRule]
    let accounts: [Account]

    @Environment(\.modelContext) private var context
    @Environment(\.moneyPrefs) private var prefs
    @Environment(RateBook.self) private var rates
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Kicker("Waiting for you", color: Ink.caution)
                Spacer()
            }
            ForEach(rules) { rule in
                HStack(spacing: 12) {
                    Glyph(symbol: rule.iconName ?? "calendar", hex: rule.colorHex ?? InkSwatch.ochre, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: rule.title)
                            .font(Typeface.labelStrong)
                            .foregroundStyle(Ink.text)
                        Text(verbatim: rule.nextDueDate.formatted(.dateTime.day().month(.abbreviated)))
                            .font(Typeface.detail)
                            .foregroundStyle(Ink.soft)
                    }
                    Spacer()
                    MoneyText(value: rule.amount, code: code(for: rule), size: .small)
                    Button {
                        RuleRunner.markPaid(rule, context: context)
                        Upkeep.afterChange(context: context, rates: rates)
                        Haptic.success()
                        toasts.show(String(localized: "Recorded \(rule.title)"))
                    } label: {
                        Text(rule.kind == .income ? "Got it" : "Paid")
                    }
                    .buttonStyle(InkButtonStyle(kind: .quiet, compact: true))
                }
            }
        }
        .paperCard()
    }

    private func code(for rule: RecurringRule) -> String {
        accounts.first { $0.id == rule.accountID }?.currencyCode ?? prefs.home
    }
}
