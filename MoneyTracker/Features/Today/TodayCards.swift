import SwiftUI
import SwiftData

// MARK: - Allowance

struct AllowanceCard: View {
    let digest: MoneyDigest
    var onSetPlan: () -> Void
    var onInfo: () -> Void

    @Environment(\.inkAccent) private var accent

    private var allowance: Allowance { digest.allowance }
    private var left: Decimal { allowance.leftToday }
    private var isOver: Bool { left < 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Kicker(isOver ? "Over today's allowance" : "Left to spend today", color: isOver ? Ink.loss : Ink.soft)
                Spacer()
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Ink.soft)
                }
                .accessibilityLabel(Text("How this is calculated"))
            }

            MoneyText(value: Decimals.abs(left), code: digest.home, size: .hero, tone: isOver ? Ink.loss : Ink.text, cents: false)
                .padding(.horizontal, 2)
                .highlighter(!isOver && left > 0)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Text("Per day")
                    .foregroundStyle(Ink.soft)
                MoneyText(value: allowance.daily, code: digest.home, size: .tiny, cents: false)
                Text(verbatim: "·").foregroundStyle(Ink.faint)
                Text("spent today")
                    .foregroundStyle(Ink.soft)
                MoneyText(value: digest.spentToday, code: digest.home, size: .tiny, cents: false)
            }
            .font(Typeface.detail)

            PaceBar(fraction: allowance.usedFraction, tint: isOver ? Ink.loss : accent, height: 5)

            HStack(alignment: .center) {
                switch allowance.basis {
                case .plan(let plan):
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: daysLeftText)
                            .font(Typeface.detail)
                            .foregroundStyle(Ink.soft)
                        HStack(spacing: 4) {
                            Text(digest.planFromBudgets ? "Budgets total" : "Monthly plan")
                            MoneyText(value: plan, code: digest.home, size: .tiny, cents: false)
                        }
                        .font(Typeface.detail)
                        .foregroundStyle(Ink.soft)
                    }
                    Spacer()
                    paceStamp
                case .balance:
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: daysLeftText)
                            .font(Typeface.detail)
                            .foregroundStyle(Ink.soft)
                        Text("Based on your balance")
                            .font(Typeface.detail)
                            .foregroundStyle(Ink.soft)
                    }
                    Spacer()
                    Button(action: onSetPlan) {
                        Text("Set a plan")
                    }
                    .buttonStyle(InkButtonStyle(kind: .quiet, compact: true))
                }
            }
        }
        .paperCard(padding: 18)
    }

    private var daysLeftText: String {
        let monthName = digest.month.start.formatted(.dateTime.month(.wide))
        return String(localized: "\(allowance.daysLeft) days left") + " · " + monthName
    }

    @ViewBuilder
    private var paceStamp: some View {
        let delta = allowance.paceDelta
        if delta > 0 {
            VStack(alignment: .trailing, spacing: 4) {
                Stamp("Under pace", tone: Ink.gain)
                MoneyText(value: delta, code: digest.home, size: .tiny, tone: Ink.gain, cents: false)
            }
        } else if delta < 0 {
            VStack(alignment: .trailing, spacing: 4) {
                Stamp("Over pace", tone: Ink.loss)
                MoneyText(value: -delta, code: digest.home, size: .tiny, tone: Ink.loss, cents: false)
            }
        } else {
            Stamp("On pace", tone: Ink.soft)
        }
    }
}

