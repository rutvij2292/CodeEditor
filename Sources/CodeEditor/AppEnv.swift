import Foundation

enum AppEnv {
    /// Verification runs (CE_SNAPSHOT / CE_SELFTEST) never show windows, steal focus or touch saved state.
    static let headless = ProcessInfo.processInfo.environment["CE_SNAPSHOT"] != nil
        || ProcessInfo.processInfo.environment["CE_SELFTEST"] != nil
    static func value(_ key: String) -> String? { ProcessInfo.processInfo.environment[key] }
}
