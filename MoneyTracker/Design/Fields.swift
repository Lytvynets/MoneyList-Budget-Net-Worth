import SwiftUI

/// Text field for money that understands both "1 234,56" and "1,234.56".
struct AmountField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var currency: String
    var allowsNegative = false

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: MoneyFormat.symbol(for: currency))
                .font(Typeface.figure(18))
                .foregroundStyle(Ink.soft)
            TextField(title, text: $text)
                .keyboardType(allowsNegative ? .numbersAndPunctuation : .decimalPad)
                .font(Typeface.figure(20, weight: .medium))
                .foregroundStyle(Ink.text)
                .onChange(of: text) { _, newValue in
                    let filtered = newValue.filter { $0.isNumber || ".,  +-−".contains($0) }
                    if filtered != newValue { text = filtered }
                }
        }
    }

    static func value(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let reading = AmountReader.read(trimmed) else { return nil }
        return reading.explicitSign == .minus ? -reading.amount : reading.amount
    }
}

/// A labelled row inside editor cards.
struct FieldRow<Content: View>: View {
    private let title: Text
    private let content: Content

    init(_ key: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = Text(key)
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            title
                .font(Typeface.kicker)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Ink.soft)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Colour swatch picker with the ink palette.
struct SwatchPicker: View {
    @Binding var hex: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(InkSwatch.all, id: \.self) { item in
                    Button {
                        Haptic.tap()
                        hex = item
                    } label: {
                        Circle()
                            .fill(Color(hexString: item))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle().strokeBorder(Ink.text, lineWidth: hex == item ? 2 : 0)
                                    .padding(-4)
                            )
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// SF Symbol picker for categories, bills and goals.
struct SymbolPicker: View {
    @Binding var symbol: String
    var tintHex: String

    static let symbols: [String] = [
        "fork.knife", "cup.and.saucer.fill", "wineglass.fill", "takeoutbag.and.cup.and.straw.fill", "cart.fill", "basket.fill",
        "car.fill", "bus.fill", "tram.fill", "airplane", "fuelpump.fill", "bicycle", "figure.walk",
        "bag.fill", "tshirt.fill", "gift.fill", "tag.fill", "shippingbox.fill",
        "house.fill", "bed.double.fill", "sofa.fill", "lightbulb.fill", "bolt.fill", "drop.fill", "flame.fill", "wifi", "wrench.and.screwdriver.fill",
        "heart.fill", "cross.case.fill", "pills.fill", "stethoscope", "dumbbell.fill", "figure.run",
        "gamecontroller.fill", "film.fill", "music.note", "popcorn.fill", "theatermasks.fill", "book.fill", "graduationcap.fill",
        "pawprint.fill", "leaf.fill", "sparkles", "scissors", "camera.fill", "phone.fill", "iphone", "laptopcomputer", "tv.fill",
        "repeat", "creditcard.fill", "banknote.fill", "building.columns.fill", "briefcase.fill", "chart.line.uptrend.xyaxis",
        "suitcase.fill", "map.fill", "beach.umbrella.fill", "car.side.fill", "house.lodge.fill", "star.fill", "ellipsis.circle.fill"
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
            ForEach(SymbolPicker.symbols, id: \.self) { item in
                Button {
                    Haptic.tap()
                    symbol = item
                } label: {
                    Image(systemName: item)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(symbol == item ? Color.white : Color(hexString: tintHex))
                        .frame(width: 38, height: 38)
                        .background(symbol == item ? Color(hexString: tintHex) : Color(hexString: tintHex).opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Sheet chrome used by every editor: serif title, cancel/save.
struct EditorChrome<Content: View>: View {
    let title: Text
    let canSave: Bool
    let onSave: () -> Void
    let content: Content

    @Environment(\.dismiss) private var dismiss

    init(_ title: Text, canSave: Bool, onSave: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.canSave = canSave
        self.onSave = onSave
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .paperBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }
}
