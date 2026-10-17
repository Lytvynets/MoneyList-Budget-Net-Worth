import SwiftUI
import SwiftData

struct HoldingEditor: View {
    let holding: Asset?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moneyPrefs) private var prefs
    @Environment(RateBook.self) private var rates

    @State private var kind: HoldingKind = .stock
    @State private var name = ""
    @State private var ticker = ""
    @State private var quantityText = ""
    @State private var costText = ""
    @State private var valueText = ""
    @State private var currency = "USD"
    @State private var date = Date()
    @State private var autoUpdate = true
    @State private var note = ""
    @State private var checking = false
    @State private var checkMessage: String?

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if holding != nil { return true }
        guard let quantity = AmountField.value(quantityText), quantity > 0, AmountField.value(costText) != nil else { return false }
        if kind.hasLiveQuotes { return !ticker.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    var body: some View {
        EditorChrome(holding == nil ? Text("New investment") : Text("Edit investment"), canSave: canSave, onSave: save) {
            if holding == nil {
                SegmentRail(items: [(HoldingKind.stock, "Stocks"), (HoldingKind.crypto, "Crypto"), (HoldingKind.collectible, "Other")], selection: $kind)
            }

            FieldRow("Name") {
                TextField(kind == .collectible ? "Flat in Lviv, watch, art…" : (kind == .crypto ? "Bitcoin" : "Apple"), text: $name)
                    .font(Typeface.body)
                if kind.hasLiveQuotes {
                    HStack {
                        TextField(kind == .crypto ? "Symbol, e.g. BTC" : "Ticker, e.g. AAPL or VWCE.DE", text: $ticker)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(Typeface.body)
                        Button {
                            Task { await check() }
                        } label: {
                            if checking { ProgressView().controlSize(.small) } else { Text("Check") }
                        }
                        .disabled(ticker.isEmpty || checking)
                    }
                    if let checkMessage {
                        Text(verbatim: checkMessage)
                            .font(Typeface.detail)
                            .foregroundStyle(Ink.soft)
                    }
                    Toggle(isOn: $autoUpdate) { Text("Live price") }
                }
            }
            .paperCard()

            if holding == nil {
                FieldRow("First purchase") {
                    TextField("Quantity (0.5 is fine)", text: $quantityText)
                        .keyboardType(.decimalPad)
                        .font(Typeface.body)
                    HStack {
                        AmountField(title: "Price per unit", text: $costText, currency: currency)
                        CurrencyMenu(code: $currency)
                    }
                    if !kind.hasLiveQuotes {
                        AmountField(title: "Value per unit today", text: $valueText, currency: currency)
                    }
                    DatePicker(selection: $date, in: ...Date(), displayedComponents: .date) { Text("Date") }
                }
                .paperCard()
            } else {
                FieldRow("Currency") {
                    CurrencyMenu(code: $currency)
                }
                .paperCard()
            }

            FieldRow("Note") {
                TextField("Optional", text: $note, axis: .vertical)
                    .font(Typeface.body)
                    .lineLimit(1...4)
            }
            .paperCard()
        }
        .onAppear(perform: load)
    }

    private func load() {
        currency = prefs.home
        guard let holding else { return }
        kind = holding.kind
        name = holding.name
        ticker = holding.ticker ?? ""
        currency = holding.currencyCode
        autoUpdate = holding.autoUpdateEnabled
        note = holding.note ?? ""
    }

    private func check() async {
        checking = true
        defer { checking = false }
        do {
            let price = try await QuoteDesk.price(kind: kind, ticker: ticker, currency: currency, rates: rates)
            checkMessage = String(localized: "Found: \(MoneyFormat.plain(price, code: currency)) per unit")
            if costText.isEmpty { costText = Decimals.editable(Decimals.rounded(price)) }
        } catch {
            checkMessage = error.localizedDescription
        }
    }

    private func save() {
        let trimmedTicker = ticker.trimmingCharacters(in: .whitespaces).uppercased()
        if let holding {
            holding.name = name.trimmingCharacters(in: .whitespaces)
            holding.ticker = kind.hasLiveQuotes && !trimmedTicker.isEmpty ? trimmedTicker : nil
            holding.autoUpdateEnabled = kind.hasLiveQuotes && autoUpdate
            holding.note = note.isEmpty ? nil : note
            if holding.currencyCode != currency, let price = holding.lastFetchedPrice {
                holding.lastFetchedPrice = rates.convert(price, from: holding.currencyCode, to: currency)
            }
            holding.currencyCode = currency
        } else {
            guard let quantity = AmountField.value(quantityText), let cost = AmountField.value(costText) else { return }
            let item = Asset(kind: kind, name: name.trimmingCharacters(in: .whitespaces), ticker: kind.hasLiveQuotes ? trimmedTicker : nil, currencyCode: currency, autoUpdate: kind.hasLiveQuotes && autoUpdate, note: note.isEmpty ? nil : note)
            if !kind.hasLiveQuotes {
                item.lastFetchedPrice = AmountField.value(valueText) ?? cost
                item.lastFetchedAt = Date()
            }
            context.insert(item)
            context.insert(AssetTransaction(asset: item, isBuy: true, quantity: quantity, pricePerUnit: cost, date: date, note: nil))
        }
        try? context.save()
        Telemetry.event("investment_saved", ["is_new": holding == nil, "kind": kind.rawValue, "live_price": kind.hasLiveQuotes && autoUpdate])
        Task {
            await Upkeep.refreshQuotes(context: context, rates: rates, force: true)
            Upkeep.afterChange(context: context, rates: rates)
        }
        Haptic.success()
        dismiss()
    }
}

