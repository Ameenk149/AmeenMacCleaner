import AppKit
import Foundation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let trash = home.appendingPathComponent(".Trash")
    static func inHome(_ relative: String) -> URL { home.appendingPathComponent(relative) }
}

extension Int64 {
    var bytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

extension URL {
    /// Path with the home folder shortened to "~".
    var tildePath: String {
        let h = Paths.home.path
        return path.hasPrefix(h) ? "~" + path.dropFirst(h.count) : path
    }

    /// True if something exists at this path (does not follow symlinks).
    var existsOnDisk: Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)) != nil
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([self])
    }
}

enum FileSizer {
    private static let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

    /// On-disk (allocated) size of a file or folder, recursively.
    static func size(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        while let f = en.nextObject() as? URL {
            if let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true {
                total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    /// Sizes many URLs in parallel.
    static func sizes(of urls: [URL]) -> [Int64] {
        let box = LockedArray(count: urls.count)
        DispatchQueue.concurrentPerform(iterations: urls.count) { i in
            box.set(i, size(of: urls[i]))
        }
        return box.values
    }
}

final class LockedArray: @unchecked Sendable {
    private var storage: [Int64]
    private let lock = NSLock()
    init(count: Int) { storage = Array(repeating: 0, count: count) }
    func set(_ i: Int, _ v: Int64) { lock.lock(); storage[i] = v; lock.unlock() }
    var values: [Int64] { lock.lock(); defer { lock.unlock() }; return storage }
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}

@MainActor
enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()
    static func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let img = cache.object(forKey: key) { return img }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(img, forKey: key)
        return img
    }
}

struct DiskInfo {
    var name: String
    var total: Int64
    var free: Int64
    var used: Int64 { max(0, total - free) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DiskInfo {
        let url = URL(fileURLWithPath: "/")
        let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeLocalizedNameKey])
        let free = v?.volumeAvailableCapacityForImportantUsage ?? Int64(v?.volumeAvailableCapacity ?? 0)
        return DiskInfo(name: v?.volumeLocalizedName ?? "Macintosh HD", total: Int64(v?.volumeTotalCapacity ?? 0), free: free)
    }
}

enum Permissions {
    static func hasFullDiskAccess() -> Bool {
        let probes = [
            Paths.inHome("Library/Safari/Bookmarks.plist").path,
            Paths.inHome("Library/Safari/CloudTabs.db").path,
            "/Library/Application Support/com.apple.TCC/TCC.db",
        ]
        for p in probes where FileManager.default.fileExists(atPath: p) {
            if let h = FileHandle(forReadingAtPath: p) { try? h.close(); return true }
        }
        return false
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f
}()
