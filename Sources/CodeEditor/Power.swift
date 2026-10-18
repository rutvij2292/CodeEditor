import AppKit
import IOKit.ps

/// Power awareness. "Power saver" is active when `Prefs.powerSaver == "always"`, or in "auto" when Low Power Mode is on, the
/// thermal state is serious/critical, or the Mac is on battery at or below 20 %. Features ask `PowerState.shared` for
/// scaled debounce delays and whether nice-to-haves (inline blame, live git-gutter diff, rainbow recolouring, occurrence
/// highlight, symbol scans) should run. Everything is event-driven: no polling timers.
final class PowerState {
    static let shared = PowerState()
    /// Posted (main thread) when `saver` flips.
    static let didChange = Notification.Name("CodeEditor.powerSaverDidChange")

    private(set) var lowPowerMode = false
    private(set) var thermalSerious = false
    private(set) var onBattery = false
    private(set) var batteryPercent = 100
    private(set) var saver = false
    private var started = false
    private var source: CFRunLoopSource?
    /// Tests: pretend the machine is in this state when non-nil.
    var simulated: Bool? { didSet { recompute() } }

    func start() {
        guard !started else { return }
        started = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(changed), name: .NSProcessInfoPowerStateDidChange, object: nil)
        nc.addObserver(self, selector: #selector(changed), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(changed), name: Prefs.didChange, object: nil)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<PowerState>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { me.changed() }
        }, ctx)?.takeRetainedValue() {
            source = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        }
        recompute()
    }

    @objc private func changed() { recompute() }

    private func readBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            if (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType {
                onBattery = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
                let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 100, max = d[kIOPSMaxCapacityKey] as? Int ?? 100
                batteryPercent = max > 0 ? cur * 100 / max : 100
                return
            }
        }
        onBattery = false
        batteryPercent = 100
    }

    func recompute() {
        let pi = ProcessInfo.processInfo
        lowPowerMode = pi.isLowPowerModeEnabled
        thermalSerious = pi.thermalState == .serious || pi.thermalState == .critical
        readBattery()
        let new: Bool
        if let simulated { new = simulated } else {
            switch Prefs.powerSaver {
            case "always": new = true
            case "off": new = false
            default: new = lowPowerMode || thermalSerious || (onBattery && batteryPercent <= 20)
            }
        }
        guard new != saver else { return }
        saver = new
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Debounce / delay stretched 2.5x while saving power.
    func scaled(_ seconds: TimeInterval) -> TimeInterval { saver ? seconds * 2.5 : seconds }

    /// Background worker cap: cores - 1, or half the cores on battery / in saver mode.
    var maxWorkers: Int {
        let n = ProcessInfo.processInfo.activeProcessorCount
        return saver || onBattery ? max(1, n / 2) : max(1, n - 1)
    }

    /// Seconds without an open file of a language before its server is shut down.
    var languageServerIdleTimeout: TimeInterval { saver ? 180 : 600 }

    static var liveBlame: Bool { !shared.saver }
    static var liveGitDiff: Bool { !shared.saver }
}
