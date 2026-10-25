import Foundation

/// Laravel string-value completions that are not "a name from the project index": validation rules (`'required|string|max:255'`,
/// `['required', 'exists:users,id']`), model cast types (`$casts = ['at' => 'datetime']`), and PHP 8 named arguments (`foo(message: `).
/// Runs on the project queue inside FastEngine.run.
enum FastRules {
    // (name, one-line description) most used first; the order is the ranking.
    private static let rules: [(String, String)] = [
        ("required", "The field must be present and not empty"), ("nullable", "The field may be null"), ("string", "The field must be a string"),
        ("integer", "The field must be an integer"), ("numeric", "The field must be numeric"), ("email", "The field must be an e-mail address"),
        ("array", "The field must be an array"), ("boolean", "The field must be true, false, 1, 0, \"1\" or \"0\""), ("date", "The field must be a valid date"),
        ("max:", "Maximum value / length / size / count"), ("min:", "Minimum value / length / size / count"),
        ("exists:", "The value must exist in a database table: exists:table,column"), ("unique:", "The value must be unique in a table: unique:table,column,ignoreId"),
        ("in:", "The value must be one of the listed ones: in:a,b,c"), ("sometimes", "Validate only when the field is present"),
        ("confirmed", "Needs a matching {field}_confirmation field"), ("image", "The file must be an image"), ("file", "The field must be an uploaded file"),
        ("mimes:", "The file's extension must be one of the listed: mimes:jpg,png"), ("url", "The field must be a valid URL"),
        ("date_format:", "The field must match the date format: date_format:Y-m-d"), ("after:", "The date must be after the given date / field"),
        ("before:", "The date must be before the given date / field"), ("after_or_equal:", "The date must be after or equal to the given date / field"),
        ("before_or_equal:", "The date must be before or equal to the given date / field"), ("size:", "Exact size / length / count"),
        ("between:", "Between two values: between:1,10"), ("regex:", "Must match the regular expression"),
        ("required_if:", "Required when another field has a value: required_if:field,value"), ("required_with:", "Required when any of the other fields is present"),
        ("required_without:", "Required when any of the other fields is absent"), ("required_unless:", "Required unless another field has a value"),
        ("required_with_all:", "Required when all of the other fields are present"), ("required_without_all:", "Required when all of the other fields are absent"),
        ("same:", "Must match another field"), ("different:", "Must differ from another field"), ("digits:", "Exactly N digits"),
        ("digits_between:", "Between N and M digits"), ("alpha", "Only letters"), ("alpha_num", "Only letters and numbers"),
        ("alpha_dash", "Letters, numbers, dashes and underscores"), ("uuid", "A valid UUID"), ("json", "A valid JSON string"), ("ip", "A valid IP address"),
        ("ipv4", "A valid IPv4 address"), ("ipv6", "A valid IPv6 address"), ("timezone", "A valid timezone identifier"), ("accepted", "yes, on, 1, true"),
        ("declined", "no, off, 0, false"), ("present", "The field must be present (may be empty)"), ("filled", "Not empty when present"),
        ("prohibited", "The field must be absent or empty"), ("bail", "Stop at the first failing rule"), ("distinct", "No duplicates in the array"),
        ("gt:", "Greater than another field / value"), ("gte:", "Greater than or equal"), ("lt:", "Less than"), ("lte:", "Less than or equal"),
        ("not_in:", "The value must not be one of the listed"), ("starts_with:", "Must start with one of the values"), ("ends_with:", "Must end with one of the values"),
        ("lowercase", "Must be lowercase"), ("uppercase", "Must be uppercase"), ("ascii", "Only 7-bit ASCII characters"), ("active_url", "A URL with a valid DNS record"),
        ("ulid", "A valid ULID"), ("mac_address", "A valid MAC address"), ("enum:", "Must be a value of the backed enum"), ("current_password", "Must match the user's password"),
        ("password", "Password rules"), ("decimal:", "Numeric with the given decimal places"), ("exclude_if:", "Exclude when another field has a value"),
        ("exclude_unless:", "Exclude unless another field has a value"), ("exclude", "Always exclude from validated data"), ("missing", "The field must not be present"),
        ("list", "An array with consecutive keys"), ("hex_color", "A valid hexadecimal colour"), ("mimetypes:", "The file's MIME type must be one of the listed"),
        ("dimensions", "Image dimensions: dimensions:min_width=100"), ("max_digits:", "At most N digits"), ("min_digits:", "At least N digits"),
        ("multiple_of:", "A multiple of the value"), ("required_array_keys:", "The array must contain the keys"), ("prohibits:", "No other listed field may be present"),
        ("accepted_if:", "Accepted when another field has a value"), ("declined_if:", "Declined when another field has a value"), ("in_array:", "The value must exist in another array field"),
        ("doesnt_start_with:", "Must not start with"), ("doesnt_end_with:", "Must not end with"), ("integer:strict", "Strict integer"), ("string:strict", "Strict string"),
        ("size", "Size"), ("exclude_with:", "Exclude when another field is present"), ("exclude_without:", "Exclude when another field is absent"), ("present_if:", "Present when another field has a value"),
        ("prohibited_if:", "Prohibited when another field has a value"), ("prohibited_unless:", "Prohibited unless another field has a value"),
    ]
    private static let casts: [(String, String)] = [
        ("array", "JSON to array"), ("boolean", "Boolean"), ("collection", "JSON to Collection"), ("date", "Carbon date (time truncated)"), ("datetime", "Carbon date-time"),
        ("integer", "Integer"), ("float", "Float"), ("string", "String"), ("decimal:", "Decimal with N places: decimal:2"), ("double", "Double"), ("object", "JSON to object"),
        ("encrypted", "Encrypted string"), ("encrypted:array", "Encrypted JSON array"), ("encrypted:collection", "Encrypted collection"), ("encrypted:object", "Encrypted object"),
        ("hashed", "Hash on assignment"), ("immutable_date", "CarbonImmutable date"), ("immutable_datetime", "CarbonImmutable date-time"), ("timestamp", "Unix timestamp"),
        ("real", "Float"), ("date:Y-m-d", "Date with a serialization format"), ("datetime:Y-m-d H:i:s", "Date-time with a serialization format"),
    ]

