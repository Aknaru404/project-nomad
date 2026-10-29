import Foundation

public enum ZimError: LocalizedError {
    case notZim
    case unsupportedCompression(UInt8)
    case corrupt(String)
    case redirectLoop

    public var errorDescription: String? {
        switch self {
        case .notZim: return "This file is not a ZIM archive."
        case .unsupportedCompression(let type): return "Unsupported ZIM compression type \(type)."
        case .corrupt(let detail): return "The ZIM file looks damaged (\(detail))."
        case .redirectLoop: return "The ZIM file contains a redirect loop."
        }
    }
}

public struct ZimEntry: Hashable, Sendable {
    public let index: UInt32
    public let namespace: Character
    public let path: String
    public let title: String
    let mimeIndex: UInt16
    let cluster: UInt32
    let blob: UInt32
    let redirectIndex: UInt32

    public var isRedirect: Bool { mimeIndex == 0xFFFF }
    /// Namespace and path as used in reader URLs, e.g. "C/Water_purification".
    public var fullPath: String { "\(namespace)/\(path)" }
}

public struct ZimContent {
    public let entry: ZimEntry
    public let mimeType: String
    public let data: Data
}

/// Read-only access to a ZIM archive (openzim.org/wiki/ZIM_file_format), read straight from disk.
/// Thread-safe: every public call takes the archive lock.
public final class ZimArchive: @unchecked Sendable {
    public let fileURL: URL
    public let entryCount: UInt32
    public let mimeTypes: [String]
    /// "C" for files written with the 2021 namespace scheme (ZIM 6.1+), "A" for older files.
    public let contentNamespace: Character

    private let handle: FileHandle
    private let lock = NSLock()
    private let fileSize: UInt64
    private let clusterCount: UInt32
    private let urlPtrPos: UInt64
    private let titlePtrPos: UInt64
    private let clusterPtrPos: UInt64
    private let checksumPos: UInt64
    private let mainPageIndex: UInt32

    private var clusterCache: [UInt32: Data] = [:]
    private var clusterCacheOrder: [UInt32] = []
    private static let clusterCacheLimit = 8
    private var titleOrder: [UInt32]?

    public init(url: URL) throws {
        fileURL = url
        handle = try FileHandle(forReadingFrom: url)
        fileSize = try handle.seekToEnd()

        let header = try ZimArchive.read(handle, at: 0, count: 80)
        guard header.count == 80, header.u32(0) == 0x044D_495A else { throw ZimError.notZim }
        let major = header.u16(4)
        let minor = header.u16(6)
        entryCount = header.u32(24)
        clusterCount = header.u32(28)
        urlPtrPos = header.u64(32)
        titlePtrPos = header.u64(40)
        clusterPtrPos = header.u64(48)
        let mimeListPos = header.u64(56)
        mainPageIndex = header.u32(64)
        checksumPos = header.u64(72)
        contentNamespace = (major > 6 || (major == 6 && minor >= 1)) ? "C" : "A"

        // The MIME list is a run of NUL-terminated strings ending with an empty one.
        var mimes: [String] = []
        var offset = mimeListPos
        var pending = Data()
        scan: while true {
            let chunk = try ZimArchive.read(handle, at: offset, count: 4096)
            guard !chunk.isEmpty else { throw ZimError.corrupt("unterminated MIME list") }
            offset += UInt64(chunk.count)
            pending.append(chunk)
            while let zero = pending.firstIndex(of: 0) {
                let name = pending[pending.startIndex..<zero]
                pending = Data(pending[pending.index(after: zero)...])
                if name.isEmpty { break scan }
                mimes.append(String(decoding: name, as: UTF8.self))
            }
        }
        mimeTypes = mimes
    }

    deinit {
        try? handle.close()
    }

    // MARK: - Public API

    public var title: String {
        metadata("Title") ?? fileURL.deletingPathExtension().lastPathComponent
    }

    public func entry(at index: UInt32) throws -> ZimEntry {
        try locked { try readEntry(index) }
    }

    public func entry(namespace: Character, path: String) throws -> ZimEntry? {
        try locked { try findByPath(namespace, path) }
    }

    /// The main page with redirects followed, or nil when the file declares none.
    public func mainEntry() throws -> ZimEntry? {
        try locked {
            if mainPageIndex != 0xFFFF_FFFF { return try resolve(readEntry(mainPageIndex)) }
            if let fallback = try findByPath("W", "mainPage") { return try resolve(fallback) }
            return nil
        }
    }

    public func resolveRedirects(_ entry: ZimEntry) throws -> ZimEntry {
        try locked { try resolve(entry) }
    }

    public func content(of entry: ZimEntry) throws -> ZimContent {
        try locked {
            let target = try resolve(entry)
            guard Int(target.mimeIndex) < mimeTypes.count else { throw ZimError.corrupt("bad MIME index") }
            let data = try readBlob(cluster: target.cluster, blob: target.blob)
            return ZimContent(entry: target, mimeType: mimeTypes[Int(target.mimeIndex)], data: data)
        }
    }

