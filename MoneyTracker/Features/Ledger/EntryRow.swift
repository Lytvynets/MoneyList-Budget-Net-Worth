import SwiftUI

/// One ledger line: glyph, title, context, signed amount.
struct EntryRow: View {
    let entry: Transaction
    var showsTime = true

    var body: some View {
        HStack(spacing: 12) {
            glyph
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(verbatim: entry.displayTitle)
                        .font(Typeface.labelStrong)
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                    if entry.recurringRuleId != nil {
                        Image(systemName: "repeat")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Ink.faint)
                    }
                    if entry.hasAttachment == true || entry.receiptImageData != nil {
                        Image(systemName: "paperclip")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Ink.faint)
                    }
                }
                Text(verbatim: subtitle)
                    .font(Typeface.detail)
                    .foregroundStyle(Ink.soft)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                MoneyText(value: displayAmount, code: entry.currencyCode, size: .row, signed: entry.kind != .transfer, tone: tone)
                if let original = entry.originalAmount, let code = entry.originalCurrency {
                    MoneyText(value: original, code: code, size: .tiny, tone: Ink.faint)
                } else if showsTime {
                    Text(verbatim: entry.date.formatted(date: .omitted, time: .shortened))
                        .font(Typeface.micro)
                        .foregroundStyle(Ink.faint)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var glyph: some View {
        if entry.kind == .transfer {
            Glyph(symbol: "arrow.left.arrow.right", hex: InkSwatch.slate, size: 36)
        } else if let category = entry.category {
            Glyph(symbol: category.iconName, hex: category.colorHex, size: 36)
        } else {
            Glyph(symbol: entry.kind == .income ? "arrow.down.left" : "arrow.up.right", hex: InkSwatch.graphite, size: 36)
        }
    }

    private var displayAmount: Decimal {
        switch entry.kind {
        case .expense: return -entry.amount
        case .income: return entry.amount
        case .transfer: return entry.amount
        }
    }

    private var tone: Color {
        switch entry.kind {
        case .expense: return Ink.text
        case .income: return Ink.gain
        case .transfer: return Ink.soft
        }
    }

    private var subtitle: String {
        switch entry.kind {
        case .transfer:
            let from = entry.account?.name ?? "—"
            let to = entry.toAccount?.name ?? "—"
            return "\(from) → \(to)"
        default:
            var parts: [String] = []
            if let note = entry.note, !note.isEmpty, let category = entry.category { parts.append(category.name) }
            if let account = entry.account { parts.append(account.name) }
            return parts.joined(separator: " · ")
        }
    }
}
