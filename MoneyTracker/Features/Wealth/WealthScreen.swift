import SwiftUI
import SwiftData
import Charts

struct WealthScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.moneyPrefs) private var prefs
    @Environment(RateBook.self) private var rates
    @Environment(ProPass.self) private var pro
    @Environment(Router.self) private var router

    @Query private var accounts: [Account]
    @Query private var holdings: [Asset]
    @Query(sort: \Transaction.date, order: .reverse) private var entries: [Transaction]

    @State private var range: WorthRange = .threeMonths
    @State private var editingAccount: AccountTarget?
    @State private var editingHolding: HoldingTarget?
    @State private var refreshing = false
    @State private var showArchived = false

    struct AccountTarget: Identifiable { let id = UUID(); var account: Account? }
    struct HoldingTarget: Identifiable { let id = UUID(); var holding: Asset? }

    private var ordered: [Account] {
        accounts.sorted { ($0.sortIndex ?? 0, $0.createdAt) < ($1.sortIndex ?? 0, $1.createdAt) }
    }

    var body: some View {
        let home = prefs.home
        let toHome: HomeConverter = { amount, code in rates.convert(amount, from: code.isEmpty ? home : code, to: home) }
        let live = ordered.filter { !$0.isArchived }
        let assetsTotal = live.reduce(Decimal(0)) { total, account in
            let value = toHome(account.balance, account.currencyCode)
            return value > 0 ? total + value : total
        }
        let debtsTotal = live.reduce(Decimal(0)) { total, account in
            let value = toHome(account.balance, account.currencyCode)
            return value < 0 ? total - value : total
        }
        let investTotal = holdings.reduce(Decimal(0)) { $0 + toHome($1.marketValue, $1.currencyCode) }
        let netWorth = assetsTotal - debtsTotal + investTotal

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker("Everything you own and owe")
                        Text("Wealth")
                            .font(Typeface.display)
                            .foregroundStyle(Ink.text)
                    }
                    .padding(.top, 8)

                    WorthHero(
                        netWorth: netWorth,
                        home: home,
                        range: $range,
                        accounts: live,
                        holdings: holdings,
                        entries: entries,
                        isPro: pro.isPro,
                        onLocked: { router.showPaywall = true }
                    )

                    SplitBar(assets: assetsTotal, debts: debtsTotal, investments: investTotal, home: home)

                    accountsSection(live: live, home: home, toHome: toHome)

                    holdingsSection(home: home, toHome: toHome, total: investTotal)

                    if !pro.isPro {
                        InlineBanner()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 90)
            }
            .refreshable { await refreshQuotes() }
            .paperBackground()
            .trackScreen("wealth")
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) { WriteButton() }
            .navigationDestination(for: UUID.self) { id in
                if let account = accounts.first(where: { $0.id == id }) {
                    AccountDetail(account: account)
                } else if let holding = holdings.first(where: { $0.id == id }) {
                    HoldingDetail(holding: holding)
                }
            }
            .sheet(item: $editingAccount) { target in
                AccountEditor(account: target.account)
            }
            .sheet(item: $editingHolding) { target in
                HoldingEditor(holding: target.holding)
            }
            .task { await Upkeep.refreshQuotes(context: context, rates: rates) }
        }
    }

    // MARK: Accounts

    @ViewBuilder
    private func accountsSection(live: [Account], home: String, toHome: @escaping HomeConverter) -> some View {
        let archived = ordered.filter(\.isArchived)
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Accounts") {
                Button {
                    if pro.allows(accounts: live.count) {
                        editingAccount = AccountTarget(account: nil)
                    } else {
                        router.showPaywall = true
                    }
                } label: {
                    Label(String(localized: "Add"), systemImage: "plus").font(Typeface.labelStrong)
                }
            }
            ForEach(WalletKind.allCases) { kind in
                let group = live.filter { $0.kind == kind }
                if !group.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        LeaderRow {
                            Kicker(verbatim: kind.groupTitle)
                        } trailing: {
                            MoneyText(value: group.reduce(Decimal(0)) { $0 + toHome($1.balance, $1.currencyCode) }, code: home, size: .tiny, tone: Ink.soft, cents: false)
                        }
                        ForEach(group) { account in
                            NavigationLink(value: account.id) {
                                AccountRow(account: account)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .paperCard(padding: 14)
                }
            }
            if !archived.isEmpty {
                DisclosureGroup(isExpanded: $showArchived) {
                    ForEach(archived) { account in
                        NavigationLink(value: account.id) {
                            AccountRow(account: account).opacity(0.6)
                        }
                        .buttonStyle(.plain)
                    }
                } label: {
                    Kicker("Archived")
                }
                .tint(Ink.soft)
                .paperCard(padding: 14)
            }
        }
    }

    // MARK: Holdings

    @ViewBuilder
    private func holdingsSection(home: String, toHome: @escaping HomeConverter, total: Decimal) -> some View {
        let unrealized = holdings.reduce(Decimal(0)) { $0 + toHome($1.unrealized, $1.currencyCode) }
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Investments") {
                HStack(spacing: 14) {
                    if holdings.contains(where: { $0.autoUpdateEnabled && $0.kind.hasLiveQuotes }) {
                        Button {
                            Task { await refreshQuotes() }
                        } label: {
                            if refreshing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise").font(Typeface.labelStrong)
                            }
                        }
                        .accessibilityLabel(Text("Refresh prices"))
                    }
                    Button {
                        if pro.allows(holdings: holdings.count) {
                            editingHolding = HoldingTarget(holding: nil)
                        } else {
                            router.showPaywall = true
                        }
                    } label: {
                        Label(String(localized: "Add"), systemImage: "plus").font(Typeface.labelStrong)
                    }
                }
            }
            if holdings.isEmpty {
                EmptyPage(
                    symbol: "chart.line.uptrend.xyaxis",
                    title: "Stocks, crypto, a flat",
                    message: "Add what you own. Stocks and crypto update with live prices; for anything else you set the value."
                )
                .paperCard(padding: 0)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .lastTextBaseline) {
                        MoneyText(value: total, code: home, size: .medium, cents: false)
                        Spacer()
                        MoneyText(value: unrealized, code: home, size: .small, signed: true, tone: unrealized >= 0 ? Ink.gain : Ink.loss, cents: false)
                    }
                    ForEach(HoldingKind.allCases) { kind in
                        let group = holdings.filter { $0.kind == kind }
                        if !group.isEmpty {
                            Divider().overlay(Ink.rule)
                            Kicker(verbatim: kind.title)
                            ForEach(group) { holding in
                                NavigationLink(value: holding.id) {
                                    HoldingRow(holding: holding)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .paperCard(padding: 14)
            }
        }
    }

    private func refreshQuotes() async {
        refreshing = true
        await rates.refresh()
        await Upkeep.refreshQuotes(context: context, rates: rates, force: true)
        Upkeep.afterChange(context: context, rates: rates)
        refreshing = false
    }
}

