import SwiftUI
import SwiftData
import CloudKit
import UserNotifications

struct SettingsScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.moneyPrefs) private var prefs
    @Environment(RateBook.self) private var rates
    @Environment(ProPass.self) private var pro
    @Environment(LockKeeper.self) private var lock
    @Environment(Router.self) private var router

    @Query private var profiles: [UserProfile]
    @Query private var accounts: [Account]

    @AppStorage(AppConfig.Keys.theme) private var themeRaw = AppTheme.system.rawValue
    @AppStorage(AppConfig.Keys.accent) private var accentRaw = InkAccent.vermilion.rawValue
    @AppStorage(AppConfig.Keys.maskOnLaunch) private var maskOnLaunch = false
    @AppStorage(AppConfig.Keys.faceLock) private var faceLock = false
    @AppStorage(AppConfig.Keys.dailyReminder) private var dailyReminder = false
    @AppStorage(AppConfig.Keys.dailyReminderMinutes) private var reminderMinutes = 21 * 60
    @AppStorage(AppConfig.Keys.billReminders) private var billReminders = true
    @AppStorage(AppConfig.Keys.analyticsAllowed) private var analyticsAllowed = true

    @State private var showPlan = false
    @State private var showExport = false
    @State private var exportURL: URL?
    @State private var showImport = false
    @State private var cloudStatus: String?
    @State private var notificationsDenied = false
    @State private var debugMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if !pro.isPro {
                    Section {
                        Button { router.showPaywall = true } label: { ProTeaser() }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    NavigationLink {
                        CurrencyScreen()
                    } label: {
                        SettingRow(symbol: "dollarsign.circle", title: "Main currency", value: "\(prefs.home) · \(MoneyFormat.symbol(for: prefs.home))")
                    }
                    Button { showPlan = true } label: {
                        SettingRow(symbol: "calendar", title: "Monthly plan & month start", value: planSummary)
                    }
                    NavigationLink {
                        CategoriesManager()
                    } label: {
                        SettingRow(symbol: "tag", title: "Categories")
                    }
                    Picker(selection: defaultAccountBinding) {
                        Text("Most used").tag(UUID?.none)
                        ForEach(accounts.filter { !$0.isArchived }) { account in
                            Text(verbatim: account.name).tag(Optional(account.id))
                        }
                    } label: {
                        SettingRow(symbol: "wallet.pass", title: "Default account")
                    }
                } header: { Text("Money") }

                Section {
                    Toggle(isOn: dailyBinding) {
                        SettingRow(symbol: "bell", title: "Daily reminder")
                    }
                    if dailyReminder {
                        DatePicker(selection: reminderTime, displayedComponents: .hourAndMinute) {
                            Text("Remind me at")
                        }
                    }
                    Toggle(isOn: billBinding) {
                        SettingRow(symbol: "calendar.badge.clock", title: "Bill reminders")
                    }
                    Toggle(isOn: budgetAlertBinding) {
                        SettingRow(symbol: "exclamationmark.triangle", title: "Budget alerts at 80% and 100%")
                    }
                    if notificationsDenied {
                        Button("Notifications are off for Money List — open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .font(Typeface.detail)
                    }
                } header: { Text("Reminders") }

                Section {
                    Toggle(isOn: lockBinding) {
                        SettingRow(symbol: lock.methodSymbol, title: "Lock with \(lock.methodName)")
                    }
                    .disabled(!lock.canUseDeviceAuth && !faceLock)
                    Toggle(isOn: $maskOnLaunch) {
                        SettingRow(symbol: "eye.slash", title: "Hide amounts when opening")
                    }
                    if FirebaseBoot.isConfigured {
                        Toggle(isOn: analyticsBinding) {
                            SettingRow(symbol: "chart.bar.xaxis", title: "Share anonymous usage statistics")
                        }
                    }
                } header: { Text("Privacy") } footer: {
                    if FirebaseBoot.isConfigured {
                        Text("Your entries stay on this device and in your private iCloud. Usage statistics never include amounts, notes or names.")
                    } else {
                        Text("No account, no sign-in. Your data stays on this device and in your private iCloud.")
                    }
                }

                Section {
                    Picker(selection: $themeRaw) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(verbatim: theme.title).tag(theme.rawValue)
                        }
                    } label: {
                        SettingRow(symbol: "circle.lefthalf.filled", title: "Appearance")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SettingRow(symbol: "paintpalette", title: "Accent")
                        HStack(spacing: 12) {
                            ForEach(InkAccent.allCases) { accent in
                                Button {
                                    if pro.isPro || accent == .vermilion {
                                        Haptic.tap()
                                        accentRaw = accent.rawValue
                                    } else {
                                        router.showPaywall = true
                                    }
                                } label: {
                                    ZStack {
                                        Circle().fill(accent.color).frame(width: 30, height: 30)
                                        if accentRaw == accent.rawValue && (pro.isPro || accent == .vermilion) {
                                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                        } else if !pro.isPro && accent != .vermilion {
                                            Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.9))
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(verbatim: accent.title))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: { Text("Look") }

                Section {
                    NavigationLink {
                        ShortcutsGuide()
                    } label: {
                        SettingRow(symbol: "wave.3.right", title: "Apple Pay auto-log & Siri")
                    }
                } header: { Text("Automation") }

                Section {
                    Button {
                        exportURL = Exporter.makeCSV(context: context)
                        Telemetry.event("csv_export")
                        showExport = exportURL != nil
                    } label: {
                        SettingRow(symbol: "square.and.arrow.up", title: "Export to CSV")
                    }
                    Button { showImport = true } label: {
                        SettingRow(symbol: "square.and.arrow.down", title: "Import from CSV")
                    }
                    HStack {
                        SettingRow(symbol: "icloud", title: "iCloud sync")
                        Spacer()
                        Text(verbatim: cloudStatus ?? "…")
                            .font(Typeface.detail)
                            .foregroundStyle(Ink.soft)
                    }
                } header: { Text("Your data") } footer: {
                    if StoreHub.mode != .cloud {
                        Text("Sync is paused: the iCloud store could not be opened, so changes are kept on this device only.")
                    }
                }

                Section {
                    NavigationLink {
                        HelpScreen()
                    } label: {
                        SettingRow(symbol: "questionmark.circle", title: "Help & questions")
                    }
                    Button {
                        if let url = URL(string: "mailto:\(AppConfig.supportEmail)?subject=Money%20List") { openURL(url) }
                    } label: {
                        SettingRow(symbol: "envelope", title: "Write to the developer")
                    }
                    Button { openURL(AppConfig.writeReview) } label: {
                        SettingRow(symbol: "star", title: "Rate Money List")
                    }
                    Button { openURL(AppConfig.developerPage) } label: {
                        SettingRow(symbol: "square.grid.2x2", title: "More apps")
                    }
                    Button { openURL(AppConfig.privacyURL) } label: {
                        SettingRow(symbol: "hand.raised", title: "Privacy policy")
                    }
                    Button { openURL(AppConfig.termsURL) } label: {
                        SettingRow(symbol: "doc.plaintext", title: "Terms of use")
                    }
                    if pro.isPro {
                        HStack {
                            SettingRow(symbol: "checkmark.seal", title: "Money List Pro")
                            Spacer()
                            Text("Unlocked").font(Typeface.detail).foregroundStyle(Ink.gain)
                        }
                    } else {
                        Button {
                            Task { await pro.restore() }
                        } label: {
                            SettingRow(symbol: "arrow.clockwise", title: "Restore purchase")
                        }
                    }
                } header: { Text("Support") } footer: {
                    Text(verbatim: versionText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                }

                #if DEBUG
                Section {
                    Button {
                        debugMessage = CloudSchemaPusher.push()
                    } label: {
                        Text(verbatim: "Push CloudKit schema (development)")
                    }
                    if let debugMessage {
                        Text(verbatim: debugMessage).font(Typeface.detail)
                    }
                } header: { Text(verbatim: "Developer") }
                #endif
            }
            .scrollContentBackground(.hidden)
            .paperBackground()
            .trackScreen("settings")
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showPlan) {
                SpendingPlanSheet().presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showExport) {
                if let exportURL { ShareSheet(items: [exportURL]) }
            }
            .sheet(isPresented: $showImport) {
                ImportFlow()
            }
            .paywallCover(.settings)
            .alert(Text("Purchase"), isPresented: Binding(get: { pro.errorMessage != nil }, set: { if !$0 { pro.errorMessage = nil } })) {
                Button("OK", role: .cancel) { pro.errorMessage = nil }
            } message: {
                Text(verbatim: pro.errorMessage ?? "")
            }
            .task {
                cloudStatus = await CloudStatus.describe()
                notificationsDenied = await Reminders.authorizationStatus() == .denied
            }
        }
    }

    private var planSummary: String? {
        guard let plan = prefs.plan else { return prefs.startDay == 1 ? nil : String(localized: "from day \(prefs.startDay)") }
        return MoneyFormat.plain(plan, code: prefs.home, cents: false)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "Money List \(version) (\(build))"
    }

    // MARK: Bindings

    private var defaultAccountBinding: Binding<UUID?> {
        Binding(get: { profiles.first?.defaultAccountID }, set: { value in
            profiles.first?.defaultAccountID = value
            try? context.save()
        })
    }

    private var dailyBinding: Binding<Bool> {
        Binding(get: { dailyReminder }, set: { value in
            dailyReminder = value
            Task {
                if value, await Reminders.requestPermission() {
                    Reminders.scheduleDaily(minutesAfterMidnight: reminderMinutes)
                } else {
                    Reminders.cancelDaily()
                    if value { dailyReminder = false; notificationsDenied = true }
                }
            }
        })
    }

    private var reminderTime: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            reminderMinutes = (parts.hour ?? 21) * 60 + (parts.minute ?? 0)
            Reminders.scheduleDaily(minutesAfterMidnight: reminderMinutes)
        })
    }

    private var billBinding: Binding<Bool> {
        Binding(get: { billReminders }, set: { value in
            billReminders = value
            Task {
                if value { await Reminders.requestPermission() }
                await Upkeep.rescheduleBillReminders(context: context, rates: rates)
            }
        })
    }

    private var budgetAlertBinding: Binding<Bool> {
        Binding(get: { profiles.first?.notificationsEnabled ?? false }, set: { value in
            profiles.first?.notificationsEnabled = value
            try? context.save()
            if value { Task { await Reminders.requestPermission() } }
        })
    }

    private var analyticsBinding: Binding<Bool> {
        Binding(
            get: { analyticsAllowed },
            set: { allowed in
                analyticsAllowed = allowed
                Telemetry.setAllowed(allowed)
            }
        )
    }

    private var lockBinding: Binding<Bool> {
        Binding(get: { faceLock }, set: { value in
            if value {
                Task {
                    let ok = await lock.confirmAndEnable()
                    faceLock = ok
                }
            } else {
                lock.isEnabled = false
                faceLock = false
            }
        })
    }
}

