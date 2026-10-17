import SwiftUI
import SwiftData

/// Settings that most screens need, derived from the synced profile.
nonisolated struct MoneyPrefs: Equatable {
    var home: String = "USD"
    var startDay: Int = 1
    var plan: Decimal? = nil
    var defaultAccountID: UUID? = nil

    var periods: PeriodCalendar { PeriodCalendar(startDay: startDay) }
}

private struct MoneyPrefsKey: EnvironmentKey {
    nonisolated static let defaultValue = MoneyPrefs()
}

extension EnvironmentValues {
    var moneyPrefs: MoneyPrefs {
        get { self[MoneyPrefsKey.self] }
        set { self[MoneyPrefsKey.self] = newValue }
    }
}

struct RootScene: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Environment(RateBook.self) private var rates
    @Environment(ProPass.self) private var pro
    @Environment(AdPacer.self) private var ads
    @Environment(LockKeeper.self) private var lock
    @Environment(Router.self) private var router

    @Query private var profiles: [UserProfile]

    @AppStorage(AppConfig.Keys.onboarded) private var onboarded = false
    @AppStorage(AppConfig.Keys.theme) private var themeRaw = AppTheme.system.rawValue
    @AppStorage(AppConfig.Keys.accent) private var accentRaw = InkAccent.vermilion.rawValue
    @AppStorage(AppConfig.Keys.maskAmounts) private var maskAmounts = false
    @AppStorage(AppConfig.Keys.maskOnLaunch) private var maskOnLaunch = false
    @AppStorage(AppConfig.Keys.whatsNewSeen) private var whatsNewSeen = false

    @State private var showWhatsNew = false
    @State private var pendingWhatsNew = false
    @State private var booted = false
    /// Free users get the Pro screen each time they open the app (`paywall_on_open`).
    @State private var openPaywallPending = false
    @State private var openPaywallReason = "launch"
    @State private var backgroundedAt: Date?
    @State private var linkOpenedAt: Date?
    /// Seconds of the opening scene for this launch (nil once it has played or when switched off).
    @State private var splashSeconds: Double? = RootScene.splashLength()

    private static func splashLength() -> Double? {
        RemoteDials.shared.bool(.splashEnabled) ? RemoteDials.shared.double(.splashSeconds) : nil
    }

    private var prefs: MoneyPrefs {
        let profile = profiles.first
        return MoneyPrefs(
            home: profile?.defaultCurrencyCode ?? Locale.current.currency?.identifier ?? "USD",
            startDay: profile?.periodStartDay ?? 1,
            plan: profile?.monthlyPlan,
            defaultAccountID: profile?.defaultAccountID
        )
    }

    private var accent: InkAccent {
        let chosen = InkAccent(rawValue: accentRaw) ?? .vermilion
        return pro.isPro ? chosen : .vermilion
    }

    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            if onboarded {
                MainShell()
                    .transition(.opacity)
            } else {
                WelcomeFlow {
                    withAnimation(.easeInOut(duration: 0.35)) { onboarded = true }
                    whatsNewSeen = true
                    Task { await Upkeep.run(context: context, rates: rates, force: true) }
                    if !pro.isPro && RemoteDials.shared.bool(.paywallAfterOnboarding) && !UserDefaults.standard.bool(forKey: AppConfig.Keys.paywallShownOnce) {
                        UserDefaults.standard.set(true, forKey: AppConfig.Keys.paywallShownOnce)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { router.showPaywall = true }
                    }
                }
                .transition(.opacity)
            }

            if lock.isLocked && onboarded && splashSeconds == nil {
                LockCover()
                    .transition(.opacity)
                    .zIndex(3)
            } else if phase != .active && lock.isEnabled && onboarded {
                PrivacyCover()
                    .zIndex(2)
            }

            if let seconds = splashSeconds {
                SplashView(duration: seconds) { endSplash() }
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .environment(\.moneyPrefs, prefs)
        .environment(\.masksAmounts, maskAmounts)
        .environment(\.inkAccent, accent.color)
        .tint(accent.color)
        .preferredColorScheme((AppTheme(rawValue: themeRaw) ?? .system).scheme)
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewSheet()
                .presentationDragIndicator(.visible)
        }
        .paywallCover(.root)
        .onOpenURL { url in
            // Opened from a widget or a link: go straight to the point.
            linkOpenedAt = Date()
            openPaywallPending = false
            if splashSeconds != nil { endSplash() }
            router.open(url)
        }
        .task {
            guard !booted else { return }
            booted = true
            Task { await RemoteDials.shared.start() }
            if maskOnLaunch { maskAmounts = true }
            if onboarded {
                openPaywallReason = "launch"
                openPaywallPending = true
                Seeder.seedIfEmpty(context: context, currency: prefs.home)
                if !whatsNewSeen {
                    whatsNewSeen = true
                    if splashSeconds == nil {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        showWhatsNew = true
                    } else {
                        pendingWhatsNew = true
                    }
                }
            }
            await pro.refresh()
            Telemetry.describe(
                isPro: pro.isPro,
                home: prefs.home,
                hasPlan: prefs.plan != nil,
                accounts: (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
            )
            await Upkeep.run(context: context, rates: rates, force: true)
            if !pro.isPro { ads.preload() }
        }
        .onChange(of: phase) { _, newPhase in
            switch newPhase {
            case .background:
                lock.lockIfNeeded()
                if maskOnLaunch { maskAmounts = true }
                backgroundedAt = Date()
            case .active:
                if lock.isLocked { Task { await lock.unlock() } }
                Task { await Upkeep.run(context: context, rates: rates) }
                if let since = backgroundedAt {
                    backgroundedAt = nil
                    if onboarded && Date().timeIntervalSince(since) >= AppConfig.paywallReturnMinutes * 60 {
                        openPaywallReason = "return"
                        openPaywallPending = true
                        schedulePaywallCheck()
                    }
                }
            default:
                break
            }
        }
        .onChange(of: lock.isLocked) { _, locked in
            if !locked { schedulePaywallCheck() }
        }
        .onChange(of: pro.checked) { _, done in
            if done { schedulePaywallCheck() }
        }
    }
}

