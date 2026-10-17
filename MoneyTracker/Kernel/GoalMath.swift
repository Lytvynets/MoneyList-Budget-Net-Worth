import Foundation

nonisolated struct GoalOutlook: Equatable {
    nonisolated enum Status: Equatable {
        case reached
        case onTrack
        case behind
        case open      // no date and no monthly plan
    }

    let saved: Decimal
    let target: Decimal
    let status: Status
    /// Monthly amount needed to hit the target date (nil without a date).
    let neededPerMonth: Decimal?
    /// Projected finish date from the planned monthly contribution.
    let projectedFinish: Date?

    var remaining: Decimal { max(target - saved, 0) }
    var fraction: Double { Decimals.ratio(saved, of: target) }
}

nonisolated enum GoalMath {

    static func outlook(saved rawSaved: Decimal, target: Decimal, monthly: Decimal?, targetDate: Date?, now: Date, calendar: Calendar = .current) -> GoalOutlook {
        let saved = max(rawSaved, 0)
        guard target > 0 else {
            return GoalOutlook(saved: saved, target: target, status: .open, neededPerMonth: nil, projectedFinish: nil)
        }
        if saved >= target {
            return GoalOutlook(saved: saved, target: target, status: .reached, neededPerMonth: nil, projectedFinish: nil)
        }
        let remaining = target - saved

        var needed: Decimal?
        if let targetDate {
            let months = monthsBetween(now, targetDate, calendar: calendar)
            needed = Decimals.rounded(remaining / Decimal(max(months, 1)))
        }

        var finish: Date?
        if let monthly, monthly > 0 {
            let monthsNeeded = ceilDivide(remaining, monthly)
            finish = calendar.date(byAdding: .month, value: monthsNeeded, to: now)
        }

        let status: GoalOutlook.Status
        if let targetDate {
            if targetDate < now {
                status = .behind
            } else if let monthly, let needed {
                status = monthly >= needed ? .onTrack : .behind
            } else if let finish {
                status = finish <= targetDate ? .onTrack : .behind
            } else {
                status = .open
            }
        } else {
            status = (monthly ?? 0) > 0 ? .onTrack : .open
        }
        return GoalOutlook(saved: saved, target: target, status: status, neededPerMonth: needed, projectedFinish: finish)
    }

    /// Whole months from `from` to `to`, rounded up (at least 0).
    static func monthsBetween(_ from: Date, _ to: Date, calendar: Calendar = .current) -> Int {
        guard to > from else { return 0 }
        let components = calendar.dateComponents([.month, .day], from: from, to: to)
        var months = components.month ?? 0
        if (components.day ?? 0) > 0 { months += 1 }
        return max(months, 0)
    }

    static func ceilDivide(_ a: Decimal, _ b: Decimal) -> Int {
        guard b > 0 else { return 0 }
        let quotient = Decimals.double(a / b)
        return max(Int(quotient.rounded(.up)), 0)
    }
}
