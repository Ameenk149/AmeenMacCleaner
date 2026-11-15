import AppKit
import CoreServices
import Foundation

// MARK: - Applications

enum AppScanner {
    /// Bundle-like folder extensions: an app nested inside one of these is a helper, not a standalone app.
    private static let bundleExtensions: Set<String> = [
        "app", "framework", "bundle", "plugin", "appex", "xpc", "simruntime", "platform",
        "xcarchive", "kext", "prefpane", "docset", "photoslibrary", "systemextension", "qlgenerator", "wdgt",
    ]
    private static let protectedIDs: Set<String> = ["com.apple.Safari", "com.apple.finder"]

    static func scan() -> [AppInfo] {
        var seen = Set<String>()
        var out: [AppInfo] = []
        let fm = FileManager.default

        func add(_ url: URL, _ loc: AppLocation, hidden: Bool) {
            let key = url.resolvingSymlinksInPath().path
            guard seen.insert(key).inserted else { return }
            if let info = makeInfo(url, loc, forceHidden: hidden) { out.append(info) }
        }

        func walk(_ dir: URL, _ loc: AppLocation, depth: Int, hidden: Bool) {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return }
            for u in items {
                let ext = u.pathExtension.lowercased()
                if ext == "app" {
                    add(u, loc, hidden: hidden)
                } else if depth > 0, !bundleExtensions.contains(ext),
                          (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    walk(u, loc, depth: depth - 1, hidden: hidden)
                }
            }
        }

        walk(URL(fileURLWithPath: "/Applications"), .applications, depth: 2, hidden: false)
        walk(Paths.inHome("Applications"), .user, depth: 2, hidden: false)
        walk(URL(fileURLWithPath: "/System/Applications"), .system, depth: 1, hidden: true)
        walk(URL(fileURLWithPath: "/System/Library/CoreServices"), .coreServices, depth: 1, hidden: true)
        // Apps people forget in their user folders (works even when Spotlight is off)
        for folder in ["Downloads", "Desktop", "Documents"] {
            walk(Paths.inHome(folder), .other, depth: 2, hidden: false)
        }

        // Deep search: every app bundle Spotlight knows about (Downloads, Desktop, external drives, …)
        for path in spotlightApps() {
            let u = URL(fileURLWithPath: path)
            guard includeSpotlightResult(u) else { continue }
            let comps = u.pathComponents
            let hidden = path.contains("/Library/") || comps.dropLast().contains { $0.hasPrefix(".") }
            add(u, .other, hidden: hidden)
        }
        return out
    }

    private static func includeSpotlightResult(_ u: URL) -> Bool {
        let p = u.path
        if p.hasPrefix("/System/") || p.hasPrefix("/private/") || p.hasPrefix("/usr/") || p.hasPrefix("/Library/Apple/") { return false }
        if p.contains("/.Trash/") { return false }
        // Skip apps nested inside other bundles (helpers) — deleting them would break the parent.
        if u.pathComponents.dropLast().contains(where: { bundleExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) { return false }
        if let ro = try? u.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly, ro { return false }
        return FileManager.default.fileExists(atPath: p)
    }

    private static func spotlightApps() -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = ["kMDItemContentType == 'com.apple.application-bundle'"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    private static func truthy(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return s == "1" || s.lowercased() == "yes" || s.lowercased() == "true" }
        return false
    }

    /// Fallback when Spotlight has no "last used" date: the newest of the app's
    /// preferences / saved window state, which macOS updates while the app runs.
    private static func activityDate(bundleID: String) -> Date? {
        let candidates = [
            "Library/Preferences/\(bundleID).plist",
            "Library/Saved Application State/\(bundleID).savedState",
            "Library/Containers/\(bundleID)/Data/Library/Preferences/\(bundleID).plist",
            "Library/Containers/\(bundleID)/Data/Library/Saved Application State/\(bundleID).savedState",
        ]
        return candidates
            .compactMap { try? Paths.inHome($0).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max()
    }

    static func makeInfo(_ url: URL, _ loc: AppLocation, forceHidden: Bool) -> AppInfo? {
        let dict = (NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any])
            ?? (NSDictionary(contentsOf: url.appendingPathComponent("WrappedBundle/Info.plist")) as? [String: Any])
            ?? [:]
        let bid = dict["CFBundleIdentifier"] as? String
        var name = FileManager.default.displayName(atPath: url.path)
        if name.lowercased().hasSuffix(".app") { name = String(name.dropLast(4)) }
        let version = (dict["CFBundleShortVersionString"] as? String) ?? (dict["CFBundleVersion"] as? String)
        let rv = try? url.resourceValues(forKeys: [.isHiddenKey, .volumeIsReadOnlyKey])
        let hidden = forceHidden || rv?.isHidden == true || url.lastPathComponent.hasPrefix(".")
        let isAppStore = FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt").path)
            || FileManager.default.fileExists(atPath: url.appendingPathComponent("WrappedBundle").path)
        let isApple = bid?.hasPrefix("com.apple.") ?? false
        let isProtected = loc == .system || loc == .coreServices || url.path.hasPrefix("/System/")
            || protectedIDs.contains(bid ?? "") || rv?.volumeIsReadOnly == true

        var lastUsed: Date?
        if let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) {
            lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        }
        if lastUsed == nil, let bid {
            lastUsed = activityDate(bundleID: bid)
        }

        return AppInfo(url: url, name: name, bundleID: bid, version: version, location: loc, isHidden: hidden,
                       isAppStore: isAppStore, isProtected: isProtected,
                       isAgent: truthy(dict["LSUIElement"]) || truthy(dict["LSBackgroundOnly"]),
                       isAppleApp: isApple, lastUsed: lastUsed)
    }
}

