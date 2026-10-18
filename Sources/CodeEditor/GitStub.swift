import AppKit

// PLACEHOLDER until the git agent's Git*.swift files are merged (then delete this file).
struct GitChange { let path: String; let index: Character; let work: Character
    var isConflict: Bool { false }; var isUntracked: Bool { work == "?" }; var isStaged: Bool { index != " " && index != "?" } }
final class GitRepo {
    let root: URL
    static func repoRoot(for url: URL) -> URL? { nil }
    init(root: URL) { self.root = root }
    func statusMap() throws -> [String: GitChange] { [:] }
}
final class GitPanelController: NSObject {
    let view = NSView()
    var onStatusChange: (() -> Void)?
    init(root: URL, openFile: @escaping (URL) -> Void) {}
    func reload() {}
    func focusCommitMessage() {}
}
