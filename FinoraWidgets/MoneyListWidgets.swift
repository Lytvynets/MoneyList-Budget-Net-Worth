import WidgetKit
import SwiftUI
import UIKit

// MARK: - Timeline

struct GlanceEntry: TimelineEntry {
    let date: Date
    let snapshot: GlanceSnapshot
    let isPreview: Bool
}

struct GlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), snapshot: .sample, isPreview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        let stored = GlanceSnapshot.load()
        completion(GlanceEntry(date: Date(), snapshot: stored ?? .sample, isPreview: stored == nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let now = Date()
        let stored = GlanceSnapshot.load()
        let snapshot = stored ?? .sample
        var entries = [GlanceEntry(date: now, snapshot: snapshot, isPreview: stored == nil)]
        // A second entry right after midnight so "today" rolls over even if the app isn't opened.
        let calendar = Calendar.current
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            entries.append(GlanceEntry(date: midnight.addingTimeInterval(60), snapshot: snapshot, isPreview: stored == nil))
        }
        let refresh = calendar.date(byAdding: .hour, value: 2, to: now) ?? now.addingTimeInterval(7200)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

/// Snapshot values adjusted for the moment the widget is drawn.
struct GlanceNow {
    let left: Double
    let daily: Double
    let spentToday: Double
    let daysLeft: Int

    init(_ snapshot: GlanceSnapshot, at date: Date) {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: snapshot.generatedAt), to: calendar.startOfDay(for: date)).day ?? 0
        if days <= 0 {
            left = snapshot.leftToday
            daily = snapshot.dailyAllowance
            spentToday = snapshot.spentToday
            daysLeft = snapshot.daysLeft
        } else {
            // The day rolled over: spread what was left across the remaining days.
            let remaining = max(snapshot.dailyAllowance * Double(snapshot.daysLeft) - snapshot.spentToday, 0)
            let newDays = max(snapshot.daysLeft - days, 1)
            daily = remaining / Double(newDays)
            left = daily
            spentToday = 0
            daysLeft = newDays
        }
    }

    var used: Double { daily > 0 ? min(max(spentToday / daily, 0), 1) : 0 }
}

// MARK: - Look

