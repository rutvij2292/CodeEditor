import AppKit

/// CE_SNAPSHOT=1 CE_PICKER=branches|branch-actions|branch-search|branch-new|branch-dirty|branch-delete: headless renders of the
/// branch widget, popup, sheet and notices (see Verification.swift). Needs a Git folder as the project.
enum BranchVerification {
    static func isBranchPicker(_ p: String?) -> Bool { p?.hasPrefix("branch") == true }

    /// Called ~0.4 s after launch; waits for the Git root to resolve, then drives the UI.
    static func start(_ picker: String, _ w: ProjectWindow) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            switch picker {
            case "branches": w.showBranchPopup()
            case "branch-actions":
                w.showBranchPopup()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { BranchPopup.selectTitle("feature/login-form"); BranchPopup.pressRight() }
            case "branch-search":
                w.showBranchPopup()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { BranchPopup.type("log") }
            case "branch-new":
                w.branches.loadBranchList { _ in
                    w.branches.newBranch(from: nil)
                    NewBranchSheet.setName(AppEnv.value("CE_BRANCH_NAME") ?? "feature/login-form")
                }
            case "branch-dirty": w.branches.checkout("bugfix/null-pointer")
            case "branch-delete":
                w.branches.loadBranchList { _ in
                    if let e = w.branches.lastList.local.first(where: { $0.name == "feature/login-form" }) { w.branches.run(.delete, entry: e) }
                }
            default: break
            }
        }
    }

    /// Writes `<shot>_widget_light.png`, `_widget_dark.png` and the picker-specific popup / sheet / notice render.
    static func finish(_ picker: String, shot: String, _ w: ProjectWindow) {
        func path(_ suffix: String) -> String { shot.replacingOccurrences(of: ".png", with: "_\(suffix).png") }
        w.branches.widget.snapshot(to: path("widget_light"), dark: false)
        w.branches.widget.snapshot(to: path("widget_dark"), dark: true)
        switch picker {
        case "branches", "branch-actions", "branch-search": BranchPopup.snapshot(to: path("popup"))
        case "branch-new": NewBranchSheet.snapshot(to: path("sheet"))
        default: if let v = BranchNotice.lastView { Verification.render(v, to: path("notice")) }
        }
        fputs("branch widget: \"\(w.branches.widget.branch)\" ahead \(w.branches.widget.ahead) behind \(w.branches.widget.behind) dirty \(w.branches.widget.dirty) visible \(w.branches.widgetVisible)\n", stderr)
        fputs("popup rows: \(BranchPopup.shownTitles.joined(separator: " | "))\n", stderr)
        fputs("notice: \(BranchNotice.lastTitle) \(BranchNotice.lastButtons)\n", stderr)
    }
}
