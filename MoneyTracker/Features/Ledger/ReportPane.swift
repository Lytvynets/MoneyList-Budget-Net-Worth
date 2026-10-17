import SwiftUI
import SwiftData
import Charts

struct ReportPane: View {
    @Binding var pane: LedgerScreen.Pane

    @Environment(\.moneyPrefs) private var prefs
    @Environment(RateBook.self) private var rates
    @Environment(\.inkAccent) private var accent

    @Query(sort: \Transaction.date, order: .reverse) private var entries: [Transaction]
    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]

    @State private var offset = 0
    @State private var showIncome = false
    @State private var pickedDay: Date?

    var body: some View {
        let periods = prefs.periods
        let month = periods.shifted(periods.month(containing: Date()), by: offset)
        let home = prefs.home
        let convert: HomeConverter = { amount, code in rates.convert(amount, from: code.isEmpty ? home : code, to: home) }
        let monthEntries = entries.filter { month.contains($0.date) }
        let tally = Tally.make(monthEntries.ledgerLines, from: month.start, to: month.end, convert: convert)
        let shares = showIncome ? tally.incomeShares() : tally.expenseShares()
        let total = showIncome ? tally.income : tally.expense

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LedgerHeader(pane: $pane)
                MonthSwitcher(month: month, offset: $offset, periods: periods, allowsFuture: false)

                HStack(spacing: 0) {
                    totalsCell("Income", tally.income, Ink.gain, home)
                    Rectangle().fill(Ink.rule).frame(width: 0.8, height: 40)
                    totalsCell("Spending", tally.expense, Ink.text, home)
                    Rectangle().fill(Ink.rule).frame(width: 0.8, height: 40)
                    totalsCell("Kept", tally.net, tally.net >= 0 ? Ink.gain : Ink.loss, home)
                }
                .paperCard(padding: 12)

                VStack(alignment: .leading, spacing: 12) {
                    SegmentRail(items: [(false, "Where it went"), (true, "Where it came from")], selection: $showIncome)
                    if shares.isEmpty {
                        Text(showIncome ? "No income recorded this month." : "No spending recorded this month.")
                            .font(Typeface.label)
                            .foregroundStyle(Ink.soft)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(shares) { share in
                            BreakdownRow(share: share, category: categories.first { $0.id == share.id }, home: home, showIncome: showIncome)
                        }
                        Divider().overlay(Ink.rule)
                        LeaderRow { Text("Total").font(Typeface.labelStrong) } trailing: {
                            MoneyText(value: total, code: home, size: .small)
                        }
                    }
                }
                .paperCard()

                CalendarHeat(month: month, periods: periods, byDay: tally.expenseByDay, home: home, picked: $pickedDay)

                YearBars(entries: entries, periods: periods, convert: convert, home: home)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
    }

    private func totalsCell(_ title: LocalizedStringKey, _ value: Decimal, _ tone: Color, _ home: String) -> some View {
        VStack(spacing: 4) {
            Kicker(title)
            MoneyText(value: value, code: home, size: .small, tone: tone, cents: false)
        }
        .frame(maxWidth: .infinity)
    }
}

struct BreakdownRow: View {
    let share: Share
    let category: TransactionCategory?
    let home: String
    let showIncome: Bool

    var body: some View {
        let hex = category?.colorHex ?? InkSwatch.graphite
        VStack(alignment: .leading, spacing: 6) {
            LeaderRow {
                HStack(spacing: 8) {
                    Glyph(symbol: category?.iconName ?? "questionmark", hex: hex, size: 26)
                    Text(verbatim: category?.name ?? String(localized: "Uncategorized"))
                        .font(Typeface.label)
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                }
            } trailing: {
                HStack(spacing: 8) {
                    Text(verbatim: "\(Int((share.fraction * 100).rounded()))%")
                        .font(Typeface.detail)
                        .foregroundStyle(Ink.soft)
                    MoneyText(value: share.amount, code: home, size: .small, cents: false)
                }
            }
            PaceBar(fraction: share.fraction, tint: Color(hexString: hex), height: 4)
                .padding(.leading, 34)
        }
    }
}

