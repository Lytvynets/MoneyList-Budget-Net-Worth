import SwiftUI
import SwiftData

struct LedgerScreen: View {
    enum Pane: Hashable { case entries, report }

    @State private var pane: Pane = .entries

    var body: some View {
        NavigationStack {
            Group {
                switch pane {
                case .entries: EntriesList(pane: $pane).trackScreen("ledger")
                case .report: ReportPane(pane: $pane).trackScreen("report")
                }
            }
            .paperBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct LedgerHeader: View {
    @Binding var pane: LedgerScreen.Pane

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Kicker("Every entry, in order")
                Text("Ledger")
                    .font(Typeface.display)
                    .foregroundStyle(Ink.text)
            }
            SegmentRail(items: [(LedgerScreen.Pane.entries, "Entries"), (LedgerScreen.Pane.report, "Report")], selection: $pane)
        }
        .padding(.top, 8)
    }
}

// MARK: - Entries

struct EntriesList: View {
    @Binding var pane: LedgerScreen.Pane

    @Environment(\.modelContext) private var context
    @Environment(\.moneyPrefs) private var prefs
    @Environment(RateBook.self) private var rates
    @Environment(ProPass.self) private var pro
    @Environment(ToastCenter.self) private var toasts
    @Environment(Router.self) private var router

    @Query(sort: \Transaction.date, order: .reverse) private var entries: [Transaction]
    @Query private var accounts: [Account]
    @Query(sort: \TransactionCategory.sortOrder) private var categories: [TransactionCategory]

    @State private var search = ""
    @State private var kindFilter: EntryKind?
    @State private var accountFilter: UUID?
    @State private var categoryFilter: UUID?
    @State private var span: Span = .all
    @State private var focused: Transaction?