    public func metadata(_ name: String) -> String? {
        guard let entry = try? entry(namespace: "M", path: name),
              let content = try? content(of: entry) else { return nil }
        return String(decoding: content.data, as: UTF8.self)
    }

    /// Title prefix search over the archive's title index. Tries the query as typed and with a capital first letter.
    public func searchTitles(_ query: String, limit: Int = 25) throws -> [ZimEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        var variants = [trimmed]
        let capitalised = trimmed.prefix(1).uppercased() + trimmed.dropFirst()
        if capitalised != trimmed { variants.append(capitalised) }

        return try locked {
            let order = try loadTitleOrder()
            var seen = Set<UInt32>()
            var results: [ZimEntry] = []
            for variant in variants {
                for entry in try prefixMatches(variant, in: order, limit: limit) where seen.insert(entry.index).inserted {
                    results.append(entry)
                }
            }
            return Array(results.prefix(limit))
        }
    }

    // MARK: - Directory entries

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private static func read(_ handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: count) ?? Data()
    }

    private func read(at offset: UInt64, count: Int) throws -> Data {
        try Self.read(handle, at: offset, count: count)
    }

    private func readEntry(_ index: UInt32) throws -> ZimEntry {
        guard index < entryCount else { throw ZimError.corrupt("entry \(index) out of range") }
        let pointer = try read(at: urlPtrPos + UInt64(index) * 8, count: 8)
        guard pointer.count == 8 else { throw ZimError.corrupt("truncated URL pointer list") }
        let offset = pointer.u64(0)

        var size = 512
        while true {
            let raw = try read(at: offset, count: size)
            guard raw.count >= 12 else { throw ZimError.corrupt("truncated directory entry") }
            let mime = raw.u16(0)
            let namespace = Character(Unicode.Scalar(raw[3]))
            let isRedirect = mime == 0xFFFF
            // Redirects carry a 4-byte target, content entries cluster + blob, legacy link/deleted entries nothing.
            let stringsStart = isRedirect ? 12 : (mime >= 0xFFFD ? 8 : 16)
            if let strings = Self.twoStrings(raw, from: stringsStart) {
                let hasLocation = !isRedirect && mime < 0xFFFD
                return ZimEntry(
                    index: index,
                    namespace: namespace,
                    path: strings.path,
                    title: strings.title.isEmpty ? strings.path : strings.title,
                    mimeIndex: mime,
                    cluster: hasLocation ? raw.u32(8) : 0,
                    blob: hasLocation ? raw.u32(12) : 0,
                    redirectIndex: isRedirect ? raw.u32(8) : 0
                )
            }
            guard raw.count == size else { throw ZimError.corrupt("unterminated directory entry") }
            size *= 4
        }
    }

    private static func twoStrings(_ data: Data, from start: Int) -> (path: String, title: String)? {
        guard start <= data.count,
              let first = data[start...].firstIndex(of: 0),
              let second = data[(first + 1)...].firstIndex(of: 0) else { return nil }
        return (String(decoding: data[start..<first], as: UTF8.self),
                String(decoding: data[(first + 1)..<second], as: UTF8.self))
    }

    private func findByPath(_ namespace: Character, _ path: String) throws -> ZimEntry? {
        let key = Array(String(namespace).utf8) + Array(path.utf8)
        var lo: UInt32 = 0
        var hi = entryCount
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            let entry = try readEntry(mid)
            let candidate = Array(String(entry.namespace).utf8) + Array(entry.path.utf8)
            if candidate == key { return entry }
            if candidate.lexicographicallyPrecedes(key) { lo = mid + 1 } else { hi = mid }
        }
        return nil
    }

    private func resolve(_ entry: ZimEntry) throws -> ZimEntry {
        var current = entry
        var hops = 0
        while current.isRedirect {
            hops += 1
            if hops > 32 { throw ZimError.redirectLoop }
            current = try readEntry(current.redirectIndex)
        }
        return current
    }

    // MARK: - Title index

    /// Entry indices in (namespace, title) order: the header list on older files, the X/listing entry on newer ones.
    private func loadTitleOrder() throws -> [UInt32] {
        if let titleOrder { return titleOrder }
        var order: [UInt32] = []
        if titlePtrPos > 0, titlePtrPos != UInt64.max, titlePtrPos + UInt64(entryCount) * 4 <= fileSize {
            order = Self.u32Array(try read(at: titlePtrPos, count: Int(entryCount) * 4))
        } else if let listing = try findByPath("X", "listing/titleOrdered/v1") ?? findByPath("X", "listing/titleOrdered/v0") {
            let target = try resolve(listing)
            order = Self.u32Array(try readBlob(cluster: target.cluster, blob: target.blob))
        }
        titleOrder = order
        return order
    }

    private func titleKey(_ entry: ZimEntry) -> [UInt8] {
        Array(String(entry.namespace).utf8) + Array(entry.title.utf8)
    }

    private func prefixMatches(_ prefix: String, in order: [UInt32], limit: Int) throws -> [ZimEntry] {
        let key = Array(String(contentNamespace).utf8) + Array(prefix.utf8)
        var lo = 0
        var hi = order.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if titleKey(try readEntry(order[mid])).lexicographicallyPrecedes(key) { lo = mid + 1 } else { hi = mid }
        }
        var matches: [ZimEntry] = []
        var i = lo
        while i < order.count, matches.count < limit {
            let entry = try readEntry(order[i])
            guard titleKey(entry).starts(with: key) else { break }
            matches.append(entry)
            i += 1
        }
        return matches
    }

    static func u32Array(_ data: Data) -> [UInt32] {
        data.withUnsafeBytes { raw in
            (0..<(raw.count / 4)).map { raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self).littleEndian }
        }
    }

    // MARK: - Clusters

    private func clusterBounds(_ cluster: UInt32) throws -> (start: UInt64, end: UInt64) {
        guard cluster < clusterCount else { throw ZimError.corrupt("cluster \(cluster) out of range") }
        let pointers = try read(at: clusterPtrPos + UInt64(cluster) * 8, count: 16)
        guard pointers.count >= 8 else { throw ZimError.corrupt("truncated cluster pointer list") }
        let start = pointers.u64(0)
        let end: UInt64
        if cluster + 1 < clusterCount {
            guard pointers.count == 16 else { throw ZimError.corrupt("truncated cluster pointer list") }
            end = pointers.u64(8)
        } else {
            end = (checksumPos > start && checksumPos <= fileSize) ? checksumPos : fileSize
        }
        guard end > start, end <= fileSize else { throw ZimError.corrupt("bad cluster bounds") }
        return (start, end)
    }

    private func readBlob(cluster: UInt32, blob: UInt32) throws -> Data {
        let (start, end) = try clusterBounds(cluster)
        guard let info = try read(at: start, count: 1).first else { throw ZimError.corrupt("empty cluster") }
        let compression = info & 0x0F
        let wide = info & 0x10 != 0

        switch compression {
        case 0, 1:
            // Uncompressed: read only the two offsets and the blob itself, so large media is not loaded whole.
            let width = wide ? 8 : 4
            let base = start + 1
            let first = try read(at: base, count: width)
            guard first.count == width else { throw ZimError.corrupt("truncated cluster") }
            let offsetCount = (wide ? first.u64(0) : UInt64(first.u32(0))) / UInt64(width)
            guard UInt64(blob) + 1 < offsetCount else { throw ZimError.corrupt("blob out of range") }
            let pair = try read(at: base + UInt64(blob) * UInt64(width), count: 2 * width)
            guard pair.count == 2 * width else { throw ZimError.corrupt("truncated cluster") }
            let from = wide ? pair.u64(0) : UInt64(pair.u32(0))
            let to = wide ? pair.u64(width) : UInt64(pair.u32(width))
            guard from <= to, base + to <= end else { throw ZimError.corrupt("bad blob offsets") }
            return try read(at: base + from, count: Int(to - from))
        case 4, 5:
            let data = try decompressedCluster(cluster, start: start, end: end, xz: compression == 4)
            return try Self.blob(in: data, index: blob, wide: wide)
        default:
            throw ZimError.unsupportedCompression(compression)
        }
    }

    private func decompressedCluster(_ cluster: UInt32, start: UInt64, end: UInt64, xz: Bool) throws -> Data {
        if let cached = clusterCache[cluster] { return cached }
        let raw = try read(at: start + 1, count: Int(end - start - 1))
        let data = xz ? try Decompress.xz(raw) : try Decompress.zstd(raw)
        clusterCache[cluster] = data
        clusterCacheOrder.append(cluster)
        if clusterCacheOrder.count > Self.clusterCacheLimit {
            clusterCache[clusterCacheOrder.removeFirst()] = nil
        }
        return data
    }

    static func blob(in data: Data, index: UInt32, wide: Bool) throws -> Data {
        let width = wide ? 8 : 4
        guard data.count >= width else { throw ZimError.corrupt("truncated cluster") }
        func offset(_ i: Int) -> Int { wide ? Int(data.u64(i * width)) : Int(data.u32(i * width)) }
        let offsetCount = offset(0) / width
        let i = Int(index)
        guard i + 1 < offsetCount, (i + 2) * width <= data.count else { throw ZimError.corrupt("blob out of range") }
        let from = offset(i)
        let to = offset(i + 1)
        guard from <= to, to <= data.count else { throw ZimError.corrupt("bad blob offsets") }
        return data.subdata(in: (data.startIndex + from)..<(data.startIndex + to))
    }
}

extension Data {
    func u16(_ offset: Int) -> UInt16 {
        withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }.littleEndian
    }

    func u32(_ offset: Int) -> UInt32 {
        withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }.littleEndian
    }

    func u64(_ offset: Int) -> UInt64 {
        withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }.littleEndian
    }
}
