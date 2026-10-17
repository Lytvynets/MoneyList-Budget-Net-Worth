import SwiftUI
import Charts

enum WorthRange: String, CaseIterable, Identifiable {
    case month, threeMonths, sixMonths, year, all

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .month: return "1M"
        case .threeMonths: return "3M"
        case .sixMonths: return "6M"
        case .year: return "1Y"
        case .all: return "All"
        }
    }

    var months: Int? {
        switch self {
        case .month: return 1
        case .threeMonths: return 3
        case .sixMonths: return 6
        case .year: return 12
        case .all: return nil
        }
    }

    func isFree() -> Bool { (months ?? Int.max) <= AppConfig.Free.historyMonths }
}

/// Net worth figure with a scrubbable history chart.
struct WorthHero: View {
    let netWorth: Decimal
    let home: String
    @Binding var range: WorthRange
    let accounts: [Account]
    let holdings: [Asset]
    let entries: [Transaction]
    let isPro: Bool
    var onLocked: () -> Void

    @Environment(RateBook.self) private var rates
    @Environment(\.inkAccent) private var accent
    @Environment(\.masksAmounts) private var masked
    @State private var picked: Date?

    var body: some View {
        let points = series()
        let first = points.first?.value ?? netWorth
        let shown = pickedPoint(in: points)
        let change = (shown?.value ?? netWorth) - first

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Kicker(shown == nil ? "Net worth" : "Net worth on this day")
                MoneyText(value: shown?.value ?? netWorth, code: home, size: .large, tone: (shown?.value ?? netWorth) < 0 ? Ink.loss : Ink.text, cents: false)
                HStack(spacing: 6) {
                    MoneyText(value: change, code: home, size: .tiny, signed: true, tone: change >= 0 ? Ink.gain : Ink.loss, cents: false)
                    Text(verbatim: shown.map { $0.date.formatted(.dateTime.day().month(.abbreviated).year()) } ?? rangeCaption)
                        .font(Typeface.detail)
                        .foregroundStyle(Ink.soft)
                }
            }

            if points.count >= 2 {
                chart(points)
                    .frame(height: 150)
            } else {
                Text("Your history fills in as you add entries.")
                    .font(Typeface.detail)
                    .foregroundStyle(Ink.soft)
                    .frame(height: 60)
            }

            HStack(spacing: 6) {
                ForEach(WorthRange.allCases) { item in
                    Button {
                        if isPro || item.isFree() {
                            Haptic.tap()
                            withAnimation(.snappy) { range = item }
                        } else {
                            onLocked()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(item.title)
                            if !isPro && !item.isFree() {
                                Image(systemName: "lock.fill").font(.system(size: 8))
                            }
                        }
                        .font(Typeface.labelStrong)
                        .foregroundStyle(range == item ? Color.white : Ink.soft)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(range == item ? Ink.text : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .paperCard(padding: 18)
    }

    private var rangeCaption: String {
        switch range {
        case .month: return String(localized: "in the last month")
        case .threeMonths: return String(localized: "in 3 months")
        case .sixMonths: return String(localized: "in 6 months")
        case .year: return String(localized: "in a year")
        case .all: return String(localized: "since you started")
        }
    }

    private func chart(_ points: [WorthPoint]) -> some View {
        let values = points.map { Decimals.double($0.value) }
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let pad = max((high - low) * 0.15, 1)
        return Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Base", low - pad),
                    yEnd: .value("Value", Decimals.double(point.value))
                )
                .foregroundStyle(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", Decimals.double(point.value))
                )
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
            }
            if let picked, let point = pickedPoint(in: points) {
                RuleMark(x: .value("Picked", picked))
                    .foregroundStyle(Ink.ruleStrong)
                PointMark(x: .value("Date", point.date), y: .value("Value", Decimals.double(point.value)))
                    .foregroundStyle(accent)
                    .symbolSize(60)
            }
        }
        .chartYScale(domain: (low - pad)...(high + pad))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Ink.faint)
            }
        }
        .chartXSelection(value: $picked)
        .blur(radius: masked ? 6 : 0)
    }

    private func pickedPoint(in points: [WorthPoint]) -> WorthPoint? {
        guard let picked else { return nil }
        return points.min { abs($0.date.timeIntervalSince(picked)) < abs($1.date.timeIntervalSince(picked)) }
    }

    private func series() -> [WorthPoint] {
        let calendar = Calendar.current
        let now = Date()
        let earliestEntry = entries.last?.date ?? now
        let earliestAccount = accounts.map(\.createdAt).min() ?? now
        let origin = min(earliestEntry, earliestAccount)
        var start: Date
        if let months = range.months {
            start = calendar.date(byAdding: .month, value: -months, to: now) ?? now
            start = max(start, origin)
        } else {
            start = origin
        }
        guard now.timeIntervalSince(start) > 86_400 else { return [] }

        let worthAccounts = accounts.map { account -> WorthAccount in
            let firstEntry = (account.transactions ?? []).map(\.date).min()
            let since = min(account.createdAt, firstEntry ?? account.createdAt)
            return WorthAccount(id: account.id, currency: account.currencyCode, balanceNow: account.balance, since: since)
        }
        let worthHoldings = holdings.map { holding in
            WorthHolding(currency: holding.currencyCode, priceNow: holding.markPrice, changes: HoldingMath.quantityChanges(holding.trades))
        }
        let samples = WorthMath.samples(from: start, to: now, maxPoints: 60)
        let relevant = entries.filter { $0.date >= start }
        return WorthMath.series(
            accounts: worthAccounts,
            holdings: worthHoldings,
            lines: relevant.ledgerLines,
            samples: samples,
            convert: { amount, code in rates.convert(amount, from: code.isEmpty ? home : code, to: home) }
        )
    }
}
