import SwiftUI

struct ExplorerView: View {
    @Environment(AppState.self) private var state
    @State private var selection: Set<String> = []

    private static let palette: [Color] = [.blue, .purple, .pink, .orange, .yellow, .green, .teal, .indigo]

    private var explorer: ExplorerModel { state.explorer }

    var body: some View {
        let folder = explorer.currentFolder
        VStack(spacing: 0) {
            PageHeader(section: .explorer, subtitle: "Browse folders by size and drill down to see exactly what's using your space.") {
                rootMenu
                Button { explorer.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Measure this folder again")
            }
            breadcrumbs
            if let folder {
                content(folder)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { explorer.load(explorer.current) }
        .onChange(of: explorer.current) { _, _ in selection = [] }
    }

    // MARK: Header pieces

    private var rootMenu: some View {
        Menu {
            Button("Home") { explorer.setRoot(Paths.home) }
            Divider()
            ForEach(["Documents", "Downloads", "Desktop", "Pictures", "Movies", "Music", "Library"], id: \.self) { name in
                Button(name) { explorer.setRoot(Paths.inHome(name)) }
            }
            Divider()
            Button("Applications") { explorer.setRoot(URL(fileURLWithPath: "/Applications")) }
            Button("Choose Folder…") { chooseFolder() }
        } label: {
            Label("Start at", systemImage: "folder")
        }
        .fixedSize()
    }

    private var breadcrumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(explorer.stack.enumerated()), id: \.offset) { i, url in
                    if i > 0 {
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    let isLast = i == explorer.stack.count - 1
                    Button {
                        explorer.jump(to: i)
                    } label: {
                        HStack(spacing: 5) {
                            Image(nsImage: IconCache.icon(for: url)).resizable().frame(width: 16, height: 16)
                            Text(i == 0 ? url.tildePath : url.lastPathComponent)
                                .fontWeight(isLast ? .semibold : .regular)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isLast ? Color.purple.opacity(0.14) : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLast)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 10)
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ folder: ExplorerFolder) -> some View {
        if folder.unreadable {
            EmptyStateView(symbol: "lock.fill", tint: .gray, title: "Can't read this folder",
                           message: "macOS blocked access. Granting Full Disk Access usually fixes this.",
                           buttonTitle: "Open Full Disk Access") { Permissions.openFullDiskAccessSettings() }
        } else {
            let rows = sortedRows(folder)
            let total = folder.total(includeHidden: state.showHidden)
            let hidden = folder.entries.filter(\.isHidden)
            let hiddenSize = hidden.reduce(0) { $0 + (folder.size(of: $1) ?? 0) }

            summary(folder, rows: rows, total: total)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

            List(rows, selection: $selection) { e in
                ExplorerRow(entry: e, size: folder.size(of: e), total: total, color: color(for: e, in: rows))
                    .tag(e.id)
            }
            .listStyle(.inset)
            .contextMenu(forSelectionType: String.self) { ids in
                if ids.count == 1, let e = rows.first(where: { ids.contains($0.id) }), e.isFolder {
                    Button("Open") { explorer.open(e.url) }
                }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(ids.map { URL(fileURLWithPath: $0) }) }
                Divider()
                Button("Remove…", role: .destructive) { requestRemoval(ids, folder: folder) }
            } primaryAction: { ids in
                guard ids.count == 1, let e = rows.first(where: { ids.contains($0.id) }) else { return }
                if e.isFolder { explorer.open(e.url) } else { e.url.revealInFinder() }
            }
            .overlay {
                if rows.isEmpty && !folder.loading {
                    ContentUnavailableView("Empty folder", systemImage: "folder",
                                           description: Text(hidden.isEmpty ? "Nothing in here." : "Only hidden items in here."))
                }
            }

            let selectedSize = rows.filter { selection.contains($0.id) }.reduce(0) { $0 + (folder.size(of: $1) ?? 0) }
            ActionBar {
                if !state.showHidden && !hidden.isEmpty {
                    Button {
                        state.showHidden = true
                    } label: {
                        Label("\(hidden.count) hidden · \(hiddenSize.bytes)", systemImage: "eye.slash")
                    }
                    .buttonStyle(.borderless)
                    .help("Show hidden items such as ~/Library and dot-folders")
                } else {
                    Text("Double-click a folder to open it").font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                if !selection.isEmpty {
                    Text("\(selection.count) selected · \(selectedSize.bytes)").foregroundStyle(.secondary).monospacedDigit()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(selection.map { URL(fileURLWithPath: $0) })
                    }
                }
                Button(role: .destructive) {
                    requestRemoval(selection, folder: folder)
                } label: {
                    Label("Remove", systemImage: "trash").frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.large)
                .disabled(selection.isEmpty)
            }
        }
    }

    private func summary(_ folder: ExplorerFolder, rows: [ExplorerEntry], total: Int64) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(total.bytes)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("in \(rows.count) items")
                    .foregroundStyle(.secondary)
                Spacer()
                if folder.loading {
                    ProgressView().controlSize(.small)
                    Text(folder.entries.isEmpty ? "Reading folder…" : "Measuring \(folder.folderCount - folder.pendingCount) of \(folder.folderCount) folders…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            proportionBar(folder, rows: rows, total: total)
                .frame(height: 14)
        }
        .padding(16)
        .card()
        .animation(.easeOut(duration: 0.4), value: total)
    }

    private func proportionBar(_ folder: ExplorerFolder, rows: [ExplorerEntry], total: Int64) -> some View {
        let top = rows.prefix(Self.palette.count).filter { (folder.size(of: $0) ?? 0) > 0 }
        return GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(top) { e in
                    let f = total > 0 ? Double(folder.size(of: e) ?? 0) / Double(total) : 0
                    if f > 0.004 {
                        Rectangle()
                            .fill(color(for: e, in: rows) ?? .gray)
                            .frame(width: max(2, geo.size.width * f))
                            .help("\(e.name) — \((folder.size(of: e) ?? 0).bytes)")
                    }
                }
                Spacer(minLength: 0)
            }
            .background(Color.primary.opacity(0.07))
            .clipShape(Capsule())
        }
    }

