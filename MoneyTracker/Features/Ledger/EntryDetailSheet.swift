import SwiftUI
import SwiftData
import UIKit

/// An entry shown as a paper receipt.
struct EntryDetailSheet: View {
    let entry: Transaction

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RateBook.self) private var rates
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Query private var rules: [RecurringRule]

    @State private var photo: UIImage?
    @State private var showPhoto = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    receipt
                    if let photo {
                        Button { showPhoto = true } label: {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 180)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Ink.rule))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Receipt photo"))
                    }
                    actions
                }
                .padding(18)
            }
            .paperBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
                if let data = writer.receipt(for: entry) {
                    photo = UIImage(data: data)
                }
            }
            .fullScreenCover(isPresented: $showPhoto) {
                PhotoViewer(image: photo)
            }
            .confirmationDialog(Text("Delete this entry?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var receipt: some View {
        VStack(spacing: 14) {
            Kicker(kindTitle, color: tone)
            MoneyText(value: entry.amount, code: entry.currencyCode, size: .large, tone: tone)
            if let original = entry.originalAmount, let code = entry.originalCurrency {
                HStack(spacing: 4) {
                    Text("Paid")
                    MoneyText(value: original, code: code, size: .tiny, tone: Ink.soft)
                }
                .font(Typeface.detail)
                .foregroundStyle(Ink.soft)
            }
            Text(verbatim: entry.displayTitle)
                .font(Typeface.heading)
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.center)

            DottedLeader().fill(Ink.ruleStrong).frame(height: 6)

            VStack(spacing: 10) {
                if let category = entry.category {
                    LeaderRow { Text("Category") } trailing: {
                        Label(category.name, systemImage: category.iconName).labelStyle(.titleAndIcon)
                    }
                }
                if entry.kind == .transfer {
                    LeaderRow { Text("From") } trailing: { Text(verbatim: entry.account?.name ?? "—") }
                    LeaderRow { Text("To") } trailing: { Text(verbatim: entry.toAccount?.name ?? "—") }
                    if let received = entry.toAmount, let code = entry.toAccount?.currencyCode {
                        LeaderRow { Text("Received") } trailing: { MoneyText(value: received, code: code, size: .tiny) }
                    }
                } else {
                    LeaderRow { Text("Account") } trailing: { Text(verbatim: entry.account?.name ?? "—") }
                }
                LeaderRow { Text("Date") } trailing: {
                    Text(verbatim: entry.date.formatted(date: .abbreviated, time: .shortened))
                }
                if let ruleID = entry.recurringRuleId {
                    LeaderRow { Text("Repeats") } trailing: {
                        Text(verbatim: rules.first { $0.id == ruleID }.map { CadenceText.title($0.cadence) } ?? String(localized: "Ended"))
                    }
                }
            }
            .font(Typeface.label)
            .foregroundStyle(Ink.text)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity)
        .background(Ink.raised, in: ReceiptEdge())
        .overlay(ReceiptEdge().stroke(Ink.rule, lineWidth: 0.8))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                let request = ComposerRequest(kind: entry.kind, editing: entry)
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { router.composer = request }
            } label: {
                Label(String(localized: "Edit"), systemImage: "pencil")
            }
            .buttonStyle(InkButtonStyle(kind: .solid))
            HStack(spacing: 10) {
                Button {
                    let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
                    if (try? writer.duplicate(entry)) != nil {
                        Upkeep.afterChange(context: context, rates: rates)
                        Haptic.success()
                        toasts.show(String(localized: "Added again for today"))
                        dismiss()
                    }
                } label: {
                    Label(String(localized: "Repeat today"), systemImage: "plus.square.on.square")
                }
                .buttonStyle(InkButtonStyle(kind: .outline))
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label(String(localized: "Delete"), systemImage: "trash")
                        .foregroundStyle(Ink.loss)
                }
                .buttonStyle(InkButtonStyle(kind: .outline))
            }
        }
    }

    private var kindTitle: LocalizedStringKey {
        switch entry.kind {
        case .expense: return "Spent"
        case .income: return "Received"
        case .transfer: return "Moved"
        }
    }

    private var tone: Color {
        switch entry.kind {
        case .expense: return Ink.text
        case .income: return Ink.gain
        case .transfer: return Ink.soft
        }
    }

    private func delete() {
        let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
        try? writer.delete(entry)
        Upkeep.afterChange(context: context, rates: rates)
        Haptic.firm()
        dismiss()
    }
}

struct PhotoViewer: View {
    let image: UIImage?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnifyGesture().onChanged { value in scale = max(1, value.magnification) }.onEnded { _ in withAnimation { scale = 1 } })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding()
            }
            .accessibilityLabel(Text("Close"))
        }
    }
}
