

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var exchangeService: CurrencyExchangeService
    @EnvironmentObject private var purchaseManager: PurchaseManager
    
    @Query(sort: \Goal.sortOrder) private var goals: [Goal]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query private var profiles: [UserProfile]
    
    @State private var showAddGoal = false
    @State private var editingGoal: Goal?
    @State private var isReordering = false
    @State private var showPaywall = false
    
    private func tapAddGoal() {
        if purchaseManager.canAddGoal(currentCount: goals.count) {
            showAddGoal = true
        } else {
            showPaywall = true
        }
    }
    
    private var displayCurrency: String { profiles.first?.defaultCurrencyCode ?? "USD" }
    
    private var totalSaved: Decimal {
        goals.reduce(Decimal(0)) { partial, goal in
            let saved = goal.currentAmount(in: accounts, convert: exchangeService.convert)
            return partial + exchangeService.convert(saved, from: goal.currencyCode, to: displayCurrency)
        }
    }
    
    private var totalTarget: Decimal {
        goals.reduce(Decimal(0)) { $0 + exchangeService.convert($1.targetAmount, from: $1.currencyCode, to: displayCurrency) }
    }
    
    var body: some View {
        List {
            if goals.isEmpty {
                Section {
                    EmptyStateView(
                        icon: "target",
                        title: "Create your first goal",
                        subtitle: "Set a target, link a wallet (or leave it linked to all of them), and watch your progress grow automatically.",
                        buttonTitle: "New goal"
                    ) { tapAddGoal() }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    summaryCard
                }
                .listRowInsets(EdgeInsets(top: 8, leading: FinoraMetric.screenPadding, bottom: 8, trailing: FinoraMetric.screenPadding))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                
                Section {
                    ForEach(goals) { goal in
                        Button {
                            if !isReordering { editingGoal = goal }
                        } label: {
                            goalRow(goal)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: FinoraMetric.screenPadding, bottom: 6, trailing: FinoraMetric.screenPadding))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteGoal(goal)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onMove(perform: moveGoals)
                } header: {
                    HStack {
                        Text("\(goals.count) goal\(goals.count == 1 ? "" : "s") • \(isReordering ? "Drag to reorder" : "Sorted manually")")
                        Spacer()
                        Button(isReordering ? "Done" : "Reorder") {
                            withAnimation { isReordering.toggle() }
                        }
                        .foregroundStyle(FinoraColor.verdant)
                    }
                    .font(FinoraFont.caption)
                    .foregroundStyle(FinoraColor.textSecondary)
                    .textCase(nil)
                    .padding(.horizontal, FinoraMetric.screenPadding - 16)
                }
                
                if !isReordering {
                    Section {
                        PrimaryButton(title: "New goal", icon: "plus", gradient: true) { tapAddGoal() }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: FinoraMetric.screenPadding, bottom: 24, trailing: FinoraMetric.screenPadding))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(isReordering ? .active : .inactive))
        .tabBarSafeArea()
        .background(FinoraColor.background)
        .navigationTitle("Goals")
        .sheet(isPresented: $showAddGoal) { AddGoalView() }
        .fullScreenCover(isPresented: $showPaywall) { PaywallView(onDismiss: { showPaywall = false }) }
        .sheet(item: $editingGoal) { goal in AddGoalView(editingGoal: goal) }
    }
    
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Total saved").font(FinoraFont.caption).foregroundStyle(FinoraColor.textSecondary)
            LiveNumberText(value: totalSaved, currencyCode: displayCurrency, font: FinoraFont.amount(28, weight: .bold), color: FinoraColor.verdant)
            Text("of \(totalTarget.formatted(.currency(code: displayCurrency)))").font(FinoraFont.caption).foregroundStyle(FinoraColor.textSecondary)
            
            GeometryReader { geo in
                let progress = SafeToSpendCalculator.progress(spent: totalSaved, limit: totalTarget)
                ZStack(alignment: .leading) {
                    Capsule().fill(FinoraColor.divider)
                    Capsule().fill(FinoraColor.verdant).frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .finoraCard()
    }
    
    private func goalRow(_ goal: Goal) -> some View {
        let saved = goal.currentAmount(in: accounts, convert: exchangeService.convert)
        let progress = goal.progress(in: accounts, convert: exchangeService.convert)
        
        return HStack(spacing: 14) {
            goalThumbnail(goal)
            VStack(alignment: .leading, spacing: 6) {
                Text(goal.name).font(FinoraFont.bodyMedium).foregroundStyle(FinoraColor.textPrimary)
                Text("\(saved.formatted(.currency(code: goal.currencyCode))) of \(goal.targetAmount.formatted(.currency(code: goal.currencyCode)))")
                    .font(FinoraFont.caption)
                    .foregroundStyle(FinoraColor.textSecondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(FinoraColor.divider)
                        Capsule().fill(FinoraColor.verdant).frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 6)
            }
            Spacer()
            Text("\(Int(progress * 100))%").font(FinoraFont.caption).foregroundStyle(FinoraColor.textSecondary)
        }
        .padding(16)
        .finoraCard()
    }
    
    @ViewBuilder
    private func goalThumbnail(_ goal: Goal) -> some View {
        if let data = goal.customImageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage).resizable().scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FinoraColor.brassGold.opacity(0.15))
                Image(systemName: goal.iconName ?? GoalIcon.other.rawValue).foregroundStyle(FinoraColor.brassGold)
            }
            .frame(width: 56, height: 56)
        }
    }
    
    private func moveGoals(from source: IndexSet, to destination: Int) {
        var reordered = goals
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, goal) in reordered.enumerated() {
            goal.sortOrder = index
        }
        try? modelContext.save()
    }
    
    private func deleteGoal(_ goal: Goal) {
        modelContext.delete(goal)
        try? modelContext.save()
    }
}


