
import SwiftUI
import SwiftData
import Charts
import UIKit

struct OverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var exchangeService: CurrencyExchangeService
    @EnvironmentObject private var purchaseManager: PurchaseManager
    
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var budgets: [Budget]
    @Query private var assets: [Asset]
    @Query private var assetLedger: [AssetTransaction]
    @Query(sort: \Goal.sortOrder) private var goals: [Goal]
    @Query private var profiles: [UserProfile]
    
    @State private var showAddTransaction = false
    @State private var showAddAccount = false
    @State private var showPaywall = false
    @State private var periodMode: PeriodMode = .month
    @State private var monthAnchor: Date = Date().startOfMonth
    @State private var yearAnchor: Date = Date().startOfYear
    @State private var showPeriodPicker = false
    @State private var editingTransaction: Transaction?
    
    private var profile: UserProfile? { profiles.first }
    private var currency: String { profile?.defaultCurrencyCode ?? "USD" }
    
    private func converted(_ amount: Decimal, from code: String) -> Decimal {
        exchangeService.convert(amount, from: code, to: currency)
    }
    
    private var visibleAccounts: [Account] {
        let nonArchived = accounts.filter { !$0.isArchived }
        let filtered = nonArchived.filter { $0.showsOnOverview }
        return filtered.isEmpty ? nonArchived : filtered
    }
    
    private var totalCapitalValue: Decimal {
        assets.reduce(0) { partial, asset in
            let ledger = assetLedger.filter { $0.asset?.id == asset.id }
            return partial + converted(asset.currentValue(in: ledger), from: asset.currencyCode)
        }
    }
    
    private var showsCapitalCard: Bool {
        (profile?.showCapitalOnOverview ?? true) && totalCapitalValue > 0
    }
    
    private var totalBalanceAllAccounts: Decimal {
        let accountsTotal = accounts
            .filter { !$0.isArchived }
            .reduce(Decimal(0)) { $0 + converted($1.balance, from: $1.currencyCode) }
        return accountsTotal + ((profile?.showCapitalOnOverview ?? true) ? totalCapitalValue : 0)
    }
    
    enum PeriodMode: String, CaseIterable, Identifiable {
        case month = "Month"
        case year = "Year"
        case last30Days = "Last 30 Days"
        case allTime = "All Time"
        var id: String { rawValue }
    }
    
    private var periodLabel: String {
        switch periodMode {
        case .month: monthAnchor.formatted(.dateTime.month(.wide).year())
        case .year: yearAnchor.formatted(.dateTime.year())
        case .last30Days: "Last 30 Days"
        case .allTime: "All Time"
        }
    }
    
    private var canNavigatePeriod: Bool { periodMode == .month || periodMode == .year }
    
    private var canGoForward: Bool {
        let calendar = Calendar.current
        switch periodMode {
        case .month: return !calendar.isDate(monthAnchor, equalTo: Date().startOfMonth, toGranularity: .month)
        case .year: return !calendar.isDate(yearAnchor, equalTo: Date().startOfYear, toGranularity: .year)
        case .last30Days, .allTime: return false
        }
    }
    
    private func shiftPeriod(_ delta: Int) {
        let calendar = Calendar.current
        switch periodMode {
        case .month:
            if let newAnchor = calendar.date(byAdding: .month, value: delta, to: monthAnchor) { monthAnchor = newAnchor }
        case .year:
            if let newAnchor = calendar.date(byAdding: .year, value: delta, to: yearAnchor) { yearAnchor = newAnchor }
        case .last30Days, .allTime:
            break
        }
    }
    
    private var heroRange: (start: Date, end: Date)? {
        let calendar = Calendar.current
        let now = Date()
        switch periodMode {
        case .month:
            return (monthAnchor, calendar.date(byAdding: .month, value: 1, to: monthAnchor) ?? monthAnchor)
        case .year:
            return (yearAnchor, calendar.date(byAdding: .year, value: 1, to: yearAnchor) ?? yearAnchor)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
            return (start, calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        case .allTime:
            return nil
        }
    }
    
    private var heroTransactions: [Transaction] {
        guard let heroRange else { return transactions }
        return transactions.filter { $0.date >= heroRange.start && $0.date < heroRange.end }
    }
    
    private var heroCategoryBreakdown: [CategoryAmount] {
        TransactionCategory.expenseBreakdown(of: heroTransactions, convert: exchangeService.convert, displayCurrency: currency)
    }
    
    private var heroExpense: Decimal { heroCategoryBreakdown.reduce(Decimal(0)) { $0 + $1.amount } }
    
    private var heroIncome: Decimal {
        heroTransactions
            .filter { $0.type == .income }
            .reduce(Decimal(0)) { $0 + converted($1.amount, from: $1.account?.currencyCode ?? currency) }
    }
    
    private var heroNet: Decimal { heroIncome - heroExpense }
    
    private var monthStart: Date { Date().startOfMonth }
    
    private var thisMonthTransactions: [Transaction] {
        transactions.filter { $0.date >= monthStart }
    }
    
    private var thisMonthBudgets: [Budget] {
        budgets.filter { Calendar.current.isDate($0.month, equalTo: monthStart, toGranularity: .month) }
    }
    
    private var totalSpentThisMonth: Decimal {
        let budgetedCategoryIDs = Set(thisMonthBudgets.compactMap { $0.category?.id })
        return thisMonthTransactions
            .filter { $0.type == .expense && $0.category.map { budgetedCategoryIDs.contains($0.id) } == true }
            .reduce(Decimal(0)) { $0 + converted($1.amount, from: $1.account?.currencyCode ?? currency) }
    }
    
    private var totalBudgetLimit: Decimal {
        thisMonthBudgets.reduce(0) { $0 + $1.limitAmount }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    totalBalanceCard
                    heroCard
                    accountsCarousel
                    
                    if !goals.isEmpty {
                        goalsPreviewSection
                    }
                    
                    if totalBudgetLimit > 0 {
                        monthlyBudgetCard
                    }
                    
                    recentTransactionsSection
                    
                    if purchaseManager.shouldShowAds {
                        BannerAdView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, FinoraMetric.screenPadding)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .tabBarSafeArea()
            .background(FinoraColor.background)
            .navigationBarHidden(true)
            .sheet(isPresented: $showAddTransaction) { AddTransactionView() }
            .sheet(isPresented: $showAddAccount) { AddAccountView() }
            .fullScreenCover(isPresented: $showPaywall) { PaywallView(onDismiss: { showPaywall = false }) }
            .sheet(item: $editingTransaction) { transaction in AddTransactionView(editingTransaction: transaction) }
            .sheet(isPresented: $showPeriodPicker) {
                PeriodPickerSheet(mode: $periodMode, monthAnchor: $monthAnchor, yearAnchor: $yearAnchor)
                    .presentationDetents([.height(460)])
                    .presentationDragIndicator(.hidden)
            }
        }
    }
    
    private var header: some View {
        HStack {
            
            Spacer()
            
            Text(Date().formatted(.dateTime.month(.wide).year()))
                .font(FinoraFont.bodyMedium)
                .foregroundStyle(FinoraColor.textPrimary)
            
            Spacer()
            
        }
    }
    
    private var totalBalanceCard: some View {
        VStack(spacing: 6) {
            Text("Total balance")
                .font(FinoraFont.caption)
                .foregroundStyle(FinoraColor.textSecondary)
            LiveNumberText(
                value: totalBalanceAllAccounts,
                currencyCode: currency,
                font: FinoraFont.amount(40, weight: .bold)
            )
        }
        .frame(maxWidth: .infinity)
    }
    
    private var heroCard: some View {
        VStack(spacing: 18) {
            periodPill
            
            ZStack {
                if heroCategoryBreakdown.isEmpty {
                    Circle()
                        .stroke(FinoraColor.divider, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .frame(width: 200, height: 200)
                } else {
                    Chart(heroCategoryBreakdown) { item in
                        SectorMark(
                            angle: .value("Amount", (item.amount as NSDecimalNumber).doubleValue),
                            innerRadius: .ratio(0.72),
                            angularInset: 2
                        )
                        .foregroundStyle(Color(hex: item.category.colorHex))
                        .cornerRadius(3)
                    }
                    .frame(width: 200, height: 200)
                }
                
                VStack(spacing: 4) {
                    Text("Net")
                        .font(FinoraFont.caption)
                        .foregroundStyle(FinoraColor.textSecondary)
                    LiveNumberText(
                        value: heroNet,
                        currencyCode: currency,
                        font: FinoraFont.amount(22, weight: .bold),
                        color: heroNet >= 0 ? FinoraColor.verdant : FinoraColor.coral
                    )
                }
            }
            
            HStack(spacing: 12) {
                heroStat(title: "Income", value: heroIncome, color: FinoraColor.verdant, icon: "arrow.up.right")
                heroStat(title: "Expenses", value: heroExpense, color: FinoraColor.coral, icon: "arrow.down.right")
            }
        }
        .padding(20)
        .finoraCard()
    }
    
    private var periodPill: some View {
        HStack(spacing: 2) {
            if canNavigatePeriod {
                Button { shiftPeriod(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FinoraColor.textSecondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
            
            Button { showPeriodPicker = true } label: {
                HStack(spacing: 6) {
                    Text(periodLabel)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .font(FinoraFont.bodyMedium)
                .foregroundStyle(FinoraColor.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            
            if canNavigatePeriod {
                Button { shiftPeriod(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(canGoForward ? FinoraColor.textSecondary : FinoraColor.textTertiary.opacity(0.4))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .disabled(!canGoForward)
            }
        }
        .padding(.horizontal, 6)
        .background(FinoraColor.surfaceElevated)
        .clipShape(Capsule())
    }
    
    private func heroStat(title: String, value: Decimal, color: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(color.opacity(0.15))
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(FinoraFont.micro).foregroundStyle(FinoraColor.textSecondary)
                LiveNumberText(value: value, currencyCode: currency, font: FinoraFont.cardAmount)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var accountsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(visibleAccounts) { account in
                    AccountCardView(account: account)
                }
                if showsCapitalCard {
                    NavigationLink {
                        CapitalView()
                            .navigationTitle("Capital")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        InvestmentCardView(value: totalCapitalValue, currencyCode: currency)
                    }
                    .buttonStyle(.plain)
                }
                AddAccountCard { tapAddAccount() }
            }
            .padding(.trailing, FinoraMetric.screenPadding)
        }
        .padding(.horizontal, -FinoraMetric.screenPadding)
        .padding(.leading, FinoraMetric.screenPadding)
    }
    
    private var monthlyBudgetCard: some View {
        NavigationLink {
            BudgetsContentView()
                .navigationTitle("Budgets")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Monthly budget").font(FinoraFont.bodyMedium).foregroundStyle(FinoraColor.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(FinoraColor.textTertiary)
                }
                Text("Spent \(totalSpentThisMonth.formatted(.currency(code: currency))) out of \(totalBudgetLimit.formatted(.currency(code: currency)))")
                    .font(FinoraFont.caption)
                    .foregroundStyle(FinoraColor.textSecondary)
                
                GeometryReader { geo in
                    let progress = SafeToSpendCalculator.progress(spent: totalSpentThisMonth, limit: totalBudgetLimit)
                    ZStack(alignment: .leading) {
                        Capsule().fill(FinoraColor.coral.opacity(0.3))
                        Capsule()
                            .fill(progress > 0.9 ? FinoraColor.coral : FinoraColor.verdant)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 10)
            }
            .padding(16)
            .finoraCard()
        }
        .buttonStyle(.plain)
    }
    
    
    private var goalsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Goals").font(FinoraFont.bodyMedium).foregroundStyle(FinoraColor.textPrimary)
                Spacer()
                NavigationLink("View all") { GoalsView() }
                    .font(FinoraFont.caption)
                    .foregroundStyle(FinoraColor.verdant)
            }
            VStack(spacing: 8) {
                ForEach(goals.prefix(3)) { goal in
                    NavigationLink { GoalsView() } label: {
                        goalPreviewRow(goal)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func goalPreviewRow(_ goal: Goal) -> some View {
        let progress = goal.progress(in: accounts, convert: exchangeService.convert)
        return HStack(spacing: 12) {
            goalThumbnail(goal)
            VStack(alignment: .leading, spacing: 6) {
                Text(goal.name).font(FinoraFont.bodyMedium).foregroundStyle(FinoraColor.textPrimary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(FinoraColor.divider)
                        Capsule().fill(FinoraColor.brassGold).frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 6)
            }
            Text("\(Int(progress * 100))%")
                .font(FinoraFont.caption)
                .foregroundStyle(FinoraColor.textSecondary)
        }
        .padding(14)
        .finoraCard()
    }
    
    @ViewBuilder
    private func goalThumbnail(_ goal: Goal) -> some View {
        if let data = goal.customImageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage).resizable().scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FinoraColor.brassGold.opacity(0.15))
                Image(systemName: goal.iconName ?? GoalIcon.other.rawValue).foregroundStyle(FinoraColor.brassGold)
            }
            .frame(width: 44, height: 44)
        }
    }
    
    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if transactions.isEmpty {
                EmptyStateView(
                    icon: "creditcard.and.123",
                    title: "Add your first transaction",
                    subtitle: "Start tracking your income and expenses to gain full control over your money.",
                    buttonTitle: "Add transaction"
                ) { showAddTransaction = true }
            } else {
                HStack {
                    Text("Recent transactions").font(FinoraFont.bodyMedium).foregroundStyle(FinoraColor.textPrimary)
                    Spacer()
                    NavigationLink("View all") { TransactionsListView() }
                        .font(FinoraFont.caption)
                        .foregroundStyle(FinoraColor.verdant)
                }
                VStack(spacing: 0) {
                    ForEach(transactions.prefix(5)) { transaction in
                        Button { editingTransaction = transaction } label: {
                            TransactionRowView(transaction: transaction)
                        }
                        .buttonStyle(.plain)
                        if transaction.id != transactions.prefix(5).last?.id {
                            Divider().overlay(FinoraColor.divider)
                        }
                    }
                }
                .padding(16)
                .finoraCard()
            }
        }
    }
    
    private func tapAddAccount() {
        if purchaseManager.canAddAccount(currentCount: accounts.count) {
            showAddAccount = true
        } else {
            showPaywall = true
        }
    }
    
    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}


private struct PeriodPickerSheet: View {
    @Binding var mode: OverviewView.PeriodMode
    @Binding var monthAnchor: Date
    @Binding var yearAnchor: Date
    @Environment(\.dismiss) private var dismiss
    
    private var recentMonths: [Date] {
        let calendar = Calendar.current
        return (0..<12).compactMap { calendar.date(byAdding: .month, value: -$0, to: Date().startOfMonth) }
    }
    
    private var recentYears: [Date] {
        let calendar = Calendar.current
        return (0..<6).compactMap { calendar.date(byAdding: .year, value: -$0, to: Date().startOfYear) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Period")
                .font(FinoraFont.screenTitle)
                .foregroundStyle(FinoraColor.textPrimary)
                .padding(.top, 20)
                .padding(.bottom, 8)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 0) {
                        modeRow(.month, label: "Month")
                        Divider().overlay(FinoraColor.divider).padding(.leading, FinoraMetric.screenPadding)
                        modeRow(.year, label: "Year")
                        Divider().overlay(FinoraColor.divider).padding(.leading, FinoraMetric.screenPadding)
                        modeRow(.last30Days, label: "Last 30 Days")
                        Divider().overlay(FinoraColor.divider).padding(.leading, FinoraMetric.screenPadding)
                        modeRow(.allTime, label: "All Time")
                    }
                    
                    if mode == .month {
                        quickJumpSection(
                            title: "Jump to a month",
                            items: recentMonths,
                            isSelected: { Calendar.current.isDate($0, equalTo: monthAnchor, toGranularity: .month) },
                            label: { $0.formatted(.dateTime.month(.wide).year()) }
                        ) { date in
                            monthAnchor = date
                            dismiss()
                        }
                    } else if mode == .year {
                        quickJumpSection(
                            title: "Jump to a year",
                            items: recentYears,
                            isSelected: { Calendar.current.isDate($0, equalTo: yearAnchor, toGranularity: .year) },
                            label: { $0.formatted(.dateTime.year()) }
                        ) { date in
                            yearAnchor = date
                            dismiss()
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(FinoraColor.background)
    }
    
    private func modeRow(_ candidate: OverviewView.PeriodMode, label: String) -> some View {
        Button {
            mode = candidate
            if candidate == .last30Days || candidate == .allTime { dismiss() }
        } label: {
            HStack {
                Text(label).foregroundStyle(FinoraColor.textPrimary)
                Spacer()
                if mode == candidate {
                    Image(systemName: "checkmark").foregroundStyle(FinoraColor.verdant)
                }
            }
            .padding(.horizontal, FinoraMetric.screenPadding)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func quickJumpSection(
        title: String,
        items: [Date],
        isSelected: @escaping (Date) -> Bool,
        label: @escaping (Date) -> String,
        action: @escaping (Date) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(FinoraFont.caption)
                .foregroundStyle(FinoraColor.textSecondary)
                .padding(.horizontal, FinoraMetric.screenPadding)
            VStack(spacing: 0) {
                ForEach(items, id: \.self) { date in
                    Button { action(date) } label: {
                        HStack {
                            Text(label(date)).foregroundStyle(FinoraColor.textPrimary)
                            Spacer()
                            if isSelected(date) {
                                Image(systemName: "checkmark").foregroundStyle(FinoraColor.verdant)
                            }
                        }
                        .padding(.horizontal, FinoraMetric.screenPadding)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}


#Preview {
    OverviewView()
        .modelContainer(for: [Account.self, Transaction.self, TransactionCategory.self, Budget.self, Goal.self, Asset.self, AssetTransaction.self, UserProfile.self], inMemory: true)
        .environmentObject(PurchaseManager())
        .environmentObject(CurrencyExchangeService())
}