struct AllowanceExplainer: View {
    let digest: MoneyDigest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch digest.allowance.basis {
                    case .plan(let plan):
                        Text("Your monthly plan, minus bills, spread over the days that are left.")
                            .font(Typeface.body)
                            .foregroundStyle(Ink.text)
                        VStack(spacing: 10) {
                            LeaderRow { Text(digest.planFromBudgets ? "Budgets total" : "Monthly plan") } trailing: {
                                MoneyText(value: plan, code: digest.home, size: .small)
                            }
                            LeaderRow { Text("Bills this month") } trailing: {
                                MoneyText(value: digest.allowance.billsReserved, code: digest.home, size: .small)
                            }
                            LeaderRow { Text("Days left") } trailing: {
                                Text(verbatim: "\(digest.allowance.daysLeft)").font(Typeface.smallFigure)
                            }
                            LeaderRow { Text("Daily allowance") } trailing: {
                                MoneyText(value: digest.allowance.daily, code: digest.home, size: .small)
                            }
                        }
                        .font(Typeface.label)
                        .foregroundStyle(Ink.soft)
                        .paperCard()
                        Text("Bills are set aside first, so a rent payment doesn't wipe out a single day. Spend less today and tomorrow's allowance grows.")
                            .font(Typeface.label)
                            .foregroundStyle(Ink.soft)
                    case .balance(let balance):
                        Text("Without a plan, the allowance comes from the money in your everyday accounts, minus bills still due this month, spread over the days that are left.")
                            .font(Typeface.body)
                            .foregroundStyle(Ink.text)
                        VStack(spacing: 10) {
                            LeaderRow { Text("Everyday accounts") } trailing: {
                                MoneyText(value: balance, code: digest.home, size: .small)
                            }
                            LeaderRow { Text("Bills still due") } trailing: {
                                MoneyText(value: digest.allowance.billsReserved, code: digest.home, size: .small)
                            }
                            LeaderRow { Text("Days left") } trailing: {
                                Text(verbatim: "\(digest.allowance.daysLeft)").font(Typeface.smallFigure)
                            }
                        }
                        .font(Typeface.label)
                        .foregroundStyle(Ink.soft)
                        .paperCard()
                        Text("Savings, credit cards and loans are not counted. You can change which accounts count in Wealth → account settings.")
                            .font(Typeface.label)
                            .foregroundStyle(Ink.soft)
                    }
                }
                .padding(20)
            }
            .paperBackground()
            .navigationTitle(Text("Daily allowance"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Month strip

struct MonthStrip: View {
    let digest: MoneyDigest

    @State private var selected: Int?
    @Environment(\.inkAccent) private var accent
    @Environment(\.masksAmounts) private var masked

    var body: some View {
        let bars = digest.dayBars.map(Decimals.double)
        let daily = Decimals.double(digest.allowance.daily)
        let peak = max(bars.max() ?? 0, daily * 1.4, 1)
        let todayIndex = digest.todayIndex ?? (bars.count - 1)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Kicker(verbatim: digest.month.start.formatted(.dateTime.month(.wide).year()))
                Spacer()
                if let selected, selected < bars.count {
                    let day = digest.periods.days(in: digest.month)[selected]
                    HStack(spacing: 4) {
                        Text(verbatim: day.formatted(.dateTime.day().month(.abbreviated)))
                            .foregroundStyle(Ink.soft)
                        MoneyText(value: digest.dayBars[selected], code: digest.home, size: .tiny)
                    }
                    .font(Typeface.detail)
                } else {
                    HStack(spacing: 4) {
                        Text("Spent")
                            .foregroundStyle(Ink.soft)
                        MoneyText(value: digest.monthTally.expense, code: digest.home, size: .tiny, cents: false)
                        if let plan = digest.plan {
                            Text(verbatim: "/").foregroundStyle(Ink.faint)
                            MoneyText(value: plan, code: digest.home, size: .tiny, tone: Ink.soft, cents: false)
                        }
                    }
                    .font(Typeface.detail)
                }
            }

            GeometryReader { proxy in
                let count = max(bars.count, 1)
                let gap: CGFloat = count > 28 ? 3 : 4
                let width = max((proxy.size.width - gap * CGFloat(count - 1)) / CGFloat(count), 2)
                ZStack(alignment: .bottomLeading) {
                    if daily > 0 {
                        Path { path in
                            let y = proxy.size.height * (1 - CGFloat(daily / peak))
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        }
                        .stroke(Ink.ruleStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(bars.indices, id: \.self) { index in
                            let value = bars[index]
                            let isFuture = index > todayIndex
                            let isToday = index == todayIndex
                            let height = isFuture ? 2 : max(CGFloat(value / peak) * proxy.size.height, value > 0 ? 3 : 2)
                            RoundedRectangle(cornerRadius: min(width / 2, 3), style: .continuous)
                                .fill(color(value: value, daily: daily, isToday: isToday, isFuture: isFuture, isSelected: selected == index))
                                .frame(width: width, height: masked && !isFuture ? 8 : height)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard !isFuture else { return }
                                    Haptic.tap()
                                    withAnimation(.snappy) { selected = selected == index ? nil : index }
                                }
                        }
                    }
                }
            }
            .frame(height: 74)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Daily spending this month"))
        }
        .paperCard()
    }

    private func color(value: Double, daily: Double, isToday: Bool, isFuture: Bool, isSelected: Bool) -> Color {
        if isFuture { return Ink.rule }
        if isSelected { return accent }
        if daily > 0 && value > daily { return Ink.loss.opacity(0.85) }
        if isToday { return accent.opacity(0.85) }
        return Ink.text.opacity(value > 0 ? 0.72 : 0.15)
    }
}

// MARK: - Upcoming

struct UpcomingCard: View {
    let items: [RuleRunner.Upcoming]
    let accounts: [Account]

    @Environment(\.moneyPrefs) private var prefs
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Coming up") {
                Button {
                    router.tab = .plan
                } label: {
                    Text("All bills").font(Typeface.labelStrong)
                }
            }
            VStack(spacing: 10) {
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        DateTag(date: item.date)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: item.rule.title)
                                .font(Typeface.labelStrong)
                                .foregroundStyle(Ink.text)
                                .lineLimit(1)
                            Text(verbatim: relative(item.date))
                                .font(Typeface.detail)
                                .foregroundStyle(Ink.soft)
                        }
                        Spacer()
                        MoneyText(
                            value: item.rule.amount,
                            code: accounts.first { $0.id == item.rule.accountID }?.currencyCode ?? prefs.home,
                            size: .small,
                            signed: item.rule.kind == .income,
                            tone: item.rule.kind == .income ? Ink.gain : Ink.text
                        )
                    }
                }
            }
            .paperCard(padding: 14)
        }
    }

    private func relative(_ date: Date) -> String {
        let days = Recurrence.daysBetween(Date(), date)
        if days < 0 { return String(localized: "Overdue") }
        if days == 0 { return String(localized: "Today") }
        if days == 1 { return String(localized: "Tomorrow") }
        return String(localized: "In \(days) days")
    }
}

/// Small calendar-page tag: weekday over day number.
struct DateTag: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.system(size: 9, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(Ink.soft)
            Text(verbatim: date.formatted(.dateTime.day()))
                .font(Typeface.figure(17, weight: .semibold))
                .foregroundStyle(Ink.text)
        }
        .frame(width: 38, height: 40)
        .background(Ink.raised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Ink.rule, lineWidth: 0.8))
    }
}
