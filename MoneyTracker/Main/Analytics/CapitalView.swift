

import SwiftUI
import SwiftData

struct CapitalView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Query private var assets: [Asset]
    @Query private var allLedgerEntries: [AssetTransaction]
    @Query private var profiles: [UserProfile]
    @EnvironmentObject private var exchangeService: CurrencyExchangeService
    @State private var showAddAsset = false
    @State private var showPaywall = false

    private var currency: String { profiles.first?.defaultCurrencyCode ?? "USD" }

    private func converted(_ value: Decimal, from code: String) -> Decimal {
        exchangeService.convert(value, from: code, to: currency)
    }

    private func ledger(for asset: Asset) -> [AssetTransaction] {
        allLedgerEntries.filter { $0.asset?.id == asset.id }
    }

    private func currentValue(of asset: Asset) -> Decimal {
        asset.currentValue(in: ledger(for: asset))
    }

    private var showOnOverviewBinding: Binding<Bool> {
        Binding(
            get: { profiles.first?.showCapitalOnOverview ?? true },
            set: { newValue in
                profiles.first?.showCapitalOnOverview = newValue
                try? modelContext.save()
            }
        )
    }

    var netWorth: Decimal {
        assets.reduce(0) { $0 + converted(currentValue(of: $1), from: $1.currencyCode) }
    }

    struct AssetGroup: Identifiable {
        let type: AssetType
        let items: [Asset]
        let total: Decimal
        var id: String { type.rawValue }
    }

    private var groups: [AssetGroup] {
        AssetType.allCases.compactMap { type in
            let items = assets.filter { $0.type == type }
            guard !items.isEmpty else { return nil }
            let total = items.reduce(Decimal(0)) { $0 + converted(currentValue(of: $1), from: $1.currencyCode) }
            return AssetGroup(type: type, items: items, total: total)
        }
    }

    private func tapAddAsset() {
        if purchaseManager.canAddAsset(currentCount: assets.count) {
            showAddAsset = true
        } else {
            showPaywall = true
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if assets.isEmpty {
                    EmptyStateView(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Track your net worth",
                        subtitle: "Add stocks, crypto, or anything else you own to see your total wealth grow over time.",
                        buttonTitle: "Add asset"
                    ) { tapAddAsset() }
                } else {
                    VStack(spacing: 4) {
                        Text("Total capital (Net Worth)").font(FinoraFont.caption).foregroundStyle(FinoraColor.textSecondary)
                        LiveNumberText(value: netWorth, currencyCode: currency, font: FinoraFont.amount(34, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Toggle(isOn: showOnOverviewBinding) {
                        Text("Show \"Investments\" on Overview")
                            .font(FinoraFont.caption)
                            .foregroundStyle(FinoraColor.textSecondary)
                    }
                    .tint(FinoraColor.verdant)

                    ForEach(groups) { group in
                        assetGroupCard(group)
                    }

                    PrimaryButton(title: "Add asset", icon: "plus", gradient: true) { tapAddAsset() }

                    if !purchaseManager.isPro {
                        Text("Free plan: up to \(FreeLimit.assets) asset. Pro adds unlimited assets.")
                            .font(FinoraFont.micro)
                            .foregroundStyle(FinoraColor.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, FinoraMetric.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .tabBarSafeArea()
        .background(FinoraColor.background)
        .sheet(isPresented: $showAddAsset) { AddAssetView() }
        .fullScreenCover(isPresented: $showPaywall) { PaywallView(onDismiss: { showPaywall = false }) }
    }

    private func assetGroupCard(_ group: AssetGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: group.type.iconName).foregroundStyle(FinoraColor.brassGold)
                Text(group.type.displayName).font(FinoraFont.bodyMedium).foregroundStyle(FinoraColor.textPrimary)
                Spacer()
                Text(percentOfNetWorth(group.total)).font(FinoraFont.caption).foregroundStyle(FinoraColor.textSecondary)
            }
            LiveNumberText(value: group.total, currencyCode: currency, font: FinoraFont.cardAmount)

            VStack(spacing: 4) {
                ForEach(group.items) { asset in
                    NavigationLink { AssetDetailView(asset: asset) } label: {
                        assetRow(asset)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .finoraCard()
    }

    private func assetRow(_ asset: Asset) -> some View {
        let assetLedger = ledger(for: asset)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name).font(FinoraFont.body).foregroundStyle(FinoraColor.textPrimary)
                if let ticker = asset.ticker {
                    Text(ticker).font(FinoraFont.micro).foregroundStyle(FinoraColor.textTertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(converted(currentValue(of: asset), from: asset.currencyCode).formatted(.currency(code: currency)))
                    .font(FinoraFont.caption)
                    .foregroundStyle(FinoraColor.textPrimary)
                if asset.quantity(in: assetLedger) > 0 {
                    let gain = converted(asset.unrealizedGainLoss(in: assetLedger), from: asset.currencyCode)
                    Text("\(gain >= 0 ? "+" : "")\(gain.formatted(.currency(code: currency)))")
                        .font(FinoraFont.micro)
                        .foregroundStyle(gain >= 0 ? FinoraColor.verdant : FinoraColor.coral)
                }
            }
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(FinoraColor.textTertiary)
        }
        .padding(.vertical, 4)
    }

    private func percentOfNetWorth(_ value: Decimal) -> String {
        guard netWorth > 0 else { return "0%" }
        let ratio = (value / netWorth as NSDecimalNumber).doubleValue
        return ratio.formatted(.percent.precision(.fractionLength(1)))
    }
}


struct AddAssetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var type: AssetType = .stock
    @State private var name = ""
    @State private var ticker = ""
    @State private var quantityText = ""
    @State private var priceText = ""
    @State private var currentPriceText = ""
    @State private var currencyCode = "USD"
    @State private var note = ""
    @State private var autoUpdateEnabled = true
    @State private var purchaseDate = Date()

    private var isAutoUpdateType: Bool { type.supportsAutoUpdate }

    private var namePlaceholder: String {
        switch type {
        case .stock: "Asset name (e.g. Apple Inc.)"
        case .crypto: "Asset name (e.g. Ethereum)"
        case .collectible: "Name (e.g. Karambit Fade, Downtown Apartment)"
        }
    }

    private var canSave: Bool {
        guard !name.isEmpty, Decimal(string: quantityText) != nil, Decimal(string: priceText) != nil else { return false }
        if isAutoUpdateType { return !ticker.isEmpty }
        return Decimal(string: currentPriceText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("1. Asset type") {
                    Picker("Type", selection: $type) {
                        ForEach(AssetType.allCases) { candidate in
                            Text(candidate.displayName).tag(candidate)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("2. Details") {
                    TextField(namePlaceholder, text: $name)

                    if isAutoUpdateType {
                        TextField(type == .stock ? "Ticker (e.g. AAPL)" : "Symbol (e.g. BTC)", text: $ticker)
                            .autocapitalization(.allCharacters)
                    }

                    TextField("Quantity (fractions OK, e.g. 0.5)", text: $quantityText)
                        .keyboardType(.decimalPad)
                        .onChange(of: quantityText) { _, newValue in
                            let sanitized = NumericInput.sanitize(newValue)
                            if sanitized != newValue { quantityText = sanitized }
                        }
                    TextField("Price paid per unit", text: $priceText)
                        .keyboardType(.decimalPad)
                        .onChange(of: priceText) { _, newValue in
                            let sanitized = NumericInput.sanitize(newValue)
                            if sanitized != newValue { priceText = sanitized }
                        }

                    if !isAutoUpdateType {
                        TextField("Current price per unit", text: $currentPriceText)
                            .keyboardType(.decimalPad)
                            .onChange(of: currentPriceText) { _, newValue in
                                let sanitized = NumericInput.sanitize(newValue)
                                if sanitized != newValue { currentPriceText = sanitized }
                            }
                    }

                    DatePicker("Purchase date", selection: $purchaseDate, displayedComponents: .date)

                    if isAutoUpdateType {
                        Toggle("Auto-update price", isOn: $autoUpdateEnabled)
                    }

                    Picker("Currency", selection: $currencyCode) {
                        ForEach(CurrencyCode.common, id: \.self) { Text($0) }
                    }
                }

                Section("Note (optional)") {
                    TextField("Add a note...", text: $note, axis: .vertical)
                }

                Text(isAutoUpdateType
                    ? "This records the first \"Buy\" — add more buys or sells later from the asset's own screen, and the average price updates automatically."
                    : "This records the first \"Buy\" at what you paid, plus today's value. There's no market feed for this kind of asset, so update that value yourself any time it changes — add more buys or sells later from the asset's own screen.")
                    .font(FinoraFont.micro)
                    .foregroundStyle(FinoraColor.textSecondary)
            }
            .navigationTitle("Add Asset")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .onAppear {
                if let defaultCode = profiles.first?.defaultCurrencyCode { currencyCode = defaultCode }
            }
        }
    }

    private func save() {
        guard let quantity = Decimal(string: quantityText), let price = Decimal(string: priceText) else { return }

        let asset = Asset(
            type: type,
            name: name,
            ticker: isAutoUpdateType ? ticker.uppercased() : nil,
            currencyCode: currencyCode,
            autoUpdateEnabled: isAutoUpdateType && autoUpdateEnabled,
            note: note.isEmpty ? nil : note
        )
        if !isAutoUpdateType, let currentPrice = Decimal(string: currentPriceText) {
            asset.lastFetchedPrice = currentPrice
            asset.lastFetchedAt = .now
        }
        modelContext.insert(asset)

        let entry = AssetTransaction(asset: asset, kind: .buy, quantity: quantity, pricePerUnit: price, date: purchaseDate)
        modelContext.insert(entry)

        try? modelContext.save()
        dismiss()
    }
}


struct AssetDetailView: View {
    @Bindable var asset: Asset
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allLedgerEntries: [AssetTransaction]

    @State private var showAddTransaction = false
    @State private var showSetPrice = false
    @State private var showDeleteConfirmation = false
    @State private var isRefreshing = false
    @State private var refreshErrorMessage: String?

    private var currency: String { asset.currencyCode }
    private var isAutoUpdateType: Bool { asset.type.supportsAutoUpdate }

    private var ledger: [AssetTransaction] {
        allLedgerEntries.filter { $0.asset?.id == asset.id }
    }

    private var currentValue: Decimal { asset.currentValue(in: ledger) }
    private var quantity: Decimal { asset.quantity(in: ledger) }
    private var averageCost: Decimal { asset.averageCostPerUnit(in: ledger) }
    private var currentPrice: Decimal { asset.currentPricePerUnit(in: ledger) }
    private var unrealizedGain: Decimal { asset.unrealizedGainLoss(in: ledger) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                ledgerSection
                if let note = asset.note, !note.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Note").font(FinoraFont.caption).foregroundStyle(FinoraColor.textSecondary)
                        Text(note).font(FinoraFont.body).foregroundStyle(FinoraColor.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, FinoraMetric.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .tabBarSafeArea()
        .background(FinoraColor.background)
        .navigationTitle(asset.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { showDeleteConfirmation = true } label: {
                        Label("Delete Asset", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showAddTransaction) { AddAssetTransactionView(asset: asset) }
        .sheet(isPresented: $showSetPrice) { SetManualPriceView(asset: asset) }
        .confirmationDialog(
            "Delete \(asset.name)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Asset", role: .destructive) { deleteAsset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the asset and all its buy/sell history — not just this record showing 0. This can't be undone.")
        }
        .alert("Couldn't refresh price", isPresented: Binding(
            get: { refreshErrorMessage != nil },
            set: { if !$0 { refreshErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { refreshErrorMessage = nil }
        } message: {
            Text(refreshErrorMessage ?? "")
        }
    }

  
    private func deleteAsset() {
        for entry in ledger {
            modelContext.delete(entry)
        }
        modelContext.delete(asset)
        try? modelContext.save()
        dismiss()
    }

    private var header: some View {
        VStack(spacing: 14) {
            if let ticker = asset.ticker {
                Text(ticker).font(FinoraFont.caption).foregroundStyle(FinoraColor.textSecondary)
            }
            LiveNumberText(value: currentValue, currencyCode: currency, font: FinoraFont.amount(30, weight: .bold))

            HStack(spacing: 0) {
                statColumn(title: "Quantity", value: "\(quantity)")
                statColumn(title: "Avg. cost", value: averageCost.formatted(.currency(code: currency)))
                statColumn(title: "Price now", value: currentPrice.formatted(.currency(code: currency)))
            }

            HStack(spacing: 6) {
                Image(systemName: unrealizedGain >= 0 ? "arrow.up.right" : "arrow.down.right")
                Text("\(unrealizedGain >= 0 ? "+" : "")\(unrealizedGain.formatted(.currency(code: currency))) unrealized")
            }
            .font(FinoraFont.bodyMedium)
            .foregroundStyle(unrealizedGain >= 0 ? FinoraColor.verdant : FinoraColor.coral)

            if isAutoUpdateType {
                if asset.autoUpdateEnabled {
                    Button {
                        Task { await refresh() }
                    } label: {
                        HStack(spacing: 6) {
                            if isRefreshing {
                                ProgressView().tint(FinoraColor.verdant)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(asset.lastFetchedAt.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Refresh price")
                        }
                        .font(FinoraFont.caption)
                        .foregroundStyle(FinoraColor.verdant)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                }
            } else {
                VStack(spacing: 8) {
                    PrimaryButton(title: "Update Price", icon: "pencil", gradient: true) { showSetPrice = true }
                    Text("No live price for this kind of asset — update it yourself any time it changes.")
                        .font(FinoraFont.micro)
                        .foregroundStyle(FinoraColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .finoraCard()
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(FinoraFont.micro).foregroundStyle(FinoraColor.textSecondary)
            Text(value).font(FinoraFont.caption).foregroundStyle(FinoraColor.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    private var sortedLedgerDescending: [AssetTransaction] {
        ledger.sorted { $0.date > $1.date }
    }

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transactions").font(FinoraFont.bodyMedium).foregroundStyle(FinoraColor.textPrimary)
                Spacer()
                Button { showAddTransaction = true } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(FinoraColor.verdant)
                }
                .buttonStyle(.plain)
            }

            if ledger.isEmpty {
                EmptyStateView(
                    icon: "list.bullet.rectangle",
                    title: "No transactions yet",
                    subtitle: "Record a buy or sell to start tracking this holding.",
                    buttonTitle: "Add transaction"
                ) { showAddTransaction = true }
            } else {
                VStack(spacing: 0) {
                    ForEach(sortedLedgerDescending) { entry in
                        transactionRow(entry)
                        if entry.id != sortedLedgerDescending.last?.id {
                            Divider().overlay(FinoraColor.divider)
                        }
                    }
                }
                .padding(16)
                .finoraCard()
            }
        }
    }

    private func transactionRow(_ entry: AssetTransaction) -> some View {
        HStack {
            ZStack {
                Circle().fill((entry.kind == .buy ? FinoraColor.verdant : FinoraColor.coral).opacity(0.15))
                Image(systemName: entry.kind == .buy ? "arrow.down" : "arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(entry.kind == .buy ? FinoraColor.verdant : FinoraColor.coral)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.kind.rawValue) \(entry.quantity) @ \(entry.pricePerUnit.formatted(.currency(code: currency)))")
                    .font(FinoraFont.bodyMedium)
                    .foregroundStyle(FinoraColor.textPrimary)
                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    .font(FinoraFont.micro)
                    .foregroundStyle(FinoraColor.textSecondary)
            }
            Spacer()
            Text(entry.total.formatted(.currency(code: currency)))
                .font(FinoraFont.caption)
                .foregroundStyle(FinoraColor.textSecondary)

            Menu {
                Button(role: .destructive) { delete(entry) } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(FinoraColor.textTertiary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 8)
    }

    private func delete(_ entry: AssetTransaction) {
        modelContext.delete(entry)
        try? modelContext.save()
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let price = try await PriceSyncService.fetchPrice(for: asset)
            asset.lastFetchedPrice = price
            asset.lastFetchedAt = .now
            try? modelContext.save()
        } catch {
            refreshErrorMessage = error.localizedDescription
        }
    }
}


struct AddAssetTransactionView: View {
    @Bindable var asset: Asset
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allLedgerEntries: [AssetTransaction]

    @State private var kind: AssetTransaction.Kind = .buy
    @State private var quantityText = ""
    @State private var priceText = ""
    @State private var date = Date()
    @State private var note = ""

    private var currentQuantity: Decimal {
        asset.quantity(in: allLedgerEntries.filter { $0.asset?.id == asset.id })
    }

    private var canSave: Bool {
        guard let quantity = Decimal(string: quantityText), quantity > 0, Decimal(string: priceText) != nil else { return false }
        if kind == .sell { return quantity <= currentQuantity }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(AssetTransaction.Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    TextField("Quantity (fractions OK, e.g. 0.1)", text: $quantityText)
                        .keyboardType(.decimalPad)
                        .onChange(of: quantityText) { _, newValue in
                            let sanitized = NumericInput.sanitize(newValue)
                            if sanitized != newValue { quantityText = sanitized }
                        }
                    TextField("Price per unit", text: $priceText)
                        .keyboardType(.decimalPad)
                        .onChange(of: priceText) { _, newValue in
                            let sanitized = NumericInput.sanitize(newValue)
                            if sanitized != newValue { priceText = sanitized }
                        }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                } footer: {
                    if kind == .sell {
                        Text("You currently hold \(currentQuantity) \(asset.ticker ?? "").")
                    }
                }
                Section("Note (optional)") {
                    TextField("Add a note...", text: $note, axis: .vertical)
                }
            }
            .navigationTitle(kind == .buy ? "Record Buy" : "Record Sell")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard let quantity = Decimal(string: quantityText), let price = Decimal(string: priceText) else { return }
        let entry = AssetTransaction(asset: asset, kind: kind, quantity: quantity, pricePerUnit: price, date: date, note: note.isEmpty ? nil : note)
        modelContext.insert(entry)
        try? modelContext.save()
        dismiss()
    }
}


struct SetManualPriceView: View {
    @Bindable var asset: Asset
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var priceText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("0.00", text: $priceText)
                        .keyboardType(.decimalPad)
                        .onChange(of: priceText) { _, newValue in
                            let sanitized = NumericInput.sanitize(newValue)
                            if sanitized != newValue { priceText = sanitized }
                        }
                } header: {
                    Text("Current price per unit")
                } footer: {
                    Text("There's no market feed for this kind of asset — update this yourself whenever the value changes.")
                }
            }
            .navigationTitle("Update Price")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        asset.lastFetchedPrice = Decimal(string: priceText)
                        asset.lastFetchedAt = .now
                        try? modelContext.save()
                        dismiss()
                    }.disabled(Decimal(string: priceText) == nil)
                }
            }
            .onAppear { priceText = asset.lastFetchedPrice.map { "\($0)" } ?? "" }
        }
    }
}

#Preview {
    NavigationStack { CapitalView() }
        .modelContainer(for: [Asset.self, AssetTransaction.self, UserProfile.self], inMemory: true)
        .environmentObject(CurrencyExchangeService())
        .environmentObject(PurchaseManager())
}