enum WInk {
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }

    static let paper = dynamic(0xF2EEE5, 0x15171B)
    static let text = dynamic(0x17181C, 0xF2EFE8)
    static let soft = dynamic(0x5C5F66, 0xA9ABB1)
    static let faint = dynamic(0x9A9CA1, 0x6E7178)
    static let rule = dynamic(0xDCD7CC, 0x2A2D33)
    static let gain = dynamic(0x1E7D58, 0x47C28F)
    static let loss = dynamic(0xC2412D, 0xFF7D66)
    static let marker = dynamic(0xF6D46A, 0x7A621F)

    static func hex(_ value: String) -> Color {
        let number = UInt32(value.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), radix: 16) ?? 0x555A63
        return Color(red: Double((number >> 16) & 0xFF) / 255, green: Double((number >> 8) & 0xFF) / 255, blue: Double(number & 0xFF) / 255)
    }

    static func money(_ value: Double, _ code: String, masked: Bool, cents: Bool = false) -> String {
        if masked { return "••••" }
        return value.formatted(.currency(code: code.isEmpty ? "USD" : code).precision(.fractionLength(cents ? 0...2 : 0...0)))
    }

    static func figure(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

struct WKicker: View {
    let text: Text
    init(_ key: LocalizedStringKey) { text = Text(key) }
    var body: some View {
        text
            .font(.system(size: 9, weight: .bold))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(WInk.soft)
            .lineLimit(1)
    }
}

// MARK: - Allowance widget

struct AllowanceWidget: Widget {
    let kind = "MoneyListAllowance"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GlanceProvider()) { entry in
            AllowanceWidgetView(entry: entry)
                .containerBackground(for: .widget) { WInk.paper }
                .widgetURL(URL(string: "moneylist://compose"))
        }
        .configurationDisplayName(Text("Today's allowance"))
        .description(Text("What you can still spend today, and the month at a glance."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct AllowanceWidgetView: View {
    let entry: GlanceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snapshot = entry.snapshot
        let now = GlanceNow(snapshot, at: entry.date)
        let accent = WInk.hex(snapshot.accentHex)
        switch family {
        case .accessoryCircular:
            Gauge(value: now.used) {
                Image(systemName: "sun.max")
            } currentValueLabel: {
                Text(verbatim: snapshot.masked ? "•" : compact(now.left, snapshot.currency))
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Left today")
                    .font(.system(size: 11, weight: .semibold))
                    .widgetAccentable()
                Text(verbatim: WInk.money(max(now.left, 0), snapshot.currency, masked: snapshot.masked))
                    .font(WInk.figure(20, .semibold))
                    .minimumScaleFactor(0.6)
                Gauge(value: now.used) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
            }
        case .accessoryInline:
            Text("\(WInk.money(max(now.left, 0), snapshot.currency, masked: snapshot.masked)) left today")
        case .systemMedium:
            HStack(spacing: 16) {
                allowanceBlock(snapshot: snapshot, now: now, accent: accent)
                VStack(alignment: .leading, spacing: 8) {
                    WKicker("This month")
                    MiniBars(values: snapshot.dayBars, todayIndex: snapshot.todayIndex, daily: now.daily, accent: accent, masked: snapshot.masked)
                        .frame(height: 50)
                    HStack(spacing: 3) {
                        Text("Spent")
                            .foregroundStyle(WInk.soft)
                        Text(verbatim: WInk.money(snapshot.monthSpent, snapshot.currency, masked: snapshot.masked))
                            .foregroundStyle(WInk.text)
                        if let plan = snapshot.monthPlan {
                            Text(verbatim: "/ " + WInk.money(plan, snapshot.currency, masked: snapshot.masked))
                                .foregroundStyle(WInk.faint)
                        }
                    }
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            }
        default:
            allowanceBlock(snapshot: snapshot, now: now, accent: accent)
        }
    }

    private func allowanceBlock(snapshot: GlanceSnapshot, now: GlanceNow, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                WKicker(now.left < 0 ? "Over today" : "Left today")
                Spacer()
                Image(systemName: "pencil.line")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Spacer(minLength: 0)
            Text(verbatim: WInk.money(abs(now.left), snapshot.currency, masked: snapshot.masked))
                .font(WInk.figure(30))
                .foregroundStyle(now.left < 0 ? WInk.loss : WInk.text)
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .padding(.horizontal, 2)
                .background(alignment: .bottom) {
                    if now.left > 0 && !snapshot.masked {
                        Capsule().fill(WInk.marker.opacity(0.85)).frame(height: 13).offset(y: -3)
                    }
                }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(WInk.rule)
                    Capsule().fill(now.left < 0 ? WInk.loss : accent).frame(width: proxy.size.width * now.used)
                }
            }
            .frame(height: 4)
            Text("\(now.daysLeft) days left")
                .font(.system(size: 10))
                .foregroundStyle(WInk.soft)
        }
    }

    private func compact(_ value: Double, _ code: String) -> String {
        let absValue = abs(value)
        if absValue >= 10_000 {
            return value.formatted(.number.notation(.compactName).precision(.significantDigits(2)))
        }
        return value.formatted(.number.precision(.fractionLength(0)))
    }
}

struct MiniBars: View {
    let values: [Double]
    let todayIndex: Int
    let daily: Double
    let accent: Color
    let masked: Bool

