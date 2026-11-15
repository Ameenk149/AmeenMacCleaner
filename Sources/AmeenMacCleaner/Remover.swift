import AppKit
import Foundation

enum Remover {
    struct Outcome {
        var removed: [URL] = []
        var failed: [(URL, String)] = []
        var bytes: Int64 = 0

        mutating func merge(_ o: Outcome) {
            removed += o.removed
            failed += o.failed
            bytes += o.bytes
        }
    }

    /// Folders that must never be removed themselves (only their contents).
    private static let forbidden: Set<String> = {
        let h = Paths.home.path
        var s: Set<String> = ["/", "/Applications", "/Library", "/System", "/Users", "/private", "/usr", "/bin", "/sbin",
                              "/opt", "/var", "/etc", "/Volumes", h, Paths.trash.path]
        for sub in ["Library", "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Applications",
                    ".npm", ".cache", ".gradle"] {
            s.insert(h + "/" + sub)
        }
        for sub in ["Application Support", "Caches", "Preferences", "Containers", "Group Containers", "Logs",
                    "Saved Application State", "HTTPStorages", "WebKit", "Cookies", "LaunchAgents", "Developer",
                    "Application Scripts", "Mail"] {
            s.insert(h + "/Library/" + sub)
            s.insert("/Library/" + sub)
        }
        return s
    }()

    static func isSafe(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        if forbidden.contains(p) { return false }
        if p.hasPrefix("/System/") || p.hasPrefix("/usr/") || p.hasPrefix("/bin/") || p.hasPrefix("/sbin/") { return false }
        return url.standardizedFileURL.pathComponents.count >= 3
    }

    @MainActor
    static func remove(_ items: [RemovalTarget], permanently: Bool) async -> Outcome {
        var out = Outcome()
        var retry: [RemovalTarget] = []
        for t in items {
            guard isSafe(t.url) else { out.failed.append((t.url, "Protected location")); continue }
            do {
                if permanently {
                    try FileManager.default.removeItem(at: t.url)
                } else {
                    try FileManager.default.trashItem(at: t.url, resultingItemURL: nil)
                }
                out.removed.append(t.url)
                out.bytes += t.size
            } catch {
                retry.append(t)
            }
        }
        guard !retry.isEmpty else { return out }

        // Items owned by root/other users: escalate.
        if permanently {
            adminRemove(retry.map(\.url))
        } else {
            _ = try? await NSWorkspace.shared.recycle(retry.map(\.url)) // Finder asks for an admin password when needed
        }
        for t in retry {
            if t.url.existsOnDisk {
                out.failed.append((t.url, "Permission denied"))
            } else {
                out.removed.append(t.url)
                out.bytes += t.size
            }
        }
        return out
    }

    @MainActor
    private static func adminRemove(_ urls: [URL]) {
        let safe = urls.filter(isSafe)
        guard !safe.isEmpty else { return }
        let args = safe.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        let cmd = "/bin/rm -rf -- " + args
        let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var err: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&err)
    }

    @MainActor
    static func emptyTrashViaFinder() -> Bool {
        var err: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&err)
        return err == nil
    }
}
