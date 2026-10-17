import Foundation

/// Everything the Today screen, widgets and Siri need, computed in one pass
/// from the stored data. Pure computation — no saving.
struct MoneyDigest {
    let periods: PeriodCalendar
    let month: MoneyMonth
    let home: String
    let monthTally: Tally
    let plan: Decimal?
    let planFromBudgets: Bool
    let allowance: Allowance
    let dayBars: [Decimal]
    let todayIndex: Int?
    let spentToday: Decimal
    let budgetLines: [BudgetLine]
    let upcoming: [RuleRunner.Upcoming]
    let overdue: [RecurringRule]
    let assetsTotal: Decimal
    let debtsTotal: Decimal
    let holdingsTotal: Decimal
    let subscriptionsYearly: Decimal
    let subscriptionsCount: Int

    var netWorth: Decimal { assetsTotal - debtsTotal + holdingsTotal }
}

enum DigestBuilder {

    static func build(
        entries: [Transaction],
        accounts: [Account],
        rules: [RecurringRule],
        budgets: [Budget],
        holdings: [Asset],
        profile: UserProfile?,
        home: String,
        convert: @escaping CurrencyConverter,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MoneyDigest {
        let periods = PeriodCalendar(startDay: profile?.periodStartDay ?? 1, calendar: calendar)
        let month = periods.month(containing: now)
        let toHome: HomeConverter = { amount, code in convert(amount, code.isEmpty ? home : code, home) }

        // Month entries only (entries arrive newest first from queries, but don't rely on it).
        let monthEntries = entries.filter { month.contains($0.date) }
        let tally = Tally.make(monthEntries.ledgerLines, from: month.start, to: month.end, calendar: calendar, convert: toHome)

        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        var discretionaryBefore: Decimal = 0
        var discretionaryToday: Decimal = 0
        var billsPaid: Decimal = 0
        var spentToday: Decimal = 0
        for entry in monthEntries where entry.kind == .expense {
            let value = toHome(entry.amount, entry.currencyCode)
            let isToday = entry.date >= startOfToday && entry.date < startOfTomorrow
            if isToday { spentToday += value }
            if entry.recurringRuleId != nil {
                billsPaid += value
            } else if entry.date < startOfToday {
                discretionaryBefore += value
            } else if isToday {
                discretionaryToday += value
            }
        }

        // Bills still to come before the month ends.
        let accountByID = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let monthUpcoming = RuleRunner.upcoming(rules: rules, from: now, to: month.end, calendar: calendar)
        var billsAhead: Decimal = 0
        for item in monthUpcoming where item.rule.kind == .expense {
            let code = item.rule.accountID.flatMap { accountByID[$0]?.currencyCode } ?? home
            billsAhead += toHome(item.rule.amount, code)
        }

        // Budgets.
        let records = budgets.compactMap { budget -> BudgetRecord? in
            guard let category = budget.category else { return nil }
            return BudgetRecord(recordID: budget.id, categoryID: category.id, month: budget.month, limit: budget.limitAmount)
        }
        let budgetLines = BudgetMath.lines(records: records, month: month, spentByCategory: tally.expenseByCategory, periods: periods, now: now)
        let budgetSum = budgetLines.reduce(Decimal(0)) { $0 + $1.limit }

        var plan: Decimal?
        var planFromBudgets = false
        if let stored = profile?.monthlyPlan, stored > 0 {
            plan = stored
        } else if budgetSum > 0 {
            plan = budgetSum
            planFromBudgets = true
        }

        // Balances.
        var assets: Decimal = 0
        var debts: Decimal = 0
        var spendable: Decimal = 0
        for account in accounts where !account.isArchived {
            let value = toHome(account.balance, account.currencyCode)
            if value >= 0 { assets += value } else { debts += -value }
            if account.isSpendable { spendable += value }
        }
        var holdingsTotal: Decimal = 0
        for asset in holdings {
            holdingsTotal += toHome(asset.marketValue, asset.currencyCode)
        }

        let allowance = AllowanceMath.compute(.init(
            plan: plan,
            spendableBalance: spendable,
            month: month,
            periods: periods,
            now: now,
            discretionaryBeforeToday: discretionaryBefore,
            discretionaryToday: discretionaryToday,
            billsPaidThisMonth: billsPaid,
            billsUpcomingThisMonth: billsAhead
        ))

        let days = periods.days(in: month)
        let bars = days.map { tally.expenseByDay[$0] ?? 0 }
        let todayIndex = periods.dayIndex(of: now, in: month)

        let horizon = calendar.date(byAdding: .day, value: 14, to: now) ?? now
        let soon = RuleRunner.upcoming(rules: rules, from: startOfToday, to: horizon, calendar: calendar)
        let overdue = RuleRunner.overdue(rules: rules, now: startOfToday)

        var subsYearly: Decimal = 0
        var subsCount = 0
        for rule in rules where rule.isActive && rule.isSubscription && rule.kind == .expense {
            let code = rule.accountID.flatMap { accountByID[$0]?.currencyCode } ?? home
            subsYearly += toHome(rule.amount, code) * rule.cadence.timesPerYear
            subsCount += 1
        }

        return MoneyDigest(
            periods: periods,
            month: month,
            home: home,
            monthTally: tally,
            plan: plan,
            planFromBudgets: planFromBudgets,
            allowance: allowance,
            dayBars: bars,
            todayIndex: todayIndex,
            spentToday: spentToday,
            budgetLines: budgetLines,
            upcoming: soon,
            overdue: overdue,
            assetsTotal: Decimals.rounded(assets),
            debtsTotal: Decimals.rounded(debts),
            holdingsTotal: Decimals.rounded(holdingsTotal),
            subscriptionsYearly: Decimals.rounded(subsYearly),
            subscriptionsCount: subsCount
        )
    }
}