struct AccountRow: View {
    let account: Account

    var body: some View {
        HStack(spacing: 12) {
            Glyph(symbol: account.displaySymbol, hex: account.colorHex, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: account.name)
                    .font(Typeface.labelStrong)
                    .foregroundStyle(Ink.text)
                Text(verbatim: account.kind.isLiability ? String(localized: "Owed") : account.currencyCode)
                    .font(Typeface.detail)
                    .foregroundStyle(Ink.soft)
            }
            Spacer()
            if let owed = account.amountOwed {
                MoneyText(value: owed, code: account.currencyCode, size: .row, tone: owed > 0 ? Ink.loss : Ink.soft)
            } else {
                MoneyText(value: account.balance, code: account.currencyCode, size: .row, tone: account.balance < 0 ? Ink.loss : Ink.text)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Ink.faint)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct HoldingRow: View {
    let holding: Asset

    var body: some View {
        let position = holding.position
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: holding.name)
                    .font(Typeface.labelStrong)
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                Text(verbatim: [holding.ticker, MoneyFormat.number(position.quantity, maxFraction: 6)].compactMap { $0 }.joined(separator: " · "))
                    .font(Typeface.detail)
                    .foregroundStyle(Ink.soft)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                MoneyText(value: holding.marketValue, code: holding.currencyCode, size: .row)
                if position.quantity > 0 {
                    MoneyText(value: holding.unrealized, code: holding.currencyCode, size: .tiny, signed: true, tone: holding.unrealized >= 0 ? Ink.gain : Ink.loss)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Ink.faint)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// Assets / investments / debts proportions on one line.
struct SplitBar: View {
    let assets: Decimal
    let debts: Decimal
    let investments: Decimal
    let home: String

    var body: some View {
        let total = max(Decimals.double(assets + debts + investments), 0.0001)
        let parts: [(LocalizedStringKey, Decimal, Color)] = [
            ("Cash & savings", assets, Ink.text.opacity(0.8)),
            ("Investments", investments, Ink.gain),
            ("Debts", debts, Ink.loss)
        ]
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(parts.indices, id: \.self) { index in
                        let value = Decimals.double(parts[index].1)
                        if value > 0 {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(parts[index].2)
                                .frame(width: max(proxy.size.width * CGFloat(value / total) - 2, 4))
                        }
                    }
                }
            }
            .frame(height: 10)
            HStack(spacing: 14) {
                ForEach(parts.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle().fill(parts[index].2).frame(width: 7, height: 7)
                            Text(parts[index].0)
                                .font(Typeface.micro)
                                .foregroundStyle(Ink.soft)
                        }
                        MoneyText(value: parts[index].1, code: home, size: .tiny, cents: false)
                    }
                }
            }
        }
        .paperCard()
    }
}
