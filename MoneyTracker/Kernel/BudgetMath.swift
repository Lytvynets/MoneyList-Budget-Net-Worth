import Foundation

/// One stored budget record: "from `month` on, category X may use `limit`".
nonisolated struct BudgetRecord: Equatable {
    let recordID: UUID
    let categoryID: UUID
    let month: Date
    let limit: Decimal
}

nonisolated struct BudgetLine: Equatable, Identifiable {
    nonisolated enum Mood: Equatable {
        case calm, ahead, over
    }

    let categoryID: UUID
    let recordID: UUID
    let limit: Decimal
    let spent: Decimal
    /// Where spending "should" be today if spread evenly.
    let expectedByToday: Decimal
    let mood: Mood

    var id: UUID { categoryID }
    var remaining: Decimal { limit - spent }
    var fraction: Double { Decimals.ratio(spent, of: limit) }
    var paceFraction: Double { Decimals.ratio(expectedByToday, of: limit) }
}

nonisolated enum BudgetMath {

    /// Budgets roll over automatically: the effective limit for a month is the
    /// newest record whose month is on or before the month start. A limit of 0
    /// switches the budget off from that month on.
    static func effective(records: [BudgetRecord], monthStart: Date) -> [UUID: BudgetRecord] {
        var best: [UUID: BudgetRecord] = [:]
        // Allow a few hours of slack for records saved with time zone drift.
        let cutoff = monthStart.addingTimeInterval(12 * 3600)
        for record in records where record.month <= cutoff {
            if let current = best[record.categoryID] {
                if record.month > current.month || (record.month == current.month && record.recordID.uuidString > current.recordID.uuidString) {
                    best[record.categoryID] = record
                }
            } else {
                best[record.categoryID] = record
            }
        }
        return best.filter { $0.value.limit > 0 }
    }

    static func lines(records: [BudgetRecord], month: MoneyMonth, spentByCategory: [UUID: Decimal], periods: PeriodCalendar, now: Date) -> [BudgetLine] {
        let active = effective(records: records, monthStart: month.start)
        let total = Decimal(max(periods.dayCount(in: month), 1))
        let elapsed: Decimal
        if now >= month.end {
            elapsed = total
        } else {
            elapsed = Decimal(periods.daysElapsed(in: month, at: now))
        }
        let paceShare = elapsed / total

        return active.values.map { record in
            let spent = spentByCategory[record.categoryID] ?? 0
            let expected = record.limit * paceShare
            let mood: BudgetLine.Mood
            if spent > record.limit {
                mood = .over
            } else if spent > expected * Decimal(string: "1.15")! && spent > record.limit / 4 {
                mood = .ahead
            } else {
                mood = .calm
            }
            return BudgetLine(categoryID: record.categoryID, recordID: record.recordID, limit: record.limit, spent: spent, expectedByToday: expected, mood: mood)
        }
        .sorted { lhs, rhs in
            if lhs.fraction == rhs.fraction { return lhs.limit > rhs.limit }
            return lhs.fraction > rhs.fraction
        }
    }
}

/// "How much can I spend today?"
nonisolated struct Allowance: Equatable {
    nonisolated enum Basis: Equatable {
        /// Monthly spending plan set by the user (or the sum of budgets).
        case plan(Decimal)
        /// No plan: derived from spendable balance minus upcoming bills.
        case balance(Decimal)
    }

    let basis: Basis
    /// Daily amount available for the rest of the month (from today).
    let daily: Decimal
    let spentToday: Decimal
    /// Positive = you are under pace by this much; negative = over pace.
    let paceDelta: Decimal
    let daysLeft: Int
    let billsReserved: Decimal

    var leftToday: Decimal { daily - spentToday }
    var usedFraction: Double { Decimals.ratio(spentToday, of: daily) }
}

nonisolated enum AllowanceMath {

    nonisolated struct Input {
        var plan: Decimal?
        var spendableBalance: Decimal
        var month: MoneyMonth
        var periods: PeriodCalendar
        var now: Date
        /// Discretionary spending (entries not created by bills) per day in the month.
        var discretionaryBeforeToday: Decimal
        var discretionaryToday: Decimal
        /// Bills already paid this month + bills still due before month end.
        var billsPaidThisMonth: Decimal
        var billsUpcomingThisMonth: Decimal
    }

    static func compute(_ input: Input) -> Allowance {
        let daysLeft = input.periods.daysLeft(in: input.month, from: input.now)
        let safeDays = Decimal(max(daysLeft, 1))

        if let plan = input.plan, plan > 0 {
            let bills = input.billsPaidThisMonth + input.billsUpcomingThisMonth
            let discretionaryBudget = plan - bills
            let remainingBeforeToday = discretionaryBudget - input.discretionaryBeforeToday
            let daily = max(remainingBeforeToday / safeDays, 0)

            let totalDays = Decimal(max(input.periods.dayCount(in: input.month), 1))
            let elapsed = Decimal(input.periods.daysElapsed(in: input.month, at: input.now))
            let idealSoFar = discretionaryBudget * elapsed / totalDays
            let actualSoFar = input.discretionaryBeforeToday + input.discretionaryToday
            return Allowance(
                basis: .plan(plan),
                daily: Decimals.rounded(daily),
                spentToday: input.discretionaryToday,
                paceDelta: Decimals.rounded(idealSoFar - actualSoFar),
                daysLeft: daysLeft,
                billsReserved: bills
            )
        }

        // Balance-based: the money you hold now (spending already left the
        // balance, so today's spend is added back) minus bills still to come.
        let pool = input.spendableBalance + input.discretionaryToday - input.billsUpcomingThisMonth
        let daily = max(pool / safeDays, 0)
        return Allowance(
            basis: .balance(input.spendableBalance),
            daily: Decimals.rounded(daily),
            spentToday: input.discretionaryToday,
            paceDelta: 0,
            daysLeft: daysLeft,
            billsReserved: input.billsUpcomingThisMonth
        )
    }
}
