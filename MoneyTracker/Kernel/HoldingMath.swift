import Foundation

nonisolated struct HoldingTrade: Equatable {
    let date: Date
    let isBuy: Bool
    let quantity: Decimal
    let price: Decimal
}

nonisolated struct HoldingPosition: Equatable {
    var quantity: Decimal
    var averageCost: Decimal
    var costBasis: Decimal
    var realized: Decimal
    var invested: Decimal

    static let empty = HoldingPosition(quantity: 0, averageCost: 0, costBasis: 0, realized: 0, invested: 0)
}

/// Average-cost bookkeeping for one holding.
nonisolated enum HoldingMath {

    static func position(_ trades: [HoldingTrade]) -> HoldingPosition {
        var quantity: Decimal = 0
        var cost: Decimal = 0
        var realized: Decimal = 0
        var invested: Decimal = 0

        for trade in trades.sorted(by: { $0.date < $1.date }) {
            if trade.isBuy {
                quantity += trade.quantity
                cost += trade.quantity * trade.price
                invested += trade.quantity * trade.price
            } else {
                guard quantity > 0 else { continue }
                let sold = min(trade.quantity, quantity)
                let average = cost / quantity
                realized += (trade.price - average) * sold
                cost -= average * sold
                quantity -= sold
            }
        }
        if quantity <= 0 {
            return HoldingPosition(quantity: 0, averageCost: 0, costBasis: 0, realized: Decimals.rounded(realized), invested: invested)
        }
        return HoldingPosition(
            quantity: quantity,
            averageCost: Decimals.rounded(cost / quantity, scale: 6),
            costBasis: Decimals.rounded(cost),
            realized: Decimals.rounded(realized),
            invested: invested
        )
    }

    /// Quantity held at a given moment (for history charts).
    static func quantityChanges(_ trades: [HoldingTrade]) -> [(date: Date, quantity: Decimal)] {
        var held: Decimal = 0
        var changes: [(date: Date, quantity: Decimal)] = []
        for trade in trades.sorted(by: { $0.date < $1.date }) {
            if trade.isBuy {
                held += trade.quantity
                changes.append((trade.date, trade.quantity))
            } else {
                let sold = min(trade.quantity, held)
                held -= sold
                changes.append((trade.date, -sold))
            }
        }
        return changes
    }
}