    enum Span: String, CaseIterable, Identifiable {
        case thisMonth, lastMonth, quarter, year, all
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .thisMonth: return "This month"
            case .lastMonth: return "Last month"
            case .quarter: return "3 months"
            case .year: return "This year"
            case .all: return "All time"
            }
        }
    }

    struct DayGroup: Identifiable {
        let day: Date
        let items: [Transaction]
        var id: Date { day }
    }

    private var filtered: [Transaction] {
        let range = spanRange
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        let numeric = AmountReader.number(needle)
        return entries.filter { entry in
            if let range, !(entry.date >= range.lowerBound && entry.date < range.upperBound) { return false }
            if let kindFilter, entry.kind != kindFilter { return false }
            if let accountFilter, entry.account?.id != accountFilter && entry.toAccount?.id != accountFilter { return false }
            if let categoryFilter, entry.category?.id != categoryFilter { return false }
            guard !needle.isEmpty else { return true }
            if let numeric, entry.amount == numeric || (entry.originalAmount ?? -1) == numeric { return true }
            let haystack = [entry.note ?? "", entry.category?.name ?? "", entry.account?.name ?? "", entry.toAccount?.name ?? ""]
                .joined(separator: " ").lowercased()
            return haystack.contains(needle)
        }
    }

    private var spanRange: Range<Date>? {
        let periods = prefs.periods
        let current = periods.month(containing: Date())
        let calendar = Calendar.current
        switch span {
        case .thisMonth: return current.start..<current.end
        case .lastMonth:
            let last = periods.shifted(current, by: -1)
            return last.start..<last.end
        case .quarter:
            let start = periods.shifted(current, by: -2).start
            return start..<current.end
        case .year:
            let start = calendar.date(from: calendar.dateComponents([.year], from: Date())) ?? current.start
            let end = calendar.date(byAdding: .year, value: 1, to: start) ?? current.end
            return start..<end
        case .all: return nil
        }
    }

    private func groups(_ items: [Transaction]) -> [DayGroup] {
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [Transaction]] = [:]
        for entry in items {
            let day = calendar.startOfDay(for: entry.date)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(entry)
        }
        return order.map { DayGroup(day: $0, items: buckets[$0] ?? []) }
    }

    var body: some View {
        let items = filtered
        let home = prefs.home
        let tally = Tally.make(items.ledgerLines) { amount, code in rates.convert(amount, from: code.isEmpty ? home : code, to: home) }
        let days = groups(items)

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    LedgerHeader(pane: $pane)
                    filters
                    summary(tally: tally, home: home, count: items.count)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 8, trailing: 18))
                .listRowBackground(Ink.paper)
                .listRowSeparator(.hidden)
            }

            if items.isEmpty {
                Section {
                    EmptyPage(
                        symbol: entries.isEmpty ? "book.closed" : "magnifyingglass",
                        title: entries.isEmpty ? "A blank page" : "Nothing matches",
                        message: entries.isEmpty ? "Write your first entry — it takes three seconds." : "Try another word, account or period."
                    )
                    .listRowBackground(Ink.paper)
                    .listRowSeparator(.hidden)
                }
            }

            ForEach(days) { group in
                daySection(group, home: home)
            }

            if !pro.isPro && items.count > 8 {
                Section {
                    InlineBanner()
                        .listRowBackground(Ink.paper)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $search, placement: .automatic, prompt: Text("Search notes, categories, amounts"))
        .overlay(alignment: .bottomTrailing) { WriteButton() }
        .sheet(item: $focused) { entry in
            EntryDetailSheet(entry: entry)
        }
    }

    private func daySection(_ group: DayGroup, home: String) -> some View {
        Section {
            ForEach(group.items) { entry in
                row(for: entry)
            }
        } header: {
            DayHeader(day: group.day, items: group.items, home: home)
        }
    }

    private func row(for entry: Transaction) -> some View {
        EntryRow(entry: entry)
            .onTapGesture { focused = entry }
            .listRowBackground(Ink.paper)
            .listRowSeparatorTint(Ink.rule)
            .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { delete(entry) } label: {
                    Label(String(localized: "Delete"), systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button { duplicate(entry) } label: {
                    Label(String(localized: "Repeat"), systemImage: "plus.square.on.square")
                }
                .tint(Ink.gain)
                Button { router.composer = ComposerRequest(kind: entry.kind, editing: entry) } label: {
                    Label(String(localized: "Edit"), systemImage: "pencil")
                }
                .tint(Ink.soft)
            }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker(selection: $span) {
                        ForEach(Span.allCases) { item in Text(item.title).tag(item) }
                    } label: { Text("Period") }
                } label: {
                    Chip(span.title, symbol: "calendar", selected: span != .all)
                }
                Menu {
                    Picker(selection: $kindFilter) {
                        Text("Everything").tag(EntryKind?.none)
                        Text("Spending").tag(Optional(EntryKind.expense))
                        Text("Income").tag(Optional(EntryKind.income))
                        Text("Transfers").tag(Optional(EntryKind.transfer))
                    } label: { Text("Type") }
                } label: {
                    Chip(kindTitle, symbol: "line.3.horizontal.decrease", selected: kindFilter != nil)
                }
                Menu {
                    Picker(selection: $accountFilter) {
                        Text("All accounts").tag(UUID?.none)
                        ForEach(accounts) { account in Text(verbatim: account.name).tag(Optional(account.id)) }
                    } label: { Text("Account") }
                } label: {
                    Chip(verbatim: accounts.first { $0.id == accountFilter }?.name ?? String(localized: "All accounts"), symbol: "wallet.pass", selected: accountFilter != nil)
                }
                Menu {
                    Picker(selection: $categoryFilter) {
                        Text("All categories").tag(UUID?.none)
                        ForEach(categories) { category in Label(category.name, systemImage: category.iconName).tag(Optional(category.id)) }
                    } label: { Text("Category") }
                } label: {
                    Chip(verbatim: categories.first { $0.id == categoryFilter }?.name ?? String(localized: "All categories"), symbol: "tag", selected: categoryFilter != nil)
                }
                if kindFilter != nil || accountFilter != nil || categoryFilter != nil || span != .all {
                    Button {
                        kindFilter = nil
                        accountFilter = nil
                        categoryFilter = nil
                        span = .all
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Ink.faint)
                    }
                    .accessibilityLabel(Text("Clear filters"))
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var kindTitle: LocalizedStringKey {
        switch kindFilter {
        case .expense?: return "Spending"
        case .income?: return "Income"
        case .transfer?: return "Transfers"
        case nil: return "Everything"
        }
    }

    private func summary(tally: Tally, home: String, count: Int) -> some View {
        HStack(spacing: 0) {
            summaryCell(title: "In", value: tally.income, tone: Ink.gain, home: home)
            Rectangle().fill(Ink.rule).frame(width: 0.8, height: 34)
            summaryCell(title: "Out", value: tally.expense, tone: Ink.text, home: home)
            Rectangle().fill(Ink.rule).frame(width: 0.8, height: 34)
            summaryCell(title: "Net", value: tally.net, tone: tally.net >= 0 ? Ink.gain : Ink.loss, home: home)
        }
        .paperCard(padding: 12)
    }

    private func summaryCell(title: LocalizedStringKey, value: Decimal, tone: Color, home: String) -> some View {
        VStack(spacing: 3) {
            Kicker(title)
            MoneyText(value: value, code: home, size: .small, tone: tone, cents: false)
        }
        .frame(maxWidth: .infinity)
    }

    private func delete(_ entry: Transaction) {
        let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
        try? writer.delete(entry)
        Upkeep.afterChange(context: context, rates: rates)
        Haptic.firm()
    }

    private func duplicate(_ entry: Transaction) {
        let writer = LedgerWriter(context: context, convert: { amount, from, to in rates.convert(amount, from: from, to: to) })
        if let copy = try? writer.duplicate(entry) {
            Upkeep.afterChange(context: context, rates: rates)
            Haptic.success()
            toasts.show(String(localized: "Added again for today")) {
                try? writer.delete(copy)
                Upkeep.afterChange(context: context, rates: rates)
            }
        }
    }
}

struct DayHeader: View {
    let day: Date
    let items: [Transaction]
    let home: String

    @Environment(RateBook.self) private var rates

    var body: some View {
        let tally = Tally.make(items.ledgerLines) { amount, code in rates.convert(amount, from: code.isEmpty ? home : code, to: home) }
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: title)
                .font(Typeface.labelStrong)
                .foregroundStyle(Ink.text)
            Spacer()
            if tally.expense > 0 {
                MoneyText(value: -tally.expense, code: home, size: .tiny, signed: true, tone: Ink.soft, cents: false)
            }
            if tally.income > 0 {
                MoneyText(value: tally.income, code: home, size: .tiny, signed: true, tone: Ink.gain, cents: false)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .textCase(nil)
    }

    private var title: String {
        let calendar = Calendar.current
        let date = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        if calendar.isDateInToday(day) { return String(localized: "Today · \(date)") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday · \(date)") }
        return date
    }
}
