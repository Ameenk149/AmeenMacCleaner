import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppState {
    // Applications
    var apps: [AppItem] = []
    var isScanningApps = false
    var appsMeasured = 0
    var appsScanned = false

    // Junk
    var junkGroups: [JunkGroup] = JunkKind.all.map { JunkGroup(kind: $0) }
    var isScanningJunk = false
    var junkScanned = false

    // Leftovers of removed apps
    var orphans: [OrphanItem] = []
    var orphanSelection: Set<String> = []
    var isScanningOrphans = false
    var orphansScanned = false

    // Large files
    var largeFiles: [LargeFile] = []
    var isScanningLarge = false
    var largeScannedCount = 0
    var largeScanned = false
    var largeThresholdMB = 100

    // General
    var disk = DiskInfo.current()
    var trashSize: Int64 = 0
    var hasFullDiskAccess = Permissions.hasFullDiskAccess()
    var toast: String?
    var failureReport: String?
    var pendingRemoval: RemovalRequest?
    var showHidden = UserDefaults.standard.bool(forKey: "showHidden") {
        didSet { UserDefaults.standard.set(showHidden, forKey: "showHidden") }
    }

    let explorer = ExplorerModel()

    @ObservationIgnored private var installedIDs: Set<String> = []
    @ObservationIgnored private var largeCancel: CancelFlag?
    @ObservationIgnored private var didLoad = false

    // MARK: Derived

    var visibleApps: [AppItem] { showHidden ? apps : apps.filter { !$0.isHidden } }
    var appsTotal: Int64 { visibleApps.reduce(0) { $0 + $1.totalSize } }
    var junkTotal: Int64 { junkGroups.filter { !$0.kind.permanent }.reduce(0) { $0 + $1.totalSize } }
    var junkSelectedTotal: Int64 { junkGroups.reduce(0) { $0 + $1.selectedSize } }
    var junkItemCount: Int { junkGroups.filter { !$0.kind.permanent }.reduce(0) { $0 + $1.items.count } }
    var orphanTotal: Int64 { orphans.reduce(0) { $0 + $1.size } }
    var visibleLargeFiles: [LargeFile] { showHidden ? largeFiles : largeFiles.filter { !$0.isHidden } }
    var largeTotal: Int64 { visibleLargeFiles.reduce(0) { $0 + $1.size } }
    var reclaimable: Int64 { junkTotal + trashSize + orphanTotal }
    var isSmartScanning: Bool { isScanningApps || isScanningJunk || isScanningOrphans }

    // MARK: Loading

    func initialLoad() async {
        guard !didLoad else { return }
        didLoad = true
        await smartScan()
    }

    func smartScan() async {
        refreshDisk()
        async let a: Void = scanApps()
        async let j: Void = scanJunk()
        _ = await (a, j)
        await scanOrphans()
        await refreshTrash()
    }

    func refreshDisk() {
        disk = DiskInfo.current()
        hasFullDiskAccess = Permissions.hasFullDiskAccess()
    }

    func refreshTrash() async {
        trashSize = await Task.detached { FileSizer.size(of: Paths.trash) }.value
    }

    func scanApps() async {
        guard !isScanningApps else { return }
        isScanningApps = true
        appsMeasured = 0
        defer { isScanningApps = false; appsScanned = true }

        let infos = await Task.detached(priority: .userInitiated) { AppScanner.scan() }.value
        let items = infos.map(AppItem.init)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        apps = items
        let ids = Set(infos.compactMap { $0.bundleID?.lowercased() })
        installedIDs = ids

        let index = await Task.detached { LibraryIndex.build() }.value
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let inputs = items.map { ($0.id, $0.bundleID, $0.name, $0.info.isAppleApp, $0.isProtected) }

        await withTaskGroup(of: (String, Int64, [RelatedFile]).self) { group in
            var next = 0
            func enqueue() {
                guard next < inputs.count else { return }
                let i = inputs[next]
                next += 1
                group.addTask {
                    Measure.app(path: i.0, bundleID: i.1, name: i.2, isApple: i.3, isProtected: i.4, index: index, ids: ids)
                }
            }
            for _ in 0..<6 { enqueue() }
            for await (id, size, rel) in group {
                if let app = byID[id] {
                    app.appSize = size
                    app.related = rel
                    app.relatedScanned = true
                }
                appsMeasured += 1
                enqueue()
            }
        }
    }

    func scanJunk() async {
        guard !isScanningJunk else { return }
        isScanningJunk = true
        for g in junkGroups { g.scanning = true }
        await withTaskGroup(of: (String, [JunkItem]).self) { group in
            for g in junkGroups {
                let kind = g.kind
                group.addTask { (kind.id, JunkScanner.scan(kind)) }
            }
            for await (id, items) in group {
                guard let g = junkGroups.first(where: { $0.id == id }) else { continue }
                g.items = items
                g.selected = g.kind.defaultSelected ? Set(items.map(\.id)) : []
                g.scanned = true
                g.scanning = false
            }
        }
        junkScanned = true
        isScanningJunk = false
    }

    func scanOrphans() async {
        guard !isScanningOrphans else { return }
        isScanningOrphans = true
        if installedIDs.isEmpty {
            let infos = await Task.detached { AppScanner.scan() }.value
            installedIDs = Set(infos.compactMap { $0.bundleID?.lowercased() })
        }
        let ids = installedIDs
        let found = await Task.detached(priority: .userInitiated) {
            OrphanFinder.find(index: LibraryIndex.build(), installed: ids)
        }.value
        orphans = found
        orphanSelection = []
        orphansScanned = true
        isScanningOrphans = false
    }

    func scanLarge() {
        largeCancel?.cancel()
        let flag = CancelFlag()
        largeCancel = flag
        isScanningLarge = true
        largeScannedCount = 0
        largeFiles = []
        let minBytes = Int64(largeThresholdMB) * 1_000_000
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                LargeFileScanner.scan(minBytes: minBytes, cancel: flag) { n in
                    Task { @MainActor [weak self] in
                        if self?.largeCancel === flag { self?.largeScannedCount = n }
                    }
                }
            }.value
            guard largeCancel === flag else { return }
            largeFiles = result
            largeScanned = true
            isScanningLarge = false
        }
    }

    func stopLarge() {
        largeCancel?.cancel()
    }

    // MARK: Removal requests

    func requestUninstall(_ app: AppItem, includeApp: Bool, files: [RelatedFile]) {
        var targets = files.map { RemovalTarget(url: $0.url, size: $0.size) }
        if includeApp { targets.insert(RemovalTarget(url: app.url, size: app.appSize ?? 0), at: 0) }
        guard !targets.isEmpty else { return }
        pendingRemoval = RemovalRequest(
            title: includeApp ? "Uninstall \(app.name)?" : "Remove \(targets.count) files of \(app.name)?",
            items: targets,
            quitBundleIDs: includeApp ? [app.bundleID].compactMap { $0 } : [])
    }

    func requestBatchUninstall(_ list: [AppItem]) {
        let removable = list.filter { !$0.isProtected }
        var targets: [RemovalTarget] = []
        for app in removable {
            targets.append(RemovalTarget(url: app.url, size: app.appSize ?? 0))
            targets += app.related.map { RemovalTarget(url: $0.url, size: $0.size) }
        }
        guard !targets.isEmpty else { return }
        pendingRemoval = RemovalRequest(title: "Uninstall \(removable.count) apps?", items: targets,
                                        quitBundleIDs: removable.compactMap(\.bundleID))
    }

    func requestJunkClean() {
        var normal: [RemovalTarget] = []
        var permanent: [RemovalTarget] = []
        for g in junkGroups {
            for i in g.items where g.selected.contains(i.id) {
                let t = RemovalTarget(url: i.url, size: i.size)
                if g.kind.permanent { permanent.append(t) } else { normal.append(t) }
            }
        }
        guard !(normal.isEmpty && permanent.isEmpty) else { return }
        let total = (normal + permanent).reduce(0) { $0 + $1.size }
        pendingRemoval = RemovalRequest(title: "Clean \(total.bytes) of junk?", items: normal, alwaysPermanent: permanent)
    }

    func requestOrphanRemoval() {
        let targets = orphans.filter { orphanSelection.contains($0.id) }.map { RemovalTarget(url: $0.url, size: $0.size) }
        guard !targets.isEmpty else { return }
        pendingRemoval = RemovalRequest(title: "Remove \(targets.count) leftover items?", items: targets)
    }

    func requestLargeRemoval(_ ids: Set<String>) {
        let targets = largeFiles.filter { ids.contains($0.id) }.map { RemovalTarget(url: $0.url, size: $0.size) }
        guard !targets.isEmpty else { return }
        pendingRemoval = RemovalRequest(title: "Remove \(targets.count) large files?", items: targets)
    }

    func requestEmptyTrash() {
        Task {
            guard let kids = try? FileManager.default.contentsOfDirectory(at: Paths.trash, includingPropertiesForKeys: nil) else {
                // No direct access to ~/.Trash — let Finder do it.
                if Remover.emptyTrashViaFinder() { showToast("Trash emptied") }
                refreshDisk()
                await refreshTrash()
                return
            }
            guard !kids.isEmpty else { showToast("The Trash is already empty"); return }
            let sizes = await Task.detached { FileSizer.sizes(of: kids) }.value
            let targets = zip(kids, sizes).map { RemovalTarget(url: $0.0, size: $0.1) }
            pendingRemoval = RemovalRequest(title: "Empty the Trash?", items: [], alwaysPermanent: targets)
        }
    }

    // MARK: Perform removal

    func perform(_ req: RemovalRequest, permanently: Bool) {
        Task {
            if !req.quitBundleIDs.isEmpty, !(await quitApps(req.quitBundleIDs)) {
                showToast("Some apps didn't quit — removing anyway")
            }
            var out = Remover.Outcome()
            if !req.items.isEmpty { out.merge(await Remover.remove(req.items, permanently: permanently)) }
            if !req.alwaysPermanent.isEmpty { out.merge(await Remover.remove(req.alwaysPermanent, permanently: true)) }
            apply(out)

            if !out.removed.isEmpty {
                let toTrash = !permanently && !req.items.isEmpty
                showToast(toTrash
                    ? "Moved \(out.bytes.bytes) to the Trash — empty it to free the space"
                    : "Freed \(out.bytes.bytes)")
            }
            if !out.failed.isEmpty {
                let lines = out.failed.prefix(12).map { "• \($0.0.tildePath) — \($0.1)" }.joined(separator: "\n")
                let more = out.failed.count > 12 ? "\n…and \(out.failed.count - 12) more" : ""
                failureReport = lines + more
            }
            refreshDisk()
            await refreshTrash()
        }
    }

    private func apply(_ out: Remover.Outcome) {
        let removed = Set(out.removed.map(\.path))
        guard !removed.isEmpty else { return }
        apps.removeAll { removed.contains($0.url.path) }
        for app in apps where app.related.contains(where: { removed.contains($0.url.path) }) {
            app.related.removeAll { removed.contains($0.url.path) }
        }
        for g in junkGroups {
            g.items.removeAll { removed.contains($0.id) }
            g.selected.subtract(removed)
        }
        // Anything that was in ~/.Trash is gone after emptying.
        if let trash = junkGroups.first(where: { $0.kind.permanent }) {
            trash.items.removeAll { !$0.url.existsOnDisk }
        }
        orphans.removeAll { removed.contains($0.id) }
        orphanSelection.subtract(removed)
        largeFiles.removeAll { removed.contains($0.id) }
        explorer.invalidate(removed)
    }

    private func quitApps(_ ids: [String]) async -> Bool {
        let me = Bundle.main.bundleIdentifier
        let running = ids.filter { $0 != me }.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
        guard !running.isEmpty else { return true }
        running.forEach { $0.terminate() }
        for _ in 0..<24 {
            if running.allSatisfy(\.isTerminated) { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return running.allSatisfy(\.isTerminated)
    }

    func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(4))
            if toast == text { toast = nil }
        }
    }
}
