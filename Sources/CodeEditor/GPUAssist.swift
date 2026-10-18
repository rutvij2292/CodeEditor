import AppKit
import QuartzCore

/// Optional asynchronous drawing (`CALayer.drawsAsynchronously`) for the editor text view's backing layer, with a policy that
/// keeps it from ever costing energy or latency by default:
///  * `Prefs.gpuAssist` "off" never enables it; "on" always does; "auto" only for big files (> `autoMinLines`), never in
///    power saver, never while the window is occluded, and never once the rolling check found it slower than sync drawing.
///  * The rolling check compares the main-thread draw cost per drawn area (exponential moving averages) of the sync path
///    (baseline, sampled first) against the async path (trial). No timers: everything runs from `draw(_:)` and notifications.
/// Everything renders identically with it off.
enum GPUAssist {
    static let autoMinLines = 2000
    static let sampleCount = 24

    struct Inputs {
        var mode: String
        var lines: Int
        var powerSaver: Bool
        var occluded: Bool
        var selfDisabled: Bool
        var baselineReady = true
    }

    /// The whole gating policy, pure so it can be tested.
    static func decide(_ i: Inputs) -> Bool {
        switch i.mode {
        case "on": return true
        case "off": return false
        default: return i.lines > autoMinLines && !i.powerSaver && !i.occluded && !i.selfDisabled && i.baselineReady
        }
    }

    /// Per-view draw-cost bookkeeping.
    struct Check {
        private(set) var syncCost = 0.0, asyncCost = 0.0
        private(set) var syncN = 0, asyncN = 0
        private(set) var selfDisabled = false
        var baselineReady: Bool { syncN >= GPUAssist.sampleCount }

        /// `ms` of main-thread draw time for a dirty rect of `area` points squared.
        mutating func record(ms: Double, area: Double, async: Bool) {
            let c = ms / max(area, 10_000) * 100_000      // ms per 100k pt^2
            if async {
                asyncCost = asyncN == 0 ? c : asyncCost * 0.9 + c * 0.1
                asyncN += 1
                if asyncN >= GPUAssist.sampleCount, baselineReady, asyncCost > syncCost * 0.95 { selfDisabled = true }
            } else if !selfDisabled {
                syncCost = syncN == 0 ? c : syncCost * 0.9 + c * 0.1
                syncN += 1
            }
        }
        mutating func reset() { self = Check() }
    }
}

extension CodeTextView {
    /// Re-evaluates the policy and flips `drawsAsynchronously` on the backing layer if needed.
    func updateGPUAssist() {
        guard let layer else { return }
        let inputs = GPUAssist.Inputs(mode: Prefs.gpuAssist, lines: folds.lineCount, powerSaver: PowerState.shared.saver,
                                      occluded: PowerState.windowHidden(self), selfDisabled: gpuCheck.selfDisabled,
                                      baselineReady: gpuCheck.baselineReady)
        let want = GPUAssist.decide(inputs)
        if layer.drawsAsynchronously != want { layer.drawsAsynchronously = want }
    }

    var gpuAssistActive: Bool { layer?.drawsAsynchronously ?? false }
}
