import Foundation

/// Fuzzy matching in the style of IDE "Go to" popups: the BEST alignment of the query inside the text (not the first scattered
/// one), rewarding matches at word starts / camelCase humps / right after separators, consecutive runs, and exact-case humps
/// (typing `TaController` prefers `TaTrackController` by matching T-a then the C hump). Higher is better; nil = no match.
enum Fuzzy {
    private static let scoreMatch = 16, gapStart = -3, gapExtension = -1
    private static let bonusBoundary = 8, bonusCamel = 7, bonusDigit = 3, bonusConsecutive = 4, bonusFirstChar = 2

    /// Legacy entry point: `query` is already lowercased without spaces (no case information).
    static func score(_ query: [Character], in text: String) -> Int? {
        score(Array(String(query).utf16), caseAware: false, in: text)
    }

    /// Case-aware entry point: pass the query as typed (spaces ignored).
    static func score(query: String, in text: String) -> Int? {
        score(Array(query.filter { !$0.isWhitespace }.utf16), caseAware: true, in: text)
    }

    @inline(__always) private static func lower(_ c: UInt16) -> UInt16 { c >= 65 && c <= 90 ? c + 32 : c }
    @inline(__always) private static func isUpper(_ c: UInt16) -> Bool { c >= 65 && c <= 90 }
    @inline(__always) private static func isLowerCase(_ c: UInt16) -> Bool { c >= 97 && c <= 122 }
    @inline(__always) private static func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
    @inline(__always) private static func isSeparator(_ c: UInt16) -> Bool { c == 47 || c == 92 || c == 46 || c == 95 || c == 45 || c == 32 || c == 58 }  // / \ . _ - space :

    static func score(_ q: [UInt16], caseAware: Bool, in text: String) -> Int? {
        let m = q.count
        if m == 0 { return 0 }
        let c = Array(text.utf16)
        let n = c.count
        if n < m { return nil }

        // Cheap rejection: is the query a subsequence at all?
        var qi = 0
        for ch in c where qi < m && lower(ch) == lower(q[qi]) { qi += 1 }
        if qi < m { return nil }

        // Per-position bonus from the previous character's class.
        var bonus = [Int](repeating: 0, count: n)
        for j in 0..<n {
            if j == 0 { bonus[j] = bonusBoundary; continue }
            let prev = c[j - 1], cur = c[j]
            if isSeparator(prev) { bonus[j] = bonusBoundary }
            else if isLowerCase(prev) && isUpper(cur) { bonus[j] = bonusCamel }
            else if !isDigit(prev) && isDigit(cur) { bonus[j] = bonusDigit }
        }

        let negative = Int.min / 4
        var prevM = [Int](repeating: negative, count: n)      // best score with query[i-1] matched exactly at j
        var curM = [Int](repeating: negative, count: n)
        for i in 0..<m {
            var gap = negative                                  // best prevM[k] - gap cost, for k < j
            for j in 0..<n {
                curM[j] = negative
                // gap carries the best way to have matched query[i-1] before j, then skipped chars up to j.
                if i > 0, j > 0 {
                    gap = max(gap + gapExtension, prevM[j - 1] + gapStart)
                }
                guard lower(c[j]) == lower(q[i]) else { continue }
                var s = scoreMatch + bonus[j]
                if caseAware, isUpper(q[i]) {
                    s += isUpper(c[j]) ? 4 : -2                 // typed capital = "this is a hump"
                }
                if i == 0 {
                    // Mild preference for matches nearer the start, strong for the very first character.
                    s -= min(j, 12) / 2
                    if j == 0 { s += bonus[0] * bonusFirstChar / 2 }
                    curM[j] = s
                } else if j > 0 {
                    var best = negative
                    if prevM[j - 1] > negative { best = prevM[j - 1] + max(bonusConsecutive, bonus[j]) }
                    if gap > negative { best = max(best, gap) }
                    if best > negative { curM[j] = best + s }
                }
            }
            swap(&prevM, &curM)
        }
        var best = negative
        for j in 0..<n where prevM[j] > best { best = prevM[j] }
        return best > negative ? best - n / 16 : nil
    }
}
