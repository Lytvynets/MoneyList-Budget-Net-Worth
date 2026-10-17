import SwiftUI

/// One or two plain-language observations, computed on device.
struct InsightsCard: View {
    let entries: [Transaction]
    let digest: MoneyDigest
    let categories: [TransactionCategory]

    @Environment(RateBook.self) private var rates
    @Environment(\.masksAmounts) private var masked

    var body: some View {
        let home = digest.home
        let insights = InsightEngine.make(.init(
            lines: entries.ledgerLines,
            month: digest.month,
            periods: digest.periods,
            now: Date(),
            plan: digest.plan,
            subscriptionYearly: digest.subscriptionsYearly,
            subscriptionCount: digest.subscriptionsCount,
            convert: { amount, code in rates.convert(amount, from: code.isEmpty ? home : code, to: home) }
        ))
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Kicker("Margin notes")
                ForEach(insights.prefix(2)) { insight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: symbol(for: insight.kind))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tone(for: insight.kind))
                            .frame(width: 22)
                            .padding(.top, 2)
                        Text(verbatim: InsightWriter.sentence(for: insight.kind, home: home, categories: categories, masked: masked))
                            .font(Typeface.label)
                            .foregroundStyle(Ink.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .paperCard()
        }
    }

    private func symbol(for kind: InsightKind) -> String {
        switch kind {
        case .categoryUp: return "arrow.up.right"
        case .categoryDown: return "arrow.down.right"
        case .projection: return "chart.line.uptrend.xyaxis"
        case .largest: return "exclamationmark.circle"
        case .quietDays: return "leaf"
        case .subscriptions: return "repeat"
        case .busiestWeekday: return "calendar"
        }
    }

    private func tone(for kind: InsightKind) -> Color {
        switch kind {
        case .categoryUp: return Ink.loss
        case .categoryDown, .quietDays: return Ink.gain
        case .projection(let projected, let plan):
            if let plan, projected > plan { return Ink.loss }
            return Ink.soft
        default: return Ink.soft
        }
    }
}

/// Turns insight data into localized sentences.
enum InsightWriter {
    static func sentence(for kind: InsightKind, home: String, categories: [TransactionCategory], masked: Bool) -> String {
        func money(_ value: Decimal) -> String { masked ? MoneyFormat.masked : MoneyFormat.plain(value, code: home, cents: false) }
        func name(_ id: UUID?) -> String {
            guard let id, let category = categories.first(where: { $0.id == id }) else { return String(localized: "Uncategorized") }
            return category.name
        }

        switch kind {
        case let .categoryUp(categoryID, percent, now, _):
            return String(localized: "\(name(categoryID)) is up \(percent)% on last month at this point (\(money(now)) so far).")
        case let .categoryDown(categoryID, percent, now, _):
            return String(localized: "\(name(categoryID)) is down \(percent)% on last month — \(money(now)) so far.")
        case let .projection(projected, plan):
            if let plan, plan > 0 {
                if projected > plan {
                    return String(localized: "At this pace the month ends near \(money(projected)) — \(money(projected - plan)) over your plan.")
                }
                return String(localized: "At this pace the month ends near \(money(projected)), within your plan.")
            }
            return String(localized: "At this pace the month ends near \(money(projected)) in spending.")
        case let .largest(_, amount, note, categoryID):
            let label = note.isEmpty ? name(categoryID) : note
            return String(localized: "Biggest expense this month: \(label), \(money(amount)).")
        case let .quietDays(count, streak):
            if streak >= 2 {
                return String(localized: "\(streak) days in a row without spending.") + " " + String(localized: "\(count) quiet days this month.")
            }
            return String(localized: "\(count) days this month without any spending.")
        case let .subscriptions(yearly, count):
            return String(localized: "Subscriptions (\(count)) add up to about \(money(yearly)) a year.")
        case let .busiestWeekday(weekday, average):
            let symbols = Calendar.current.standaloneWeekdaySymbols
            let day = symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
            return String(localized: "\(day) is your priciest day — about \(money(average)) on average.")
        }
    }
}
