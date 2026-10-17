import Foundation
import Observation
import StoreKit

/// One-time "Money List Pro" unlock via StoreKit 2.
@Observable
final class ProPass {

    private(set) var isPro: Bool
    /// True once the App Store entitlements have been read in this launch.
    private(set) var checked = false
    private(set) var product: Product?
    private(set) var isWorking = false
    var errorMessage: String?

    @ObservationIgnored private var updates: Task<Void, Never>?

    init() {
        isPro = UserDefaults.standard.bool(forKey: AppConfig.Keys.proCache)
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                if AppConfig.isProProduct(transaction.productID) {
                    self?.setPro(transaction.revocationDate == nil)
                }
                await transaction.finish()
            }
        }
    }

    var priceText: String? { product?.displayPrice }

    func loadProduct() async {
        guard product == nil else { return }
        do {
            product = try await Product.products(for: [AppConfig.proProductID]).first
        } catch {
            print("Money List: product load failed — \(error)")
        }
    }

    /// Returns true when Pro is unlocked after the purchase sheet closes.
    @discardableResult
    func purchase() async -> Bool {
        if product == nil { await loadProduct() }
        guard let product else {
            errorMessage = String(localized: "The App Store is not reachable right now. Please try again later.")
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            Telemetry.event("pro_purchase_start")
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    setPro(true)
                    await transaction.finish()
                    Telemetry.event("pro_purchase", ["result": "success"])
                } else {
                    errorMessage = String(localized: "The purchase could not be verified.")
                    Telemetry.event("pro_purchase", ["result": "unverified"])
                }
            case .userCancelled:
                Telemetry.event("pro_purchase", ["result": "cancelled"])
            case .pending:
                Telemetry.event("pro_purchase", ["result": "pending"])
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
            Telemetry.event("pro_purchase", ["result": "failed"])
        }
        return isPro
    }

    func restore() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
        Telemetry.event("pro_restore", ["found": isPro])
        if !isPro && errorMessage == nil {
            errorMessage = String(localized: "No previous purchase was found for this Apple Account.")
        }
    }

    func refresh() async {
        var owned = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if AppConfig.isProProduct(transaction.productID) && transaction.revocationDate == nil {
                owned = true
            }
        }
        setPro(owned)
        checked = true
    }

    private func setPro(_ value: Bool) {
        isPro = value
        UserDefaults.standard.set(value, forKey: AppConfig.Keys.proCache)
    }

    // MARK: Limits

    func allows(accounts count: Int) -> Bool { isPro || count < AppConfig.Free.accounts }
    func allows(budgets count: Int) -> Bool { isPro || count < AppConfig.Free.budgets }
    func allows(goals count: Int) -> Bool { isPro || count < AppConfig.Free.goals }
    func allows(bills count: Int) -> Bool { isPro || count < AppConfig.Free.bills }
    func allows(holdings count: Int) -> Bool { isPro || count < AppConfig.Free.holdings }
    func allows(customCategories count: Int) -> Bool { isPro || count < AppConfig.Free.customCategories }
}
