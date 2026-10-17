import SwiftUI

/// Opening scene (about three seconds, `splash_seconds` in Remote Config).
///
/// The app icon writes itself like a ledger slip: the card lands on ruled
/// paper, three entries are written, the middle one is highlighted, the total
/// is ruled twice and the name appears. A tap skips it; with Reduce Motion it
/// simply fades.
struct SplashView: View {
    var duration: Double
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = 0
    @State private var leaving = false
    @State private var finished = false

    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()

            NotebookPaper()
                .opacity(stage >= 1 ? 1 : 0)
                .animation(.easeOut(duration: 0.6), value: stage)

            VStack(spacing: 30) {
                SplashMark(stage: stage, size: 156)
                VStack(spacing: 10) {
                    Text(verbatim: "Money List")
                        .font(.system(size: 36, weight: .semibold, design: .serif))
                        .foregroundStyle(Ink.text)
                        .tracking(stage >= 9 ? 0.4 : 9)
                        .opacity(stage >= 9 ? 1 : 0)
                        .animation(.easeOut(duration: 0.7), value: stage)
                    Text("Your money,\nwritten down plainly.")
                        .font(Typeface.label)
                        .foregroundStyle(Ink.soft)
                        .multilineTextAlignment(.center)
                        .opacity(stage >= 10 ? 1 : 0)
                        .offset(y: stage >= 10 ? 0 : 8)
                        .animation(.easeOut(duration: 0.5), value: stage)
                }
            }
            .offset(y: -16)
        }
        .scaleEffect(leaving ? 1.06 : 1)
        .opacity(leaving ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task { await play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Money List"))
        .accessibilityAddTraits(.isImage)
    }

    // MARK: Timeline

    private func play() async {
        if reduceMotion {
            stage = 10
            await pause(min(duration, 1.2))
            finish()
            return
        }
        // Beats for a three-second run; other durations stretch or squeeze them.
        let scale = max(duration, 1.2) / 3.0
        let beats: [(stage: Int, at: Double)] = [
            (1, 0.05),   // ruled paper
            (2, 0.15),   // the card pops in
            (3, 0.45),   // the slip lands on it
            (4, 0.80),   // first entry
            (5, 0.98),   // second entry
            (6, 1.16),   // third entry
            (7, 1.38),   // highlighter swash
            (8, 1.70),   // total and the double rule
            (9, 1.95),   // name
            (10, 2.20)   // tagline
        ]
        var elapsed = 0.0
        for beat in beats {
            let target = beat.at * scale
            await pause(target - elapsed)
            elapsed = target
            if finished { return }
            stage = beat.stage
        }
        await pause(max(duration - 0.4 - elapsed, 0.2))
        finish()
    }

    private func pause(_ seconds: Double) async {
        guard seconds > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        withAnimation(.easeIn(duration: 0.4)) { leaving = true }
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            onFinish()
        }
    }
}

/// The icon, drawn in steps.
private struct SplashMark: View {
    let stage: Int
    let size: CGFloat

    private let paper = Color(red: 0.984, green: 0.969, blue: 0.937)
    private let ink = Color(red: 0.09, green: 0.094, blue: 0.11)
    private let marker = Color(red: 0.965, green: 0.83, blue: 0.416)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(light: 0xEE7149, dark: 0xF07A52), Color(light: 0xC23A1C, dark: 0xD24A28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color(light: 0xC23A1C, dark: 0x000000, opacity: 0.28), radius: size * 0.09, y: size * 0.05)
                .scaleEffect(stage >= 2 ? 1 : 0.4)
                .opacity(stage >= 2 ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: stage)

            slip
                .rotationEffect(.degrees(stage >= 3 ? -7 : -24))
                .offset(x: size * 0.005, y: stage >= 3 ? size * 0.012 : -size * 0.42)
                .opacity(stage >= 3 ? 1 : 0)
                .animation(.spring(response: 0.55, dampingFraction: 0.68), value: stage)
        }
        .frame(width: size, height: size)
    }

    private var slip: some View {
        let width = size * 0.60
        let height = size * 0.68
        let line = size * 0.044
        let pitch = size * 0.118
        let x0 = width * 0.14
        let column = width * 0.72
        let rows: [(item: CGFloat, amount: CGFloat)] = [(0.44, 0.13), (0.33, 0.17), (0.40, 0.11)]
        let firstRow = height * 0.17
        let totalY = firstRow + pitch * 3 + size * 0.010
        let rule = max(size * 0.013, 0.75)
        let ruleY = totalY + line * 1.25 + size * 0.030

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: size * 0.075, style: .continuous)
                .fill(paper)
                .shadow(color: .black.opacity(0.2), radius: size * 0.035, y: size * 0.02)

            // Highlighter swash behind the middle entry.
            bar(x: x0 - size * 0.026, y: firstRow + pitch + line / 2 - line * 1.5,
                width: column + size * 0.052, height: line * 3, color: marker,
                shown: stage >= 7, animation: .easeInOut(duration: 0.38))

            ForEach(rows.indices, id: \.self) { index in
                let y = firstRow + pitch * CGFloat(index)
                let shown = stage >= 4 + index
                bar(x: x0, y: y, width: width * rows[index].item, height: line, color: ink,
                    shown: shown, animation: .easeOut(duration: 0.24))
                bar(x: x0 + column - width * rows[index].amount, y: y, width: width * rows[index].amount, height: line, color: ink,
                    shown: shown, animation: .easeOut(duration: 0.16).delay(0.12))
            }

            bar(x: x0 + column - width * 0.24, y: totalY, width: width * 0.24, height: line * 1.25, color: ink,
                shown: stage >= 8, animation: .easeOut(duration: 0.22))
            bar(x: x0 + column - width * 0.30, y: ruleY, width: width * 0.30, height: rule, color: ink,
                shown: stage >= 8, animation: .easeOut(duration: 0.2).delay(0.14))
            bar(x: x0 + column - width * 0.30, y: ruleY + rule + size * 0.016, width: width * 0.30, height: rule, color: ink,
                shown: stage >= 8, animation: .easeOut(duration: 0.2).delay(0.24))
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private func bar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: Color, shown: Bool, animation: Animation) -> some View {
        Capsule()
            .fill(color)
            .frame(width: shown ? width : 0, height: height)
            .offset(x: x, y: y)
            .animation(animation, value: shown)
    }
}

/// Faint ledger paper: horizontal rules and a red margin line.
private struct NotebookPaper: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 30
            var y = spacing
            while y < size.height {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(Ink.rule), lineWidth: 0.6)
                y += spacing
            }
            var margin = Path()
            margin.move(to: CGPoint(x: 44, y: 0))
            margin.addLine(to: CGPoint(x: 44, y: size.height))
            context.stroke(margin, with: .color(Color(light: 0xE0532F, dark: 0xFF6B45, opacity: 0.25)), lineWidth: 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
