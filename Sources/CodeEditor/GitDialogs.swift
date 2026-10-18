import AppKit

/// Alert builders of the Git panel. They only construct the alerts, so callers decide whether to run them
/// as a sheet or modally (and tests can render them without showing anything).
enum GitDialogs {
    static let skipPushPreviewKey = "CodeEditor.git.skipPushPreview"
    static var skipPushPreview: Bool {
        get { UserDefaults.standard.bool(forKey: skipPushPreviewKey) }
        set { UserDefaults.standard.set(newValue, forKey: skipPushPreviewKey) }
    }

    private static func listScroll(_ lines: [NSAttributedString], width: CGFloat, height: CGFloat) -> NSScrollView {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 4, height: 4)
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        let all = NSMutableAttributedString()
        for (i, l) in lines.enumerated() { all.append(l); if i < lines.count - 1 { all.append(NSAttributedString(string: "\n")) } }
        tv.textStorage?.setAttributedString(all)
        let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        sv.documentView = tv
        sv.hasVerticalScroller = true
        sv.borderType = .bezelBorder
        return sv
    }

    private static func mono(_ text: String, color: NSColor = .labelColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: color])
    }

    /// Push confirmation: the commits that will be pushed. Force-push is deliberately not offered.
    static func pushAlert(_ p: GitPushPreview) -> (alert: NSAlert, dontAsk: NSButton) {
        let alert = NSAlert()
        let target = p.upstream ?? p.remote.map { "\($0)/\(p.branch)" } ?? p.branch
        alert.messageText = "Push \(p.branch) to \(target)?"
        let width: CGFloat = 460
        let listHeight: CGFloat = p.commits.isEmpty ? 36 : min(170, CGFloat(p.commits.count) * 15 + 12)
        var lines: [NSAttributedString] = []
        for c in p.commits { lines.append(mono("\(c.shortHash)  \(c.subject)")) }
        if p.commits.isEmpty { lines = [mono("Nothing new to push.", color: .secondaryLabelColor)] }
        let header = NSTextField(wrappingLabelWithString: p.newBranch
            ? "New branch will be pushed to \(p.remote ?? "origin")" + (p.commits.isEmpty ? "." : " with \(p.commits.count)\(p.commits.count >= 200 ? "+" : "") commit\(p.commits.count == 1 ? "" : "s"):")
            : "\(p.commits.count) commit\(p.commits.count == 1 ? "" : "s") will be pushed:")
        header.font = .systemFont(ofSize: 12, weight: .medium)
        let scroll = listScroll(lines, width: width, height: listHeight)
        let check = NSButton(checkboxWithTitle: "Don't ask again", target: nil, action: nil)
        check.font = .systemFont(ofSize: 11)
        let total = 18 + 8 + listHeight + 8 + 20
        let box = NSView(frame: NSRect(x: 0, y: 0, width: width, height: total))
        header.frame = NSRect(x: 0, y: total - 18, width: width, height: 18)
        scroll.frame = NSRect(x: 0, y: 28, width: width, height: listHeight)
        check.frame = NSRect(x: 0, y: 0, width: width, height: 20)
        for v in [header, scroll, check] { box.addSubview(v) }
        alert.accessoryView = box
        alert.addButton(withTitle: "Push")
        alert.addButton(withTitle: "Cancel")
        return (alert, check)
    }

    /// Rollback confirmation listing the files; untracked ones go to the Trash.
    static func rollbackAlert(tracked: [String], untracked: [String]) -> NSAlert {
        let alert = NSAlert()
        let n = tracked.count + untracked.count
        alert.messageText = "Roll back \(n) file\(n == 1 ? "" : "s")?"
        alert.informativeText = (tracked.isEmpty ? "" : "Changes to tracked files are reverted to the last commit and cannot be undone. ")
            + (untracked.isEmpty ? "" : "Untracked files are moved to the Trash.")
        var lines: [NSAttributedString] = []
        for p in tracked { lines.append(mono("M  " + p)) }
        for p in untracked { lines.append(mono("U  " + p + "   \u{2192} Trash", color: .secondaryLabelColor)) }
        let height = min(170, CGFloat(lines.count) * 15 + 12)
        alert.accessoryView = listScroll(lines, width: 460, height: height)
        alert.addButton(withTitle: "Rollback")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        return alert
    }

    static func stashAlert() -> (alert: NSAlert, message: NSTextField, untracked: NSButton) {
        let alert = NSAlert()
        alert.messageText = "Stash Changes"
        alert.informativeText = "Save the local changes and restore a clean working tree."
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 56))
        let field = NSTextField(frame: NSRect(x: 0, y: 32, width: 300, height: 22))
        field.placeholderString = "Message (optional)"
        let check = NSButton(checkboxWithTitle: "Include untracked files", target: nil, action: nil)
        check.frame = NSRect(x: 0, y: 4, width: 300, height: 20)
        box.addSubview(field)
        box.addSubview(check)
        alert.accessoryView = box
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Stash")
        alert.addButton(withTitle: "Cancel")
        return (alert, field, check)
    }

    static func confirmAlert(title: String, info: String, button: String, destructive: Bool = false) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = destructive
        return alert
    }

    static func textAlert(title: String, info: String, placeholder: String, button: String) -> (alert: NSAlert, field: NSTextField) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        return (alert, field)
    }
}
