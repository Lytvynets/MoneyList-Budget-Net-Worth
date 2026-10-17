import SwiftUI
import SwiftData
import UIKit

// MARK: - Goals

struct GoalsPane: View {
    @Environment(\.modelContext) private var context
    @Environment(\.moneyPrefs) private var prefs
    @Environment(RateBook.self) private var rates
    @Environment(ProPass.self) private var pro
    @Environment(Router.self) private var router

    @Query(sort: \Goal.sortOrder) private var goals: [Goal]
    @Query private var accounts: [Account]

    @State private var editing: GoalTarget?
    @State private var topUp: Goal?

    struct GoalTarget: Identifiable {
        let id = UUID()
        var goal: Goal?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if goals.isEmpty {
                EmptyPage(
                    symbol: "flag.checkered",
                    title: "Nothing to save for yet?",
                    message: "A trip, a laptop, a safety cushion. Set a target and Money List shows when you'll get there.",
                    actionTitle: "New goal",
                    action: addGoal
                )
                .paperCard(padding: 0)
            } else {
                summary
                ForEach(goals) { goal in
                    Button {
                        editing = GoalTarget(goal: goal)
                    } label: {
                        GoalCard(goal: goal, saved: saved(goal), onTopUp: goal.tracking == .manual ? { topUp = goal } : nil)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: addGoal) {
                    Label(String(localized: "New goal"), systemImage: "plus")
                }
                .buttonStyle(InkButtonStyle(kind: .outline))
            }
        }
        .sheet(item: $editing) { target in
            GoalEditor(goal: target.goal)
        }
        .sheet(item: $topUp) { goal in
            GoalTopUpSheet(goal: goal)
                .presentationDetents([.height(320)])
        }
    }

    private var summary: some View {
        let home = prefs.home
        var targets: Decimal = 0
        var manual: Decimal = 0
        var walletGoalsTarget: Decimal = 0
        var accountIDs = Set<UUID>()
        var usesAll = false
        for goal in goals {
            targets += rates.convert(goal.targetAmount, from: goal.currencyCode, to: home)
            switch goal.tracking {
            case .manual:
                manual += rates.convert(min(goal.manualSaved ?? 0, goal.targetAmount), from: goal.currencyCode, to: home)
            case .wallets:
                walletGoalsTarget += rates.convert(goal.targetAmount, from: goal.currencyCode, to: home)
                if goal.linkedAccountIDs.isEmpty { usesAll = true } else { accountIDs.formUnion(goal.linkedAccountIDs) }
            }
        }
        let pool = accounts.filter { !$0.isArchived && !$0.kind.isLiability && (usesAll || accountIDs.contains($0.id)) }
        let walletSaved = pool.reduce(Decimal(0)) { $0 + max(rates.convert($1.balance, from: $1.currencyCode, to: home), 0) }
        let saved = min(walletSaved, walletGoalsTarget) + manual

        return VStack(alignment: .leading, spacing: 10) {
            Kicker("Saved toward goals")
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                MoneyText(value: saved, code: home, size: .large, tone: Ink.gain, cents: false)
                Text("of").font(Typeface.label).foregroundStyle(Ink.soft)
                MoneyText(value: targets, code: home, size: .small, tone: Ink.soft, cents: false)
            }
            PaceBar(fraction: Decimals.ratio(saved, of: targets), tint: Ink.gain)
        }
        .paperCard()
    }

    private func saved(_ goal: Goal) -> Decimal {
        switch goal.tracking {
        case .manual:
            return goal.manualSaved ?? 0
        case .wallets:
            let pool = goal.linkedAccountIDs.isEmpty
                ? accounts.filter { !$0.isArchived && !$0.kind.isLiability }
                : accounts.filter { goal.linkedAccountIDs.contains($0.id) }
            return pool.reduce(Decimal(0)) { $0 + rates.convert($1.balance, from: $1.currencyCode, to: goal.currencyCode) }
        }
    }

    private func addGoal() {
        if pro.allows(goals: goals.count) {
            editing = GoalTarget(goal: nil)
        } else {
            router.showPaywall = true
        }
    }
}

struct GoalCard: View {
    let goal: Goal
    let saved: Decimal
    var onTopUp: (() -> Void)?

