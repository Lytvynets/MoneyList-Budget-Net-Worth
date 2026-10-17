import SwiftUI
import SwiftData
import Foundation

struct CategoriesManager: View {
    @Environment(\.modelContext) private var context
    @Environment(ProPass.self) private var pro
    @Environment(Router.self) private var router
    @Environment(RateBook.self) private var rates

    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]

    @State private var showIncome = false
    @State private var editing: CategoryTarget?
    @State private var deleting: TransactionCategory?

    struct CategoryTarget: Identifiable { let id = UUID(); var category: TransactionCategory? }

    private var shown: [TransactionCategory] { categories.filter { $0.isIncome == showIncome } }

    var body: some View {
        List {
            Section {
                SegmentRail(items: [(false, "Spending"), (true, "Income")], selection: $showIncome)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            }
            Section {
                ForEach(shown) { category in
                    HStack(spacing: 12) {
                        Glyph(symbol: category.iconName, hex: category.colorHex, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: category.name)
                                .font(Typeface.body)
                                .foregroundStyle(category.visible ? Ink.text : Ink.faint)
                            Text(verbatim: usage(category))
                                .font(Typeface.detail)
                                .foregroundStyle(Ink.soft)
                        }
                        Spacer()
                        if !category.visible {
                            Image(systemName: "eye.slash").foregroundStyle(Ink.faint)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = CategoryTarget(category: category) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { deleting = category } label: {
                            Label(String(localized: "Delete"), systemImage: "trash")
                        }
                        Button {
                            let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
                            try? writer.setHidden(category, category.visible)
                        } label: {
                            Label(category.visible ? String(localized: "Hide") : String(localized: "Show"), systemImage: category.visible ? "eye.slash" : "eye")
                        }
                        .tint(Ink.soft)
                    }
                }
                .onMove(perform: move)
            } footer: {
                Text("Drag to reorder. Hidden categories keep their history but stop appearing when you write entries.")
            }
        }
        .scrollContentBackground(.hidden)
        .paperBackground()
        .navigationTitle(Text("Categories"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if pro.allows(customCategories: categories.filter(\.isCustom).count) {
                        editing = CategoryTarget(category: nil)
                    } else {
                        router.showPaywall = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("New category"))
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .sheet(item: $editing) { target in
            CategoryEditor(category: target.category, isIncome: showIncome)
        }
        .confirmationDialog(Text("Delete category?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { category in
            let others = categories.filter { $0.id != category.id && $0.isIncome == category.isIncome && $0.visible }
            ForEach(others.prefix(6)) { other in
                Button(String(localized: "Move entries to \(other.name)")) { delete(category, to: other) }
            }
            Button(String(localized: "Delete and leave entries uncategorized"), role: .destructive) { delete(category, to: nil) }
        } message: { category in
            Text("Entries in this category: \((category.transactions ?? []).count)")
        }
    }

    private func usage(_ category: TransactionCategory) -> String {
        let count = (category.transactions ?? []).count
        return String(localized: "\(count) entries")
    }

    private func move(from source: IndexSet, to destination: Int) {
        var list = shown
        list.move(fromOffsets: source, toOffset: destination)
        let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
        try? writer.reorderCategories(list)
    }

    private func delete(_ category: TransactionCategory, to replacement: TransactionCategory?) {
        let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
        try? writer.deleteCategory(category, movingTo: replacement)
        Upkeep.afterChange(context: context, rates: rates)
        deleting = nil
    }
}

struct CategoryEditor: View {
    let category: TransactionCategory?
    var isIncome: Bool = false
    var onCreated: ((TransactionCategory) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RateBook.self) private var rates

    @State private var name = ""
    @State private var symbol = "tag.fill"
    @State private var hex = InkSwatch.teal
    @State private var income = false

    var body: some View {
        EditorChrome(category == nil ? Text("New category") : Text("Edit category"), canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty, onSave: save) {
            HStack(spacing: 14) {
                Glyph(symbol: symbol, hex: hex, size: 54)
                TextField("Name", text: $name)
                    .font(Typeface.heading)
            }
            .paperCard()
            if category == nil {
                SegmentRail(items: [(false, "Spending"), (true, "Income")], selection: $income)
            }
            FieldRow("Color") { SwatchPicker(hex: $hex) }
                .paperCard()
            FieldRow("Symbol") { SymbolPicker(symbol: $symbol, tintHex: hex) }
                .paperCard()
        }
        .onAppear {
            income = isIncome
            guard let category else { return }
            name = category.name
            symbol = category.iconName
            hex = category.colorHex
            income = category.isIncome
        }
    }

    private func save() {
        let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let category {
            try? writer.updateCategory(category, name: trimmed, icon: symbol, colorHex: hex)
        } else if let created = try? writer.createCategory(name: trimmed, icon: symbol, colorHex: hex, isIncome: income) {
            onCreated?(created)
        }
        Haptic.success()
        dismiss()
    }
}

/// Main currency with search; offers to convert budgets and the plan.
struct CurrencyScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RateBook.self) private var rates
    @Query private var profiles: [UserProfile]
    @Query private var budgets: [Budget]

    @State private var search = ""
    @State private var pending: String?

    private var codes: [String] {
        let all = Array(Set(Locale.commonISOCurrencyCodes + CurrencyMenu.frequent)).sorted()
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = needle.isEmpty ? all : all.filter { $0.lowercased().contains(needle) || MoneyFormat.currencyName($0).lowercased().contains(needle) }
        let top = CurrencyMenu.frequent.filter { filtered.contains($0) }
        return top + filtered.filter { !top.contains($0) }
    }

    var body: some View {
        List(codes, id: \.self) { code in
            Button {
                guard code != profiles.first?.defaultCurrencyCode else { return }
                pending = code
            } label: {
                HStack {
                    Text(verbatim: MoneyFormat.symbol(for: code))
                        .font(Typeface.figure(17))
                        .frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: code).font(Typeface.labelStrong)
                        Text(verbatim: MoneyFormat.currencyName(code)).font(Typeface.detail).foregroundStyle(Ink.soft)
                    }
                    Spacer()
                    if code == profiles.first?.defaultCurrencyCode {
                        Image(systemName: "checkmark").foregroundStyle(Ink.gain)
                    }
                }
                .foregroundStyle(Ink.text)
            }
        }
        .searchable(text: $search, prompt: Text("Search currencies"))
        .scrollContentBackground(.hidden)
        .paperBackground()
        .navigationTitle(Text("Main currency"))
        .confirmationDialog(Text("Switch main currency?"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible, presenting: pending) { code in
            Button(String(localized: "Switch and convert budgets")) { apply(code, convert: true) }
            Button(String(localized: "Switch, keep budget numbers")) { apply(code, convert: false) }
        } message: { code in
            Text("Totals will be shown in \(code). Accounts keep their own currencies.")
        }
    }

    private func apply(_ code: String, convert: Bool) {
        guard let profile = profiles.first else { return }
        let old = profile.defaultCurrencyCode
        if convert {
            for budget in budgets { budget.limitAmount = Decimals.rounded(rates.convert(budget.limitAmount, from: old, to: code), scale: 0) }
            if let plan = profile.monthlyPlan { profile.monthlyPlan = Decimals.rounded(rates.convert(plan, from: old, to: code), scale: 0) }
        }
        profile.defaultCurrencyCode = code
        try? context.save()
        Upkeep.afterChange(context: context, rates: rates)
        pending = nil
        dismiss()
    }
}