struct SettingRow: View {
    let symbol: String
    let title: LocalizedStringKey
    var value: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Ink.text)
                .frame(width: 26)
            Text(title)
                .font(Typeface.body)
                .foregroundStyle(Ink.text)
            if let value {
                Spacer()
                Text(verbatim: value)
                    .font(Typeface.detail)
                    .foregroundStyle(Ink.soft)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Small Pro advertisement drawn in the receipt style.
struct ProTeaser: View {
    @Environment(\.inkAccent) private var accent

    var body: some View {
        HStack(spacing: 14) {
            LedgerMark(size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("Money List Pro")
                    .font(Typeface.heading)
                    .foregroundStyle(Ink.text)
                Text("No ads, no limits, receipts and colors. Paid once.")
                    .font(Typeface.detail)
                    .foregroundStyle(Ink.soft)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Ink.faint)
        }
        .paperCard(padding: 14, raised: true)
    }
}

enum CloudStatus {
    static func describe() async -> String {
        if StoreHub.mode != .cloud { return String(localized: "Off") }
        do {
            let status = try await CKContainer(identifier: StoreHub.cloudContainerID).accountStatus()
            switch status {
            case .available: return String(localized: "On")
            case .noAccount: return String(localized: "Not signed in")
            case .restricted: return String(localized: "Restricted")
            case .temporarilyUnavailable: return String(localized: "Unavailable")
            default: return String(localized: "Unknown")
            }
        } catch {
            return String(localized: "Unknown")
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
