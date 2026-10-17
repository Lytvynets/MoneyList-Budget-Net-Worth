import SwiftUI
import Observation

// MARK: - Buttons

struct InkButtonStyle: ButtonStyle {
    enum Kind { case solid, outline, quiet }

    var kind: Kind = .solid
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        InkButtonFace(kind: kind, compact: compact, pressed: configuration.isPressed) {
            configuration.label
        }
    }
}

private struct InkButtonFace<Label: View>: View {
    let kind: InkButtonStyle.Kind
    let compact: Bool
    let pressed: Bool
    let label: Label

    @Environment(\.inkAccent) private var accent
    @Environment(\.isEnabled) private var enabled

    init(kind: InkButtonStyle.Kind, compact: Bool, pressed: Bool, @ViewBuilder label: () -> Label) {
        self.kind = kind
        self.compact = compact
        self.pressed = pressed
        self.label = label()
    }

    var body: some View {
        label
            .font(compact ? Typeface.labelStrong : Font.body.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 16 : 20)
            .frame(minHeight: compact ? 38 : 52)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(background)
            .overlay {
                if kind == .outline {
                    Capsule().strokeBorder(Ink.ruleStrong, lineWidth: 1)
                }
            }
            .clipShape(Capsule())
            .opacity(enabled ? (pressed ? 0.82 : 1) : 0.45)
            .scaleEffect(pressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }

    private var foreground: Color {
        switch kind {
        case .solid: return .white
        case .outline: return Ink.text
        case .quiet: return accent
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .solid: accent
        case .outline: Ink.sheet
        case .quiet: accent.opacity(0.10)
        }
    }
}

/// A selectable pill used for categories, accounts, dates and filters.
struct Chip: View {
    private let title: Text
    private let symbol: String?
    private let selected: Bool
    private let tint: Color?
    private let dashed: Bool

    init(_ key: LocalizedStringKey, symbol: String? = nil, selected: Bool = false, tint: Color? = nil, dashed: Bool = false) {
        self.title = Text(key)
        self.symbol = symbol
        self.selected = selected
        self.tint = tint
        self.dashed = dashed
    }

    init(verbatim: String, symbol: String? = nil, selected: Bool = false, tint: Color? = nil, dashed: Bool = false) {
        self.title = Text(verbatim: verbatim)
        self.symbol = symbol
        self.selected = selected
        self.tint = tint
        self.dashed = dashed
    }

    @Environment(\.inkAccent) private var accent

    var body: some View {
        let color = tint ?? accent
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
            }
            title
                .lineLimit(1)
        }
        .font(Typeface.label)
        .foregroundStyle(selected ? Color.white : Ink.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(selected ? color : Ink.sheet, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(selected ? Color.clear : Ink.ruleStrong, style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 3] : []))
        }
        .contentShape(Capsule())
    }
}

/// Editorial section switcher: words with an ink underline.
struct SegmentRail<Value: Hashable>: View {
    let items: [(value: Value, title: LocalizedStringKey)]
    @Binding var selection: Value

    @Namespace private var underline
    @Environment(\.inkAccent) private var accent

    var body: some View {
        HStack(spacing: 20) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let isOn = item.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = item.value }
                    Haptic.tap()
                } label: {
                    VStack(spacing: 6) {
                        Text(item.title)
                            .font(isOn ? Typeface.labelStrong : Typeface.label)
                            .foregroundStyle(isOn ? Ink.text : Ink.soft)
                        ZStack {
                            Capsule().fill(Color.clear).frame(height: 2.5)
                            if isOn {
                                Capsule()
                                    .fill(accent)
                                    .frame(height: 2.5)
                                    .matchedGeometryEffect(id: "rail", in: underline)
                            }
                        }
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Toasts

struct Toast: Identifiable {
    let id = UUID()
    let message: String
    var undo: (() -> Void)?
}

@Observable
final class ToastCenter {
    private(set) var current: Toast?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    func show(_ message: String, undo: (() -> Void)? = nil) {
        dismissTask?.cancel()
        withAnimation(.snappy) { current = Toast(message: message, undo: undo) }
        let id = current?.id
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if Task.isCancelled { return }
            if current?.id == id {
                withAnimation(.easeOut) { current = nil }
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut) { current = nil }
    }
}

struct ToastBanner: View {
    let toast: Toast
    let onUndo: () -> Void
    let onClose: () -> Void

    @Environment(\.inkAccent) private var accent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Ink.gain)
            Text(verbatim: toast.message)
                .font(Typeface.label)
                .foregroundStyle(Ink.text)
                .lineLimit(2)
            Spacer(minLength: 4)
            if toast.undo != nil {
                Button(action: onUndo) {
                    Text("Undo").font(Typeface.labelStrong)
                }
                .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Ink.raised, in: Capsule())
        .overlay(Capsule().strokeBorder(Ink.rule, lineWidth: 0.8))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .padding(.horizontal, 16)
        .onTapGesture(perform: onClose)
    }
}

