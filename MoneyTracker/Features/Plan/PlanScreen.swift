import SwiftUI
import SwiftData

struct PlanScreen: View {
    enum Pane: Hashable { case budgets, goals, bills }

    @State private var pane: Pane = .budgets

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker("Budgets, goals and bills")
                        Text("Plan")
                            .font(Typeface.display)
                            .foregroundStyle(Ink.text)
                    }
                    .padding(.top, 8)
                    SegmentRail(items: [(Pane.budgets, "Budgets"), (Pane.goals, "Goals"), (Pane.bills, "Bills")], selection: $pane)
                    switch pane {
                    case .budgets: BudgetsPane().trackScreen("budgets")
                    case .goals: GoalsPane().trackScreen("goals")
                    case .bills: BillsPane().trackScreen("bills")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 90)
            }
            .paperBackground()
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) { WriteButton() }
        }
    }
}

// MARK: - Budgets

struct BudgetsPane: View {
    @Environment(\.modelContext) private var context
    @Environment(\.moneyPrefs) private var prefs
    @Environment(RateBook.self) private var rates
    @Environment(ProPass.self) private var pro
    @Environment(Router.self) private var router

    @Query private var budgets: [Budget]
    @Query(sort: \Transaction.date, order: .reverse) private var entries: [Transaction]
    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]

    @State private var offset = 0
    @State private var editing: BudgetTarget?
    @State private var showPlan = false

    struct BudgetTarget: Identifiable {
        let id = UUID()
        var category: TransactionCategory?
        var limit: Decimal?
    }

    var body: some View {
        let periods = prefs.periods
        let month = periods.shifted(periods.month(containing: Date()), by: offset)
        let home = prefs.home
        let tally = Tally.make(entries.filter { month.contains($0.date) }.ledgerLines, from: month.start, to: month.end) { amount, code in
            rates.convert(amount, from: code.isEmpty ? home : code, to: home)
        }
        let records = budgets.compactMap { budget -> BudgetRecord? in
            guard let id = budget.category?.id else { return nil }
            return BudgetRecord(recordID: budget.id, categoryID: id, month: budget.month, limit: budget.limitAmount)
        }
        let lines = BudgetMath.lines(records: records, month: month, spentByCategory: tally.expenseByCategory, periods: periods, now: Date())
        let budgeted = Set(lines.map(\.categoryID))
        let unbudgeted = tally.expenseShares().filter { share in
            guard let id = share.id else { return false }
            return !budgeted.contains(id)
        }
        let totalLimit = lines.reduce(Decimal(0)) { $0 + $1.limit }
        let totalSpent = lines.reduce(Decimal(0)) { $0 + $1.spent }
        let paceShare = lines.first.map { $0.paceFraction } ?? 0

        VStack(alignment: .leading, spacing: 16) {
            MonthSwitcher(month: month, offset: $offset, periods: periods)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Kicker("Budgeted spending")
                    Spacer()
                    Button {
                        showPlan = true
                    } label: {
                        Text("Monthly plan").font(Typeface.labelStrong)
                    }
                }
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    MoneyText(value: totalSpent, code: home, size: .large, cents: false)
                    Text("of").font(Typeface.label).foregroundStyle(Ink.soft)
                    MoneyText(value: totalLimit, code: home, size: .small, tone: Ink.soft, cents: false)
                }
                PaceBar(fraction: Decimals.ratio(totalSpent, of: totalLimit), pace: totalLimit > 0 && offset == 0 ? paceShare : nil, tint: totalSpent > totalLimit ? Ink.loss : Ink.text.opacity(0.8))
                if let plan = prefs.plan {
                    LeaderRow { Text("Monthly plan").font(Typeface.detail).foregroundStyle(Ink.soft) } trailing: {
                        MoneyText(value: plan, code: home, size: .tiny, cents: false)
                    }
                }
                LeaderRow { Text("All spending this month").font(Typeface.detail).foregroundStyle(Ink.soft) } trailing: {
                    MoneyText(value: tally.expense, code: home, size: .tiny, cents: false)
                }
            }
            .paperCard()

            if lines.isEmpty {
                EmptyPage(
                    symbol: "chart.bar.doc.horizontal",
                    title: "No budgets yet",
                    message: "Give a category a monthly limit. It repeats every month until you change it.",
                    actionTitle: "Add a budget",
                    action: addBudget
                )
                .paperCard(padding: 0)
            } else {
                VStack(spacing: 0) {
                    ForEach(lines) { line in
                        if let category = categories.first(where: { $0.id == line.categoryID }) {
                            Button {
                                editing = BudgetTarget(category: category, limit: line.limit)
                            } label: {
                                BudgetRow(line: line, category: category, home: home, showsPace: offset == 0)
                            }
                            .buttonStyle(.plain)
                            if line.id != lines.last?.id {
                                Divider().overlay(Ink.rule)
                            }
                        }
                    }
                }
                .paperCard(padding: 14)

                Button(action: addBudget) {
                    Label(String(localized: "Add a budget"), systemImage: "plus")
                }
                .buttonStyle(InkButtonStyle(kind: .outline))
            }

            if !unbudgeted.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Kicker("Spent without a budget")
                    ForEach(Array(unbudgeted.prefix(6))) { share in
                        if let category = categories.first(where: { $0.id == share.id }) {
                            HStack(spacing: 12) {
                                Glyph(symbol: category.iconName, hex: category.colorHex, size: 30)
                                Text(verbatim: category.name)
                                    .font(Typeface.label)
                                    .foregroundStyle(Ink.text)
                                Spacer()
                                MoneyText(value: share.amount, code: home, size: .small)
                                Button {
                                    editing = BudgetTarget(category: category, limit: nil)
                                } label: {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 18))
                                }
                                .accessibilityLabel(Text("Set a budget"))
                            }
                        }
                    }
                }
                .paperCard()
            }
        }
        .sheet(item: $editing) { target in
            BudgetEditor(category: target.category, limit: target.limit, month: month)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showPlan) {
            SpendingPlanSheet()
                .presentationDetents([.medium, .large])
        }
    }

    private func addBudget() {
        let periods = prefs.periods
        let month = periods.shifted(periods.month(containing: Date()), by: offset)
        let records = budgets.compactMap { budget -> BudgetRecord? in
            guard let id = budget.category?.id else { return nil }
            return BudgetRecord(recordID: budget.id, categoryID: id, month: budget.month, limit: budget.limitAmount)
        }
        let active = BudgetMath.effective(records: records, monthStart: month.start).count
        if pro.allows(budgets: active) {
            editing = BudgetTarget(category: nil, limit: nil)
        } else {
            router.showPaywall = true
        }
    }
}

