import Foundation
import Darwin

/// Gives every native-JS parse its own memory arena that is handed back to the OS the moment its document dies.
///
/// A parse allocates ~26 bytes per source character in many small blocks. Freed to the general heap they fragment it: pages stay
/// resident, interleaved with long lived data, and `malloc_zone_pressure_relief` / `malloc_destroy_zone` returned none of it (measured:
/// one minified 650 KB file left +10 MB behind for the life of the process). tree-sitter lets the host replace its allocator
/// (`ts_set_allocator`), so while a thread is inside `NJSAlloc.parse` its allocations come from a private arena: 1 MB slabs carved out of
/// one reserved virtual range, size-class free lists inside (the churn of a parse is reused), and on `destroy` every slab is replaced by
/// a fresh PROT_NONE mapping, which drops the dirty pages for real. The parser is created and deleted inside the same call.
/// `free` first checks whether the pointer lies in the reserved range; anything else (the syntax highlighter's trees, blocks allocated
/// before the switch, requests above 512 KB) is plain libc malloc / free, so other threads are unaffected.
@_silgen_name("ts_set_allocator")
private func ts_set_allocator(_ m: @convention(c) (Int) -> UnsafeMutableRawPointer?,
                              _ c: @convention(c) (Int, Int) -> UnsafeMutableRawPointer?,
                              _ r: @convention(c) (UnsafeMutableRawPointer?, Int) -> UnsafeMutableRawPointer?,
                              _ f: @convention(c) (UnsafeMutableRawPointer?) -> Void)

/// One parse's arena. Created by `NJSAlloc.parse`, destroyed (explicitly) when the tree is gone.
final class NJSArena {
    fileprivate var slabs: [Int] = []
    fileprivate var cursor: UnsafeMutableRawPointer?
    fileprivate var limit: UnsafeMutableRawPointer?
    fileprivate var heads: [UnsafeMutableRawPointer?]
    fileprivate let lock = NSLock()
    fileprivate var destroyed = false

    fileprivate init() { heads = [UnsafeMutableRawPointer?](repeating: nil, count: NJSAlloc.sizes.count) }

    fileprivate func alloc(_ n: Int) -> UnsafeMutableRawPointer? {
        guard let cls = NJSAlloc.classIndex(n) else { return nil }
        lock.lock(); defer { lock.unlock() }
        if destroyed { return nil }
        let size = NJSAlloc.sizes[cls]
        if let h = heads[cls] {
            heads[cls] = h.load(as: UnsafeMutableRawPointer?.self)         // free list link lives in the (unused) payload
            return h
        }
        let need = size + NJSAlloc.header
        if cursor == nil || cursor! + need > limit! {
            guard let slab = NJSAlloc.acquireSlab() else { return nil }
            slabs.append(slab)
            cursor = NJSAlloc.slabAddress(slab)
            limit = cursor! + NJSAlloc.slabSize
            NJSAlloc.setOwner(slab, Unmanaged.passUnretained(self).toOpaque())
        }
        let block = cursor!
        cursor = block + need
        block.storeBytes(of: UInt32(cls), as: UInt32.self)
        block.storeBytes(of: UInt32(0), toByteOffset: 4, as: UInt32.self)
        block.storeBytes(of: size, toByteOffset: 8, as: Int.self)
        return block + NJSAlloc.header
    }

    fileprivate func free(_ p: UnsafeMutableRawPointer) {
        let block = p - NJSAlloc.header
        let cls = Int(block.load(as: UInt32.self))
        lock.lock(); defer { lock.unlock() }
        if destroyed { return }
        p.storeBytes(of: heads[cls], as: UnsafeMutableRawPointer?.self)
        heads[cls] = p
    }

    fileprivate func release() {
        lock.lock()
        destroyed = true
        let mine = slabs
        slabs = []; cursor = nil; limit = nil
        for i in heads.indices { heads[i] = nil }
        lock.unlock()
        for s in mine { NJSAlloc.releaseSlab(s) }
    }
}

enum NJSAlloc {
    static let header = 16
    static let slabSize = 1 << 20
    private static let regionSize = 64 << 30
    private static let maxBlock = 512 << 10

    /// Block payload sizes: 16 steps up to 512, then ~1.25x steps.
    static let sizes: [Int] = {
        var s = Array(stride(from: 16, through: 512, by: 16))
        var cur = 512
        while cur < maxBlock { cur = min(maxBlock, (Int(Double(cur) * 1.25) + 15) & ~15); s.append(cur) }
        return s
    }()

    static func classIndex(_ n: Int) -> Int? {
        if n > maxBlock { return nil }
        if n <= 512 { return max(0, (n + 15) / 16 - 1) }
        var lo = 32, hi = sizes.count - 1                   // sizes[31] == 512
        while lo < hi { let mid = (lo + hi) / 2; if sizes[mid] >= n { hi = mid } else { lo = mid + 1 } }
        return lo
    }

    // MARK: reserved range

