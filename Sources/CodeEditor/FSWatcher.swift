import Foundation
import CoreServices

/// Light FSEvents wrapper: reports changed paths under a folder (coalesced by `latency`).
/// Events are received and pre-filtered on a utility queue (a `node_modules` / build-output storm never touches the main
/// thread); only paths that pass `filter` are delivered, on the main queue. `excluded` directories are not even reported
/// by the kernel stream (FSEvents allows up to 8).
final class FSWatcher {
    private var stream: FSEventStreamRef?
    private let handler: ([String]) -> Void
    private let filter: (([String]) -> [String])?
    private static let queue = DispatchQueue(label: "fswatcher", qos: .utility)

    init?(path: String, latency: TimeInterval = 0.6, excluded: [String] = [], filter: (([String]) -> [String])? = nil,
          handler: @escaping ([String]) -> Void) {
        self.handler = handler
        self.filter = filter
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = Array((unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []).prefix(count))
            let kept = watcher.filter?(list) ?? list
            guard !kept.isEmpty else { return }
            DispatchQueue.main.async { [weak watcher] in watcher?.handler(kept) }
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard let stream = FSEventStreamCreate(nil, callback, &context, [path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        else { return nil }
        self.stream = stream
        let fm = FileManager.default
        let existing = excluded.filter { fm.fileExists(atPath: $0) }.prefix(8)
        if !existing.isEmpty { FSEventStreamSetExclusionPaths(stream, Array(existing) as CFArray) }
        FSEventStreamSetDispatchQueue(stream, Self.queue)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