    // MARK: Helpers

    private func sortedRows(_ folder: ExplorerFolder) -> [ExplorerEntry] {
        folder.entries
            .filter { state.showHidden || !$0.isHidden }
            .sorted {
                let a = folder.size(of: $0), b = folder.size(of: $1)
                switch (a, b) {
                case let (x?, y?): return x != y ? x > y : $0.name < $1.name
                case (nil, nil): return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                case (nil, _): return false
                case (_, nil): return true
                }
            }
    }

    private func color(for e: ExplorerEntry, in rows: [ExplorerEntry]) -> Color? {
        guard let i = rows.prefix(Self.palette.count).firstIndex(where: { $0.id == e.id }) else { return nil }
        return Self.palette[i]
    }

    private func requestRemoval(_ ids: Set<String>, folder: ExplorerFolder) {
        let targets = folder.entries.filter { ids.contains($0.id) }
            .map { RemovalTarget(url: $0.url, size: folder.size(of: $0) ?? 0) }
        guard !targets.isEmpty else { return }
        state.pendingRemoval = RemovalRequest(title: "Remove \(targets.count) item\(targets.count == 1 ? "" : "s")?", items: targets)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = explorer.current
        panel.prompt = "Explore"
        if panel.runModal() == .OK, let url = panel.url { explorer.setRoot(url) }
    }
}

struct ExplorerRow: View {
    let entry: ExplorerEntry
    let size: Int64?
    let total: Int64
    let color: Color?

    private var fraction: Double { total > 0 ? Double(size ?? 0) / Double(total) : 0 }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color ?? Color.clear)
                .frame(width: 8, height: 8)
            Image(nsImage: IconCache.icon(for: entry.url))
                .resizable()
                .frame(width: 26, height: 26)
                .opacity(entry.isHidden ? 0.6 : 1)
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(entry.isHidden ? .secondary : .primary)
            Spacer(minLength: 8)
            if let size {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
                SizeBar(fraction: fraction, tint: color ?? .purple)
                    .frame(width: 110, height: 6)
                Text(size.bytes)
                    .font(.callout.monospacedDigit())
                    .frame(width: 80, alignment: .trailing)
            } else {
                ProgressView().controlSize(.mini)
                    .frame(width: 236, alignment: .trailing)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .opacity(entry.isFolder ? 1 : 0)
        }
        .padding(.vertical, 3)
    }
}