/// Month calendar shaded by daily spending.
struct CalendarHeat: View {
    let month: MoneyMonth
    let periods: PeriodCalendar
    let byDay: [Date: Decimal]
    let home: String
    @Binding var picked: Date?

    @Environment(\.inkAccent) private var accent

    var body: some View {
        let calendar = periods.calendar
        let days = periods.days(in: month)
        let peak = days.map { Decimals.double(byDay[$0] ?? 0) }.max() ?? 0
        let first = days.first ?? month.start
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let symbols = rotatedWeekdaySymbols(calendar)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Kicker("Spending calendar")
                Spacer()
                if let picked {
                    HStack(spacing: 4) {
                        Text(verbatim: picked.formatted(.dateTime.day().month(.abbreviated)))
                            .foregroundStyle(Ink.soft)
                        MoneyText(value: byDay[picked] ?? 0, code: home, size: .tiny)
                    }
                    .font(Typeface.detail)
                }
            }
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(symbols.indices, id: \.self) { index in
                    Text(verbatim: symbols[index])
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Ink.faint)
                        .frame(maxWidth: .infinity)
                }
                ForEach(0..<leading, id: \.self) { index in
                    Color.clear.frame(height: 34).id("pad-\(index)")
                }
                ForEach(days, id: \.self) { day in
                    let value = Decimals.double(byDay[day] ?? 0)
                    let strength = peak > 0 ? value / peak : 0
                    let isFuture = day > Date()
                    Button {
                        Haptic.tap()
                        picked = picked == day ? nil : day
                    } label: {
                        Text(verbatim: "\(calendar.component(.day, from: day))")
                            .font(.system(size: 12, weight: .medium, design: .serif))
                            .foregroundStyle(strength > 0.55 ? Color.white : (isFuture ? Ink.faint : Ink.text))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(cell(strength: strength, isFuture: isFuture), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(picked == day ? Ink.text : (calendar.isDateInToday(day) ? accent : Color.clear), lineWidth: 1.2)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isFuture)
                }
            }
        }
        .paperCard()
    }

    private func cell(strength: Double, isFuture: Bool) -> Color {
        if isFuture { return Ink.rule.opacity(0.4) }
        if strength <= 0 { return Ink.rule.opacity(0.7) }
        return accent.opacity(0.18 + 0.8 * strength)
    }

    private func rotatedWeekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[start...] + symbols[..<start])
    }
}

/// Twelve months of income vs spending.
struct YearBars: View {
    let entries: [Transaction]
    let periods: PeriodCalendar
    let convert: HomeConverter
    let home: String

    @Environment(\.inkAccent) private var accent
    @Environment(\.masksAmounts) private var masked

    struct Bar: Identifiable {
        let id = UUID()
        let month: Date
        let series: String
        let value: Double
    }

    var body: some View {
        let current = periods.month(containing: Date())
        let months = (0..<12).map { periods.shifted(current, by: -11 + $0) }
        let earliest = months.first?.start ?? Date()
        let window = entries.filter { $0.date >= earliest }.ledgerLines
        let income = String(localized: "Income")
        let spending = String(localized: "Spending")
        let bars: [Bar] = months.flatMap { month -> [Bar] in
            let tally = Tally.make(window, from: month.start, to: month.end, convert: convert)
            return [
                Bar(month: month.start, series: income, value: Decimals.double(tally.income)),
                Bar(month: month.start, series: spending, value: Decimals.double(tally.expense))
            ]
        }

        VStack(alignment: .leading, spacing: 12) {
            Kicker("Twelve months")
            Chart(bars) { bar in
                BarMark(
                    x: .value("Month", bar.month, unit: .month),
                    y: .value("Amount", bar.value)
                )
                .foregroundStyle(by: .value("Series", bar.series))
                .position(by: .value("Series", bar.series))
                .cornerRadius(3)
            }
            .chartForegroundStyleScale([income: Ink.gain, spending: accent])
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Ink.rule)
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(verbatim: masked ? "•" : MoneyFormat.compact(Decimals.fromDouble(amount), code: home))
                                .font(.system(size: 9))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { value in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 180)
        }
        .paperCard()
    }
}
