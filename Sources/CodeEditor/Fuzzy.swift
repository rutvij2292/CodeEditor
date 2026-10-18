import Foundation

enum Fuzzy {
    private static func isSeparator(_ c: Character) -> Bool { "/._- ".contains(c) }

    /// Higher is better; nil when `query` (already lowercased, no spaces) isn't a subsequence of `text`.
    static func score(_ query: [Character], in text: String) -> Int? {
        if query.isEmpty { return 0 }
        let original = Array(text)
        let lower = original.map { Character(String($0).lowercased()) }
        var qi = 0, score = 0, prev = -2, first = -1
        for i in lower.indices where qi < query.count && lower[i] == query[qi] {
            var s = 1
            if i == prev + 1 { s += 5 }
            if i == 0 || isSeparator(original[i - 1]) { s += 8 }
            else if original[i].isUppercase && !original[i - 1].isUppercase { s += 6 }
            score += s
            prev = i
            if first < 0 { first = i }
            qi += 1
        }
        guard qi == query.count else { return nil }
        if String(lower).contains(String(query)) { score += 20 }
        let nameStart = (lower.lastIndex(of: "/") ?? -1) + 1
        if first >= nameStart { score += 25 }
        return score - lower.count / 8
    }
}
