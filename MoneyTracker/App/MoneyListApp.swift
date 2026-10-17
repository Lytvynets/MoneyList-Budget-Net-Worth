import SwiftUI
import SwiftData

@main
struct MoneyListApp: App {
    @State private var rates = RateBook()
    @State private var pro = ProPass()
    @State private var ads = AdPacer()
    @State private var lock = LockKeeper()
    @State private var toasts = ToastCenter()
    @State private var router = Router()

    init() {
        FirebaseBoot.configure()
        AdKit.start()
    }

    var body: some Scene {
        WindowGroup {
            RootScene()
                .environment(rates)
                .environment(pro)
                .environment(ads)
                .environment(lock)
                .environment(toasts)
                .environment(router)
        }
        .modelContainer(StoreHub.container)
    }
}

/// Cross-screen navigation requests (deep links, widgets, Siri, onboarding).
@Observable
final class Router {
    enum Tab: Hashable { case today, ledger, plan, wealth }

    var tab: Tab = .today
    var composer: ComposerRequest?
    var showSettings = false
    var showPaywall = false

    /// SwiftUI shows one modal per level, so the Pro screen is hosted by the
    /// root view and by each sheet that can ask for it; the open sheet wins.
    nonisolated enum PaywallLayer: Hashable { case root, settings, composer }

    var paywallLayer: PaywallLayer {
        if composer != nil { return .composer }
        if showSettings { return .settings }
        return .root
    }

    func open(_ url: URL) {
        guard url.scheme == AppConfig.urlScheme else { return }
        Telemetry.event("deep_link", ["target": url.host ?? "none"])
        switch url.host ?? "" {
        case "compose", "add": composer = ComposerRequest()
        case "income": composer = ComposerRequest(kind: .income)
        case "today": tab = .today
        case "ledger": tab = .ledger
        case "plan", "bills": tab = .plan
        case "wealth": tab = .wealth
        case "settings": showSettings = true
        default: break
        }
    }
}

/// Opens the composer, optionally pre-filled.
struct ComposerRequest: Identifiable {
    let id = UUID()
    var kind: EntryKind = .expense
    var editing: Transaction? = nil
    var prefill: QuickLine? = nil
    var categoryID: UUID? = nil
    var accountID: UUID? = nil
}
