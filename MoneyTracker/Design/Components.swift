import SwiftUI
import UIKit

// MARK: - Text pieces

/// Small uppercase label above figures and sections ("LEFT TODAY").
struct Kicker: View {
    private let text: Text
    private let color: Color

    init(_ key: LocalizedStringKey, color: Color = Ink.soft) {
        self.text = Text(key)
        self.color = color
    }

    init(verbatim: String, color: Color = Ink.soft) {
        self.text = Text(verbatim: verbatim)
        self.color = color
    }

    var body: some View {
        text
            .font(Typeface.kicker)
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Every amount in the app goes through this view (privacy masking, digits, animation).
struct MoneyText: View {
    enum Size {
        case hero, large, medium, row, small, tiny

        var font: Font {
            switch self {
            case .hero: return Typeface.figure(56, weight: .regular)
            case .large: return Typeface.figure(36, weight: .regular)
            case .medium: return Typeface.figure(24, weight: .medium)
            case .row: return Typeface.rowFigure
            case .small: return Typeface.smallFigure
            case .tiny: return Font.system(.caption, design: .serif, weight: .medium)
            }
        }
    }

    let value: Decimal
    let code: String
    var size: Size = .row
    var signed = false
    var tone: Color? = nil
    var cents = true

    @Environment(\.masksAmounts) private var masked

    private var formatted: String {
        signed ? MoneyFormat.signed(value, code: code) : MoneyFormat.plain(value, code: code, cents: cents)
    }

    var body: some View {
        Text(verbatim: masked ? MoneyFormat.masked : formatted)
            .font(size.font)
            .monospacedDigit()
            .foregroundStyle(tone ?? Ink.text)
            .contentTransition(.numericText(value: Decimals.double(value)))
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .accessibilityLabel(masked ? Text("Hidden amount") : Text(verbatim: formatted))
    }
}

// MARK: - Ledger ornaments

/// The dotted line between a label and its amount, like a printed ledger.
struct DottedLeader: Shape {
    var spacing: CGFloat = 4.5
    var dot: CGFloat = 1.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.maxY - dot - 1
        var x = rect.minX + 2
        while x + dot < rect.maxX - 2 {
            path.addEllipse(in: CGRect(x: x, y: y, width: dot, height: dot))
            x += spacing
        }
        return path
    }
}

struct LeaderRow<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            leading
            DottedLeader()
                .fill(Ink.ruleStrong)
                .frame(height: 8)
                .frame(minWidth: 10)
            trailing
        }
    }
}

/// Rubber-stamp status ("ON PACE", "OVER", "PAID").
struct Stamp: View {
    private let text: Text
    private let tone: Color
    private let tilt: Double

    init(_ key: LocalizedStringKey, tone: Color, tilt: Double = -4) {
        self.text = Text(key)
        self.tone = tone
        self.tilt = tilt
    }

    init(verbatim: String, tone: Color, tilt: Double = -4) {
        self.text = Text(verbatim: verbatim)
        self.tone = tone
        self.tilt = tilt
    }

    var body: some View {
        text
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(tone)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(tone, lineWidth: 1.3)
            )
            .rotationEffect(.degrees(tilt))
            .opacity(0.94)
    }
}

/// Highlighter swash drawn behind important figures.
struct MarkerSwash: Shape {
    func path(in rect: CGRect) -> Path {
        let top = rect.minY + rect.height * 0.46
        let bottom = rect.maxY - rect.height * 0.06
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - 6, y: top + 3))
        path.addQuadCurve(to: CGPoint(x: rect.maxX + 6, y: top), control: CGPoint(x: rect.midX, y: top - 5))
        path.addLine(to: CGPoint(x: rect.maxX + 3, y: bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX - 3, y: bottom + 2), control: CGPoint(x: rect.midX, y: bottom + 4))
        path.closeSubpath()
        return path
    }
}

extension View {
    func highlighter(_ active: Bool = true) -> some View {
        background {
            if active {
                MarkerSwash().fill(Ink.marker.opacity(0.9))
            }
        }
    }
}

/// Coloured index tab on the leading edge of a row.
struct IndexTab: View {
    let color: Color
    var height: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(color)
            .frame(width: 3, height: height)
    }
}

/// Category/account symbol on a small paper tile with a coloured tab.
struct Glyph: View {
    let symbol: String
    let hex: String
    var size: CGFloat = 36

    var body: some View {
        let tint = Color(hexString: hex)
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(tint.opacity(0.10))
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 0.8)
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
            Capsule()
                .fill(tint)
                .frame(width: 2.5, height: size * 0.46)
                .padding(.leading, 3)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Containers

struct PaperCard: ViewModifier {
    var padding: CGFloat = 16
    var raised = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(raised ? Ink.raised : Ink.sheet, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Ink.rule, lineWidth: 0.8)
            )
    }
}

extension View {
    func paperCard(padding: CGFloat = 16, raised: Bool = false) -> some View {
        modifier(PaperCard(padding: padding, raised: raised))
    }

    /// Screen background used everywhere.
    func paperBackground() -> some View {
        background(Ink.paper.ignoresSafeArea())
    }
}

/// Section title in the ledger style: serif heading + optional trailing action.
struct SectionHeading<Trailing: View>: View {
    private let title: Text
    private let trailing: Trailing

    init(_ key: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = Text(key)
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            title
                .font(Typeface.heading)
                .foregroundStyle(Ink.text)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension SectionHeading where Trailing == EmptyView {
    init(_ key: LocalizedStringKey) {
        self.init(key) { EmptyView() }
    }
}

/// Empty state written like a note on a blank page.
struct EmptyPage: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .strokeBorder(Ink.ruleStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .frame(width: 72, height: 72)
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Ink.soft)
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(Typeface.heading)
                    .foregroundStyle(Ink.text)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(Typeface.label)
                    .foregroundStyle(Ink.soft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                }
                .buttonStyle(InkButtonStyle(kind: .solid, compact: true))
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Progress

struct PaceBar: View {
    var fraction: Double
    var pace: Double? = nil
    var tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let filled = width * Decimals.clamp01(fraction)
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.rule).frame(height: height)
                Capsule().fill(tint).frame(width: fraction > 0 ? max(filled, height) : 0, height: height)
                if let pace {
                    Rectangle()
                        .fill(Ink.text.opacity(0.75))
                        .frame(width: 1.5, height: height + 6)
                        .offset(x: min(max(width * Decimals.clamp01(pace) - 0.75, 0), width - 1.5))
                }
            }
            .frame(height: height + 6)
        }
        .frame(height: height + 6)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(Int((fraction * 100).rounded()))%"))
    }
}

struct InkRing: View {
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(Ink.rule, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: Decimals.clamp01(fraction))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Paper edge with a torn/perforated bottom, used for receipts.
struct ReceiptEdge: Shape {
    var tooth: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tooth))
        var x = rect.maxX
        var down = true
        while x > rect.minX {
            let next = max(x - tooth, rect.minX)
            path.addLine(to: CGPoint(x: next, y: down ? rect.maxY : rect.maxY - tooth))
            down.toggle()
            x = next
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Feedback

enum Haptic {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func firm() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
