import Foundation

/// One-shot `claude -p` runs through the user's installed Claude Code CLI. They use the account Claude Code is already logged
/// into (subscription), never an API key: ANTHROPIC_API_KEY is stripped from the child environment so the CLI cannot silently
/// switch to metered API billing. Nothing stays resident: one process per request, killed on cancel.
enum ClaudeCLI {
    struct Failure: Error { let message: String }

    /// The `claude` executable, or nil when Claude Code is not installed.
    static func executable() -> String? {
        if let forced = ProcessInfo.processInfo.environment["CE_CLAUDE_BIN"], FileManager.default.isExecutableFile(atPath: forced) { return forced }
        let home = NSHomeDirectory()
        var candidates = ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude",
                          "/usr/local/bin/claude", "\(home)/.npm-global/bin/claude", "\(home)/.bun/bin/claude"]
        for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") { candidates.append("\(dir)/claude") }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Scratch directory used as cwd when a request should not pick up a project's CLAUDE.md / settings.
    static var neutralDirectory: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kode-claude-scratch")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Arguments for a text-only, tool-less, hook-free answer. `--setting-sources project` skips the user's hooks and plugins,
    /// which roughly halves start-up latency.
    static func arguments(model: String?, system: String?) -> [String] {
        var args = ["-p", "--no-session-persistence", "--tools", "", "--setting-sources", "project", "--output-format", "text"]
        if let model { args += ["--model", model] }
        if let system { args += ["--append-system-prompt", system] }
        return args
    }

    /// Runs `claude -p` with `prompt` on stdin. `completion` is called on the main queue. The returned process can be terminated
    /// to cancel (completion then reports "Cancelled").
    @discardableResult
    static func run(prompt: String, model: String? = "haiku", system: String? = nil, cwd: URL? = nil,
                    timeout: TimeInterval = 120, completion: @escaping (Result<String, Failure>) -> Void) -> Process? {
        guard let exe = executable() else {
            completion(.failure(Failure(message: "Claude Code is not installed (looked for `claude` in ~/.local/bin, Homebrew and PATH).")))
            return nil
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = arguments(model: model, system: system)
        p.currentDirectoryURL = cwd ?? neutralDirectory
        p.qualityOfService = .userInitiated
        var env = ProcessInfo.processInfo.environment
        env["ANTHROPIC_API_KEY"] = nil
        env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        p.environment = env
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe
        let cancelled = Atomic()
        DispatchQueue.global(qos: .userInitiated).async {
            do { try p.run() } catch {
                DispatchQueue.main.async { completion(.failure(Failure(message: "Cannot launch claude: \(error.localizedDescription)"))) }
                return
            }
            let killer = DispatchWorkItem { cancelled.timedOut = true; p.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
            DispatchQueue.global().async {
                inPipe.fileHandleForWriting.write(Data(prompt.utf8))
                try? inPipe.fileHandleForWriting.close()
            }
            var errData = Data()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
            let out = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.wait()
            p.waitUntilExit()
            killer.cancel()
            let text = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let err = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let result: Result<String, Failure>
            if cancelled.timedOut { result = .failure(Failure(message: "Claude took longer than \(Int(timeout)) s.")) }
            else if p.terminationReason == .uncaughtSignal { result = .failure(Failure(message: "Cancelled")) }
            else if p.terminationStatus != 0 || text.isEmpty {
                let detail = err.isEmpty ? text : err
                result = .failure(Failure(message: detail.isEmpty ? "claude exited with status \(p.terminationStatus)." : String(detail.prefix(600))))
            } else { result = .success(text) }
            DispatchQueue.main.async { completion(result) }
        }
        return p
    }

    private final class Atomic { var timedOut = false }

    // MARK: prompts

    /// Instruction + context for a commit message; `diff` is already size-capped by the caller.
    static func commitPrompt(branch: String?, recentSubjects: [String], stat: String, diff: String) -> String {
        var s = """
        Write a git commit message for the changes below.
        Rules: first line is an imperative subject of at most 72 characters with no trailing period; if the change needs it, add a blank line and a short body (wrapped at 72) explaining what and why, not how. Match the style of the recent commits. Output ONLY the commit message text: no code fences, no quotes, no preamble.

        """
        if let branch, !branch.isEmpty { s += "Branch: \(branch)\n" }
        if !recentSubjects.isEmpty { s += "Recent commit subjects (style reference):\n" + recentSubjects.map { "- \($0)" }.joined(separator: "\n") + "\n" }
        s += "\nChanged files:\n\(stat)\n\nDiff:\n\(diff)\n"
        return s
    }

    /// Strips fences / quotes a model sometimes wraps around the message.
    static func cleanCommitMessage(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            var lines = t.components(separatedBy: "\n")
            lines.removeFirst()
            if lines.last?.hasPrefix("```") == true { lines.removeLast() }
            t = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if t.count > 2, t.hasPrefix("\""), t.hasSuffix("\""), !t.dropFirst().dropLast().contains("\"") { t = String(t.dropFirst().dropLast()) }
        return t
    }

    struct Turn { let question: String; var answer: String? }

    /// Stateless chat prompt: the code, then earlier turns, then the new question.
    static func chatPrompt(path: String, startLine: Int, endLine: Int, code: String, turns: [Turn]) -> String {
        var s = "The user selected this code in their editor (\(path), lines \(startLine)-\(endLine)) and wants to discuss it.\n\n```\n\(code)\n```\n\n"
        for t in turns {
            s += "User: \(t.question)\n"
            if let a = t.answer { s += "Assistant: \(a)\n\n" }
        }
        s += "Answer the last user question concisely, referring to the code above. Use Markdown. You cannot run tools or read other files in this mode; say so if you need more context."
        return s
    }
}
