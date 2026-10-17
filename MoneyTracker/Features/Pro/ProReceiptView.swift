import SwiftUI
import StoreKit
import Foundation

/// The Pro offer, printed as a receipt.
struct ProReceiptView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.inkAccent) private var accent
    @Environment(ProPass.self) private var pro

    @State private var appeared = false

    private let lines: [(LocalizedStringKey, String)] = [
        ("Unlimited accounts & budgets", "infinity"),
        ("Unlimited goals and bills", "flag.checkered"),
        ("Full net worth history", "chart.xyaxis.line"),
        ("Receipt photos with total scan", "doc.text.viewfinder"),
        ("All accent colors", "paintpalette"),
        ("No ads, ever", "nosign")
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Ink.paper.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    LedgerMark(size: 72, animated: true)
                        .padding(.top, 36)
                    VStack(spacing: 6) {
                        Text("Money List Pro")
                            .font(Typeface.display)
                            .foregroundStyle(Ink.text)
                        Text("Everything, for good. One payment, no subscription.")
                            .font(Typeface.label)
                            .foregroundStyle(Ink.soft)
                            .multilineTextAlignment(.center)
                    }
                    receipt
                    buyButton
                    footer
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ink.soft)
                    .frame(width: 36, height: 36)
                    .background(Ink.sheet, in: Circle())
                    .overlay(Circle().strokeBorder(Ink.rule))
            }
            .padding(16)
            .accessibilityLabel(Text("Close"))
        }
        .task { await pro.loadProduct() }
        .trackScreen("paywall")
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.3)) { appeared = true } }
        .onChange(of: pro.isPro) { _, unlocked in
            if unlocked { dismiss() }
        }
        .alert(Text("Purchase"), isPresented: Binding(get: { pro.errorMessage != nil }, set: { if !$0 { pro.errorMessage = nil } })) {
            Button("OK", role: .cancel) { pro.errorMessage = nil }
        } message: {
            Text(verbatim: pro.errorMessage ?? "")
        }
    }

    private var receipt: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Kicker(verbatim: "MONEY LIST")
                Spacer()
                Kicker(verbatim: Date().formatted(.dateTime.day().month(.twoDigits).year()))
            }
            DottedLeader().fill(Ink.ruleStrong).frame(height: 6)
            ForEach(lines.indices, id: \.self) { index in
                LeaderRow {
                    HStack(spacing: 8) {
                        Image(systemName: lines[index].1)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accent)
                            .frame(width: 18)
                        Text(lines[index].0)
                            .font(Typeface.label)
                            .foregroundStyle(Ink.text)
                    }
                } trailing: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Ink.gain)
                }
            }
            DottedLeader().fill(Ink.ruleStrong).frame(height: 6)
            LeaderRow {
                Text("Total, once")
                    .font(Typeface.labelStrong)
                    .foregroundStyle(Ink.text)
            } trailing: {
                Text(verbatim: pro.priceText ?? "—")
                    .font(Typeface.figure(22, weight: .semibold))
                    .foregroundStyle(Ink.text)
            }
            HStack {
                Spacer()
                Stamp("Paid once · yours forever", tone: accent, tilt: -6)
                    .scaleEffect(appeared ? 1 : 1.6)
                    .opacity(appeared ? 1 : 0)
                Spacer()
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 30)
        .background(Ink.raised, in: ReceiptEdge())
        .overlay(ReceiptEdge().stroke(Ink.rule, lineWidth: 0.8))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
    }

    private var buyButton: some View {
        Button {
            Task { await pro.purchase() }
        } label: {
            HStack(spacing: 8) {
                if pro.isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text("Unlock Pro")
                    if let price = pro.priceText {
                        Text(verbatim: "· \(price)")
                    }
                }
            }
        }
        .buttonStyle(InkButtonStyle(kind: .solid))
        .disabled(pro.isWorking)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button("Restore purchase") {
                Task { await pro.restore() }
            }
            .font(Typeface.labelStrong)
            .foregroundStyle(Ink.text)
            HStack(spacing: 14) {
                Button("Terms of use") { openURL(AppConfig.termsURL) }
                Button("Privacy policy") { openURL(AppConfig.privacyURL) }
            }
            .font(Typeface.detail)
            .foregroundStyle(Ink.soft)
            Text("A one-time in-app purchase tied to your Apple Account. Restore it on any of your devices.")
                .font(Typeface.micro)
                .foregroundStyle(Ink.faint)
                .multilineTextAlignment(.center)
        }
    }
}

/// Hosts the Pro screen at one presentation level. The root view and the
/// sheets that can ask for Pro each attach it; only the level on top shows it,
/// so the screen opens even while Settings or the entry form is up.
private struct PaywallCover: ViewModifier {
    let layer: Router.PaywallLayer
    @Environment(Router.self) private var router

    func body(content: Content) -> some View {
        // Read here, in body, so SwiftUI redraws this level as soon as the
        // request changes; a value read only inside the binding is not tracked.
        let shown = router.showPaywall && router.paywallLayer == layer
        content.fullScreenCover(isPresented: Binding(
            get: { shown },
            set: { if !$0 { router.showPaywall = false } }
        )) {
            ProReceiptView()
        }
    }
}

extension View {
    func paywallCover(_ layer: Router.PaywallLayer) -> some View {
        modifier(PaywallCover(layer: layer))
    }
}
