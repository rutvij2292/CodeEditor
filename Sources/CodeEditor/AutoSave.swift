import Foundation

/// Auto-save policy. Settings live in UserDefaults (`autoSaveOnFocusLoss`, `autoSaveOnTabSwitch`, `autoSaveIdleSeconds`);
/// a menu toggle sets the static vars below, which post `AutoSave.didChange`.
enum AutoSave {
    static let didChange = Notification.Name("AutoSaveSettingsDidChange")
    /// Swappable so tests never touch the real preferences.
    static var defaults = UserDefaults.standard

    static var focusLossEnabled: Bool {
        get { defaults.object(forKey: "autoSaveOnFocusLoss") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoSaveOnFocusLoss"); NotificationCenter.default.post(name: didChange, object: nil) }
    }
    static var tabSwitchEnabled: Bool {
        get { defaults.object(forKey: "autoSaveOnTabSwitch") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoSaveOnTabSwitch"); NotificationCenter.default.post(name: didChange, object: nil) }
    }
    /// 0 = off (default).
    static var idleSeconds: Double {
        get { max(0, defaults.object(forKey: "autoSaveIdleSeconds") as? Double ?? 0) }
        set { defaults.set(max(0, newValue), forKey: "autoSaveIdleSeconds"); NotificationCenter.default.post(name: didChange, object: nil) }
    }

    enum Trigger { case focusLoss, tabSwitch, idle }

    static func enabled(for trigger: Trigger) -> Bool {
        switch trigger {
        case .focusLoss: return focusLossEnabled
        case .tabSwitch: return tabSwitchEnabled
        case .idle: return idleSeconds > 0
        }
    }

    enum Outcome: Equatable {
        case saved
        /// A will-save hook (formatter) is still working; the write follows when it proceeds.
        case pending
        case skipped(String)
    }
}
