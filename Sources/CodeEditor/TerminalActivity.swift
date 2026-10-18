import AppKit

/// "An agent finished" detection for terminal tabs (pure state machine; time is passed in so tests use a fake clock).
///
/// A tab that produced output while nobody was watching it becomes *pending*; once it stays quiet for `idleSeconds`
/// it is *done*. A BEL (Claude Code rings it when it wants attention) marks it done immediately. Looking at the tab clears it.
struct TerminalIdleTracker {
    var idleSeconds: TimeInterval = 4
    private struct State { var lastOutput = Date.distantPast; var pending = false; var done = false }
    private var states: [Int: State] = [:]

    var anyPending: Bool { states.values.contains { $0.pending } }
    var doneIDs: [Int] { states.filter { $0.value.done }.map(\.key).sorted() }
    func isDone(_ id: Int) -> Bool { states[id]?.done ?? false }
    func isPending(_ id: Int) -> Bool { states[id]?.pending ?? false }

    /// Output arrived. `watched`: the user is looking at this tab right now (visible, app active).
    mutating func output(_ id: Int, at now: Date, watched: Bool) {
        if watched { states[id] = nil; return }
        var s = states[id] ?? State()
        if s.done { return }   // stays done until the user looks at the tab
        s.lastOutput = now; s.pending = true
        states[id] = s
    }

    /// BEL. Returns true when the tab newly became done.
    @discardableResult
    mutating func bell(_ id: Int, watched: Bool) -> Bool {
        if watched { return false }
        var s = states[id] ?? State()
        let was = s.done
        s.done = true; s.pending = false
        states[id] = s
        return !was
    }

    /// Advances the clock; returns the tabs that just turned done.
    mutating func tick(at now: Date) -> [Int] {
        var fired: [Int] = []
        for (id, s) in states where s.pending && now.timeIntervalSince(s.lastOutput) >= idleSeconds {
            var n = s; n.pending = false; n.done = true
            states[id] = n
            fired.append(id)
        }
        return fired.sorted()
    }

    mutating func clear(_ id: Int) { states[id] = nil }
}

/// Dock tile badge + dock bounce. No notification-centre permission is needed (and none is requested).
enum TerminalNotifier {
    /// Tests replace this; `nil` uses the real dock tile (never in headless runs).
    static var sink: ((_ badge: String?, _ requestAttention: Bool) -> Void)?

    static func update(doneCount: Int, newlyDone: Bool) {
        let badge = doneCount > 0 ? String(doneCount) : nil
        if let sink { sink(badge, newlyDone && !appIsActive()); return }
        guard !AppEnv.headless else { return }
        NSApp.dockTile.badgeLabel = badge
        if newlyDone, !appIsActive() { NSApp.requestUserAttention(.informationalRequest) }
    }

    static var appIsActive: () -> Bool = { NSApp?.isActive ?? false }
}
