
import SwiftUI
import SwiftData

struct AnalyticsView: View {
    private enum Segment: String, CaseIterable, Hashable { case budgets = "Budgets", reports = "Reports", capital = "Capital" }

    @State private var segment: Segment = .budgets

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    CustomSegmentedControl(
                        options: Segment.allCases.map { ($0, $0.rawValue) },
                        selection: $segment
                    )
                    .padding(.horizontal, FinoraMetric.screenPadding)
                    .padding(.top, 8)
                    
                    switch segment {
                    case .budgets: BudgetsContentView()
                    case .reports: ReportsView()
                    case .capital: CapitalView()
                    }
                }
                .navigationTitle("Analytics")
            }
            .scrollIndicators(.hidden)
            .background(FinoraColor.background.ignoresSafeArea())
        }
    }
}



struct BudgetsContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var exchangeService: CurrencyExchangeService
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]
    @Query private var allBudgets: [Budget]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var profiles: [UserProfile]

    @State private var showAddBudget = false
    @State private var editingBudget: Budget?
    @State private var showPaywall = false

    private var currency: String { profiles.first?.defaultCurrencyCode ?? "USD" }
    private var monthStart: Date { Date().startOfMonth }
    private var thisMonthBudgets: [Budget] {
        allBudgets.filter { Calendar.current.isDate($0.month, equalTo: monthStart, toGranularity: .month) }
    }

    private func tapAddBudget() {
        if purchaseManager.canAddBudget(currentCount: thisMonthBudgets.count) {
            showAddBudget = true
        } else {
            showPaywall = true
        }
    }

    private func spent(for category: TransactionCategory) -> Decimal {
        transactions
            .filter { $0.category?.id == category.id && $0.type == .expense && $0.date >= monthStart }
            .reduce(Decimal(0)) { $0 + exchangeService.convert($1.amount, from: $1.account?.currencyCode ?? currency, to: currency) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Budgets for \(Date().formatted(.dateTime.month(.wide)))")
                    .font(FinoraFont.caption)
                    .foregroundStyle(FinoraColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if thisMonthBudgets.isEmpty {
                    ScrollView {
                        EmptyStateView(
                            icon: "chart.bar.fill",
                            title: "No budgets yet",
                            subtitle: "Set a monthly limit per category to see your progress here.",
                            buttonTitle: "New budget"
                        ) { tapAddBudget() }
                            .padding()
                            .padding(.top, 55)
                    }
                } else {
                    ForEach(thisMonthBudgets) { budget in
                        if let category = budget.category {
                            budgetRow(budget: budget, category: category)
                        }
                    }
                    PrimaryButton(title: "New budget", icon: "plus", gradient: true) { tapAddBudget() }
                }
            }
            .padding(.horizontal, FinoraMetric.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .tabBarSafeArea()
        .scrollIndicators(.hidden)
        .background(FinoraColor.background)
        .sheet(isPresented: $showAddBudget) { AddBudgetView() }
        .sheet(item: $editingBudget) { budget in AddBudgetView(editingBudget: budget) }
        .fullScreenCover(isPresented: $showPaywall) { PaywallView(onDismiss: { showPaywall = false }) }
        
    }

    private func budgetRow(budget: Budget, category: TransactionCategory) -> some View {
        let spentAmount = spent(for: category)
        let progress = SafeToSpendCalculator.progress(spent: spentAmount, limit: budget.limitAmount)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                CategoryIconView(iconName: category.iconName, colorHex: category.colorHex, size: 32)
                Text(category.name).font(FinoraFont.bodyMedium).foregroundStyle(FinoraColor.textPrimary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(FinoraFont.caption)
                    .foregroundStyle(progress > 0.9 ? FinoraColor.coral : FinoraColor.textSecondary)
                Menu {
                    Button { editingBudget = budget } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { delete(budget) } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(FinoraColor.textTertiary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
            }
            Text("\(spentAmount.formatted(.currency(code: currency))) / \(budget.limitAmount.formatted(.currency(code: currency)))")
                .font(FinoraFont.caption)
                .foregroundStyle(FinoraColor.textSecondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(FinoraColor.divider)
                    Capsule()
                        .fill(progress > 0.9 ? FinoraColor.coral : Color(hex: category.colorHex))
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .finoraCard()
    }

    private func delete(_ budget: Budget) {
        modelContext.delete(budget)
        try? modelContext.save()
    }
}


struct AddBudgetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]

    var editingBudget: Budget?

    @State private var selectedCategory: TransactionCategory?
    @State private var limitText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("Select a category").tag(TransactionCategory?.none)
                        ForEach(categories.filter { $0.kind == .expense }) { category in
                            Text(category.name).tag(Optional(category))
                        }
                    }
                }
                Section("Monthly limit") {
                    TextField("0.00", text: $limitText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle(editingBudget == nil ? "New Budget" : "Edit Budget")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(selectedCategory == nil || Decimal(string: limitText) == nil)
                }
            }
            .onAppear {
                guard let editingBudget else { return }
                selectedCategory = editingBudget.category
                limitText = "\(editingBudget.limitAmount)"
            }
        }
    }

    private func save() {
        guard let selectedCategory, let limit = Decimal(string: limitText) else { return }
        if let editingBudget {
            editingBudget.category = selectedCategory
            editingBudget.limitAmount = limit
        } else {
            let budget = Budget(category: selectedCategory, limitAmount: limit, month: Date().startOfMonth)
            modelContext.insert(budget)
        }
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    AnalyticsView()
        .modelContainer(for: [Account.self, Transaction.self, TransactionCategory.self, Budget.self, Asset.self, AssetTransaction.self, UserProfile.self], inMemory: true)
        .environmentObject(CurrencyExchangeService())
        .environmentObject(PurchaseManager())
}
