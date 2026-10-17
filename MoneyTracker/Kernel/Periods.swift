import Foundation

/// A "money month" that can start on any day 1…28 (payday-based months).
nonisolated struct MoneyMonth: Equatable, Hashable {
    let start: Date
    let end: Date

    func contains(_ date: Date) -> Bool { date >= start && date < end }

    var interval: DateInterval { DateInterval(start: start, end: end) }
}

nonisolated struct PeriodCalendar {
    var startDay: Int
    var calendar: Calendar

    init(startDay: Int = 1, calendar: Calendar = .current) {
        self.startDay = min(max(startDay, 1), 28)
        self.calendar = calendar
    }

    func month(containing date: Date) -> MoneyMonth {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        var components = DateComponents()
        components.year = parts.year
        components.month = parts.month
        components.day = startDay
        var start = calendar.date(from: components) ?? calendar.startOfDay(for: date)
        if (parts.day ?? 1) < startDay {
            start = calendar.date(byAdding: .month, value: -1, to: start) ?? start
        }
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start.addingTimeInterval(30 * 86_400)
        return MoneyMonth(start: start, end: end)
    }

    func shifted(_ month: MoneyMonth, by offset: Int) -> MoneyMonth {
        let probe = calendar.date(byAdding: .month, value: offset, to: month.start) ?? month.start
        return self.month(containing: probe)
    }

    /// Start-of-day dates for every day in the month.
    func days(in month: MoneyMonth) -> [Date] {
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: month.start)
        while cursor < month.end && days.count < 32 {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    func dayCount(in month: MoneyMonth) -> Int { days(in: month).count }

    /// Days remaining including today (≥ 1 while inside the month).
    func daysLeft(in month: MoneyMonth, from now: Date) -> Int {
        let today = calendar.startOfDay(for: now)
        guard today < month.end else { return 0 }
        let from = max(today, calendar.startOfDay(for: month.start))
        let count = calendar.dateComponents([.day], from: from, to: month.end).day ?? 0
        return max(count, 1)
    }

    /// Days elapsed including today (1 on the first day).
    func daysElapsed(in month: MoneyMonth, at now: Date) -> Int {
        let today = calendar.startOfDay(for: now)
        if today < month.start { return 0 }
        let total = dayCount(in: month)
        let elapsed = (calendar.dateComponents([.day], from: calendar.startOfDay(for: month.start), to: today).day ?? 0) + 1
        return min(max(elapsed, 0), total)
    }

    func isCalendarMonth() -> Bool { startDay == 1 }

    /// Index of `date` within the month's day list.
    func dayIndex(of date: Date, in month: MoneyMonth) -> Int? {
        guard month.contains(date) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: month.start), to: calendar.startOfDay(for: date)).day
    }
}