    var body: some View {
        let outlook = GoalMath.outlook(saved: saved, target: goal.targetAmount, monthly: goal.monthlyContribution, targetDate: goal.targetDate, now: Date())
        let tint = Color(hexString: goal.colorHex ?? InkSwatch.moss)
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                InkRing(fraction: outlook.fraction, tint: tint, lineWidth: 5)
                if let data = goal.customImageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    Image(systemName: goal.iconName ?? "flag.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: goal.name)
                        .font(Typeface.heading)
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                    Spacer()
                    statusStamp(outlook.status)
                }
                HStack(spacing: 4) {
                    MoneyText(value: outlook.saved, code: goal.currencyCode, size: .small, cents: false)
                    Text(verbatim: "/").foregroundStyle(Ink.faint)
                    MoneyText(value: goal.targetAmount, code: goal.currencyCode, size: .small, tone: Ink.soft, cents: false)
                    Spacer()
                    Text(verbatim: "\(Int((outlook.fraction * 100).rounded()))%")
                        .font(Typeface.smallFigure)
                        .foregroundStyle(Ink.soft)
                }
                if let line = outlookLine(outlook) {
                    Text(verbatim: line)
                        .font(Typeface.detail)
                        .foregroundStyle(Ink.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let onTopUp, outlook.status != .reached {
                    Button(action: onTopUp) {
                        Label(String(localized: "Add money"), systemImage: "plus")
                    }
                    .buttonStyle(InkButtonStyle(kind: .quiet, compact: true))
                    .padding(.top, 2)
                }
            }
        }
        .paperCard()
    }

    @ViewBuilder
    private func statusStamp(_ status: GoalOutlook.Status) -> some View {
        switch status {
        case .reached: Stamp("Reached", tone: Ink.gain)
        case .onTrack: Stamp("On track", tone: Ink.gain)
        case .behind: Stamp("Behind", tone: Ink.caution)
        case .open: EmptyView()
        }
    }

    private func outlookLine(_ outlook: GoalOutlook) -> String? {
        if outlook.status == .reached { return String(localized: "Done. Time to pick the next one.") }
        var parts: [String] = []
        if let needed = outlook.neededPerMonth, let date = goal.targetDate {
            let amount = MoneyFormat.plain(needed, code: goal.currencyCode, cents: false)
            let when = date.formatted(.dateTime.month(.abbreviated).year())
            parts.append(String(localized: "\(amount) a month to finish by \(when)"))
        }
        if let finish = outlook.projectedFinish {
            let when = finish.formatted(.dateTime.month(.wide).year())
            parts.append(String(localized: "At your pace: \(when)"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct GoalTopUpSheet: View {
    let goal: Goal

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RateBook.self) private var rates
    @State private var text = ""
    @State private var withdraw = false

    var body: some View {
        EditorChrome(Text(verbatim: goal.name), canSave: AmountField.value(text).map { $0 > 0 } ?? false, onSave: save) {
            SegmentRail(items: [(false, "Add"), (true, "Take out")], selection: $withdraw)
            AmountField(title: "Amount", text: $text, currency: goal.currencyCode)
                .paperCard()
            HStack(spacing: 4) {
                Text("Saved so far").foregroundStyle(Ink.soft)
                MoneyText(value: goal.manualSaved ?? 0, code: goal.currencyCode, size: .tiny)
            }
            .font(Typeface.detail)
        }
    }

    private func save() {
        guard let value = AmountField.value(text), value > 0 else { return }
        let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
        try? writer.addToGoal(goal, amount: withdraw ? -value : value)
        Haptic.success()
        dismiss()
    }
}

// MARK: - Bills

struct BillsPane: View {
    @Environment(\.modelContext) private var context
    @Environment(\.moneyPrefs) private var prefs
    @Environment(RateBook.self) private var rates
    @Environment(ProPass.self) private var pro
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts

    @Query(sort: \RecurringRule.nextDueDate) private var rules: [RecurringRule]
    @Query private var accounts: [Account]

    @State private var editing: BillTarget?

    struct BillTarget: Identifiable {
        let id = UUID()
        var rule: RecurringRule?
    }

    var body: some View {
        let home = prefs.home
        let active = rules.filter { $0.isActive }
        let paused = rules.filter { !$0.isActive }
        let monthlyOut = active.filter { $0.kind == .expense }.reduce(Decimal(0)) { $0 + rates.convert($1.cadence.monthlyShare(of: $1.amount), from: code(for: $1), to: home) }
        let monthlyIn = active.filter { $0.kind == .income }.reduce(Decimal(0)) { $0 + rates.convert($1.cadence.monthlyShare(of: $1.amount), from: code(for: $1), to: home) }
        let subscriptions = active.filter { $0.isSubscription && $0.kind == .expense }
        let subsYearly = subscriptions.reduce(Decimal(0)) { $0 + rates.convert($1.amount * $1.cadence.timesPerYear, from: code(for: $1), to: home) }

        VStack(alignment: .leading, spacing: 16) {
            if rules.isEmpty {
                EmptyPage(
                    symbol: "calendar.badge.clock",
                    title: "Bills that come back",
                    message: "Rent, phone, streaming, salary. Add them once — Money List records them on time and reminds you before they're due.",
                    actionTitle: "Add a bill",
                    action: addBill
                )
                .paperCard(padding: 0)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Kicker("Every month, roughly")
                    LeaderRow { Text("Going out").font(Typeface.label).foregroundStyle(Ink.soft) } trailing: {
                        MoneyText(value: monthlyOut, code: home, size: .small, cents: false)
                    }
                    if monthlyIn > 0 {
                        LeaderRow { Text("Coming in").font(Typeface.label).foregroundStyle(Ink.soft) } trailing: {
                            MoneyText(value: monthlyIn, code: home, size: .small, tone: Ink.gain, cents: false)
                        }
                    }
                    if !subscriptions.isEmpty {
                        LeaderRow { Text("Subscriptions a year").font(Typeface.label).foregroundStyle(Ink.soft) } trailing: {
                            MoneyText(value: subsYearly, code: home, size: .small, cents: false)
                        }
                    }
                }
                .paperCard()

                VStack(spacing: 0) {
                    ForEach(active) { rule in
                        BillRow(rule: rule, code: code(for: rule))
                            .contentShape(Rectangle())
                            .onTapGesture { editing = BillTarget(rule: rule) }
                            .contextMenu { menu(for: rule) }
                        if rule.id != active.last?.id {
                            Divider().overlay(Ink.rule)
                        }
                    }
                }
                .paperCard(padding: 14)

                if !paused.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Kicker("Paused")
                        ForEach(paused) { rule in
                            BillRow(rule: rule, code: code(for: rule))
                                .opacity(0.55)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = BillTarget(rule: rule) }
                                .contextMenu { menu(for: rule) }
                        }
                    }
                    .paperCard(padding: 14)
                }

                Button(action: addBill) {
                    Label(String(localized: "Add a bill"), systemImage: "plus")
                }
                .buttonStyle(InkButtonStyle(kind: .outline))

                Text("Long-press a bill to pay it early, skip one time or pause it.")
                    .font(Typeface.detail)
                    .foregroundStyle(Ink.faint)
            }
        }
        .sheet(item: $editing) { target in
            BillEditor(rule: target.rule)
        }
    }

