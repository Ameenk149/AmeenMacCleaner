import AppKit
import Observation
import SwiftUI

/// Remembers the size of every folder it has measured, so drilling down into
/// a folder whose parent was already measured is instant.
final class SizeCache: @unchecked Sendable {
    static let shared = SizeCache()
    private var map: [String: Int64] = [:]
    private let lock = NSLock()
    private static let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

    func cached(_ path: String) -> Int64? {
        lock.lock(); defer { lock.unlock() }
        return map[path]
    }

    private func store(_ path: String, _ size: Int64) {
        lock.lock(); map[path] = size; lock.unlock()
    }

    /// Recursive on-disk size of a folder; records every subfolder along the way.
    func measure(_ url: URL) -> Int64 {
        if let c = cached(url.path) { return c }
        let keySet = Set(Self.keys)
        guard let kids = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Self.keys, options: []) else {
            store(url.path, 0)
            return 0
        }
        var total: Int64 = 0
        for k in kids {
            guard let v = try? k.resourceValues(forKeys: keySet), v.isSymbolicLink != true else { continue }
            if v.isDirectory == true {
                total += measure(k)
            } else {
                total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
        }
        store(url.path, total)
        return total
    }

    /// Forget removed paths, everything under them, and every folder above them.
    func invalidate(_ paths: Set<String>) {
        guard !paths.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let prefixes = paths.map { $0 + "/" }
        map = map.filter { key, _ in !paths.contains(key) && !prefixes.contains { key.hasPrefix($0) } }
        for p in paths {
            var url = URL(fileURLWithPath: p).deletingLastPathComponent()
            while url.path != "/" {
                map[url.path] = nil
                url = url.deletingLastPathComponent()
            }
        }
    }
}

struct ExplorerEntry: Identifiable, Sendable {
    let url: URL
    let isFolder: Bool      // a normal folder you can open
    let isPackage: Bool     // .app, .photoslibrary, … (sized like a folder, opened in Finder)
    let isHidden: Bool
    let fileSize: Int64

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var needsMeasuring: Bool { isFolder || isPackage }
}

@Observable
final class ExplorerFolder {
    let url: URL
    var entries: [ExplorerEntry] = []
    var sizes: [String: Int64] = [:]
    var loading = true
    var stale = false
    var unreadable = false

    init(url: URL) { self.url = url }

    func size(of e: ExplorerEntry) -> Int64? { e.needsMeasuring ? sizes[e.id] : e.fileSize }
    var pendingCount: Int { entries.filter { $0.needsMeasuring && sizes[$0.id] == nil }.count }
    var folderCount: Int { entries.filter(\.needsMeasuring).count }
    func total(includeHidden: Bool) -> Int64 {
        entries.filter { includeHidden || !$0.isHidden }.reduce(0) { $0 + (size(of: $1) ?? 0) }
    }
}

@MainActor
@Observable
final class ExplorerModel {
    var stack: [URL] = [Paths.home]
    var folders: [String: ExplorerFolder] = [:]

    var current: URL { stack.last ?? Paths.home }
    var currentFolder: ExplorerFolder? { folders[current.path] }

    func open(_ url: URL) {
        stack.append(url)
        load(url)
    }

    func jump(to index: Int) {
        stack = Array(stack.prefix(index + 1))
        load(current)
    }

    func setRoot(_ url: URL) {
        stack = [url]
        load(url)
    }

    func reload() {
        SizeCache.shared.invalidate([current.path])
        load(current, force: true)
    }

    func load(_ url: URL, force: Bool = false) {
        if let f = folders[url.path], !f.stale, !force { return }
        let folder = ExplorerFolder(url: url)
        folders[url.path] = folder
        Task {
            let listed = await Task.detached(priority: .userInitiated) { Self.list(url) }.value
            guard let entries = listed else {
                folder.unreadable = true
                folder.loading = false
                return
            }
            folder.entries = entries
            // Already-known sizes show up immediately.
            for e in entries where e.needsMeasuring {
                if let c = SizeCache.shared.cached(e.id) { folder.sizes[e.id] = c }
            }
            let todo = entries.filter { $0.needsMeasuring && folder.sizes[$0.id] == nil }.map(\.url)
            await withTaskGroup(of: (String, Int64).self) { group in
                var next = 0
                func enqueue() {
                    guard next < todo.count else { return }
                    let u = todo[next]
                    next += 1
                    group.addTask { (u.path, SizeCache.shared.measure(u)) }
                }
                for _ in 0..<6 { enqueue() }
                for await (path, size) in group {
                    folder.sizes[path] = size
                    enqueue()
                }
            }
            folder.loading = false
        }
    }

    /// Called after files were deleted anywhere in the app.
    func invalidate(_ removed: Set<String>) {
        guard !removed.isEmpty else { return }
        SizeCache.shared.invalidate(removed)
        for f in folders.values {
            f.entries.removeAll { removed.contains($0.id) }
            f.stale = true
        }
        load(current, force: true)
    }

    nonisolated static func list(_ url: URL) -> [ExplorerEntry]? {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isHiddenKey,
                                      .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let kids = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: []) else { return nil }
        return kids.compactMap { k in
            guard let v = try? k.resourceValues(forKeys: Set(keys)) else { return nil }
            if v.isSymbolicLink == true { return nil }
            let isDir = v.isDirectory == true
            let isPkg = isDir && v.isPackage == true
            return ExplorerEntry(url: k, isFolder: isDir && !isPkg, isPackage: isPkg,
                                 isHidden: k.lastPathComponent.hasPrefix(".") || v.isHidden == true,
                                 fileSize: isDir ? 0 : Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0))
        }
    }
}
