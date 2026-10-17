import SwiftUI
import Foundation

/// How to log Apple Pay purchases automatically with the Shortcuts app.
struct ShortcutsGuide: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker("Without bank access")
                    Text("Log Apple Pay purchases automatically")
                        .font(Typeface.title)
                        .foregroundStyle(Ink.text)
                    Text("iPhone can tell Money List about every Wallet payment. Set it up once in the Shortcuts app — it takes about a minute.")
                        .font(Typeface.label)
                        .foregroundStyle(Ink.soft)
                }

                VStack(alignment: .leading, spacing: 14) {
                    GuideStep(number: 1, text: "Open Shortcuts → Automation → New Automation.")
                    GuideStep(number: 2, text: "Choose “Transaction” (Wallet), pick your cards and set it to Run Immediately.")
                    GuideStep(number: 3, text: "Add the action “Log Purchase” from Money List.")
                    GuideStep(number: 4, text: "Tap Amount and choose the Shortcut Input “Amount”; tap Merchant and choose “Merchant”.")
                    GuideStep(number: 5, text: "Done. Each Apple Pay payment now appears in your ledger, already categorized.")
                }
                .paperCard()

                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label(String(localized: "Open Shortcuts"), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(InkButtonStyle(kind: .solid))

                VStack(alignment: .leading, spacing: 10) {
                    Kicker("Ask Siri")
                    PhraseRow(text: "“Write in Money List”")
                    PhraseRow(text: "“Log an expense in Money List”")
                    PhraseRow(text: "“What can I spend today in Money List”")
                    Text("You can also find these actions in Spotlight and add them to the Action button or Control Center.")
                        .font(Typeface.detail)
                        .foregroundStyle(Ink.soft)
                }
                .paperCard()
            }
            .padding(18)
        }
        .paperBackground()
        .trackScreen("automation_guide")
        .navigationTitle(Text("Automation"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GuideStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(Typeface.figure(15, weight: .semibold))
                .foregroundStyle(Ink.text)
                .frame(width: 26, height: 26)
                .background(Ink.marker.opacity(0.9), in: Circle())
            Text(text)
                .font(Typeface.label)
                .foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PhraseRow: View {
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .foregroundStyle(Ink.soft)
            Text(text)
                .font(Typeface.label)
                .foregroundStyle(Ink.text)
        }
    }
}

struct HelpScreen: View {
    private let items: [(LocalizedStringKey, LocalizedStringKey)] = [
        ("How do I write an entry fast?", "Type it like a note on Today: “coffee 4.50”, “taxi 120 yesterday”, “+2000 salary”. Money List finds the amount, date and category and learns from your corrections."),
        ("What is the daily allowance?", "It's what you can spend today and stay within your monthly plan. Bills are set aside first. Without a plan, it's based on your everyday accounts minus upcoming bills."),
        ("Do budgets carry over to next month?", "Yes. A budget keeps its limit every month until you change or remove it."),
        ("Can my month start on payday?", "Yes. Settings → Monthly plan & month start lets you pick any day from 1 to 28."),
        ("How do bills work?", "Add rent, subscriptions or salary once. Money List records them on the day (or asks first, if you prefer) and can remind you beforehand."),
        ("Where is my data?", "On your iPhone and in your private iCloud, synced between your devices. There is no account, and your entries are never sent to us — only anonymous usage statistics, which you can turn off in Settings → Privacy."),
        ("How do I move from another app?", "Export a CSV file from that app or your bank, then use Settings → Import from CSV. Money List detects the columns for you."),
        ("Why is my net worth chart approximate?", "History is rebuilt from your entries using today's exchange rates and prices, so it shows how your money moved rather than past market prices."),
        ("I bought Pro on another device", "Settings → Restore purchase. Pro is a one-time purchase tied to your Apple Account.")
    ]

    var body: some View {
        List {
            ForEach(items.indices, id: \.self) { index in
                DisclosureGroup {
                    Text(items[index].1)
                        .font(Typeface.label)
                        .foregroundStyle(Ink.soft)
                        .padding(.vertical, 4)
                } label: {
                    Text(items[index].0)
                        .font(Typeface.labelStrong)
                        .foregroundStyle(Ink.text)
                }
                .tint(Ink.soft)
            }
            Section {
                Link(destination: URL(string: "mailto:\(AppConfig.supportEmail)?subject=Money%20List")!) {
                    Label(String(localized: "Still stuck? Write to the developer"), systemImage: "envelope")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .paperBackground()
        .trackScreen("help")
        .navigationTitle(Text("Help"))
    }
}