    @ViewBuilder
    private func menu(for rule: RecurringRule) -> some View {
        if rule.isActive {
            Button {
                RuleRunner.markPaid(rule, context: context)
                Upkeep.afterChange(context: context, rates: rates)
                toasts.show(String(localized: "Recorded \(rule.title)"))
            } label: {
                Label(rule.kind == .income ? String(localized: "Record it now") : String(localized: "Pay now"), systemImage: "checkmark.circle")
            }
            Button {
                RuleRunner.skip(rule, context: context)
                Upkeep.afterChange(context: context, rates: rates)
            } label: {
                Label(String(localized: "Skip this time"), systemImage: "forward")
            }
            Button {
                rule.isActive = false
                try? context.save()
                Upkeep.afterChange(context: context, rates: rates)
            } label: {
                Label(String(localized: "Pause"), systemImage: "pause.circle")
            }
        } else {
            Button {
                rule.isActive = true
                if rule.nextDueDate < Calendar.current.startOfDay(for: Date()) {
                    rule.nextDueDate = Recurrence.next(after: Date(), anchor: rule.anchorDate, cadence: rule.cadence)
                    rule.cycleIndex = Recurrence.firstIndex(onOrAfter: rule.nextDueDate, anchor: rule.anchorDate, cadence: rule.cadence)
                }
                try? context.save()
                Upkeep.afterChange(context: context, rates: rates)
            } label: {
                Label(String(localized: "Resume"), systemImage: "play.circle")
            }
        }
        Button(role: .destructive) {
            let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
            try? writer.deleteRule(rule)
            Upkeep.afterChange(context: context, rates: rates)
        } label: {
            Label(String(localized: "Delete"), systemImage: "trash")
        }
    }

    private func code(for rule: RecurringRule) -> String {
        accounts.first { $0.id == rule.accountID }?.currencyCode ?? prefs.home
    }

    private func addBill() {
        if pro.allows(bills: rules.filter(\.isActive).count) {
            editing = BillTarget(rule: nil)
        } else {
            router.showPaywall = true
        }
    }
}

struct BillRow: View {
    let rule: RecurringRule
    let code: String

    var body: some View {
        HStack(spacing: 12) {
            DateTag(date: rule.nextDueDate)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: rule.title)
                        .font(Typeface.labelStrong)
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                    if rule.isSubscription {
                        Image(systemName: "repeat")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Ink.soft)
                    }
                }
                HStack(spacing: 4) {
                    Text(verbatim: CadenceText.title(rule.cadence))
                    Text(verbatim: "·")
                    Text(rule.autoPost ? "Records itself" : "Asks first")
                }
                .font(Typeface.detail)
                .foregroundStyle(Ink.soft)
            }
            Spacer()
            MoneyText(value: rule.amount, code: code, size: .small, signed: rule.kind == .income, tone: rule.kind == .income ? Ink.gain : Ink.text)
        }
        .padding(.vertical, 8)
    }
}
