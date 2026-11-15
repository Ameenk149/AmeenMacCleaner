import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var section: AppSection? = .overview

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $section)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            Group {
                switch section ?? .overview {
                case .overview: OverviewView(section: $section)
                case .explorer: ExplorerView()
                case .apps: AppsView()
                case .junk: JunkView()
                case .leftovers: LeftoversView()
                case .large: LargeFilesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .task { await state.initialLoad() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshDisk()
        }
        .overlay(alignment: .bottom) {
            if let toast = state.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                    .padding(.bottom, 72)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: state.toast)
        .confirmationDialog(
            state.pendingRemoval?.title ?? "",
            isPresented: Binding(get: { state.pendingRemoval != nil }, set: { if !$0 { state.pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: state.pendingRemoval
        ) { req in
            if !req.items.isEmpty {
                Button("Move to Trash") { state.perform(req, permanently: false) }
            }
            Button("Delete Permanently", role: .destructive) { state.perform(req, permanently: true) }
            Button("Cancel", role: .cancel) {}
        } message: { req in
            Text(confirmMessage(req))
        }
        .alert(
            "Some items couldn't be removed",
            isPresented: Binding(get: { state.failureReport != nil }, set: { if !$0 { state.failureReport = nil } }),
            presenting: state.failureReport
        ) { _ in
            if !state.hasFullDiskAccess {
                Button("Open Full Disk Access") { Permissions.openFullDiskAccessSettings() }
            }
            Button("OK", role: .cancel) {}
        } message: { report in
            Text(report + "\n\nThese are usually protected by macOS (System Integrity Protection) or need Full Disk Access.")
        }
    }

    private func confirmMessage(_ req: RemovalRequest) -> String {
        var s = "\(req.count) item\(req.count == 1 ? "" : "s") · \(req.totalSize.bytes)\n\n"
        if req.items.isEmpty {
            s += "This permanently deletes them and cannot be undone."
        } else {
            s += "Move to Trash lets you restore items later (space is freed when the Trash is emptied). Delete Permanently frees the space right away and cannot be undone."
            if !req.alwaysPermanent.isEmpty { s += "\n\nItems already in the Trash are always deleted permanently." }
        }
        if !req.quitBundleIDs.isEmpty { s += "\n\nRunning apps will be quit first." }
        return s
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var state
    @Binding var selection: AppSection?

    var body: some View {
        @Bindable var state = state
        List(selection: $selection) {
            Section {
                ForEach(AppSection.allCases) { s in
                    HStack(spacing: 10) {
                        IconTile(symbol: s.symbol, tint: s.tint, size: 24)
                        Text(s.title)
                        Spacer()
                        badge(for: s)
                    }
                    .padding(.vertical, 2)
                    .tag(s)
                }
            } header: {
                Text("Cleaner")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Ameen").font(.headline)
                    Text("Mac Cleaner").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Toggle(isOn: $state.showHidden) {
                    Label("Show hidden items", systemImage: state.showHidden ? "eye" : "eye.slash")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                HStack(spacing: 6) {
                    Circle()
                        .fill(state.hasFullDiskAccess ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(state.hasFullDiskAccess ? "Full Disk Access granted" : "Limited access")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !state.hasFullDiskAccess {
                        Button("Fix") { Permissions.openFullDiskAccessSettings() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private func badge(for s: AppSection) -> some View {
        let text: String? = switch s {
        case .overview: nil
        case .explorer: state.explorer.folders[Paths.home.path].flatMap { $0.loading ? nil : $0.total(includeHidden: true).bytes }
        case .apps: state.apps.isEmpty ? nil : "\(state.visibleApps.count)"
        case .junk: state.junkScanned && state.junkTotal > 0 ? state.junkTotal.bytes : nil
        case .leftovers: state.orphansScanned && state.orphanTotal > 0 ? state.orphanTotal.bytes : nil
        case .large: state.largeScanned ? "\(state.visibleLargeFiles.count)" : nil
        }
        if let text {
            Text(text)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
