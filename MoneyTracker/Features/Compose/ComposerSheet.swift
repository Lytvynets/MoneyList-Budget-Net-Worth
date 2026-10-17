import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Full entry form with a calculator keypad, categories, accounts, date,
/// note, receipt photo and repeat schedule.
struct ComposerSheet: View {
    let request: ComposerRequest

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moneyPrefs) private var prefs
    @Environment(\.inkAccent) private var accent
    @Environment(RateBook.self) private var rates
    @Environment(ProPass.self) private var pro
    @Environment(AdPacer.self) private var ads
    @Environment(ToastCenter.self) private var toasts
    @Environment(Router.self) private var router

    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]
    @Query private var accounts: [Account]
    @Query(sort: \Transaction.date, order: .reverse) private var entries: [Transaction]

    @State private var kind: EntryKind = .expense
    @State private var expression = ""
    @State private var inputCurrency = "USD"
    @State private var accountID: UUID?
    @State private var toAccountID: UUID?
    @State private var receivedText = ""
    @State private var receivedTouched = false
    @State private var categoryID: UUID?
    @State private var note = ""
    @State private var date = Date()
    @State private var cadence: Cadence?
    @State private var photo: Data?
    @State private var photoChanged = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var receiptHint: ReceiptReader.Result?
    @State private var keypadVisible = true
    @State private var showNewCategory = false
    @State private var loaded = false
    @FocusState private var noteFocused: Bool

    private var editing: Transaction? { request.editing }

    private var liveAccounts: [Account] {
        accounts.filter { !$0.isArchived || $0.id == editing?.account?.id }
            .sorted { ($0.sortIndex ?? 0, $0.createdAt) < ($1.sortIndex ?? 0, $1.createdAt) }
    }

    private var account: Account? { liveAccounts.first { $0.id == accountID } }
    private var target: Account? { liveAccounts.first { $0.id == toAccountID } }
    private var amount: Decimal? { AmountReader.evaluate(expression.replacingOccurrences(of: "−", with: "-")) }

    private var isCrossCurrency: Bool {
        guard kind == .transfer, let account, let target else { return false }
        return account.currencyCode != target.currencyCode
    }

    private var canSave: Bool {
        guard let amount, amount > 0, account != nil else { return false }
        if kind == .transfer { return target != nil && target?.id != account?.id }
        return true
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        SegmentRail(items: [(EntryKind.expense, "Spent"), (EntryKind.income, "Received"), (EntryKind.transfer, "Moved")], selection: $kind)
                        amountBlock
                        if kind == .transfer {
                            transferBlock
                        } else {
                            categoryBlock
                            accountBlock
                        }
                        dateBlock
                        noteBlock
                        extrasBlock
                    }
                    .padding(18)
                }
                .scrollDismissesKeyboard(.interactively)

                if keypadVisible && !noteFocused {
                    CalcKeypad(expression: $expression) {
                        if let amount, expression.dropFirst().contains(where: { "+−×÷".contains($0) }) {
                            expression = Decimals.editable(Decimals.rounded(amount))
                        } else {
                            withAnimation(.snappy) { keypadVisible = false }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(Ink.paper)
                    .overlay(alignment: .top) { Rectangle().fill(Ink.rule).frame(height: 0.8) }
                    .transition(.move(edge: .bottom))
                }
            }
            .paperBackground()
            .trackScreen(editing == nil ? "composer" : "composer_edit")
            .navigationTitle(editing == nil ? Text("New entry") : Text("Edit entry"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
            .onChange(of: kind) { _, newKind in
                if let current = categories.first(where: { $0.id == categoryID }), current.isIncome != (newKind == .income) {
                    categoryID = nil
                }
                if newKind == .transfer, toAccountID == nil {
                    toAccountID = liveAccounts.first { $0.id != accountID }?.id
                }
            }
            .onChange(of: accountID) { old, _ in
                // The first assignment comes from `load()`; only follow later picks.
                if old != nil, kind != .transfer, let account { inputCurrency = account.currencyCode }
                syncReceived()
            }
            .onChange(of: toAccountID) { _, _ in syncReceived() }
            .onChange(of: expression) { _, _ in syncReceived() }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    await attach(data)
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraCapture { image in
                    Task {
                        if let data = PhotoShrinker.jpeg(from: image) { await attach(data, image: image) }
                    }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showNewCategory) {
                CategoryEditor(category: nil, isIncome: kind == .income) { created in
                    categoryID = created.id
                }
            }
            .paywallCover(.composer)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(amount != nil && editing == nil)
    }

    // MARK: Blocks

    private var amountBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button {
                    noteFocused = false
                    withAnimation(.snappy) { keypadVisible = true }
                } label: {
                    Text(verbatim: displayExpression)
                        .font(Typeface.figure(48))
                        .monospacedDigit()
                        .foregroundStyle(expression.isEmpty ? Ink.faint : (kind == .income ? Ink.gain : Ink.text))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .highlighter(!expression.isEmpty && keypadVisible)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Amount"))
                .accessibilityValue(Text(verbatim: displayExpression))

                if kind == .transfer {
                    Text(verbatim: account?.currencyCode ?? prefs.home)
                        .font(Typeface.labelStrong)
                        .foregroundStyle(Ink.soft)
                } else {
                    CurrencyMenu(code: $inputCurrency)
                }
            }
            if let amount, kind != .transfer, let account, inputCurrency != account.currencyCode {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11))
                    MoneyText(value: rates.convert(amount, from: inputCurrency, to: account.currencyCode), code: account.currencyCode, size: .tiny, tone: Ink.soft)
                    Text("goes to \(account.name)")
                }
                .font(Typeface.detail)
                .foregroundStyle(Ink.soft)
            }
            if let hint = receiptHint, let found = hint.amount, found != amount {
                Button {
                    expression = Decimals.editable(found)
                    if note.isEmpty, let merchant = hint.merchant { note = merchant }
                    receiptHint = nil
                } label: {
                    Chip(verbatim: String(localized: "Use \(MoneyFormat.plain(found, code: inputCurrency)) from the receipt"), symbol: "doc.text.viewfinder", selected: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var displayExpression: String {
        guard !expression.isEmpty else { return MoneyFormat.symbol(for: kind == .transfer ? (account?.currencyCode ?? prefs.home) : inputCurrency) + "0" }
        let mark = Locale.current.decimalSeparator ?? "."
        return expression.replacingOccurrences(of: ".", with: mark)
    }

    private var categoryBlock: some View {
        let pool = categories.filter { $0.visible && $0.isIncome == (kind == .income) }
        let ordered = rankedCategories(pool)
        return VStack(alignment: .leading, spacing: 10) {
            Kicker("Category")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                ForEach(ordered) { category in
                    Button {
                        Haptic.tap()
                        categoryID = category.id
                    } label: {
                        VStack(spacing: 6) {
                            Glyph(symbol: category.iconName, hex: category.colorHex, size: 44)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(categoryID == category.id ? Color(hexString: category.colorHex) : Color.clear, lineWidth: 2)
                                        .padding(-3)
                                )
                            Text(verbatim: category.name)
                                .font(.system(size: 11, weight: categoryID == category.id ? .semibold : .regular))
                                .foregroundStyle(categoryID == category.id ? Ink.text : Ink.soft)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    let custom = categories.filter(\.isCustom).count
                    if pro.allows(customCategories: custom) {
                        showNewCategory = true
                    } else {
                        router.showPaywall = true
                    }
                } label: {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Ink.ruleStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: 44, height: 44)
                            .overlay(Image(systemName: "plus").foregroundStyle(Ink.soft))
                        Text("New")
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.soft)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Most used categories first (last 200 entries), then the saved order.
    private func rankedCategories(_ pool: [TransactionCategory]) -> [TransactionCategory] {
        var counts: [UUID: Int] = [:]
        for entry in entries.prefix(200) {
            if let id = entry.category?.id { counts[id, default: 0] += 1 }
        }
        return pool.sorted { lhs, rhs in
            let a = counts[lhs.id] ?? 0
            let b = counts[rhs.id] ?? 0
            if a != b { return a > b }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    private var accountBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(kind == .income ? "Into" : "From")
            accountChips(selection: $accountID, excluding: nil)
        }
    }

    private var transferBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Kicker("From")
                accountChips(selection: $accountID, excluding: nil)
            }
            VStack(alignment: .leading, spacing: 10) {
                Kicker("To")
                accountChips(selection: $toAccountID, excluding: accountID)
            }
            if isCrossCurrency, let target {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker("Arrives as")
                    AmountField(title: "0", text: Binding(get: { receivedText }, set: { receivedText = $0; receivedTouched = true }), currency: target.currencyCode)
                    if let account, let rate = rates.rate(from: account.currencyCode, to: target.currencyCode) {
                        Text(verbatim: "1 \(account.currencyCode) ≈ \(MoneyFormat.number(Decimals.rounded(rate, scale: 4), maxFraction: 4)) \(target.currencyCode)")
                            .font(Typeface.detail)
                            .foregroundStyle(Ink.faint)
                    }
                }
                .paperCard(padding: 14)
            }
        }
    }

    private func accountChips(selection: Binding<UUID?>, excluding: UUID?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(liveAccounts.filter { $0.id != excluding }) { item in
                    Button {
                        Haptic.tap()
                        selection.wrappedValue = item.id
                    } label: {
                        Chip(verbatim: item.name, symbol: item.displaySymbol, selected: selection.wrappedValue == item.id, tint: Color(hexString: item.colorHex))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var dateBlock: some View {
        let calendar = Calendar.current
        return VStack(alignment: .leading, spacing: 10) {
            Kicker("When")
            HStack(spacing: 8) {
                Button {
                    date = merge(day: Date())
                } label: {
                    Chip("Today", selected: calendar.isDateInToday(date))
                }
                .buttonStyle(.plain)
                Button {
                    date = merge(day: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date())
                } label: {
                    Chip("Yesterday", selected: calendar.isDateInYesterday(date))
                }
                .buttonStyle(.plain)
                DatePicker(selection: $date, displayedComponents: [.date, .hourAndMinute]) {
                    Text("Date")
                }
                .labelsHidden()
            }
        }
    }

    private var noteBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker("Note")
            TextField("Where, what, who with…", text: $note, axis: .vertical)
                .font(Typeface.body)
                .lineLimit(1...3)
                .focused($noteFocused)
                .padding(12)
                .background(Ink.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Ink.rule))
                .onChange(of: noteFocused) { _, focused in
                    if focused { withAnimation(.snappy) { keypadVisible = false } }
                }
        }
    }

    private var extrasBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker("Extras")
            HStack(spacing: 10) {
                if pro.isPro {
                    Menu {
                        Button {
                            showCamera = true
                        } label: {
                            Label(String(localized: "Take a photo"), systemImage: "camera")
                        }
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    } label: {
                        Chip(photo == nil ? "Receipt" : "Receipt added", symbol: photo == nil ? "camera" : "checkmark", selected: photo != nil)
                    } primaryAction: {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
                    }
                    let libraryChip = Chip("From photos", symbol: "photo")
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        libraryChip
                    }
                    if photo != nil {
                        Button {
                            photo = nil
                            photoChanged = true
                            receiptHint = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Ink.faint)
                        }
                        .accessibilityLabel(Text("Remove receipt"))
                    }
                } else {
                    Button {
                        router.showPaywall = true
                    } label: {
                        Chip("Scan receipt", symbol: "lock.fill", dashed: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            if editing == nil {
                Menu {
                    Button {
                        cadence = nil
                    } label: {
                        Text("Doesn't repeat")
                    }
                    ForEach(CadenceText.presets, id: \.self) { item in
                        Button(CadenceText.title(item)) { cadence = item }
                    }
                } label: {
                    Chip(verbatim: cadence.map(CadenceText.title) ?? String(localized: "Doesn't repeat"), symbol: "repeat", selected: cadence != nil)
                }
            }
        }
    }

    // MARK: Logic

    private func merge(day: Date) -> Date {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute], from: Date())
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }

    private func syncReceived() {
        guard isCrossCurrency, !receivedTouched, let amount, let account, let target else { return }
        receivedText = Decimals.editable(Decimals.rounded(rates.convert(amount, from: account.currencyCode, to: target.currencyCode)))
    }

    private func attach(_ data: Data, image: UIImage? = nil) async {
        let shrunk = PhotoShrinker.jpeg(from: data) ?? data
        photo = shrunk
        photoChanged = true
        guard let picture = image ?? UIImage(data: shrunk) else { return }
        let result = await ReceiptReader.read(picture)
        Telemetry.event("receipt_scan", ["found_total": result.amount != nil])
        if let found = result.amount {
            if expression.isEmpty {
                expression = Decimals.editable(found)
                if note.isEmpty, let merchant = result.merchant { note = merchant }
            } else {
                receiptHint = result
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        kind = request.kind
        let fallbackAccount = prefs.defaultAccountID.flatMap { id in liveAccounts.first { $0.id == id } }
            ?? liveAccounts.first(where: { $0.isSpendable })
            ?? liveAccounts.first

        if let entry = editing {
            kind = entry.kind
            accountID = entry.account?.id
            toAccountID = entry.toAccount?.id
            categoryID = entry.category?.id
            note = entry.note ?? ""
            date = entry.date
            if let original = entry.originalAmount, let code = entry.originalCurrency {
                expression = Decimals.editable(original)
                inputCurrency = code
            } else {
                expression = Decimals.editable(entry.amount)
                inputCurrency = entry.account?.currencyCode ?? prefs.home
            }
            if let received = entry.toAmount {
                receivedText = Decimals.editable(received)
                receivedTouched = true
            }
            let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
            photo = writer.receipt(for: entry)
            keypadVisible = false
            return
        }

        accountID = request.accountID ?? fallbackAccount?.id
        inputCurrency = account?.currencyCode ?? prefs.home
        categoryID = request.categoryID
        if let line = request.prefill {
            if let amount = line.amount { expression = Decimals.editable(amount) }
            if let code = line.currencyCode { inputCurrency = code }
            note = line.note
            if let lineDate = line.date { date = lineDate }
            cadence = line.cadence
        }
        if kind == .transfer {
            toAccountID = liveAccounts.first { $0.id != accountID }?.id
        }
    }

    private func save() {
        guard let amount, amount > 0 else { return }
        var draft = EntryDraft()
        draft.kind = kind
        draft.amount = amount
        draft.inputCurrency = kind == .transfer ? (account?.currencyCode ?? prefs.home) : inputCurrency
        draft.accountID = accountID
        draft.toAccountID = kind == .transfer ? toAccountID : nil
        draft.receivedAmount = isCrossCurrency ? AmountField.value(receivedText) : nil
        draft.categoryID = kind == .transfer ? nil : categoryID
        draft.note = note
        draft.date = date
        draft.repeatCadence = editing == nil ? cadence : nil
        draft.attachment = photoChanged ? photo : nil
        draft.removeAttachment = photoChanged && photo == nil

        let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
        do {
            let entry = try writer.save(draft, editing: editing)
            Haptic.success()
            Telemetry.event(editing == nil ? "entry_saved" : "entry_edited", [
                "kind": kind.rawValue,
                "source": "form",
                "repeats": draft.repeatCadence != nil,
                "foreign_currency": kind != .transfer && inputCurrency != (account?.currencyCode ?? inputCurrency),
                "receipt": photo != nil
            ])
            if editing == nil {
                AfterSave.run(entry: entry, context: context, rates: rates, pro: pro, ads: ads)
            } else {
                Upkeep.afterChange(context: context, rates: rates)
            }
            dismiss()
        } catch {
            toasts.show(error.localizedDescription)
        }
    }
}

/// System camera for receipt photos.
struct CameraCapture: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        init(parent: CameraCapture) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
