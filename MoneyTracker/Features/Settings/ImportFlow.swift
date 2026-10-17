import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Foundation

/// Bring history over from another app or a bank export.
struct ImportFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moneyPrefs) private var prefs
    @Environment(RateBook.self) private var rates
    @Query private var accounts: [Account]

    @State private var picking = false
    @State private var table: [[String]] = []
    @State private var plan = ImportPlan(hasHeader: false, roles: [], dateFormat: nil)
    @State private var accountID: UUID?
    @State private var keepBalances = true
    @State private var skipDuplicates = true
    @State private var outcome: Importer.Outcome?
    @State private var failure: String?

    private var rows: [ImportedRow] { ImportMapper.rows(from: table, plan: plan) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let outcome {
                        done(outcome)
                    } else if table.isEmpty {
                        intro
                    } else {
                        mapping
                    }
                }
                .padding(18)
            }
            .paperBackground()
            .trackScreen("import")
            .navigationTitle(Text("Import"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(outcome == nil ? "Cancel" : "Close") { dismiss() }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text], allowsMultipleSelection: false) { result in
                load(result)
            }
            .onAppear {
                accountID = prefs.defaultAccountID ?? accounts.first(where: { !$0.isArchived })?.id
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Moving in")
                .font(Typeface.title)
                .foregroundStyle(Ink.text)
            Text("Export a CSV file from your old app or your bank (Monobank, PrivatBank, Revolut and most others can), then pick it here. Money List recognizes the columns and shows a preview before anything is saved.")
                .font(Typeface.label)
                .foregroundStyle(Ink.soft)
            if let failure {
                Text(verbatim: failure)
                    .font(Typeface.detail)
                    .foregroundStyle(Ink.loss)
            }
            Button {
                picking = true
            } label: {
                Label(String(localized: "Choose a CSV file"), systemImage: "doc.badge.plus")
            }
            .buttonStyle(InkButtonStyle(kind: .solid))
        }
    }

    private var mapping: some View {
        let recognised = rows
        let income = recognised.filter(\.isIncome).count
        let width = plan.roles.count
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker("Columns")
                Text("Check what each column means. Rows without a date or amount are skipped.")
                    .font(Typeface.detail)
                    .foregroundStyle(Ink.soft)
            }
            ForEach(0..<width, id: \.self) { column in
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: header(column))
                            .font(Typeface.labelStrong)
                            .foregroundStyle(Ink.text)
                            .lineLimit(1)
                        Text(verbatim: sample(column))
                            .font(Typeface.detail)
                            .foregroundStyle(Ink.soft)
                            .lineLimit(1)
                    }
                    Spacer()
                    Picker(selection: roleBinding(column)) {
                        ForEach(ImportRole.allCases) { role in
                            Text(roleTitle(role)).tag(role)
                        }
                    } label: { Text("Meaning") }
                    .labelsHidden()
                }
                .paperCard(padding: 12)
            }

            Toggle(isOn: $plan.hasHeader) { Text("First row is a header") }
                .paperCard(padding: 12)

            FieldRow("Into account") {
                Picker(selection: $accountID) {
                    ForEach(accounts.filter { !$0.isArchived }) { account in
                        Text(verbatim: "\(account.name) · \(account.currencyCode)").tag(Optional(account.id))
                    }
                } label: { Text("Account") }
                Toggle(isOn: $keepBalances) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep current balances")
                        Text("Past entries won't change what the account shows today.")
                            .font(Typeface.detail)
                            .foregroundStyle(Ink.soft)
                    }
                }
                Toggle(isOn: $skipDuplicates) { Text("Skip entries already in Money List") }
            }
            .paperCard()

            VStack(alignment: .leading, spacing: 6) {
                Kicker("Preview")
                Text("Entries found: \(recognised.count) · spending: \(recognised.count - income) · income: \(income)")
                    .font(Typeface.label)
                    .foregroundStyle(Ink.text)
                ForEach(Array(recognised.prefix(4).enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(verbatim: row.date.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(Ink.soft)
                        Text(verbatim: row.note.isEmpty ? (row.category ?? "—") : row.note)
                            .lineLimit(1)
                        Spacer()
                        Text(verbatim: (row.isIncome ? "+" : "−") + MoneyFormat.number(row.amount))
                            .foregroundStyle(row.isIncome ? Ink.gain : Ink.text)
                    }
                    .font(Typeface.detail)
                }
            }
            .paperCard()

            Button {
                runImport(recognised)
            } label: {
                Text("Import \(recognised.count) entries")
            }
            .buttonStyle(InkButtonStyle(kind: .solid))
            .disabled(recognised.isEmpty || accountID == nil)
        }
    }

    private func done(_ outcome: Importer.Outcome) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 44))
                .foregroundStyle(Ink.gain)
            Text("Imported \(outcome.imported) entries")
                .font(Typeface.title)
                .foregroundStyle(Ink.text)
            if outcome.skipped > 0 {
                Text("\(outcome.skipped) duplicates skipped.")
                    .font(Typeface.label)
                    .foregroundStyle(Ink.soft)
            }
            if outcome.newCategories > 0 {
                Text("\(outcome.newCategories) new categories created.")
                    .font(Typeface.label)
                    .foregroundStyle(Ink.soft)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func header(_ column: Int) -> String {
        if plan.hasHeader, let first = table.first, column < first.count, !first[column].isEmpty { return first[column] }
        return String(localized: "Column \(column + 1)")
    }

    private func sample(_ column: Int) -> String {
        let body = table.dropFirst(plan.hasHeader ? 1 : 0).prefix(3)
        return body.compactMap { column < $0.count ? $0[column] : nil }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func roleBinding(_ column: Int) -> Binding<ImportRole> {
        Binding(get: {
            column < plan.roles.count ? plan.roles[column] : .ignore
        }, set: { newRole in
            guard column < plan.roles.count else { return }
            if newRole != .ignore, let existing = plan.roles.firstIndex(of: newRole) { plan.roles[existing] = .ignore }
            plan.roles[column] = newRole
            if newRole == .date {
                let values = table.dropFirst(plan.hasHeader ? 1 : 0).compactMap { column < $0.count ? $0[column] : nil }
                plan.dateFormat = ImportMapper.bestDateFormat(Array(values))
            }
        })
    }

    private func roleTitle(_ role: ImportRole) -> LocalizedStringKey {
        switch role {
        case .ignore: return "Skip"
        case .date: return "Date"
        case .amount: return "Amount (±)"
        case .outflow: return "Money out"
        case .inflow: return "Money in"
        case .kind: return "Type"
        case .category: return "Category"
        case .note: return "Note"
        case .account: return "Account"
        case .currency: return "Currency"
        }
    }

    private func load(_ result: Result<[URL], Error>) {
        failure = nil
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard let text = Importer.readText(from: url) else {
            failure = String(localized: "That file couldn't be read.")
            return
        }
        let parsed = CSVKit.parse(text)
        guard parsed.count >= 1 else {
            failure = String(localized: "No rows found in that file.")
            return
        }
        table = parsed
        plan = ImportMapper.plan(for: parsed)
    }

    private func runImport(_ recognised: [ImportedRow]) {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        outcome = Importer.apply(recognised, defaultAccount: account, keepBalances: keepBalances, skipDuplicates: skipDuplicates, context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
        Upkeep.afterChange(context: context, rates: rates)
        Telemetry.event("csv_import", ["rows": Telemetry.bucket(recognised.count)])
        Haptic.success()
    }
}
