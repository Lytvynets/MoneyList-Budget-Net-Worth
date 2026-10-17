import Foundation
import LocalAuthentication
import Observation

/// Face ID / Touch ID / passcode lock. Locked from cold launch when enabled,
/// re-locks when the app goes to the background.
@Observable
final class LockKeeper {
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false

    init() {
        isLocked = UserDefaults.standard.bool(forKey: AppConfig.Keys.faceLock)
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: AppConfig.Keys.faceLock) }
        set {
            UserDefaults.standard.set(newValue, forKey: AppConfig.Keys.faceLock)
            if !newValue { isLocked = false }
        }
    }

    var canUseDeviceAuth: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return String(localized: "Passcode")
        }
    }

    var methodSymbol: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.fill"
        }
    }

    func lockIfNeeded() {
        if isEnabled { isLocked = true }
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            // No passcode on the device any more: don't trap the person outside.
            isLocked = false
            return
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Unlock your money notes"))
            if ok { isLocked = false }
        } catch {
            isLocked = true
        }
    }

    /// Confirms identity before turning the lock on.
    func confirmAndEnable() async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Turn on app lock"))
            if ok { isEnabled = true }
            return ok
        } catch {
            return false
        }
    }
}