// MARK: - Library index (support files, caches, preferences, …)

struct LibraryEntry: Sendable {
    let url: URL
    let base: String      // lowercased name with .plist/.savedState/… stripped
    let rawBase: String
    let category: String
    let nameMatch: Bool   // folder may be named after the app's display name
    let isUser: Bool
}

struct LibraryIndex: Sendable {
    let entries: [LibraryEntry]

    private static let suffixes: Set<String> = ["plist", "savedstate", "binarycookies", "bom", "lockfile"]
    private static let roots: [(path: String, category: String, nameMatch: Bool, user: Bool)] = [
        ("Library/Application Support", "Application Support", true, true),
        ("Library/Caches", "Caches", true, true),
        ("Library/Preferences", "Preferences", false, true),
        ("Library/Preferences/ByHost", "Preferences", false, true),
        ("Library/Containers", "Containers", false, true),
        ("Library/Group Containers", "Group Containers", false, true),
        ("Library/Saved Application State", "Saved State", false, true),
        ("Library/Logs", "Logs", true, true),
        ("Library/HTTPStorages", "HTTP Storage", false, true),
        ("Library/WebKit", "WebKit Data", false, true),
        ("Library/Cookies", "Cookies", false, true),
        ("Library/LaunchAgents", "Launch Agents", false, true),
        ("Library/Application Scripts", "App Scripts", false, true),
        ("/Library/Application Support", "Application Support (System)", true, false),
        ("/Library/Caches", "Caches (System)", false, false),
        ("/Library/Preferences", "Preferences (System)", false, false),
        ("/Library/LaunchAgents", "Launch Agents (System)", false, false),
        ("/Library/LaunchDaemons", "Launch Daemons", false, false),
        ("/Library/PrivilegedHelperTools", "Helper Tools", false, false),
        ("/Library/Logs", "Logs (System)", true, false),
        ("/private/var/db/receipts", "Install Receipts", false, false),
    ]

    static func build() -> LibraryIndex {
        var out: [LibraryEntry] = []
        for root in roots {
            let dir = root.user ? Paths.inHome(root.path) : URL(fileURLWithPath: root.path)
            guard let kids = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: []) else { continue }
            for k in kids {
                let name = k.lastPathComponent
                if name == ".DS_Store" || name == ".localized" || name == "ByHost" { continue }
                var raw = name
                while true {
                    let ext = (raw as NSString).pathExtension.lowercased()
                    guard suffixes.contains(ext) else { break }
                    raw = (raw as NSString).deletingPathExtension
                }
                out.append(LibraryEntry(url: k, base: raw.lowercased(), rawBase: raw, category: root.category,
                                        nameMatch: root.nameMatch, isUser: root.user))
            }
        }
        return LibraryIndex(entries: out)
    }

    /// Files in the Library that belong to an app.
    func related(bundleID: String?, name: String, isApple: Bool, otherIDs: Set<String>) -> [LibraryEntry] {
        let bid = bundleID?.lowercased()
        let n1 = name.lowercased()
        let n2 = n1.replacingOccurrences(of: " ", with: "")
        var res: [LibraryEntry] = []
        for e in entries {
            var hit = false
            if let bid, bid.count >= 4 {
                let b = e.base
                if b == bid || b.hasSuffix("." + bid) {
                    hit = true
                } else if b.hasPrefix(bid + ".") {
                    hit = !Self.belongsToMoreSpecific(b, than: bid, otherIDs)
                }
            }
            if !hit, e.nameMatch, !isApple, n1.count >= 4, e.base == n1 || e.base == n2 {
                hit = true
            }
            if hit { res.append(e) }
        }
        return res
    }

    /// e.g. "com.google.chrome.canary" belongs to Chrome Canary, not Chrome.
    private static func belongsToMoreSpecific(_ b: String, than bid: String, _ others: Set<String>) -> Bool {
        let parts = b.split(separator: ".")
        let bidCount = bid.split(separator: ".").count
        var n = parts.count
        while n > bidCount {
            if others.contains(parts[0..<n].joined(separator: ".")) { return true }
            n -= 1
        }
        return false
    }
}

enum Measure {
    static func app(path: String, bundleID: String?, name: String, isApple: Bool, isProtected: Bool,
                    index: LibraryIndex, ids: Set<String>) -> (String, Int64, [RelatedFile]) {
        let size = FileSizer.size(of: URL(fileURLWithPath: path))
        guard !isProtected else { return (path, size, []) }
        var others = ids
        if let b = bundleID?.lowercased() { others.remove(b) }
        let entries = index.related(bundleID: bundleID, name: name, isApple: isApple, otherIDs: others)
        let rel = entries.map { RelatedFile(url: $0.url, category: $0.category, size: FileSizer.size(of: $0.url)) }
            .sorted { $0.size > $1.size }
        return (path, size, rel)
    }
}