    private static let lock = NSLock()
    private static let base: UnsafeMutableRawPointer? = {
        let p = mmap(nil, regionSize, PROT_NONE, MAP_PRIVATE | MAP_ANON | MAP_NORESERVE, -1, 0)
        return p == MAP_FAILED ? nil : p
    }()
    private static let owners: UnsafeMutablePointer<UnsafeMutableRawPointer?> = {
        let p = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: regionSize / slabSize)
        p.initialize(repeating: nil, count: regionSize / slabSize)
        return p
    }()
    private static var nextSlab = 0
    private static var freeSlabs: [Int] = []
    private static var committedSlabs = 0
    private static var live = 0
    private static var installed = false
    private static let key: pthread_key_t = {
        var k = pthread_key_t()
        pthread_key_create(&k, nil)
        return k
    }()

    fileprivate static func slabAddress(_ i: Int) -> UnsafeMutableRawPointer { base! + i * slabSize }
    fileprivate static func setOwner(_ i: Int, _ o: UnsafeMutableRawPointer) { owners[i] = o }

    fileprivate static func acquireSlab() -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard let base else { return nil }
        let i: Int
        if let f = freeSlabs.popLast() { i = f }
        else if (nextSlab + 1) * slabSize <= regionSize { i = nextSlab; nextSlab += 1 }
        else { return nil }
        guard mprotect(base + i * slabSize, slabSize, PROT_READ | PROT_WRITE) == 0 else { freeSlabs.append(i); return nil }
        committedSlabs += 1
        return i
    }

    fileprivate static func releaseSlab(_ i: Int) {
        lock.lock(); defer { lock.unlock() }
        guard let base else { return }
        owners[i] = nil
        // a fresh PROT_NONE mapping over the slab: the old dirty pages are dropped, the address range stays reserved
        _ = mmap(base + i * slabSize, slabSize, PROT_NONE, MAP_FIXED | MAP_PRIVATE | MAP_ANON | MAP_NORESERVE, -1, 0)
        freeSlabs.append(i)
        committedSlabs -= 1
    }

    @inline(__always) private static func arenaOf(_ p: UnsafeMutableRawPointer) -> NJSArena? {
        guard let b = base, p >= b, p < b + regionSize, let o = owners[(p - b) >> 20] else { return nil }
        return Unmanaged<NJSArena>.fromOpaque(o).takeUnretainedValue()
    }
    @inline(__always) private static func inRegion(_ p: UnsafeMutableRawPointer) -> Bool {
        guard let b = base else { return false }
        return p >= b && p < b + regionSize
    }

    private static func current() -> NJSArena? {
        pthread_getspecific(key).map { Unmanaged<NJSArena>.fromOpaque($0).takeUnretainedValue() }
    }

    // MARK: allocator callbacks

    static func install() {
        lock.lock()
        let already = installed
        installed = true
        lock.unlock()
        guard !already else { return }
        _ = base; _ = key; _ = owners
        ts_set_allocator({ n in NJSAlloc.current()?.alloc(n) ?? malloc(n) },
                         { c, n in
                             let (t, o) = c.multipliedReportingOverflow(by: n)
                             if !o, let a = NJSAlloc.current(), let p = a.alloc(t) { memset(p, 0, t); return p }
                             return calloc(c, n)
                         },
                         { p, n in
                             guard let p else { return NJSAlloc.current()?.alloc(n) ?? malloc(n) }
                             guard NJSAlloc.inRegion(p) else { return realloc(p, n) }
                             let old = (p - NJSAlloc.header).load(fromByteOffset: 8, as: Int.self)
                             if n <= old { return p }
                             guard let arena = NJSAlloc.arenaOf(p), let q = arena.alloc(n) ?? malloc(n) else { return nil }
                             memcpy(q, p, min(old, n))
                             arena.free(p)
                             return q
                         },
                         { p in
                             guard let p else { return }
                             if NJSAlloc.inRegion(p) { NJSAlloc.arenaOf(p)?.free(p) } else { free(p) }
                         })
    }

    /// Runs `body` with this thread's tree-sitter allocations going to a new arena, which the caller owns.
    static func parse<T>(_ body: () -> T) -> (T, NJSArena) {
        install()
        let a = NJSArena()
        lock.lock(); live += 1; lock.unlock()
        pthread_setspecific(key, Unmanaged.passUnretained(a).toOpaque())
        defer { pthread_setspecific(key, nil) }
        return (body(), a)
    }

    /// Returns the arena's memory to the system. Only valid once the parse's tree and every node made from it are gone.
    static func destroy(_ a: NJSArena) {
        a.release()
        lock.lock(); live -= 1; lock.unlock()
    }

    /// Arenas alive right now (tests: must return to 0 when the documents are released).
    static var liveZones: Int { lock.lock(); defer { lock.unlock() }; return live }
    /// Bytes of slabs currently committed to arenas.
    static var committedBytes: Int { lock.lock(); defer { lock.unlock() }; return committedSlabs * slabSize }
}

typealias NJSZone = NJSArena
