import Foundation

/// Automatic ledger entry for every commit: right after a commit succeeds, the commit is written to the ledger (message, files,
/// line counts) and Claude Code (the user's own login, no API key) adds a plain-language summary of what the change does overall.
/// No review step. Nothing runs until a commit happens; if Claude is missing or fails, the entry keeps the commit message as its note.
enum CommitLedger {
    static let diffCap = 40_000

    static func prompt(subject: String, body: String, stat: String, diff: String) -> String {
        """
        You are writing a changelog entry for a developer's personal "ledger": a memory of what each commit did, to be read months later by someone who does not remember the code.
        Explain, in plain language, what this commit achieves overall: the feature or fix, how the behaviour changes for users or other parts of the app, and why it was probably needed. Name the main concepts (screens, features, business rules, data) rather than methods, variables or file names. Avoid code and jargon.
        Format: 2 to 5 short sentences, or up to 5 short "- " bullets if the commit touches several unrelated things. No heading, no preamble, no code fences, no markdown other than the dashes.

        Commit message:
        \(subject)
        \(body)

        Files changed:
        \(stat)

        Diff:
        \(diff)
        """
    }

    /// Files from `git show --numstat --format=` output ("added<TAB>removed<TAB>path"; "-" for binary files).
    static func files(fromNumstat out: String) -> [LedgerFile] {
        out.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard p.count == 3 else { return nil }
            return LedgerFile(rel: String(p[2]), added: Int(p[0]) ?? 0, removed: Int(p[1]) ?? 0, symbols: [])
        }
    }

    /// Records HEAD of `repo` in `ledger`, then fills in the summary. `ledger` is touched on the main queue only.
    static func record(repo: GitRepo, ledger: @escaping () -> ChangeLedger?, summarize: Bool = true) {
        DispatchQueue.global(qos: .utility).async {
            guard let hash = (try? repo.text(["rev-parse", "HEAD"]))?.trimmingCharacters(in: .whitespacesAndNewlines), !hash.isEmpty else { return }
            let message = ((try? repo.text(["show", "-s", "--format=%B", "HEAD"])) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = message.components(separatedBy: "\n").first ?? ""
            let body = message.dropFirst(subject.count).trimmingCharacters(in: .whitespacesAndNewlines)
            let numstat = (try? repo.text(["show", "--numstat", "--format=", "HEAD"])) ?? ""
            let files = Self.files(fromNumstat: numstat)
            var diff = (try? repo.text(["show", "--format=", "--patch", "HEAD"])) ?? ""
            if diff.utf8.count > diffCap { diff = String(decoding: Array(diff.utf8.prefix(diffCap)), as: UTF8.self) + "\n[diff truncated]" }
            let id = "commit-" + hash, short = String(hash.prefix(7))
            let title = subject.isEmpty ? "Commit \(short)" : subject
            DispatchQueue.main.async {
                guard let l0 = ledger() else { return }
                l0.record(id: id, title: title, started: Date(), files: files, note: body, now: Date())
                guard summarize, ClaudeCLI.executable() != nil else { return }
                let p = prompt(subject: subject, body: body, stat: numstat, diff: diff)
                _ = ClaudeCLI.run(prompt: p, model: "haiku", completion: { result in
                    guard case .success(let raw) = result else { return }
                    let text = ClaudeCLI.cleanCommitMessage(raw)
                    guard !text.isEmpty, let l = ledger() else { return }
                    // Only replace the fallback note: never over something the user already typed.
                    if let s = l.sessions.first(where: { $0.id == id }), s.note == body { l.setNote(text, for: id) }
                })
            }
        }
    }
}
