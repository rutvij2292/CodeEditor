import Foundation

/// On-disk, memory-mapped vendor class table. Layout (little endian):
///   header 64B | package records 32B each | class records 16B each (sorted by lowercased FQN) | string blob
/// Nothing is decoded eagerly: readers walk the mapped bytes, so resident memory stays a few MB for 40k classes.
enum VendorFormat {
    static let magic: UInt32 = 0x4956_4543          // "CEVI"
    static let version: UInt32 = 1                  // bump when the layout or the extraction rules change
    static let headerSize = 64, packageSize = 32, classSize = 16

    enum Kind: UInt8 { case unknown = 0, `class`, interface, trait, `enum` }
    static let flagAbstract: UInt8 = 1, flagFinal: UInt8 = 2

    /// Intermediate (build time only) representation.
    struct RawEntry { var fqn: String; var rel: String; var kind: UInt8; var flags: UInt8 }
    struct RawPackage { var name: String; var version: String; var root: String; var sig: UInt64; var entries: [RawEntry] }

    /// FNV-1a 64.
    static func fnv(_ bytes: UnsafeRawBufferPointer, seed: UInt64 = 0xcbf2_9ce4_8422_2325) -> UInt64 {
        var h = seed
        for b in bytes { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return h
    }
    static func fnv(_ string: String, seed: UInt64 = 0xcbf2_9ce4_8422_2325) -> UInt64 {
        var s = string
        return s.withUTF8 { fnv(UnsafeRawBufferPointer($0), seed: seed) }
    }

    /// Lowercased FQN with `\` as `/` (the form that is compared and sorted).
    static func sortKey(_ fqn: String) -> [UInt8] {
        fqn.utf8.map { $0 == 92 ? 47 : ($0 >= 65 && $0 <= 90 ? $0 + 32 : $0) }
    }

    static func serialize(key: UInt64, packages: [RawPackage]) -> Data {
        var blob = [UInt8]()
        var strings: [String: UInt32] = [:]
        func intern(_ s: String) -> (UInt32, Int) {
            let n = s.utf8.count
            if let o = strings[s] { return (o, n) }
            let o = UInt32(blob.count)
            blob.append(contentsOf: s.utf8)
            strings[s] = o
            return (o, n)
        }
        struct Rec { var sort: [UInt8]; var fqn: (UInt32, Int); var path: (UInt32, Int); var pkg: Int; var kind: UInt8; var flags: UInt8 }
        var recs: [Rec] = []
        var pkgRecs = [UInt8]()
        func u16(_ v: Int, _ a: inout [UInt8]) { a.append(UInt8(v & 255)); a.append(UInt8((v >> 8) & 255)) }
        func u32(_ v: UInt32, _ a: inout [UInt8]) { for i in 0..<4 { a.append(UInt8((v >> (8 * UInt32(i))) & 255)) } }
        func u64(_ v: UInt64, _ a: inout [UInt8]) { for i in 0..<8 { a.append(UInt8((v >> (8 * UInt64(i))) & 255)) } }
        for (pi, p) in packages.enumerated() {
            let n = intern(p.name), v = intern(p.version), r = intern(p.root)
            u32(n.0, &pkgRecs); u32(v.0, &pkgRecs); u32(r.0, &pkgRecs)
            u16(min(n.1, 65535), &pkgRecs); u16(min(v.1, 65535), &pkgRecs); u16(min(r.1, 65535), &pkgRecs); u16(0, &pkgRecs)
            u64(p.sig, &pkgRecs); u32(0, &pkgRecs)
            for e in p.entries where e.fqn.utf8.count < 65535 && e.rel.utf8.count < 65535 {
                recs.append(Rec(sort: sortKey(e.fqn), fqn: intern(e.fqn), path: intern(e.rel), pkg: pi, kind: e.kind, flags: e.flags))
            }
        }
        recs.sort { $0.sort.lexicographicallyPrecedes($1.sort) }
        var classRecs = [UInt8](); classRecs.reserveCapacity(recs.count * classSize)
        for r in recs {
            u32(r.fqn.0, &classRecs); u32(r.path.0, &classRecs)
            u16(r.fqn.1, &classRecs); u16(r.path.1, &classRecs); u16(r.pkg, &classRecs)
            classRecs.append(r.kind); classRecs.append(r.flags)
        }
        let pkgOff = headerSize, classOff = pkgOff + pkgRecs.count, blobOff = classOff + classRecs.count
        let total = blobOff + blob.count
        var out = [UInt8](); out.reserveCapacity(total)
        u32(magic, &out); u32(version, &out); u64(key, &out)
        u32(UInt32(recs.count), &out); u32(UInt32(packages.count), &out)
        u32(UInt32(pkgOff), &out); u32(UInt32(classOff), &out); u32(UInt32(blobOff), &out)
        u32(UInt32(blob.count), &out); u32(UInt32(total), &out)
        while out.count < headerSize { out.append(0) }
        out.append(contentsOf: pkgRecs); out.append(contentsOf: classRecs); out.append(contentsOf: blob)
        return Data(out)
    }
}

/// Read-only view over a mapped table. Every access is bounds-checked, so a corrupt file can't crash the app.
final class VendorTable {
    let data: Data
    let count: Int, packageCount: Int
    private let pkgOff: Int, classOff: Int, blobOff: Int, blobLen: Int
    let key: UInt64