struct AddGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var exchangeService: CurrencyExchangeService
    @Query(sort: \Goal.sortOrder) private var existingGoals: [Goal]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query private var profiles: [UserProfile]
    
    var editingGoal: Goal?
    
    @State private var name = ""
    @State private var targetAmountText = ""
    @State private var currencyCode = "USD"
    @State private var targetDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var monthlyContributionText = ""
    @State private var linkedAccountIDs: Set<UUID> = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var customImageData: Data?
    @State private var selectedIcon: GoalIcon = .other
    
    private var canSave: Bool {
        !name.isEmpty && Decimal(string: targetAmountText) != nil
    }
    
    private var previewSavedAmount: Decimal {
        let relevant = linkedAccountIDs.isEmpty ? accounts : accounts.filter { linkedAccountIDs.contains($0.id) }
        return relevant.reduce(Decimal(0)) { $0 + exchangeService.convert($1.balance, from: $1.currencyCode, to: currencyCode) }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    imagePickerRow
                }
                
                Section("Goal name") {
                    TextField("e.g. New Car", text: $name)
                }
                
                Section("Target amount") {
                    HStack {
                        TextField("0.00", text: $targetAmountText).keyboardType(.decimalPad)
                        Picker("Currency", selection: $currencyCode) {
                            ForEach(CurrencyCode.common, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                Section {
                    accountChips
                } header: {
                    Text("Wallets")
                } footer: {
                    Text("Progress is calculated automatically from the balance of the selected wallets (or all of them, if none are selected) — converted to \(currencyCode) using live exchange rates.")
                }
                
                Section("Currently saved") {
                    HStack {
                        Text("From selected wallets")
                        Spacer()
                        Text(previewSavedAmount.formatted(.currency(code: currencyCode)))
                            .foregroundStyle(FinoraColor.verdant)
                    }
                }
                
                Section("Target date") {
                    DatePicker("Target date", selection: $targetDate, displayedComponents: .date)
                }
                
                Section {
                    TextField("0.00", text: $monthlyContributionText).keyboardType(.decimalPad)
                } header: {
                    Text("Monthly contribution (optional)")
                } footer: {
                    Text("It helps you reach your goal faster.")
                }
            }
            .navigationTitle(editingGoal == nil ? "Add New Goal" : "Edit Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
            }
            .onAppear(perform: prefill)
            .onChange(of: pickerItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        customImageData = data
                    }
                }
            }
        }
    }
    
    
    private var imagePickerRow: some View {
        VStack(spacing: 14) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: FinoraMetric.cardRadius, style: .continuous)
                        .fill(FinoraColor.surfaceElevated)
                        .frame(height: 140)
                    if let customImageData, let uiImage = UIImage(data: customImageData) {
                        Image(uiImage: uiImage).resizable().scaledToFill()
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: FinoraMetric.cardRadius, style: .continuous))
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "camera.fill").font(.system(size: 26))
                            Text("Choose a photo").font(FinoraFont.caption)
                        }
                        .foregroundStyle(FinoraColor.textSecondary)
                    }
                }
            }
            
            if customImageData != nil {
                Button("Remove photo", role: .destructive) { customImageData = nil }
                    .font(FinoraFont.caption)
            }
            
            Text("or pick an icon").font(FinoraFont.caption).foregroundStyle(FinoraColor.textSecondary)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                ForEach(GoalIcon.allCases) { icon in
                    Button {
                        selectedIcon = icon
                        customImageData = nil
                    } label: {
                        ZStack {
                            Circle().fill(FinoraColor.brassGold.opacity(selectedIcon == icon && customImageData == nil ? 0.35 : 0.15))
                            Image(systemName: icon.rawValue).foregroundStyle(FinoraColor.brassGold)
                        }
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle().stroke(selectedIcon == icon && customImageData == nil ? FinoraColor.brassGold : .clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 6)
    }
    
    private var accountChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All wallets", isSelected: linkedAccountIDs.isEmpty) {
                    linkedAccountIDs = []
                }
                ForEach(accounts) { account in
                    FilterChip(title: account.name, isSelected: linkedAccountIDs.contains(account.id)) {
                        if linkedAccountIDs.contains(account.id) {
                            linkedAccountIDs.remove(account.id)
                        } else {
                            linkedAccountIDs.insert(account.id)
                        }
                    }
                }
            }
        }
    }
    
    private func prefill() {
        if currencyCode == "USD", let defaultCode = profiles.first?.defaultCurrencyCode {
            currencyCode = defaultCode
        }
        guard let editingGoal else { return }
        name = editingGoal.name
        targetAmountText = "\(editingGoal.targetAmount)"
        currencyCode = editingGoal.currencyCode
        targetDate = editingGoal.targetDate ?? targetDate
        monthlyContributionText = editingGoal.monthlyContribution.map { "\($0)" } ?? ""
        linkedAccountIDs = Set(editingGoal.linkedAccountIDs)
        customImageData = editingGoal.customImageData
        selectedIcon = GoalIcon(rawValue: editingGoal.iconName ?? "") ?? .other
    }
    
    private func save() {
        let target = Decimal(string: targetAmountText) ?? 0
        let monthly = Decimal(string: monthlyContributionText)
        
        if let editingGoal {
            editingGoal.name = name
            editingGoal.targetAmount = target
            editingGoal.currencyCode = currencyCode
            editingGoal.targetDate = targetDate
            editingGoal.monthlyContribution = monthly
            editingGoal.linkedAccountIDs = Array(linkedAccountIDs)
            editingGoal.customImageData = customImageData
            editingGoal.iconName = customImageData == nil ? selectedIcon.rawValue : nil
        } else {
            let maxOrder = existingGoals.map(\.sortOrder).max() ?? 0
            let goal = Goal(
                name: name,
                targetAmount: target,
                currencyCode: currencyCode,
                iconName: customImageData == nil ? selectedIcon.rawValue : nil,
                customImageData: customImageData,
                targetDate: targetDate,
                monthlyContribution: monthly,
                sortOrder: maxOrder + 1,
                linkedAccountIDs: Array(linkedAccountIDs)
            )
            modelContext.insert(goal)
        }
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    NavigationStack { GoalsView() }
        .modelContainer(for: [Goal.self, Account.self, UserProfile.self], inMemory: true)
        .environmentObject(CurrencyExchangeService())
        .environmentObject(PurchaseManager())
}
