import SwiftUI

/// The Money List mark (same drawing as the app icon): a tilted paper slip with
/// three entries — the middle one highlighted — and a double-ruled total.
struct LedgerMark: View {
    var size: CGFloat = 64
    var animated = false

    @State private var drawn = false

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
            slip
                .rotationEffect(.degrees(-7))
                .offset(x: size * 0.005, y: size * 0.012)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animated else { drawn = true; return }
            withAnimation(.easeOut(duration: 0.9).delay(0.15)) { drawn = true }
        }
        .accessibilityHidden(true)
    }

    private var slip: some View {
        let width = size * 0.60
        let height = size * 0.68
        let line = max(size * 0.044, 1.5)
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
                width: column + size * 0.052, height: line * 3, color: marker)

            ForEach(rows.indices, id: \.self) { index in
                let y = firstRow + pitch * CGFloat(index)
                bar(x: x0, y: y, width: width * rows[index].item, height: line, color: ink)
                bar(x: x0 + column - width * rows[index].amount, y: y, width: width * rows[index].amount, height: line, color: ink)
            }

            bar(x: x0 + column - width * 0.24, y: totalY, width: width * 0.24, height: line * 1.25, color: ink)
            bar(x: x0 + column - width * 0.30, y: ruleY, width: width * 0.30, height: rule, color: ink)
            bar(x: x0 + column - width * 0.30, y: ruleY + rule + size * 0.016, width: width * 0.30, height: rule, color: ink)
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private func bar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: drawn ? width : 0, height: height)
            .offset(x: x, y: y)
    }
}