    private static func ruleItems(_ list: [(String, String)], kind: CompletionKind, detail: String, range: NSRange) -> [CompletionItem] {
        var out: [CompletionItem] = []
        out.reserveCapacity(list.count)
        for (i, e) in list.enumerated() {
            var it = CI.make(e.0, kind, detail: detail, doc: "**\(e.0)** \u{2014} \(e.1)", range: range)
            it.priority = i
            out.append(it)
        }
        return out
    }

    private enum Ctx { case rules, casts }

    /// Which kind of string this is, from the declaration the caret sits in. A string that is an argument of some other call
    /// (`route('..')`, `Rule::exists('..')`) is never a rule.
    private static func context(_ ns: NSString, open: Int) -> Ctx? {
        if let paren = FastEngine.enclosingCall(ns, openAbs: open) {
            var q = paren - 1
            while q >= 0, [32, 9, 10, 13].contains(ns.character(at: q)) { q -= 1 }
            let id = CompletionLex.identBefore(ns, q + 1).lowercased()
            if ["validate", "validatewithbag", "validated", "rules"].contains(id) { return .rules }
            if id == "make" {
                let r = q + 1 - id.utf16.count
                if r >= 11, ns.substring(with: NSRange(location: r - 11, length: 11)).lowercased() == "validator::" { return .rules }
            }
            return nil
        }
        let from = max(0, open - 6000)
        let head = ns.substring(with: NSRange(location: from, length: open - from)) as NSString
        let fn = head.range(of: "function ", options: .backwards)
        var name = ""
        if fn.location != NSNotFound {
            var e = fn.location + fn.length
            while e < head.length, CompletionLex.isIdent(head.character(at: e)) { e += 1 }
            name = head.substring(with: NSRange(location: fn.location + fn.length, length: e - fn.location - fn.length))
        }
        let lname = name.lowercased()
        let afterFn = fn.location == NSNotFound ? 0 : fn.location
        if lname == "casts" { return .casts }
        if lname.contains("rules") { return .rules }
        let castVar = head.range(of: "$casts", options: .backwards)
        if castVar.location != NSNotFound, castVar.location > afterFn { return .casts }
        let rulesVar = head.range(of: "$rules", options: .backwards)
        if rulesVar.location != NSNotFound, rulesVar.location > afterFn { return .rules }
        return nil
    }

    /// The string is a rules / casts VALUE (not an array key): nothing but spaces, then `=>`, must not follow its closing quote.
    private static func isKey(_ ns: NSString, open: Int, caret: Int) -> Bool {
        let q = ns.character(at: open)
        var j = caret
        let lim = min(ns.length, caret + 300)
        while j < lim {
            let c = ns.character(at: j)
            if c == q { j += 1; break }
            if c == 10 { return false }
            j += 1
        }
        while j < lim, ns.character(at: j) == 32 || ns.character(at: j) == 9 { j += 1 }
        return j + 1 < ns.length && ns.character(at: j) == 61 && ns.character(at: j + 1) == 62
    }