// MARK: - Calculator keypad

/// Number pad with + − × ÷ for the composer. Works on a plain expression string.
struct CalcKeypad: View {
    @Binding var expression: String
    var onDone: () -> Void

    @Environment(\.inkAccent) private var accent

    private let rows: [[String]] = [
        ["7", "8", "9", "÷"],
        ["4", "5", "6", "×"],
        ["1", "2", "3", "−"],
        [".", "0", "⌫", "+"]
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button { press(key) } label: {
                            keyFace(key)
                        }
                        .buttonStyle(KeyPressStyle())
                        .accessibilityLabel(accessibilityName(key))
                    }
                }
            }
            Button(action: onDone) {
                Text(isExpression ? "=" : String(localized: "Done"))
                    .font(.system(size: 20, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.white)
                    .background(accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(KeyPressStyle())
        }
    }

    private var isExpression: Bool {
        expression.dropFirst().contains { "+−×÷".contains($0) }
    }

    @ViewBuilder
    private func keyFace(_ key: String) -> some View {
        let isOperator = "÷×−+".contains(key)
        Group {
            if key == "⌫" {
                Image(systemName: "delete.left")
                    .font(.system(size: 20, weight: .medium))
            } else {
                Text(verbatim: key == "." ? decimalMark : key)
                    .font(isOperator ? .system(size: 22, weight: .medium) : Typeface.figure(26))
            }
        }
        .foregroundStyle(isOperator ? accent : Ink.text)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(isOperator ? accent.opacity(0.09) : Ink.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ink.rule, lineWidth: 0.8))
    }

    private var decimalMark: String { Locale.current.decimalSeparator ?? "." }

    private func accessibilityName(_ key: String) -> Text {
        switch key {
        case "⌫": return Text("Delete")
        case "÷": return Text("Divide")
        case "×": return Text("Multiply")
        case "−": return Text("Minus")
        case "+": return Text("Plus")
        case ".": return Text("Decimal point")
        default: return Text(verbatim: key)
        }
    }

    private func press(_ key: String) {
        Haptic.tap()
        switch key {
        case "⌫":
            if !expression.isEmpty { expression.removeLast() }
        case "+", "−", "×", "÷":
            guard let last = expression.last else { return }
            if "+−×÷".contains(last) {
                expression.removeLast()
            }
            if last == "." { expression.removeLast() }
            expression.append(key)
        case ".":
            let current = expression.split(whereSeparator: { "+−×÷".contains($0) }).last.map(String.init) ?? ""
            if expression.isEmpty || "+−×÷".contains(expression.last!) {
                expression.append("0.")
            } else if !current.contains(".") {
                expression.append(".")
            }
        default:
            let current = expression.split(whereSeparator: { "+−×÷".contains($0) }).last.map(String.init) ?? ""
            if let dot = current.firstIndex(of: "."), current.distance(from: dot, to: current.endIndex) > 2,
               !(expression.last.map { "+−×÷".contains($0) } ?? false) {
                return
            }
            if current == "0" && !(expression.last.map { "+−×÷".contains($0) } ?? true) {
                expression.removeLast()
            }
            if expression.count < 24 { expression.append(key) }
        }
    }
}

private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
