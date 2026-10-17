import Foundation
#if canImport(FirebaseCore)
import FirebaseCore
#endif

/// Starts Firebase when the app bundle has a GoogleService-Info.plist.
/// Without that file the app runs as before: statistics stay off and
/// remote settings use their built-in defaults.
enum FirebaseBoot {

    private(set) static var isConfigured = false

    static func configure() {
        #if canImport(FirebaseCore)
        guard !isConfigured,
              Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else {
            #if DEBUG
            if !isConfigured { print("Money List: GoogleService-Info.plist is missing — Firebase stays off.") }
            #endif
            return
        }
        #if DEBUG
        FirebaseConfiguration.shared.setLoggerLevel(.warning)
        #else
        FirebaseConfiguration.shared.setLoggerLevel(.min)
        #endif
        FirebaseApp.configure()
        isConfigured = true
        Telemetry.applyPreferences()
        #endif
    }
}