// MARK: - Orphaned leftovers

enum OrphanFinder {
    private static let categories: Set<String> = [
        "Application Support", "Caches", "Preferences", "Containers", "Saved State",
        "HTTP Storage", "WebKit Data", "Logs", "Cookies", "App Scripts",
    ]
    private static let tlds: Set<String> = [
        "com", "org", "net", "io", "app", "co", "de", "me", "dev", "ai", "us", "uk", "fr", "jp", "cn", "ru",
        "info", "tv", "ch", "nl", "se", "no", "at", "be", "it", "es", "ca", "au", "ly", "sh", "so", "cc", "xyz", "pl", "eu",
    ]

    static func find(index: LibraryIndex, installed: Set<String>) -> [OrphanItem] {
        var cands: [LibraryEntry] = []
        for e in index.entries where e.isUser && categories.contains(e.category) {
            let b = e.base
            guard looksLikeBundleID(b), !b.hasPrefix("com.apple."), !isInstalled(b, installed) else { continue }
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: e.rawBase) != nil { continue }
            cands.append(e)
        }
        let sizes = FileSizer.sizes(of: cands.map(\.url))
        return zip(cands, sizes)
            .filter { $0.1 > 0 }
            .map { OrphanItem(url: $0.0.url, bundleID: $0.0.rawBase, category: $0.0.category, size: $0.1) }
            .sorted { $0.size > $1.size }
    }

    private static func looksLikeBundleID(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        guard parts.count >= 3, let first = parts.first, tlds.contains(String(first)) else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
    }

    private static func isInstalled(_ b: String, _ installed: Set<String>) -> Bool {
        let parts = b.split(separator: ".")
        var n = parts.count
        while n >= 3 {
            if installed.contains(parts[0..<n].joined(separator: ".")) { return true }
            n -= 1
        }
        return false
    }
}

// MARK: - Junk

enum JunkScanner {
    private static let ignored: Set<String> = [".DS_Store", ".localized"]

    static func scan(_ kind: JunkKind) -> [JunkItem] {
        var urls: [URL] = []
        for root in kind.roots {
            let dir = Paths.inHome(root)
            let kids = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])) ?? []
            for k in kids where !ignored.contains(k.lastPathComponent) {
                if let exts = kind.extensions, !exts.contains(k.pathExtension.lowercased()) { continue }
                urls.append(k)
            }
        }
        let sizes = FileSizer.sizes(of: urls)
        return zip(urls, sizes)
            .filter { $0.1 > 0 }
            .map { JunkItem(url: $0.0, size: $0.1) }
            .sorted { $0.size > $1.size }
    }
}

// MARK: - Large files

enum LargeFileScanner {
    static func scan(minBytes: Int64, cancel: CancelFlag, progress: @escaping @Sendable (Int) -> Void) -> [LargeFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey,
                                      .fileAllocatedSizeKey, .contentModificationDateKey, .contentAccessDateKey]
        let home = Paths.home
        guard let en = FileManager.default.enumerator(at: home, includingPropertiesForKeys: keys,
                                                      options: [.skipsPackageDescendants], errorHandler: { _, _ in true })
        else { return [] }
        // Folders covered elsewhere (Junk / Trash) or full of tiny files.
        let skip: Set<String> = [Paths.trash.path, Paths.inHome("Library/CloudStorage").path, Paths.inHome("Library/Mobile Documents").path,
                                 Paths.inHome("Library/Caches").path, Paths.inHome("Library/Developer/Xcode/DerivedData").path,
                                 Paths.inHome(".npm").path, Paths.inHome(".cache").path, Paths.inHome(".gradle/caches").path]
        let skipNames: Set<String> = ["node_modules", ".git", ".build", "Pods"]
        var out: [LargeFile] = []
        var count = 0
        while let u = en.nextObject() as? URL {
            if cancel.isCancelled { break }
            count += 1
            if count % 1500 == 0 { progress(count) }
            if skip.contains(u.path) || skipNames.contains(u.lastPathComponent) { en.skipDescendants(); continue }
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isSymbolicLink != true else { continue }
            var size: Int64 = 0
            let isPackage = v.isPackage == true
            if isPackage {
                if u.pathExtension.lowercased() == "app" { continue } // apps are handled in Applications
                size = FileSizer.size(of: u)
            } else if v.isRegularFile == true {
                size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
            guard size >= minBytes else { continue }
            let rel = u.path.dropFirst(home.path.count)
            let hidden = rel.hasPrefix("/Library/") || rel.split(separator: "/").contains { $0.hasPrefix(".") }
            out.append(LargeFile(url: u, size: size, modified: v.contentModificationDate ?? .distantPast,
                                 accessed: v.contentAccessDate ?? .distantPast, isHidden: hidden, isPackage: isPackage))
        }
        progress(count)
        return out.sorted { $0.size > $1.size }
    }
}