struct BudgetRow: View {
    let line: BudgetLine
    let category: TransactionCategory
    let home: String
    var showsPace = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Glyph(symbol: category.iconName, hex: category.colorHex, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: category.name)
                        .font(Typeface.labelStrong)
                        .foregroundStyle(Ink.text)
                    HStack(spacing: 4) {
                        MoneyText(value: line.spent, code: home, size: .tiny, cents: false)
                        Text(verbatim: "/").foregroundStyle(Ink.faint)
                        MoneyText(value: line.limit, code: home, size: .tiny, tone: Ink.soft, cents: false)
                    }
                    .font(Typeface.detail)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    switch line.mood {
                    case .over: Stamp("Over", tone: Ink.loss)
                    case .ahead: Stamp("Careful", tone: Ink.caution)
                    case .calm: EmptyView()
                    }
                    if line.remaining >= 0 {
                        HStack(spacing: 3) {
                            MoneyText(value: line.remaining, code: home, size: .tiny, tone: Ink.soft, cents: false)
                            Text("left").font(Typeface.detail).foregroundStyle(Ink.soft)
                        }
                    } else {
                        HStack(spacing: 3) {
                            MoneyText(value: -line.remaining, code: home, size: .tiny, tone: Ink.loss, cents: false)
                            Text("over").font(Typeface.detail).foregroundStyle(Ink.loss)
                        }
                    }
                }
            }
            PaceBar(fraction: line.fraction, pace: showsPace ? line.paceFraction : nil, tint: line.mood == .over ? Ink.loss : Color(hexString: category.colorHex), height: 5)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// ← October 2026 →
struct MonthSwitcher: View {
    let month: MoneyMonth
    @Binding var offset: Int
    let periods: PeriodCalendar
    var allowsFuture = true

    var body: some View {
        HStack {
            Button {
                Haptic.tap()
                offset -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(Text("Previous month"))
            Spacer()
            VStack(spacing: 1) {
                Text(verbatim: title)
                    .font(Typeface.heading)
                    .foregroundStyle(Ink.text)
                if offset != 0 {
                    Button("Back to now") { offset = 0 }
                        .font(Typeface.detail)
                }
            }
            Spacer()
            Button {
                Haptic.tap()
                offset += 1
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .disabled(!allowsFuture && offset >= 0)
            .accessibilityLabel(Text("Next month"))
        }
        .foregroundStyle(Ink.text)
    }

    private var title: String {
        if periods.isCalendarMonth() {
            return month.start.formatted(.dateTime.month(.wide).year())
        }
        let last = month.end.addingTimeInterval(-1)
        return month.start.formatted(.dateTime.day().month(.abbreviated)) + " – " + last.formatted(.dateTime.day().month(.abbreviated))
    }
}