struct HoldingDetail: View {
    let holding: Asset

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RateBook.self) private var rates
    @State private var editing = false
    @State private var trading = false
    @State private var pricing = false
    @State private var refreshing = false
    @State private var errorText: String?
    @State private var confirmDelete = false

    var body: some View {
        let position = holding.position
        let trades = (holding.transactions ?? []).sorted { $0.date > $1.date }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Kicker(verbatim: [holding.ticker, holding.kind.title].compactMap { $0 }.joined(separator: " · "))
                    MoneyText(value: holding.marketValue, code: holding.currencyCode, size: .large)
                    MoneyText(value: holding.unrealized, code: holding.currencyCode, size: .small, signed: true, tone: holding.unrealized >= 0 ? Ink.gain : Ink.loss)
                    Divider().overlay(Ink.rule)
                    VStack(spacing: 8) {
                        LeaderRow { Text("Quantity") } trailing: { Text(verbatim: MoneyFormat.number(position.quantity, maxFraction: 8)).font(Typeface.smallFigure) }
                        LeaderRow { Text("Average cost") } trailing: { MoneyText(value: position.averageCost, code: holding.currencyCode, size: .tiny) }
                        LeaderRow { Text("Price now") } trailing: { MoneyText(value: holding.markPrice, code: holding.currencyCode, size: .tiny) }
                        if position.realized != 0 {
                            LeaderRow { Text("Realized") } trailing: { MoneyText(value: position.realized, code: holding.currencyCode, size: .tiny, signed: true, tone: position.realized >= 0 ? Ink.gain : Ink.loss) }
                        }
                    }
                    .font(Typeface.label)
                    .foregroundStyle(Ink.soft)

                    if holding.kind.hasLiveQuotes && holding.autoUpdateEnabled {
                        Button {
                            Task { await refresh() }
                        } label: {
                            HStack(spacing: 6) {
                                if refreshing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                                Text(verbatim: holding.lastFetchedAt.map { String(localized: "Updated \($0.formatted(date: .abbreviated, time: .shortened))") } ?? String(localized: "Get price"))
                            }
                            .font(Typeface.detail)
                        }
                        .disabled(refreshing)
                    } else {
                        Button { pricing = true } label: { Label(String(localized: "Update value"), systemImage: "pencil") }
                            .buttonStyle(InkButtonStyle(kind: .quiet, compact: true))
                    }
                    if let errorText {
                        Text(verbatim: errorText).font(Typeface.detail).foregroundStyle(Ink.loss)
                    }
                }
                .paperCard(padding: 18)

                SectionHeading("Buys and sells") {
                    Button { trading = true } label: { Label(String(localized: "Add"), systemImage: "plus").font(Typeface.labelStrong) }
                }
                VStack(spacing: 0) {
                    ForEach(trades) { trade in
                        HStack(spacing: 12) {
                            Image(systemName: trade.isBuy ? "arrow.down.to.line" : "arrow.up.to.line")
                                .foregroundStyle(trade.isBuy ? Ink.gain : Ink.loss)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: (trade.isBuy ? String(localized: "Bought") : String(localized: "Sold")) + " " + MoneyFormat.number(trade.quantity, maxFraction: 8))
                                    .font(Typeface.labelStrong)
                                    .foregroundStyle(Ink.text)
                                Text(verbatim: trade.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(Typeface.detail)
                                    .foregroundStyle(Ink.soft)
                            }
                            Spacer()
                            MoneyText(value: trade.pricePerUnit, code: holding.currencyCode, size: .small)
                        }
                        .padding(.vertical, 8)
                        .contextMenu {
                            Button(role: .destructive) {
                                context.delete(trade)
                                try? context.save()
                                Upkeep.afterChange(context: context, rates: rates)
                            } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }
                        }
                        Divider().overlay(Ink.rule)
                    }
                }
                .paperCard(padding: 14)

                if let note = holding.note, !note.isEmpty {
                    Text(verbatim: note)
                        .font(Typeface.label)
                        .foregroundStyle(Ink.soft)
                        .paperCard()
                }

                Button(role: .destructive) { confirmDelete = true } label: {
                    Text("Delete investment").foregroundStyle(Ink.loss)
                }
                .buttonStyle(InkButtonStyle(kind: .outline))
            }
            .padding(18)
        }
        .paperBackground()
        .navigationTitle(Text(verbatim: holding.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true } }
        }
        .sheet(isPresented: $editing) { HoldingEditor(holding: holding) }
        .sheet(isPresented: $trading) { TradeEditor(holding: holding).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $pricing) { ManualPriceSheet(holding: holding).presentationDetents([.height(300)]) }
        .confirmationDialog(Text("Delete \(holding.name)?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
                try? writer.deleteHolding(holding)
                Upkeep.afterChange(context: context, rates: rates)
                dismiss()
            }
        } message: {
            Text("Its buy and sell history is removed too.")
        }
    }

    private func refresh() async {
        refreshing = true
        defer { refreshing = false }
        do {
            let price = try await QuoteDesk.price(kind: holding.kind, ticker: holding.ticker, currency: holding.currencyCode, rates: rates)
            holding.lastFetchedPrice = price
            holding.lastFetchedAt = Date()
            try? context.save()
            errorText = nil
            Upkeep.afterChange(context: context, rates: rates)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct TradeEditor: View {
    let holding: Asset

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RateBook.self) private var rates

    @State private var isBuy = true
    @State private var quantityText = ""
    @State private var priceText = ""
    @State private var date = Date()

    private var held: Decimal { holding.position.quantity }

    private var canSave: Bool {
        guard let quantity = AmountField.value(quantityText), quantity > 0, AmountField.value(priceText) != nil else { return false }
        return isBuy || quantity <= held
    }

    var body: some View {
        EditorChrome(isBuy ? Text("Record a buy") : Text("Record a sell"), canSave: canSave, onSave: save) {
            SegmentRail(items: [(true, "Buy"), (false, "Sell")], selection: $isBuy)
            FieldRow("Trade") {
                TextField("Quantity", text: $quantityText)
                    .keyboardType(.decimalPad)
                    .font(Typeface.body)
                AmountField(title: "Price per unit", text: $priceText, currency: holding.currencyCode)
                DatePicker(selection: $date, in: ...Date(), displayedComponents: .date) { Text("Date") }
                if !isBuy {
                    Text("You hold \(MoneyFormat.number(held, maxFraction: 8)).")
                        .font(Typeface.detail)
                        .foregroundStyle(Ink.soft)
                }
            }
            .paperCard()
        }
        .onAppear {
            if let price = holding.lastFetchedPrice { priceText = Decimals.editable(Decimals.rounded(price)) }
        }
    }

    private func save() {
        guard let quantity = AmountField.value(quantityText), let price = AmountField.value(priceText) else { return }
        context.insert(AssetTransaction(asset: holding, isBuy: isBuy, quantity: quantity, pricePerUnit: price, date: date, note: nil))
        try? context.save()
        Upkeep.afterChange(context: context, rates: rates)
        Haptic.success()
        dismiss()
    }
}

struct ManualPriceSheet: View {
    let holding: Asset

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RateBook.self) private var rates
    @State private var text = ""

    var body: some View {
        EditorChrome(Text("Value per unit"), canSave: (AmountField.value(text) ?? 0) > 0, onSave: save) {
            AmountField(title: "0", text: $text, currency: holding.currencyCode)
                .paperCard()
            Text("No market feed for this one — update the value whenever it changes.")
                .font(Typeface.detail)
                .foregroundStyle(Ink.soft)
        }
        .onAppear {
            if let price = holding.lastFetchedPrice { text = Decimals.editable(price) }
        }
    }

    private func save() {
        guard let value = AmountField.value(text), value > 0 else { return }
        holding.lastFetchedPrice = value
        holding.lastFetchedAt = Date()
        try? context.save()
        Upkeep.afterChange(context: context, rates: rates)
        dismiss()
    }
}
