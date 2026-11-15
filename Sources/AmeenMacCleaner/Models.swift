import AppKit
import Observation
import SwiftUI

enum AppLocation: String, Sendable {
    case applications = "Applications"
    case user = "~/Applications"
    case system = "System"
    case coreServices = "Core Services"
    case other = "Elsewhere on disk"
}

struct AppInfo: Sendable {
    let url: URL
    let name: String
    let bundleID: String?
    let version: String?
    let location: AppLocation
    let isHidden: Bool
    let isAppStore: Bool
    let isProtected: Bool
    let isAgent: Bool
    let isAppleApp: Bool
    let lastUsed: Date?
}

struct RelatedFile: Identifiable, Hashable, Sendable {
    let url: URL
    let category: String
    let size: Int64
    var id: String { url.path }
}

@Observable
final class AppItem: Identifiable {
    let info: AppInfo
    var appSize: Int64?
    var related: [RelatedFile] = []
    var relatedScanned = false

    init(_ info: AppInfo) { self.info = info }

    var id: String { info.url.path }
    var url: URL { info.url }
    var name: String { info.name }
    var bundleID: String? { info.bundleID }
    var version: String? { info.version }
    var isHidden: Bool { info.isHidden }
    var isProtected: Bool { info.isProtected }
    var isAppStore: Bool { info.isAppStore }
    var isAgent: Bool { info.isAgent }
    var lastUsed: Date? { info.lastUsed }
    var location: AppLocation { info.location }

    var relatedSize: Int64 { related.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { (appSize ?? 0) + relatedSize }
    var isMeasured: Bool { appSize != nil }

    var lastUsedText: String {
        guard let d = lastUsed else { return "Never opened" }
        return "Opened " + relativeFormatter.localizedString(for: d, relativeTo: Date())
    }

    var isRunning: Bool {
        guard let id = bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }
}

// MARK: - Junk

struct JunkKind: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let roots: [String]          // relative to home
    var extensions: Set<String>? = nil
    var defaultSelected = true
    var permanent = false        // items are always deleted permanently (Trash)

    static let all: [JunkKind] = [
        JunkKind(id: "caches", title: "User Caches", detail: "Temporary data apps rebuild automatically",
                 symbol: "archivebox.fill", tint: .orange, roots: ["Library/Caches"]),
        JunkKind(id: "logs", title: "Logs & Crash Reports", detail: "Diagnostic logs written by apps and macOS",
                 symbol: "doc.text.fill", tint: .brown, roots: ["Library/Logs"]),
        JunkKind(id: "derived", title: "Xcode Derived Data", detail: "Build products and indexes — rebuilt on next build",
                 symbol: "hammer.fill", tint: .blue, roots: ["Library/Developer/Xcode/DerivedData"]),
        JunkKind(id: "devicesupport", title: "Device Support Files", detail: "Debug symbols for old iPhone/Watch/TV OS versions",
                 symbol: "iphone.gen3", tint: .cyan,
                 roots: ["Library/Developer/Xcode/iOS DeviceSupport", "Library/Developer/Xcode/watchOS DeviceSupport",
                         "Library/Developer/Xcode/tvOS DeviceSupport", "Library/Developer/Xcode/visionOS DeviceSupport"]),
        JunkKind(id: "simcaches", title: "Simulator Caches", detail: "Cached data from the iOS Simulator",
                 symbol: "ipad.and.iphone", tint: .mint, roots: ["Library/Developer/CoreSimulator/Caches"]),
        JunkKind(id: "archives", title: "Xcode Archives", detail: "Old app archives — keep the ones you still need",
                 symbol: "shippingbox.fill", tint: .indigo, roots: ["Library/Developer/Xcode/Archives"], defaultSelected: false),
        JunkKind(id: "devcaches", title: "Developer Tool Caches", detail: "npm, pnpm, Gradle and other package caches",
                 symbol: "terminal.fill", tint: .green, roots: [".npm/_cacache", ".cache", ".gradle/caches", "Library/pnpm/store"]),
        JunkKind(id: "mail", title: "Mail Attachments", detail: "Attachments Mail downloaded when you opened them",
                 symbol: "paperclip", tint: .blue,
                 roots: ["Library/Containers/com.apple.mail/Data/Library/Mail Downloads"]),
        JunkKind(id: "installers", title: "Installer Files", detail: "Disk images and packages in Downloads",
                 symbol: "opticaldiscdrive.fill", tint: .purple, roots: ["Downloads"],
                 extensions: ["dmg", "pkg", "mpkg", "iso", "xip"], defaultSelected: false),
        JunkKind(id: "trash", title: "Trash", detail: "Items already in the Trash — always deleted permanently",
                 symbol: "trash.fill", tint: .gray, roots: [".Trash"], permanent: true),
    ]
}

struct JunkItem: Identifiable, Sendable {
    let url: URL
    let size: Int64
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

@Observable
final class JunkGroup: Identifiable {
    let kind: JunkKind
    var items: [JunkItem] = []
    var selected: Set<String> = []
    var scanned = false
    var scanning = false

    init(kind: JunkKind) { self.kind = kind }

    var id: String { kind.id }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.reduce(0) { selected.contains($1.id) ? $0 + $1.size : $0 } }
}

// MARK: - Leftovers & large files

struct OrphanItem: Identifiable, Sendable {
    let url: URL
    let bundleID: String
    let category: String
    let size: Int64
    var id: String { url.path }
}

struct LargeFile: Identifiable, Sendable {
    let url: URL
    let size: Int64
    let modified: Date
    let accessed: Date
    let isHidden: Bool
    let isPackage: Bool

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var folder: String { url.deletingLastPathComponent().tildePath }
    var kind: String {
        if isPackage { return "Package" }
        let ext = url.pathExtension.uppercased()
        return ext.isEmpty ? "File" : ext
    }
}

// MARK: - Removal

struct RemovalTarget: Sendable {
    let url: URL
    let size: Int64
}

struct RemovalRequest: Identifiable {
    let id = UUID()
    var title: String
    var items: [RemovalTarget]
    var alwaysPermanent: [RemovalTarget] = []
    var quitBundleIDs: [String] = []

    var totalSize: Int64 { (items + alwaysPermanent).reduce(0) { $0 + $1.size } }
    var count: Int { items.count + alwaysPermanent.count }
}