    struct Package { let name: String; let version: String; let root: String; let sig: UInt64 }

    init?(data: Data) {
        guard data.count >= VendorFormat.headerSize else { return nil }
        self.data = data
        func u32(_ o: Int) -> Int { Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }) }
        guard UInt32(u32(0)) == VendorFormat.magic, UInt32(u32(4)) == VendorFormat.version else { return nil }
        key = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self) }
        count = u32(16); packageCount = u32(20); pkgOff = u32(24); classOff = u32(28); blobOff = u32(32); blobLen = u32(36)
        let total = u32(40)
        guard total == data.count, pkgOff == VendorFormat.headerSize,
              classOff == pkgOff + packageCount * VendorFormat.packageSize,
              blobOff == classOff + count * VendorFormat.classSize, blobOff + blobLen == total else { return nil }
    }

    @inline(__always) private func u32(_ o: Int) -> Int { Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }) }
    @inline(__always) private func u16(_ o: Int) -> Int { Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt16.self) }) }

    private func string(_ off: Int, _ len: Int) -> String {
        guard off >= 0, len >= 0, off + len <= blobLen else { return "" }
        return data.withUnsafeBytes { String(decoding: UnsafeRawBufferPointer(rebasing: $0[(blobOff + off)..<(blobOff + off + len)]), as: UTF8.self) }
    }

    func package(_ i: Int) -> Package {
        guard i >= 0, i < packageCount else { return Package(name: "", version: "", root: "", sig: 0) }
        let o = pkgOff + i * VendorFormat.packageSize
        let sig = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o + 20, as: UInt64.self) }
        return Package(name: string(u32(o), u16(o + 12)), version: string(u32(o + 4), u16(o + 14)),
                       root: string(u32(o + 8), u16(o + 16)), sig: sig)
    }

    struct Row { let fqn: String; let rel: String; let pkg: Int; let kind: UInt8; let flags: UInt8 }

    func row(_ i: Int) -> Row? {
        guard i >= 0, i < count else { return nil }
        let o = classOff + i * VendorFormat.classSize
        let pkg = u16(o + 12)
        guard pkg < packageCount else { return nil }
        return Row(fqn: string(u32(o), u16(o + 8)), rel: string(u32(o + 4), u16(o + 10)), pkg: pkg,
                   kind: data[o + 14], flags: data[o + 15])
    }

    /// Calls `body` with the FQN bytes of every row (index, bytes); stops when it returns false.
    func scanNames(_ body: (Int, UnsafeBufferPointer<UInt8>) -> Void) {
        data.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: UInt8.self)
            for i in 0..<count {
                let o = classOff + i * VendorFormat.classSize
                let off = Int(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self))
                let len = Int(raw.loadUnaligned(fromByteOffset: o + 8, as: UInt16.self))
                guard off + len <= blobLen else { continue }
                body(i, UnsafeBufferPointer(rebasing: base[(blobOff + off)..<(blobOff + off + len)]))
            }
        }
    }

    func allPackages() -> [Package] { (0..<packageCount).map(package) }

    /// Rows are sorted by `sortKey`; binary search for an exact (case-insensitive) FQN. Returns every duplicate.
    func find(fqn: String) -> [Int] {
        let target = VendorFormat.sortKey(fqn.hasPrefix("\\") ? String(fqn.dropFirst()) : fqn)
        func key(_ i: Int) -> [UInt8] { VendorFormat.sortKey(row(i)?.fqn ?? "") }
        var lo = 0, hi = count
        while lo < hi { let m = (lo + hi) / 2; if key(m).lexicographicallyPrecedes(target) { lo = m + 1 } else { hi = m } }
        var out: [Int] = []
        while lo < count, key(lo) == target { out.append(lo); lo += 1 }
        return out
    }
}