    static func items(_ ns: NSString, open: Int, caret: Int, fp: FastProject) -> FastEngine.Result? {
        guard caret > open, caret <= ns.length else { return nil }
        guard let kind = context(ns, open: open), !isKey(ns, open: open, caret: caret) else { return nil }
        let typed = ns.substring(with: NSRange(location: open + 1, length: caret - open - 1)) as NSString
        if kind == .casts {
            if typed.range(of: ":").location != NSNotFound { return FastEngine.Result(items: []) }
            return FastEngine.Result(items: ruleItems(casts, kind: .enumMember, detail: "cast", range: NSRange(location: open + 1, length: typed.length)))
        }
        let bar = typed.range(of: "|", options: .backwards)
        let tokStart = bar.location == NSNotFound ? 0 : bar.location + 1
        let token = typed.substring(from: tokStart) as NSString
        let base = open + 1 + tokStart
        let colon = token.range(of: ":")
        if colon.location == NSNotFound {
            return FastEngine.Result(items: ruleItems(rules, kind: .keyword, detail: "rule", range: NSRange(location: base, length: token.length)))
        }
        let rule = token.substring(to: colon.location).lowercased()
        let params = token.substring(from: colon.location + 1) as NSString
        guard rule == "exists" || rule == "unique" else { return FastEngine.Result(items: []) }
        let schema = fp.schema()
        let comma = params.range(of: ",")
        if comma.location == NSNotFound {
            let range = NSRange(location: base + colon.location + 1, length: params.length)
            let items = schema.keys.sorted().map { t -> CompletionItem in
                var it = CI.make(t, .struct, detail: "table", doc: "`\(t)` \u{2014} \((schema[t] ?? []).count) columns", range: range)
                it.priority = 0
                return it
            }
            return FastEngine.Result(items: items)
        }
        var table = params.substring(to: comma.location)
        if let dot = table.lastIndex(of: ".") { table = String(table[table.index(after: dot)...]) }   // connection.table
        let lastComma = params.range(of: ",", options: .backwards)
        if params.substring(from: comma.location + 1).contains(",") && lastComma.location != comma.location { return FastEngine.Result(items: []) }  // 3rd+ parameter: ignore id / where
        let range = NSRange(location: base + colon.location + 1 + comma.location + 1, length: params.length - comma.location - 1)
        let items = (schema[table] ?? []).map { c -> CompletionItem in
            var it = CI.make(c.name, .field, detail: c.type, doc: "Column of `\(table)`", range: range)
            it.priority = c.name == "id" ? 0 : 1
            return it
        }
        return FastEngine.Result(items: items)
    }

    // MARK: Named arguments

    /// `foo(me|`, `$obj->save(fo|`, `new Foo(na|`: the remaining parameter names of the callee as `name: ` items.
    static func namedArgs(_ ctx: CompletionContext, _ ns: NSString, caret: Int, fp: FastProject) -> FastEngine.Result? {
        let p = ctx.prefixRange.location
        var b = p - 1
        while b >= 0, [32, 9, 10, 13].contains(ns.character(at: b)) { b -= 1 }
        guard b >= 0, ns.character(at: b) == 40 || ns.character(at: b) == 44 else { return nil }
        // the next non-space char after the caret must not already make this a `name:` pair or a call
        var a = caret
        while a < ns.length, CompletionLex.isIdent(ns.character(at: a)) { a += 1 }
        if a < ns.length, ns.character(at: a) == 58, !(a + 1 < ns.length && ns.character(at: a + 1) == 58) { return nil }
        let r = NativePHP.resolver(fp: fp, url: ctx.fileURL, text: ns)
        guard let site = r.callSite(at: caret) else { return nil }
        // the innermost open bracket must be this call's "(" (not an array literal inside the call)
        var i = r.ev.tokenIndex(atOrAfter: caret) - 1, depth = 0
        while i > site.open {
            let t = r.lex.toks[i]
            if t.kind == .punct {
                if t.ch == 41 || t.ch == 93 || t.ch == 125 { depth += 1 }
                else if t.ch == 40 || t.ch == 91 || t.ch == 123 { if depth == 0 { return nil }; depth -= 1 }
            }
            i -= 1
        }
        guard let target = r.calleeTarget(open: site.open) else { return nil }
        var params = NPResolver.splitParams(target.params)
        if target.dropFirst, !params.isEmpty { params.removeFirst() }
        guard !params.isEmpty else { return nil }
        // names already used as `name:` in this call
        var used = Set<String>()
        var k = site.open + 1
        let end = r.ev.tokenIndex(atOrAfter: caret)
        var d = 0
        while k < end - 1 {
            let t = r.lex.toks[k]
            if t.kind == .punct { if [40, 91, 123].contains(t.ch) { d += 1 } else if [41, 93, 125].contains(t.ch) { d -= 1 } }
            else if d == 0, t.kind == .ident, r.lex.isPunct(k + 1, ":") { used.insert(r.lex.text(k)) }
            k += 1
        }
        var items: [CompletionItem] = []
        for (idx, par) in params.enumerated() {
            guard let n = NPResolver.paramName(par) else { continue }
            let name = String(n.dropFirst())
            if used.contains(name) || par.contains("...") || idx < site.index - used.count { continue }   // used by name / variadic / supplied positionally
            var doc = ""
            if let d = target.doc?.params.first(where: { $0.name == n }), !d.text.isEmpty { doc = NPDoc.clip(NPDoc.cleanInline(d.text), 220) }
            var it = CI.make(name + ":", .variable, detail: par, insert: name + ": ", sort: "0" + String(format: "%02d", idx), doc: doc.isEmpty ? "```php\n\(par)\n```" : "```php\n\(par)\n```\n" + doc)
            it.priority = 0
            items.append(it)
        }
        return items.isEmpty ? nil : FastEngine.Result(items: items)
    }
}
