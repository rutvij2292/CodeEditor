import Foundation

/// One problem handed to Claude for evaluation. `id` is the caller's index, echoed back in the answer.
struct ProblemRef {
    let id: Int
    let url: URL
    let relPath: String
    let d: FileProblems.Diagnostic
    let fileText: String?
}

/// Claude's verdict on one problem. `oldText`/`newText` (both set) describe an exact, single-occurrence text replacement.
struct ProblemAnswer: Equatable {
    enum Verdict: String { case real, falsePositive = "false_positive", ignorable }
    enum Difficulty: String { case easy, moderate, hard }
    let verdict: Verdict
    let difficulty: Difficulty
    let explanation: String
    let oldText: String?
    let newText: String?
}

/// "Evaluate with Claude": one `claude -p` call for up to 20 problems, one structured answer per problem. Only runs on request.
enum ProblemEvaluator {
    static let maxPerCall = 20

    static func prompt(_ refs: [ProblemRef]) -> String {
        var s = """
        You are reviewing editor diagnostics. For each problem below decide: is it a real problem, a false positive, or safe to ignore? How hard is it to fix (easy = a small local edit, moderate, hard)? Give a short explanation and, only when the fix is a small local edit visible in the snippet, an exact replacement: "oldText" must be copied verbatim from the snippet and occur exactly once in the file, "newText" is what replaces it (empty string to delete).

        Reply with ONLY a JSON array, no prose, one object per problem:
        [{"id": <number>, "verdict": "real" | "false_positive" | "ignorable", "difficulty": "easy" | "moderate" | "hard", "explanation": "<one or two sentences>", "oldText": "<optional>", "newText": "<optional>"}]


        """
        for r in refs {
            var tag = [r.d.source, r.d.code].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            if !tag.isEmpty { tag = " [\(tag)]" }
            s += "### Problem \(r.id)\n\(r.relPath):\(r.d.line):\(r.d.column) \(TerminalBridge.severityName(r.d.severity)): \(r.d.message.replacingOccurrences(of: "\n", with: " "))\(tag)\n"
            if let t = r.fileText, let snip = FixWithClaude.snippet(of: t, around: r.d.line) {
                s += TerminalBridge.fencedBlock(path: r.relPath, start: snip.start, end: snip.end, text: snip.text) + "\n"
            }
            s += "\n"
        }
        return s
    }

    /// Extracts the first JSON array in `raw` (fences and prose around it are fine). Entries with unknown ids, bad enum values or
    /// missing fields are dropped.
    static func parse(_ raw: String, ids: [Int]) -> [Int: ProblemAnswer] {
        guard let a = raw.firstIndex(of: "["), let b = raw.lastIndex(of: "]"), a < b,
              let arr = (try? JSONSerialization.jsonObject(with: Data(raw[a...b].utf8))) as? [[String: Any]] else { return [:] }
        var out: [Int: ProblemAnswer] = [:]
        for o in arr {
            guard let id = o["id"] as? Int, ids.contains(id),
                  let v = (o["verdict"] as? String).flatMap(ProblemAnswer.Verdict.init(rawValue:)),
                  let d = (o["difficulty"] as? String).flatMap(ProblemAnswer.Difficulty.init(rawValue:)),
                  let e = o["explanation"] as? String else { continue }
            let old = o["oldText"] as? String, new = o["newText"] as? String
            out[id] = ProblemAnswer(verdict: v, difficulty: d, explanation: e, oldText: new == nil ? nil : old, newText: old == nil ? nil : new)
        }
        return out
    }

    /// Identifies a problem across edits: its message plus the trimmed text of its line.
    static func fingerprint(_ r: ProblemRef) -> String {
        let lines = (r.fileText ?? "").components(separatedBy: "\n")
        let line = r.d.line >= 1 && r.d.line <= lines.count ? lines[r.d.line - 1].trimmingCharacters(in: .whitespaces) : ""
        return "\(r.d.message)|\(line)"
    }

    /// `completion` is called on the main queue (synchronously for the over-limit failure). The returned process can be terminated.
    @discardableResult
    static func evaluate(_ refs: [ProblemRef], completion: @escaping (Result<[Int: ProblemAnswer], ClaudeCLI.Failure>) -> Void) -> Process? {
        guard refs.count <= maxPerCall else {
            completion(.failure(.init(message: "Evaluate at most \(maxPerCall) problems at a time.")))
            return nil
        }
        let ids = refs.map { $0.id }
        return ClaudeCLI.run(prompt: prompt(refs), timeout: 180) { result in
            switch result {
            case .failure(let f): completion(.failure(f))
            case .success(let text): completion(.success(parse(text, ids: ids)))
            }
        }
    }
}

/// In-memory answers, newest kept. Key = file path + "|" + `ProblemEvaluator.fingerprint`.
final class ProblemAnswerCache {
    static let shared = ProblemAnswerCache()
    let capacity = 200
    private var order: [String] = []
    private var store: [String: ProblemAnswer] = [:]
    var count: Int { store.count }

    func get(_ key: String) -> ProblemAnswer? { store[key] }

    func set(_ key: String, _ a: ProblemAnswer) {
        if store[key] == nil { order.append(key) }
        store[key] = a
        while order.count > capacity { store[order.removeFirst()] = nil }
    }

    func invalidate(path: String) {
        let prefix = path + "|"
        order.removeAll { $0.hasPrefix(prefix) }
        store = store.filter { !$0.key.hasPrefix(prefix) }
    }

    func removeAll() { order.removeAll(); store.removeAll() }
}
