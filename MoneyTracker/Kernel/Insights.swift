import Foundation

/// Plain, on-device observations about spending. The UI turns them into text.
nonisolated enum InsightKind: Equatable {
    case categoryUp(categoryID: UUID, percent: Int, now: Decimal, before: Decimal)
    case categoryDown(categoryID: UUID, percent: Int, now: Decimal, before: Decimal)
    case projection(projected: Decimal, plan: Decimal?)
    case largest(lineID: UUID, amount: Decimal, note: String, categoryID: UUID?)
    case quietDays(count: Int, streak: Int)
    case subscriptions(yearly: Decimal, count: Int)
    case busiestWeekday(weekday: Int, average: Decimal)
}

nonisolated struct Insight: Equatable, Identifiable {
    let id: String
    let kind: InsightKind
    let weight: Double
}

nonisolated enum InsightEngine {

    nonisolated struct Input<L: LedgerLine> {
        var lines: [L]
        var month: MoneyMonth
        var periods: PeriodCalendar
        var now: Date
        var plan: Decimal?
        var subscriptionYearly: Decimal
        var subscriptionCount: Int
        var convert: HomeConverter
    }

    static func make<L: LedgerLine>(_ input: Input<L>) -> [Insight] {
        let calendar = input.periods.calendar
        let month = input.month
        let now = min(input.now, month.end)
        var output: [Insight] = []

        let current = Tally.make(input.lines, from: month.start, to: now, calendar: calendar, convert: input.convert)
        let previousMonth = input.periods.shifted(month, by: -1)
        let elapsed = now.timeIntervalSince(month.start)
        let previousCut = previousMonth.start.addingTimeInterval(elapsed)
        let previous = Tally.make(input.lines, from: previousMonth.start, to: min(previousCut, previousMonth.end), calendar: calendar, convert: input.convert)

        // Category changes against the same point of last month.
        if current.expense > 0 {
            var best: (UUID, Double, Decimal, Decimal)?
            var calmest: (UUID, Double, Decimal, Decimal)?
            for (category, amount) in current.expenseByCategory {
                let before = previous.expenseByCategory[category] ?? 0
                guard before > 0, amount >= current.expense / 20 else { continue }
                let change = Decimals.rawRatio(amount - before, of: before)
                if change >= 0.25, (best == nil || change > best!.1) { best = (category, change, amount, before) }
                if change <= -0.25, (calmest == nil || change < calmest!.1) { calmest = (category, change, amount, before) }
            }
            if let best {
                output.append(Insight(id: "up-\(best.0)", kind: .categoryUp(categoryID: best.0, percent: Int((best.1 * 100).rounded()), now: best.2, before: best.3), weight: 0.9 + min(best.1, 2) / 10))
            }
            if let calmest {
                output.append(Insight(id: "down-\(calmest.0)", kind: .categoryDown(categoryID: calmest.0, percent: Int((-calmest.1 * 100).rounded()), now: calmest.2, before: calmest.3), weight: 0.7))
            }
        }

        // Pace projection.
        let elapsedDays = input.periods.daysElapsed(in: month, at: now)
        let totalDays = input.periods.dayCount(in: month)
        if elapsedDays >= 5, elapsedDays < totalDays, current.expense > 0 {
            let projected = Decimals.rounded(current.expense / Decimal(elapsedDays) * Decimal(totalDays), scale: 0)
            var weight = 0.6
            if let plan = input.plan, plan > 0 { weight = projected > plan ? 1.0 : 0.65 }
            output.append(Insight(id: "projection", kind: .projection(projected: projected, plan: input.plan), weight: weight))
        }

        // Largest single expense this month.
        var largest: L?
        var largestValue: Decimal = 0
        for line in input.lines where line.lineKind == .expense && month.contains(line.lineDate) && line.lineDate <= now {
            let value = input.convert(line.lineAmount, line.lineCurrency)
            if value > largestValue { largestValue = value; largest = line }
        }
        if let largest, current.count >= 3 {
            output.append(Insight(id: "largest-\(largest.lineID)", kind: .largest(lineID: largest.lineID, amount: largestValue, note: largest.lineNote, categoryID: largest.lineCategory), weight: 0.5))
        }

        // Days without spending.
        let days = input.periods.days(in: month).filter { $0 <= now }
        if days.count >= 3 {
            var quiet = 0
            for day in days.dropLast() where (current.expenseByDay[day] ?? 0) == 0 { quiet += 1 }
            var streak = 0
            for day in days.reversed() {
                if (current.expenseByDay[day] ?? 0) == 0 { streak += 1 } else { break }
            }
            if quiet >= 2 || streak >= 2 {
                output.append(Insight(id: "quiet", kind: .quietDays(count: quiet, streak: streak), weight: streak >= 3 ? 0.85 : 0.45))
            }
        }

        if input.subscriptionCount > 0, input.subscriptionYearly > 0 {
            output.append(Insight(id: "subs", kind: .subscriptions(yearly: input.subscriptionYearly, count: input.subscriptionCount), weight: 0.55))
        }

        // Busiest weekday over the last eight weeks.
        if let windowStart = calendar.date(byAdding: .day, value: -56, to: calendar.startOfDay(for: input.now)) {
            let window = Tally.make(input.lines, from: windowStart, to: input.now, calendar: calendar, convert: input.convert)
            if window.count >= 12 {
                var sums: [Int: Decimal] = [:]
                for (day, value) in window.expenseByDay {
                    sums[calendar.component(.weekday, from: day), default: 0] += value
                }
                if let top = sums.max(by: { $0.value < $1.value }), top.value > 0 {
                    let average = Decimals.rounded(top.value / 8, scale: 0)
                    let mean = window.expense / 7
                    if top.value / 8 > mean / 8 * Decimal(string: "1.4")! {
                        output.append(Insight(id: "weekday", kind: .busiestWeekday(weekday: top.key, average: average), weight: 0.4))
                    }
                }
            }
        }

        return output.sorted { $0.weight > $1.weight }
    }
}
