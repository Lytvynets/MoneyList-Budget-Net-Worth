import Foundation

nonisolated struct WorthPoint: Equatable, Identifiable {
    let date: Date
    let value: Decimal
    var id: Date { date }
}

/// Account information needed to replay history.
nonisolated struct WorthAccount {
    let id: UUID
    let currency: String
    let balanceNow: Decimal
    /// The account counts from this moment on (creation or first entry).
    let since: Date
}

/// A holding's buy/sell ledger reduced to quantity changes, valued at `priceNow`.
nonisolated struct WorthHolding {
    let currency: String
    let priceNow: Decimal
    let changes: [(date: Date, quantity: Decimal)]
}

nonisolated enum WorthMath {

    /// Rebuilds a net-worth series by walking entries backwards from today's
    /// balances. Values use today's exchange rates and prices, so the curve
    /// shows how your money moved, not historical market prices.
    static func series<L: LedgerLine>(
        accounts: [WorthAccount],
        holdings: [WorthHolding],
        lines: [L],
        samples: [Date],
        convert: HomeConverter
    ) -> [WorthPoint] {
        guard !samples.isEmpty else { return [] }
        let sortedSamples = samples.sorted()
        let accountByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })

        // Lines newest first; we undo them as we move back in time.
        let ordered = lines.sorted { $0.lineDate > $1.lineDate }
        var running: [UUID: Decimal] = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.balanceNow) })
        var cursor = 0

        var holdingQuantities: [Decimal] = holdings.map { holding in
            holding.changes.reduce(Decimal(0)) { $0 + $1.quantity }
        }
        let holdingChanges: [[(date: Date, quantity: Decimal)]] = holdings.map { $0.changes.sorted { $0.date > $1.date } }
        var holdingCursors = Array(repeating: 0, count: holdings.count)

        var points: [WorthPoint] = []
        for sample in sortedSamples.reversed() {
            // Undo every entry that happened after this sample.
            while cursor < ordered.count, ordered[cursor].lineDate > sample {
                let line = ordered[cursor]
                let touched = Set([line.lineSource, line.lineTarget].compactMap { $0 })
                for accountID in touched {
                    guard let current = running[accountID] else { continue }
                    running[accountID] = current - LedgerMath.effect(of: line, on: accountID)
                }
                cursor += 1
            }
            for index in holdings.indices {
                while holdingCursors[index] < holdingChanges[index].count, holdingChanges[index][holdingCursors[index]].date > sample {
                    holdingQuantities[index] -= holdingChanges[index][holdingCursors[index]].quantity
                    holdingCursors[index] += 1
                }
            }

            var total: Decimal = 0
            for (id, balance) in running {
                guard let account = accountByID[id], account.since <= sample else { continue }
                total += convert(balance, account.currency)
            }
            for (index, holding) in holdings.enumerated() {
                let quantity = max(holdingQuantities[index], 0)
                if quantity > 0 {
                    total += convert(quantity * holding.priceNow, holding.currency)
                }
            }
            points.append(WorthPoint(date: sample, value: Decimals.rounded(total)))
        }
        return points.reversed()
    }

    /// Evenly spaced sample dates ending at `end` (inclusive).
    static func samples(from start: Date, to end: Date, maxPoints: Int = 60, calendar: Calendar = .current) -> [Date] {
        guard end > start else { return [end] }
        let total = end.timeIntervalSince(start)
        let days = max(Int(total / 86_400), 1)
        let step = max(days / max(maxPoints - 1, 1), 1)
        var dates: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        while cursor < end {
            if let endOfDay = calendar.date(byAdding: .second, value: 86_399, to: cursor) {
                dates.append(min(endOfDay, end))
            }
            guard let next = calendar.date(byAdding: .day, value: step, to: cursor) else { break }
            cursor = next
        }
        if dates.last.map({ calendar.isDate($0, inSameDayAs: end) }) != true {
            dates.append(end)
        } else {
            dates[dates.count - 1] = end
        }
        return dates
    }
}