extension RootScene {
    private func endSplash() {
        withAnimation(.easeOut(duration: 0.25)) { splashSeconds = nil }
        if pendingWhatsNew {
            pendingWhatsNew = false
            showWhatsNew = true
        }
        schedulePaywallCheck(after: 0.45)
    }

    /// A short pause lets a widget or link that opened the app arrive first.
    private func schedulePaywallCheck(after seconds: Double = 0.6) {
        guard openPaywallPending else { return }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            presentOpenPaywallIfNeeded()
        }
    }

    private func presentOpenPaywallIfNeeded() {
        guard openPaywallPending else { return }
        // Wait for the opening scene, Face ID and the App Store check.
        guard onboarded, splashSeconds == nil, !lock.isLocked, pro.checked,
              UIApplication.shared.applicationState == .active else {
            paywallLog("waiting (splash, Face ID or App Store check)")
            return
        }
        openPaywallPending = false
        if pro.isPro { return paywallLog("skipped: Pro is active on this device") }
        if !AppConfig.paywallOnOpen { return paywallLog("skipped: paywall_on_open = false") }
        if router.showPaywall { return paywallLog("skipped: already open") }
        if showWhatsNew || pendingWhatsNew { return paywallLog("skipped: What's New is showing") }
        // Opened from a widget or a link: let the person do what they came for.
        if let opened = linkOpenedAt, Date().timeIntervalSince(opened) < 5 { return paywallLog("skipped: opened from a link") }
        // Never cover a sheet, alert or share sheet that is already open.
        if UIApplication.shared.isPresentingModal { return paywallLog("skipped: another window is open") }
        paywallLog("showing (\(openPaywallReason))")
        router.showPaywall = true
        Telemetry.event("paywall_auto", ["when": openPaywallReason])
    }

    private func paywallLog(_ message: String) {
        #if DEBUG
        print("Money List paywall: \(message)")
        #endif
    }
}

extension UIApplication {
    /// True while a sheet, cover, alert, share sheet or ad is on screen.
    var isPresentingModal: Bool {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        return window?.rootViewController?.presentedViewController != nil
    }
}

/// Shown over the app while it is locked.
struct LockCover: View {
    @Environment(LockKeeper.self) private var lock
    @Environment(\.inkAccent) private var accent

    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            VStack(spacing: 22) {
                LedgerMark(size: 74)
                VStack(spacing: 6) {
                    Text("Money List is locked")
                        .font(Typeface.title)
                        .foregroundStyle(Ink.text)
                    Text("Your notes stay private until you unlock.")
                        .font(Typeface.label)
                        .foregroundStyle(Ink.soft)
                }
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label(String(localized: "Unlock with \(lock.methodName)"), systemImage: lock.methodSymbol)
                }
                .buttonStyle(InkButtonStyle(kind: .solid, compact: true))
                .disabled(lock.isAuthenticating)
            }
            .padding(32)
        }
        .task { await lock.unlock() }
    }
}

/// Hides balances in the app switcher when the lock is on.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            LedgerMark(size: 64)
        }
    }
}
