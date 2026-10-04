

import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @State private var showAddAccount = false
    @State private var editingAccount: Account?
    @State private var showPaywall = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(accounts) { account in
                    Button { editingAccount = account } label: {
                        HStack {
                            ZStack {
                                Circle().fill(FinoraColor.verdant.opacity(0.18))
                                Image(systemName: account.type.iconName).foregroundStyle(FinoraColor.verdant)
                            }
                            .frame(width: 36, height: 36)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(account.name).font(FinoraFont.bodyMedium).foregroundStyle(FinoraColor.textPrimary)
                                    if !account.showsOnOverview {
                                        Image(systemName: "eye.slash")
                                            .font(.system(size: 11))
                                            .foregroundStyle(FinoraColor.textTertiary)
                                    }
                                }
                                Text(account.type.displayName).font(FinoraFont.caption).foregroundStyle(FinoraColor.textSecondary)
                            }
                            Spacer()
                            LiveNumberText(value: account.balance, currencyCode: account.currencyCode, font: FinoraFont.cardAmount)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            modelContext.delete(account)
                            try? modelContext.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .tabBarSafeArea()
        .background(FinoraColor.background)
        .navigationTitle("My Accounts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { tapAdd() } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAddAccount) { AddAccountView() }
        .sheet(item: $editingAccount) { account in AddAccountView(editingAccount: account) }
        .fullScreenCover(isPresented: $showPaywall) { PaywallView(onDismiss: { showPaywall = false }) }
    }
    
    private func tapAdd() {
        if purchaseManager.canAddAccount(currentCount: accounts.count) {
            showAddAccount = true
        } else {
            showPaywall = true
        }
    }
}

struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    
    var editingAccount: Account?
    
    @State private var name = ""
    @State private var type: AccountType = .cash
    @State private var currencyCode = "USD"
    @State private var startingBalanceText = "0"
    @State private var overviewVisibility: OverviewVisibility = .automatic
    
    private var canSave: Bool { !name.isEmpty }
    
    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(FinoraColor.textTertiary)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
            
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(FinoraColor.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(FinoraColor.surface)
                        .clipShape(Circle())
                }
                Spacer()
                Text(editingAccount == nil ? "Add Account" : "Edit Account")
                    .font(FinoraFont.screenTitle)
                    .foregroundStyle(FinoraColor.textPrimary)
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, FinoraMetric.screenPadding)
            .padding(.top, 12)
            
            ScrollView {
                VStack(spacing: 22) {
                    typePicker
                    styledField(title: "Account name") {
                        TextField("e.g. Cash,bank", text: $name)
                            .font(FinoraFont.body)
                            .foregroundStyle(FinoraColor.textPrimary)
                    }
                    currencyPicker
                    styledField(title: editingAccount == nil ? "Starting balance" : "Balance") {
                        TextField("0.00", text: $startingBalanceText)
                            .keyboardType(.decimalPad)
                            .font(FinoraFont.body)
                            .foregroundStyle(FinoraColor.textPrimary)
                    }
                    overviewVisibilityPicker
                    
                    PrimaryButton(title: editingAccount == nil ? "Add Account" : "Save Changes", gradient: true) { save() }
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)
                }
                .padding(.horizontal, FinoraMetric.screenPadding)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .background(FinoraColor.background.ignoresSafeArea())
        .onAppear(perform: prefill)
    }
    
    private var typePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Type").font(FinoraFont.bodyMedium).foregroundStyle(FinoraColor.textPrimary)
            HStack(spacing: 10) {
                ForEach(AccountType.allCases) { candidate in
                    Button { type = candidate } label: {
                        VStack(spacing: 6) {
                            Image(systemName: candidate.iconName)
                                .font(.system(size: 16, weight: .semibold))
                            Text(candidate.displayName).font(FinoraFont.micro)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(type == candidate ? FinoraColor.verdant : FinoraColor.surface)
                        .foregroundStyle(type == candidate ? Color.white : FinoraColor.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var currencyPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Currency").font(FinoraFont.bodyMedium).foregroundStyle(FinoraColor.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CurrencyCode.common, id: \.self) { code in
                        FilterChip(title: code, isSelected: currencyCode == code) { currencyCode = code }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var overviewVisibilityPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Show on Overview").font(FinoraFont.bodyMedium).foregroundStyle(FinoraColor.textPrimary)
            HStack(spacing: 8) {
                ForEach(OverviewVisibility.allCases) { option in
                    FilterChip(title: option.shortLabel, isSelected: overviewVisibility == option) { overviewVisibility = option }
                }
            }
            Text("Automatic hides this wallet from the home screen whenever its balance is zero or negative.")
                .font(FinoraFont.micro)
                .foregroundStyle(FinoraColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func styledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(FinoraFont.bodyMedium).foregroundStyle(FinoraColor.textPrimary)
            content()
                .padding(.horizontal, 14)
                .frame(height: FinoraMetric.inputHeight)
                .background(FinoraColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: FinoraMetric.chipRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func prefill() {
        guard let editingAccount else {
            if let defaultCode = profiles.first?.defaultCurrencyCode { currencyCode = defaultCode }
            return
        }
        name = editingAccount.name
        type = editingAccount.type
        currencyCode = editingAccount.currencyCode
        startingBalanceText = "\(editingAccount.balance)"
        overviewVisibility = editingAccount.overviewVisibility
    }
    
    private func save() {
        let balance = Decimal(string: startingBalanceText) ?? 0
        if let editingAccount {
            editingAccount.name = name
            editingAccount.type = type
            editingAccount.currencyCode = currencyCode
            editingAccount.balance = balance
            editingAccount.overviewVisibility = overviewVisibility
        } else {
            let account = Account(name: name, type: type, currencyCode: currencyCode, balance: balance, overviewVisibility: overviewVisibility)
            modelContext.insert(account)
        }
        try? modelContext.save()
        dismiss()
    }
}

private extension OverviewVisibility {
    var shortLabel: String {
        switch self {
        case .automatic: "Automatic"
        case .alwaysShow: "Always show"
        case .alwaysHide: "Always hide"
        }
    }
}

#Preview {
    NavigationStack { AccountsView() }
        .modelContainer(for: [Account.self], inMemory: true)
        .environmentObject(PurchaseManager())
}
