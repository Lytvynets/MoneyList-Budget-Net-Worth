import SwiftUI
import UIKit
import GoogleMobileAds

/// Ads for the free version, kept out of the way: a banner at the end of long
/// screens and an occasional interstitial, never during first use.
enum AdKit {
    static func start() {
        MobileAds.shared.start()
    }
}

/// Decides when a full-screen ad is acceptable.
@Observable
final class AdPacer {
    @ObservationIgnored private var interstitial: InterstitialAd?
    @ObservationIgnored private var loading = false
    @ObservationIgnored private let delegateProxy = AdDelegateProxy()

    // Pacing comes from Remote Config (ads_interstitial_every_entries, …).
    private var minimumEntriesBetween: Int { RemoteDials.shared.int(.adsInterstitialEveryEntries) }
    private var minimumSecondsBetween: TimeInterval { RemoteDials.shared.double(.adsInterstitialMinSeconds) }
    private var graceDays: Double { RemoteDials.shared.double(.adsGraceDays) }

    init() {
        delegateProxy.onDismiss = { [weak self] in
            self?.interstitial = nil
            self?.preload()
        }
    }

    func preload() {
        guard AppConfig.interstitialsEnabled, interstitial == nil, !loading else { return }
        loading = true
        Task {
            do {
                let ad = try await InterstitialAd.load(with: AppConfig.interstitialUnitID, request: Request())
                ad.fullScreenContentDelegate = delegateProxy
                interstitial = ad
            } catch {
                print("Money List: interstitial not loaded — \(error.localizedDescription)")
            }
            loading = false
        }
    }

    /// Call after an entry was saved; shows an ad only when pacing allows.
    func entrySaved(isPro: Bool) {
        let defaults = UserDefaults.standard
        guard !isPro, AppConfig.interstitialsEnabled else { return }
        let count = defaults.integer(forKey: AppConfig.Keys.entriesSinceAd) + 1
        defaults.set(count, forKey: AppConfig.Keys.entriesSinceAd)

        let firstLaunch = defaults.object(forKey: AppConfig.Keys.firstLaunch) as? Date ?? Date()
        let lastShown = defaults.object(forKey: AppConfig.Keys.lastAdAt) as? Date ?? .distantPast
        let pastGrace = Date().timeIntervalSince(firstLaunch) > graceDays * 86_400
        let spaced = Date().timeIntervalSince(lastShown) > minimumSecondsBetween
        guard pastGrace, spaced, count >= minimumEntriesBetween else {
            preload()
            return
        }
        guard let ad = interstitial, let root = UIApplication.shared.topMostController else {
            preload()
            return
        }
        defaults.set(0, forKey: AppConfig.Keys.entriesSinceAd)
        defaults.set(Date(), forKey: AppConfig.Keys.lastAdAt)
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            ad.present(from: root)
            Telemetry.event("ad_interstitial_shown")
        }
    }
}

final class AdDelegateProxy: NSObject, FullScreenContentDelegate {
    var onDismiss: (() -> Void)?

    // The SDK may call these from any thread; hop to the main actor explicitly.
    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor [weak self] in self?.onDismiss?() }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor [weak self] in self?.onDismiss?() }
    }
}

/// Adaptive banner that collapses to zero height until an ad arrives.
struct InlineBanner: View {
    @State private var loaded = false
    @State private var width: CGFloat = 0

    var body: some View {
        if AppConfig.bannersEnabled {
            banner
        }
    }

    private var banner: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { _, newWidth in width = newWidth }
        }
        .frame(height: 0)
        .overlay(alignment: .top) {
            if width > 0 {
                let size = largeAnchoredAdaptiveBanner(width: width)
                BannerHost(size: size, loaded: $loaded)
                    .frame(width: size.size.width, height: size.size.height)
                    .opacity(loaded ? 1 : 0)
            }
        }
        .frame(height: loaded && width > 0 ? largeAnchoredAdaptiveBanner(width: width).size.height : 0)
        .animation(.easeOut(duration: 0.25), value: loaded)
    }
}

private struct BannerHost: UIViewRepresentable {
    let size: AdSize
    @Binding var loaded: Bool

    func makeCoordinator() -> Coordinator { Coordinator(loaded: $loaded) }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: size)
        banner.adUnitID = AppConfig.bannerUnitID
        banner.rootViewController = UIApplication.shared.topMostController
        banner.delegate = context.coordinator
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    final class Coordinator: NSObject, BannerViewDelegate {
        @Binding var loaded: Bool
        init(loaded: Binding<Bool>) { _loaded = loaded }

        nonisolated func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            Task { @MainActor in self.loaded = true }
        }

        nonisolated func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            Task { @MainActor in self.loaded = false }
        }
    }
}

extension UIApplication {
    var topMostController: UIViewController? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
