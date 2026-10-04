
import SwiftUI
import SwiftData

struct CategoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var exchangeService: CurrencyExchangeService
    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var profiles: [UserProfile]
    
    @State private var kind: CategoryKind = .expense
    @State private var showAddCategory = false
    @State private var showPaywall = false
    @EnvironmentObject private var purchaseManager: PurchaseManager
    
    private var currency: String { profiles.first?.defaultCurrencyCode ?? "USD" }
    private var filtered: [TransactionCategory] { categories.filter { $0.kind == kind } }
    
    private func total(for category: TransactionCategory) -> Decimal {
        transactions
            .filter { $0.category?.id == category.id }
            .reduce(Decimal(0)) { $0 + exchangeService.convert($1.amount, from: $1.account?.currencyCode ?? currency, to: currency) }
    }
    
    private func count(for category: TransactionCategory) -> Int {
        transactions.filter { $0.category?.id == category.id }.count
    }
    
    var body: some View {
        
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    CustomSegmentedControl(
                        options: [(CategoryKind.expense, "Expense"), (CategoryKind.income, "Income")],
                        selection: $kind
                    )
                    .padding(.bottom)
                    
                    ForEach(filtered) { category in
                        HStack {
                            CategoryIconView(iconName: category.iconName, colorHex: category.colorHex, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name).font(FinoraFont.bodyMedium).foregroundStyle(FinoraColor.textPrimary)
                                Text("\(count(for: category)) transactions").font(FinoraFont.caption).foregroundStyle(FinoraColor.textSecondary)
                            }
                            Spacer()
                            Text(total(for: category).formatted(.currency(code: currency)))
                                .font(FinoraFont.caption)
                                .foregroundStyle(FinoraColor.textSecondary)
                        }
                        .padding(.vertical, 10)
                        .listRowBackground(FinoraColor.background)
                        .swipeActions {
                            Button(role: .destructive) {
                                modelContext.delete(category)
                                try? modelContext.save()
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                .padding()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .tabBarSafeArea()
        }
        .background(FinoraColor.background)
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { tapAdd() } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAddCategory) { AddCategoryView(defaultKind: kind) }
        .fullScreenCover(isPresented: $showPaywall) { PaywallView(onDismiss: { showPaywall = false }) }
        
        
    }
    
    private func tapAdd() {
        if purchaseManager.canAddCustomCategory() {
            showAddCategory = true
        } else {
            showPaywall = true
        }
    }
}

struct AddCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existingCategories: [TransactionCategory]
    
    var defaultKind: CategoryKind = .expense
    
    @State private var name = ""
    @State private var kind: CategoryKind
    @State private var selectedIcon = "fork.knife"
    @State private var selectedColorHex = CategoryPalette.terracotta
    @State private var showAllIcons = false
    
    init(defaultKind: CategoryKind = .expense) {
        self.defaultKind = defaultKind
        _kind = State(initialValue: defaultKind)
    }
    
    
    private let icons = [
        "fork.knife", "cup.and.saucer.fill", "wineglass.fill", "takeoutbag.and.cup.and.straw.fill",
        "car.fill", "bus.fill", "tram.fill", "airplane", "fuelpump.fill", "bicycle",
        "bag.fill", "cart.fill", "tag.fill", "gift.fill",
        "house.fill", "bed.double.fill", "lightbulb.fill", "wrench.and.screwdriver.fill", "sofa.fill",
        "heart.fill", "cross.case.fill", "pills.fill", "stethoscope",
        "gamecontroller.fill", "music.note", "film.fill", "popcorn.fill", "theatermasks.fill",
        "dumbbell.fill", "figure.run", "sportscourt.fill",
        "graduationcap.fill", "book.fill", "pencil",
        "wallet.pass.fill", "banknote.fill", "creditcard.fill", "briefcase.fill", "chart.pie.fill",
        "suitcase.fill", "map.fill", "pawprint.fill",
        "laptopcomputer", "iphone", "bolt.fill", "drop.fill", "wifi",
        "scissors", "leaf.fill", "star.fill", "ellipsis"
    ]
    private let collapsedIconCount = 16
    private var visibleIcons: [String] {
        showAllIcons ? icons : Array(icons.prefix(collapsedIconCount))
    }
    
    private let colors = CategoryPalette.all
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CustomSegmentedControl(
                        options: [(CategoryKind.expense, "Expense"), (CategoryKind.income, "Income")],
                        selection: $kind
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                
                Section("Category icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        ForEach(visibleIcons, id: \.self) { icon in
                            Button { selectedIcon = icon } label: {
                                ZStack {
                                    Circle().fill(Color(hex: selectedColorHex).opacity(selectedIcon == icon ? 0.35 : 0.15))
                                    Image(systemName: icon).foregroundStyle(Color(hex: selectedColorHex))
                                }
                                .frame(width: 48, height: 48)
                                .overlay(Circle().stroke(selectedIcon == icon ? Color(hex: selectedColorHex) : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    if icons.count > collapsedIconCount {
                        Button(showAllIcons ? "Show fewer icons" : "Show all icons (\(icons.count))") {
                            withAnimation { showAllIcons.toggle() }
                        }
                        .font(FinoraFont.caption)
                        .foregroundStyle(FinoraColor.verdant)
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                    
                    HStack {
                        ForEach(colors, id: \.self) { hex in
                            Button { selectedColorHex = hex } label: {
                                Circle().fill(Color(hex: hex))
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(.white, lineWidth: selectedColorHex == hex ? 2 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
                
                Section("Category name") {
                    TextField("Enter category name", text: $name)
                }
            }
            .navigationTitle("Add New Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func save() {
        let maxOrder = existingCategories.filter { $0.kind == kind }.map(\.sortOrder).max() ?? 0
        let category = TransactionCategory(
            name: name, iconName: selectedIcon, colorHex: selectedColorHex,
            kind: kind, isCustom: true, sortOrder: maxOrder + 1
        )
        modelContext.insert(category)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    NavigationStack { CategoriesView() }
        .modelContainer(for: [TransactionCategory.self, Transaction.self, UserProfile.self], inMemory: true)
        .environmentObject(CurrencyExchangeService())
        .environmentObject(PurchaseManager())
}