    var body: some View {
        GeometryReader { proxy in
            let count = max(values.count, 1)
            let gap: CGFloat = 1.5
            let width = max((proxy.size.width - gap * CGFloat(count - 1)) / CGFloat(count), 1.5)
            let peak = max(values.max() ?? 0, daily * 1.4, 1)
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(values.indices, id: \.self) { index in
                    let future = index > todayIndex
                    let height = future || masked ? 2 : max(CGFloat(values[index] / peak) * proxy.size.height, values[index] > 0 ? 2.5 : 1.5)
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(future ? WInk.rule : (index == todayIndex ? accent : (daily > 0 && values[index] > daily ? WInk.loss : WInk.text.opacity(0.7))))
                        .frame(width: width, height: height)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

// MARK: - Net worth widget

struct WorthWidget: Widget {
    let kind = "MoneyListWorth"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GlanceProvider()) { entry in
            WorthWidgetView(entry: entry)
                .containerBackground(for: .widget) { WInk.paper }
                .widgetURL(URL(string: "moneylist://wealth"))
        }
        .configurationDisplayName(Text("Net worth"))
        .description(Text("Everything you own minus what you owe, with the last 30 days."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WorthWidgetView: View {
    let entry: GlanceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snapshot = entry.snapshot
        let accent = WInk.hex(snapshot.accentHex)
        VStack(alignment: .leading, spacing: 6) {
            WKicker("Net worth")
            Spacer(minLength: 0)
            Text(verbatim: WInk.money(snapshot.netWorth, snapshot.currency, masked: snapshot.masked))
                .font(WInk.figure(family == .systemSmall ? 24 : 30))
                .foregroundStyle(snapshot.netWorth < 0 ? WInk.loss : WInk.text)
                .minimumScaleFactor(0.45)
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: snapshot.netWorthChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                Text(verbatim: WInk.money(abs(snapshot.netWorthChange), snapshot.currency, masked: snapshot.masked))
                Text("in 30 days").foregroundStyle(WInk.soft)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(snapshot.netWorthChange >= 0 ? WInk.gain : WInk.loss)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            if !snapshot.masked {
                Sparkline(values: snapshot.worthSpark, tint: accent)
                    .frame(height: family == .systemSmall ? 26 : 34)
            }
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let low = values.min() ?? 0
            let high = values.max() ?? 1
            let span = max(high - low, 1)
            Path { path in
                for (index, value) in values.enumerated() {
                    let x = proxy.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                    let y = proxy.size.height * (1 - CGFloat((value - low) / span))
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Bills widget

struct BillsWidget: Widget {
    let kind = "MoneyListBills"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GlanceProvider()) { entry in
            BillsWidgetView(entry: entry)
                .containerBackground(for: .widget) { WInk.paper }
                .widgetURL(URL(string: "moneylist://bills"))
        }
        .configurationDisplayName(Text("Coming up"))
        .description(Text("Your next bills, subscriptions and paydays."))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct BillsWidgetView: View {
    let entry: GlanceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snapshot = entry.snapshot
        let items = Array(snapshot.upcoming.prefix(family == .systemLarge ? 5 : 3))
        VStack(alignment: .leading, spacing: 8) {
            WKicker("Coming up")
            if items.isEmpty {
                Spacer()
                Text("No bills in the next two weeks.")
                    .font(.system(size: 13))
                    .foregroundStyle(WInk.soft)
                Spacer()
            } else {
                ForEach(items) { bill in
                    HStack(spacing: 10) {
                        VStack(spacing: 0) {
                            Text(verbatim: bill.dueDate.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.system(size: 8, weight: .bold))
                                .textCase(.uppercase)
                                .foregroundStyle(WInk.soft)
                            Text(verbatim: bill.dueDate.formatted(.dateTime.day()))
                                .font(WInk.figure(14, .semibold))
                                .foregroundStyle(WInk.text)
                        }
                        .frame(width: 30)
                        RoundedRectangle(cornerRadius: 1.5).fill(WInk.hex(bill.colorHex)).frame(width: 3, height: 22)
                        Text(verbatim: bill.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WInk.text)
                            .lineLimit(1)
                        Spacer()
                        Text(verbatim: (bill.isIncome ? "+" : "") + WInk.money(bill.amount, bill.currency, masked: snapshot.masked, cents: true))
                            .font(WInk.figure(13, .medium))
                            .foregroundStyle(bill.isIncome ? WInk.gain : WInk.text)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Bundle

@main
struct MoneyListWidgetBundle: WidgetBundle {
    var body: some Widget {
        AllowanceWidget()
        WorthWidget()
        BillsWidget()
    }
}
