import Foundation

/// Identity of a file's on-disk state (mtime, size, inode). Used to notice external changes, including atomic replaces.
struct FileStamp: Equatable {
    var seconds: Int
    var nanos: Int
    var size: Int64
    var inode: UInt64

    var date: Date { Date(timeIntervalSince1970: Double(seconds) + Double(nanos) / 1e9) }
}

enum FileIOError: LocalizedError, Equatable {
    case isDirectory
    case readOnly
    case cannotEncode(String)
    case posix(Int32)

    var errorDescription: String? {
        switch self {
        case .isDirectory: return "The path is now a directory."
        case .readOnly: return "The file is read-only on disk."
        case .cannotEncode(let name): return "The text contains characters that cannot be stored as \(name)."
        case .posix(let code): return String(cString: strerror(code))
        }
    }
}

/// Symlink-, permission- and attribute-safe file access.
enum FileIO {
    /// The real file a path refers to: symlinked files and directories are followed (also dangling links and deleted files:
    /// the parent directory is resolved and a dangling final link is followed to where it points).
    static func resolve(_ url: URL) -> URL {
        var path = url.path
        var hops = 0
        while hops < 32 {
            var st = stat()
            guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFLNK else { break }
            guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else { break }
            path = dest.hasPrefix("/") ? dest : ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(dest)
            hops += 1
        }
        if let real = realpath(path, nil) {
            defer { free(real) }
            return URL(fileURLWithPath: String(cString: real))
        }
        let parent = (path as NSString).deletingLastPathComponent
        if !parent.isEmpty, let real = realpath(parent, nil) {
            defer { free(real) }
            return URL(fileURLWithPath: String(cString: real)).appendingPathComponent((path as NSString).lastPathComponent)
        }
        return URL(fileURLWithPath: path)
    }

    /// Follows symlinks (unlike `FileManager.attributesOfItem`, which describes the link itself).
    static func stamp(_ url: URL) -> FileStamp? {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return nil }
        return FileStamp(seconds: Int(st.st_mtimespec.tv_sec), nanos: Int(st.st_mtimespec.tv_nsec), size: Int64(st.st_size), inode: UInt64(st.st_ino))
    }

    enum Kind { case missing, file, directory }
    static func kind(_ url: URL) -> Kind {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return .missing }
        return (st.st_mode & S_IFMT) == S_IFDIR ? .directory : .file
    }

    /// Writes `data` to the real target of `url` through a temp file in the same directory (renamed into place), keeping the
    /// file's permissions, ownership (best effort) and extended attributes. A read-only file is refused unless
    /// `overwriteReadOnly` (the permissions then stay read-only). The temp file never outlives a failure.
    static func write(_ data: Data, to url: URL, overwriteReadOnly: Bool = false) throws {
        let target = resolve(url)
        var st = stat()
        let exists = stat(target.path, &st) == 0
        if exists {
            if (st.st_mode & S_IFMT) == S_IFDIR { throw FileIOError.isDirectory }
            if access(target.path, W_OK) != 0 {
                guard overwriteReadOnly else { throw FileIOError.readOnly }
            }
        }
        let mode: mode_t
        if exists { mode = st.st_mode & 0o7777 } else {
            let mask = umask(0); umask(mask)
            mode = 0o666 & ~mask
        }
        let dir = target.deletingLastPathComponent().path
        var template = Array((dir + "/.\(target.lastPathComponent).ce-XXXXXX").utf8CString)
        let fd = mkstemp(&template)
        if fd < 0 {
            // Directory not writable: fall back to rewriting the file in place.
            if exists, errno == EACCES || errno == EPERM { try writeInPlace(data, to: target, mode: mode, original: st) }
            else { throw FileIOError.posix(errno) }
            return
        }
        let temp = String(cString: template)
        var renamed = false, closed = false
        defer { if !renamed { unlink(temp) } }
        do {
            try writeAll(fd, data)
            fsync(fd)
            fchmod(fd, mode)
            if exists { _ = fchown(fd, st.st_uid, st.st_gid) }
            close(fd); closed = true
            if exists { _ = copyfile(target.path, temp, nil, copyfile_flags_t(COPYFILE_XATTR)) }
            guard rename(temp, target.path) == 0 else { throw FileIOError.posix(errno) }
            renamed = true
        } catch {
            if !closed { close(fd) }
            throw error
        }
    }

    private static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < buffer.count {
                let n = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if n < 0 { if errno == EINTR { continue }; throw FileIOError.posix(errno) }
                offset += n
            }
        }
    }

    private static func writeInPlace(_ data: Data, to target: URL, mode: mode_t, original: stat) throws {
        let needsChmod = mode & 0o200 == 0
        if needsChmod { chmod(target.path, mode | 0o200) }
        defer { if needsChmod { chmod(target.path, mode) } }
        let fd = open(target.path, O_WRONLY | O_TRUNC)
        guard fd >= 0 else { throw FileIOError.posix(errno) }
        defer { close(fd) }
        try writeAll(fd, data)
        fsync(fd)
    }
}

/// Text encodings the editor can read and write, with the byte-order mark handling.
enum TextEncodings {
    struct Choice { let name: String; let encoding: String.Encoding }

    static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

    static let choices: [Choice] = [
        Choice(name: "UTF-8", encoding: .utf8), Choice(name: "UTF-16 LE", encoding: .utf16LittleEndian),
        Choice(name: "UTF-16 BE", encoding: .utf16BigEndian), Choice(name: "Latin-1", encoding: .isoLatin1),
        Choice(name: "Windows-1252", encoding: .windowsCP1252), Choice(name: "Shift-JIS", encoding: .shiftJIS),
        Choice(name: "GB18030", encoding: gb18030),
    ]

    static func name(_ encoding: String.Encoding, bom: Bool) -> String {
        let base = choices.first { $0.encoding == encoding }?.name ?? String.localizedName(of: encoding)
        return bom && encoding == .utf8 ? "UTF-8 BOM" : base
    }

    static func bomBytes(for encoding: String.Encoding) -> [UInt8] {
        switch encoding {
        case .utf8: return [0xEF, 0xBB, 0xBF]
        case .utf16LittleEndian: return [0xFF, 0xFE]
        case .utf16BigEndian: return [0xFE, 0xFF]
        default: return []
        }
    }

    /// The encoding announced by a byte-order mark, and the mark's length.
    static func sniffBOM(_ data: Data) -> (String.Encoding, Int)? {
        let b = [UInt8](data.prefix(3))
        if b.count >= 3, b[0] == 0xEF, b[1] == 0xBB, b[2] == 0xBF { return (.utf8, 3) }
        if b.count >= 2, b[0] == 0xFF, b[1] == 0xFE { return (.utf16LittleEndian, 2) }
        if b.count >= 2, b[0] == 0xFE, b[1] == 0xFF { return (.utf16BigEndian, 2) }
        return nil
    }
}
